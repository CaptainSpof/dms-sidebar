import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// One entity, controlled according to its domain. Reads from `ha.states` and
// writes through `ha.callService`; it keeps no state of its own.
Item {
    id: row

    required property var ha
    required property string entityId
    // Drop the "Area · " prefix of a friendly name (used when grouped by area).
    property bool shortNames: false

    readonly property var st: ha.states[entityId]
    readonly property string domain: entityId.split(".")[0]
    readonly property string state: st ? st.state : "unavailable"
    readonly property var attrs: st ? st.attributes : ({})
    readonly property bool unavailable: state === "unavailable" || state === "unknown"
    readonly property bool isOn: state === "on" || state === "heat" || state === "auto" || state === "open"
    readonly property bool toggleable: ["light", "switch", "input_boolean", "fan", "automation"].indexOf(domain) >= 0
    readonly property bool dimmable: domain === "light" && isOn && attrs.brightness !== undefined && attrs.brightness !== null

    readonly property string label: {
        let n = attrs.friendly_name || entityId;
        if (shortNames)
            n = n.replace(/^.*? · /, "");
        return n;
    }

    readonly property string iconName: {
        switch (domain) {
        case "light": return "lightbulb";
        case "switch": return "power";
        case "climate": return "thermostat";
        case "cover": return "blinds";
        case "sensor": return "sensors";
        case "binary_sensor": return "sensors";
        case "scene": return "palette";
        case "script": return "play_circle";
        case "fan": return "mode_fan";
        case "media_player": return "speaker";
        default: return "circle";
        }
    }

    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth
    opacity: unavailable ? 0.45 : 1

    function call(service, data) {
        ha.callService(domain, service, data || {}, entityId);
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacingXS

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            DankIcon {
                name: row.iconName
                size: 20
                filled: row.isOn
                color: row.isOn ? Theme.primary : Theme.surfaceVariantText
            }

            StyledText {
                Layout.fillWidth: true
                text: row.label
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
            }

            // Toggleable: light, switch, ...
            DankToggle {
                visible: row.toggleable
                enabled: !row.unavailable
                hideText: true
                checked: row.isOn
                onToggled: on => row.ha.callService("homeassistant", on ? "turn_on" : "turn_off", {}, row.entityId)
            }

            // Climate: current temperature, then target with - / +.
            RowLayout {
                visible: row.domain === "climate"
                spacing: Theme.spacingXS

                StyledText {
                    text: row.attrs.current_temperature !== undefined ? row.attrs.current_temperature + "°" : ""
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }
                DankActionButton {
                    iconName: "remove"
                    enabled: !row.unavailable
                    onClicked: row.call("set_temperature", {temperature: Number(row.attrs.temperature) - (row.attrs.target_temp_step || 0.5)})
                }
                StyledText {
                    text: row.attrs.temperature !== undefined && row.attrs.temperature !== null ? Number(row.attrs.temperature).toFixed(1) + "°" : "–"
                    color: row.isOn ? Theme.primary : Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                }
                DankActionButton {
                    iconName: "add"
                    enabled: !row.unavailable
                    onClicked: row.call("set_temperature", {temperature: Number(row.attrs.temperature) + (row.attrs.target_temp_step || 0.5)})
                }
            }

            // Cover
            RowLayout {
                visible: row.domain === "cover"
                spacing: 0
                DankActionButton { iconName: "keyboard_arrow_up"; onClicked: row.call("open_cover") }
                DankActionButton { iconName: "stop"; onClicked: row.call("stop_cover") }
                DankActionButton { iconName: "keyboard_arrow_down"; onClicked: row.call("close_cover") }
            }

            // Scene / script / button: run once.
            DankActionButton {
                visible: ["scene", "script", "button", "input_button"].indexOf(row.domain) >= 0
                iconName: "play_arrow"
                onClicked: row.ha.callService(row.domain, row.domain === "script" ? "turn_on" : (row.domain === "scene" ? "turn_on" : "press"), {}, row.entityId)
            }

            // Read-only value.
            StyledText {
                visible: row.domain === "sensor" || row.domain === "binary_sensor"
                text: row.state + (row.attrs.unit_of_measurement ? " " + row.attrs.unit_of_measurement : "")
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeMedium
            }
        }

        DankSlider {
            Layout.fillWidth: true
            visible: row.dimmable
            minimum: 1
            maximum: 100
            unit: "%"
            value: row.dimmable ? Math.round(row.attrs.brightness / 255 * 100) : 0
            onSliderDragFinished: v => row.call("turn_on", {brightness_pct: v})
        }
    }
}
