import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets as DCommon

// Slideout body: a tab bar over a stack of tab widgets. A tab is
// {id, text, icon, type, ...}: `type: "home"` is the per-area entity list
// (`sections`), `type: "lovelace"` renders an HA dashboard (`dashboard`: its
// url_path), `type: "rer"` lists the next departures at a stop (PRIM),
// anything else shows a placeholder. To add a widget type, add a
// component below and a branch in the Loader.
Item {
    id: panel

    required property var slideout
    required property var ha
    required property var tabs
    property string mdiFont: ""
    property string mdiMap: ""

    property int currentIndex: 0

    Keys.onEscapePressed: slideout.hide()

    // Ctrl+Tab / Ctrl+Shift+Tab cycle through the tabs.
    function cycle(step) {
        if (tabs.length > 1)
            currentIndex = (currentIndex + step + tabs.length) % tabs.length;
    }

    Shortcut {
        sequences: ["Ctrl+Tab"]
        onActivated: panel.cycle(1)
    }

    Shortcut {
        // Shift+Tab arrives as Backtab.
        sequences: ["Ctrl+Shift+Tab", "Ctrl+Shift+Backtab", "Ctrl+Backtab"]
        onActivated: panel.cycle(-1)
    }

    Component {
        id: homeTab
        HomeTab {
            property var tabData
            ha: panel.ha
            sections: tabData ? (tabData.sections || []) : []
        }
    }

    Component {
        id: lovelaceTab
        LovelaceTab {
            property var tabData
            ha: panel.ha
            dashboard: tabData ? (tabData.dashboard || "") : ""
            startPage: tabData ? (tabData.page || "") : ""
            skipSections: tabData ? (tabData.skipSections || []) : []
            hideUnsupported: tabData ? tabData.hideUnsupported === true : false
            mdiFontPath: panel.mdiFont
            mdiMapPath: panel.mdiMap
        }
    }

    Component {
        id: rerTab
        RerTab {
            property var tabData
            conf: tabData || ({})
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
                    required property int index
                    // On screen: the shown tab of an open panel. Tabs that poll (RER) use it.
                    readonly property bool shown: index === panel.currentIndex && panel.slideout.isVisible
                    sourceComponent: {
                        switch (modelData.type) {
                        case "home": return homeTab;
                        case "lovelace": return lovelaceTab;
                        case "rer": return rerTab;
                        default: return placeholderTab;
                        }
                    }
                    onLoaded: {
                        item.tabData = modelData;
                        if (item.active !== undefined)
                            item.active = Qt.binding(() => loader.shown);
                    }
                }
            }
        }
    }
}
