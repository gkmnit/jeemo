pragma ComponentBehavior: Bound
import QtQuick

// Three numbers sitting above a view. Meant to be read in one glance before
// anyone looks at an individual dish.

Rectangle {
    id: strip

    property int meals: 0
    property int dishes: 0
    property real avg: 0
    property int rated: 0
    property int floor: 3

    implicitHeight: 84
    radius: 14
    color: "#17140F"
    border.color: "#2A2420"

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 22
        spacing: 40

        Column {
            spacing: 3
            Text {
                text: strip.meals
                font.pixelSize: 26
                font.bold: true
                color: "#EDE7DE"
            }
            Text {
                text: strip.meals === 1 ? "meal rated" : "meals rated"
                font.pixelSize: 12
                color: "#6A6358"
            }
        }

        Rectangle { width: 1; height: 44; color: "#2A2420" }

        Column {
            spacing: 3
            Text {
                text: strip.dishes
                font.pixelSize: 26
                font.bold: true
                color: "#EDE7DE"
            }
            Text {
                text: strip.dishes === 1 ? "dish rated" : "dishes rated"
                font.pixelSize: 12
                color: "#6A6358"
            }
        }

        Rectangle { width: 1; height: 44; color: "#2A2420" }

        Column {
            spacing: 3
            Row {
                spacing: 7
                Text {
                    text: strip.rated > 0 ? strip.avg.toFixed(1) : "–"
                    font.pixelSize: 26
                    font.bold: true
                    color: strip.rated === 0 ? "#5E5750"
                         : strip.avg >= 4.2 ? "#4FA86B"
                         : strip.avg >= 3.2 ? "#D9A441"
                         : "#D4634A"
                }
                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    text: "/ 5"
                    font.pixelSize: 13
                    color: "#5E5750"
                }
            }
            Text {
                text: strip.rated > 0
                      ? "average across " + strip.rated
                        + (strip.rated === 1 ? " dish" : " dishes")
                      : "nothing past " + strip.floor + " answers yet"
                font.pixelSize: 12
                color: "#6A6358"
            }
        }
    }
}
