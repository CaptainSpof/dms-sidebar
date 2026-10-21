import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "./components"

// Daemon: one instance for the whole shell, no bar pill. It owns one slideout
// per screen; `dms ipc call dafSidebar toggle` opens it on the focused screen.
PluginComponent {
    id: root
    Item {}

    readonly property string side: pluginData.side || "left"
    readonly property real panelWidth: Number(pluginData.width) || 420

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

            content: Component {
                SidebarPanel {
                    // Not `slideout: slideout`: see AGENTS.md.
                    slideout: slideoutWindow
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
