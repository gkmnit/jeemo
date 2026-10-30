# Threat model and known limits

Jeemo collects opinions about food from people who often cannot leave the place
serving it. That is the whole reason this document exists. If someone can work
out who said what, the honest answers stop and the product is worthless.

This is a short document on purpose. A small threat model is a sign of a small
attack surface, and everything here is written down rather than only said out
loud.

## What the system holds

Three kinds of message travel between machines, and each machine keeps its own
copy of all of them in a plain file on disk.

| Message | Fields | Carries a sender? |
| --- | --- | --- |
| Menu | day, meal, dish names, description, ingredients, method | Yes, the kitchen's node id |
| Rating | dish name, score out of three, optional note, random nonce, timestamp | **No** |
| Request | dish or meal it attaches to, text, random nonce, timestamp | **No** |

The nonce on a rating is random, generated per visitor, and discarded when the
tablet is handed to the next person. It exists only to stop one person's rating
being counted twice, and it is never linked to anything else.

There is no account system, no profile, no phone number, no email and no login.

## Who we are protecting, and from whom

**The person eating, from the person cooking.** This is the primary case. In a
house of thirty, a visible complaint identifies the complainer in about a
minute, and after that nobody complains again.

**The person eating, from the operator.** In a hostel, shelter or ward, the
organisation being rated also controls the person's housing, care or job.

**Everyone, from a future operator.** Data collected today should not become
leverage later, when the building changes hands.

We are explicitly **not** trying to defend against a determined state-level
adversary with network-wide visibility. That is not the threat in a dining room.

## What an attacker cannot get

- **No identity on a rating or a request.** There is nothing to deanonymise,
  because nothing identifying was ever attached.
- **No central store.** There is no server, so there is no single database to
  breach, subpoena, sell or lose in an acquisition.
- **No credentials.** There are no accounts, so there is nothing to phish and no
  password to reset.
- **No small-number exposure.** A dish shows no breakdown at all until three
  people have answered. This rule lives in the core module, below every screen,
  so a screen written next year cannot quietly remove it.

## What an attacker can still do today

These are real and unfixed. They are listed here so that nobody has to discover
them.

1. **Messages are not signed.** Anyone who can reach the content topics can
   publish to them. A stranger could post a fake menu, or stuff ratings to move
   a score. Message signing with a kitchen key is the first security item on the
   roadmap, after storage.
2. **The local history is a plain file.** Anyone with access to a machine can
   read every message that machine has seen. The file contains no identities,
   but it does contain the full set of ratings and requests.
3. **Someone can watch you tap.** This is a social problem rather than a
   cryptographic one. The mitigation is that the tablet is passed around and
   holds no state between people.
4. **Timing can narrow things down.** If one person eats long after everyone
   else, a rating arriving at that moment is more attributable. We do not
   currently add any delay or batching.
5. **A malicious client can ignore the rating windows.** Those windows are
   enforced in the screens, not in the core module.

## Known limits, not security related

- **No photographs and no voice.** Both need the Codex storage layer, which is
  not wired up. This is the single largest gap in the product.
- **Peer discovery is manual.** The bundled bootstrap peer identifiers are stale
  upstream, so peers are configured by hand for now.
- **The screens look like a developer tool**, because they are drawn inside
  Logos Basecamp's own frame.
- **Installation is manual.** Signed releases need a signing key we do not have.
- **No automated test suite.** The core path has been verified by hand across two
  independent nodes with separate stores on disk, and that test is described in
  the README, but it is not yet scripted.

## What we would do next, in order

1. Sign every message with a kitchen key, so a stranger cannot publish a menu.
2. Move the rating windows from the screens into the core module.
3. Encrypt the local history at rest.
4. Write the two-node test as a script that runs in CI.
5. A self-audit against this document, once storage and signing are in.

## Reporting a problem

Open an issue at https://github.com/gkmnit/jeemo/issues. If the issue is a
security one and you would rather not post it publicly, say so in an issue with
no detail and we will find another channel.
