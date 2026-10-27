#include "jeemo_net_impl.h"
#include "jeemo_json.h"
#include "logos_sdk.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <random>
#include <sstream>
#include <sys/stat.h>

namespace {

const char* TOPIC_MENU   = "/jeemo/1/menu/json";
const char* TOPIC_RATING  = "/jeemo/1/rating/json";
const char* TOPIC_REQUEST = "/jeemo/1/request/json";

int64_t nowSeconds()
{
    using namespace std::chrono;
    return duration_cast<seconds>(system_clock::now().time_since_epoch()).count();
}

std::string randomId()
{
    static const char* hex = "0123456789abcdef";
    std::random_device rd;
    std::mt19937_64 gen(rd());
    std::uniform_int_distribution<int> pick(0, 15);
    std::string out;
    for (int i = 0; i < 24; ++i) out += hex[pick(gen)];
    return out;
}

std::vector<uint8_t> toBytes(const std::string& s)
{
    return std::vector<uint8_t>(s.begin(), s.end());
}

std::string fromBytes(const std::vector<uint8_t>& b)
{
    return std::string(b.begin(), b.end());
}

std::string envOr(const char* name, const std::string& fallback)
{
    const char* v = std::getenv(name);
    return (v && *v) ? std::string(v) : fallback;
}

} // namespace

// ── Lifecycle ────────────────────────────────────────────────────────

void JeemoNetImpl::onContextReady()
{
    if (m_armed) return;
    m_armed = true;

    m_myId = randomId();
    load();

    // Armed before anything is started, so the first message after start()
    // cannot slip past us.
    modules().delivery_module.onMessageReceived(
        [this](const std::string& /*hash*/, const std::string& contentTopic,
               const std::vector<uint8_t>& payload, const std::string& /*source*/,
               int64_t /*timestamp*/) {
            const std::string body = fromBytes(payload);
            int changed = 0;
            if      (contentTopic == TOPIC_MENU)    changed = takeMenu(body);
            else if (contentTopic == TOPIC_RATING)  changed = takeRating(body);
            else if (contentTopic == TOPIC_REQUEST) changed = takeRequest(body);
            if (changed) {
                save();
                stateChanged(m_revision);
            }
        });

    modules().delivery_module.onConnectionStateChanged(
        [this](const std::string& status, int64_t /*timestamp*/) {
            if (status.find("Connected") != std::string::npos) setStatus(2);
            else if (!status.empty())                          setStatus(1);
        });
}

