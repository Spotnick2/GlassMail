# GlassMailbox plan

What is built, in what order. The features are defined in [FEATURES.md](FEATURES.md). The plan was
reviewed adversarially with Codex (gpt-6-astra, high effort) over three rounds, to consensus; the
review's main corrections are listed at the end.

## Milestones

- **M0: skeleton and probe** *(done)*.
  - The addon boots, has `/gmail`, an options page and a first glass pass on the mail windows.
  - Repository tooling: tests, deploy, `.pkgmeta`, CI.
  - `Tools/MailProbe` is run on the live client and its results recorded in
    [FOREVER-PROBE.md](FOREVER-PROBE.md). **No feature code before the
    measurements its design depends on.** Items still open are listed with the milestone that
    must measure them (FOREVER-PROBE.md, "Still open").
- **M1, first release** *(in progress, #4)*: the mail core (`Core/Scan.lua`, `Core/Ops.lua`,
  `Core/Loot.lua`), the skin finished in clear and smoked glass, I1, I2, I3, X3, with the operation
  records that confirm each action succeeded. Five PRs: look → probe session 5 → core + I1 →
  I2 + I3 → X3 + v0.1.0. See "M1" below.
- **M2:** S1 (picker; registry from local characters and AltStable), local X1, I4, the X2 history UI,
  and `Core/Summary.lua` / `Core/Names.lua`, which have their first consumers here.
- **M3, reuse:** `Scan` / `Summary` / `Names` move out into `C:\Projects\WoW\LibMailbox`
  (`LibMailbox-1.0`, LibShowcase's layout, upgrade tests). An AltStable PR adopts it in the same
  round, keeping AltStable's `mail_*` fields. The loot and send queues stay here unless a second
  addon needs them.
- **M4:** N1 bank character (`Core/Send.lua`, one Send click per batch), N2 local return assistance.
- **Later:** cross-account N2 over LibAccountSync, shared-settings sync, merged autocomplete, Forward.

## M1 (reviewed with Codex, 4 rounds, consensus)

- **Look.** `skin` = clear / smoked / stock, switched live (see Skin.lua). Choices on the options
  page are radio groups.
- **Identity.**
  - A fingerprint covers sender, subject, money, COD, `wasReturned`, and each slot's item
    *link* × count. It leaves out `daysLeft`.
  - A missing link makes the fingerprint unresolved: nothing is dispatched against that mail, and
    no scan containing it confirms anything.
  - A remembered target (a selection, a residual) is acted on only when exactly one mail matches.
    Two identical mails are not interchangeable: expiry, read state, letter text and variants can
    differ. A twin's checkbox is disabled.
- **`Core/Ops.lua`, the one operation owner** for Open All, Open selected, Return selected and the
  row icons.
  - **Foreign calls.** `TakeInboxItem`, `TakeInboxMoney`, `AutoLootMailItem`, `ReturnInboxItem`
    and `DeleteInboxItem` are post-hooked, with a flag marking our own calls. A foreign call
    cancels the run.
  - **One attempt at a time,** with the residual fingerprint it expects. Success means the
    before-count fell by one **and** the residual count rose by one, or the mail is gone; "gone"
    alone proves nothing.
  - **Unrelated updates** neither confirm nor overwrite an attempt.
  - **5 s unresolved** stops the run as uncertain.
  - **Failures.** A failed item joins the skip set. A failed money take, Return or Delete stops the
    run.
- **`Core/Loot.lua`, what to take.**
  - Money first.
  - Then each attachment, if it fits: in partial stacks, in specialty slots of a matching family,
    or in general slots above `keepFree`. Unknown means skip.
  - **Refill** is for Open All only: one `CheckInbox` in flight, a 10 s completion deadline, and a
    stop on unchanged contents or after 3 refills. It ships only if session 5 sees `total > loaded`.
- **After probe session 5** (2026-10-10, FOREVER-PROBE.md):
  - Return selected ships as "Return next (n left)", one click per mail: several returns in a row
    weren't measured. Returnable means `not InboxItemCanDelete(i)`, as Blizzard decides it.
  - Refill isn't in v0.1.0 (no overflow seen); Open All stops at the loaded window.
  - Our controls disable in combat and a run stops; combat wasn't measured.
  - X3 has no minimap item: Blizzard hides the icon once every mail is read.
  - Loot: a specialty-bag item goes to the specialty bag first; slots keep their numbers.
- **Probe session 5** (what was asked of it):
  - the AH subject strings and Postmaster fields;
  - several timed returns;
  - money with several attachments, step by step;
  - partial stacks, unique items and locked slots;
  - the specialty-bag reserve boundary;
  - overflow past 100 mails;
  - row controls parented to InboxFrame, in combat;
  - `HasNewMail` and the minimap icon.

## The mail core (M1)

In `Core/`, shaped like a library but not published as one until M3. (Superseded where the M1
section above differs: `Summary` and `Names` moved to M2.)
- **`Scan()`** returns a plain-value snapshot:
  - header `{guid, name, at, loaded, total, complete}`;
  - each mail `{index, sender, subject, money, cod, daysLeft, wasRead, wasReturned, canReply, isGM,
    type, items}`, `type` parsed from the `AUCTION_*_MAIL_SUBJECT` globals;
  - each item `{slot, itemID, link, count, isCurrency}`.
- **`Summary(snapshot)`** reproduces AltStable's rule exactly (`AltStable/Core.lua` `ScanMail`):
  count only mail with items or money and positive days left, round expiry down to the minute, and
  return empty when there is nothing so the stored fields are cleared.
- **Engines** (`Loot`, later `Send`) have one owner at a time, track their own attempt and match it
  against `MAIL_SUCCESS` / `MAIL_FAILED` / `MAIL_SEND_SUCCESS`. They stop when the mailbox closes and
  re-check their target after every inbox change.
- **`IsSendable(bag, slot)`** answers yes / no / unknown with a reason, never an unconditional yes.

## Probe checklist (M0, `/mailprobe`)

Each item goes in FOREVER-PROBE.md with what was seen.

1. **Lifecycle:** which of `MAIL_SHOW`, `PLAYER_INTERACTION_MANAGER_FRAME_SHOW`/`HIDE` (MailInfo),
   `MAIL_CLOSED` and `PLAYER_LEAVING_WORLD` fire, in what order, and whether any fire twice.
   *(passive: open and close a mailbox; walk away; log out at one)*
2. **Inbox identity and capacity:** loaded vs total counts, `CanCheckInbox` refill, index shifts on
   new mail or partial loots, identical duplicate mails, returned mail, an inbox update while a
   confirmation is open. *(`state`, `inbox`, `dupes`)*
3. **Looting:** stack limits, item variants, unique items, locked slots, unknown item info,
   specialty bags, the free-slot reserve boundary, money with full bags, skipped mail filling the
   loaded window, `MAIL_FAILED` payloads. *(`take`, `money`, `bags`)*
4. **Batch actions:** do `TakeInboxItem` and `ReturnInboxItem` work from a timer after one key
   press? This decides whether I2's batch Return needs a click per mail. *(`taketimer`,
   `returntimer` on a test mail)*
