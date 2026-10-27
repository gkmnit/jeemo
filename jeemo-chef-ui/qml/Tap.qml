pragma ComponentBehavior: Bound
import QtQuick

// A plain tappable button. Deliberately not QtQuick.Controls.Button:
// styling that needs a custom background and contentItem makes `parent`
// mean the background item, and label bindings silently come back empty.
Rectangle {
    id: tap

    property string label: ""
    property color fill: "#1E1A17"
    property color edge: "#2E2822"
    property color ink: "#C8C0B5"
    property int size: 14
    property bool bold: false
    signal clicked()

    implicitWidth: text.implicitWidth + 32
    implicitHeight: 44
    radius: 11
    color: mouse.pressed ? Qt.darker(tap.fill, 1.25) : tap.fill
    border.color: tap.edge
    border.width: 1

    Text {
        id: text
        anchors.centerIn: parent
        width: parent.width - 20
        text: tap.label
        color: tap.ink
        font.pixelSize: tap.size
        font.bold: tap.bold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: tap.clicked()
    }
}
