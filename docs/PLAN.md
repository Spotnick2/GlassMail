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
- **M2** *(planned, #17; reviewed, see "M2" below)*: S1 (picker; registry from local characters and AltStable), local X1, I4, the X2 history UI,
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

## M2 (reviewed with Codex, 5 rounds, consensus; #17)

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
- **Real-time ends for real-time things:** mail expires whether you play or not. A snapshot whose
  last mail has expired (`expires < time()`) is dropped, and its expired mails are left out when
  shown; a Trash entry goes when the mail it held would have expired.
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
- **AltStable**, when loaded (`## OptionalDeps: AltStable`, `PUBLIC_API_VERSION == 1`):
  `GetCharacters()` (copies; GUID, name, realm, faction, class, account, hidden, current) and the
  `CharactersChanged` callback, only to refresh what is shown. Nothing from it is saved.
- **Reachability:** an own character is offered as a recipient when its faction tag and realm name
  match the current character's. Session 6: the other faction fails ("Target is unfriendly");
  the other account's character on the same realm takes mail like an alt; other realms and
  rulesets are unmeasured, so they stay out.

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
    the same flag, MailFrame.lua:1683). A removal made while it is unsettled is left out: a take
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
4. **S1** picker.
5. **I4** grid; v0.2.0; closes #17.

Settings added: `expiryDays`, `recentMax` (options page radios, `/gmail`). New saved data in
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
- A 1 s ticker while `open` isn't empty: a record not `awaiting` and past 120 s is saved
  `unconfirmed` and removed.
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
  AltStable absent, wrong `PUBLIC_API_VERSION`, present (nothing saved from it).
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

**In game** (the owner, after deploy; a temporary debug line shows the dialog-close hook):
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
  taint: the outbound bridge calls it by name in the global environment). Measured in game.
- **Trash needs a settled inbox:** an earlier call in flight voids a capture; only an update
  with no command pending settles it; no timeout does.
- **Smaller:** only error 457 drops a send; `lastDate` is a high-water mark; the current
  character's play day refreshes on every tick; the new settings are validated at load; a
  restarted clock drops the play-day-stamped subtrees.

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
