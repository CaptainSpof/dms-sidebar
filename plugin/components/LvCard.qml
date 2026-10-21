import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// One lovelace card. Containers load nested LvCard files through a Loader
// (a QML type cannot instantiate itself directly); leaves are the inline
// components below. `dash` is the LovelaceTab context.
Item {
    id: root

    property var dash
    property var card

    readonly property string kind: {
        if (!card)
            return "hidden";
        switch (card.type) {
        case "vertical-stack": return "vstack";
        case "horizontal-stack": return "hstack";
        case "grid": return "grid";
        case "conditional": return "conditional";
        case "heading": return "separator";
        case "tile":
        case "entity":
        case "button": return card.entity ? "tile" : "fallback";
        case "entities": return "entities";
        case "custom:paper-buttons-row":
            const nav = card.base_config && card.base_config.tap_action;
            return nav && nav.action === "navigate" && String(nav.navigation_path).charAt(0) === "#" ? "room" : "paper";
        case "custom:bubble-card":
            switch (card.card_type) {
            case "separator": return "separator";
            case "button":
            case "media-player": return card.entity ? "tile" : "fallback";
            case "sub-buttons": return "subButtons";
            case "pop-up": return "hidden";
            default: return "fallback";
            }
        default: return "fallback";
        }
    }

    readonly property bool shown: !!dash && kind !== "hidden" && !(kind === "fallback" && dash.hideUnsupported) && dash.conditionsMet(card.visibility) && (kind !== "conditional" || dash.conditionsMet(card.conditions))

    visible: shown
    implicitHeight: shown && loader.item ? loader.item.implicitHeight : 0
    implicitWidth: loader.item ? loader.item.implicitWidth : 0

    Loader {
        id: loader
        width: parent.width
        active: root.shown
        sourceComponent: {
            switch (root.kind) {
            case "vstack":
            case "conditional": return vstack;
            case "hstack": return hstack;
            case "grid": return grid;
            case "separator": return separator;
            case "tile": return tile;
            case "subButtons": return subButtonsRow;
            case "room": return room;
            case "paper": return paperRow;
            case "entities": return entities;
            default: return fallback;
            }
        }
    }

    // A nested card, created with its properties already set.
    component Nested: Loader {
        property var child
        property var dash
        Component.onCompleted: setSource("LvCard.qml", {
            dash: dash,
            card: child
        })
    }

    // ── containers ────────────────────────────────────────────────────────

    Component {
        id: vstack
        ColumnLayout {
            spacing: Theme.spacingS
            Repeater {
                model: root.kind === "conditional" ? [root.card.card] : (root.card.cards || [])
                delegate: Nested {
                    dash: root.dash
                    required property var modelData
                    Layout.fillWidth: true
                    child: modelData
                }
            }
        }
    }

    Component {
        id: hstack
        RowLayout {
            spacing: Theme.spacingS
            Repeater {
                model: root.card.cards || []
                delegate: Nested {
                    dash: root.dash
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    child: modelData
                }
            }
        }
    }

    Component {
        id: grid
        GridLayout {
            id: g
            readonly property int cols: Math.max(1, Number(root.card.columns) || 2)
            columns: cols
            columnSpacing: Theme.spacingS
            rowSpacing: Theme.spacingS
            Repeater {
                model: root.card.cards || []
                delegate: Nested {
                    dash: root.dash
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: (g.width - g.columnSpacing * (g.cols - 1)) / g.cols
                    Layout.alignment: Qt.AlignTop
                    child: modelData
                }
            }
        }
    }

    // ── shared pieces ─────────────────────────────────────────────────────

    component Mdi: Text {
        property var dash
        property string icon: ""
        property real size: 20
        text: dash.glyph(icon)
        font.family: dash.mdiFamily
        font.pixelSize: size
        color: Theme.surfaceVariantText
        visible: text !== ""
    }

    // Icon + optional text, clickable. Used for sub-buttons and paper buttons.
    component Chip: StyledRect {
        id: chip
        property var dash
        property string icon: ""
        property string label: ""
        property bool active: false
        property bool filled: true
        signal tapped

        implicitHeight: 32
        implicitWidth: chipRow.implicitWidth + Theme.spacingS * 2
        radius: height / 2
        color: !filled ? "transparent" : (active ? Theme.secondaryContainer : Theme.surfaceContainerHighest)

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Theme.spacingXS
            Mdi {
                dash: chip.dash
                anchors.verticalCenter: parent.verticalCenter
                icon: chip.icon
                size: 18
                color: chip.active ? Theme.onSecondaryContainer : Theme.surfaceVariantText
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.label !== ""
                text: chip.label
                font.pixelSize: Theme.fontSizeSmall
                color: chip.active ? Theme.onSecondaryContainer : Theme.surfaceText
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.tapped()
        }
    }

    // A bubble-card sub-button.
    component SubButton: Chip {
        property var sb
        readonly property string ent: sb.entity || ""
        readonly property var st: dash.stateObj(ent)
        icon: dash.plain(sb.icon) || (ent ? dash.entityIcon(ent) : "")
        label: {
            const parts = [];
            if (sb.show_name && dash.plain(sb.name))
                parts.push(dash.plain(sb.name));
            if (sb.show_state && ent)
                parts.push(dash.stateText(ent, sb.attribute));
            return parts.join(" · ");
        }
        active: ent !== "" && dash.isActive(ent)
        filled: sb.show_background !== false
        onTapped: dash.runAction(sb.tap_action || {action: "more-info"}, ent)
    }

    // ── leaves ────────────────────────────────────────────────────────────

    Component {
        id: separator
        RowLayout {
            spacing: Theme.spacingS
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacingS
                text: root.dash.plain(root.card.name || root.card.heading)
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.primary
            }
            Repeater {
                model: root.dash.subButtons(root.card, "main")
                delegate: SubButton {
                    dash: root.dash
                    required property var modelData
                    sb: modelData
                }
            }
        }
    }

    Component {
        id: subButtonsRow
        Flow {
            spacing: Theme.spacingS
            Repeater {
                model: root.dash.subButtons(root.card, "main").concat(root.dash.subButtons(root.card, "bottom"))
                delegate: SubButton {
                    dash: root.dash
                    required property var modelData
                    sb: modelData
                    label: root.dash.plain(modelData.name) || (modelData.entity ? root.dash.stateText(modelData.entity) : "")
                }
            }
        }
    }

    // Bubble-card button / media-player, and HA's own tile/entity/button.
    Component {
        id: tile
        StyledRect {
            id: t
            readonly property string ent: root.card.entity
            readonly property var st: root.dash.stateObj(ent)
            readonly property string domain: ent.split(".")[0]
            readonly property string btype: root.card.button_type || (root.card.card_type === "media-player" ? "state" : (root.card.type === "custom:bubble-card" ? "switch" : "state"))
            readonly property bool active: root.dash.isActive(ent)
            readonly property bool unavailable: !st || st.state === "unavailable"
            readonly property bool showState: btype === "state" || btype === "switch" || btype === "slider" || root.card.show_state === true || root.card.type !== "custom:bubble-card"
            readonly property var tapAction: (root.card.button_action && root.card.button_action.tap_action) || (root.card.type === "custom:bubble-card" ? null : root.card.tap_action) || (btype === "switch" ? {action: "toggle"} : {action: "more-info"})

            implicitHeight: col.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: active ? Theme.secondaryContainer : Theme.surfaceContainerHigh
            opacity: unavailable ? 0.5 : 1

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dash.runAction(t.tapAction, t.ent)
            }

            ColumnLayout {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Theme.spacingS
                spacing: Theme.spacingXS

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS

                    // The icon has its own action (more-info by default).
                    StyledRect {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: 18
                        color: t.active ? Theme.primary : Theme.surfaceContainerHighest
                        Mdi {
                            dash: root.dash
                            anchors.centerIn: parent
                            icon: root.dash.plain(root.card.icon) || root.dash.entityIcon(t.ent)
                            size: 20
                            color: t.active ? Theme.onPrimary : Theme.surfaceVariantText
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dash.runAction(root.card.type === "custom:bubble-card" ? (root.card.tap_action || {action: "more-info"}) : t.tapAction, t.ent)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: root.dash.plain(root.card.name) || root.dash.friendlyName(t.ent)
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: t.active ? Theme.onSecondaryContainer : Theme.surfaceText
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: t.showState
                            text: root.dash.stateText(t.ent, root.card.attribute)
                            elide: Text.ElideRight
                            font.pixelSize: Theme.fontSizeSmall
                            color: t.active ? Theme.onSecondaryContainer : Theme.surfaceVariantText
                        }
                    }

                    Repeater {
                        model: root.dash.subButtons(root.card, "main")
                        delegate: SubButton {
                            dash: root.dash
                            required property var modelData
                            sb: modelData
                        }
                    }

                    // Media player: play / pause.
                    DankActionButton {
                        visible: t.domain === "media_player"
                        iconName: t.st && t.st.state === "playing" ? "pause" : "play_arrow"
                        onClicked: root.dash.ha.callService("media_player", "media_play_pause", {}, t.ent)
                    }
                }

                DankSlider {
                    Layout.fillWidth: true
                    visible: t.btype === "slider" && !t.unavailable
                    readonly property var a: t.st ? t.st.attributes : ({})
                    minimum: t.domain === "input_number" || t.domain === "number" ? Number(a.min) || 0 : 0
                    maximum: t.domain === "input_number" || t.domain === "number" ? Number(a.max) || 100 : 100
                    showValue: true
                    value: {
                        if (!t.st)
                            return 0;
                        switch (t.domain) {
                        case "light": return t.st.state === "on" ? Math.round((a.brightness || 0) / 255 * 100) : 0;
                        case "cover": return a.current_position || 0;
                        case "media_player": return Math.round((a.volume_level || 0) * 100);
                        case "fan": return a.percentage || 0;
                        default: return Number(t.st.state) || 0;
                        }
                    }
                    onSliderDragFinished: v => {
                        const ha = root.dash.ha;
                        switch (t.domain) {
                        case "light": ha.callService("light", "turn_on", {brightness_pct: v}, t.ent); break;
                        case "cover": ha.callService("cover", "set_cover_position", {position: v}, t.ent); break;
                        case "media_player": ha.callService("media_player", "volume_set", {volume_level: v / 100}, t.ent); break;
                        case "fan": ha.callService("fan", "set_percentage", {percentage: v}, t.ent); break;
                        default: ha.callService(t.domain, "set_value", {value: v}, t.ent); break;
                        }
                    }
                }
            }
        }
    }

    // paper-buttons-row whose base action opens a pop-up: the dashboard's room
    // tiles. The row is laid out with CSS in HA; here it is read for meaning —
    // the room name, its lights toggle and its state readouts.
    Component {
        id: room
        StyledRect {
            id: r
            readonly property var buttons: root.card.buttons || []
            readonly property var base: root.card.base_config || {}
            readonly property string title: {
                const b = buttons.find(b => (b.layout === "name") && typeof b.name === "string" && b.name.trim() !== "");
                return b ? b.name : "";
            }
            readonly property var lightButton: buttons.find(b => b.entity && b.icon && b.tap_action && b.tap_action.action === "toggle") || null
            readonly property bool active: !!lightButton && root.dash.isActive(lightButton.entity)
            readonly property var readouts: buttons.filter(b => b.entity && b.layout === "state")
            readonly property var presence: buttons.find(b => b.entity && b.state_icons && b.layout === "icon") || null

            implicitHeight: rcol.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: active ? Theme.secondaryContainer : Theme.surfaceContainerHigh

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dash.runAction(r.base.tap_action)
            }

            ColumnLayout {
                id: rcol
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS

                RowLayout {
                    Layout.fillWidth: true
                    StyledRect {
                        visible: !!r.lightButton
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: 20
                        color: r.active ? Theme.primary : Theme.surfaceContainerHighest
                        Mdi {
                            dash: root.dash
                            anchors.centerIn: parent
                            icon: r.lightButton ? r.lightButton.icon : ""
                            size: 22
                            color: r.active ? Theme.onPrimary : Theme.surfaceVariantText
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dash.runAction(r.lightButton.tap_action, r.lightButton.entity)
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Mdi {
                        dash: root.dash
                        visible: !!r.presence && root.dash.isActive(r.presence.entity)
                        icon: r.presence ? (r.presence.state_icons.on || r.presence.icon) : ""
                        size: 18
                        color: Theme.primary
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: r.title
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: r.active ? Theme.onSecondaryContainer : Theme.surfaceText
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: r.readouts.map(b => {
                        const v = root.dash.stateText(b.entity, b.state && b.state.attribute);
                        return v === "" ? "" : v + ((b.state && b.state.postfix) || "");
                    }).filter(s => s !== "").join(" · ")
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall
                    color: r.active ? Theme.onSecondaryContainer : Theme.surfaceVariantText
                }
            }
        }
    }

    // Any other paper-buttons-row: one chip per button.
    Component {
        id: paperRow
        Flow {
            spacing: Theme.spacingS
            Repeater {
                model: (root.card.buttons || []).map(b => Object.assign({}, root.card.base_config || {}, b))
                delegate: Chip {
                    dash: root.dash
                    required property var modelData
                    readonly property var b: modelData
                    readonly property string ent: b.entity || ""
                    readonly property var st: root.dash.stateObj(ent)
                    readonly property string layout: String(b.layout || "icon|name")
                    visible: root.dash.conditionsMet(b.visibility)
                    icon: {
                        if (st && b.state_icons && b.state_icons[st.state])
                            return b.state_icons[st.state];
                        return b.icon || (ent ? root.dash.entityIcon(ent) : "");
                    }
                    label: {
                        const parts = [];
                        if (layout.indexOf("name") >= 0 && b.name !== false) {
                            const n = typeof b.name === "string" ? b.name.trim() : (ent ? root.dash.friendlyName(ent) : "");
                            if (n)
                                parts.push(n);
                        }
                        if (layout.indexOf("state") >= 0 && ent) {
                            const raw = st ? (b.state && b.state.attribute ? st.attributes[b.state.attribute] : st.state) : "";
                            const txt = b.state_text && b.state_text[raw] !== undefined ? b.state_text[raw] : root.dash.stateText(ent, b.state && b.state.attribute);
                            parts.push(txt + ((b.state && b.state.postfix) || ""));
                        }
                        return parts.join(" ");
                    }
                    active: ent !== "" && root.dash.isActive(ent)
                    onTapped: root.dash.runAction(b.tap_action || {action: "toggle"}, ent)
                }
            }
        }
    }

    Component {
        id: entities
        ColumnLayout {
            spacing: Theme.spacingS
            StyledText {
                visible: !!root.card.title
                text: root.dash.plain(root.card.title)
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.primary
            }
            Repeater {
                model: (root.card.entities || []).map(e => typeof e === "string" ? e : e.entity).filter(e => !!e)
                delegate: EntityRow {
                    required property string modelData
                    Layout.fillWidth: true
                    ha: root.dash.ha
                    entityId: modelData
                }
            }
        }
    }

    Component {
        id: fallback
        StyledRect {
            implicitHeight: 44
            radius: Theme.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: Theme.outlineVariant
            StyledText {
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: (root.card.type || "?").replace(/^custom:/, "") + (root.card.card_type ? " · " + root.card.card_type : "") + " — non pris en charge"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }
}
