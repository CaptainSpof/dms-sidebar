import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "./components"

// Daemon: one instance for the whole shell, no bar pill. It owns one slideout
// per screen, the Home Assistant connection (open only while a slideout is
// visible) and the IPC target `dms ipc call dafSidebar toggle`.
//
// Layout and Home Assistant settings come from
// ~/.config/DankMaterialShell/dafSidebar.json:
//   { "url": "http://dafoltop:8123",
//     "tokenFile": "~/.config/hass/token",
//     "tabs": [ {id, text, icon, type: "home", sections: [...]} ] }
PluginComponent {
    id: root
    Item {}

    readonly property string side: pluginData.side || "left"
    readonly property real panelWidth: Number(pluginData.width) || 420

    readonly property string home: Quickshell.env("HOME")
    property var config: ({})
    property string token: ""
    property int visibleCount: 0

    readonly property var defaultTabs: [
        {
            id: "home",
            text: "Maison",
            icon: "home",
            type: "home",
            sections: [{byArea: true}]
        }
    ]
    readonly property var tabs: config.tabs && config.tabs.length > 0 ? config.tabs : defaultTabs
    readonly property string tokenPath: (config.tokenFile || (home + "/.config/hass/token")).replace(/^~/, home)

    FileView {
        path: root.home + "/.config/DankMaterialShell/dafSidebar.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.config = JSON.parse(text());
            } catch (e) {
                console.warn("dafSidebar: invalid dafSidebar.json:", e);
            }
        }
    }

    FileView {
        path: root.tokenPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.token = text().trim()
    }

    HaClient {
        id: haClient
        url: root.config.url || "http://dafoltop:8123"
        token: root.token
        active: root.visibleCount > 0
    }

    function toggleOn(screenName) {
        const list = slideouts.instances || [];
        if (list.length === 0)
            return;
        const target = list.find(s => s.modelData?.name === screenName) || list[0];
        list.forEach(s => {
            if (s !== target && s.isVisible)
                s.hide();
        });
        target.toggle();
    }

    Variants {
        id: slideouts
        model: Quickshell.screens

        delegate: DankSlideout {
            id: slideoutWindow
            layerNamespace: "dms:plugins:dafSidebar"
            title: "Sidebar"
            slideoutWidth: root.panelWidth
            edgeGap: SettingsData.notepadEffectiveEdgeGap
            slideEdge: root.side
            customTransparency: Theme.notepadTransparency

            onIsVisibleChanged: root.visibleCount += isVisible ? 1 : -1

            content: Component {
                SidebarPanel {
                    // Not `slideout: slideout`: see AGENTS.md. (same for `ha`: hence haClient)
                    slideout: slideoutWindow
                    ha: haClient
                    tabs: root.tabs
                }
            }
        }
    }

    IpcHandler {
        target: "dafSidebar"

        function toggle(): string {
            root.toggleOn(BarWidgetService.getFocusedScreenName());
            return "ok";
        }

        function hide(): string {
            (slideouts.instances || []).forEach(s => s.hide());
            return "ok";
        }
    }
}