5. **Open All ownership:** hide the stock button, then trigger it from a gamepad; does
   `C_Mail.SetOpeningAll(false)` follow its `OnHide`? *(`hidestock`, passive `C` lines)*
6. **Sending:** an existing draft, editing the recipient, attachment readiness, splitting a stack
   to attach part of it, postage failure, bind/refund prompts, accepting or cancelling the
   secure-transfer dialog, event order around the draft reset. *(`draft`, `split`, `sendnow`,
   `sendtimer`)*
7. **Taint:** our row controls, a custom Open All, the picker then Send, entering and leaving
   combat. Watch for `!` lines (`ADDON_ACTION_BLOCKED` / `_FORBIDDEN`), not only Lua errors.
   *(`rows on`, `picker NAME`)*
8. **Data:** sender string formats (players, AH, Postmaster, localized), secret values in the fields
   we read, whether `GetInboxText` marks mail as read. *(`inbox`, `readtest`)*

Deferred until their features come up: autocomplete-source then Send; whether a subject suffix
token survives a round trip; splitting a stack into an attachment and `SendMail` from a timer
(M4). The gamepad path of item 5 can't be tested (no gamepad).

**M0 probe status:** what M1's design depends on is measured (FOREVER-PROBE.md sessions 1-4).
The remaining items are in FOREVER-PROBE.md's "Still open" table. Each is measured before the
feature that depends on it ships.

## Review outcome (Codex, 2026-10-09)

Accepted: the mail core stays in this repo until AltStable adopts it (no library before a second
consumer); a picker instead of an autocomplete hook; no row-click takeover; Open All ownership
measured; no promise of stable mail IDs; N2 reduced to local return assistance; the registry is
local characters plus live AltStable, keyed by GUID, with reachability data; snapshots carry
completeness; queue success is matched to our own attempt; a Send click, and Blizzard's confirmation whenever it shows,
are always required; a wider probe; milestones reordered; no code copied from the references.