int64_t JeemoNetImpl::startDelivery()
{
    if (m_started) return 1;

    // Connecting is set before start(), because the state event can fire
    // inside start() and we would otherwise overwrite it afterwards.
    setStatus(1);

    if (!m_createNodeDone) {
        // Three machines run this: the chef's laptop, the board outside the
        // dining room, and a resident's own Basecamp. Each needs its own
        // ports and key, so everything that varies per machine is an
        // environment variable rather than a separate build.
        //
        //   JEEMO_ROLE     chef | board | guest
        //   JEEMO_TCPPORT  JEEMO_UDPPORT  JEEMO_NODEKEY
        //   JEEMO_PEERS    comma-separated multiaddrs to dial directly
        const std::string role = envOr("JEEMO_ROLE", "chef");

        // Fixed keys mean fixed PeerIDs, which is what lets two instances on
        // one machine find each other before either has ever run. The first
        // two are the pair published with the shared-color tutorial and their
        // PeerIDs are known good.
        const std::string KEY_CHEF  = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";
        const std::string KEY_GUEST = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f21";
        const std::string KEY_BOARD = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f22";
        const std::string PEERID_CHEF  = "16Uiu2HAm4Ms862Gnqafssgvik4JJ1LuqWMcKNipq4nm2UaoLRbeP";
        const std::string PEERID_GUEST = "16Uiu2HAmAD6tSgCQZNS1aNwyQS94ud45VoW7uXdw7UhiCwp247iq";

        int64_t tcpPort = 60000, udpPort = 9000;
        std::string nodeKey = KEY_CHEF;
        if (role == "guest")      { tcpPort = 60001; udpPort = 9001; nodeKey = KEY_GUEST; }
        else if (role == "board") { tcpPort = 60002; udpPort = 9002; nodeKey = KEY_BOARD; }

        tcpPort = std::strtoll(envOr("JEEMO_TCPPORT", std::to_string(tcpPort)).c_str(), nullptr, 10);
        udpPort = std::strtoll(envOr("JEEMO_UDPPORT", std::to_string(udpPort)).c_str(), nullptr, 10);
        nodeKey = envOr("JEEMO_NODEKEY", nodeKey);

        // Static peers. The bundled logos.dev bootstrap ids have been stale
        // upstream, so peers that rely on discovery alone never reach
        // Connected. The shared-color tutorial pins peers for the same
        // reason; on a real network set JEEMO_PEERS per machine.
        std::string peersJson;
        const std::string peers = envOr("JEEMO_PEERS", "");
        if (!peers.empty()) {
            std::stringstream ss(peers);
            std::string one;
            while (std::getline(ss, one, ',')) {
                while (!one.empty() && one.front() == ' ') one.erase(one.begin());
                while (!one.empty() && one.back()  == ' ') one.pop_back();
                if (one.empty()) continue;
                if (!peersJson.empty()) peersJson += ",";
                peersJson += jeemo::quoted(one);
            }
        } else if (role == "guest") {
            peersJson = jeemo::quoted("/ip4/127.0.0.1/tcp/60000/p2p/" + PEERID_CHEF);
        } else if (role == "chef") {
            peersJson = jeemo::quoted("/ip4/127.0.0.1/tcp/60001/p2p/" + PEERID_GUEST);
        }

        std::string cfg = "{";
        cfg += "\"logLevel\":\"INFO\",";
        cfg += "\"mode\":\"Core\",";
        cfg += "\"preset\":\"logos.dev\",";
        cfg += "\"relay\":true,";            // gossipsub; needed for same-shard relay
        cfg += "\"tcpPort\":" + std::to_string(tcpPort) + ",";
        cfg += "\"discv5UdpPort\":" + std::to_string(udpPort);
        if (!nodeKey.empty())  cfg += ",\"nodeKey\":" + jeemo::quoted(nodeKey);
        if (!peersJson.empty()) cfg += ",\"staticNodes\":[" + peersJson + "]";
        cfg += "}";

        m_peerInfo = "role=" + role
                   + " tcp=" + std::to_string(tcpPort)
                   + " udp=" + std::to_string(udpPort);

        logos::CallError err;
        auto r = modules().delivery_module.createNode(cfg, &err, 20000);
        if (!err.ok() || !r.success) {
            std::fprintf(stderr, "jeemo_net: createNode failed: %s\n",
                         err.ok() ? r.error.c_str() : err.code.c_str());
            setStatus(3);
            return 0;
        }
        m_createNodeDone = true;
    }

    {
        logos::CallError err;
        auto r = modules().delivery_module.start(&err, 30000);
        // start() has been declared void in some builds, so an empty reply is
        // not a failure; readiness really arrives on connectionStateChanged.
        if (!err.ok() && !err.code.empty())
            std::fprintf(stderr, "jeemo_net: start reported %s\n", err.code.c_str());
        (void)r;
    }

    // Subscribe synchronously, straight after start. Deferring it leaves a
    // window where the connection is up but neither side has announced its
    // subscription; gossipsub then falls back to fanout for the late peer and
    // you get the asymmetric bug where the chef sees the guest but not the
    // other way round.
    {
        logos::CallError e1, e2;
        auto a = modules().delivery_module.subscribe(TOPIC_MENU,   &e1, 10000);
        auto b = modules().delivery_module.subscribe(TOPIC_RATING, &e2, 10000);
        logos::CallError e3;
        auto c = modules().delivery_module.subscribe(TOPIC_REQUEST, &e3, 10000);
        if ((!e1.ok() || !a.success) || (!e2.ok() || !b.success)
            || (!e3.ok() || !c.success)) {
            std::fprintf(stderr, "jeemo_net: subscribe failed\n");
            setStatus(3);
            return 0;
        }
    }

    m_subscribed = true;
    m_started    = true;
    if (m_status < 2) setStatus(2);     // only meaningful when running alone
    return 1;
}

