import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Widgets

// Dashboard tab. `sections` come from the config file:
//   {title, entities: [...]}            explicit list
//   {title, area: "Salon", domains: []} one area
//   {byArea: true, domains: []}         one group per area
// `exclude` is a list of regexes matched against the entity id and name.
Item {
    id: tab

    required property var ha
    property var sections: []

    readonly property var defaultDomains: ["light", "switch", "climate", "cover"]
    readonly property var defaultExclude: ["adaptive_lighting", "adaptive lighting", "sleep.mode", "adapt.(brightness|color)", "smart.temperature", "bypass", "permit.join", "_led", "disable.leds", "child.lock", "open.window", "do.not.disturb", "dust.emptying"]

    property var groups: []
    property string _signature: ""

    function matches(id, excludes) {
        const name = (ha.states[id] && ha.states[id].attributes.friendly_name) || "";
        return excludes.some(rx => rx.test(id) || rx.test(name));
    }

    function rebuild() {
        const out = [];
        const areaNames = ha.areas;
        (sections || []).forEach(sec => {
            const domains = sec.domains || defaultDomains;
            const excludes = (sec.exclude || defaultExclude).map(r => new RegExp(r, "i"));
            const candidates = Object.keys(ha.states).filter(id => domains.indexOf(id.split(".")[0]) >= 0 && !ha.hidden[id] && !matches(id, excludes)).sort();
            if (sec.entities) {
                out.push({
                    title: sec.title || "",
                    short: false,
                    ids: sec.entities
                });
            } else if (sec.area) {
                const ids = candidates.filter(id => (areaNames[ha.entityArea[id]] || "").toLowerCase() === sec.area.toLowerCase());
                out.push({
                    title: sec.title || sec.area,
                    short: true,
                    ids: ids
                });
            } else if (sec.byArea) {
                const byArea = {};
                candidates.forEach(id => {
                    const a = areaNames[ha.entityArea[id]];
                    if (a)
                        (byArea[a] = byArea[a] || []).push(id);
                });
                Object.keys(byArea).sort().forEach(a => out.push({
                        title: a,
                        short: true,
                        ids: byArea[a]
                    }));
            }
        });
        const filtered = out.filter(g => g.ids.length > 0);
        // Rebuilding the model re-creates every row; only do it when membership changed.
        const sig = JSON.stringify(filtered);
        if (sig !== _signature) {
            _signature = sig;
            groups = filtered;
        }
    }

    // States change constantly; membership only when entities appear or move.
    Connections {
        target: tab.ha
        function onEntityAreaChanged() {
            tab.rebuild();
        }
        function onAreasChanged() {
            tab.rebuild();
        }
        function onHiddenChanged() {
            tab.rebuild();
        }
        function onStatesChanged() {
            if (!tab._haveStates) {
                tab._haveStates = true;
                tab.rebuild();
            }
        }
    }
    property bool _haveStates: false
    onSectionsChanged: rebuild()
    Component.onCompleted: rebuild()

    StyledText {
        anchors.centerIn: parent
        visible: !tab.ha.ready || tab.groups.length === 0
        width: parent.width - Theme.spacingL * 2
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Theme.surfaceVariantText
        text: tab.ha.phase === "error" ? tab.ha.errorText : (!tab.ha.url || !tab.ha.token ? "Home Assistant non configuré (URL ou token manquant)." : (tab.ha.ready ? "Aucune entité à afficher." : "Connexion à Home Assistant…"))
    }

    // Groups spread over as many columns as the width allows, each to the
    // currently shortest column.
    readonly property int columnCount: Math.max(1, Math.floor((scroller.availableWidth + Theme.spacingM) / (360 + Theme.spacingM)))
    readonly property var columns: {
        const cols = [];
        const heights = [];
        for (let i = 0; i < columnCount; i++) {
            cols.push([]);
            heights.push(0);
        }
        groups.forEach(g => {
            let k = 0;
            for (let i = 1; i < columnCount; i++)
                if (heights[i] < heights[k])
                    k = i;
            cols[k].push(g);
            heights[k] += g.ids.length + 1;
        });
        return cols.filter(c => c.length > 0);
    }

    ScrollView {
        id: scroller
        anchors.fill: parent
        visible: tab.groups.length > 0
        contentWidth: availableWidth
        clip: true

        RowLayout {
            width: scroller.availableWidth
            spacing: Theme.spacingM

            Repeater {
                model: tab.columns
                delegate: ColumnLayout {
                    id: column
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: Theme.spacingM

                    Repeater {
                        model: column.modelData
                        delegate: ColumnLayout {
                            id: group
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.spacingXS

                            StyledText {
                                visible: group.modelData.title !== ""
                                text: group.modelData.title
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.primary
                            }

                            Repeater {
                                model: group.modelData.ids
                                delegate: EntityRow {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    ha: tab.ha
                                    entityId: modelData
                                    shortNames: group.modelData.short === true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
