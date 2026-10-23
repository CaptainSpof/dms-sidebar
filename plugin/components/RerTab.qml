import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Widgets

// Next departures at one stop, from PRIM's real-time "prochains passages"
// (SIRI Lite stop-monitoring) — the same data and rules as the dafos
// dashboard's RER widget.
//
// PRIM allows 1000 requests a day per token, shared with that dashboard, so
// the tab fetches only while it is shown, at most every `refreshSeconds`, and
// recomputes the countdown locally in between.
//
// Direction is picked by destination: SIRI's DirectionRef is the same for both
// ways at some stops, so `excludeDestinations` drops the other side's termini.
Item {
    id: tab

    property var conf: ({})
    // True while this tab is on screen; fetching stops otherwise.
    property bool active: false

    readonly property string stopArea: String(conf.stopArea || "")
    readonly property var excludes: conf.excludeDestinations || []
    readonly property int limit: conf.limit || 6
    readonly property int walkMin: (conf.walk && conf.walk.min) || 7
    readonly property int walkMax: (conf.walk && conf.walk.max) || 8
    readonly property int margin: conf.margin !== undefined ? conf.margin : 3
    readonly property int refreshSeconds: Math.max(60, conf.refreshSeconds || 120)
    readonly property string keyFile: conf.keyFile || ""

    // Weather under the departures: [{name, latitude, longitude}], from
    // Open-Meteo (no key), refetched every 30 min while shown.
    readonly property var places: conf.weather || []
    property var weather: []        // [{name, temp, code, isDay, max, min, rain, hours: [{time, code, temp, rain, isDay}]}]
    property real weatherAt: 0

    property string apiKey: ""
    property var departures: []     // [{dest, note, quay, expected (ms), late (min), cancelled}]
    property real fetchedAt: 0
    property string errorText: ""
    property bool loading: false
    property real now: Date.now()

    FileView {
        path: tab.keyFile
        onLoaded: tab.apiKey = text().trim()
    }

    function fetch() {
        if (!apiKey || !stopArea || loading)
            return;
        loading = true;
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            loading = false;
            fetchedAt = Date.now();
            now = fetchedAt;
            if (xhr.status === 429) {
                errorText = "Quota PRIM du jour atteint (1000 requêtes). Les horaires reviennent demain.";
                return;
            }
            if (xhr.status !== 200) {
                errorText = "PRIM indisponible : " + (xhr.status || "pas de réponse");
                return;
            }
            try {
                parse(JSON.parse(xhr.responseText));
                errorText = "";
            } catch (e) {
                errorText = "Réponse PRIM illisible";
            }
        };
        xhr.open("GET", "https://prim.iledefrance-mobilites.fr/marketplace/stop-monitoring?MonitoringRef=" + encodeURIComponent("STIF:StopArea:SP:" + stopArea + ":"));
        xhr.setRequestHeader("apikey", apiKey);
        xhr.send();
    }

    function parse(json) {
        const visits = ((json.Siri.ServiceDelivery.StopMonitoringDelivery || [])[0] || {}).MonitoredStopVisit || [];
        const out = [];
        visits.forEach(v => {
            const j = v.MonitoredVehicleJourney || {};
            const call = j.MonitoredCall || {};
            const dest = ((j.DestinationName || [])[0] || {}).value || "";
            if (excludes.indexOf(dest) >= 0)
                return;
            const expected = Date.parse(call.ExpectedDepartureTime || call.AimedDepartureTime);
            const aimed = Date.parse(call.AimedDepartureTime || call.ExpectedDepartureTime);
            if (isNaN(expected))
                return;
            out.push({
                dest: dest,
                note: ((j.JourneyNote || [])[0] || {}).value || "",
                quay: (call.DeparturePlatformName || {}).value || "",
                expected: expected,
                late: Math.round((expected - aimed) / 60000),
                cancelled: call.DepartureStatus === "cancelled"
            });
        });
        out.sort((a, b) => a.expected - b.expected);
        departures = out;
    }

    function fetchWeather() {
        if (places.length === 0)
            return;
        const q = "latitude=" + places.map(p => p.latitude).join(",") + "&longitude=" + places.map(p => p.longitude).join(",") + "&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code,precipitation_probability,is_day,uv_index,wind_gusts_10m&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=Europe%2FParis&forecast_days=2";
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200)
                return;
            try {
                const json = JSON.parse(xhr.responseText);
                const list = Array.isArray(json) ? json : [json];
                weatherAt = Date.now();
                weather = list.map((w, i) => {
                    const h = w.hourly;
                    // Hourly times are local ("2026-10-23T15:00"): start at the current hour.
                    const start = Math.max(0, h.time.indexOf(w.current.time.slice(0, 13) + ":00"));
                    const hours = [];
                    for (let k = start + 1; k < Math.min(h.time.length, start + 7); k++)
                        hours.push({time: h.time[k].slice(11, 13) + "h", code: h.weather_code[k], temp: Math.round(h.temperature_2m[k]), rain: h.precipitation_probability[k], isDay: h.is_day[k] === 1, uv: h.uv_index[k] || 0, gust: Math.round(h.wind_gusts_10m[k] || 0)});
                    return {
                        name: places[i].name,
                        temp: Math.round(w.current.temperature_2m),
                        code: w.current.weather_code,
                        isDay: w.current.is_day === 1,
                        max: Math.round(w.daily.temperature_2m_max[0]),
                        min: Math.round(w.daily.temperature_2m_min[0]),
                        rain: w.daily.precipitation_probability_max[0],
                        hours: hours
                    };
                });
            } catch (e) {
                console.warn("dafSidebar: weather:", e);
            }
        };
        xhr.open("GET", "https://api.open-meteo.com/v1/forecast?" + q);
        xhr.send();
    }

    // What to take or wear for the next hours, over every place: [{icon, text}].
    // A condition seen at some places only names them ("à Paris").
    readonly property var advice: {
        if (weather.length === 0)
            return [];
        const isRain = c => (c >= 51 && c <= 67) || (c >= 80 && c <= 82) || c >= 95;
        const isSnow = c => (c >= 71 && c <= 77) || c === 85 || c === 86;
        const where = names => names.length === weather.length ? "" : " à " + names.join(" et ");
        const hit = test => weather.filter(w => test(w)).map(w => w.name);
        const out = [];

        const storm = hit(w => w.code >= 95 || w.hours.some(h => h.code >= 95));
        if (storm.length)
            out.push({icon: "thunderstorm", text: "Orage prévu" + where(storm) + " : mieux vaut éviter de sortir."});

        const rainNow = hit(w => isRain(w.code));
        if (rainNow.length)
            out.push({icon: "umbrella", text: "Il pleut" + where(rainNow) + " : prends un parapluie."});
        const soon = weather.filter(w => !isRain(w.code)).map(w => ({name: w.name, hour: w.hours.find(h => h.rain >= 50 || isRain(h.code))})).filter(x => !!x.hour);
        if (soon.length) {
            const first = soon.reduce((a, b) => a.hour.time <= b.hour.time ? a : b);
            out.push({icon: "umbrella", text: "Pluie probable vers " + first.hour.time + where(soon.map(x => x.name)) + " : prends un parapluie."});
        }

        const snow = hit(w => isSnow(w.code) || w.hours.some(h => isSnow(h.code)));
        if (snow.length)
            out.push({icon: "weather_snowy", text: "Neige prévue" + where(snow) + " : chaussures adaptées."});

        const uvMax = Math.round(Math.max(0, ...weather.map(w => Math.max(0, ...w.hours.map(h => h.uv)))));
        if (uvMax >= 6)
            out.push({icon: "sunny", text: "Soleil fort (UV " + uvMax + ")" + where(hit(w => w.hours.some(h => h.uv >= 6))) + " : lunettes et crème solaire."});
        else if (uvMax >= 3 && !rainNow.length && !soon.length)
            out.push({icon: "sunny", text: "Beau temps (UV " + uvMax + ") : lunettes de soleil conseillées."});

        const tMax = Math.max(...weather.map(w => Math.max(w.temp, ...w.hours.map(h => h.temp))));
        const tMin = Math.min(...weather.map(w => Math.min(w.temp, ...w.hours.map(h => h.temp))));
        if (tMax >= 28)
            out.push({icon: "thermostat", text: "Jusqu'à " + tMax + "° : habille-toi léger et prends de l'eau."});
        if (tMin <= 3)
            out.push({icon: "ac_unit", text: "Jusqu'à " + tMin + "° : couvre-toi bien (bonnet, gants)."});
        else if (tMin <= 10)
            out.push({icon: "checkroom", text: "Frais (" + tMin + "°) : prends une veste."});

        const gust = Math.max(...weather.map(w => Math.max(0, ...w.hours.map(h => h.gust))));
        if (gust >= 50)
            out.push({icon: "air", text: "Rafales jusqu'à " + gust + " km/h" + where(hit(w => w.hours.some(h => h.gust >= 50))) + " : le parapluie risque de souffrir."});

        if (out.length === 0)
            out.push({icon: "check_circle", text: "Rien de particulier à prévoir pour les prochaines heures."});
        return out;
    }

    // WMO weather code -> [French label, Material Symbols icon].
    function wmo(code, isDay) {
        if (code >= 95) return ["Orage", "thunderstorm"];
        if (code >= 85) return ["Averses de neige", "weather_snowy"];
        if (code >= 80) return ["Averses", "rainy"];
        if (code >= 71) return ["Neige", "weather_snowy"];
        if (code >= 61) return ["Pluie", "rainy"];
        if (code >= 51) return ["Bruine", "rainy_light"];
        if (code >= 45) return ["Brouillard", "foggy"];
        if (code === 3) return ["Couvert", "cloud"];
        if (code >= 1) return ["Éclaircies", isDay ? "partly_cloudy_day" : "partly_cloudy_night"];
        return [isDay ? "Ensoleillé" : "Dégagé", isDay ? "sunny" : "clear_night"];
    }

    // Upcoming departures, recomputed against `now` between fetches.
    readonly property var upcoming: departures.filter(d => d.expected - now >= 0).slice(0, limit)

    function minutesTo(d) {
        return Math.floor((d.expected - now) / 60000);
    }

    // ok: time to spare; hurry: leave now; missed: even the fastest walk is late.
    function stateOf(d) {
        if (d.cancelled)
            return "cancelled";
        const m = minutesTo(d);
        if (m < walkMin)
            return "missed";
        if (m - walkMax < margin)
            return "hurry";
        return "ok";
    }

    function stripe(state) {
        switch (state) {
        case "ok": return Theme.success;
        case "hurry": return Theme.warning;
        default: return Theme.error;
        }
    }

    function fmtTime(ms) {
        const d = new Date(ms);
        return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2);
    }

    // Fetch when shown if the data is older than the interval, then on the
    // interval while shown.
    onActiveChanged: {
        if (!active)
            return;
        if (Date.now() - fetchedAt >= refreshSeconds * 1000)
            fetch();
        if (Date.now() - weatherAt >= 30 * 60000)
            fetchWeather();
    }
    onApiKeyChanged: if (active) fetch()

    Timer {
        interval: tab.refreshSeconds * 1000
        repeat: true
        running: tab.active
        onTriggered: tab.fetch()
    }

    Timer {
        interval: 30 * 60000
        repeat: true
        running: tab.active
        onTriggered: tab.fetchWeather()
    }

    Timer {
        interval: 15000
        repeat: true
        running: tab.active
        onTriggered: tab.now = Date.now()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: tab.conf.title || "RER"
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Medium
                color: Theme.surfaceText
            }
            StyledText {
                visible: tab.fetchedAt > 0
                text: "maj " + tab.fmtTime(tab.fetchedAt)
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
            DankActionButton {
                iconName: "refresh"
                enabled: !tab.loading
                tooltipText: "Rafraîchir les horaires"
                onClicked: tab.fetch()
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: text !== ""
            wrapMode: Text.WordWrap
            color: Theme.error
            text: !tab.keyFile ? "Clé PRIM non configurée (keyFile)." : tab.errorText
        }

        StyledText {
            Layout.fillWidth: true
            visible: tab.errorText === "" && tab.fetchedAt > 0 && tab.upcoming.length === 0
            text: "Aucun départ annoncé."
            color: Theme.surfaceVariantText
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: parent.width
                spacing: Theme.spacingS

                Repeater {
                    model: tab.upcoming
                    delegate: StyledRect {
                        id: row
                        required property var modelData
                        readonly property var d: modelData
                        readonly property string departureState: tab.stateOf(d)
                        readonly property int mins: tab.minutesTo(d)
                        readonly property int leave: mins - tab.walkMax

                        Layout.fillWidth: true
                        implicitHeight: rowLayout.implicitHeight + Theme.spacingS * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        Rectangle {
                            width: 4
                            radius: 2
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: Theme.spacingXS
                            color: tab.stripe(row.departureState)
                        }

                        RowLayout {
                            id: rowLayout
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            spacing: Theme.spacingM

                            StyledText {
                                text: tab.fmtTime(row.d.expected)
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.d.dest
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.surfaceText
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: [row.d.note, row.d.quay ? "quai " + row.d.quay : ""].filter(s => s).join(" · ") + (row.d.late > 0 ? " · +" + row.d.late + " min" : "")
                                    elide: Text.ElideRight
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: row.d.late > 0 ? Theme.error : Theme.surfaceVariantText
                                }
                            }

                            ColumnLayout {
                                spacing: 0
                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    text: row.d.cancelled ? "Supprimé" : (row.mins <= 0 ? "à quai" : row.mins + " min")
                                    font.pixelSize: row.d.cancelled ? Theme.fontSizeMedium : Theme.fontSizeLarge
                                    font.weight: Font.Medium
                                    color: row.d.cancelled ? Theme.error : Theme.surfaceText
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    visible: !row.d.cancelled
                                    text: row.departureState === "missed" ? "trop tard" : (row.departureState === "hurry" ? "pars maintenant" : "pars dans " + row.leave + " min")
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: tab.stripe(row.departureState)
                                }
                            }
                        }
                    }
                }

                // ── advice: what to take for the next hours ──
                StyledRect {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacingM
                    visible: tab.advice.length > 0
                    implicitHeight: adviceCol.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.secondaryContainer

                    ColumnLayout {
                        id: adviceCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        Repeater {
                            model: tab.advice
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.spacingS
                                DankIcon {
                                    Layout.alignment: Qt.AlignTop
                                    name: modelData.icon
                                    size: 20
                                    color: Theme.onSecondaryContainer
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.text
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.onSecondaryContainer
                                }
                            }
                        }
                    }
                }

                // ── weather ──
                Repeater {
                    model: tab.weather
                    delegate: StyledRect {
                        id: place
                        required property var modelData
                        readonly property var w: modelData
                        Layout.fillWidth: true
                        Layout.topMargin: index === 0 ? Theme.spacingM : 0
                        required property int index
                        implicitHeight: placeCol.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        ColumnLayout {
                            id: placeCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingM
                                DankIcon {
                                    name: tab.wmo(place.w.code, place.w.isDay)[1]
                                    size: 32
                                    color: Theme.primary
                                }
                                StyledText {
                                    text: place.w.temp + "°"
                                    font.pixelSize: Theme.fontSizeLarge * 1.4
                                    font.weight: Font.Medium
                                    color: Theme.surfaceText
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: place.w.name
                                        elide: Text.ElideRight
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: Theme.surfaceText
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: tab.wmo(place.w.code, place.w.isDay)[0]
                                        elide: Text.ElideRight
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                }
                                ColumnLayout {
                                    spacing: 0
                                    StyledText {
                                        Layout.alignment: Qt.AlignRight
                                        text: place.w.max + "° / " + place.w.min + "°"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                    }
                                    StyledText {
                                        Layout.alignment: Qt.AlignRight
                                        text: "pluie " + place.w.rain + " %"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: place.w.rain >= 50 ? Theme.primary : Theme.surfaceVariantText
                                    }
                                }
                            }

                            // Next hours.
                            Row {
                                id: hoursRow
                                Layout.fillWidth: true
                                Repeater {
                                    model: place.w.hours
                                    delegate: Column {
                                        required property var modelData
                                        width: hoursRow.width / Math.max(1, place.w.hours.length)
                                        spacing: 2
                                        StyledText {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.time
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                        DankIcon {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            name: tab.wmo(modelData.code, modelData.isDay)[1]
                                            size: 20
                                            color: Theme.surfaceText
                                        }
                                        StyledText {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.temp + "°"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceText
                                        }
                                        StyledText {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: modelData.rain >= 20 ? modelData.rain + "%" : " "
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.primary
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
