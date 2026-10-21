import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "dafSidebar"

    SelectionSetting {
        settingKey: "side"
        label: "Côté"
        description: "Bord de l'écran d'où le panneau apparaît."
        options: [
            {
                label: "Gauche",
                value: "left"
            },
            {
                label: "Droite",
                value: "right"
            }
        ]
        defaultValue: "left"
    }

    StringSetting {
        settingKey: "width"
        label: "Largeur (px)"
        description: "Largeur du panneau, 420 par défaut."
        placeholder: "420"
        defaultValue: "420"
    }
}
