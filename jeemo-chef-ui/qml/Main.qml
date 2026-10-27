pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// Jeemo - chef app.
// Puts up menus, listens for answers, shows what people said.
// The only Logos touchpoint is the `net` object below.

Rectangle {
    id: root
    anchors.fill: parent
    color: "#121010"

    readonly property int floor: 3      // hide a split under this many answers

    readonly property bool offline: !link.ready
    property string tab: "add"          // "add" | "said"
    property string day: Qt.formatDate(new Date(), "yyyy-MM-dd")
    property string meal: "dinner"
    property string note: ""
    // The dishes being written right now. A ListModel, not a plain array, so
    // that editing one character does not rebuild every row and drop focus.
    ListModel {
        id: dishes
        ListElement {
            name: ""; description: ""
            ingredients: ""; recipe: ""
            locked: false           // true for a dish taken from Cooked before
            sourceId: ""            // the itemId it was taken from
        }
    }
    property var ratings: []
    property var myMenus: ({})
    property var resultRows: []
    property string status: ""

    // ---------------------------------------------------------------- logos

    // ---------------------------------------------------------------- logos
    //
    // Everything that touches the network lives in the jeemo_net core
    // module. This tab is sandboxed and could not open a socket if it tried.

    Link { id: link }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: link.refresh()
    }

    Component.onCompleted: {
        link.changed.connect(root.absorb);
        link.start();
        link.refresh();
    }

    // The core already merged and de-duplicated everything. We only reshape
    // its two flat lists into what the views want.
    function absorb() {
        var held = ({});
        for (var i = 0; i < link.menus.length; i++) {
            var m = link.menus[i];
            if (m && m.menuId)
                held[m.menuId] = m;
        }
        root.myMenus = held;
        root.ratings = link.ratings;
        root.buildPantry();
        root.rebuildAsks();
        root.rollUp();
    }


    // Every dish ever put up, newest first, one entry per itemId. This is what
    // the "cooked before" row offers.
    property var pantry: []

    function buildPantry() {
        var seen = ({});
        var all = [];
        for (var key in root.myMenus) {
            var menu = root.myMenus[key];
            for (var i = 0; i < menu.items.length; i++) {
                var it = menu.items[i];
                if (seen[it.itemId] && seen[it.itemId] >= menu.at)
                    continue;
                seen[it.itemId] = menu.at;
                all.push({ itemId: it.itemId, name: it.name,
                           description: it.description,
                           ingredients: it.ingredients ? it.ingredients : "",
                           recipe: it.recipe ? it.recipe : "",
                           at: menu.at, day: menu.day, meal: menu.meal,
                           times: 0 });
            }
        }
        // De-duplicate, keeping the most recent wording of each dish.
        var best = ({});
        for (var k = 0; k < all.length; k++) {
            var e = all[k];
            if (!best[e.itemId] || best[e.itemId].at < e.at)
                best[e.itemId] = e;
        }
        // How often each dish has been cooked, and how it scored. Both feed
        // the sort, because at a hundred dishes "most recent" alone is not
        // enough to find the one you want.
        var times = ({});
        for (var key2 in root.myMenus) {
            var menu2 = root.myMenus[key2];
            for (var j = 0; j < menu2.items.length; j++) {
                var id2 = menu2.items[j].itemId;
                times[id2] = (times[id2] || 0) + 1;
            }
        }
        var out = [];
        for (var id in best) {
            var e2 = best[id];
            e2.times = times[id] || 1;
            var t = root.tally(id, null);
            e2.score = t.score;
            e2.enough = t.enough;
            e2.answers = t.total;
            out.push(e2);
        }
        root.pantry = out;
        root.sortPantry();
    }

    // "recent" newest first, "often" most cooked, "loved" best scoring with
    // unrated dishes last, "name" alphabetical.
    // Requests from residents. Open ones first, newest first within each.
    property var openAsks: []
    property var doneAsks: []

    function rebuildAsks() {
        var open = [], done = [];
        for (var i = 0; i < link.requests.length; i++) {
            var r = link.requests[i];
            if (!r || r.type !== "request" || !r.id)
                continue;
            if (!root.askMatches(r))
                continue;
            (r.done ? done : open).push(r);
        }
        open.sort(function (a, b) { return b.at - a.at; });
        done.sort(function (a, b) { return b.at - a.at; });
        root.openAsks = open;
        root.doneAsks = done;
    }

    // Two outcomes, because they mean different things to the person who
    // asked. Saying yes puts it on the board outside, so they find out without
    // having to ask again. Closing it just takes it off the kitchen's list.
    function answerAsk(r, accepted) {
        link.publishRequest({
            v: 1, type: "request", id: r.id, text: r.text,
            itemId: r.itemId ? r.itemId : "",
            itemName: r.itemName ? r.itemName : "",
            meal: r.meal ? r.meal : "",
            menuId: r.menuId ? r.menuId : "",
            done: true, accepted: accepted,
            at: Math.floor(Date.now() / 1000)
        });
    }

    function askContext(r) {
        if (r.itemName && r.itemName !== "") return r.itemName;
        if (r.meal && r.meal !== "")         return root.mealLabel(r.meal);
        return "Anything at all";
    }

    // Today, then earlier. Within each, newest first.
    function askIsToday(at) {
        return Qt.formatDate(new Date(at * 1000), "yyyy-MM-dd") === root.dayOffset(0);
    }

    property string askFilter: "all"      // all | dish | meal | general

    function askMatches(r) {
        if (root.askFilter === "dish")    return r.itemName && r.itemName !== "";
        if (root.askFilter === "meal")    return (!r.itemName || r.itemName === "")
                                                 && r.meal && r.meal !== "";
        if (root.askFilter === "general") return (!r.itemName || r.itemName === "")
                                                 && (!r.meal || r.meal === "");
        return true;
    }

    function askWhen(at) {
        var mins = Math.floor((Date.now() / 1000 - at) / 60);
        if (mins < 1)   return "just now";
        if (mins < 60)  return mins + " min ago";
        var hrs = Math.floor(mins / 60);
        if (hrs < 24)   return hrs + (hrs === 1 ? " hour ago" : " hours ago");
        return Math.floor(hrs / 24) + " days ago";
    }

    property string pantrySort: "recent"
    property string pantryFind: ""

    function sortPantry() {
        var out = root.pantry.slice();
        if (root.pantrySort === "often")
            out.sort(function (a, b) { return b.times - a.times || b.at - a.at; });
        else if (root.pantrySort === "loved")
            out.sort(function (a, b) {
                if (a.enough !== b.enough) return a.enough ? -1 : 1;
                return b.score - a.score || b.at - a.at;
            });
        else if (root.pantrySort === "name")
            out.sort(function (a, b) { return a.name.localeCompare(b.name); });
        else
            out.sort(function (a, b) { return b.at - a.at; });
        root.pantry = out;
    }

    function pantryShown() {
        var q = root.pantryFind.trim().toLowerCase();
        if (q === "")
            return root.pantry;
        var out = [];
        for (var i = 0; i < root.pantry.length; i++)
            if (root.pantry[i].name.toLowerCase().indexOf(q) >= 0)
                out.push(root.pantry[i]);
        return out;
    }

    // True when this dish is already in the list being written.
    function alreadyAdded(itemId) {
        for (var i = 0; i < dishes.count; i++)
            if (root.slug(dishes.get(i).name) === itemId)
                return true;
        return false;
    }

    // A dish taken from Cooked before arrives locked. Editing it in place
    // would silently change what the name has always meant, and every rating
    // ever given to it: the ratings hang off the itemId, which is the slug of
    // the name. Changing the recipe under the same name makes the history a
    // lie. To change anything, it has to become a new dish with a new name.
    function addFromPantry(entry) {
        if (root.alreadyAdded(entry.itemId))
            return;
        if (dishes.count === 1 && dishes.get(0).name === ""
                && dishes.get(0).description === "")
            dishes.clear();
        dishes.append({ name: entry.name, description: entry.description,
                        ingredients: entry.ingredients ? entry.ingredients : "",
                        recipe: entry.recipe ? entry.recipe : "",
                        locked: true, sourceId: entry.itemId });
        root.dishRev = root.dishRev + 1;
    }

    // Unlocking blanks the name, because keeping it would land straight back on
    // the duplicate-name rule below. The chef names the variant.
    function unlockDish(i) {
        if (i < 0 || i >= dishes.count)
            return;
        dishes.setProperty(i, "locked", false);
        dishes.setProperty(i, "name", "");
        root.dishRev = root.dishRev + 1;
    }

    // A name already used by another dish, in this draft or ever cooked.
    function nameTaken(i, candidate) {
        var slug = root.slug(candidate);
        if (slug === "")
            return "";
        for (var j = 0; j < dishes.count; j++)
            if (j !== i && root.slug(dishes.get(j).name) === slug)
                return "already on this menu";
        var row = dishes.get(i);
        if (row && row.sourceId === slug)
            return "";                      // unchanged reuse, which is fine
        for (var k = 0; k < root.pantry.length; k++)
            if (root.pantry[k].itemId === slug)
                return "cooked before, pick another name";
        return "";
    }

    // ---------------------------------------------------------------- helpers

    function slug(s) {
        return s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
    }

    // ListModel edits do not notify bindings, so anything that watches the
    // draft list watches this counter instead.
    property int dishRev: 0

    function setDish(i, field, value) {
        if (i >= 0 && i < dishes.count)
            dishes.setProperty(i, field, value);
        root.dishRev = root.dishRev + 1;
    }

    function addDish() {
        dishes.append({ name: "", description: "", ingredients: "", recipe: "",
                        locked: false, sourceId: "" });
        root.dishRev = root.dishRev + 1;
    }

    function removeDish(i) {
        if (i >= 0 && i < dishes.count)
            dishes.remove(i);
        if (dishes.count === 0)
            dishes.append({ name: "", description: "", ingredients: "", recipe: "",
                            locked: false, sourceId: "" });
        root.dishRev = root.dishRev + 1;
    }

    function clearDishes() {
        dishes.clear();
        dishes.append({ name: "", description: "", ingredients: "", recipe: "",
                        locked: false, sourceId: "" });
        root.dishRev = root.dishRev + 1;
    }

    function sendMenu() {
        var items = [];
        for (var i = 0; i < dishes.count; i++) {
            var d = dishes.get(i);
            if (!d.name || d.name.trim() === "")
                continue;
            items.push({
                itemId: root.slug(d.name),
                name: d.name.trim(),
                description: d.description ? d.description.trim() : "",
                ingredients: d.ingredients ? d.ingredients.trim() : "",
                recipe: d.recipe ? d.recipe.trim() : "",
                tags: []
            });
        }
        if (items.length === 0) {
            root.status = "Write at least one dish first.";
            return;
        }
        for (var c = 0; c < dishes.count; c++) {
            var clash = root.nameTaken(c, dishes.get(c).name);
            if (clash !== "") {
                root.status = "Fix the dish name first: it is " + clash + ".";
                return;
            }
        }
        var menu = {
            v: 1, type: "menu",
            menuId: root.day + "-" + root.meal,
            day: root.day, meal: root.meal, note: root.note.trim(),
            items: items,
            at: Math.floor(Date.now() / 1000)
        };
        link.publishMenu(menu);
        root.status = "Done. Everyone can see it now.";
        root.clearDishes();
        root.note = "";
        noteField.text = "";
        root.rollUp();
    }

    // ------------------------------------------------------- what people said
    //
    // Two readings of the same answers:
    //   recentGroups - one block per meal served today and yesterday
    //   allTime      - every dish ever cooked, best first
    // Both are built from `ratings` and `myMenus`, so nothing is stored twice.

    property var recentGroups: []
    property var allTime: []
    property string search: ""
    property string lens: "recent"      // "recent" | "all"
    property string openDish: ""        // itemId whose reviews are expanded

    function dayOffset(n) {
        var d = new Date();
        d.setDate(d.getDate() + n);
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    // Counts one dish inside one menu, or across every menu it appeared in.
    function tally(itemId, menuId) {
        var more = 0, fine = 0, no = 0;
        var notes = [];
        for (var j = 0; j < root.ratings.length; j++) {
            var r = root.ratings[j];
            if (r.itemId !== itemId)
                continue;
            if (menuId && r.menuId !== menuId)
                continue;
            if (r.score === 2) more = more + 1;
            else if (r.score === 1) fine = fine + 1;
            else no = no + 1;
            if (r.comment && r.comment.trim() !== "")
                notes.push({ text: r.comment.trim(), score: r.score });
        }
        var total = more + fine + no;
        // Out of five, so it reads the way people expect a food rating to read.
        // Wanted more counts 5, fine counts 3, did not like it counts 1.
        var score = total > 0 ? (more * 5 + fine * 3 + no * 1) / total : 0;
        return {
            itemId: itemId, more: more, fine: fine, no: no, total: total,
            enough: total >= root.floor,
            score: score, scoreText: score > 0 ? score.toFixed(1) : "–",
            notes: notes
        };
    }

    function tileFor(item, menuId) {
        var t = root.tally(item.itemId, menuId);
        t.name = item.name;
        t.description = item.description;
        return t;
    }

    function mealLabel(meal) {
        return meal.charAt(0).toUpperCase() + meal.slice(1);
    }

    function rebuildRecent() {
        var want = [ { day: root.dayOffset(0), when: "Today" },
                     { day: root.dayOffset(-1), when: "Yesterday" } ];
        var order = [ "breakfast", "lunch", "dinner" ];
        var groups = [];
        for (var w = 0; w < want.length; w++) {
            for (var m = 0; m < order.length; m++) {
                var id = want[w].day + "-" + order[m];
                var menu = root.myMenus[id];
                if (!menu)
                    continue;
                var tiles = [];
                for (var i = 0; i < menu.items.length; i++)
                    tiles.push(root.tileFor(menu.items[i], id));
                groups.push({
                    key: id,
                    label: want[w].when + " · " + root.mealLabel(order[m]),
                    answered: tiles.filter(function (t) { return t.total > 0; }).length,
                    count: tiles.length,
                    tiles: tiles
                });
            }
        }
        root.recentGroups = groups;
    }

    function rebuildAllTime() {
        // One entry per dish, however many times it has been cooked.
        var seen = ({});
        var times = ({});
        for (var key in root.myMenus) {
            var menu = root.myMenus[key];
            for (var i = 0; i < menu.items.length; i++) {
                var it = menu.items[i];
                times[it.itemId] = (times[it.itemId] || 0) + 1;
                if (!seen[it.itemId] || seen[it.itemId].at < menu.at)
                    seen[it.itemId] = { item: it, at: menu.at, day: menu.day };
            }
        }
        var out = [];
        for (var id in seen) {
            var t = root.tileFor(seen[id].item, null);
            t.times = times[id];
            t.lastDay = seen[id].day;
            out.push(t);
        }
        // Best first, but only among dishes with enough answers to judge. The
        // rest fall to the bottom rather than sitting at the top on one vote.
        out.sort(function (a, b) {
            if (a.enough !== b.enough)
                return a.enough ? -1 : 1;
            if (b.score !== a.score)
                return b.score - a.score;
            return b.total - a.total;
        });
        root.allTime = out;
    }

    function rollUp() {
        root.rebuildRecent();
        root.rebuildAllTime();
        root.rebuildSummaries();
    }

    // ------------------------------------------------------------- headline
    // Three numbers above each view: how many meals got answers, how many
    // dishes got answers, and the average score across them. Dishes under the
    // threshold are left out of the average, so one stray vote cannot move it.

    property var recentSummary: ({ meals: 0, dishes: 0, avg: 0, rated: 0 })
    property var allSummary: ({ meals: 0, dishes: 0, avg: 0, rated: 0 })

    function summarise(tiles, meals) {
        var dishes = 0, scored = 0, sum = 0;
        for (var i = 0; i < tiles.length; i++) {
            if (tiles[i].total > 0)
                dishes = dishes + 1;
            if (tiles[i].enough) {
                scored = scored + 1;
                sum = sum + tiles[i].score;
            }
        }
        return {
            meals: meals, dishes: dishes, rated: scored,
            avg: scored > 0 ? sum / scored : 0
        };
    }

    function rebuildSummaries() {
        var all = [];
        var meals = 0;
        for (var g = 0; g < root.recentGroups.length; g++) {
            if (root.recentGroups[g].answered > 0)
                meals = meals + 1;
            all = all.concat(root.recentGroups[g].tiles);
        }
        root.recentSummary = root.summarise(all, meals);

        // All time: a meal counts once any of its dishes was answered.
        var served = ({});
        for (var j = 0; j < root.ratings.length; j++)
            served[root.ratings[j].menuId] = true;
        var mealCount = 0;
        for (var k in served)
            mealCount = mealCount + 1;
        root.allSummary = root.summarise(root.allTime, mealCount);
    }

    function matches(name) {
        if (root.search.trim() === "")
            return true;
        return name.toLowerCase().indexOf(root.search.trim().toLowerCase()) >= 0;
    }

    function filtered(list) {
        var out = [];
        for (var i = 0; i < list.length; i++)
            if (root.matches(list[i].name))
                out.push(list[i]);
        return out;
    }

    // ---------------------------------------------------------------- ui

    Column {
        id: head
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 26
        spacing: 12

        Text {
            text: "Jeemo"
            font.pixelSize: 26
            font.bold: true
            color: "#EDE7DE"
        }

        Row {
            spacing: 8
            Tap {
                label: "Add food"
                size: 14
                bold: root.tab === "add"
                fill: root.tab === "add" ? "#F26B3A" : "#1E1A17"
                edge: root.tab === "add" ? "#F26B3A" : "#2E2822"
                ink: root.tab === "add" ? "#17110E" : "#948B7E"
                onClicked: root.tab = "add"
            }
            Tap {
                label: "What people said"
                size: 14
                bold: root.tab === "said"
                fill: root.tab === "said" ? "#F26B3A" : "#1E1A17"
                edge: root.tab === "said" ? "#F26B3A" : "#2E2822"
                ink: root.tab === "said" ? "#17110E" : "#948B7E"
                onClicked: { root.rollUp(); root.tab = "said"; }
            }

            // The count is the notification. A kitchen screen that pings is a
            // kitchen screen somebody turns off; a number that sits there until
            // it is dealt with is harder to ignore and easier to live with.
            Tap {
                label: root.openAsks.length > 0
                       ? "Requests  " + root.openAsks.length
                       : "Requests"
                size: 14
                bold: root.tab === "asks" || root.openAsks.length > 0
                fill: root.tab === "asks" ? "#F26B3A"
                    : root.openAsks.length > 0 ? "#3A2A1E" : "#1E1A17"
                edge: root.tab === "asks" ? "#F26B3A"
                    : root.openAsks.length > 0 ? "#C98A5E" : "#2E2822"
                ink: root.tab === "asks" ? "#17110E"
                   : root.openAsks.length > 0 ? "#E3B99D" : "#948B7E"
                onClicked: { root.rebuildAsks(); root.tab = "asks"; }
            }
        }

        Text {
            visible: root.status !== "" && !root.offline
            text: root.status
            font.pixelSize: 14
            color: "#8FC79F"
        }

        // Connection, stated plainly. A screen that has quietly
        // stopped reaching anyone is worse than one that says so.
        Row {
            spacing: 9
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 9; height: 9; radius: 5
                color: link.statusColor()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: link.statusText()
                font.pixelSize: 13
                color: link.ready ? "#948B7E" : "#E09A6E"
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: link.status === -1
                text: "install jeemo_net and restart Basecamp"
                font.pixelSize: 13
                color: "#E09A6E"
            }
            Tap {
                visible: link.status === 0 || link.status === 3
                label: "Connect"
                size: 12
                implicitHeight: 30
                fill: "#1E1A17"
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

    // ------------------------------------------------------------- add food

    Flickable {
        id: addScroll
        visible: root.tab === "add"
        anchors.top: head.bottom
        anchors.topMargin: 16
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 26
        anchors.rightMargin: 26
        anchors.bottomMargin: 20
        clip: true
        contentHeight: addCol.height + 30

        Column {
            id: addCol
            width: addScroll.width
            spacing: 12

            Row {
                spacing: 24

                Column {
                    spacing: 6
                    Text { text: "Which day?"; font.pixelSize: 13; color: "#948B7E" }
                    TextField {
                        text: root.day
                        onTextEdited: root.day = text
                        color: "#EDE7DE"
                        font.pixelSize: 14
                        implicitWidth: 170
                        background: Rectangle {
                            radius: 9
                            color: "#1E1A17"
                            border.color: "#2E2822"
                        }
                    }
                }

                Column {
                    spacing: 6
                    Text { text: "Which meal?"; font.pixelSize: 13; color: "#948B7E" }
                    Row {
                        spacing: 6
                        Tap {
                            label: "breakfast"
                            fill: root.meal === "breakfast" ? "#2A1C14" : "#1E1A17"
                            edge: root.meal === "breakfast" ? "#F26B3A" : "#2E2822"
                            ink: root.meal === "breakfast" ? "#F26B3A" : "#948B7E"
                            onClicked: { root.meal = "breakfast"; root.rollUp(); }
                        }
                        Tap {
                            label: "lunch"
                            fill: root.meal === "lunch" ? "#2A1C14" : "#1E1A17"
                            edge: root.meal === "lunch" ? "#F26B3A" : "#2E2822"
                            ink: root.meal === "lunch" ? "#F26B3A" : "#948B7E"
                            onClicked: { root.meal = "lunch"; root.rollUp(); }
                        }
                        Tap {
                            label: "dinner"
                            fill: root.meal === "dinner" ? "#2A1C14" : "#1E1A17"
                            edge: root.meal === "dinner" ? "#F26B3A" : "#2E2822"
                            ink: root.meal === "dinner" ? "#F26B3A" : "#948B7E"
                            onClicked: { root.meal = "dinner"; root.rollUp(); }
                        }
                    }
                }
            }

            // ------------------------------------------- cooked before
            // Dishes put up on any earlier day. Tapping one drops it into the
            // list below, keeping the same itemId so the ratings line up with
            // the last time it was cooked.
            Column {
                visible: root.pantry.length > 0
                width: addCol.width
                spacing: 8

                Text {
                    text: "Cooked before"
                    font.pixelSize: 13
                    color: "#948B7E"
                }

                // At a hundred dishes a flat newest-first list stops being a
                // way to find anything, so it sorts and filters.
                Row {
                    spacing: 7
                    Tap {
                        label: "Recent"
                        implicitHeight: 30; size: 12
                        bold: root.pantrySort === "recent"
                        fill: root.pantrySort === "recent" ? "#2A2420" : "#161311"
                        edge: root.pantrySort === "recent" ? "#F26B3A" : "#2A2420"
                        ink: root.pantrySort === "recent" ? "#EDE7DE" : "#948B7E"
                        onClicked: { root.pantrySort = "recent"; root.sortPantry(); }
                    }
                    Tap {
                        label: "Cooked most"
                        implicitHeight: 30; size: 12
                        bold: root.pantrySort === "often"
                        fill: root.pantrySort === "often" ? "#2A2420" : "#161311"
                        edge: root.pantrySort === "often" ? "#F26B3A" : "#2A2420"
                        ink: root.pantrySort === "often" ? "#EDE7DE" : "#948B7E"
                        onClicked: { root.pantrySort = "often"; root.sortPantry(); }
                    }
                    Tap {
                        label: "Best liked"
                        implicitHeight: 30; size: 12
                        bold: root.pantrySort === "loved"
                        fill: root.pantrySort === "loved" ? "#2A2420" : "#161311"
                        edge: root.pantrySort === "loved" ? "#F26B3A" : "#2A2420"
                        ink: root.pantrySort === "loved" ? "#EDE7DE" : "#948B7E"
                        onClicked: { root.pantrySort = "loved"; root.sortPantry(); }
                    }
                    Tap {
                        label: "A to Z"
                        implicitHeight: 30; size: 12
                        bold: root.pantrySort === "name"
                        fill: root.pantrySort === "name" ? "#2A2420" : "#161311"
                        edge: root.pantrySort === "name" ? "#F26B3A" : "#2A2420"
                        ink: root.pantrySort === "name" ? "#EDE7DE" : "#948B7E"
                        onClicked: { root.pantrySort = "name"; root.sortPantry(); }
                    }
                    TextField {
                        id: pantryFind
                        width: 180
                        height: 30
                        placeholderText: "Find a dish"
                        onTextEdited: root.pantryFind = text
                        color: "#EDE7DE"
                        font.pixelSize: 12
                        leftPadding: 10
                        background: Rectangle {
                            radius: 8
                            color: "#161311"
                            border.color: "#2A2420"
                        }
                    }
                }

                Flow {
                    width: addCol.width
                    spacing: 8

                    Repeater {
                        model: root.pantryFind.length >= 0 ? root.pantryShown() : []

                        Tap {
                            id: pantryChip
                            required property var modelData
                            label: pantryChip.modelData.name
                                   + (pantryChip.modelData.enough
                                      ? "  " + pantryChip.modelData.score.toFixed(1)
                                      : "")
                            implicitHeight: 36
                            size: 13
                            readonly property bool onMenu:
                                root.dishRev >= 0
                                && root.alreadyAdded(pantryChip.modelData.itemId)
                            fill: pantryChip.onMenu ? "#2A2420" : "#1E1A17"
                            edge: "#3B342C"
                            ink: pantryChip.onMenu ? "#6A6358" : "#C8C0B5"
                            onClicked: root.addFromPantry(pantryChip.modelData)
                        }
                    }
                }

                Text {
                    text: root.pantryShown().length === root.pantry.length
                          ? "Tap one to put it on the menu again. It comes back locked."
                          : root.pantryShown().length + " of " + root.pantry.length
                            + " dishes match"
                    font.pixelSize: 12
                    color: "#6A6358"
                }
            }

            Text { text: "What are you cooking?"; font.pixelSize: 13; color: "#948B7E" }

            Repeater {
                model: dishes

                Rectangle {
                    id: editCard
                    required property string name
                    required property string description
                    required property string ingredients
                    required property string recipe
                    required property bool locked
                    required property int index
                    width: addCol.width
                    height: edit.height + 28
                    radius: 13
                    color: editCard.locked ? "#1A1E1B" : "#1E1A17"
                    border.color: editCard.locked ? "#3A5544"
                                : editCard.clash !== "" ? "#D4634A" : "#2E2822"

                    // Recomputed whenever the draft changes, via dishRev.
                    readonly property string clash:
                        root.dishRev >= 0 && !editCard.locked
                        ? root.nameTaken(editCard.index, nameField.text) : ""

                    property bool showMore: false

                    Column {
                        id: edit
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 8

                        Row {
                            spacing: 10

                            TextField {
                                id: nameField
                                // Seeded once, never bound. A live binding to the
                                // model role would fight the cursor on every key.
                                Component.onCompleted: text = editCard.name
                                readOnly: editCard.locked
                                placeholderText: "Dish name"
                                onTextEdited: root.setDish(editCard.index, "name", text)
                                color: editCard.locked ? "#9ECBAC" : "#EDE7DE"
                                font.pixelSize: 16
                                font.bold: true
                                implicitWidth: edit.width - 56
                                background: Rectangle {
                                    radius: 8
                                    color: editCard.locked ? "#161A17" : "#171412"
                                    border.color: editCard.locked ? "#2E4538" : "#2E2822"
                                }
                            }
                            Tap {
                                label: "\u00d7"
                                implicitWidth: 44
                                implicitHeight: 44
                                size: 18
                                fill: "#171412"
                                onClicked: root.removeDish(editCard.index)
                            }
                        }

                        Text {
                            visible: editCard.clash !== ""
                            width: edit.width
                            wrapMode: Text.WordWrap
                            text: "That name is " + editCard.clash + "."
                            font.pixelSize: 12
                            color: "#D4634A"
                        }

                        // A reused dish is shown, not edited. Its ratings hang
                        // off its name, so changing it quietly would rewrite
                        // the history of every meal it has ever been in.
                        Row {
                            visible: editCard.locked
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Cooked before, so it stays as it was"
                                font.pixelSize: 12
                                color: "#7FA98C"
                            }
                            Tap {
                                label: "Change it"
                                implicitHeight: 30
                                size: 12
                                fill: "#161A17"
                                edge: "#3A5544"
                                ink: "#9ECBAC"
                                onClicked: {
                                    root.unlockDish(editCard.index);
                                    nameField.text = "";
                                    nameField.forceActiveFocus();
                                }
                            }
                        }

                        Text {
                            visible: editCard.locked
                            width: edit.width
                            wrapMode: Text.WordWrap
                            text: editCard.description
                            font.pixelSize: 13
                            color: "#6E8A77"
                        }

                        TextField {
                            visible: !editCard.locked
                            width: edit.width
                            Component.onCompleted: text = editCard.description
                            placeholderText: "How would you describe it?"
                            onTextEdited: root.setDish(editCard.index, "description", text)
                            color: "#948B7E"
                            font.pixelSize: 13
                            background: Rectangle {
                                radius: 8
                                color: "#171412"
                                border.color: "#2E2822"
                            }
                        }

                        // Ingredients and method are useful and rarely filled
                        // in at the moment of writing a menu, so they stay out
                        // of the way until asked for.
                        Tap {
                            visible: !editCard.showMore
                            label: (editCard.ingredients === "" && editCard.recipe === "")
                                   ? "Add ingredients or method"
                                   : "Show ingredients and method"
                            implicitWidth: 240
                            implicitHeight: 34
                            size: 12
                            fill: "#171412"
                            edge: "#2E2822"
                            ink: (editCard.ingredients === "" && editCard.recipe === "")
                                 ? "#6A6358" : "#C98A5E"
                            onClicked: editCard.showMore = true
                        }

                        Column {
                            visible: editCard.showMore
                            width: edit.width
                            spacing: 8

                            Text {
                                text: "Ingredients"
                                font.pixelSize: 12
                                color: "#6A6358"
                            }
                            TextArea {
                                width: edit.width
                                readOnly: editCard.locked
                                Component.onCompleted: text = editCard.ingredients
                                placeholderText: "One per line, or however you keep them"
                                wrapMode: TextArea.Wrap
                                onTextChanged: if (!editCard.locked)
                                    root.setDish(editCard.index, "ingredients", text)
                                color: editCard.locked ? "#6E8A77" : "#C8C0B5"
                                font.pixelSize: 13
                                background: Rectangle {
                                    radius: 8
                                    color: "#171412"
                                    border.color: "#2E2822"
                                    implicitHeight: 76
                                }
                            }

                            Text {
                                text: "How it is made"
                                font.pixelSize: 12
                                color: "#6A6358"
                            }
                            TextArea {
                                width: edit.width
                                readOnly: editCard.locked
                                Component.onCompleted: text = editCard.recipe
                                placeholderText: "Enough that someone else could cook it"
                                wrapMode: TextArea.Wrap
                                onTextChanged: if (!editCard.locked)
                                    root.setDish(editCard.index, "recipe", text)
                                color: editCard.locked ? "#6E8A77" : "#C8C0B5"
                                font.pixelSize: 13
                                background: Rectangle {
                                    radius: 8
                                    color: "#171412"
                                    border.color: "#2E2822"
                                    implicitHeight: 110
                                }
                            }

                            Tap {
                                label: "Hide these"
                                implicitWidth: 130
                                implicitHeight: 32
                                size: 12
                                fill: "#121010"
                                edge: "#2E2822"
                                ink: "#6A6358"
                                onClicked: editCard.showMore = false
                            }
                        }
                    }
                }
            }

            Tap {
                label: "Add one more"
                implicitWidth: addCol.width
                implicitHeight: 46
                edge: "#3B342C"
                fill: "#121010"
                onClicked: root.addDish()
            }

            Text { text: "Want to tell people anything?"; font.pixelSize: 13; color: "#948B7E" }

            TextField {
                id: noteField
                width: addCol.width
                text: root.note
                placeholderText: "At the fire, from 8"
                onTextEdited: root.note = text
                color: "#EDE7DE"
                font.pixelSize: 14
                background: Rectangle {
                    radius: 9
                    color: "#1E1A17"
                    border.color: "#2E2822"
                }
            }

            Tap {
                label: "Show this to everyone"
                implicitWidth: addCol.width
                implicitHeight: 54
                size: 16
                bold: true
                fill: "#F26B3A"
                edge: "#F26B3A"
                ink: "#17110E"
                onClicked: root.sendMenu()
            }

            // Demo housekeeping: empties the shared test file so a run can be
            // started over in front of someone. Clears every peer this one reaches.
            Tap {
                label: "Start the demo over"
                implicitWidth: addCol.width
                implicitHeight: 40
                size: 13
                fill: "#121010"
                edge: "#3B342C"
                ink: "#6A6358"
                onClicked: {
                    link.clearAll();
                    root.myMenus = ({});
                    root.ratings = [];
                    root.clearDishes();
                    root.status = "Cleared. Reopen the table tab too.";
                    root.rollUp();
                }
            }
        }
    }

    // --------------------------------------------------------- what they said

    Item {
        id: said
        visible: root.tab === "said"
        anchors.top: head.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 26
        anchors.rightMargin: 26
        anchors.bottomMargin: 18

        // ---- controls: which reading, and a search box for when there are
        // hundreds of dishes and scrolling stops being a way to find anything.
        Row {
            id: lensRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 8

            Tap {
                label: "Today and yesterday"
                size: 13
                bold: root.lens === "recent"
                fill: root.lens === "recent" ? "#2A2420" : "#161311"
                edge: root.lens === "recent" ? "#F26B3A" : "#2A2420"
                ink: root.lens === "recent" ? "#EDE7DE" : "#948B7E"
                onClicked: root.lens = "recent"
            }
            Tap {
                label: "Best of all time"
                size: 13
                bold: root.lens === "all"
                fill: root.lens === "all" ? "#2A2420" : "#161311"
                edge: root.lens === "all" ? "#F26B3A" : "#2A2420"
                ink: root.lens === "all" ? "#EDE7DE" : "#948B7E"
                onClicked: root.lens = "all"
            }

            TextField {
                id: searchField
                width: 240
                height: 44
                placeholderText: "Find a dish"
                onTextEdited: root.search = text
                color: "#EDE7DE"
                font.pixelSize: 13
                leftPadding: 14
                background: Rectangle {
                    radius: 11
                    color: "#161311"
                    border.color: "#2A2420"
                }
            }

            Tap {
                visible: root.search !== ""
                label: "Clear"
                size: 12
                implicitHeight: 44
                fill: "#161311"
                edge: "#2A2420"
                ink: "#948B7E"
                onClicked: { searchField.text = ""; root.search = ""; }
            }
        }

        Flickable {
            id: saidScroll
            anchors.top: lensRow.bottom
            anchors.topMargin: 16
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            contentHeight: saidCol.height + 30

            Column {
                id: saidCol
                width: saidScroll.width
                spacing: 22

                // ---------------------------------------------- recent
                Headline {
                    visible: root.lens === "recent"
                    width: saidCol.width
                    meals: root.recentSummary.meals
                    dishes: root.recentSummary.dishes
                    avg: root.recentSummary.avg
                    rated: root.recentSummary.rated
                    floor: root.floor
                }

                Text {
                    visible: root.lens === "recent" && root.recentGroups.length === 0
                    width: saidCol.width
                    text: "No meals put up today or yesterday yet."
                    wrapMode: Text.WordWrap
                    font.pixelSize: 14
                    color: "#948B7E"
                }

                Repeater {
                    model: root.lens === "recent" ? root.recentGroups : []

                    Column {
                        id: group
                        required property var modelData
                        width: saidCol.width
                        spacing: 11

                        readonly property var shown: root.filtered(group.modelData.tiles)

                        Row {
                            spacing: 10
                            Text {
                                text: group.modelData.label
                                font.pixelSize: 15
                                font.bold: true
                                color: "#EDE7DE"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: group.modelData.answered + " of "
                                      + group.modelData.count + " rated"
                                font.pixelSize: 12
                                color: "#6A6358"
                            }
                        }

                        Flow {
                            width: saidCol.width
                            spacing: 12

                            Repeater {
                                model: group.shown

                                DishTile {
                                    id: recentTile
                                    required property var modelData
                                    width: Math.max(228,
                                        (saidCol.width - 36) / Math.max(1,
                                            Math.floor(saidCol.width / 252)))
                                    name: recentTile.modelData.name
                                    scoreText: recentTile.modelData.scoreText
                                    score: recentTile.modelData.score
                                    more: recentTile.modelData.more
                                    fine: recentTile.modelData.fine
                                    no: recentTile.modelData.no
                                    total: recentTile.modelData.total
                                    enough: recentTile.modelData.enough
                                    reviews: recentTile.modelData.notes.length
                                    expanded: root.openDish === group.modelData.key
                                                              + "/" + recentTile.modelData.itemId
                                    onToggled: root.openDish = recentTile.expanded ? ""
                                        : group.modelData.key + "/" + recentTile.modelData.itemId
                                }
                            }
                        }

                        // Reviews for whichever tile in this block is open.
                        Repeater {
                            model: group.shown

                            Reviews {
                                id: recentReviews
                                required property var modelData
                                width: saidCol.width
                                dish: recentReviews.modelData.name
                                notes: recentReviews.modelData.notes
                                enough: recentReviews.modelData.enough
                                floor: root.floor
                                total: recentReviews.modelData.total
                                more: recentReviews.modelData.more
                                fine: recentReviews.modelData.fine
                                no: recentReviews.modelData.no
                                visible: root.openDish === group.modelData.key
                                                           + "/" + recentReviews.modelData.itemId
                            }
                        }
                    }
                }

                // ---------------------------------------------- all time
                Column {
                    id: allBlock
                    visible: root.lens === "all"
                    width: saidCol.width
                    spacing: 11

                    readonly property var shown: root.filtered(root.allTime)

                    Headline {
                        width: saidCol.width
                        meals: root.allSummary.meals
                        dishes: root.allSummary.dishes
                        avg: root.allSummary.avg
                        rated: root.allSummary.rated
                        floor: root.floor
                    }

                    Text {
                        visible: root.allTime.length === 0
                        width: saidCol.width
                        text: "Nothing cooked yet."
                        font.pixelSize: 14
                        color: "#948B7E"
                    }

                    Text {
                        visible: root.allTime.length > 0
                        text: "Best first. A dish needs " + root.floor
                              + " answers before it gets a score."
                        font.pixelSize: 12
                        color: "#6A6358"
                    }

                    Flow {
                        width: saidCol.width
                        spacing: 12

                        Repeater {
                            model: allBlock.shown

                            DishTile {
                                id: allTile
                                required property var modelData
                                width: Math.max(228,
                                    (saidCol.width - 36) / Math.max(1,
                                        Math.floor(saidCol.width / 252)))
                                name: allTile.modelData.name
                                scoreText: allTile.modelData.scoreText
                                score: allTile.modelData.score
                                more: allTile.modelData.more
                                fine: allTile.modelData.fine
                                no: allTile.modelData.no
                                total: allTile.modelData.total
                                enough: allTile.modelData.enough
                                times: allTile.modelData.times
                                reviews: allTile.modelData.notes.length
                                expanded: root.openDish === "all/" + allTile.modelData.itemId
                                onToggled: root.openDish = allTile.expanded ? ""
                                    : "all/" + allTile.modelData.itemId
                            }
                        }
                    }

                    Repeater {
                        model: allBlock.shown

                        Reviews {
                            id: allReviews
                            required property var modelData
                            width: saidCol.width
                            dish: allReviews.modelData.name
                            notes: allReviews.modelData.notes
                            enough: allReviews.modelData.enough
                            floor: root.floor
                            total: allReviews.modelData.total
                            more: allReviews.modelData.more
                            fine: allReviews.modelData.fine
                            no: allReviews.modelData.no
                            visible: root.openDish === "all/" + allReviews.modelData.itemId
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------- requests

    Flickable {
        id: askScroll
        visible: root.tab === "asks"
        anchors.top: head.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 26
        anchors.rightMargin: 26
        anchors.bottomMargin: 18
        clip: true
        contentHeight: askCol.height + 30

        Column {
            id: askCol
            width: askScroll.width
            spacing: 12

            Text {
                visible: root.openAsks.length === 0 && root.doneAsks.length === 0
                width: askCol.width
                wrapMode: Text.WordWrap
                text: "Nothing asked for yet. Anything residents send from the table "
                      + "lands here."
                font.pixelSize: 14
                color: "#948B7E"
            }

            Row {
                spacing: 7
                Tap {
                    label: "All"
                    implicitHeight: 30; size: 12
                    bold: root.askFilter === "all"
                    fill: root.askFilter === "all" ? "#2A2420" : "#161311"
                    edge: root.askFilter === "all" ? "#F26B3A" : "#2A2420"
                    ink: root.askFilter === "all" ? "#EDE7DE" : "#948B7E"
                    onClicked: { root.askFilter = "all"; root.rebuildAsks(); }
                }
                Tap {
                    label: "About a dish"
                    implicitHeight: 30; size: 12
                    bold: root.askFilter === "dish"
                    fill: root.askFilter === "dish" ? "#2A2420" : "#161311"
                    edge: root.askFilter === "dish" ? "#F26B3A" : "#2A2420"
                    ink: root.askFilter === "dish" ? "#EDE7DE" : "#948B7E"
                    onClicked: { root.askFilter = "dish"; root.rebuildAsks(); }
                }
                Tap {
                    label: "About a meal"
                    implicitHeight: 30; size: 12
                    bold: root.askFilter === "meal"
                    fill: root.askFilter === "meal" ? "#2A2420" : "#161311"
                    edge: root.askFilter === "meal" ? "#F26B3A" : "#2A2420"
                    ink: root.askFilter === "meal" ? "#EDE7DE" : "#948B7E"
                    onClicked: { root.askFilter = "meal"; root.rebuildAsks(); }
                }
                Tap {
                    label: "Anything else"
                    implicitHeight: 30; size: 12
                    bold: root.askFilter === "general"
                    fill: root.askFilter === "general" ? "#2A2420" : "#161311"
                    edge: root.askFilter === "general" ? "#F26B3A" : "#2A2420"
                    ink: root.askFilter === "general" ? "#EDE7DE" : "#948B7E"
                    onClicked: { root.askFilter = "general"; root.rebuildAsks(); }
                }
            }

            Text {
                visible: root.openAsks.length > 0
                text: root.openAsks.length === 1 ? "1 waiting"
                                                 : root.openAsks.length + " waiting"
                font.pixelSize: 15
                font.bold: true
                color: "#EDE7DE"
            }

            Repeater {
                model: root.openAsks

                Rectangle {
                    id: askCard
                    required property var modelData
                    width: askCol.width
                    height: askBody.height + 30
                    radius: 14
                    color: "#17130F"
                    border.color: "#3A2A1E"

                    Column {
                        id: askBody
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 16
                        spacing: 9

                        Row {
                            spacing: 8
                            Rectangle {
                                radius: 999
                                color: "#2A1C14"
                                border.color: "#6B4226"
                                implicitWidth: ctxText.implicitWidth + 20
                                implicitHeight: 24
                                Text {
                                    id: ctxText
                                    anchors.centerIn: parent
                                    text: root.askContext(askCard.modelData)
                                    font.pixelSize: 11
                                    color: "#E3B99D"
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.askIsToday(askCard.modelData.at)
                                      ? "today" : "earlier"
                                font.pixelSize: 11
                                color: "#6A6358"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.askWhen(askCard.modelData.at)
                                font.pixelSize: 11
                                color: "#6A6358"
                            }
                        }

                        Text {
                            width: askBody.width
                            text: askCard.modelData.text
                            wrapMode: Text.WordWrap
                            font.pixelSize: 15
                            color: "#EDE7DE"
                        }

                        Row {
                            spacing: 8
                            Tap {
                                label: "Yes, doing it"
                                implicitHeight: 34
                                size: 12
                                bold: true
                                fill: "#4FA86B"
                                edge: "#4FA86B"
                                ink: "#0D1F13"
                                onClicked: root.answerAsk(askCard.modelData, true)
                            }
                            Tap {
                                label: "Close it"
                                implicitHeight: 34
                                size: 12
                                fill: "#171412"
                                edge: "#3B342C"
                                ink: "#C8C0B5"
                                onClicked: root.answerAsk(askCard.modelData, false)
                            }
                        }

                        Text {
                            width: askBody.width
                            wrapMode: Text.WordWrap
                            text: "Saying yes puts it on the board outside, so whoever "
                                  + "asked finds out without having to ask again."
                            font.pixelSize: 11
                            color: "#5E574F"
                        }
                    }
                }
            }

            Text {
                visible: root.doneAsks.length > 0
                text: "Handled"
                font.pixelSize: 13
                color: "#6A6358"
            }

            Repeater {
                model: root.doneAsks

                Rectangle {
                    id: doneCard
                    required property var modelData
                    width: askCol.width
                    height: doneText.implicitHeight + 34
                    radius: 12
                    color: "#161311"
                    border.color: "#241F1C"

                    Text {
                        id: doneText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 16
                        text: (doneCard.modelData.accepted ? "Doing it:  " : "Closed:  ")
                              + doneCard.modelData.text
                              + "   ·   " + root.askContext(doneCard.modelData)
                              + "   ·   " + root.askWhen(doneCard.modelData.at)
                        wrapMode: Text.WordWrap
                        font.pixelSize: 13
                        color: doneCard.modelData.accepted ? "#7FA98C" : "#5E574F"
                    }
                }
            }

            Text {
                visible: root.openAsks.length > 0 || root.doneAsks.length > 0
                width: askCol.width
                wrapMode: Text.WordWrap
                text: "Requests carry no name. If you need to know who asked, ask at "
                      + "the table."
                font.pixelSize: 12
                color: "#6A6358"
            }
        }
    }
}
