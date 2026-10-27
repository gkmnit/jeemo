# Jeemo

Everyone eats together. Nobody can say anything about it.

Jeemo is a dining-room feedback loop with no server in it: the kitchen puts up
each meal, the people eating rate individual dishes and ask for things, and the
kitchen sees what is actually worth cooking again. Built for the Logos and
Zu-Grama Field Station in Rajasthan, India.

## The problem

Hostels, residencies, offices, offsites, canteens, co-living houses. Anywhere a
group eats food somebody else cooks, the same five things are missing.

**Nobody knows what is coming.** No menu anywhere, or one pinned up where half
the people never walk past. You find out what lunch is by arriving at lunch.

**Nobody knows what is in it.** What went into the dish, whether it has nuts,
whether it is veg today. The only way to find out is to find the cook and ask,
every single time.

**There is no way to say what you thought.** The loudest person at the table
gets heard. Everybody else eats quietly and says nothing, so a dish most of the
room disliked comes back next week.

**There is no way to ask for anything.** No curd, too much chilli, something
without onion. You either chase down the manager or you let it go.

**If you do ask, you never hear back.** You have no idea whether anyone wrote it
down, whether it is happening, or whether you should ask again.

And from the other side, the kitchen is just as blind. The cook has no idea
which dishes landed, which fell flat, what has been asked for twice already, or
what people want more of. Months of cooking and no record of any of it.

## The name

**Jeemo** comes from *jeeman*, which in Rajasthani means eating together as a
community. *Jeemo* is the invitation: eat. The idea started at the Logos and
Zu-Grama Field Station in Rajasthan, where twenty-odd people ate together three
times a day for nine days, and every one of the problems above showed up by the
second meal.

## What Jeemo does

Three screens, and whichever ones a place needs.

**In the kitchen.** Put up each meal, dish by dish, with a description,
ingredients and how it is made. Dishes cooked before come back with one tap and
carry their history with them. After the meal, see exactly how each dish
landed: a score out of five, how many wanted more, and what people wrote.
Across days, see what is worth cooking again and what should be retired.

**Outside the dining room.** A screen showing today's meals in large type, with
what is in each dish and how it was made, rotating through the day. And a panel
showing what the kitchen has agreed to do about what people asked for, so the
answer finds you instead of you chasing it.

**At the table, or on your own machine.** Rate each dish with one tap, write a
note if you want to, and ask the kitchen for something, attached to a particular
dish or meal so it means something. Then hand the tablet on, and it forgets you
completely.

### What makes it different

**No server.** There is nothing to host, nothing to pay for, nobody who owns the
data. The machines pass messages to each other directly and each keeps its own
copy. Unplug the internet and it still works across the building.

**Nothing is traceable to you.** A rating carries no identity at all, and the
one-time tag on it is thrown away the moment the tablet is handed on. A request
carries no name either. That rule lives in the networking layer, not in the
screens, so no future screen can quietly break it.

**You cannot be singled out.** A dish's breakdown stays hidden until three
people have answered it. In a group of twenty, one visible complaint is an
identified complainer.

**History is honest.** A dish's ratings belong to its name. Reusing a dish
brings it back exactly as it was, and changing the recipe means giving it a new
name, so last month's scores never quietly come to mean something else.

## How it is built