int64_t JeemoNetImpl::stopDelivery()
{
    if (!m_started) return 1;
    logos::CallError err;
    if (m_subscribed) {
        modules().delivery_module.unsubscribe(TOPIC_MENU,   &err, 5000);
        modules().delivery_module.unsubscribe(TOPIC_RATING, &err, 5000);
        m_subscribed = false;
    }
    modules().delivery_module.stop(&err, 10000);
    m_started = false;
    setStatus(0);
    save();
    return 1;
}

int64_t     JeemoNetImpl::deliveryStatus() { return m_status; }
std::string JeemoNetImpl::peerInfo()       { return m_peerInfo; }
std::string JeemoNetImpl::myId()           { return m_myId; }
int64_t     JeemoNetImpl::revision()       { return m_revision; }

// ── Sending ──────────────────────────────────────────────────────────

int64_t JeemoNetImpl::publishMenu(const std::string& json)
{
    if (!m_started && !startDelivery()) return 0;

    // A menu is a public act by the chef, so it carries who sent it. That is
    // also what breaks ties when two machines post the same meal at once.
    std::string body = jeemo::withField(json, "from", jeemo::quoted(m_myId));
    body = jeemo::withField(body, "at", std::to_string(nowSeconds()));

    // Applied locally first, so the chef's own screen never waits on the
    // round trip back through gossipsub.
    if (takeMenu(body)) { save(); stateChanged(m_revision); }
    return sendOn(TOPIC_MENU, body);
}

int64_t JeemoNetImpl::publishRating(const std::string& json)
{
    if (!m_started && !startDelivery()) return 0;

    // Deliberately no sender id. The nonce is random per visitor and thrown
    // away when the tablet is handed on; attaching anything that survives a
    // reset would make every answer traceable to a machine. This lives here
    // rather than in the UI so a later screen cannot quietly get it wrong.
    std::string body = jeemo::withField(json, "at", std::to_string(nowSeconds()));

    if (takeRating(body)) { save(); stateChanged(m_revision); }
    return sendOn(TOPIC_RATING, body);
}

int64_t JeemoNetImpl::publishRequest(const std::string& json)
{
    if (!m_started && !startDelivery()) return 0;

    // A request is a resident asking the kitchen for something. Like a rating
    // it carries no sender: who asked is the kitchen's business to find out in
    // person, not the network's to record.
    std::string body = jeemo::withField(json, "at", std::to_string(nowSeconds()));

    if (takeRequest(body)) { save(); stateChanged(m_revision); }
    return sendOn(TOPIC_REQUEST, body);
}

int JeemoNetImpl::sendOn(const std::string& topic, const std::string& payload)
{
    logos::CallError err;
    auto r = modules().delivery_module.send(topic, toBytes(payload), &err, 10000);
    if (!err.ok() || !r.success) {
        std::fprintf(stderr, "jeemo_net: send failed on %s\n", topic.c_str());
        return 0;
    }
    return 1;
}

// ── Merging ──────────────────────────────────────────────────────────

int JeemoNetImpl::takeMenu(const std::string& json)
{
    if (jeemo::field(json, "type") != "menu") return 0;
    if (jeemo::number(json, "v") != 1)        return 0;
    const std::string menuId = jeemo::field(json, "menuId");
    if (menuId.empty())                       return 0;

    // Last write wins per meal, so re-posting dinner replaces dinner
    // everywhere. A tie on the second is broken by sender id, which every
    // peer compares the same way, so no two screens settle differently.
    auto it = m_menus.find(menuId);
    if (it != m_menus.end()) {
        const long long mine   = jeemo::number(it->second, "at");
        const long long theirs = jeemo::number(json, "at");
        if (theirs < mine) return 0;
        if (theirs == mine
            && jeemo::field(json, "from") <= jeemo::field(it->second, "from"))
            return 0;
    }
    m_menus[menuId] = json;
    ++m_revision;
    return 1;
}

