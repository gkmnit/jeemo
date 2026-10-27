pragma ComponentBehavior: Bound
import QtQuick

// The bridge to jeemo_net. This is the only file in any of the three UI
// modules that knows Logos exists.
//
// UI modules are sandboxed away from the network, so nothing here opens a
// socket. Everything goes through logos.callModule into the core module,
// which owns the delivery node, the merge rules and the stored history.
//
// The core exposes one cheap integer, revision(), that moves whenever its
// state changes. We poll that and only pull the full lists when it moves,
// so an idle screen costs one small call a second.

QtObject {
    id: link

    property string module: "jeemo_net"

    // 0 off, 1 connecting, 2 connected, 3 error, -1 bridge missing entirely
    property int status: -1
    property var menus: []
    property var ratings: []
    property var requests: []
    property int revision: -1
    property string peerInfo: ""

    readonly property bool ready: link.status === 2
    readonly property bool bridged: link.status >= 0

    signal changed()

    function statusText() {
        if (link.status === -1) return "No core module";
        if (link.status === 0)  return "Off";
        if (link.status === 1)  return "Connecting";
        if (link.status === 2)  return "Connected";
        if (link.status === 3)  return "Error";
        return "";
    }

    function statusColor() {
        if (link.status === 2) return "#4FA86B";
        if (link.status === 1) return "#D9A441";
        if (link.status === 3) return "#D4634A";
        return "#6A6358";
    }

    function call(method, args) {
        if (typeof logos === "undefined" || !logos.callModule) {
            return null;                     // running outside Basecamp
        }
        return logos.callModule(link.module, method, args);
    }

    // callModule hands back either a value or its JSON string form, depending
    // on the type and the Basecamp build. Normalise both.
    function unwrap(raw, fallback) {
        if (raw === null || raw === undefined)
            return fallback;
        if (typeof raw !== "string")
            return raw;
        try { return JSON.parse(raw); } catch (e) { return raw; }
    }

    function start() { link.call("startDelivery", []); link.refresh(); }
    function stop()  { link.call("stopDelivery",  []); link.refresh(); }

    function clearAll() {
        link.call("clearAll", []);
        link.revision = -1;                  // force a reload next tick
        link.refresh();
    }

    function publishMenu(obj) {
        return link.call("publishMenu", [JSON.stringify(obj)]);
    }

    function publishRating(obj) {
        return link.call("publishRating", [JSON.stringify(obj)]);
    }

    function publishRequest(obj) {
        return link.call("publishRequest", [JSON.stringify(obj)]);
    }

    // Read everything, every tick. An earlier version skipped the read when
    // revision() had not moved, and gated the whole function on
    // deliveryStatus() returning a number — so one call coming back in an
    // unexpected shape stopped all reading, silently and forever. A few KB of
    // local JSON a second costs nothing; being blind costs the demo.
    property bool loaded: false

    function refresh() {
        var s = Number(link.unwrap(link.call("deliveryStatus", []), NaN));
        link.status = isFinite(s) ? s : -1;

        if (link.peerInfo === "") {
            var p = link.unwrap(link.call("peerInfo", []), "");
            if (typeof p === "string") link.peerInfo = p;
        }

        var rev = Number(link.unwrap(link.call("revision", []), NaN));
        if (isFinite(rev) && rev === link.revision && link.loaded)
            return;                          // genuinely nothing new
        if (isFinite(rev))
            link.revision = rev;

        link.menus = link.asArray(link.call("menus", []));
        link.ratings = link.asArray(link.call("ratings", []));
        link.requests = link.asArray(link.call("requests", []));
        link.loaded = true;
        link.changed();
    }

    // callModule hands back a value or its JSON text depending on the type and
    // the build. Take either, and never throw.
    function asArray(raw) {
        var v = link.unwrap(raw, []);
        if (typeof v === "string") {
            try { v = JSON.parse(v); } catch (e) { return []; }
        }
        return Array.isArray(v) ? v : [];
    }
}
