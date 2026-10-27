pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// One dish on the table screen. Three buttons, and a note box that opens on
// request so the common case stays a single tap.

Rectangle {
    id: card

    property string name: ""
    property string description: ""
    property var tags: []
    property bool open: false           // meal has been served, rating allowed
    property int mine: -1               // this visitor's rating, -1 for none
    property string note: ""
    property string windowText: ""

    signal rated(int score)
    signal noted(string text)
    signal asked()
    signal wipe()

    // Bumped by the screen whenever the tablet is handed to the next person.
    property int visitorRev: 0
    onVisitorRevChanged: card.wipe()

    radius: 16
    color: "#1A1715"
    border.color: card.mine >= 0 ? "#3E5F6B" : "#2A2420"
    implicitHeight: body.height + 36

    Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        spacing: 10

        Text {
            width: body.width
            text: card.name
            wrapMode: Text.WordWrap
            font.pixelSize: 19
            font.bold: true
            color: "#EDE7DE"
        }

        Text {
            visible: card.description !== ""
            width: body.width
            text: card.description
            wrapMode: Text.WordWrap
            font.pixelSize: 13
            lineHeight: 1.25
            color: "#948B7E"
        }

        Row {
            spacing: 6
            Repeater {
                model: card.tags
                Rectangle {
                    id: chip
                    required property var modelData
                    radius: 999
                    color: "transparent"
                    border.color: "#3B342C"
                    implicitWidth: chipText.implicitWidth + 18
                    implicitHeight: 24
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: chip.modelData
                        font.pixelSize: 11
                        color: "#948B7E"
                    }
                }
            }
        }

        Text {
            visible: !card.open
            width: body.width
            wrapMode: Text.WordWrap
            text: "Open for rating " + card.windowText
            font.pixelSize: 13
            font.italic: true
            color: "#6A6358"
        }

        // Three choices, stacked to fill the card width evenly.
        Column {
            visible: card.open
            width: body.width
            spacing: 7

            Tap {
                label: "More please"
                implicitWidth: body.width
                implicitHeight: 48
                size: 15
                bold: card.mine === 2
                fill: card.mine === 2 ? "#4FA86B" : "#171412"
                edge: card.mine === 2 ? "#4FA86B" : "#3B342C"
                ink: card.mine === 2 ? "#0D1F13" : "#C8C0B5"
                onClicked: card.rated(2)
            }
            Tap {
                label: "Fine"
                implicitWidth: body.width
                implicitHeight: 48
                size: 15
                bold: card.mine === 1
                fill: card.mine === 1 ? "#8A8176" : "#171412"
                edge: card.mine === 1 ? "#8A8176" : "#3B342C"
                ink: card.mine === 1 ? "#17140F" : "#C8C0B5"
                onClicked: card.rated(1)
            }
            Tap {
                label: "Not for me"
                implicitWidth: body.width
                implicitHeight: 48
                size: 15
                bold: card.mine === 0
                fill: card.mine === 0 ? "#D4634A" : "#171412"
                edge: card.mine === 0 ? "#D4634A" : "#3B342C"
                ink: card.mine === 0 ? "#1F0E09" : "#C8C0B5"
                onClicked: card.rated(0)
            }
        }

        // The note box is always there once the dish can be rated. Nothing is
        // sent from this card: the one Send button at the bottom of the screen
        // publishes every rating and note together.
        Column {
            visible: card.open
            width: body.width
            spacing: 6

            Text {
                text: "Want to say something? (optional)"
                font.pixelSize: 12
                color: "#6A6358"
            }

            TextArea {
                id: noteBox
                width: body.width
                placeholderText: "Too salty? Just right? Tell the chef."
                wrapMode: TextArea.Wrap
                color: "#EDE7DE"
                font.pixelSize: 14
                onTextChanged: card.noted(text)
                background: Rectangle {
                    radius: 11
                    color: "#121010"
                    border.color: noteBox.text !== "" ? "#3A2A1E" : "#2A2420"
                    implicitHeight: 78
                }
            }
        }

        // Asking about this particular dish, rather than in general: the chef
        // can act on "less chilli in the sambhar" and cannot act on "less
        // chilli" with no idea which pot it refers to.
        Tap {
            label: "Ask about this dish"
            implicitWidth: body.width
            implicitHeight: 34
            size: 12
            fill: "#121010"
            edge: "#2A2420"
            ink: "#6A6358"
            onClicked: card.asked()
        }

        // Emptied when the tablet is handed on, the same way the ratings are.
        Connections {
            target: card
            function onWipe() { noteBox.text = ""; }
        }
    }
}
