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
    onActiveChanged: if (active && Date.now() - fetchedAt >= refreshSeconds * 1000) fetch()
    onApiKeyChanged: if (active) fetch()

    Timer {
        interval: tab.refreshSeconds * 1000
        repeat: true
        running: tab.active
        onTriggered: tab.fetch()
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
            }
        }
    }
}
