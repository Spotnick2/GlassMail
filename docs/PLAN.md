# GlassMail plan

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
- **M1, first release** *(done, #4; v0.1.0)*: the mail core (`Core/Scan.lua`, `Core/Ops.lua`,
  `Core/Loot.lua`), the skin finished in clear and smoked glass, I1, I2, I3, X3, with the operation
  records that confirm each action succeeded. Five PRs: look → probe session 5 → core + I1 →
  I2 + I3 → X3 + v0.1.0. See "M1" below.
- **M2** *(done, #17; v0.2.0, released 2026-11-12; the owner runs its in-game gate as they play,
  "The grid PR in detail")*: S1 (picker and last-recipient fill; registry from local characters and AltStable), local X1, I4, the X2 history UI,
  and `Core/Summary.lua` / `Core/Names.lua`, which have their first consumers here. After it, the
  To box's completion ("S1: completing a name as you type").
- **M3, reuse** *(done, #46; LibMailbox r1, GlassMail #47, AltStable #329)*: `Scan` / `Summary` / `Names` move out into `C:\Projects\WoW\LibMailbox`
  (`LibMailbox-1.0`, LibShowcase's layout, upgrade tests). An AltStable PR adopts it in the same
  round, keeping AltStable's `mail_*` fields. The loot and send queues stay here unless a second
  addon needs them.
- **M4** *(in progress, #50)*: N2 local return assistance first ("N2: recall", below; v0.3.0),
  then N1 bank character ("N1: the bank character", below: `Core/Bank.lua`, one Send click per
  batch; probe session 7 first).
- **Later:** cross-account N2 over LibAccountSync, shared-settings sync, Forward.

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
- **PR 3, core + I1** (implementation plan reviewed with Codex, 4 rounds, consensus,
  2026-10-11):
  - **Twins in Open All are taken.** Open All has no remembered target: each dispatch takes the
    mail a fresh scan finds eligible now. A wrong credit between twins only skews the summary.
    The unique-match rule stays for remembered targets (PR 4's selection and Return).
  - **"Gone" needs the loaded count to fall too,** besides the fingerprint's count. A mail emptied
    by its last take may also stay, empty, when it has letter text (Blizzard deletes such a mail
    itself on closing the letter, MailFrame.lua:581): its empty residual confirms too (PR 9 review).
  - **Secrecy first:** every header and attachment value is checked with `issecretvalue` before any
    comparison or copy; such a mail is kept unresolved, with no values (PR 9 review).
  - **Fingerprints are length-prefixed** fields, so delimiters can't merge two mails.
  - **`MAIL_FAILED` with no itemID** (the API allows it) on an item stops the run as uncertain;
    only a real ID joins the skip set. A failed money take stops the run.
  - **Bags:** locked stacks offer no room; after an item, the next waits for a
    `BAG_UPDATE_DELAYED` since its dispatch, or 1 s. Bags 0-4 only: the reagent bag is unmeasured.
  - **"System mail"**, not "Postmaster": not AH and can't be replied to (or GM). Returned mail can
    be replied to, so it's player mail.
  - **Resolve on `MAIL_INBOX_UPDATE` only**; `OnUpdate` drives the deadline and the dispatch gate.
  - **Gamepad UI mode:** Blizzard drives its own Open All from a footer binding. We leave it alone
    there and don't offer ours; the stock button is hidden from an `OnShow` hook only in mouse
    mode, so its re-show on a mode change is caught whatever the callback order. Any
    `INPUT_DEVICE_INTERFACE_TRANSITION` stops our run, and each dispatch re-checks the mode.
    Reasoned, not measured (no gamepad).
  - **Cut:** the options-page copy of the filters (the right-click menu only), the invoice check
    (the six templates classify AH mail), per-frame rescans, repeated skip counting (tallied once
    at the end).
- **PR 4, I2 + I3** (implementation plan reviewed with Codex, 3 rounds, consensus,
  2026-10-12):
  - **Nothing runs while a letter is open**, Open All included: Blizzard keeps the open letter as
    a bare index, re-read on every inbox update, and closing it may delete the mail at that index
    (MailFrame.lua:146, 581). A letter opened mid-run stops the run. **Known limit:** the one action
    already sent can't be recalled; Blizzard's own Open All and shift-click leave the same window,
    and a stock row click is never blocked. Closing the letter from our code is worse (its OnHide
    deletes by a possibly stale index).
  - **Row icons need a unique fingerprint**, as the checkboxes do: a twin can shift into the
    clicked index before the paced dispatch.
  - **During Open (n) the run owns the selection:** its targets move to their residuals inside
    Ops, and the checkboxes show that live set, because Blizzard's `InboxFrame:Update` runs before
    Ops confirms on the same `MAIL_INBOX_UPDATE`. What is left becomes the selection at the end.
  - **Open (n) ignores the type filters** (the player chose the mails); COD and GM mail are still
    left, `keepFree` still applies.
  - **Cut:** a tooltip rebuild on `GET_ITEM_INFO_RECEIVED` (Blizzard's row `OnUpdate` rebuilds the
    tooltip every frame, MailFrame.xml:160).
- **PR 5, X3 + v0.1.0** (implementation plan reviewed with Codex, 4 rounds, consensus,
  2026-10-13):
  - **Trade block = the `blockTrades` CVar** while the mailbox is open (closing the trade window on
    `TRADE_SHOW` would undo an accept the player made, and the request popup comes first). One
    rule, re-run on every change: blocked while the mailbox is open and the setting is on. Only our
    own block is ever undone: our writes are marked (`CVAR_UPDATE` is synchronous), and a change we
    didn't make ends the claim; an "off" made during a visit lasts until it closes. Nothing is
    written in combat; the rule re-runs when combat ends. A per-character claim undoes a block left
    by a session that ended uncleanly (best effort: built-in CVar persistence is unmeasured).
  - **Gold collected** counts only money Ops confirmed, over every run of the visit; manual takes
    aren't counted (no `GetMoney`).
  - **New-mail alert** is "the latest senders changed while you're away", not per arrival: a
    sender list isn't an arrival ID. Mail seen at the mailbox isn't announced afterwards.
  - **Cut:** petition blocking (it means unregistering a Blizzard frame's event).
- **Probe session 5** (what was asked of it):
  - the AH subject strings and Postmaster fields;
  - several timed returns;
  - money with several attachments, step by step;
  - partial stacks, unique items and locked slots;
  - the specialty-bag reserve boundary;
  - overflow past 100 mails;
  - row controls parented to InboxFrame, in combat;
  - `HasNewMail` and the minimap icon.

## M2 (reviewed with Codex, 5 rounds, consensus; #17. The last-recipient fill: 2 more rounds, 2026-11-06)

The memory milestone: S1, X2, X1, I4, and `Core/Names` / `Core/Summary`. Research behind it
(2026-10-13): Blizzard's send path (MailFrame.lua:1251-1278, 145-183), the secure-transfer UI
(Blizzard_SecureTransferUI.lua:110-124, 288-304), AltStable's public API (PublicAPI.lua, v1) and
its mail rule (Core.lua:2717-2772), the API dump, and FOREVER-PROBE sessions 2-3 (a send confirmed
4.3 s, ~15 s and 99 s after `SendMail`; the picker's `SetText` then Send worked for an alt).

**What the owner wants most** (2026-10-13): "where did I just send that?" without a tour of every
alt. The window is organised like Gmail: **Inbox** (every character's mailbox), **Sent**, and
**Trash** (deleted mail, kept until it would have expired, then gone by itself). Drafts and Spam are
later ideas, not M2.

### The rule for everything saved: it ends by itself (owner, 2026-10-13)

Lists that only grow (Prat's dead characters) are out. Every saved list has an end of life and
needs no cleanup pass:
- **Live, never saved:** friends (`C_FriendList`), the guild roster (`GetGuildRosterInfo`), and
  AltStable's characters. Read when the picker or window opens.
- **A play-day clock.** `GlassMailDB.playDay` counts the calendar days on which any character of
  the account played. The local date is checked at `PLAYER_LOGIN`, before any record is written or
  pruned, and on a 10-minute ticker; the counter advances at most once per date, so a session over
  midnight counts both days. Ages that should survive a break are in play days: months away change
  nothing.
- **Setting `expiryDays`** (default 30 play days; choices 7 / 14 / 30 / 60 / 90): a recent
  recipient not sent to, an own character not played, and a Sent record, that many play days old,
  are dropped (at login and on the date change).
- **Setting `recentMax`** (default 20; choices 10 / 20 / 50): the oldest recent recipient goes.
- **Real-time ends for real-time things:** mail expires whether you play or not. A snapshot's
  expired mails (`expires < time()`) are dropped from it; the snapshot itself ends with its
  character (the window PR, below). A Trash entry goes when the mail it held would have expired.
- **A snapshot goes with its character** (aged out of the registry). AltStable's "forget" is not
  mirrored: absence from `GetCharacters()` can't be told from "never known" (a fresh AltStable),
  and a lost snapshot costs a mailbox visit, a wrong one costs trust.
- **Every row in the window has a forget action.**
- **Versioning:** `GlassMailDB.version` covers the new data subtrees (`chars`, `recents`,
  `snapshots`, `sent`, `trash`) only. A subtree of an unknown or unreadable shape is dropped,
  never half-read; the settings keep their existing per-key validation (`ensureDefaults`), so a
  v0.1.0 player's look and Open All choices survive.

### `Core/Names.lua`

- `Names.Key(name)`: the comparison key. Trimmed, inner spaces collapsed, lower-cased. A `-Realm`
  suffix is **kept** (part of the key): session 6 found none in the guild roster, and other realms
  are unmeasured, so a candidate with a suffix other than the current realm's is left out of the
  picker.
- `Names.Display(name)`: trimmed, as the player would type it.
- A secret name (`issecretvalue`) is never keyed or stored; it is skipped.

### The character registry (S1, X1)

- **Own characters**, account-wide, keyed by GUID: `{ name, realm, faction, lastPlayDay }`,
  written at `PLAYER_LOGIN` (`UnitGUID`, `API.PlayerFullName`, `GetRealmName`, the
  `UnitFactionGroup` tag). Aged by `expiryDays`.
- **AltStable**, when loaded (`## OptionalDeps: AltStable`, `PUBLIC_API_VERSION == 1`, and
  `PUBLIC_API_FEATURES.provenance`): `GetCharacters()` (copies; GUID, name, realm, faction, class,
  account, hidden, current, provenance) and the `CharactersChanged` callback, only to refresh what
  is shown. Its sheet holds other players' characters too: only `provenance` `self` and
  `own-account` are taken. An AltStable without the provenance feature can't say whose a
  character is, so it isn't used (our own record is). Nothing from it is saved.
- **Reachability:** an own character is offered as a recipient when its faction tag and
  **ruleset** match the current character's (`Registry.RulesetOf`, from the realm's name,
  AltStable's rule; "Unknown" matches nothing). Session 6: the other faction fails ("Target is
  unfriendly"); the other account's character takes mail like an alt. **Owner, 2026-11-12:** on
  Forever a realm is part of its ruleset (a ruleset is a group of servers, not worlds of their
  own), and mail reached a character of another realm of the same ruleset ("Realm 1 PvE" and
  "Realm 7 PvE"); the first rule (same realm) hid those characters. Another ruleset is
  unmeasured, so it stays out.

### Sent (X2, `Core/Sent.lua`)

A send is captured as it is made and kept, in the state its outcome justifies:
- **Capture** in `hooksecurefunc("SendMail", ...)` (MailFrame.lua:1273, the only caller; the
  gamepad footer ends there too, MailFrame.lua:1200). The draft is still in place then (Blizzard
  resets it only on `MAIL_SEND_SUCCESS`, MailFrame.lua:152-158; session 6 confirms): recipient and
  subject from the arguments, `GetSendMailMoney()`, `GetSendMailCOD()`, slots
  1..`ATTACHMENTS_MAX_SEND` by `GetSendMailItem` (itemID, count; no links). Record `{ day, at, char,
  to, subject, money, cod, items, state = "pending" }`.
- **States:** `pending` while in memory only; saved as `sent` or `unconfirmed`. No `failed`:
  `MAIL_FAILED` never fired inside `SendMail` (session 6) and carries no action identity
  (MailInfoDocumentation.lua:90-97). An unconfirmed send still shows in Sent, marked, because
  "where did I send that?" needs it too.
- **Attribution: a 120 s window** (session 6 replaced the session-long overlap rule, which a
  mistyped name or a cancelled confirmation would have turned on for the rest of the session):
  - Each `SendMail` opens a **window** of 120 s for its record: the longest a result has ever taken
    is 99 s (sessions 2-3); session 6 measured 0.4-0.7 s, and 11 s for a stranger confirmed by hand.
  - **`MAIL_SEND_SUCCESS` confirms a record only when it is the one record with an open window**
    (and not yet confirmed); it is then `sent` and its window closes. With two or more open, the
    success confirms none of them.
  - A record whose window ends unconfirmed (120 s) is saved `unconfirmed`. The window rests on one
    assumption: no result comes more than 120 s after its window starts (its `SendMail`, or the
    confirmation dialog's close for a stranger). If one ever did, it could
    confirm a later send that is alone in its window; the 99 s worst case measured is the margin.
  - **A client refusal is dropped:** `UI_ERROR_MESSAGE` with **message type 457** (session 6: a
    one-word name, no other event), in the same frame as the record's `SendMail`, with exactly one
    record opened in that frame, closes its window and the record is never saved: the mail never
    left the client. The type is read only after `issecretvalue`; any other error, or 457 in
    another frame, is left alone (the record ends with its window).
  - **No inference from `MAIL_FAILED`**: it doesn't close a window (it may be an inbox action's);
    the record ends `unconfirmed` when its window does.
  - **The stranger confirmation:** `SECURE_TRANSFER_CONFIRM_SEND_MAIL` fires inside `SendMail`;
    confirming sends through `C_SecureTransfer.SendMail` (no second call) and `MAIL_SEND_SUCCESS`
    follows; cancelling fires nothing. The dialog has no timeout, so the player can accept minutes
    later (Blizzard_SecureTransferUI.lua:101-132). A record whose `SendMail` raised it is
    **awaiting confirmation**: an open candidate with **no time limit**, until the dialog closes.
    Its close (accept or cancel) calls the global `SendMailFrame_EnableSendMailButton` through
    `securecall` (`SecureTransferDialog_OnHide`, Blizzard_SecureTransferUI.lua:414-417, and its
    outbound bridge, Blizzard_SecureTransferUIOutbound.lua:8-10); our post-hook on it starts the
    record's 120 s window then. If that hook never fires (unmeasured), the record stays in the
    candidate count until it is confirmed or the player logs out: a success with another
    candidate open is then ambiguous, and nothing is misattributed.
    The core PR's in-game check measures it. `SECURE_TRANSFER_CANCEL` is never used: it fires on
    every mailbox close and reload.
  - **A mailbox close doesn't end a window.** At logout every open record is saved
    `unconfirmed`. A `/reload` starts with no open window.
- `SendMail` joins Ops' foreign-call hooks: a send stops any Ops run.
- **Returns go to Sent too**, as "returned to <sender>": a return is mail travelling back. Captured
  like a delete (below).
- A `sent` record updates the recent recipients (`Names.Key` → `{ name, day }`).
- Expiry: `expiryDays` play days, and at most 1000 records.

### Trash (`Core/Trash.lua`)

- **Capture at the post-hook** (session 6: the `DeleteInboxItem` / `ReturnInboxItem` post-hook
  still finds the mail at its index, 5 of 5; the update that removes it follows 0.12-0.37 s
  later). Every call, ours or Blizzard's (the letter's buttons, the delete popup), is captured from
  a fresh `Scan` of that index, with its contents and `expires` (`time() + daysLeft * 86400`).
  - **Not when an inbox update came in the same frame** (`GetTime()` equal to the last
    `MAIL_INBOX_UPDATE`'s): it may have come inside the call, so the index may already hold the
    next mail. That removal is left out (none did in session 6).
  - **Confirmed** when an update within 5 s shows its fingerprint's count and the loaded count each
    one fewer than at the hook; committed a frame later, so a later call's post-hook can still void
    it. Otherwise dropped.
  - **Not while an earlier inbox call is unsettled:** every inbox-changing call (Take, money,
    AutoLoot, Return, Delete, ours or anyone's: the post-hooks Ops uses) marks the inbox
    unsettled. Only a `MAIL_INBOX_UPDATE` that arrives with `C_Mail.IsCommandPending()` false
    settles it (an update says nothing about which call finished; Blizzard's own Open All waits for
    the same flag, MailFrame.lua:1683). That the flag is false once a call's update has come is
    unmeasured: the core PR's in-game check logs it, and if it stays true the inbox never settles,
    so Trash records nothing rather than something wrong. A removal made while it is unsettled is left out: a take
    already in flight could otherwise remove the mail and pass for the return. No timeout settles
    it: a call that never produces an update (a take on an empty slot, session 5) leaves the next
    removal out, and that removal's own update settles it again.
  - One capture at a time; **any later inbox-changing call drops a capture still outstanding**, so
    a take that empties a mail can't confirm a return. An unresolved mail (missing link, secret) is
    not captured.
  - Removals left out are said nowhere but in the window's note: Trash holds what Glass Mail saw.
- A confirmed delete goes to Trash; a confirmed return to Sent ("returned to").
- Trash shows only in its folder, never in Inbox. Each entry goes when the mail would have expired.
- Takes by hand (shift-click, the letter's buttons) are not recorded: frequent, paced by the
  player, and not an answer to "where did it go?".

### S1: the address book picker (`Address.lua`)

- **Our button** to the right of `SendMailNameEditBox` (a child of SendMailFrame), opening a
  `MenuUtil.CreateContextMenu` with sections, each skipped when empty:
  1. **My characters**: AltStable's list if loaded, else the registry; reachable ones only, not
     the current character, AltStable's hidden ones left out.
  2. **Recent**: newest first.
  3. **Friends**: `C_FriendList.GetFriendInfoByIndex` (WoW friends), read now.
  4. **Guild**: the roster, read now, in a submenu with `SetScrollMode`;
     `C_GuildInfo.GuildRoster()` is requested when the picker opens.
  Each name appears once (by `Names.Key`, first section wins).
- **Picking fills the box**: `SendMailNameEditBox:SetText(name)` and nothing else (Blizzard's own
  reply does the same, MailFrame.lua:1088). `SetText` raises no autocomplete (`userInput` false,
  AutoComplete.lua:367-378) and re-runs `SendMailFrame_CanSend`. The player still clicks Send, and
  any confirmation.
- **Ships only after session 6** shows a picked name then Send to a stranger, through the
  confirmation, raises no `ADDON_ACTION_BLOCKED` / `_FORBIDDEN` (the alt case passed in session 3).
- **Contacts** (a saved list the player curates) are **cut**: recents, friends and guild cover
  them, and a hand-kept list is the upkeep the owner wants gone. FEATURES.md is updated.

### S1: the last recipient (owner, 2026-11-06)

Postal's "Autofill last person mailed", as a behaviour reference: the To box starts with the last
name this character mailed. In `Address.lua`, beside the picker.
- **What "last" is:** `chars[guid].lastTo`, the `Names.Key` of the newest send from that character
  that Sent attributed as `sent`. Set where the record goes into `recents`. A `return` never sets
  it, and a send that ends `unconfirmed` without a success (a cancel, a typo) leaves it as it was.
  **A `MAIL_SEND_SUCCESS` that Sent can't attribute clears it** (`lastTo = nil`): a newer send went
  somewhere unknown, so the older name is no longer the last one (Codex review: mail A, cancel a
  stranger, mail B inside that window; B's success is ambiguous, and reopening the tab must not
  offer A). The next attributed success sets it again. Per character, so it is never the current
  character itself and always of its faction. An optional field: no version change; one that
  isn't a string is dropped at load.
- **It ages out:** it is filled only while `recents[lastTo]` exists (the name shown is that
  entry's `name`). `recents` is account-wide, so another character mailing the same name keeps it
  alive; that's fine (it is still someone you mail), and with no sends to it the entry expires
  (`expiryDays`, `recentMax`) and the fill stops. This is aging, not detection of a deleted
  character.
- **When it fills**, each time only if `autofill` is on, `SendMailFrame:IsVisible()` (not
  `IsShown()`, which stays true under a hidden mailbox) and `SendMailNameEditBox:GetText() == ""`,
  all checked at the moment of filling:
  1. **The send tab opens**: a `hooksecurefunc("MailFrameTab_OnClick", ...)` post-hook, for tab 2
     (`tabID` or the button's `GetID()`, as Blizzard reads it, MailFrame.lua:189-192). Blizzard's
     Reply calls `MailFrameTab_OnClick(nil, 2)` and then sets the sender (MailFrame.lua:1092-1093),
     so a reply overwrites our fill; the mailbox's close empties the box (MailFrame.lua:53).
  2. **After a send**: Blizzard's `MAIL_SEND_SUCCESS` handler calls `SendMailFrame_Reset()`, which
     empties and focuses the box (MailFrame.lua:144-150, 1422-1424). When Sent attributes a success,
     it schedules the fill with `C_Timer.After(0)` from that branch: by then Blizzard's handler has
     reset the box (and, after a reply, gone back to the inbox), whichever handler ran first. The
     callback also checks that `lastTo` still names that record's recipient (an unattributed success
     in between has cleared it). No reset hook. An unattributed success schedules nothing, so the
     box stays empty. A reply's success shows the inbox (MailFrame.lua:148-150): not visible,
     nothing filled.
- **How:** `SetText(name)` then `HighlightText()`, so typing replaces it after a send (the box
  has focus then); on the tab's open a click may drop the highlight, and the player selects the
  name to replace it (the PR's detail, below). Nothing else: no focus change, no autocomplete
  (`SetText` isn't user input), no send. The player still clicks Send and
  any confirmation.
- **Setting `autofill`** (default on): a checkbox under "Memory", `/gmail autofill on|off`,
  validated in `ensureDefaults` like the other booleans.
- **Tests** (mutation-tested): fills on tab 2 when empty; not over typed text, not on tab 1, not
  when off; Reply's sender wins; `lastTo` without its recent → nothing; a `return` and a cancelled
  send don't move `lastTo`; another character's `lastTo` is never used; after an attributed success
  the box refills with that recipient a frame later, with Sent's handler before Blizzard's and
  after; after an unattributed one it stays empty, **and reopening the send tab fills nothing**
  (A sent, a stranger cancelled, B's success ambiguous); a reply's success fills nothing; the
  mailbox closed or a name typed before the deferred fill → nothing; a non-string `lastTo` is
  dropped at load.
- **In game, before it ships** (with the picker's check): the send tab opens with the name;
  after a send, typing replaces it (on the tab's open, what a click does to the highlight); Reply puts the sender in; two sends in a row to an alt need no
  typing; a stranger's send with an autofilled name goes through the confirmation with no
  `ADDON_ACTION_BLOCKED` / `_FORBIDDEN`.

### Inbox (X1): alt mailbox memory (`Core/Summary.lua`, `Core/Memory.lua`)

- **Snapshot** per character (account-wide, keyed by GUID), from `Scan.Inbox()` on each
  `MAIL_INBOX_UPDATE` while the mailbox is open: `{ at, loaded, total, complete, mails = { {
  sender, subject, money, cod, expires, type, wasReturned, items = { { itemID, count } } } } }`,
  `expires = time() + daysLeft * 86400` rounded down to the minute (AltStable's rule). No letter
  text (it would mark mail read).
- **What may replace a snapshot:** only a scan whose every mail is resolved, taken after the visit's
  first `MAIL_INBOX_UPDATE` (the inbox before it is stale or empty). `complete` is
  `loaded == total`; a partial scan (over 100 mails) is still the newest truth and replaces the old
  one, shown as "N of M loaded". FEATURES.md's X1 line is updated to say this.
- **`Summary.Of(snapshot)`**: AltStable's rule exactly (Core.lua:2745-2750): mails with items or
  money and days left, their count, money, and the soonest expiry; empty when none. Its first
  consumer is the Inbox folder's character rows. (M3 moves it to LibMailbox; AltStable keeps its
  fields.)

### The window (`Window.lua`)

Our own glass window (LibGlass panel, ScrollBox lists), opened by `/gmail mail` and a small button
on MailFrame's title. It opens on **Sent**, the owner's first question. Folders down the left, like
Gmail:
- **Inbox**: one row per character (name, "last seen 3 days ago", the summary; partial marked),
  opening into its mails.
- **Sent**: newest first: to whom, when, state, subject, money, items. The default search target.
- **Trash**: deleted mail, with "gone in N days".
A search box above searches the open folder: names, subjects, and item names
(`C_Item.GetItemNameByID`). Saved records keep only item IDs, and that call needs the item's data
loaded (`Blizzard_ObjectAPI/Mainline/Item.lua:195`), so waiting is not enough after a restart: on a
cache miss the window asks with `C_Item.RequestLoadItemDataByID`, once per itemID per session
(distinct IDs only, never per record), and refreshes the search on `ITEM_DATA_LOAD_RESULT`. A load
that reports `success = false` isn't retried; that item is left out of name search until the next
session.

### I4: mail bag grid (`Bag.lua`)

- A panel beside the inbox (our frame, toggled by an "Items" button on InboxFrame's top bar),
  showing every attachment in the loaded inbox merged by itemID: icon, total count, "in N mails".
  Plain buttons of ours (`ItemButtonTemplate` is unmeasured here); tooltip by itemID plus the mail
  count. Refreshed from the `InboxFrame:Update` post-hook.
- **A click takes every copy**: an Ops run `kind = "items"` with `opts.items = { [itemID] = true }`.
  In `Loot`, the item filter applies **before** the money-first branch: money and other items are
  skipped. COD and GM mail are still left, `keepFree` applies, the type filters don't. `items` joins
  `openall` / `selected` in Ops' start, finish (`SetOpeningAll`, tally) and stop conditions. Twins
  are fine (no remembered target), as Open All. Disabled while any run, a letter, or combat is on.
- Ops' item attempts also carry the stack `count` (from the scan), so a confirmed take can be
  shown.

### Probe session 6 (MailProbe, before Sent, Trash and S1 ship)

1. `sendwatch on`: in a `SendMail` post-hook, log the arguments and what `GetSendMailItem`,
   `GetSendMailMoney`, `GetSendMailCOD` return; every send-side event in order
   (`MAIL_SEND_INFO_UPDATE`, `MAIL_SEND_SUCCESS`, `MAIL_FAILED`, `MAIL_SUCCESS`,
   `SECURE_TRANSFER_*`, `UI_ERROR_MESSAGE`), and whether any fires **inside** `SendMail` (before
   the post-hook). Cases: an alt, plain, with an item, money, COD; a stranger with an item,
   confirming and cancelling (which `SECURE_TRANSFER_*` events reach us, with what); an unknown
   name; not enough money for postage; the other faction; another ruleset; the other account's
   character.
2. **Correlation:** close the mailbox right after Send (does the success still come?); take mail
   while a send is pending (unrelated `MAIL_FAILED` / `MAIL_SUCCESS`); click Send twice quickly
   (what re-enables Send; do the outcomes keep order).
3. **Delete and return capture:** in `DeleteInboxItem` / `ReturnInboxItem` post-hooks, is the mail
   still at its index; the update order after (Blizzard's letter Delete, an AH mail with items).
4. `picker NAME`: `SetText` then Send to a stranger, through the confirmation. Watch for `!` lines.
5. Friend and guild name formats (surname, realm suffix), and secrecy, in and out of an instance.
6. The two v0.1.0 checks never reported: the gold line at close, and no blocked action (the
   ForeverProbe baseline's watcher) after a session with Open All and the row icons.

Session 6 runs as ForeverProbe procedures (`/fp steps mail send|timing|capture|picker|names|release`):
MailProbe became a ForeverProbe module before it ran.

**Measured 2026-10-15** (FOREVER-PROBE.md, "Session 6 findings"): the post-hook capture works for
sends and removals; S1's stranger confirmation passed; `SECURE_TRANSFER_CANCEL` and `failed` are
out. **Sent's overlap rule is too strict** (a typo'd name or a cancelled confirmation leaves a send
with no result, and the rest of the session would be unconfirmed): the core PR's plan narrows it,
reviewed with Codex before code.

### Delivery: five PRs, each "Part of #17"

1. **Probe session 6** (MailProbe), results into FOREVER-PROBE.md.
2. **Core:** `Names`, the play-day clock and expiry, the registry, Sent and Trash capture, recents,
   the two settings, `SendMail` in Ops' foreign calls, the item count on attempts. No window yet.
3. **The window:** `Summary`, snapshots, and the Sent, Inbox and Trash folders with search. Sent
   first: it answers the owner's question.
4. **S1** picker and the last-recipient fill.
5. **I4** grid; v0.2.0; closes #17.

Settings added: `expiryDays`, `recentMax` (options page radios, `/gmail`); `autofill` (a
checkbox, with the picker PR). New saved data in
`GlassMailDB`: `playDay`, `lastDate`, `version`, `chars`, `recents`, `snapshots`, `sent`, `trash`.

### The core PR in detail (PR 2 of M2; reviewed before code)

What it ships: the memory, with no window yet. The owner checks it in game with `/gmail sent` and
`/gmail trash` (the last 10 of each, one chat line apiece) until the window PR replaces them.

**Files** (TOC: after `Core\Ops.lua`, before `OpenAll.lua`):
- `Core\Names.lua`: `Names.Key`, `Names.Display` (above).
- `Core\Store.lua`: the saved data's shape, the play-day clock and expiry. Owns
  `GlassMailDB.version`, `playDay`, `lastDate` and the subtrees `chars`, `recents`, `sent`, `trash`
  (`snapshots` arrive with the window PR, under the same version rules).
- `Core\Registry.lua`: own characters, AltStable when loaded.
- `Core\Sent.lua`: send capture and attribution, returns, recent recipients.
- `Core\Trash.lua`: delete capture (and the return capture Sent records).

**Saved data** (`GlassMailDB`, account-wide; plain values only, every field checked with
`issecretvalue` before it is kept; a secret field drops that field, a secret name or GUID drops the
record):
- `version = 1`; `playDay` (a counter from 1); `lastDate` (`date("%Y-%m-%d")`, the local date).
- `chars[guid] = { name, realm, faction, lastPlayDay }`; the current character's `lastPlayDay` is
  refreshed at login and on every tick, before pruning (a session over midnight counts).
- `recents[key] = { name, day }`, `key = Names.Key(name)`, `day` the play day of the last `sent`.
- `sent = { record, ... }`, oldest first, at most 1000:
  `{ kind = "send" | "return", day, at, from (GUID), to (name), subject, money, cod,
  items = { { id, count }, ... }, state = "sent" | "unconfirmed" }`. A return is
  `{ kind = "return", to = <its sender>, ... }`, `state = "sent"` once confirmed.
- `trash = { entry, ... }`, oldest first, at most 500:
  `{ at, from (GUID: whose mailbox), sender, subject, money, cod, items, expires }`.
- **Required fields** (a record without one is invalid): `sent`: `kind`, `day`, `at`, `from`, `to`,
  `state`; `trash`: `at`, `from`, `expires`. Everything else may be absent (a secret field is left
  out, not the record). The caps apply on insertion (the oldest goes) and again on prune.
- **Loading:** at `ADDON_LOADED`, `Store.Load()` reads each subtree with a shape check (a table, of
  tables, with the required fields and types); a subtree that fails is dropped whole, and so is
  everything when `version` is missing or isn't 1. The clock header is checked too: `playDay` a
  whole number of at least 1 and `lastDate` a `YYYY-MM-DD` string, else both restart (1, today)
  **and the subtrees stamped in play days go with them** (`chars`, `recents`, `sent`: their days
  belong to the lost counter and would never age); `trash` ages in real time and stays.
  The settings are untouched by this. `DEFAULTS` gets `expiryDays = 30` and `recentMax = 20`, and
  `ensureDefaults` validates both like `keepFree` (one of the offered choices, else removed so the
  default applies); the setters use the same validators. The subtrees and clock fields are not
  settings and never fall through to `DEFAULTS`.

**The play-day clock** (`Store.Tick()`): at `PLAYER_LOGIN`, before any write or prune, and every 10
minutes (`C_Timer.NewTicker`). `lastDate` is a **high-water mark**: if `date("%Y-%m-%d")` is later
than `lastDate` (string order is date order in this form), `playDay` + 1 and `lastDate` = today; an
earlier date changes nothing, so a clock set back and forward again never counts a date twice
(counting waits until the calendar passes `lastDate` again). Then the current character's
`lastPlayDay` = `playDay`, then `Store.Prune()`:
- `chars`: `lastPlayDay` older than `expiryDays` play days goes; the current character never does.
- `recents`: older than `expiryDays` goes; then the oldest past `recentMax`.
- `sent`: `day` older than `expiryDays` goes; then the oldest past 1000.
- `trash`: `expires < time()` goes (real time); then the oldest past 500.

**Sent's window, in code:** `Sent.open = { record, ... }` in memory (the candidates).
- `SendMail` post-hook: capture (above); `record.opened = GetTime()`; append to `open`.
- `SECURE_TRANSFER_CONFIRM_SEND_MAIL` fires inside `SendMail`, before the post-hook: the handler
  notes the frame (`GetTime()`), and the post-hook marks its record `awaiting` (no window yet) when
  the note is from this frame.
- `SendMailFrame_EnableSendMailButton` post-hook (the dialog's close): every `awaiting` record gets
  `opened = GetTime()`, `awaiting = nil`: its window starts.
- `MAIL_SEND_SUCCESS`: the candidates are the records in `open` that are `awaiting` or whose window
  hasn't ended (`GetTime() - opened <= 120`); exactly one → `sent`, saved, removed from `open`, its
  recipient into `recents`. Otherwise nothing is attributed.
- `UI_ERROR_MESSAGE` type 457, as above: removed, unsaved.
- Each window ends by its own `C_Timer.After(120)`, set when it opens (at `SendMail`, or at the
  dialog's close): a record still open then is saved `unconfirmed` and removed. (The code uses
  that in place of the 1 s ticker first planned: one timer per window, nothing to stop.)
- `PLAYER_LOGOUT`: every record in `open` is saved `unconfirmed`.

**Trash, in code:** `unsettled` is set by every inbox-changing post-hook (Ops' list) and cleared
only by a `MAIL_INBOX_UPDATE` that finds `C_Mail.IsCommandPending()` false (one still pending
leaves it set for a later update); `lastUpdate` is the last update's `GetTime()`. A removal's
post-hook reads both **before** it marks the inbox unsettled itself: captured only when the inbox
was settled and `lastUpdate ~= GetTime()`.

**Ops** gets `SendMail` in its foreign calls, and each take attempt carries the scan's stack
count (`attempt.count`) for I4.

**Settings:** `Settings.SetExpiryDays(n)` (7 / 14 / 30 / 60 / 90) and `Settings.SetRecentMax(n)`
(10 / 20 / 50), each pruning at once; the options page gets two radio groups under a new
"Memory" heading; `/gmail expiry N`, `/gmail recents N`, `/gmail sent`, `/gmail trash`. Each
`/gmail sent` line: when, from which character, kind and state (`sent`, `unconfirmed`,
`returned to`), to whom, subject, money and COD, and items as `itemID x count`; `/gmail trash`
the same with the sender and "gone in N days".

**Tests** (each mutation-tested):
- Names: trim, collapse, case, a kept suffix, a secret name.
- Store: a fresh DB; v0.1.0's settings-only DB keeps every setting; an unknown version drops the
  subtrees; one malformed subtree is dropped alone; a record missing a required field is
  invalid, one missing an optional field is kept; a secret field never saved; the caps on insertion.
- Clock: advances once per date, twice over midnight within one session (the ticker); the
  sequence forward → backward → the original date → the next date counts each date once; an
  invalid header restarts and drops `chars`, `recents` and `sent` (records stamped day 200 with
  the header broken), keeping `trash`; prune by play days, by count, trash by `time()`.
- Settings: an invalid saved `expiryDays` / `recentMax` (a string, an unoffered number) is
  removed at load; a valid non-default choice is kept.
- Registry: the current character written at login, and refreshed by a tick over midnight (then a
  character switch: it ages from the later day); aged out by play days, never the current one;
  AltStable absent, wrong `PUBLIC_API_VERSION`, without the provenance feature, present (nothing
  saved from it; a third-party character left out).
- Sent, as timelines: the draft captured at the post-hook (money, COD, items, no links); one open
  window and a success → `sent` and a recent; two open → neither; the 120 s end → `unconfirmed`;
  error 457 in the same frame → dropped; another error in that frame, or 457 a frame later → kept;
  logout → `unconfirmed`; a stranger: confirmation at t=0, accepted at t=130 (the dialog closes,
  its window starts), B sent at t=130.3, a success at t=130.6 → neither (both candidates); a
  stranger accepted at 11 s with nothing else open → `sent`; a cancelled stranger → its window
  starts at the close and ends `unconfirmed`; the close hook never firing → the record stays a
  candidate until logout.
- Trash: a delete captured at the hook and confirmed by the next update (deferred a frame);
  an update in the same frame → not captured; a take before the confirmation drops it; **take →
  return before the take's update → the return isn't captured**; removal A → removal B before A's
  update → neither (A dropped by B, B unsettled), with twins and with a rejected second call; a
  take, then an unrelated update **while a command is still pending**, then a Return → not
  captured (still unsettled); a take that produces no update → the next removal is left out and
  its own update settles the inbox again; a
  twin's fingerprint count; a return goes to Sent as `return`; an unresolved mail isn't captured;
  the 5 s end drops it; the deferred commit checks the capture is still the same one.
- Ops: a foreign `SendMail` stops a run; a take attempt carries the count.

**In game** (the owner, after deploy; a temporary debug line shows the dialog-close hook; the
steps are #27, run after launch):
- Send to an alt; to a stranger confirmed at once, held over 2 minutes then confirmed, and
  cancelled; to a one-word name. `/gmail sent` shows `sent`, `sent`, `sent`, then `unconfirmed`
  2 minutes after the cancel, and nothing for the typo. The debug line shows the close hook firing
  on accept and on cancel.
- Delete an empty mail, return a test mail, delete an AH mail with items through its popup:
  `/gmail trash` shows both deletes, `/gmail sent` the return. Take an item then Return the same
  mail at once: no record for it.
- The debug line also logs `C_Mail.IsCommandPending()` at each inbox update around a take and a
  return, to confirm it is false once a call's update has come.
- `/reload` while a send is still open: it isn't saved as `sent` later. Then a full exit: the
  saved records survive (persistence needs the exit).

**Review outcome for the core PR** (Codex gpt-6-astra, high, 3 rounds, consensus, 2026-10-17):
- **A stranger's send waits for the dialog:** no time limit while awaiting confirmation; its
  window starts at the dialog's close (a post-hook on `SendMailFrame_EnableSendMailButton`, no
  taint: the outbound bridge calls it by name in the global environment). Read from Blizzard's
  source (Blizzard_SecureTransferUIOutbound.lua:8-10), not measured: the core PR's in-game check
  confirms it fires on both accept and cancel.
- **Pending, after launch (#27):** both client checks in "In game" above, the dialog-close hook and
  `C_Mail.IsCommandPending()` after an update, recorded in FOREVER-PROBE.md with the build. The
  game is unavailable until Nov 4, so they don't block merging: a failure only makes Glass Mail
  record less.
- **Trash needs a settled inbox:** an earlier call in flight voids a capture; only an update
  with no command pending settles it; no timeout does.
- **Smaller:** only error 457 drops a send; `lastDate` is a high-water mark; the current
  character's play day refreshes on every tick; the new settings are validated at load; a
  restarted clock drops the play-day-stamped subtrees.

### The window PR in detail (PR 3 of M2; Codex gpt-6-astra, high, 3 rounds, consensus, 2026-11-06)

What it ships: the Inbox snapshots and the window with its three folders. `/gmail sent` and
`/gmail trash` go (the window replaces them, with `Sent.Lines` and `Trash.Lines`).

**Files** (TOC: `Core\Summary.lua` and `Core\Memory.lua` after `Core\Trash.lua`; `Window.lua`
after `Comforts.lua`, before `Options.lua`):
- `Core\Summary.lua`: `Summary.Of(snapshot, now)`.
- `Core\Memory.lua`: taking the snapshots.
- `Window.lua`: the window, its folders, rows, search and forget actions.

**Saved data:** a fifth subtree, `snapshots[guid]`, under `version = 1` (a new subtree is an
addition: an older save has none and loads as empty; no version change). A restarted clock drops
it with `chars`, `recents` and `sent`: its characters' registry goes then, and a snapshot without
its character could never age out.
- `{ at, loaded, total, complete, mails = { mail, ... } }`; required `at`, `loaded`, `total`
  (numbers), `complete` (a boolean), `mails` (a list).
- Each mail: required `expires` (a number) and `type` (`ah` / `system` / `player`); optional
  `sender`, `subject`, `money`, `cod`, `wasReturned` (a boolean), `items` (`{ id, count }`). A
  mail that fails makes its snapshot invalid, and an invalid snapshot drops the subtree, as for
  the others. At most 100 mails (the loaded window); a longer list is invalid.
- Store gets a `boolean` field kind and a `mails` kind (a list of records cleaned by the mail
  spec), `Store.Snapshots()`, `Store.SetSnapshot(guid, snap)` and the forget calls below.
- **Prune:** a snapshot whose GUID isn't in `chars` goes (its character aged out). Then each
  snapshot loses its mails with `expires < time()` (an expired mail has left the mailbox: returned
  or deleted by the server). A snapshot left with no mails stays until its character goes. (The
  first rule dropped a snapshot once its last mail expired. That loses "last seen"; the
  character's own expiry still ends it, one record per character.)

**Taking a snapshot** (`Core\Memory.lua`):
- A visit starts at `MAIL_SHOW` and ends at `PLAYER_INTERACTION_MANAGER_FRAME_HIDE` (type 17).
  Each visit gets a new number; the close clears it. Updates outside a visit are ignored.
- Each `MAIL_INBOX_UPDATE` in a visit, the first one included, schedules one scan a frame later
  (`C_Timer.After(0)`, coalesced per visit: several updates in one frame scan once). The callback
  carries its visit's number and scans only if that visit is still the open one (update, close,
  reopen: the old callback does nothing).
- **Assumed, checked in game before v0.2.0:** the first update after `MAIL_SHOW` carries this
  visit's inbox, never a previous character's or visit's (Blizzard's `RefreshInbox` may defer
  `CheckInbox`, MailFrame.lua:237-246; the measured updates came 0.15-0.3 s after opening, contents
  unchecked). The debug line logs, at each scan: the visit, `loaded`, `total` and the first
  sender. If it fails, the acceptance rule is revised from what was measured, not padded with a
  delay or a second `CheckInbox`.
- **What a scan must show to replace the snapshot** (else nothing is saved and the previous one
  stays): `Scan.Inbox()` `resolved` (no secret, every attachment linked); a mail at every index up
  to `loaded` (`#mails == loaded`: a header not yet there is skipped by Scan); every mail's
  `daysLeft` a number; and each mail's attachments as many as its header's `itemCount` (Scan keeps
  `itemCount` on the mail; a nil `itemCount` is 0: this client gives nil for a mail without items,
  FOREVER-PROBE session 2). A readable loaded subset (`loaded < total`) is accepted, as before.
  Then the current character's snapshot is replaced: `at = time()`,
  `loaded`, `total`, `complete = loaded == total`, and each mail as `{ sender, subject, money, cod,
  expires = floor((time() + daysLeft * 86400) / 60) * 60, type, wasReturned, items }`. Currency
  attachments (`isCurrency`) are left out of `items`: their ID isn't an itemID.
- No current GUID (secret, nil) → nothing saved. No letter text, ever.
- `complete`, `loaded` and `total` are the visit's coverage, never updated by a prune or a
  forget: "100 of 140 loaded at the last visit".

**`Summary.Of(snapshot, now)`**: AltStable's rule (Core.lua:2927-2950): over the mails with items
or money and `expires > now`: their count, their money, the soonest `expires`. nil when none.

**The window** (`Window.lua`, a frame named `GlassMailWindow`, child of `UIParent`):
- **Look:** one glass surface (`Glass.Apply(frame, "large")`) in the current preset, the `stock`
  skin using `smoked` (the window has no Blizzard art to fall back on); `Skin.Refresh` repaints it
  (Skin keeps a list of extra surfaces). Every open repaints the list from the Store. Section panes as on the mail windows: the folder column
  and the list on a `section` pane, rows on `pane`.
- **Frame:** about 640 x 440, `HIGH` strata, `SetToplevel`, clamped, movable by its title bar
  (the position isn't saved: it opens centred each session), a close button
  (`UIPanelCloseButton`). **Escape closes it:** its name is in `UISpecialFrames`, taken out at
  `PLAYER_REGEN_DISABLED` and put back at `PLAYER_REGEN_ENABLED` (GlassGear's rule: an addon entry
  taints the Escape pass, which would then fail to hide a protected frame in combat). Put in at
  creation only when `API.InCombat()` is false (a window built in combat, by `/gmail mail` or after
  a reload, waits for `PLAYER_REGEN_ENABLED`). Only `table.insert` / `table.remove` on the table,
  never an assignment. So Escape closes it out of combat; in combat the close button and the
  toggle do.
- **Opened by** `/gmail mail` (a toggle) and our small button on `MailFrame`'s title bar, left of
  its close button (a child of `MailFrame`, like the row controls). Works away from the mailbox,
  in combat too (nothing protected).
- **Folders** down the left: **Inbox** (characters with a snapshot), **Sent** (n), **Trash** (n).
  The first open in a session shows Sent; after that, the folder last shown.
- **Search box** above the list (a plain `EditBox` on a pane, "Search" as a grey hint while empty):
  filters the open folder as you type; Escape clears its focus. Matching: the query and each field
  lower-cased, a plain `find` (no patterns), every space-separated word must match some field.
- **The list:** a pool of row frames (as many as fit, about 10), an offset, the mouse wheel and a
  thin scroll bar of ours (a `Slider`): 1000 Sent records never build 1000 frames. Rows are two
  lines; up to 6 item icons (`C_Item.GetItemIconByID`), each with its count and a tooltip
  (`GameTooltip:SetItemByID`), "+N" past 6.
- **Sent rows**, newest first: "to *name*" (or "returned to *name*"), from which character
  (`chars[from].name`, else "another character"), when (`date` of `at`: "14:02" today, else
  "Nov 3"), state (an amber "unconfirmed" when so), then subject, money, COD and the items.
- **Trash rows**, newest first: "from *sender*", in whose mailbox, "gone in N days" (from
  `expires`), then the contents. A note under the list says what Trash holds: deletes Glass Mail
  confirmed; one made while another mail action was in flight isn't there.
- **Inbox:** one row per snapshot, sorted by character name: the name, "last seen N days ago"
  (from `at`, real time; "today"), and the summary ("3 mails with items or gold, 120g, the first
  expires in 2 days"). With no summary, what is known and no more: "empty when last seen" only
  for a complete snapshot whose `total` was 0; "letters only" when unexpired mails remain; "no
  unexpired mail recorded" otherwise. "100 of 140 loaded at the last visit" when not `complete`. A click opens that
  character's mails (not expired, soonest expiry first): sender, subject, money, COD, items,
  "expires in N days", "returned" when so; a back button returns to the characters. **A search in
  Inbox** lists the matching mails of every character, each with its character's name, even from
  one character's mails (clearing it returns there). A character's mails with nothing to list say
  that character's line ("Empty when last seen", "No unexpired mail recorded").
- **Empty states:** "Nothing sent yet", "Trash is empty", "No mailbox seen yet: open one on each
  character". When `Store.Ready()` is false: "Glass Mail's memory couldn't load" (and nothing
  else).
- **Forget, on every row:** a small × on the row's right, dim until hovered: a Sent record or a Trash
  entry is removed from its list (by identity: the row holds the record table), a character's row
  drops its snapshot, a mail row drops that mail from its snapshot. One click, no confirmation
  (only Glass Mail's memory changes; the mailbox doesn't).
- **Item names** for search: `C_Item.GetItemNameByID(id)`. On a miss, the window asks
  `C_Item.RequestLoadItemDataByID(id)` once per itemID per session (only for the records being
  searched, distinct IDs; the ID is marked asked before the request, and the event is registered
  first), and on `ITEM_DATA_LOAD_RESULT(id, true)` for an ID it asked, refreshes
  the search (coalesced to one refresh a frame). `success = false`: that ID isn't asked again
  this session and is left out of name search.
- **Live:** Store gets `Store.OnChange(fn)`, called after every write (a Sent record, a Trash
  entry, a snapshot, a forget, a prune that removed something). The window refreshes a frame later,
  only while shown.

**Tests** (each mutation-tested):
- Store: a snapshot's shape at load (a bad mail drops the subtree; over 100 mails invalid; a
  boolean field; `complete = false` and `wasReturned = false` kept, not taken for missing); an
  older save with no `snapshots` keeps its other subtrees; a restarted clock drops snapshots
  (through `Load`, `Tick` and `Prune`); prune: the character gone → its snapshot goes, expired
  mails go, an emptied snapshot stays.
- Memory: no snapshot before the visit's first update, or after its close; update → close →
  reopen → the old callback saves nothing; several updates in one frame scan once; the old snapshot
  stays on an unresolved scan, a missing header, a missing `daysLeft`, or fewer attachments than
  `itemCount`; an inbox of a money-only mail, a plain letter and a mail with items is taken; `expires` rounded to the minute; currency left out; partial `complete = false`; a
  secret GUID saves nothing.
- Summary: AltStable's rule (an empty mail, an expired one, money only, the soonest).
- Window: opens on Sent, then on the last folder; Sent newest first with state, return and the
  other character's name; Trash's "gone in N days" and its note; Inbox rows, a character's mails,
  back, search across characters; search by name, subject, item name, two words; an item-name miss
  asks once, a success refreshes, a failure isn't asked again; forget on each row kind; a new
  Sent record while open shows a frame later, and one added while hidden shows on the next open;
  the pool never grows past its rows (1000 records); the scroll clamps; Escape's entry leaves in
  combat and comes back after, and a window built in combat gets it only after; the Inbox row's
  wording (summary, letters only, nothing recorded, empty when last seen, partial); the store not
  ready.

**In game** (the owner, after deploy):
- Open the window from the mailbox button and with `/gmail mail`; drag it; Escape closes it, and
  after a fight too.
- Send to an alt: the row appears while the window is open. Visit two characters' mailboxes: both
  show in Inbox with their summaries; open one.
- After a full client exit, search for an item by name in Sent: the names load and the row shows.
- Forget a row of each kind.
- **The freshness check, before v0.2.0** (`/gmail debug on`): two characters with visibly
  different inboxes, one empty; switch between them; reopen a mailbox quickly; open one right
  after login (a deferred `CheckInbox`). Each scan's debug line must show that visit's own inbox.

**Review outcome:** a snapshot needs every loaded mail read whole (a header at each index, days
left, attachments matching `itemCount`, nil being 0); the deferred scan belongs to its visit;
first-update freshness is an in-game gate, not a padded delay; a restarted clock drops snapshots
with their characters; "empty" is said only when seen empty; Escape's entry waits out combat at
creation too.

### The address PR in detail (PR 4 of M2; Codex gpt-6-astra, high, 2 rounds, consensus, 2026-11-12)

What it ships: S1, the picker and the last-recipient fill (both specified above), and the
`autofill` setting.

**Files** (TOC: `Address.lua` after `Window.lua`, before `Options.lua`; started at `PLAYER_LOGIN`
from `GlassMail.lua`, as the window is; `Blizzard_MailFrame` isn't load-on-demand):
- `Address.lua`: the picker button and its menu, the fill.
- `Core\Store.lua`: `chars[guid].lastTo` (optional string), `Store.SetLastTo(guid, key)`.
- `Core\Registry.lua`: `Registry.Touch` rewrites the current character's record every tick; it
  keeps `lastTo` (else the 10-minute tick would erase it).
- `Core\Sent.lua`: sets and clears `lastTo` (below).
- `GlassMail.lua`, `Options.lua`: the setting.

**`lastTo`** (as specified in "S1: the last recipient"):
- **Cleared first, on every `MAIL_SEND_SUCCESS`**, on the current character's record (the one
  that sent: mail is sent only from the open mailbox), before Sent's attribution: an error caught
  later in Sent's handler, a capture whose GUID or recipient wasn't readable, zero candidates (a
  send before a /reload) and two or more all leave it cleared. Another character's is never touched.
- **Set again** only in Sent's `save(rec, "sent")` for a `send` (never a return: `Sent.AddReturn`
  doesn't go there), on `rec.from`'s record: `Names.Key(rec.to)`, beside `Store.AddRecent(rec.to)`,
  when both are readable.
- `Store.SetLastTo(guid, key)`: `key` a string or nil; nothing when the Store isn't ready, the
  GUID has no record, or either is secret. No `Store.OnChange` (nothing the window shows).
- At load the `chars` spec takes `lastTo` as an optional string: a non-string is dropped, the
  record kept.

**The fill** (`Address.lua`):
- `fill()` writes only when all hold at that moment: `GM.db.autofill`, `Store.Ready()`,
  `SendMailFrame:IsVisible()`, `SendMailNameEditBox:GetText() == ""`, the current GUID's record has
  a string `lastTo`, and `Store.Recents()[lastTo]` exists. It writes that entry's `name` with
  `SetText`, then `HighlightText()`.
- **Tab 2:** a `hooksecurefunc("MailFrameTab_OnClick", fill)` post-hook. It needn't read the tab
  (`tabID or self:GetID()`, MailFrame.lua:189-192): `fill()` needs the send tab visible, which only
  tab 2 leaves it. The tabs call it with `self` (MailFrame.xml:884); Reply with `nil, 2`
  (MailFrame.lua:1092), then sets the sender over ours.
- **After a send**, as the spec says: Sent, having set `lastTo` in its attributed branch, calls
  one callback, `Sent.onConfirmed(key)` (Address sets it; no general notification), which
  schedules `fill()` with `C_Timer.After(0)`: by then every handler of that event has run
  (Blizzard's reset among them). `fill()` reads `lastTo` then, so an unattributed success in
  between (which cleared it) leaves nothing to fill.
- **Typing replaces it after a send**: the box has focus then (`SendMailFrame_Reset`,
  MailFrame.lua:1424), and the highlight is on. **On the tab's open** the box has no focus; a
  click into it may place the cursor and drop the highlight, so the player selects the name to
  replace it. No focus hooks on Blizzard's box (round 1: the extra interaction state isn't worth
  it).

**The picker** (`Address.lua`, as specified in "S1: the address book picker"):
- **Button:** ours, a child of `SendMailFrame`, 20 x 20, `LEFT` on the To box's `RIGHT` + 4 (the
  postage line is right-anchored at the frame's edge, MailFrame.xml:660-663); an address-book icon,
  a tooltip ("Glass Mail: pick a recipient"). Not disabled in combat: `SetText` isn't protected and
  nothing is sent.
- **Menu:** `MenuUtil.CreateContextMenu(button, generator)`, built on each click, scrolling past
  400 px (`root:SetScrollMode(400)`: 50 recents and the friends would pass the screen, and a menu
  scrolls only when asked, Menu.lua:1485), sections as titles, each skipped when empty:
  1. **My characters:** `Registry.Characters()`, `Registry.Reachable`, not `hidden`; by name.
  2. **Recent:** `Store.Recents()`, newest `day` first, then name.
  3. **Friends:** `C_FriendList.GetNumFriends()` and `GetFriendInfoByIndex(i)`, which may return
     nothing (FriendListDocumentation.lua:108: skipped), its `name`; online or not (mail reaches
     either); by name.
  4. **Guild:** `IsInGuild()`, `GetNumGuildMembers()`, `GetGuildRosterInfo(i)` (its first
     return); by name, in a submenu (`CreateButton("Guild")`) with `SetScrollMode(400)`.
     `C_GuildInfo.GuildRoster()` is requested when the picker opens; an open menu isn't rebuilt
     (session 6: on a loaded roster no `GUILD_ROSTER_UPDATE` comes), the next open has it.
  Nothing at all → one disabled line, "No names yet".
- **Each candidate:** `Names.Display`; a secret or blank name is skipped; `Ambiguate(name,
  "none")` drops the current realm's suffix (session 6: guild names unchanged by it); a name that
  still has a `-` (another realm: a character name has none) is left out; the current
  character's own name is left out; once per `Names.Key`, the first section wins.
- **A pick:** `SendMailNameEditBox:SetText(name)`, nothing else (no focus, no send).

**Setting `autofill`** (default on): `DEFAULTS.autofill = true`; `ensureDefaults` drops a
non-boolean; `Settings.SetAutofill(on)`; a checkbox under "Memory" ("Fill in the last name this
character mailed"); `/gmail autofill on|off` and its help line.

**Tests** (each mutation-tested): the spec's list ("S1: the last recipient", Tests), plus:
`Registry.Touch` keeps `lastTo`; a zero-candidate success clears it and keeps another
character's; an error inside Sent's success handling leaves it cleared (no fill, none on
reopening the tab); one candidate whose GUID or recipient wasn't readable leaves it cleared; an
attributed success then an unattributed one before the frame's timers: nothing filled; the setting
turned off or the recent removed before the deferred fill: nothing; `SetLastTo` refuses a secret,
an unknown GUID, a not-ready Store. Picker: each section and its order; empty sections skipped;
"No names yet"; the current character, hidden, unreachable, other-realm and secret names left
out; a friend index that returns nothing skipped; one name once across sections (first wins); the
menu and the guild submenu scroll; the roster asked on open; a pick fills the box and nothing else.
The setting: default, `ensureDefaults`, slash, checkbox. `test_methods` covers the new widget
calls.

**In game** (the spec's list, on the PR and in #27's issue): the send tab opens with the name;
after a send, typing replaces it (on the tab's open: what a click does to the highlight);
Blizzard's autocomplete still works once the player types over a filled name; the picker in
combat; `lastTo` after a full client exit; Reply puts the sender in; two sends in a row to an alt
need no typing; a stranger's send with an autofilled name and one with a picked name go through
the confirmation with no `ADDON_ACTION_BLOCKED` / `_FORBIDDEN`; the picker's sections with a
guild; a friend's name format (unmeasured, FOREVER-PROBE "Still open" 8).

### The grid PR in detail (PR 5 of M2; Codex gpt-6-astra, high, 2 rounds, consensus, 2026-11-12)

What it ships: I4 (specified above, "I4: mail bag grid") and the v0.2.0 release prep. It closes
#17; the tag waits for the in-game gate below.

**Files** (TOC: `Bag.lua` after `Address.lua`, before `Options.lua`; started at `PLAYER_LOGIN`):
- `Bag.lua`: the "Items" button, the panel and its grid.
- `Core\Loot.lua`: the item filter. `Core\Ops.lua`: the `items` run kind.
- `OpenAll.lua`: its end-of-run line names what an `items` run took.

**`Loot` with `opts.items`** (`{ [itemID] = true }`), in `mailAction`, before everything else:
- Unresolved first → `loading`: Scan can return an unresolved mail with no or some items listed
  (a secret header field, a missing link), so its contents prove nothing either way.
- Then a resolved mail with none of those items (by `itemID`, currency left out) offers nothing
  and counts nowhere in the tally (`nil, nil`), so "left 2 COD" means mails that hold the item.
- Then, as now: COD → `cod`, GM → `gm`. The type filters don't apply
  (the player chose the item, as with the selection) and **money is skipped**: the money-first
  branch is not reached.
- Then that mail's slots holding one of the items, from the lowest: `failed` (`MAIL_FAILED` named
  it this run), else `Loot.Fits` with `keepFree` (`full`, `loading`), the first that fits taken.
- `opts.only` and `opts.items` are never set together.

**`Ops`:**
- `Ops.TakeItems(ids, opts, onStop, onChange)`: `start("items", { items = copy of ids,
  keepFree = opts.keepFree, failed = {} }, ...)`. No remembered target: each dispatch takes what a
  fresh scan offers now, so twins are fine (as Open All).
- The kinds that wrap `C_Mail.SetOpeningAll(true/false)` and get a tally at the end become a set:
  `openall`, `selected`, `items`. Every stop condition already applies to every run.
- `Ops.Items()`: the active `items` run's set, else nil (the panel marks that button).
- `stats.units`: the summed stack `count` of confirmed item takes (the attempts already carry it,
  from the scan), beside `stats.items` (takes). Every kind keeps it; only the summary reads it.

**The panel** (`Bag.lua`):
- **The "Items" button:** ours, a 20 x 20 icon button (a bag icon, a tooltip "Items in the
  mailbox"), a child of `InboxFrame` (so only on the inbox tab) on the title bar, left of the
  window's button (`TOPRIGHT` -50, -2; the window's is at -28). Round 1: below the title, the
  selection bar spans x 80-326 at y -36 to -58 and Open (n) would sit under a button there. It
  toggles the panel; shown or not is remembered for the session.
- **The panel:** our frame, a child of `InboxFrame` (it hides with the inbox: the send tab, the
  close), anchored `TOPLEFT` to `MailFrame`'s `TOPRIGHT` (+2, 0), `MailFrame`'s height, glass
  through `Skin.AddWindow` (as the window: `stock` shows it smoked). A title ("Items in the
  mailbox") and a footer under the grid: "Click an item to take every copy", or, during an `items`
  run, "Taking *name*" and a **Stop** button (the fixed stop control: the clicked item's button
  can move, below).
- **The grid:** 6 columns, a fixed pool of 6 x 9 plain `Button`s (36 px: an icon texture, a count
  font string), a row offset with the mouse wheel when there are more distinct items. No
  `ItemButtonTemplate` (unmeasured here).
- **Entries**, from `Scan.Inbox()` at refresh: every non-currency attachment in the loaded inbox,
  merged by `itemID`: the total `count`, the number of mails holding it, and how many of those are
  COD (or GM). Order: first appearance in inbox order (stable while names load).
  `C_Item.GetItemIconByID` for the icon.
- **Tooltip:** `GameTooltip:SetItemByID(id)`, then "in N mails", and "N COD, left to you" when
  some are.
- **A click:** `Ops.TakeItems({ [id] = true }, { keepFree = GM.db.keepFree }, onStop, refresh)`.
  While that run is on, the footer's Stop button stops it (`Ops.Stop("stopped")`); the button
  showing that item, wherever it is now (the order is by first appearance, and a take can move
  it), has a glow and also stops it on a click; every other button is disabled. Each refresh
  repaints every pooled button whole (item, icon, count, enabled, glow), so a reused one keeps
  nothing of its last item.
  All disabled (and desaturated) while any other run, a letter, combat (`API.InCombat()`), or the
  gamepad UI mode. The end line: `OpenAll.Summary(r)`, which for an `items` run says "took 120
  Copper Ore" (`stats.units` and the item's name, `C_Item.GetItemNameByID`, "items" when not
  cached), then the existing "left …" and "stopped" parts.
- **Refresh**, only while the panel `IsVisible()` (it stays shown under a hidden inbox): its own
  `OnShow`, the `InboxFrame:Update` post-hook, `Ops.Watch`, `MAIL_INBOX_UPDATE`, the combat events
  (`API.NoteCombat` first), `INPUT_DEVICE_INTERFACE_TRANSITION`, the letter's show / hide. The
  offset is clamped at each refresh.
- **The selection:** a take changes its mail's fingerprint, and the selection drops a fingerprint
  that is gone (Inbox.lua, outside its own run), as after Open All. Unchanged.

**Release prep (v0.2.0, RELEASING.md §1, §3):** `CHANGELOG.md`'s `## Unreleased` becomes
`## v0.2.0` (the grid's line added); `README.md` and `README.curseforge.md` describe v0.2.0 (the
window, the memory, the address book, the fill, the grid, the new commands and options, nothing
it no longer does: `/gmail sent` and `/gmail trash` are gone); FEATURES.md and CLAUDE.md's status.
`.pkgmeta` ignores `README.curseforge.md` too (RELEASING §1; it is already gitignored), and the
PR says the local copy changed (the owner pastes it). No tag in the PR.

**The gate before the tag** (the owner, in game, after deploy of the commit to tag, noting the
client build and the LibGlass pin deployed): PR 3's whole list ("The window PR in detail", In
game: the window, Escape after a fight, live Sent, item-name search after a full client exit,
forget, the snapshot freshness check); #27's steps (through the window's Sent and Trash); PR 4's
list ("The address PR in detail", In game); and the grid's:
- the panel beside the inbox; the "Items" button on the title bar beside the window's, nothing
  overlapping with mails selected and with "too much mail" shown;
- a click takes every copy across several mails, including twins; money and other items stay;
  COD mail stays; a full bag stops with "no bag room"; a second click stops; the end line;
- the grid follows the inbox as mails go; the send tab hides it; it comes back on the next open;
- nothing blocked (the baseline's watcher).

**Tests** (each mutation-tested):
- Loot: with `opts.items`, money skipped, other items skipped, the lowest matching slot, COD / GM
  / failed / full left, a mail without the item not counted in the tally, type filters ignored;
  unresolved → `loading` both with the item listed (a missing link) and with an empty or partial
  list; one mail with the item in slots 1 and 3 (counted once, the second take is slot 3); a
  stack too big to fit, then a smaller one that fits a partial stack; a specialty bag at the
  `keepFree` boundary.
- Ops: an `items` run sets and clears `SetOpeningAll`, takes every copy across mails (twins too),
  confirms each from the inbox, sums `units` (a failed or unconfirmed attempt adds none), skips
  an ID `MAIL_FAILED` named, stops on one existing condition (the code is shared), and ends "done"
  with a tally; the stock Open All button shown mid-run puts `SetOpeningAll(true)` back, and the
  stop clears it.
- Bag: the entries (merge, counts, mails, COD, currency left out, order); the button toggles the
  panel; the pool never grows (200 distinct items); the wheel scrolls and clamps, also when
  entries go; a click starts the run for that item; the footer's Stop stops it, and so does the
  item's button where it moved (taking its first copy moves it out of view); the others are
  disabled; a reused button keeps no item, glow or enabled state of its last one; disabled in
  combat, with a letter open, during another run, in gamepad mode (and back, with no other event);
  the first open and a reopen after hidden updates show the inbox as it is; the tooltip lines;
  the end line; the skin repaint.
- The selection: taking from a selected mail drops it from the selection (`Selection.Get()`,
  `OnChange`), an untouched selected mail stays.
- `test_methods` exercises the panel.

### The searchable picker (S1, in PR 5; owner, 2026-11-12; Codex gpt-6-astra, high, 2 rounds, consensus)

**Why:** in game, a guild of several hundred made the `MenuUtil` guild submenu unusable (owner's
screenshot: a scroll through every name). A search box can't live in Blizzard's menu without
rebuilding the menu on each keystroke, so the address-book button opens **our own panel**
instead. (Blizzard's own To-box autocomplete already searches the guild as you type,
`AutoComplete.lua:19-22, 106`; the picker is for browsing your names and finding one by part of it.)

**The panel** (`Address.lua`, replacing the menu; `Address.Sections()` unchanged):
- Ours, a child of `SendMailFrame` (it goes with the send tab and the mailbox), anchored under
  the button (`TOPLEFT` to its `BOTTOMLEFT`, 0, -2), about 240 x 330, `DIALOG` strata, toplevel,
  glass (`Skin.AddWindow`, joins the repaint), a title ("Pick a recipient") and a close ×.
- **A search box** (our `EditBox`, `SetAutoFocus(false)`) at the top, **focused when the panel
  opens**. As you type, the list filters: lower-cased, plain `find`, every space-separated word
  must be in the name; **each change of the query puts the list back at the top**. Enter picks the
  first name of the filtered list (titles skipped; nothing when none). **While the search has
  focus, Escape closes only the picker**; without focus, Blizzard's own keyboard handling applies
  (the mailbox's Escape closes it, and the picker with it). No `UISpecialFrames` entry, no global
  key handler.
- **The list:** a fixed pool of rows (about 15 x 18 px), a row offset, the mouse wheel (3 rows a
  notch) and a thin `Slider` (as the window's). Rows are section titles (gold, not clickable) and
  names; a section with no name left after the filter isn't shown. Nothing at all: "No names yet"
  (empty query) or "No match".
- The guild is a section like the others (no submenu), all its members, filtered like the rest.
- **A pick:** a name row's click is `SendMailNameEditBox:SetText(name)`, then the panel closes.
  Nothing else (no focus given to the To box, no send).
- **Built once** (frame, pool, skin), **its data read when it opens:** `Address.Sections()`, the
  roster requested (`C_GuildInfo.GuildRoster()`), the query emptied, the offset 0. While it is
  open, `GUILD_ROSTER_UPDATE` re-reads the sections (a big roster may arrive after the request),
  keeping the query and the offset (clamped), and never taking focus.
- **Closes on:** the ×, Escape in the search box, the button again, a pick, a left or right mouse
  down outside the panel and the button (`GLOBAL_MOUSE_DOWN`, registered only while it is shown,
  as Blizzard's menus do, Menu.lua:54; the button's own mouse down is excluded, so its click
  toggles cleanly), **`MAIL_SEND_SUCCESS`** (attributed or not: Blizzard's reset focuses the To
  box, MailFrame.lua:1422-1424, and the deferred fill may fill it; the picker steps aside and
  doesn't take focus back), and its parent hiding (the inbox tab, the mailbox's close: the
  parent's `OnHide` closes it for real, so coming back to the send tab doesn't reopen it). **Every
  close is one cleanup:** hidden, the search's focus cleared, `GLOBAL_MOUSE_DOWN` and
  `GUILD_ROSTER_UPDATE` unregistered.

**Tests** (each mutation-tested; the `Address.Sections()` tests stay): the button opens and
closes it, through its mouse down then its click, both ways; the search box has focus on open;
filtering by one and two words, case, a `.` taken literally; a section with no match hidden, its
title too; "No names yet" and "No match"; scrolled down, a new query starts at the top, and so
does a reopen; Enter picks the first name (none: nothing); a click on a title does nothing; a pick
fills the To box, closes, and sends nothing; Escape, the ×, an outside mouse down closing it (one
on the panel or the button not); `MAIL_SEND_SUCCESS` closing it, with Sent's handler before and
after Blizzard's, the fill then landing in the To box; the send tab hidden or the mailbox closed
closing it for good (back on the send tab it stays closed); after every close the focus is
cleared and both events unregistered; a roster update while open and scrolled re-reads it (names
gone and reordered), the query and the focus as they were; a pooled row going name → title →
unused → name keeps nothing of before (its name, its click, its enabled state); the pool never
grows (500 guild members); the wheel and the slider scroll and clamp; the skin repaint.
`test_methods` exercises it.

**In game** (added to the gate): the panel under the button, nothing cut off by the screen's
edge at the default scale; typing filters a big guild and stays responsive, and a late roster
fills it in; movement keys type into the search while it has focus; Enter, Escape (with and
without the search's focus) and a click outside; typing and chat work after it closes; the To
box's own autocomplete still works after a pick; a stranger's send after a mouse pick and after an
Enter pick goes through the confirmation with nothing blocked.

### S1: completing a name as you type (owner, 2026-11-12, after v0.2.0; Codex gpt-6-astra, high, 2 rounds, consensus)

**Why:** in game, typing an alt of another WoW account into the To box offers nothing. The box's
completion is Blizzard's, from `C_AutoComplete.GetAutoCompleteResults` with
`AUTOCOMPLETE_LIST.MAIL` (`MailFrame.xml:630`, `AutoComplete.lua:106`): friends, guild, people
interacted with and **this WoW account's** characters. The client never sees the other accounts;
AltStable does, and the picker lists them, but only once opened.

**What it does:** where Blizzard completes nothing, Glass Mail completes the name **the way
Blizzard does** (`AutoCompleteEditBox_AddHighlightedText`, `AutoComplete.lua:392-418`): the rest
of the name is added, highlighted, the cursor after what was typed. Typing on replaces the
highlight; Backspace removes it; while Blizzard's dropdown stays hidden (it has no results),
Enter moves to the subject and Tab to the next field, keeping the name; losing focus clears the highlight
(`EditBox_ClearHighlight`), the text stays. All Blizzard's own key handling, untouched.

**How** (`Address.lua`, no new file, no setting):
- **One behavioural post-hook,** `SendMailNameEditBox:HookScript("OnChar", ...)`, at
  `Address.Start`, plus a diagnostic `OnTextChanged` hook that only logs while `/gmail debug on`
  (below). It runs
  after the template's `AutoCompleteEditBox_OnChar` (`AutoComplete.xml:8`; the box's own scripts,
  `MailFrame.xml:628-657`, don't replace it). Nothing else is hooked, written or replaced:
  Blizzard's `AutoCompleteBox`, its buttons, the box's `autoCompleteSource` and fields are left
  alone (the 2026-10-09 review's "a picker instead of an autocomplete hook" was about replacing
  that source; this doesn't). No focus hooks. OnChar fires for typed characters only (not
  Backspace, not a paste, not `SetText`), so the fill and the picker's pick never trigger it.
- **Only when all hold,** checked at that moment:
  1. the box isn't composing IME input (`b:IsInIMECompositionMode()`, an EditBox method);
  2. the text is a string, not secret, not empty (a `-`, another realm's, never starts one of
     our names, which have none);
  3. the cursor is at the end (`GetCursorPosition() == #text`, bytes): typing in the middle gets
     nothing, and so does a keystroke Blizzard just completed (its completion puts the cursor back
     before the added part, `AutoComplete.lua:410`);
  4. **Blizzard's dropdown isn't shown** (`AutoCompleteBox:IsShown()`, read only; any dropdown, not
     just this box's, which is the conservative side). A dropdown left from the previous letter
     could otherwise stay under our completion, and Enter would pick its entry over ours
     (`AutoComplete.lua:358-365`). Cost: when the previous letter had Blizzard results and this
     one has none, ours may come one letter later.
  5. **Blizzard has no result for the text:** the same call Blizzard makes,
     `C_AutoComplete.GetAutoCompleteResults(text, 1, GetUTF8CursorPosition(), true,
     AUTOCOMPLETE_LIST.MAIL.include, AUTOCOMPLETE_LIST.MAIL.exclude)`, returns no entry. This
     covers Blizzard's exact match too (it adds nothing, cursor at the end, but the name is
     Blizzard's: we must not lengthen it into another). The table or the list missing: nothing
     (we can't tell, so we don't compete); the call throwing: nothing, one `API.Fail`;
  6. **our match:** `Address.Complete(text)`, from **my characters only** (the problem is the
     other account's alts; Blizzard already has friends, guild and people interacted with): the
     picker's "My characters" list (reachable, not hidden, not the current character, no other
     realm's; one function now shared by `Address.Sections()` and the completion, no other section
     read), in name order, the first whose lower-cased start equals the lower-cased
     text (plain bytes, `name:lower():sub(1, #text) == text:lower()`) and that is longer than the
     text. **The whole list is checked first:** if the text already is one of them
     (case-insensitively), nothing, even when a longer one comes earlier.
- **The completion:** `SetText(name)` (the name's own case, as Blizzard's), then
  `HighlightText(#text, #name)` and `SetCursorPosition(#text)`, bytes, as Blizzard
  (`AutoComplete.lua:408-410`). `SetText` is the picker's pick (session 6: `SetText` then Send
  passed, through the stranger's confirmation).
- **Event order (measured in game, not assumed):** whether a typed character fires
  `OnTextChanged(userInput)` before or after `OnChar`, and whether our `SetText` inside `OnChar`
  turns that pending update's `userInput` false (Blizzard's comment says `SetText` clears it,
  `AutoComplete.lua:401`), isn't known on this client. Condition 4 keeps us off any shown
  dropdown in either order. One case stays open: a later `AutoComplete_Update` on the completed
  text with the cursor inside it (`AutoComplete.lua:167, 195`) is a different query from ours and
  might show Blizzard's dropdown under our completion; Enter would then take Blizzard's name. In
  game: the dropdown after a completion, both on a fresh box and after a letter that had
  Blizzard results. If it shows, that's a visible choice, not a silent overwrite; noted, not
  worked around (no Blizzard dropdown helper is called, they write Blizzard's fields).
- Errors: `safely("address complete", ...)`, one `API.Fail` key. My characters are read on each
  eligible keystroke (the registry, or AltStable's list live; no cache to go stale).

**Known limits** (said, not fixed): when Blizzard has any match, ours isn't offered even if it
is the alt you meant ("Ka" gives Blizzard's guildmate "Kaleid", not your other account's
"Karuzo"): type one more letter, or use the picker. Only my characters complete (a recent
recipient Blizzard doesn't know doesn't). Inline only, no dropdown entry. Lower-casing is ASCII
(`string.lower`), so an accented capital matches only as typed.

**Tests** (`test_complete.lua`, each mutation-tested). The stubs get enough of Blizzard's
autocomplete on the To box: `C_AutoComplete` answering from `WoW.autocomplete` (the text up to the
UTF-8 cursor, case aside), `AutoCompleteBox` shown with the results, the box's `OnTextChanged` /
`OnChar` / `OnEnterPressed` as `AutoComplete.lua` has them; `HighlightText` keeping its byte range;
the cursor; `SetText` putting the cursor at the end and clearing the highlight. A typing helper: a
character replaces the highlight or goes in at the cursor, then `OnTextChanged(true)` and `OnChar`
in either order (with `OnChar` first, a `SetText` inside it takes the typed change's own update
away, the worst case). Cases: an other-account alt from AltStable completes ("ve" → "Vex Morrow",
highlighted from 2, cursor at 2), in both orders; the next matching letter keeps it, one that
doesn't leaves what was typed; Enter then keeps it; Blizzard's result wins (its completion
unchanged), and so does its exact match; a dropdown shown from the previous letter, then a letter
Blizzard has nothing for: not completed (in the `OnChar`-first order), and Enter doesn't swap what
was typed for a stale entry; IME composing: nothing; the cursor in the middle, a selection in the
middle: nothing; `Address.Complete` of an empty, a secret or a whole name: nil; a selection through
the end replaced (the last-recipient fill's whole highlight, then a letter): completes; typing over
a pick: completes; the text already one of my characters, a longer one beside it: nothing more; the
case taken from the name; name order; the current character, a hidden, an unreachable or a third
party's one, a recent, a friend or a guild member: never offered; this realm's suffix dropped,
another realm's name never offered; `C_AutoComplete`, its function or the list missing: nothing; it
throwing: one `API.Fail` and the box as typed; a typed prefix that holds a multi-byte character
highlights from its byte length; the debug trace off and on. `test_methods` types into the box.
Equivalent mutants, kept: `Complete`'s secret check (the kit's secrets are userdata, caught by the
type check; a client secret string may not be) and the trace's early return (`API.Debug` checks too;
it saves the formatting).

**In game:** typing the start of another account's alt completes it; with Blizzard's dropdown
hidden, Enter, Tab and a click on Send keep it; a stranger's send after a completion, with an item
or money, goes through the confirmation; a name Blizzard knows still completes Blizzard's way, its
dropdown as before; after a completion, whether Blizzard's dropdown shows (fresh box, and after a
letter with Blizzard results), and if it shows, the recipient Enter leaves; which order
`OnTextChanged` / `OnChar` came in (`/gmail debug on` logs each, numbered, after Blizzard's handler,
with the cursor, the text's byte length, the dropdown, and a line before our `SetText`; start with a
prefix nobody completes, then compare one of ours with one of Blizzard's); Backspace, Delete, typing
in the middle, a paste and focus loss behave as before.

### Review outcome (Codex gpt-6-astra, high, 5 rounds, consensus, 2026-10-13)

- **Sent:** a pending send survives a mailbox close (a success came 99 s late); no inferred
  `failed` (`MAIL_FAILED` has no action identity); any overlap leaves the rest of the session
  unconfirmed; unconfirmed sends still show.
- **Trash and returns:** capture rule decided by session 6; a fallback for removals known in
  advance; any later inbox-changing call drops an outstanding capture; the open letter's capture
  needs the same, unique fingerprint (twins void it).
- **AltStable forgetting is not mirrored** (a fresh AltStable looks like "forgot everyone").
- **The play-day clock** also advances over midnight; the version covers only the new data, never
  the settings; realm suffixes are kept until measured; the item filter precedes money-first.
- **Order:** the window (Sent first) before the picker; contacts cut.

## M3: LibMailbox-1.0 (owner, 2026-11-12; Codex gpt-6-astra, high, 2 rounds, consensus)

**Why.** AltStable reads the inbox too, twice: `Core.lua` `ScanMail` (the synced `mail_count` /
`mail_expiry` / `mail_money` summary) and the Warband plugin's `ReadInbox` (attachments by item ID).
Neither tests for secret values, and the summary rule is written twice (GlassMail's `Summary.Of`
copies AltStable's). One library reads the inbox the same way for both (each addon still calls it
itself: no shared cache, no event ownership). Nothing a player sees changes.

**What moves.** `Core/Scan.lua`, `Core/Summary.lua`, `Core/Names.lua`: the inbox as plain values,
the fingerprint and its residuals, the AH-subject classification, the "worth keeping" summary, the
name key. What stays in GlassMail: Loot, Ops, Store, Memory, Sent, Trash (one consumer each).

### The library (`C:\Projects\WoW\LibMailbox`, github.com/Spotnick2/LibMailbox, public, MIT)

LibShowcase's layout: no TOC; `LibMailbox-1.0.xml` loads `LibStub\LibStub.lua`, then
`LibMailbox.lua` (`MAJOR, MINOR = "LibMailbox-1.0", 1`); `LICENSE`; `README.md`; `CLAUDE.md`;
`docs/DESIGN.md` (the contract and the measured facts, cited from GlassMail's FOREVER-PROBE.md);
`.pkgmeta` (never packaged alone; the ignore list consumers repeat under `Libs/LibMailbox-1.0/`);
`Tools/deploy.ps1` (copies the XML, what it loads and LICENSE into `AddOns\<Addon>\Libs\LibMailbox-1.0`,
as LibGlass's does); tests on WowTestKit (`tests/kit.pin`, the current pin); CI `check.yml` (luac,
tests) like LibGlass's. Tagged `r1` once merged; consumers pin the tag.

**The API: functions, dot-called, no state, no frames, no events.** Within `LibMailbox-1.0` the API
only grows (LibShowcase's contract). Every function is looked up on `lib` when called: a consumer
keeps `local LM = LibStub("LibMailbox-1.0")` and calls `LM.ScanInbox()`, never a captured
function, so the newest copy loaded runs (LibStub). `lib.ready = MINOR` is the last line.
- `LM.ScanInbox() → scan`: today's `Scan.Inbox()`: `{ loaded, total, mails, resolved }`, each mail
  `{ index, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned, canReply, isGM,
  type, items = { { slot, itemID, link, count, isCurrency } }, resolved, fp }`. Two additions:
  - a mail whose **header** was withheld (a secret header field) is `{ index, secret = true,
    resolved = false, items = {} }` (today: the same without `secret`). A secret *attachment* field
    leaves the header readable and only stops the fingerprint, as today: no `secret` flag;
  - `scan.headers` is true only when the counts were readable, every index up to `loaded` returned
    a header (today a missing one is skipped silently; Memory.lua:31 already rejects that
    mismatch) and none was withheld. A secret count gives `{ loaded = 0, total = 0, mails = {},
    resolved = false, headers = false }`: unreadable, never "empty".
  `resolved` is unchanged: a missing attachment link makes a scan unresolved but leaves its headers
  good. Never `GetInboxText`. Read-only: no call that changes the inbox or marks mail read.
- `LM.Fingerprint(mail)`, `LM.Count(scan)`, `LM.Residual(mail, kind, slot)`: today's, unchanged.
- `LM.Summary(mails, now) → { count, money, soonest } | nil`: the rule both addons share, over two
  disjoint shapes; a mail with an `expires` field is a saved one, any other a live one:

  | Shape | Counts when | Its expiry |
  |---|---|---|
  | live (a `ScanInbox` mail) | (`itemCount > 0` or `money > 0`) and `daysLeft > 0`: the header, AltStable's rule exactly (Core.lua:2936); `items` is never read | `LM.Expires(daysLeft, now)`, never compared with `now` |
  | saved (a snapshot mail, Memory.lua) | (`#items > 0` or `money > 0`) and `expires > now` | `expires` |

  `money` is summed, `soonest` is the smallest expiry; nil when none counts (the caller clears its
  fields). A missing `daysLeft` doesn't count (never `nil > now`); a withheld mail counts for nothing.
  Parity cases (tests): one second left (`daysLeft = 1/86400` at `now = 100000`) counts, its
  expiry rounded to 99960; zero, negative or absent `daysLeft` doesn't; `itemCount = 1` with
  `items = {}` counts; `itemCount = 0`, no money, a non-empty `items` doesn't (the header decides);
  a plain letter doesn't, money with a nil `itemCount` does; an inbox of only non-counting mail is nil.
- `LM.Expires(daysLeft, now)`: `math.floor((now + daysLeft * 86400) / 60) * 60`, AltStable's
  rounding (stable across re-scans), which GlassMail's Memory.lua already uses.
- `LM.NameKey(name)`, `LM.NameDisplay(name)`: today's `Names.Key` / `Names.Display`.
- Secrecy: the library's own `issecretvalue` test (absent function: nothing is secret), before any
  other use of a value, as today.
- `LM.Ready() → bool`: `lib.ready ==` LibStub's current minor for `LibMailbox-1.0`. A newer copy
  that failed half-way has claimed its minor and replaced some functions while `ready` still holds
  the old one: then false. Consumers call it at each entry (GlassMail's adapters, AltStable's
  `ScanMail`) and read nothing when false (a scan is unreadable, a summary nil).
- Fingerprints are opaque session identifiers; their encoding doesn't change within the major
  version without a reason a consumer can live with (none saves one).
- Private helpers stay per-copy locals: nothing escapes into a callback, so no `lib.impl` layer.

**Upgrade.** Stateless, so an upgrade is the newer copy's functions replacing the older's on the
same `lib` table. The AH patterns are cached per copy (rebuilt by the newer copy). `test_upgrade.lua`
(EMBEDDED-LIBRARIES.md's first-release pattern: a synthetic newer copy, since LibStub skips an
equal minor): current then MINOR+1 with observably changed functions: a held `LM` and an adapter
made before reach the new ones, the table keeps its identity, a scan returned by the old copy goes
through the new `Summary` / `Residual`; the reverse order changes nothing; an equal copy changes
nothing; a MINOR+1 that errors after replacing some functions makes `LM.Ready()` false. The real
`r1` file is frozen as a fixture once tagged, for later upgrades. Each consumer's tests go through a failed
upgrade too: GlassMail's adapters still serve their callers (`Scan.Inbox` then `Scan.Count`, as
Inbox.lua's refresh does: an unreadable scan, an empty count), AltStable's seeded `mail_*` fields,
`lastUpdate` and refresh stay untouched.

**Tests** moved from GlassMail (`test_scan`, `test_summary`, `test_names`, unchanged in substance,
on the library's own stubs: `GetInboxNumItems`, `GetInboxHeaderInfo`, `GetInboxItem`,
`GetInboxItemLink`, the six `AUCTION_*_MAIL_SUBJECT` globals), plus `Summary`'s two shapes and its
parity cases, `Expires`, `secret`, `headers` (a secret count, a missing header row), `Ready`, and the
upgrade. Mutation-tested.

### GlassMail (one PR, after `r1` is tagged)

- `.pkgmeta`: the `Libs/LibMailbox-1.0` external at `tag: r1`, its ignore entries.
- TOC: `Libs\LibMailbox-1.0\LibMailbox-1.0.xml` after LibGlass, before `Compat.lua`.
- `Core/Scan.lua`, `Core/Summary.lua`, `Core/Names.lua` become one thin `Core/Mailbox.lua`: `GM.Scan`,
  `GM.Summary`, `GM.Names` keep their names and signatures and call `LM` at call time
  (`Summary.Of(snapshot, now)` keeps its guard: nil for a snapshot that isn't a table with a `mails`
  table, else `LM.Summary(snapshot.mails, now)`; `Scan.Inbox()` is an unreadable scan when
  `LM.Ready()` is false). No call site changes.
- Tests: GlassMail's `test_scan` / `test_summary` / `test_names` shrink to the adapters (the logic is
  tested in the library); the harness loads LibMailbox the way it loads LibGlass (`$LIBMAILBOX`,
  else `..\LibMailbox`); CI fetches both externals (`tests/fetch_external.sh`) and the zip
  allowlist and the "packaged library is the pinned commit" step cover both; `tests/run.ps1` and
  `Tools/deploy.ps1` report each library's pin status and deploy LibMailbox through its own
  `Tools/deploy.ps1` (`Tools/LibGlassPin.ps1` already takes the library path). The allowlist lists
  LibMailbox's XML, what it loads and LICENSE (no `Media`).
- Docs: CLAUDE.md (layout, the library), FEATURES/PLAN status, LICENSE's third-party section.

### AltStable (one PR, in a worktree off `origin/main`: the owner's checkout has work in progress)

- Embeds LibMailbox as it embeds LibShowcase (`.pkgmeta` external `tag: r1` + its repeated ignore
  entries, TOC line, `tests/fetch_libmailbox.sh` + `tests/libmailbox.lua` like `libshowcase`'s, CI,
  deploy), with `test_packaging`'s ignore and TOC checks extended to it. Every test that loads
  `Core.lua` directly (`test_comm` first) loads the library too, and its mail fixture stubs
  `GetInboxItem` / `GetInboxItemLink` for the scan.
- `Core.lua` `ScanMail`: if `LM.Ready()` is false or `scan.headers` isn't true, nothing is written:
  the three fields, `lastUpdate` and the refresh stay as they were (an unreadable inbox is not an
  empty one). A deliberate change: the old code had no secret guard. Else `LM.Summary(scan.mails,
  now)` sets or clears `mail_count` / `mail_expiry` / `mail_money` exactly as today. The fields, the
  sync payload and `CheckMailAlerts` are unchanged; `test_comm`'s existing mail assertions pass
  unchanged, and the parity cases join them.
- **Cost:** AltStable reads headers only today; `ScanInbox` also reads each attachment slot (16
  `GetInboxItem` per mail with a truthy `itemCount`, a link per occupied slot) on every
  `MAIL_INBOX_UPDATE`. A known call-count increase, not a measured problem: the in-game check
  watches for it, and a header-only scan is an additive API for a later round if it shows.
- **Not** the Warband plugin's `ReadInbox` in this round: it ignores currencies, refuses a read when
  a count is missing or not positive and scans the slots even with a nil `itemCount`, where
  `ScanInbox` keeps currencies, takes a missing count as 1, skips a mail with a nil `itemCount` and
  calls a mail unresolved when its link is missing. Adopting it changes when a Warband read is
  recorded: an AltStable issue for a later round, with a narrow secret guard meanwhile.
- AltStable's version bump and release are the owner's.

### Order

1. LibMailbox repo: the scaffold on `main` (README, LICENSE, `.gitignore`: a new repo has no other
   branch to start from), then the library in a PR.
2. Both consumers' changes on their branches, tested against the library's checkout
   (`$LIBMAILBOX`, LibShowcase's discipline) before `r1` is frozen.
3. The library PR merged, `r1` tagged; the consumer PRs pin `r1` and their CI tests it.

**In game:** GlassMail's Open All, the selection, the grid and a snapshot behave as before (the
debug line's scans); AltStable's sheet shows the same mail column after a mailbox visit with both
addons loaded, and with only AltStable; no hitch opening a full mailbox (the scan's cost).

## N2: recall (M4, #50; owner, 2026-11-12; Codex gpt-6-astra, high, 2 rounds, consensus; built)

FEATURES.md's N2: a mail sent to the wrong one of your characters goes back in one deliberate
click. From the Sent folder, the player marks a send **recall**; when the character it went to
opens a mailbox, the mails that could be it are highlighted, and a sure one gets a Return button.
v1 is local: both characters on this WoW account, so both read the same `GlassMailDB`.
Cross-account recall stays "Later" (LibAccountSync).

**Why it can stay small.** Both ends are the player's own characters, and a return only sends
the mail back to its sender. So a wrong match costs one mail travelling back to another character
of yours, never a loss. The return itself, its confirmation and its record already exist:
`Ops.Act("return", fp)` (one match, no twin), and Trash's confirmed return (`Sent.AddReturn`),
which also sees returns made by hand with the letter's button.

### What is saved

Two optional fields on a `sent` record (`Store` SPECS; `Store.VERSION` stays 1, and an older Glass
Mail drops them on load, so a downgrade forgets recalls and nothing else):
- `recall = true` while marked;
- `fromName`: the sending character's name, copied from `chars[from]` when it is marked (a
  record has only the sender's GUID, and its `chars` entry can age out before the mail is found).

`Store.SetRecall(rec, on)` takes the saved record itself, as the forget calls do, sets (or
clears) both fields, then calls the watchers. A record must stay comparable on its own: the Store
cleans each optional field separately, so `recall = true` can survive a `fromName`, `items`,
`money` or `cod` that was dropped. `Matches` therefore checks the record too (below), and such a
record matches nothing, can still be unmarked, and never throws. Nothing else is saved: where the
mail is now is worked out each time (below). A recall ends with its record (play-day expiry, the
1000 cap), when it is unmarked, or when its mail is returned.

### `Core/Recall.lua` (no frames)

Loads after `Core/Sent.lua`, before `Core/Trash.lua`.
- **`Recall.CanMark(rec)`**, and why not (for the tooltip): a `send` (not a return); its `subject`,
  `money`, `cod` and `items` all saved (a field that was secret at capture is missing, and then
  nothing can be compared); items or money in it (a letter alone isn't worth a recall, and
  Blizzard may only offer Delete for it); `chars[from]` known (its name becomes `fromName`); the
  recipient one of `Store.Chars()`, by `Names.Key`, whose GUID isn't `rec.from` (the record's
  sender, not whoever is browsing Sent): a character that has logged in with Glass Mail on this
  account. Not AltStable's list: a character of another account, or one that never ran Glass
  Mail, would never see the recall. The tooltip says so ("Log in to it once with Glass Mail").
  And mail can reach it from the sender: `Registry.Reachable`'s rule applied to the two saved
  characters (same faction, same known ruleset), not to the current one, since a recall can be
  marked from another character's history. A send across factions can still be saved
  `unconfirmed`.
- **`Recall.Matches(rec, m)`**: `m` is a scanned mail (live shape, items `{ itemID, count }`) or a
  snapshot's (saved shape, `{ id, count }`). False unless the record is comparable: a non-empty
  `Names.Key(rec.fromName)`, and `subject`, `money`, `cod` and `items` all present (a missing
  money is unknown, never 0). True when: not `wasReturned`; `Names.Key(m.sender) ==
  Names.Key(rec.fromName)`; `m.subject == rec.subject` (the `SendMail` argument: Blizzard puts an
  item's name in an empty subject box before Send, MailFrame.lua:1302-1306, so it is what was
  sent); money and COD equal; the attachments equal as a multiset of (itemID, count), whatever
  their slots, and, on a live mail, `#m.items == (m.itemCount or 0)` over the full list, currencies
  included (`itemCount` counts occupied slots; a secret field stops LibMailbox's attachment list
  part way, and a partial list must not match a smaller send). Memory.lua checks the same before
  it leaves currencies out of a snapshot.
  **No test of the mail's type:** LibMailbox classifies by the AH subject templates before
  `canReply`, so an alt's mail titled like an AH one is `ah`; the sender's name (one of your
  characters) already rules out real AH and system mail. Header values and item IDs only, so a
  mail still loading its links can match (it can't be returned until it resolves). That the
  received mail carries exactly the sent subject, money and items is unmeasured: the in-game check.
- **`Recall.Mine()`**: the marked records whose `to` is the current character (`Names.Key` of
  `API.PlayerFullName()`), oldest first. Read from `Store.Sent()` on each call (a thousand records
  at most, on an inbox refresh: cheap).
- **`Recall.Inbox(snap, counts)`**: for the inbox the player sees. Each recall's matching mails,
  and each mail's state:
  - **sure**: the recall's only matching mail, unique (`counts[fp] == 1`), and Blizzard would return
    it (`Ops.RowAction(m) == "return"`);
  - **possible**: anything else that matches: two or more mails, twins, a mail still loading (no
    `fp`), or one Blizzard won't return.
  Two identical recalls (the same send made twice) share their mails: one matching mail is still
  sure, and returning it ends the oldest recall. No one-to-one assignment. **Sure means one
  actionable candidate, not proven identity:** an older identical mail, or an unconfirmed send
  that never arrived, can make some other mail the only match. Within the premise that costs a
  mail going back to your other character. No arrival-time test (`daysLeft`): no measured formula
  covers every send (COD included), and a wrong one would hide the real mail.
- **`Recall.OnReturned(m)`**: Trash calls it after `Sent.AddReturn`, for a confirmed return, ours
  or by hand. The oldest of `Recall.Mine()` that matches `m` loses its mark, and chat says
  "Glass Mail: sent back to <sender>: <subject>". Trash hands over the mail as it was before the
  return, so `wasReturned` is still false there. These leave the mark, and the player unmarks it
  (the Sent row shows no matching mail): a return Trash can't confirm (its "left out" cases),
  a mail whose money or some items were taken before its return (the rest no longer matches; no
  fuzzy matching), and the game's own return at expiry.
- **`Recall.Seen(rec)`**, for the Sent row: the recipient's snapshot (Core/Memory.lua) against
  `Matches`: "matching mail in <To>'s mailbox (<ago>)" (a match in a partial snapshot counts too),
  "no matching mail in what Glass Mail saved of <To>'s mailbox (read <ago>)" (only from a complete
  one, and worded as memory: a mail forgotten in the window or pruned at its expiry leaves the
  snapshot without it, and a partly taken one no longer matches, while the mailbox may still hold
  it), "<To>'s mailbox not read whole" (incomplete, no match), "<To>'s mailbox not seen since" (no
  snapshot, or one older than the send).

### The inbox (`Inbox.lua`)

On every refresh (it already runs on each `InboxFrame:Update`, inbox update, letter, combat and
Ops change), `Recall.Inbox(snap, counts)`, over the refresh's own scan and counts. **The refresh
also subscribes to `Store.OnChange`:** marking, unmarking or forgetting a recall in the window
while the mailbox is open, and `OnReturned`, must repaint at once (else an unmarked recall keeps
an enabled Return button: Ops checks the mail, not the recall).
- **Rows:** a tint on each matching row, our own texture on our own frame over `MailItemN`, under
  our checkbox and icon, mouse disabled (the stock row keeps its clicks): the accent for sure,
  amber for possible. Shown under glass and stock alike. The row tooltip adds "Glass Mail: you
  asked to send this back" (sure) or "Could be a mail you asked to send back: check it"
  (possible); the tooltip hook's early return (no attachment lines, no truncated subject) must let
  a recall line through.
- **The notice:** one line in a glass strip under the mail window, below Blizzard's Inbox / Send
  Mail tabs (their bottom is 30 px under the window's, MailFrame.xml:870; the strip's top is 34)
  (a child of `InboxFrame`, like the item grid beside it; every band inside is taken: the message
  count and the bar above the rows, Prev / Open All / Next in the footer, and a button over Next
  would take its click; PR #51's review, twice), whatever the page: "Recall: <subject>,
  from <sender>" and a **Return** button for a sure match; for possible ones, "N mails could be
  <subject>: check the highlighted rows" and no button (twins: "open one and use its Return
  button"). Several recalls: the first sure one, then "+N more".
- **Return** calls `Ops.Act("return", fp, ...)` with the same guards as the row icon: not in combat,
  no run, no open letter, the inbox resolved, the mail unique, its tooltip saying why when
  disabled. The click is the only thing that acts; nothing returns by itself, on any event.

### The Sent folder (`Window.lua`)

- A recall toggle on each send row, left of the forget ×; none on a return. Enabled for a marked
  record (to unmark it) or one `CanMark` accepts; otherwise disabled, its tooltip giving
  `CanMark`'s reason (a send to someone else, a secret field, nothing attached), with motion
  scripts while disabled as the inbox's controls have. The faction and ruleset test fails when
  either character's faction or realm is missing: two unknowns don't agree.
- A marked row's top line gets an amber "recall", and its right-hand text `Recall.Seen(rec)`
  instead of the date.
- The search and the forget × work as before; forgetting a record forgets its recall with it.

### Tests

`tests/test_recall.lua`, each case mutation-tested:
- `Matches`: each criterion alone (sender, subject, money, COD, a count, an extra or missing item,
  a returned mail), slot order ignored, repeated item IDs, both item shapes; an alt's mail with an
  AH-shaped subject matches, a real AH mail (its sender) doesn't; a partial attachment list
  (fewer read than `itemCount`) doesn't; a record missing `fromName`, `items`, `money` or `cod`
  matches nothing;
- `CanMark`: each reason (a return, a field missing, nothing attached, an unknown sender, the
  recipient not in `chars`, the recipient the sender, another faction, another ruleset), judged
  from the record's sender while another character browses; AltStable's characters not counted;
- the Store: the two fields kept on load, junk dropped field by field, `SetRecall` on a record not
  in the list refused, both fields set before the watchers run;
- the inbox: sure, two matches, twins, loading, a mail Blizzard won't return, two identical recalls,
  a recall for another character ignored; the Return button calls `Ops.Act` with that fingerprint
  and nothing else does; disabled in combat, during a run, with a letter open; unmarking with the
  mailbox open repaints (no button left); a recall-only row tooltip shows;
- `OnReturned`: our return and one by hand (through Trash's confirm path) end the oldest matching
  recall and say so; an unconfirmed return ends nothing;
- the window: the toggle's shown / hidden / reason, the "recall" tag and each `Seen` line; a
  matching snapshot mail forgotten in the window gives the saved-memory wording, never "not in
  the mailbox".

### In game

1. Send an item and some gold to an alt that has logged in with Glass Mail; mark it in Sent; check
   the row says "<To>'s mailbox not seen since".
2. Log in to the alt, open the mailbox: the row is tinted, the notice names it, Return sends it
   back, chat says so, the Sent row (on either character) no longer says recall. Before the
   return, the Sent row says "in <To>'s mailbox": the received subject, money and items equal the
   sent ones (the unmeasured assumption; if not, the row says "no matching mail", and the notice is absent).
3. Two identical sends: both rows possible, no button.
4. A send to a character that never ran Glass Mail: the toggle disabled, its tooltip says why.
5. The shapes: a money-only send, a COD send, several attachments with a repeated item, a subject
   shaped like an AH one ("Auction won: ..."): each matches.
6. With the alt's mailbox open, mark and unmark from `/gmail mail`: the tint and the notice follow.
7. One return with Blizzard's letter button: the recall ends too.
8. Mark one, exit the client fully, relaunch: still marked (the new fields persist).

## N1: the bank character (M4, #50; owner, 2026-11-13; plan, Codex gpt-6-astra, high, 3 rounds so far)

FEATURES.md's N1: name a bank character and simple rules, and one click fills a draft of what
should go there; the player still presses Send. The owner's choices (2026-11-13):
- **One bank per faction and ruleset group** (not a recipient per rule: that is Kerzo's auto-send,
  which FEATURES keeps out).
- **A button fills the draft.** At the mailbox, one chat line says what is ready; on the Send tab,
  our button fills an empty draft; the player checks it and presses Send; the button then offers
  the next batch.
- **The rules live on a Bank page in the Glass Mail window** (`/gmail mail`).

**Why it can stay small.** We never send: Blizzard's Send button and its confirmation do, as for
every mail. Our code only puts items from the bags on the cursor and drops them on the draft's
attachment slots, which is what the player's own clicks do. Sent already records the send
(`Core/Sent.lua`, at the `SendMail` post-hook). What we promise is narrower than FEATURES' first
wording ("checks everything again before sending"): the bags are read again at the click, the
draft is verified after filling, and the player reviews it and sends. A `SendMail` post-hook is too
late to veto a send, and nothing here pretends to.

### Measured (session 7, 2026-11-13, FOREVER-PROBE.md)

- **A whole stack attaches by code**: `C_Container.PickupContainerItem` then
  `ClickSendMailItemButton(slot)`, from a click, a frame later, and **from a timer** (no key
  press). It is in the draft at once (`MAIL_SEND_INFO_UPDATE` fires inside the drop). Three stacks
  in one frame all landed.
- **Attachments stay in the bags**, locked, at their full count, until the send succeeds; a close
  of the mailbox empties the draft and unlocks them.
- **A split dropped on the draft attaches the whole source stack**: "split 2" of a 10-stack put all
  10 in the draft (and they were sent). **Session 7b: a split into an empty bag slot works**, and
  that stack attaches alone (exactly 2 sent). The bags change only when the server answers (the
  new stack shows within about a second, unlocked), so a split is its own click (Prepare, below).
- **A soulbound item is refused**: `UI_ERROR_MESSAGE` 460, the item stays on the cursor, and
  `ClearCursor` puts it back unlocked. `ContainerItemInfo.isBound` and `C_Item.IsBound` agreed on
  every item (a heirloom too).
- Blizzard fills an empty subject with the first attachment ("Windstone (5)"); our right-click
  clear by code works; a send to the player's own alt showed no confirmation, success 0.22 s later.
- Session 7b also: a split put straight back is whole again at once (`ClearCursor`); a delayed
  attach due after a mailbox close stopped and moved nothing. Unmeasured: a code-filled draft
  through the secure-transfer confirmation (a bank on another account); Blizzard's own dialog
  does that send.

### What is saved

A new `bank` table in `GlassMailDB`, loaded and checked by `Core/Bank.lua` itself (a small
loader, not Store's generic one; `Store.VERSION` stays 1; an older Glass Mail ignores it):
- `bank.banks[group] = { name, guid? }`: the bank's mail address ("First Surname") and its GUID
  when it was picked from your characters. `group` is `faction .. ":" .. ruleset`
  (`Registry.RulesetOf`); an "Unknown" ruleset gets no bank.
- `bank.rules`: a list, each exactly one of `{ item = itemID, keep = n }` or
  `{ class = c, sub = s?, keep = n }` (`sub` absent: the whole class, for Recipes). IDs are
  positive integers, `keep` an integer 0-9999, a category one of the offered ones (below). Adding a
  rule that exists (same item, same class and sub) updates its keep. An entry that fails is
  dropped alone.

Not expired: the owner set them, unlike the lists that grow by themselves (the "no stale
characters" rule). The bank is resolved live: by its GUID in `Registry.Characters()` (AltStable's
list included, so a bank on another account resolves too) for its current name and reachability;
the saved name is the fallback for one no list knows. It is "this character" by GUID, or by name
key (`Names.Key`) when the GUID is unknown.

### `Core/Bank.lua` (no frames)

Loads after `Core/Recall.lua`.
- **`Bank.Group(c)`**: a character's group, nil when its faction or ruleset is unknown.
- **`Bank.For()`**: the current character's bank `{ name, guid }`, or nil and why (none set; the
  bank is this character; not reachable, when the bank resolves to a known character).
- **`Bank.Rule(itemID)`**: the item rule, else the category rule for its
  `C_Item.GetItemInfoInstant` class and subclass (no cache needed), else nil.
- **`Bank.Plan()`**: one mail's worth, from a fresh read of bags 0-4 (never cached). Per itemID
  with a rule: `total` counts every unit in bags 0-4 (bound, locked and refused ones too: they
  stay, so they count toward keep), `excess = total - keep`; then **movable** stacks (unbound,
  unlocked, not refused this session) are taken whole, smallest first, while each fits in what is
  left of the excess. A remainder that no whole stack fits (session 7b measured the split) is a **split to
  prepare** (below), into an empty general bag slot, one per item, only while empty slots are free.
  Up to 12 attachments. Returns the stacks and how many items would
  still be movable after this batch. Simple over optimal: stacks of 6 and 10 with keep 6 send the 6.
- **`Bank.Ready()`**: what the algorithm can actually move in all (the chat line, the button).

Categories offered (ItemSubClass, build 70938, `References\Forever\db`; session 7's bag scan
confirmed items carry them, e.g. a herb 7.9, a part 7.11): Trade Goods' Cloth (7.5), Leather
(7.6), Metal & Stone (7.7), Cooking (7.8), Herb (7.9), Elemental (7.10), Enchanting (7.12), Parts
(7.1) and Other (7.11), and Recipes (class 9). Names from `C_Item.GetItemSubClassInfo` /
`GetItemClassInfo` at run time, never saved.

### The Send tab (`Bank.lua`)

- **The button**: ours, on the mailbox's title bar beside the window's, shown on the Send tab
  only; its tooltip says "Fill for <Bank>: n items (m mails)" or why it is off. Its place is
  checked with a screenshot.
- **Enabled when** a bank is set for this group and reachable, `Bank.Ready()` has something, the
  cursor is empty, not in combat (`API.InCombat`), no Ops run, and **the draft is empty**: no
  attachment, the subject and the body empty, `MoneyInputFrame_GetCopper(SendMailMoney) == 0`
  (the widget: `GetSendMailMoney()` stays 0 until the Send click copies it, session 6) and COD
  unchecked; any of them unreadable disables it.
- **No send in flight.** Blizzard keeps a sent draft (subject, attachments) until
  `MAIL_SEND_SUCCESS` resets it, so an empty draft already rules out its own pending send. On top:
  a send is pending from the `SendMail` post-hook (or `SECURE_TRANSFER_CONFIRM_SEND_MAIL`) until
  `MAIL_SEND_SUCCESS`, `MAIL_FAILED`, `SECURE_TRANSFER_CANCEL`, the mailbox closing (interaction
  HIDE 17), or 60 s; Fill is off meanwhile. This is not Sent's 120 s attribution window.
- **A fill** runs inside the click (measured: several stacks in one frame), so nothing is left
  scheduled. It re-plans from the bags at the click, puts the bank's name in the To box (`SetText`,
  as the picker does; it replaces what was there), then for each planned stack: the source slot
  still holds that item and count, unlocked; the cursor is empty (a pickup with something held
  swaps); the attachment slot is free; pick up; the cursor holds that itemID (`GetCursorInfo`);
  drop; the slot now holds that item and count. Any check failing stops the fill. A refused drop
  (our item still on the cursor) goes back with `ClearCursor`, checked; if the cursor holds anything
  else, it is left alone and chat says so. A refused itemID is skipped for the session.
  `MAIL_LOCK_SEND_ITEMS` (Blizzard's refund confirmation) stops the fill and leaves the dialog to
  the player. We never call `SendMailFrame_Update` (Blizzard's update runs on its own event), never
  press Send, never fill money or COD.
- **Keep N exactly takes two clicks (session 7b; Codex's round 2).** When the plan needs splits,
  the button first reads "Prepare for <Bank> (split n stacks)": that click splits each remainder
  into its own empty general bag slot (split, the cursor holds that item, drop on the empty slot,
  the slot then holds it; the same per-step checks and recovery as a fill) and attaches nothing.
  Prepare **remembers the batch** it prepared, for this mailbox visit: each stack to send as
  `{ bag, slot, itemID, count }`, the new split stacks included. Once the bags settle (every prepared
  stack in its slot, unlocked, on `BAG_UPDATE_DELAYED`), the button reads "Fill for <Bank>", and that click attaches **exactly that batch** when every stack of it is
  still there as remembered (same item, same count, unlocked) and nothing else of those items moved;
  otherwise it forgets the batch and plans again from the bags (which may offer Prepare again). A
  fresh plan is not used after Prepare: smallest-first could pick other stacks (Codex's round 3:
  stacks of 5 and 6, keep 2, prepare 5 + a split of 4; a fresh plan over 2, 4, 5 takes 2 + 4 and
  leaves 5). Nothing is scheduled between the clicks, so no deferred action can act on a changed
  draft; a prepared stack the player doesn't send just stays in the bags. The batch is forgotten
  at a send, the mailbox closing and any change to those bag slots.
- **Afterwards** it compares the draft with the plan (each attachment's itemID and count) and
  prints one line if anything differs. After `MAIL_SEND_SUCCESS` the button recounts; the player
  clicks again for the next batch.
- **At the mailbox**: one chat line per visit, "Glass Mail: n items ready for <Bank> (Fill on the
  Send tab)", only when something is ready (a setting, on by default: `bankNotice`).

### The Bank page (`Window.lua` + `Bank.lua`)

A fourth entry in the window's sidebar, **Bank**, below the folders. The page replaces the list:
- **Bank for <group>**: the current group's bank, chosen from a menu of your reachable characters
  (`Registry.Characters`, as the address book lists them), or Clear. The other groups' banks are
  listed below, each with a Clear.
- **Rules**: one row per rule, its item (icon and name, loaded on demand) or category name, a keep
  box (digits, 0-9999) and a ×. **Add**: drop an item from the bags on the add slot (the cursor's
  item, `GetCursorInfo`; then `ClearCursor`, which session 7 measured puts it back), or pick a
  category from a menu.
- Nothing on the page acts on mail; it only edits `bank`.

### Tests

- `test_bank.lua` (core): groups; `Bank.For`'s reasons, the bank resolved through AltStable's list;
  rule precedence and the loader (bad entries dropped alone, duplicates update); `Plan` over fake
  bags: keep N with whole stacks, smallest first, bound / locked / refused units counted but not
  moved, keep at or above the total, the 12 cap and the count left, a category rule, nothing for
  items without a rule.
- `test_bankui.lua`: the button's enable rules (each one off alone: body, the money widget, COD,
  subject, an attachment, the cursor, combat, a run, a pending send); a fill attaches the plan in
  order and fills To; each per-stack check stops it (source changed, cursor busy, slot taken, the
  wrong item picked up); a refused drop is put back, a foreign cursor item left alone;
  `MAIL_LOCK_SEND_ITEMS` stops it; Prepare splits each remainder into its own empty slot and
  attaches nothing, then Fill attaches exactly the remembered batch (stacks of 5 and 6 with keep 2:
  5 and the prepared 4, leaving 2), and plans afresh when a remembered stack changed; the
  verification line; the next batch after a send; the chat
  line once per visit; the page's add, keep and remove, and the bank menu. The fake cursor swaps
  on a pickup, as the client does.
- Mutation-test each.

### In game

1. Set a bank on the Bank page; add an item rule (keep 20) and a category (Herb).
2. On another character of the group: the chat line at the mailbox; Fill on the Send tab; the draft
   holds the right stacks, at least keep N left in the bags; press Send; the next batch.
3. A soulbound item under a category rule: never attached.
4. More than 12 stacks: two mails.
5. The bank itself, and a character of the other faction: the button is off and says why.
6. A body typed first, or gold in the money box: the button is off.
7. Close the mailbox with a filled draft: everything back in the bags.
8. A full client exit: the bank and rules persist.

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

## Following Glass UI's suite (owner, 2026-11-12; Codex gpt-6-astra, high, 3 rounds, consensus; built)

**Why.** Glass UI's roster lists Glass Mail (GlassUI Suite.lua:36), but Glass Mail speaks none of
its suite API: its windows don't take the suite's material, tint or accent. The contract is Glass
UI's (`docs/SUITE.md`, `docs/SUITE-LOOK.md`, `Suite.API == 1`, checked with its session against
GlassUI main 54b84fb). Glass UI needs no change. The model is GlassChat's `Suite.lua` (GlassChat
#121: Body, Accent, overrides); GlassMiniMap's is the Theme/Report plumbing.

**Owner decisions (2026-11-12):**
- **Pearl is Glass Mail's own material** too, followed or not (as GUF, GRF and GAB decided).
- **A look chosen in Glass Mail overrides the suite's tint** while following (GAB's model).
- **No carry-over:** a saved `skin = "smoked"` isn't moved into an override; everyone follows the
  suite's tint after the update. `skin` keeps its meaning when not following.
- **The accent colours Glass Mail's own text only**, never Blizzard's labels on the mail windows.

### The material: one instance, built when we know

- `Glass.lua` stops building at file scope. `GM.Glass` becomes a stable forwarding table
  (`__index` to the instance), so the files that capture `GM.Glass` at load (Address, Bag, Skin,
  Window) keep working unchanged: none captures a function or reads `STYLE` at file scope. It is
  built in our own `ADDON_LOADED` handler right after the settings exist, before anything that
  builds a surface (Skin.Start runs at `PLAYER_LOGIN` and at `Blizzard_MailFrame`'s
  `ADDON_LOADED` once `GM.db` exists, GlassMail.lua:249; the windows on first open).
- **When:** our own `ADDON_LOADED`, with `## OptionalDeps: GlassUI` added (Glass UI's
  `ADDON_LOADED` then runs first and `Ready()` is true: GlassMiniMap's S.2, measured on 70450).
  Once per session; no rebuild later (LibGlass never restyles a built instance).
- **Which:** following, `Theme(ADDON).preset` (a name, not hard-coded "pearl"); not following,
  `"pearl"`. A build that errors falls back to `"clean"`, then to the library defaults (classic).
  "No Theme answer" (not following) and "the followed preset failed" stay distinct: the latter is
  reported with `reason = "library-too-old"` only for Pearl under LibGlass MINOR 11, else
  `"build-failed"`, and `minor` = the winning LibStub MINOR at the attempt. The build is never
  reinterpreted after a library upgrade.
- **The material baseline is fixed:** surfaces are built from the material as `New` made it; the
  body (tint, wash) is no longer pushed into `STYLE` before `Apply` (today's `pushStyle`,
  Skin.lua:130, which compounds and makes a surface's construction alpha depend on which tint was
  current when it was built). The material's own wash is captured right after `New`
  (`baseWash`), and every surface is painted after building through `SetSurfaceTint` and
  `SetWash(g, baseWash * factor)`: under Pearl, clear and class 0.10, smoked ≈ 0.078; under clean,
  0.18 and 0.14, as today.

### The look: effective tint and body

- **Glass Mail's choices:** `skin` = `clear` | `smoked` | `stock` (unchanged; saved sparse, default
  clear) is the look when not following. While following, an override in its own sparse table,
  `GlassMailDB.suiteOwn = { skin = "clear" | "smoked" | "stock" }`, read with `rawget`, never pruned
  against the defaults (an override equal to the default must survive a reload).
- **The effective look:** following, the override if set, else the suite look's `tint` (`clear`,
  `smoked` or `class`, live); not following, `skin`.
- **The body numbers** come from `Suite.Body(effectiveTint)` while following (tint or `classShade`,
  `wash` as a factor of our instance's `STYLE.wash`, `backing`), checked like GlassChat's
  `validBody`, else our own copy in Body's shape (`Skin.BODIES`: clear and smoked as today's tints,
  wash ×1 and ×0.14/0.18, backing 0.35 and 0.92; class `classShade = 0.6`, wash ×1, backing 0.35;
  backing RGB {0.04, 0.05, 0.07}), also used when `Body` is missing, throws or answers junk.
  **Valid** means the whole answer, checked before painting: every colour component a finite
  number in 0..1 (NaN fails), `classShade` finite in 0..1 when there is no `tint`, and a finite
  `wash` factor whose `baseWash * factor` is within 0..1 (LibGlass's setters return false on
  anything else, which `pcall` can't see). Not valid: the whole local body, never a mix. Accent
  colours are checked the same way. Not
  following, our copy. Resolved once per refresh and shared by every surface: no caches. The
  panes and sections (`pane`, `section`) stay Glass Mail's own; class uses clear's full RGBA (a
  neutral, dense reading fill, no class-coloured panes).
- **When the suite can't say:** `Look` missing or throwing, or a tint we don't know: the local
  `skin` is the look, exactly as when not following, and no override is made from it.
- **Class:** its own paint branch (a class Body has no `tint`): `classShade` × the player's class
  colour (`C_ClassColor` / `RAID_CLASS_COLORS` by the class token), `SetSurfaceTint` with three
  values, so the construction alpha (the material's, now the same for every surface) is kept. An
  unreadable colour resets the surface to its built tint (`SetSurfaceTint(g)`, as Glass UI's Theme,
  GlassUI Theme.lua:66), not a previous smoked one, and repaints at `PLAYER_ENTERING_WORLD`.
- **Stock** (`skin` or the override): Blizzard's own art, no glass on the mail windows, as today.
  Glass Mail's own windows stay glass (smoked, as today). Reported as `declined = "Blizzard's
  own"`, `built = nil`: Glass UI shows "its own look by its choice", not a failure.

### The accent

- Our own text that is Blizzard's gold today takes the accent: the picker's section headers
  (Address.lua:241, `GOLD`). Text only, as decided: the Glass Mail window's selected-folder
  highlight (a background texture, Window.lua:416) stays gold, and no new targets are added.
  Following: `Suite.Accent(name)` with the validated effective name (the suite's `accent` when we
  know it, else gold); when it is missing, throws or answers a bad colour, our own copy of that
  name (`ACCENTS = { gold = {1, 0.82, 0}, ice = {0.65, 0.835, 0.905} }`, GlassChat's), so what is
  painted and what is reported agree; not following: gold. No accent override in Glass Mail, so no `own.accent`. Blizzard's labels on
  MailFrame are never recoloured. A repaint touches the existing rows only (no roster rebuild); a
  picker built later reads the current colour.

### Live

- **Start order** (SUITE-LOOK): freeze participation at our `ADDON_LOADED`; register for
  `GlassUI.Suite.LookChanged`; pull `Suite.Look()` at once, before any surface is built.
- `LookChanged(owner, look)`: copy the `tint` and `accent` we know (a value we don't know keeps
  ours), `Skin.Refresh()` and the accent repaint, then `Report`. Idempotent.
- **Combat:** a tint or accent change only repaints colours and alphas (ours, and `SetAlpha` on the
  faded Blizzard art, as every skin switch does today); it never calls Blizzard's letter refresh
  (`OpenMailFrame:Update`, Skin.lua:417), which only runs when the letter turns light or dark, and
  a tint change never does (`letter.light` stays true: kept and tested). A **stock ↔ glass**
  change does turn the letter, whatever caused it: a Glass Mail setting, or a suite event (with a
  local `stock` and no override, a valid suite tint shows glass and an unknown one falls back to
  stock). So Skin keeps the **applied** look: every paint path (Refresh, the inbox guides' hook,
  a window built later) paints from it, never from the settings directly. A refresh computes the
  requested look; if it crosses the stock boundary in combat, the applied one stays, and at
  `PLAYER_REGEN_ENABLED` the latest requested look is resolved and applied whole (stationery,
  pane, text). A change back before combat ends cancels it. Settings save at once and the options
  page shows the saved request; the report says what is applied. No general combat queue.
- Everything read from Glass UI goes through `rawget`; every call through `pcall`; a junk or
  throwing suite means our own look, never an error.

### Report

`{ api = 1, built, reason, minor, declined, look = { tint = effective, accent = name }, own = {
tint = true } (an override of clear or smoked), options = GM.Options.Open }`, plain values, sent
after the build and after every change (a look change, an override set or cleared, stock to glass
and back). Derived each time from the frozen participation, the build result and the stock state
(no report state of its own): `built` is the built preset only while participating and not stock,
nil otherwise (else Glass UI would show us as following); stock to glass clears `declined` and
reports the original build result again, an earlier failure included. No `live` (we repaint
live), no `own.backing` (our backing is Body's).

### Settings

- The options page's look radios: while following, a first choice "Glass UI (<current tint>)"
  that clears the override, then Clear glass, Smoked glass, Blizzard's own as overrides; the
  selection goes by source (an override equal to the suite's value still shows as ours). Not
  following: today's three radios. A status line under them: "Follows Glass UI" / "Glass UI isn't
  loaded" / "Not following Glass UI (set in Glass UI)" / "Glass UI's theme integration isn't
  available" (an API other than 1), plus a material build failure when there was one, with Glass
  UI's `Open()` behind a button when it exists.
- **Live:** a suite event or a slash command while the page is open re-runs its refreshers (the
  selection and the "Glass UI (<tint>)" label), through one `Options.Refresh()`.
- `/gmail skin clear|smoked|stock` sets the override while following, `skin` otherwise; `/gmail
  skin suite` clears the override.

### Tests

A fake `GlassUI.Suite` in the stubs (API 1; Theme, Report, Look, Body, Accent, Open, each
removable or throwing). Cases: no Glass UI (Pearl, our look, no report); following (the preset
built is Theme's; the body is Body's; a LookChanged repaints and reports; a tint we don't know is
ignored; class with the colour unreadable, then painted at PLAYER_ENTERING_WORLD); not following
(our look, a report saying so); an override (set, survives a reload, cleared by "Glass UI");
stock while following (declined, mail windows unglassed, our windows glass); a failed build
(`clean`, reported); the accent on the picker headers (the folder highlight stays gold), never on a
Blizzard label; `Look`, `Body` or `Accent` missing or throwing; API 2 counts as absent; the
options page by source. Plus (Codex round 1):
- the TOC loads without touching the forwarding instance; it is built once, after the settings,
  on both start paths (our `ADDON_LOADED`, then `Blizzard_MailFrame`'s);
- repeated tint changes and windows opened later don't compound the wash; surfaces built before
  and after a smoked change agree under class;
- class with `Body` missing or throwing; an unreadable class colour after smoked resets to the
  built tint, then paints at `PLAYER_ENTERING_WORLD`;
- following switched either way stays frozen until a reload; an old local smoked or stock is kept
  for not-following and never becomes an override;
- stock → glass clears `declined` and reports the original build result, a failure included;
- unknown tint or accent values, malformed answers and a throwing metatable stay inside the suite
  boundary, and what is reported matches what is painted;
- the open options page updates after `/gmail skin` and after a suite event; a picker built after
  an accent change uses the current colour; the folder highlight stays gold;
- a known `ice` with `Accent` missing, throwing or answering a bad colour: our ice, on headers
  already built and on reused rows; a Body with NaN, an out-of-range component or a wash factor
  out of range: the local body whole;
- the applied look: local stock with no override, then a valid suite tint, an unknown one, a valid
  one again, in combat: stock ↔ glass waits, a later `/gmail guides`, suite event or window opened
  meanwhile paints the applied look; a change back before combat ends cancels it; glass-to-glass
  changes repaint at once without `OpenMailFrame:Update`;
- in combat, a tint or accent change never calls `OpenMailFrame:Update`; a stock ↔ glass switch
  waits for combat's end and then applies whole.
Mutation-tested.

**In game:** with Glass UI following: change the suite tint (clear, smoked, class) and the accent
on its "Suite look" page and watch the mail windows, the letter, the Glass Mail window, the picker
and the grid repaint live, in and out of combat (no `ADDON_ACTION_BLOCKED` / `_FORBIDDEN`); stock
↔ glass in combat waits for its end; override Smoked in Glass Mail, reload, see it
kept; Blizzard's own, see Glass UI's page say so; switch following off in Glass UI and reload.
