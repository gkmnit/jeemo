pragma ComponentBehavior: Bound
import QtQuick

// The written notes for one dish, shown when its tile is open.
// Held back entirely until the dish has passed the threshold: in a group this
// small, one note next to one rating identifies whoever wrote it.

Rectangle {
    id: panel

    property string dish: ""
    property var notes: []
    property bool enough: false
    property int floor: 3
    property int total: 0
    property int more: 0
    property int fine: 0
    property int no: 0

    implicitHeight: inner.height + 32
    radius: 14
    color: "#17130F"
    border.color: "#3A2A1E"

    Column {
        id: inner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 10

        Row {
            spacing: 12
            Text {
                text: panel.dish
                font.pixelSize: 14
                font.bold: true
                color: "#EDE7DE"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: panel.enough
                text: panel.total + " answered  ·  " + panel.more + " more, "
                      + panel.fine + " fine, " + panel.no + " no"
                font.pixelSize: 11
                color: "#6A6358"
            }
        }

        Text {
            visible: !panel.enough
            width: inner.width
            wrapMode: Text.WordWrap
            text: "Notes stay hidden until " + panel.floor + " people have answered. "
                  + panel.total + " so far."
            font.pixelSize: 13
            color: "#948B7E"
        }

        Text {
            visible: panel.enough && panel.notes.length === 0
            text: "No one wrote anything for this one."
            font.pixelSize: 13
            color: "#6A6358"
        }

        Repeater {
            model: panel.enough ? panel.notes : []

            Row {
                id: noteRow
                required property var modelData
                width: inner.width
                spacing: 10

                // How this person rated the dish, carried beside what they
                // wrote. "Too much chilli" from someone who wanted more of it
                // means something different from the same words from someone
                // who left it, and the words alone do not say which.
                readonly property int score:
                    noteRow.modelData.score === undefined ? -1
                                                          : noteRow.modelData.score
                readonly property color mark:
                    noteRow.score === 2 ? "#4FA86B"
                  : noteRow.score === 1 ? "#8A8176"
                  : noteRow.score === 0 ? "#D4634A"
                  : "#4B443C"

                Rectangle {
                    width: 3
                    height: noteCol.height
                    radius: 2
                    color: noteRow.mark
                }

                Column {
                    id: noteCol
                    width: inner.width - 13
                    spacing: 4

                    Rectangle {
                        visible: noteRow.score >= 0
                        radius: 6
                        color: "transparent"
                        border.color: noteRow.mark
                        implicitWidth: verdict.implicitWidth + 16
                        implicitHeight: 20
                        Text {
                            id: verdict
                            anchors.centerIn: parent
                            text: noteRow.score === 2 ? "wanted more"
                                : noteRow.score === 1 ? "said it was fine"
                                                      : "not for them"
                            font.pixelSize: 11
                            font.bold: true
                            color: noteRow.mark
                        }
                    }

                    Text {
                        width: noteCol.width
                        text: noteRow.modelData.text
                        wrapMode: Text.WordWrap
                        font.pixelSize: 13
                        color: "#C8C0B5"
                    }
                }
            }
        }
    }
}