Built on the pattern from
[logos-shared-color](https://github.com/hackyguru/logos-shared-color):
one `core` module in C++ that owns the delivery node, and `ui_qml` modules
that call into it through `logos.callModule`. UI modules are sandboxed away
from the network in Basecamp, so this split is not a style choice.

The core is written in the **universal** authoring model, which the module
builder now requires of any core module shipping a plugin. That means
`src/jeemo_net_impl.h` is the entire contract: its public methods are the
module's API, and the Qt plugin, the `.lidl`, the C-ABI wrapper and the event
glue are all generated from it. There is no hand-written interface or plugin
pair, and no Qt in the module's own code.

The shared-color tutorial predates this and still uses the older hand-written
path, so its `metadata.json` has no `interface` field. Copying it verbatim
today fails at evaluation with a message naming exactly that.

## What this actually uses

| Logos pillar | Module | Used? |
| --- | --- | --- |
| Messaging | `delivery_module` | yes, for every menu, rating and request |
| Storage | Codex | no |
| Blockchain | Nomos | no |

History is a plain JSON-lines file written by `jeemo_net` to
`~/.local/share/jeemo/state.jsonl`, one message per line, or wherever
`JEEMO_STORE` points. It exists only so a machine that was switched off does
not come back blank, because messaging delivers what is published while you
are listening and is not a database. Moving it to Codex is the first thing to
do if history should be shared between machines rather than merely survive a
restart on one, and it is the same change that would carry dish photographs.

## The four modules

| Module | Type | Runs where |
| --- | --- | --- |
| `jeemo_net` | core | every machine. All the networking and all the state. |
| `jeemo_chef_ui` | ui_qml | the chef or manager. Put up meals, read what came back. |
| `jeemo_board_ui` | ui_qml | the screen outside the dining room. Read only. |
| `jeemo_guest_ui` | ui_qml | a resident's own Basecamp, or the tablet on the table. |

Install `jeemo_net` first on every machine, then whichever screens that
machine needs. A machine may carry more than one.

## How it moves

```
          /jeemo/1/menu/json                /jeemo/1/rating/json
  chef  ──────────────────────▶  everyone     everyone ◀────────────  guest
  board ◀──────────────────────               chef    ◀────────────
```

Two content topics, named per LIP-23. Everyone subscribes to both; what a
screen does with them is the only difference between the three UIs.

`jeemo_net` holds the merged state and settles conflicts the same way on
every machine, so the three screens agree without talking to each other
directly:

- **Menus: last write wins per `menuId`**, which is `<day>-<meal>`. Re-posting
  dinner replaces dinner everywhere. Ties on timestamp break by sender id, so
  every peer picks the same winner.
- **Ratings: last write wins per `nonce`.** One answer per person per dish.
  A later message under the same nonce is that person changing their mind or
  adding a note, not a second vote.
- **`itemId` is a slug of the dish name**, stable across days. That is what
  makes "cooked four times, liked three" possible with no central id service.

## Privacy, and why it is in the core

The `nonce` on a rating is a random string generated for whoever is holding
the tablet, joined to the dish's id so that one person's answers to different
dishes stay separate: `k7f3a91c2-laal-maas`. The random half is thrown away
when the tablet is handed on, so nothing links one visitor's answers to the
next one's. It exists so duplicates can be dropped, nothing more, and it must
never be derived from a device id, a key, or anything that survives a reset.

`publishRating` in the core deliberately does **not** attach the sender id,
though `publishMenu` does. A menu is a public act by the cooks; a rating is
not. Putting this in the core rather than in each UI means a new screen cannot
get it wrong later.

The chef UI holds back a dish's breakdown until three people have answered it.
In a group of twenty, one visible critic is an identified critic.

## Reviews carry their rating

A written note travels inside the same message as that person's rating, so
the chef screen shows them together: each note is labelled *wanted more*,
*said it was fine*, or *not for them*, in the colour of that verdict.

Without it the notes mislead. "Too much chilli" from someone who wanted more
of the dish is praise; the same four words from someone who left it are not,
and the words alone cannot tell you which.

## Messages

```json
{
  "v": 1, "type": "menu",
  "menuId": "2026-10-25-dinner",
  "day": "2026-10-25", "meal": "dinner",
  "note": "At the fire, from 8",
  "items": [
    { "itemId": "laal-maas", "name": "Laal Maas",
      "description": "Mutton in Mathania chillies and yoghurt.",
      "tags": ["non-veg", "spicy"] }
  ],
  "at": 1792840000
}
```

```json
{
  "v": 1, "type": "rating",
  "menuId": "2026-10-25-dinner",
  "itemId": "laal-maas",
  "score": 2,
  "comment": "More of this please",
  "nonce": "k7f3a91c2-laal-maas",
  "at": 1792841000
}
```

`score` is 2 wanted more, 1 fine, 0 did not like it.

## What the core exposes

Everything returns a value or a JSON string; `Link.qml` normalises both.

| Method | Does |
| --- | --- |
| `startDelivery()` / `stopDelivery()` | node lifecycle |
| `deliveryStatus()` | 0 off, 1 connecting, 2 connected, 3 error |
| `publishMenu(json)` / `publishRating(json)` | send one message |
| `menus()` / `ratings()` | the merged state, as JSON arrays |
| `revision()` | one integer that moves on any change |
| `peerInfo()` | role and ports, for wiring the next machine |
| `clearAll()` | wipe local state. Demos only. |

The UIs poll `revision()` once a second and only pull the lists when it moves,
so an idle board costs one small call per second rather than two full reads.

## Sidebar icons

Each UI module carries its own, named in its `metadata.json`:

```json
"icon": "icons/chef.png"
```

The file is a 128x128 PNG inside the module, and the name is what Basecamp
shows in the sidebar next to it. Change either and rebuild that module; the
icon is baked into the `.lgx` at build time, so editing the PNG in an
installed plugin folder does nothing.

A module installed by hand rather than built refers to its icon from
`manifest.json` instead, usually as `assets/icon.png`.

## The core's files

```
jeemo-core/
  metadata.json          "interface": "universal", depends on delivery_module
  CMakeLists.txt
  src/jeemo_net_impl.h   the whole API. Public methods are the contract.
  src/jeemo_net_impl.cpp merge rules, delivery calls, local history
  src/jeemo_json.h       a 120-line reader for the six top-level fields
```

`jeemo_json.h` exists because module code in this model is Qt-free, and the
core only ever reads `type`, `v`, `menuId`, `nonce`, `at` and `from` off the
top level of a message. It never walks into the items array; that is the UI's
business. Messages are stored and re-sent byte for byte as they arrived, so a
field added by a newer UI survives a hop through an older core untouched.

## Build

Nix with flakes. The first build pulls the whole `logos-delivery-module`
closure, so allow 15 to 30 minutes. Later builds take seconds.

```bash
cd jeemo-core
nix flake update                                  # first time only
nix build '.#lgx-portable' --out-link result-portable

cd ../jeemo-chef-ui
nix build --override-input jeemo_net path:../jeemo-core \
  '.#lgx-portable' --out-link result-portable

cd ../jeemo-board-ui
nix build --override-input jeemo_net path:../jeemo-core \
  '.#lgx-portable' --out-link result-portable

cd ../jeemo-guest-ui
nix build --override-input jeemo_net path:../jeemo-core \
  '.#lgx-portable' --out-link result-portable
```

Each build leaves an `.lgx` at `result-portable/*.lgx`. In Basecamp, open
**Modules → Install LGX Package**. Install `jeemo_net` first, then the UI.
`delivery_module` is already in Basecamp.

## Running it on more than one machine

Each node needs its own ports and its own key. Everything that varies per
machine is an environment variable, so no machine needs a different build.

```
JEEMO_ROLE      chef | board | guest   picks sane defaults for ports and key
JEEMO_TCPPORT   override the TCP port
JEEMO_UDPPORT   override the discv5 UDP port
JEEMO_NODEKEY   32-byte hex libp2p key
JEEMO_PEERS     comma-separated multiaddrs to dial directly
```

### Two instances on one machine, to try it

```bash
JEEMO_ROLE=chef  ./LogosBasecamp &
JEEMO_ROLE=guest ./LogosBasecamp &
```

The chef defaults to TCP 60000 and the guest to 60001, and each lists the
other in `staticNodes` over loopback, so they find each other without
depending on any bootstrap fleet.

Kill leftovers between runs, or a stale host holds the old libraries:

```bash
pkill -9 -f LogosBasecamp; pkill -9 -f logos_host
```

### Three machines on one network

The bundled `logos.dev` bootstrap peer IDs have been stale upstream, which is
why the shared-color tutorial pins static nodes rather than trusting
discovery. Do the same here: start one machine, read its PeerID out of the
Basecamp log, and list it on the others.

```bash
# on the chef's laptop, at 192.168.1.10
JEEMO_ROLE=chef ./LogosBasecamp

# on the board and on each resident's machine
JEEMO_ROLE=board \
JEEMO_PEERS=/ip4/192.168.1.10/tcp/60000/p2p/<chef PeerID> \
  ./LogosBasecamp
```

Every peer reaching the chef's machine is enough; gossipsub relays the rest.

## Why history is stored locally

Messaging delivers what is published while you are listening. It is not a
database. A laptop switched off overnight would come back blank, so
`jeemo_net` mirrors its merged state to one JSON file under the application
data directory and reloads it on start.

Codex is the right home for this the moment history needs to be shared
between machines rather than merely survive a restart on one, and it is also
the answer for dish photographs, which are far too large to put inside a
message. Neither is wired up here.

## Not done

- **Photographs.** The data model has room for them. They belong in Codex with
  only the reference travelling in the message.
- **Shared history.** A machine that was never switched on sees only what is
  published from then onwards.
- **Rating windows are enforced in the UI**, not in the core. A hostile peer
  could post a rating at any hour. That is the right trade for a residency
  dining room and the wrong one for anything larger.
