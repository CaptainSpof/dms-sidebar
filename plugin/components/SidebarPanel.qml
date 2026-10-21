import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets as DCommon

// Slideout body: a tab bar over a stack of tab widgets. A tab is
// {id, text, icon, type, sections}; `type: "home"` is the Home Assistant
// dashboard, anything else shows a placeholder. To add a widget type, add a
// component below and a branch in the Loader.
Item {
    id: panel

    required property var slideout
    required property var ha
    required property var tabs

    property int currentIndex: 0

    Keys.onEscapePressed: slideout.hide()

    Component {
        id: homeTab
        HomeTab {
            property var tabData
            ha: panel.ha
            sections: tabData ? (tabData.sections || []) : []
        }
    }

    Component {
        id: placeholderTab
        PlaceholderTab {
            property var tabData
            label: tabData ? (tabData.text || "") : ""
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        DCommon.DTabBar {
            Layout.fillWidth: true
            visible: panel.tabs.length > 1
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
                delegate: Loader {
                    id: loader
                    required property var modelData
                    sourceComponent: modelData.type === "home" ? homeTab : placeholderTab
                    onLoaded: item.tabData = modelData
                }
            }
        }
    }
}
