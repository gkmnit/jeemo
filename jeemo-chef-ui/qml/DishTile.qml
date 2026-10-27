pragma ComponentBehavior: Bound
import QtQuick

// One dish, as a small card in a grid. Shows the score if enough people have
// answered, and holds it back if they have not. Tapping opens the reviews.

Rectangle {
    id: tile

    property string name: ""
    property string scoreText: "–"
    property real score: 0
    property int more: 0
    property int fine: 0
    property int no: 0
    property int total: 0
    property bool enough: false
    property int times: 0
    property bool expanded: false
    property int reviews: 0

    signal toggled()

    implicitWidth: 240
    implicitHeight: col.height + 28
    radius: 14
    color: hover.hovered ? "#231E1A" : "#1A1715"
    border.color: tile.expanded ? "#F26B3A" : "#2A2420"
    border.width: tile.expanded ? 2 : 1

    Behavior on color { ColorAnimation { duration: 90 } }

    // Good dishes get a warm edge down the left, so the grid can be read at a
    // glance without putting a number on everything.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: 4
        radius: 2
        visible: tile.enough
        color: tile.score >= 4.2 ? "#4FA86B"
             : tile.score >= 3.2 ? "#D9A441"
             : "#D4634A"
    }

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 14
        spacing: 7

        Row {
            width: col.width
            spacing: 8

            Text {
                width: col.width - pill.width - 8
                text: tile.name
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                font.pixelSize: 15
                font.bold: true
                color: "#EDE7DE"
            }

            // The score badge. Grey and dashed until the threshold is met.
            Rectangle {
                id: pill
                width: 46
                height: 26
                radius: 7
                color: !tile.enough ? "#241F1C"
                     : tile.score >= 4.2 ? "#4FA86B"
                     : tile.score >= 3.2 ? "#D9A441"
                     : "#D4634A"
                Text {
                    anchors.centerIn: parent
                    text: tile.enough ? tile.scoreText : "–"
                    font.pixelSize: 13
                    font.bold: true
                    color: tile.enough ? "#10180F" : "#5E5750"
                }
            }
        }

        // Split bar. Only drawn once the dish has passed the threshold.
        Row {
            visible: tile.enough
            width: col.width
            height: 6
            Rectangle {
                width: tile.total > 0 ? (col.width * tile.more / tile.total) : 0
                height: 6; color: "#4FA86B"
            }
            Rectangle {
                width: tile.total > 0 ? (col.width * tile.fine / tile.total) : 0
                height: 6; color: "#4B443C"
            }
            Rectangle {
                width: tile.total > 0 ? (col.width * tile.no / tile.total) : 0
                height: 6; color: "#D4634A"
            }
        }

        // The actual counts, not only the bar. A chef deciding what to cook
        // again needs the numbers, and three colours do not carry them.
        Text {
            visible: tile.enough
            text: tile.total + " answered  ·  " + tile.more + " more, "
                  + tile.fine + " fine, " + tile.no + " no"
            font.pixelSize: 11
            color: "#948B7E"
        }

        Text {
            visible: !tile.enough
            width: col.width
            text: tile.total === 0
                  ? "No answers yet"
                  : tile.total + (tile.total === 1 ? " answer so far" : " answers so far")
            font.pixelSize: 11
            color: "#6A6358"
        }

        Text {
            visible: tile.enough || tile.reviews > 0
            text: tile.expanded ? "Hide notes"
                                : (tile.reviews > 0 ? "Read " + tile.reviews
                                     + (tile.reviews === 1 ? " note" : " notes")
                                   : "Open")
            font.pixelSize: 11
            font.bold: true
            font.underline: true
            color: "#C98A5E"
        }

        Row {
            spacing: 10
            Text {
                visible: tile.times > 0
                text: tile.times === 1 ? "Cooked once" : "Cooked " + tile.times + " times"
                font.pixelSize: 11
                color: "#6A6358"
            }
            Text {
                visible: tile.enough && tile.reviews > 0
                text: tile.reviews === 1 ? "1 note" : tile.reviews + " notes"
                font.pixelSize: 11
                font.bold: true
                color: "#C98A5E"
            }
        }
    }

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        onClicked: tile.toggled()
    }
}
