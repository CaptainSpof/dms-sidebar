import QtQuick
import qs.Common
import qs.Widgets

// Stand-in body for a tab whose widget does not exist yet.
Item {
    property string label: ""

    StyledText {
        anchors.centerIn: parent
        text: label
        color: Theme.surfaceVariantText
    }
}
