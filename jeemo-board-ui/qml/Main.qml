pragma ComponentBehavior: Bound
import QtQuick

// Jeemo - the board outside the dining room.
//
// Read-only on purpose. Nobody taps this screen, so it carries no buttons and
// no state of its own: it shows what the chef has put up for today, large
// enough to read from across a corridor, and it rotates through the meals so
// the whole day is visible from a standing start.

Rectangle {
    id: root
    anchors.fill: parent
    color: "#0E0C0B"

    property var menuList: []
    property int shownIndex: 0

    Link { id: link }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: link.refresh()
    }

    // Rotates between the meals that exist today. One meal filling the screen
    // reads far better from a distance than three columns of small text.
    Timer {
        interval: 12000
        repeat: true
        running: root.menuList.length > 1
        onTriggered: root.shownIndex = (root.shownIndex + 1) % root.menuList.length
    }

    Component.onCompleted: {
        link.changed.connect(root.rebuild);
        link.changed.connect(root.rebuildYes);
        link.start();
        link.refresh();
    }

    function today() { return Qt.formatDate(new Date(), "yyyy-MM-dd"); }

    // Requests the kitchen said yes to, from the last day. The point of the
    // board is that whoever asked finds out without having to ask again, and
    // everyone else learns it is worth asking at all.
    property var saidYes: []

    function rebuildYes() {
        var cut = Math.floor(Date.now() / 1000) - 86400;
        var out = [];
        for (var i = 0; i < link.requests.length; i++) {
            var r = link.requests[i];
            if (!r || r.type !== "request" || !r.done || !r.accepted)
                continue;
            if (r.at < cut)
                continue;
            out.push(r);
        }
        out.sort(function (a, b) { return b.at - a.at; });
        root.saidYes = out;
    }

    function yesContext(r) {
        if (r.itemName && r.itemName !== "") return r.itemName;
        if (r.meal && r.meal !== "")         return r.meal;
        return "";
    }

    function rebuild() {
        var order = [ "breakfast", "lunch", "dinner" ];
        var byId = ({});
        for (var i = 0; i < link.menus.length; i++) {
            var m = link.menus[i];
            if (m && m.menuId)
                byId[m.menuId] = m;
        }
        var out = [];
        for (var k = 0; k < order.length; k++) {
            var meal = byId[root.today() + "-" + order[k]];
            if (meal)
                out.push(meal);
        }
        root.menuList = out;
        if (root.shownIndex >= out.length)
            root.shownIndex = 0;
    }

    readonly property var current:
        root.menuList.length > 0 ? root.menuList[root.shownIndex] : null

    // ---------------------------------------------------------------- head

    Column {
        id: head
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 44
        spacing: 10

        Row {
            spacing: 18
            Text {
                id: mealTitle
                text: root.current ? root.current.meal.toUpperCase() : "JEEMO"
                font.pixelSize: 44
                font.bold: true
                font.letterSpacing: 2
                color: "#F26B3A"
            }
            Text {
                anchors.baseline: mealTitle.baseline
                text: Qt.formatDate(new Date(), "dddd, d MMMM")
                font.pixelSize: 20
                color: "#5E574F"
            }
        }

        Rectangle {
            width: head.width
            height: 1
            color: "#241F1C"
        }

        Text {
            visible: root.current && root.current.note !== ""
            width: head.width
            text: root.current ? root.current.note : ""
            wrapMode: Text.WordWrap
            font.pixelSize: 22
            color: "#E3B99D"
        }
    }

    // ---------------------------------------------------------------- body

    Text {
        anchors.centerIn: parent
        visible: root.menuList.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: link.ready || link.status === 0
              ? "Nothing up for today yet."
              : link.status === -1
                ? "No core module.\nInstall jeemo_net and restart Basecamp."
                : "Waiting for the chef…"
        font.pixelSize: 26
        color: "#5E574F"
    }

    Flickable {
        id: scroll
        visible: root.menuList.length > 0
        anchors.top: head.bottom
        anchors.topMargin: 30
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: yesStrip.visible ? yesStrip.top : footer.top
        anchors.leftMargin: 44
        anchors.rightMargin: 44
        clip: true
        contentHeight: grid.height + 40

        Grid {
            id: grid
            width: scroll.width
            columns: scroll.width > 1000 ? 3 : (scroll.width > 640 ? 2 : 1)
            columnSpacing: 20
            rowSpacing: 20

            readonly property real cellWidth:
                (scroll.width - (grid.columns - 1) * 20) / grid.columns

            Repeater {
                model: root.current ? root.current.items : []

                Rectangle {
                    id: dish
                    required property var modelData
                    width: grid.cellWidth
                    height: dishCol.height + 44
                    radius: 18
                    color: "#171412"
                    border.color: "#241F1C"

                    Column {
                        id: dishCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 22
                        spacing: 10

                        Text {
                            width: dishCol.width
                            text: dish.modelData.name
                            wrapMode: Text.WordWrap
                            font.pixelSize: 28
                            font.bold: true
                            color: "#EDE7DE"
                        }

                        Text {
                            visible: dish.modelData.description !== ""
                            width: dishCol.width
                            text: dish.modelData.description
                            wrapMode: Text.WordWrap
                            lineHeight: 1.3
                            font.pixelSize: 17
                            color: "#948B7E"
                        }

                        Column {
                            visible: dish.modelData.ingredients !== undefined
                                     && dish.modelData.ingredients !== ""
                            width: dishCol.width
                            spacing: 3
                            Text {
                                text: "WHAT IS IN IT"
                                font.pixelSize: 11
                                font.letterSpacing: 1.2
                                font.bold: true
                                color: "#5E574F"
                            }
                            Text {
                                width: dishCol.width
                                text: dish.modelData.ingredients
                                wrapMode: Text.WordWrap
                                lineHeight: 1.25
                                font.pixelSize: 15
                                color: "#B3A99C"
                            }
                        }

                        Column {
                            visible: dish.modelData.recipe !== undefined
                                     && dish.modelData.recipe !== ""
                            width: dishCol.width
                            spacing: 3
                            Text {
                                text: "HOW IT IS MADE"
                                font.pixelSize: 11
                                font.letterSpacing: 1.2
                                font.bold: true
                                color: "#5E574F"
                            }
                            Text {
                                width: dishCol.width
                                text: dish.modelData.recipe
                                wrapMode: Text.WordWrap
                                lineHeight: 1.25
                                font.pixelSize: 14
                                color: "#8A8176"
                            }
                        }

                        Row {
                            spacing: 7
                            Repeater {
                                model: dish.modelData.tags
                                Rectangle {
                                    id: chip
                                    required property var modelData
                                    radius: 999
                                    color: "transparent"
                                    border.color: "#3B342C"
                                    implicitWidth: chipText.implicitWidth + 22
                                    implicitHeight: 28
                                    Text {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: chip.modelData
                                        font.pixelSize: 13
                                        color: "#948B7E"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- foot

    // Said yes to
    Rectangle {
        id: yesStrip
        visible: root.saidYes.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.leftMargin: 44
        anchors.rightMargin: 44
        anchors.bottomMargin: 14
        height: yesCol.height + 30
        radius: 14
        color: "#14201A"
        border.color: "#2E4538"

        Column {
            id: yesCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 15
            spacing: 7

            Text {
                text: "THE KITCHEN SAID YES"
                font.pixelSize: 12
                font.letterSpacing: 1.4
                font.bold: true
                color: "#7FA98C"
            }

            Repeater {
                model: root.saidYes.slice(0, 3)

                Text {
                    id: yesLine
                    required property var modelData
                    width: yesCol.width
                    text: (root.yesContext(yesLine.modelData) === ""
                           ? "" : root.yesContext(yesLine.modelData) + " — ")
                          + yesLine.modelData.text
                    wrapMode: Text.WordWrap
                    font.pixelSize: 17
                    color: "#C6DCCC"
                }
            }

            Text {
                visible: root.saidYes.length > 3
                text: "and " + (root.saidYes.length - 3) + " more"
                font.pixelSize: 13
                color: "#5E7A66"
            }
        }
    }

    Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 44
        anchors.rightMargin: 44
        height: 58

        // Which meal of the day is on screen, as dots rather than words.
        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Repeater {
                model: root.menuList
                Rectangle {
                    id: dot
                    required property int index
                    width: 8; height: 8; radius: 4
                    color: dot.index === root.shownIndex ? "#F26B3A" : "#3B342C"
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8; height: 8; radius: 4
                color: link.statusColor()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: link.statusText() + "  ·  " + link.menus.length + " menus"
                font.pixelSize: 13
                color: "#4A443D"
            }
        }
    }
}