int JeemoNetImpl::takeRating(const std::string& json)
{
    if (jeemo::field(json, "type") != "rating") return 0;
    if (jeemo::number(json, "v") != 1)          return 0;
    const std::string nonce = jeemo::field(json, "nonce");
    if (nonce.empty())                          return 0;

    // One answer per person per dish. A later message under the same nonce is
    // that person changing their mind or adding a note, not a second vote.
    auto it = m_ratings.find(nonce);
    if (it != m_ratings.end()
        && jeemo::number(json, "at") < jeemo::number(it->second, "at"))
        return 0;

    m_ratings[nonce] = json;
    ++m_revision;
    return 1;
}

int JeemoNetImpl::takeRequest(const std::string& json)
{
    if (jeemo::field(json, "type") != "request") return 0;
    if (jeemo::number(json, "v") != 1)           return 0;
    const std::string id = jeemo::field(json, "id");
    if (id.empty())                              return 0;

    // Last write wins per request id. That is what lets the kitchen mark one
    // handled: it re-publishes the same id with done set, and every screen
    // converges on the later copy.
    auto it = m_requests.find(id);
    if (it != m_requests.end()
        && jeemo::number(json, "at") < jeemo::number(it->second, "at"))
        return 0;

    m_requests[id] = json;
    ++m_revision;
    return 1;
}

// ── Reading ──────────────────────────────────────────────────────────

std::string JeemoNetImpl::menus()
{
    std::string out = "[";
    bool first = true;
    for (const auto& kv : m_menus) {
        if (!first) out += ",";
        out += kv.second;
        first = false;
    }
    return out + "]";
}

std::string JeemoNetImpl::ratings()
{
    std::string out = "[";
    bool first = true;
    for (const auto& kv : m_ratings) {
        if (!first) out += ",";
        out += kv.second;
        first = false;
    }
    return out + "]";
}

std::string JeemoNetImpl::requests()
{
    std::string out = "[";
    bool first = true;
    for (const auto& kv : m_requests) {
        if (!first) out += ",";
        out += kv.second;
        first = false;
    }
    return out + "]";
}

int64_t JeemoNetImpl::clearAll()
{
    m_menus.clear();
    m_ratings.clear();
    m_requests.clear();
    ++m_revision;
    save();
    stateChanged(m_revision);
    return 1;
}

// ── Local history ────────────────────────────────────────────────────
//
// Messaging delivers what is published while you are listening; it is not a
// database. A laptop switched off overnight would come back blank, so the
// merged state is mirrored to one file and reloaded on start. One message per
// line, exactly as it arrived.
//
// Codex is the right home for this the moment history needs to be shared
// between machines rather than merely survive a restart on one.

std::string JeemoNetImpl::storePath() const
{
    // Two instances on one laptop must not share a history file, or the
    // second one loads the first one's menus off the disk and the test
    // proves nothing about the network.
    const char* override = std::getenv("JEEMO_STORE");
    if (override && *override) return std::string(override);

    const char* home = std::getenv("HOME");
    if (!home || !*home) return "jeemo-state.jsonl";
    const std::string dir = std::string(home) + "/.local/share/jeemo";
    ::mkdir((std::string(home) + "/.local").c_str(), 0755);
    ::mkdir((std::string(home) + "/.local/share").c_str(), 0755);
    ::mkdir(dir.c_str(), 0755);
    return dir + "/state.jsonl";
}

void JeemoNetImpl::save()
{
    std::ofstream f(storePath(), std::ios::trunc);
    if (!f) return;
    for (const auto& kv : m_menus)   f << kv.second << "\n";
    for (const auto& kv : m_ratings)  f << kv.second << "\n";
    for (const auto& kv : m_requests) f << kv.second << "\n";
}

void JeemoNetImpl::load()
{
    std::ifstream f(storePath());
    if (!f) return;
    std::string line;
    while (std::getline(f, line)) {
        if (line.empty()) continue;
        if (!takeMenu(line) && !takeRating(line)) takeRequest(line);
    }
}

// ── Plumbing ─────────────────────────────────────────────────────────

void JeemoNetImpl::setStatus(int64_t status)
{
    if (m_status == status) return;
    m_status = status;
    deliveryStatusChanged(status);
}
