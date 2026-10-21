import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets as DCommon

// Slideout body: a tab bar over a stack of tab widgets. To add a widget, add
// an entry to `tabs` and a component for it in `tabComponents`.
Item {
    id: panel

    required property var slideout

    Keys.onEscapePressed: slideout.hide()

    readonly property var tabs: [
        {
            id: "home",
            text: "Maison",
            icon: "home"
        },
        {
            id: "climate",
            text: "Climat",
            icon: "thermostat"
        },
        {
            id: "media",
            text: "Média",
            icon: "speaker"
        }
    ]
    property int currentIndex: 0

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        DCommon.DTabBar {
            Layout.fillWidth: true
            model: panel.tabs
            currentIndex: panel.currentIndex
            onTabClicked: index => panel.currentIndex = index
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: panel.currentIndex

            Repeater {
                model: panel.tabs
                delegate: PlaceholderTab {
                    required property var modelData
                    label: modelData.text
                }
            }
        }
    }
}
