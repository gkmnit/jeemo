#pragma once

#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "logos_module_context.h"

/**
 * Jeemo's networking and its memory.
 *
 * In the universal authoring model this class is the whole module: its public
 * methods ARE the API, and the Qt plugin glue is generated from this header.
 * Module code is Qt-free, so everything here is std::.
 *
 * The three UI tabs are sandboxed and cannot open a socket. They call in here
 * through logos.callModule, and this class owns the delivery node, both
 * content topics, the merge rules and the stored history.
 *
 *   /jeemo/1/menu/json    meals the chef puts up
 *   /jeemo/1/rating/json  what people thought of each dish
 *
 * Menus are last-write-wins per menuId. Ratings are last-write-wins per
 * nonce, so a person can change their mind or add a note without being
 * counted twice. Both rules live here rather than in each UI, so a fourth
 * screen written later cannot get them subtly different.
 */
class JeemoNetImpl : public LogosModuleContext
{
public:
    /// Brings the delivery node up and subscribes to both topics.
    /// Returns 1 on success, 0 on failure.
    int64_t startDelivery();

    /// Takes the node down. Returns 1.
    int64_t stopDelivery();

    /// 0 off, 1 connecting, 2 connected, 3 error.
    int64_t deliveryStatus();

    /// Role and ports, for wiring up the next machine.
    std::string peerInfo();

    /// Sends one menu. `json` is a single JSON object; see README.
    int64_t publishMenu(const std::string& json);

    /// Sends one rating. Deliberately attaches no sender id.
    int64_t publishRating(const std::string& json);

    /// Sends one request from a resident to the kitchen, or the kitchen's
    /// update marking one handled. Also carries no sender id.
    int64_t publishRequest(const std::string& json);

    /// The merged state, as JSON arrays.
    std::string menus();
    std::string ratings();
    std::string requests();

    /// Moves on every change to either list. The UIs poll this one cheap
    /// number and only pull the full lists when it has moved.
    int64_t revision();

    /// This node's own id. Used on menus, never on ratings.
    std::string myId();

    /// Wipes local state and the file behind it. Demos, not service.
    int64_t clearAll();

    /// Arms the delivery subscriptions once the module is wired up.
    void onContextReady();

logos_events:
    /// Carries the new revision. A UI may subscribe instead of polling.
    void stateChanged(int64_t revision);

    /// 0 off, 1 connecting, 2 connected, 3 error.
    void deliveryStatusChanged(int64_t status);

private:
    int  takeMenu(const std::string& json);
    int  takeRating(const std::string& json);
    int  takeRequest(const std::string& json);
    int  sendOn(const std::string& topic, const std::string& payload);
    void setStatus(int64_t status);

    void load();
    void save();
    std::string storePath() const;

    std::string m_myId;
    std::string m_peerInfo;

    std::map<std::string, std::string> m_menus;    // menuId -> raw JSON
    std::map<std::string, std::string> m_ratings;  // nonce  -> raw JSON
    std::map<std::string, std::string> m_requests; // id     -> raw JSON
    int64_t m_revision = 0;

    int64_t m_status        = 0;
    bool    m_started       = false;
    bool    m_subscribed    = false;
    bool    m_createNodeDone = false;
    bool    m_armed         = false;
};
