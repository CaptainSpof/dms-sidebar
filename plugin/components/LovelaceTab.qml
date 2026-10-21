import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Widgets

// Renders a Home Assistant dashboard (lovelace/config) natively. Only the
// cards this dashboard is built from are understood — bubble-card buttons,
// separators, sub-buttons and pop-ups, paper-buttons-row, stacks, grids and
// conditionals; anything else is drawn as a fallback box naming its type.
//
// Bubble-card pop-ups become pages: `navigate` to "#hash" pushes one, and a
// `more-info` action pushes an entity page built from EntityRow. This object
// is also the context (`dash`) every card reads helpers from.
Item {
    id: dash

    required property var ha
    property string dashboard: ""
    // Pop-up hash this tab opens on ("#popup_kitchen"); its root then is that page.
    property string startPage: ""
    property string mdiFontPath: ""
    property string mdiMapPath: ""

    property var config: null
    property var popups: ({})       // "#hash" -> pop-up card
    property var rootCards: []      // first view's cards, pop-ups taken out
    property var pageStack: []      // [{kind: "popup", hash} | {kind: "entity", entity}]
    property var mdi: ({})
    readonly property var page: pageStack.length > 0 ? pageStack[pageStack.length - 1] : null

    // ── loading ───────────────────────────────────────────────────────────

    function load() {
        if (!ha.ready)
            return;
        ha.fetchLovelace(dashboard, cfg => {
            config = cfg;
            index();
        });
    }

    function index() {
        const pops = {};
        const roots = [];
        const view = config && config.views && config.views[0];
        const collect = card => {
            if (card && card.type === "custom:bubble-card" && card.card_type === "pop-up") {
                pops[card.hash] = card;
                return true;
            }
            return false;
        };
        if (view) {
            (view.sections || []).forEach(sec => (sec.cards || []).forEach(c => {
                if (!collect(c))
                    roots.push(c);
            }));
            (view.cards || []).forEach(c => {
                if (!collect(c))
                    roots.push(c);
            });
        }
        popups = pops;
        rootCards = roots;
        pageStack = pageStack.filter(p => p.kind !== "popup" || pops[p.hash]);
        if (startPage && pageStack.length === 0 && pops[startPage])
            pageStack = [{kind: "popup", hash: startPage, pinned: true}];
    }

    Connections {
        target: dash.ha
        function onReadyChanged() {
            dash.load();
        }
        function onLovelaceUpdated(urlPath) {
            if (urlPath === dash.dashboard)
                dash.load();
        }
    }
    onDashboardChanged: load()
    Component.onCompleted: load()

    FontLoader {
        id: mdiFont
        source: dash.mdiFontPath ? "file://" + dash.mdiFontPath : ""
    }

    FileView {
        path: dash.mdiMapPath
        onLoaded: {
            try {
                dash.mdi = JSON.parse(text());
            } catch (e) {
                console.warn("dafSidebar: invalid MDI map:", e);
            }
        }
    }

    // ── helpers used by the cards ─────────────────────────────────────────

    readonly property string mdiFamily: mdiFont.status === FontLoader.Ready ? mdiFont.name : ""

    // Card strings may be JS (`${…}`) or Jinja (`{{ … }}`) templates, which are
    // not evaluated here: treat them as absent.
    function plain(s) {
        if (typeof s !== "string" || s.indexOf("${") >= 0 || s.indexOf("{{") >= 0)
            return "";
        return s;
    }

    function stateObj(entityId) {
        return entityId ? ha.states[entityId] : undefined;
    }

    function glyph(icon) {
        const name = plain(icon).replace(/^mdi:/, "");
        const cp = mdi[name];
        return cp ? String.fromCodePoint(cp) : "";
    }

    function isActive(entityId) {
        const s = stateObj(entityId);
        if (!s)
            return false;
        return ["on", "open", "opening", "playing", "heat", "cool", "heat_cool", "auto", "home", "unlocked", "cleaning"].indexOf(s.state) >= 0;
    }

    function entityIcon(entityId) {
        const s = stateObj(entityId);
        if (s && s.attributes.icon)
            return s.attributes.icon;
        const on = isActive(entityId);
        const dc = s ? s.attributes.device_class : "";
        switch ((entityId || "").split(".")[0]) {
        case "light": return on ? "mdi:lightbulb" : "mdi:lightbulb-outline";
        case "switch": return on ? "mdi:toggle-switch-variant" : "mdi:toggle-switch-variant-off";
        case "input_boolean": return on ? "mdi:toggle-switch" : "mdi:toggle-switch-off";
        case "climate": return "mdi:thermostat";
        case "cover": return on ? "mdi:window-shutter-open" : "mdi:window-shutter";
        case "fan": return "mdi:fan";
        case "lock": return on ? "mdi:lock-open-variant" : "mdi:lock";
        case "media_player": return "mdi:speaker";
        case "person": return "mdi:account";
        case "scene": return "mdi:palette";
        case "script": return "mdi:script-text";
        case "vacuum": return "mdi:robot-vacuum";
        case "binary_sensor":
            if (dc === "door") return on ? "mdi:door-open" : "mdi:door-closed";
            if (dc === "window") return on ? "mdi:window-open" : "mdi:window-closed";
            if (dc === "motion" || dc === "occupancy" || dc === "presence") return on ? "mdi:motion-sensor" : "mdi:motion-sensor-off";
            return on ? "mdi:checkbox-marked-circle" : "mdi:checkbox-blank-circle-outline";
        case "sensor":
            if (dc === "temperature") return "mdi:thermometer";
            if (dc === "humidity") return "mdi:water-percent";
            if (dc === "power" || dc === "energy") return "mdi:flash";
            if (dc === "battery") return "mdi:battery";
            return "mdi:eye";
        default: return "mdi:eye";
        }
    }

    readonly property var stateLabels: ({
        "on": "Allumé",
        "off": "Éteint",
        "open": "Ouvert",
        "closed": "Fermé",
        "opening": "Ouverture",
        "closing": "Fermeture",
        "playing": "Lecture",
        "paused": "Pause",
        "idle": "Inactif",
        "home": "À la maison",
        "not_home": "Absent",
        "locked": "Verrouillé",
        "unlocked": "Déverrouillé",
        "heat": "Chauffe",
        "cool": "Clim",
        "auto": "Auto",
        "unavailable": "Indisponible",
        "unknown": "Inconnu"
    })

    function stateText(entityId, attribute) {
        const s = stateObj(entityId);
        if (!s)
            return "";
        if (attribute) {
            const v = s.attributes[attribute];
            return v === undefined || v === null ? "" : String(v);
        }
        const domain = entityId.split(".")[0];
        if (domain === "light" && s.state === "on" && s.attributes.brightness)
            return Math.round(s.attributes.brightness / 255 * 100) + " %";
        if (domain === "climate") {
            const cur = s.attributes.current_temperature;
            const tgt = s.attributes.temperature;
            return (cur !== undefined ? cur + "°" : "") + (tgt !== undefined && tgt !== null ? " → " + tgt + "°" : "");
        }
        const unit = s.attributes.unit_of_measurement;
        if (unit)
            return s.state + " " + unit;
        return stateLabels[s.state] || s.state;
    }

    function friendlyName(entityId) {
        const s = stateObj(entityId);
        return s ? (s.attributes.friendly_name || entityId) : (entityId || "");
    }

    // HA card `conditions` / `visibility`. Screen and user conditions are
    // always true here.
    function conditionsMet(conditions) {
        if (!conditions || conditions.length === 0)
            return true;
        return conditions.every(c => conditionMet(c));
    }

    function conditionMet(c) {
        const kind = c.condition || (c.entity ? "state" : "");
        const s = stateObj(c.entity);
        const st = s ? s.state : "unavailable";
        const asList = v => Array.isArray(v) ? v.map(String) : [String(v)];
        switch (kind) {
        case "state":
            if (c.state !== undefined && asList(c.state).indexOf(st) < 0)
                return false;
            if (c.state_not !== undefined && asList(c.state_not).indexOf(st) >= 0)
                return false;
            return true;
        case "numeric_state":
            const n = Number(st);
            if (isNaN(n))
                return false;
            if (c.above !== undefined && !(n > Number(c.above)))
                return false;
            if (c.below !== undefined && !(n < Number(c.below)))
                return false;
            return true;
        case "or":
            return (c.conditions || []).some(x => conditionMet(x));
        case "and":
            return (c.conditions || []).every(x => conditionMet(x));
        case "not":
            return !(c.conditions || []).some(x => conditionMet(x));
        default:
            return true;
        }
    }

    // Normalise bubble-card `sub_button`: an array (older) or {main, bottom}.
    function subButtons(card, slot) {
        const sb = card && card.sub_button;
        if (!sb)
            return [];
        if (Array.isArray(sb))
            return slot === "main" ? sb : [];
        const list = sb[slot] || [];
        // Groups ({group: [...]}) are flattened.
        const out = [];
        list.forEach(b => b && b.group ? b.group.forEach(g => out.push(g)) : out.push(b));
        return out.filter(b => b && conditionsMet(b.visibility));
    }

    function runAction(action, entityId) {
        const a = action || {};
        const target = a.entity || entityId;
        switch (a.action) {
        case "toggle":
            if (target)
                ha.callService("homeassistant", "toggle", {}, target);
            break;
        case "more-info":
            if (target)
                push({kind: "entity", entity: target});
            break;
        case "navigate":
            if (a.navigation_path && a.navigation_path.charAt(0) === "#" && popups[a.navigation_path])
                push({kind: "popup", hash: a.navigation_path});
            break;
        case "call-service":
        case "perform-action":
            const svc = (a.perform_action || a.service || "").split(".");
            if (svc.length === 2) {
                const data = Object.assign({}, a.data || a.service_data || {});
                const tgt = a.target && a.target.entity_id ? a.target.entity_id : (data.entity_id || null);
                delete data.entity_id;
                ha.callService(svc[0], svc[1], data, tgt);
            }
            break;
        }
    }

    function push(p) {
        pageStack = pageStack.concat([p]);
    }

    // A pinned start page is the floor of the stack.
    readonly property int floor: pageStack.length > 0 && pageStack[0].pinned ? 1 : 0

    function back() {
        if (pageStack.length > floor)
            pageStack = pageStack.slice(0, -1);
    }

    function home() {
        pageStack = pageStack.slice(0, floor);
    }

    readonly property string pageTitle: {
        if (!page)
            return config && config.views && config.views[0] ? (config.views[0].title || "") : "";
        if (page.kind === "popup")
            return plain(popups[page.hash] && popups[page.hash].name) || page.hash;
        return friendlyName(page.entity);
    }

    readonly property var pageCards: {
        if (!page)
            return rootCards;
        if (page.kind === "popup") {
            const p = popups[page.hash];
            return p ? (p.cards || []) : [];
        }
        return [];
    }

    // ── layout ────────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingXS

            DankActionButton {
                visible: dash.pageStack.length > dash.floor
                iconName: "arrow_back"
                onClicked: dash.back()
            }
            StyledText {
                Layout.fillWidth: true
                text: dash.pageTitle
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Medium
                color: Theme.surfaceText
            }
            DankActionButton {
                visible: dash.pageStack.length > dash.floor + 1
                iconName: "home"
                onClicked: dash.home()
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !dash.config
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            color: Theme.surfaceVariantText
            text: dash.ha.phase === "error" ? dash.ha.errorText : (dash.ha.ready ? "Chargement du dashboard « " + dash.dashboard + " »…" : "Connexion à Home Assistant…")
        }

        ScrollView {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !!dash.config
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: scroller.availableWidth
                spacing: Theme.spacingM

                // Entity page: the same controls as the area dashboard.
                EntityRow {
                    Layout.fillWidth: true
                    visible: !!dash.page && dash.page.kind === "entity"
                    ha: dash.ha
                    entityId: dash.page && dash.page.kind === "entity" ? dash.page.entity : ""
                }

                Repeater {
                    model: dash.pageCards
                    delegate: Loader {
                        required property var modelData
                        Layout.fillWidth: true
                        Component.onCompleted: setSource("LvCard.qml", {
                            dash: dash,
                            card: modelData
                        })
                    }
                }
            }
        }
    }
}
