pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// Jeemo - guest app, for the shared screen at the dining table.
// Shows the menu the chef put up, takes one tap per dish.
// The only Logos touchpoint is the `net` object below.

Rectangle {
    id: root
    anchors.fill: parent
    color: "#121010"

    // When each meal can be rated. Dinner runs past midnight into the morning,
    // so its window wraps around the clock. A function rather than a property
    // named `window`, which collides with names QtQuick already uses on an
    // Item and left the binding never re-evaluating.
    function windowFor(meal) {
        if (meal === "breakfast") return { from: 7,  to: 13 };
        if (meal === "lunch")     return { from: 13, to: 19 };
        if (meal === "dinner")    return { from: 19, to: 7  };
        return null;
    }

    readonly property bool offline: !link.ready
    property var menuList: []       // newest menu per menuId, today only
    property string visitor: ""
    property var myTaps: ({})
    property int touched: 0   // anything picked or typed yet

    // ---------------------------------------------------------------- logos

    // All networking lives in the jeemo_net core module; a ui_qml tab is
    // sandboxed and cannot open a socket.

    Link { id: link }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: link.refresh()
    }

    Component.onCompleted: {
        link.changed.connect(root.rebuild);
        link.start();
        link.refresh();
        root.newVisitor();
    }

    // ---------------------------------------------------------------- state

    function rebuild() {
        var order = ["breakfast", "lunch", "dinner"];
        var byId = ({});
        for (var i = 0; i < link.menus.length; i++) {
            var m = link.menus[i];
            if (m && m.menuId)
                byId[m.menuId] = m;      // the core already picked the winner
        }
        var out = [];
        for (var k = 0; k < order.length; k++) {
            var meal = byId[root.today() + "-" + order[k]];
            if (meal)
                out.push(meal);
        }
        root.menuList = out;
    }

    function today() { return Qt.formatDate(new Date(), "yyyy-MM-dd"); }

    // Normally a dish can only be rated once it has been served. The demo
    // switch lifts that, so the whole thing can be shown at any hour.
    property bool anytime: false

    function isServed(meal) {
        if (root.anytime)
            return true;
        var w = root.windowFor(meal);
        if (!w)
            return false;
        var h = root.clockHour;
        // A window that ends before it starts has wrapped past midnight.
        return w.from <= w.to ? (h >= w.from && h < w.to)
                              : (h >= w.from || h < w.to);
    }

    function windowText(meal) {
        var w = root.windowFor(meal);
        if (!w)
            return "";
        function say(h) {
            var ap = h >= 12 ? "pm" : "am";
            var t = h % 12; if (t === 0) t = 12;
            return t + ap;
        }
        return say(w.from) + " to " + say(w.to);
    }

    // Re-checked on a timer, so a window closing while the tablet sits on the
    // table actually closes it rather than waiting for a reload.
    property int clockHour: new Date().getHours()

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.clockHour = new Date().getHours()
    }

    function newVisitor() {
        root.visitor = "k" + Math.random().toString(36).slice(2)
                           + Date.now().toString(36);
        root.myTaps = ({});
        root.myNotes = ({});
        root.asked = 0;
        root.askAbout("", "", "", "");
        root.touched = 0;
        root.visitorRev = root.visitorRev + 1;   // wipes the note boxes
        idle.stop();
    }

    Timer {
        id: idle
        interval: 45000
        onTriggered: root.newVisitor()
    }

    property var myNotes: ({})
    property int visitorRev: 0

    // Nothing is sent while a person is choosing. Ratings and notes are held
    // here, and the single Send button at the bottom publishes the lot. One
    // message per dish, so a note always arrives attached to its rating.
    function setRating(itemId, score) {
        var t = root.myTaps;
        if (t[itemId] === score)
            delete t[itemId];           // tapping the same one again clears it
        else
            t[itemId] = score;
        root.myTaps = t;
        root.touched = root.touched + 1;
        idle.restart();
    }

    function setNote(itemId, comment) {
        var n = root.myNotes;
        n[itemId] = comment;
        root.myNotes = n;
        root.touched = root.touched + 1;
        idle.restart();
    }

    function sendAll() {
        var sent = 0;
        for (var itemId in root.myTaps) {
            var menuId = root.menuOf(itemId);
            if (!menuId)
                continue;
            link.publishRating({
                v: 1, type: "rating",
                menuId: menuId, itemId: itemId,
                score: root.myTaps[itemId],
                comment: root.noteFor(itemId),
                nonce: root.visitor + "-" + itemId,
                at: Math.floor(Date.now() / 1000)
            });
            sent = sent + 1;
        }
        return sent;
    }

    // Which meal a dish belongs to on the menu currently on screen.
    function menuOf(itemId) {
        for (var i = 0; i < root.menuList.length; i++) {
            var m = root.menuList[i];
            for (var j = 0; j < m.items.length; j++)
                if (m.items[j].itemId === itemId)
                    return m.menuId;
        }
        return "";
    }

    // How many dishes this person has rated, and how many notes they wrote.
    function ratedCount() {
        var n = 0;
        for (var k in root.myTaps) {
            if (root.myTaps[k] !== undefined) n = n + 1;
        }
        return n;
    }

    function notedCount() {
        var n = 0;
        for (var k in root.myNotes)
            if (root.myNotes[k] && root.myNotes[k].trim() !== "") n = n + 1;
        return n;
    }

    // A request is a resident asking the kitchen for something that is not on
    // the menu. It carries no sender for the same reason a rating does not.
    property string requestText: ""
    property int asked: 0

    // What the open ask is about: "" for general, otherwise a dish or a meal.
    property string askItemId: ""
    property string askItemName: ""
    property string askMeal: ""
    property string askMenuId: ""

    function askAbout(menuId, meal, itemId, itemName) {
        root.askMenuId = menuId ? menuId : "";
        root.askMeal = meal ? meal : "";
        root.askItemId = itemId ? itemId : "";
        root.askItemName = itemName ? itemName : "";
    }

    function askTarget() {
        if (root.askItemName !== "") return "About " + root.askItemName;
        if (root.askMeal !== "")     return "About " + root.askMeal;
        return "Anything at all";
    }

    function sendRequest() {
        var t = root.requestText.trim();
        if (t === "")
            return false;
        link.publishRequest({
            v: 1, type: "request",
            id: "r" + Math.random().toString(36).slice(2) + Date.now().toString(36),
            text: t, done: false, accepted: false,
            itemId: root.askItemId, itemName: root.askItemName,
            meal: root.askMeal, menuId: root.askMenuId,
            at: Math.floor(Date.now() / 1000)
        });
        root.requestText = "";
        return true;
    }

    function noteFor(itemId) {
        var n = root.myNotes[itemId];
        return n === undefined ? "" : n;
    }

    function scoreFor(itemId) {
        var s = root.myTaps[itemId];
        return s === undefined ? -1 : s;
    }

    // ---------------------------------------------------------------- ui

    Column {
        id: head
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 30
        spacing: 8

        Row {
            spacing: 14
            Text {
                id: bigTitle
                text: "What's cooking"
                font.pixelSize: 32
                font.bold: true
                font.letterSpacing: -0.5
                color: "#EDE7DE"
            }
            Text {
                anchors.baseline: bigTitle.baseline
                text: Qt.formatDate(new Date(), "dddd, d MMMM")
                font.pixelSize: 15
                color: "#6A6358"
            }
        }
        Row {
            spacing: 12
            Text {
                visible: !root.offline
                anchors.verticalCenter: parent.verticalCenter
                text: "New person · nothing carried over from the last one"
                font.pixelSize: 14
                color: "#948B7E"
            }
            Tap {
                label: root.asked > 0 ? "Ask again" : "Ask the kitchen"
                implicitHeight: 32
                size: 12
                fill: "#171412"
                edge: "#C98A5E"
                ink: "#C98A5E"
                onClicked: {
                    root.askAbout("", "", "", "");
                    askPanel.askOpen = !askPanel.askOpen;
                }
            }
            Tap {
                label: root.anytime ? "Demo mode on" : "Demo mode off"
                implicitHeight: 32
                size: 12
                fill: root.anytime ? "#5FB3CE" : "#171412"
                edge: root.anytime ? "#5FB3CE" : "#3B342C"
                ink: root.anytime ? "#10242B" : "#948B7E"
                onClicked: root.anytime = !root.anytime
            }
        }

        Row {
            spacing: 9
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 9; height: 9; radius: 5
                color: link.statusColor()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: link.ready ? "Connected"
                                 : link.status === -1
                                   ? "No core module. Install jeemo_net and restart Basecamp."
                                   : link.statusText()
                font.pixelSize: 13
                color: link.ready ? "#6A6358" : "#E09A6E"
            }
            Tap {
                visible: link.status === 0 || link.status === 3
                label: "Connect"
                size: 12
                implicitHeight: 30
                fill: "#171412"
                edge: "#3B342C"
                ink: "#C8C0B5"
                onClicked: link.start()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: link.statusText() + "  ·  " + link.menus.length + " menus  ·  "
                      + link.ratings.length + " ratings"
                      + (link.peerInfo === "" ? "" : "  ·  " + link.peerInfo)
                font.pixelSize: 11
                color: "#5E574F"
            }
        }
    }

    Flickable {
        id: scroll
        anchors.top: head.bottom
        anchors.topMargin: 18
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.touched > 0 ? 90 : 0
        anchors.leftMargin: 30
        anchors.rightMargin: 30
        clip: true
        contentHeight: body.height + 30

        Column {
            id: body
            width: scroll.width
            spacing: 20

            Text {
                visible: root.menuList.length === 0
                width: body.width
                text: "No food added for today yet.\nThe chef usually adds it the night before."
                wrapMode: Text.WordWrap
                font.pixelSize: 16
                color: "#948B7E"
            }

            Repeater {
                model: root.menuList

                Column {
                    id: mealBlock
                    required property var modelData
                    width: body.width
                    spacing: 11

                    Row {
                        width: mealBlock.width
                        spacing: 12
                        Text {
                            id: mealName
                            text: mealBlock.modelData.meal.toUpperCase()
                            font.pixelSize: 13
                            font.letterSpacing: 1.6
                            font.bold: true
                            color: "#F26B3A"
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, mealBlock.width - mealName.implicitWidth
                                   - countText.implicitWidth - mealAsk.implicitWidth - 48)
                            height: 1
                            color: "#2A2420"
                        }
                        Text {
                            id: countText
                            anchors.verticalCenter: parent.verticalCenter
                            text: mealBlock.modelData.items.length === 1
                                  ? "1 dish" : mealBlock.modelData.items.length + " dishes"
                            font.pixelSize: 12
                            color: "#6A6358"
                        }
                        Tap {
                            id: mealAsk
                            anchors.verticalCenter: parent.verticalCenter
                            label: "Ask about this meal"
                            implicitHeight: 26
                            size: 11
                            fill: "#121010"
                            edge: "#2A2420"
                            ink: "#6A6358"
                            onClicked: {
                                root.askAbout(mealBlock.modelData.menuId,
                                              mealBlock.modelData.meal, "", "");
                                askPanel.askOpen = true;
                            }
                        }
                    }

                    Rectangle {
                        visible: mealBlock.modelData.note !== ""
                        width: mealBlock.width
                        height: noteText.implicitHeight + 22
                        radius: 10
                        color: "#2A1C14"
                        border.color: "#6B4226"
                        Text {
                            id: noteText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 13
                            text: mealBlock.modelData.note
                            wrapMode: Text.WordWrap
                            font.pixelSize: 14
                            color: "#E3B99D"
                        }
                    }

                    // Two dishes to a row, so a table of people can take in a
                    // whole meal without scrolling past it.
                    Grid {
                        id: dishGrid
                        width: mealBlock.width
                        columns: mealBlock.width > 720 ? 2 : 1
                        columnSpacing: 14
                        rowSpacing: 14

                        readonly property real cellWidth:
                            (mealBlock.width - (dishGrid.columns - 1) * 14) / dishGrid.columns

                        Repeater {
                            model: mealBlock.modelData.items

                            GuestDish {
                                id: dishCard
                                required property var modelData
                                width: dishGrid.cellWidth
                                name: dishCard.modelData.name
                                description: dishCard.modelData.description
                                tags: dishCard.modelData.tags
                                open: root.isServed(mealBlock.modelData.meal)
                                windowText: root.windowText(mealBlock.modelData.meal)
                                mine: root.visitorRev >= 0
                                      && root.touched >= 0
                                      ? root.scoreFor(dishCard.modelData.itemId) : -1
                                note: root.visitorRev >= 0
                                      ? root.noteFor(dishCard.modelData.itemId) : ""
                                visitorRev: root.visitorRev
                                onRated: function (score) {
                                    root.setRating(dishCard.modelData.itemId, score);
                                }
                                onNoted: function (text) {
                                    root.setNote(dishCard.modelData.itemId, text);
                                }
                                onAsked: {
                                    root.askAbout(mealBlock.modelData.menuId,
                                                  mealBlock.modelData.meal,
                                                  dishCard.modelData.itemId,
                                                  dishCard.modelData.name);
                                    askPanel.askOpen = true;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- ask the kitchen

    // Folded away by default. Rating is the common act; asking for something
    // is the rare one, and giving it equal weight on screen would slow the
    // common case down for everybody at the table.
    Rectangle {
        id: askPanel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: sendBar.visible ? sendBar.top : parent.bottom
        anchors.leftMargin: 30
        anchors.rightMargin: 30
        anchors.bottomMargin: 16
        height: askOpen ? askCol.height + 32 : 0
        visible: askOpen
        radius: 14
        color: "#17130F"
        border.color: "#3A2A1E"

        property bool askOpen: false

        Column {
            id: askCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 16
            spacing: 10

            Row {
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Ask the kitchen"
                    font.pixelSize: 14
                    font.bold: true
                    color: "#EDE7DE"
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.askItemName !== "" || root.askMeal !== ""
                    radius: 999
                    color: "#2A1C14"
                    border.color: "#6B4226"
                    implicitWidth: aboutText.implicitWidth + 20
                    implicitHeight: 24
                    Text {
                        id: aboutText
                        anchors.centerIn: parent
                        text: root.askTarget()
                        font.pixelSize: 11
                        color: "#E3B99D"
                    }
                }
                Tap {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.askItemName !== "" || root.askMeal !== ""
                    label: "Not about that"
                    implicitHeight: 24
                    size: 11
                    fill: "#121010"
                    edge: "#2A2420"
                    ink: "#6A6358"
                    onClicked: root.askAbout("", "", "", "")
                }
            }

            TextArea {
                id: askBox
                width: askCol.width
                placeholderText: root.askItemName !== ""
                                 ? "Less chilli in the " + root.askItemName + "?"
                                 : "More curd at lunch? Something without chilli?"
                wrapMode: TextArea.Wrap
                color: "#EDE7DE"
                font.pixelSize: 14
                onTextChanged: root.requestText = text
                background: Rectangle {
                    radius: 11
                    color: "#121010"
                    border.color: "#3B342C"
                    implicitHeight: 84
                }
            }

            Row {
                spacing: 8
                Tap {
                    label: "Send to the kitchen"
                    implicitWidth: 220
                    implicitHeight: 44
                    size: 14
                    bold: true
                    fill: root.requestText.trim() === "" ? "#2A2420" : "#F26B3A"
                    edge: root.requestText.trim() === "" ? "#2A2420" : "#F26B3A"
                    ink: root.requestText.trim() === "" ? "#6A6358" : "#17110E"
                    onClicked: {
                        if (root.sendRequest()) {
                            askBox.text = "";
                            askPanel.askOpen = false;
                            root.asked = root.asked + 1;
                        }
                    }
                }
                Tap {
                    label: "Never mind"
                    implicitWidth: 130
                    implicitHeight: 44
                    size: 13
                    fill: "#121010"
                    edge: "#2A2420"
                    ink: "#948B7E"
                    onClicked: {
                        askBox.text = "";
                        root.requestText = "";
                        askPanel.askOpen = false;
                    }
                }
            }

            Text {
                text: "Goes straight to the kitchen. Nobody's name is attached."
                font.pixelSize: 12
                color: "#6A6358"
            }
        }
    }

    // ------------------------------------------------------------- send it all

    Rectangle {
        id: sendBar
        visible: root.touched > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 90
        color: "#171412"
        border.color: "#2E2822"

        readonly property int rated: root.touched >= 0 ? root.ratedCount() : 0
        readonly property int noted: root.touched >= 0 ? root.notedCount() : 0

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 30
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                text: sendBar.rated === 0
                      ? "Pick a rating before sending"
                      : sendBar.rated + (sendBar.rated === 1 ? " dish rated" : " dishes rated")
                        + (sendBar.noted > 0
                           ? "  ·  " + sendBar.noted
                             + (sendBar.noted === 1 ? " note" : " notes")
                           : "")
                font.pixelSize: 14
                font.bold: true
                color: sendBar.rated === 0 ? "#C98A5E" : "#EDE7DE"
            }
            Text {
                text: "Clears by itself in 45 seconds"
                font.pixelSize: 12
                color: "#6A6358"
            }
        }

        Tap {
            anchors.right: parent.right
            anchors.rightMargin: 30
            anchors.verticalCenter: parent.verticalCenter
            label: "Send and hand to the next person"
            implicitWidth: 360
            implicitHeight: 54
            size: 16
            bold: true
            fill: sendBar.rated === 0 ? "#2A2420" : "#F26B3A"
            edge: sendBar.rated === 0 ? "#2A2420" : "#F26B3A"
            ink: sendBar.rated === 0 ? "#6A6358" : "#17110E"
            onClicked: {
                if (sendBar.rated === 0)
                    return;
                root.sendAll();
                root.newVisitor();
            }
        }
    }
}
