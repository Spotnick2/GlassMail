# MailProbe results

Measured on the live client with `Tools/MailProbe` (`pwsh Tools/deploy.ps1 -Probe`, then
`/mailprobe help`). Item numbers match the probe checklist in [PLAN.md](PLAN.md). The probe keeps its
log in `MailProbeDB.log` (`WTF\Account\<account>\SavedVariables\MailProbe.lua`) after a full client
exit; paste the relevant lines under each item.

Build: 1.60.1.70291 (session 1, 2026-10-09, an empty inbox).

| # | Question | Result |
|---|---|---|
| 1 | Lifecycle events, order, duplicates | **`MAIL_CLOSED` never fires**; close = interaction HIDE (17). See session 2. |
| 2 | Inbox identity and capacity | Two identical mails differ only by `daysLeft` (session 2). Slots don't renumber after a take; links carry fields beyond the item ID (session 5). Refill past 100: never seen (no overflow). |
| 3 | Looting limits and failures | Specialty bags take items when general bags are full, and are preferred when both have room; a partial stack is enough; money needs no slot; `MAIL_FAILED(itemID)` + error type 3. Sessions 3 and 5. |
| 4 | Take / Return from a timer | `TakeInboxItem` from timers works (several in a row). One `ReturnInboxItem` from a timer works; several in a row: not measured, so I2 ships one click per return. Sessions 3-5. |
| 5 | Open All ownership (gamepad, OnHide) | Hiding calls `SetOpeningAll(false)`; the button comes back on every mailbox open and on /reload. No gamepad available (owner): untestable. Our engine re-checks its own state each step instead of relying on the stock button staying inert. |
| 6 | Sending, splitting, secure transfer | No confirmation appeared for two item sends (to "Cowruzo Test" and "Cowruzo Kashmere"). Blizzard shows it only for strangers. Success 4.3 s, ~15 s and 99 s after `SendMail`. Strangers, splitting, timer send: open (see below). |
| 7 | Taint: row controls, picker, combat | No block from our row button (take) or our picker followed by Blizzard's Send, on sends that needed no confirmation. Combat: not measured, so our controls disable in combat. The picker with a confirmation: open (see below). |
| 8 | Sender formats, secrets, read state | `GetMoney` was **not** secret (out of combat, in town). Players "First Surname"; AH "Horde Auction House" (faction-specific); six `AUCTION_*_MAIL_SUBJECT` templates (session 5). Item count nil without items; uncached items named "". |

## Session 5 findings (2026-10-10, build 70338, M1)

**Answered without the probe** (the sibling addons' probes, the porting guide and the client
source were searched first):
- **The minimap mail icon** is `MinimapCluster.IndicatorFrame.MailFrame` (Forever loads the
  Mainline minimap: `Blizzard_Minimap.toc`, `[Family]` for camelot). It is shown or hidden on
  `UPDATE_PENDING_MAIL` from `HasNewMail()` alone (`Mainline/Minimap.lua:454-466`).
- **Bag contents** are `C_Container.GetContainerItemInfo` structs with `itemID` and `stackCount`
  (AltStable forever-api-notes; Apotheca: `stackCount` is readable in combat). Bags 0-4 plus the
  reagent bag 5 (`Enum.BagIndex`, porting guide).
- **Return or Delete is one rule in Blizzard's code:** the letter's button deletes when
  `InboxItemCanDelete(i)` and returns otherwise (`OpenMailDeleteMixin:Delete`, MailFrame.lua:1108).
  A returned mail still has `canReply = true` (measured below), so `canReply` alone does not mean
  "returnable"; use Blizzard's rule.
- Found nowhere, so probed: the AH subject strings (the API dump has no string constants, the UI
  source none), item family and max stack on this client. PrimalMailer is a TBC addon (Interface
  20504) and proves nothing here.

**AH subjects (item 8).** Six templates (`strings`):
`AUCTION_EXPIRED_MAIL_SUBJECT` "Auction expired: %s", `AUCTION_INVOICE_MAIL_SUBJECT` "Sale Pending: %s",
`AUCTION_OUTBID_MAIL_SUBJECT` "Outbid on %s" (no final period), `AUCTION_REMOVED_MAIL_SUBJECT`
"Auction canceled: %s", `AUCTION_SOLD_MAIL_SUBJECT` "Auction successful: %s",
`AUCTION_WON_MAIL_SUBJECT` "Auction won: %s". A real subject, "Auction canceled: Scroll of Spirit (3)",
matched `REMOVED`: the `%s` part carries the count suffix. That mail had **no invoice**
(`GetInboxInvoiceInfo` nil), so the subject templates are needed beside the invoice. No Postmaster
or system mail was available.

**Links (identity).** `GetInboxItemLink` gave a link for every attachment seen, cached or not
(no `link=nil` in this session). A link looks like
`|cnIQ1:|Hitem:2675::::::::16:1485:::::::::|h[Crawler Claw]|h|r`: it carries fields beyond the
item ID (`16:1485`, possibly the viewer's level, unverified). So a fingerprint is good for one
session on one character; anything saved (X1, N2) keys items by itemID, not link.

**Taking, step by step (item 3).** Mail 1: 1 copper, 2 Refreshing Spring Water (slot 1), 2 Tough
Jerky (slot 2).
- `TakeInboxMoney(1)`: the mail turned **read at the call**, then money 0 and `MAIL_SUCCESS` 0.13 s
  later.
- `TakeInboxItem(1, 1)`: slot 1 emptied and **the Jerky stayed in slot 2. Slots do not renumber.**
  Take by the slot numbers the mail has now.
- `TakeInboxItem(1, 1)` again, on the empty slot: **nothing at all**, no event and no failure.
  The engine must never dispatch on an empty slot; such an attempt would only end at the 5 s
  "uncertain" stop.
- The last take of a mail: `CLOSE_INBOX_ITEM`, the mail briefly listed with no items, then
  `MAIL_INBOX_UPDATE` without it.

**Fit (item 3).**
- **A partial stack is enough:** 10 Brilliant Smallfish (max stack 20, 3 held) were taken with
  **0** general free slots; `fit` said 17 room in partial stacks.
- **The specialty bag is preferred:** with 1 general slot and 10 quiver slots free, a Sharp Arrow
  went to the quiver (10 → 9 free; general still 1). So an item that fits a specialty bag never
  uses the general reserve while that bag has room.
- `C_Item.GetItemMaxStackSizeByID` and `C_Item.GetItemFamily` work by item ID (20 and 0 for food).

**New mail (X3).** **`HasNewMail()` turns false when the last unread mail is read**, and the minimap
icon hides with it (`UPDATE_PENDING_MAIL hasNewMail=false ... shown=false` the moment Crawler Claw
became read, again later for the next new mail). Opening the mailbox alone doesn't clear it.
Blizzard already hides the icon once everything is read, so X3 drops its minimap item.
`UPDATE_PENDING_MAIL` comes in pairs, about 0.25 s apart, again.

**Returns (item 4).** One more single return, from Blizzard's own button (`ReturnInboxItem(2)`):
again the inbox shrank before `MAIL_SUCCESS`. A returned mail showed `wasReturned = true` with
`canReply = true`.

**Sending (item 6).** `MAIL_SEND_SUCCESS` came **99 s** after `SendMail` this time (4.3 s and 15 s
before). A send can take minutes to confirm.

**Open All (item 5).** The stock button's `OnHide` (with `SetOpeningAll(false)`) also fired right
at most `MAIL_SHOW`s. Our Open All sets `SetOpeningAll(true)` only when its run starts, never at open.

**Not measured, and what M1 does instead** (owner, 2026-10-10: not possible on this account):
- **A unique item, a locked slot:** a failed take reports `MAIL_FAILED(itemID)` (session 3); Loot
  adds the item to the run's skip set whatever the reason. No special case.
- **Combat:** our row controls disable themselves on `PLAYER_REGEN_DISABLED` and a running
  operation stops; they come back on `PLAYER_REGEN_ENABLED`.
- **Several returns in a row:** I2 ships "Return next (n left)", one click per mail. `returnmany`
  can still upgrade it later, with 2-3 test mails from an alt.
- **Overflow past 100 mails:** never `total > loaded`, so v0.1.0 doesn't refill; Open All stops at
  the loaded window and says more mail waits.
- **Postmaster mail:** none came. The filter calls a mail "system" when it isn't AH and
  `canReply` is false, a reasoned rule, to be checked when one arrives.
- **Our row buttons inside InboxFrame** weren't clicked (`rows on` ran, the mailbox closed). Session
  3's UIParent button took an item with no block; PR 4's in-game check clicks the real ones.

```
strings: AUCTION_REMOVED_MAIL_SUBJECT = "Auction canceled: %s"
mail 2: sender="Horde Auction House" subject="Auction canceled: Scroll of Spirit (3)" ... reply=false
   icons package=134937 stationery=134939 textCreated=true AH template="AUCTION_REMOVED_MAIL_SUBJECT"
C TakeInboxItem(1, 1)
W 1: "Cowruzo Kashmere" "Refreshing Spring Water (2)" money=0 ... [2:|cnIQ1:|Hitem:117::...|h[Tough Jerky]|h|rx2]
C TakeInboxItem(1, 1)                        (no event follows)
fit 1 slot 1: id=6290 x10 maxStack=20 family=0 held=3 cached=true room in partial stacks=17 specialty free=0
bag 0: 20 slots, 1 free, family 0 / bag 4: 10 slots, 10 free, family 1
C TakeInboxItem(1, 1)                        (a Sharp Arrow)
bag 0: 20 slots, 1 free, family 0 / bag 4: 10 slots, 9 free, family 1
R UPDATE_PENDING_MAIL hasNewMail=false senders=nil, nil, nil minimap indicator shown=false
```

## Session 4 findings (2026-10-09)

**Batch actions (item 4).** **One `ReturnInboxItem` from a timer worked.** `returntimer 1`
returned a player's mail ("Kaleid Sumner", "Crawler Claw") 1 s after the key press, from a
`C_Timer` callback, with nothing blocked.
- **The order differs from a take:** the inbox shrank (1 mail to 0) **before** `MAIL_SUCCESS`, and
  there was no `CLOSE_INBOX_ITEM`. After a return, the indices have shifted by the time the success
  event arrives.
- A batch Return must find each mail again, by its fingerprint, after every inbox update and
  immediately before each `ReturnInboxItem`. It must never use an index remembered from before the
  last update. Otherwise the next return can send back the wrong mail.
- Several returns in a row were **not** measured. That happens during M1, on test mails, before
  I2's "Return selected" ships.

```
returntimer 1: sender="Kaleid Sumner" subject="Crawler Claw" - returning in 1 s, from a timer
C ReturnInboxItem(1)
I inbox loaded=0 total=0
R MAIL_SUCCESS (nil)
```

**Taint (item 7).** **The picker worked on a send that showed no confirmation.** Our own `@`
button (a `UIParent` child) called `SendMailNameEditBox:SetText("Cowruzo Kashmere")`. Blizzard's
Send then sent the mail normally, with nothing blocked.
- **Blizzard's secure-transfer confirmation is for strangers.** `Blizzard_SecureTransferUI.lua:298-304`
  shows `SEND_ITEMS_TO_STRANGER` / `SEND_MONEY_TO_STRANGER` when `SECURE_TRANSFER_CONFIRM_SEND_MAIL`
  fires. Our two sends (to "Cowruzo Test" and "Cowruzo Kashmere") showed none.
- **Still unmeasured:** whether a name set by our code, followed by a send that does need the
  confirmation (an item or gold to a stranger), still goes through the restricted
  `C_SecureTransfer.SendMail`. The S1 picker is only proven for recipients that need no
  confirmation until then. It must be measured before S1 ships (M2), with the `MenuUtil` menu S1
  will use.

**Sending (item 6).**
- **Send order:** `SEND_MAIL_COD_CHANGED` and `SEND_MAIL_MONEY_CHANGED` fire on the Send click,
  before `SendMail`. That comes from Blizzard's code, `SendMailButtonMixin:OnClick` in
  `MailFrame.lua:1251-1268`, which calls `SetSendMailCOD(0)` and `SetSendMailMoney(0)` before
  `SendMailFrame_SendMail()`. The log can't show it, because the probe's `C` lines are post-hooks
  logged after the call returns. The same two events fire again when the draft resets after success.
- **`MAIL_SEND_SUCCESS` came 4.3 s after `SendMail`** (`GetTime` 610146.39 to 610150.70). In
  session 3 it came about 15 s after, which is wall-clock only (16:51:02 to 16:51:17, 1 s
  resolution). A send queue (N1) must wait for it with a generous timeout. A mailbox close in
  the meantime means "unknown", not "failed".

```
610139.87 picker: recipient set to "Cowruzo Kashmere"; now press Send yourself
610146.39 R SEND_MAIL_COD_CHANGED ()
610146.39 R SEND_MAIL_MONEY_CHANGED ()
610146.39 C SendMail("Cowruzo Kashmere", "Commonplace Herb Seeds", "", nil)
610150.70 R SEND_MAIL_MONEY_CHANGED ()
610150.70 R SEND_MAIL_COD_CHANGED ()
610150.70 R MAIL_SEND_SUCCESS ()
610150.70 R MAIL_SUCCESS (nil)
```

## Still open, and when it gets measured

M0 and session 5 measured what M1 depends on. These items stay open; each feature that needs one
ships with a safe fallback until it is measured:

| Item | Open question | Measure in | Blocks |
|---|---|---|---|
| 2 | `CanCheckInbox` refill past the loaded window (needs over 100 mails) | when available | I1 refill (not in v0.1.0) |
| 2 | Index shifts when mail arrives during a run; an inbox update while a confirmation is open | when it happens (`watch on`) | nothing: Ops finds every target again from a fresh scan before each call, and acts only on one exact match |
| 3 | Skipped mail (COD, failed items) filling the loaded window | with over 100 mails | nothing in v0.1.0: without refill, Open All stops at the loaded window anyway |
| 3 | The `keepFree` boundary itself (general slots only, specialty bags first) | PR 3's in-game check | I1 `keepFree`: counts family-0 free slots, as Blizzard's total does (session 1) |
| 3 | The reagent bag (`Enum.BagIndex.ReagentBag` = 5): its family, and whether mail loot goes there | when one is carried | nothing: Open All counts bags 0-4 only, so it may stop early, never overfill |
| 4 | Several `ReturnInboxItem` in a row (`returnmany`) | when convenient | I2 batch Return (v0.1.0: one click each) |
| 7 | Our controls in combat | when convenient | nothing: they disable in combat |
| 8 | Postmaster mail and other system senders; senders on a localized client | when one arrives | I1 filter (a reasoned rule until then) |
| 6, 7 | A send that needs the secure-transfer confirmation (a stranger), after our `SetText`; postage failure; bind/refund prompts | M2 | S1 |
| 6 | Splitting a stack into an attachment; `SendMail` from a timer (measured only, never used) | M4 | N1 |
| 5 | Open All from a gamepad | never (no gamepad) | none: our engine checks its own state at every step |

## Session 3 findings (2026-10-09, same inbox)

**Looting (item 3).**
- **A specialty bag takes its items when the general bags are full.** `take 5` (a Sharp Arrow)
  succeeded with 0 general free slots: the arrow went into bag 4 (family 1). Blizzard's free-slot
  total said 0, so I1 must not stop on that total alone. It should try an item when some bag that
  fits it has room.
- **A failed take:** `MAIL_FAILED (itemID)` (1181) plus `UI_ERROR_MESSAGE (3, "Inventory is
  full.")`. `MAIL_FAILED` is the failure signal. The `UI_ERROR_MESSAGE` only gives
  the reason: type 3 is "inventory full", the only reason measured so far. Never match its text.
- **Taking money needs no bag slot:** `TakeInboxMoney` with 0 free slots succeeded.
- **`MAIL_SUCCESS` carries no itemID** (nil) even for an item take. Success has to be checked from
  the inbox, not from the event.
- **An emptied mail with items is removed:** the last take fires `CLOSE_INBOX_ITEM (index)`,
  `MAIL_SUCCESS` twice, and `MAIL_INBOX_UPDATE` with one mail fewer. The indices shift down.
- **A money-only mail stays after its money is taken** (mail 3, `money=0 items=nil`). There was no
  `CLOSE_INBOX_ITEM`. It still has to be deleted by hand, so Open All leaves such mails behind,
  as Blizzard's does.

**Batch actions (item 4, half).** **`TakeInboxItem` works from a timer.** `taketimer 2` took
slot 3 from the key press, then slots 2 and 1 from `C_Timer` callbacks 0.3-0.5 s apart; all
three succeeded with no block. So looting needs no click per item. `ReturnInboxItem` from a timer
is still unmeasured.

**Read state (item 8).**
- **`GetInboxText` marks a mail read immediately** (`readtest 2`: false before, true right after).
  The X1 snapshot must never call it on an unread mail.
- Mail 1 also turned read after its *failed* take. A take attempt seems to mark mail read even
  when it fails.

**Identity (item 2).** `dupes` found mails 4 and 5 identical, as expected.

**Open All (item 5).** Hidden with `hidestock`, the stock button stays hidden while the mailbox
stays open. **Reopening the mailbox shows it again** (it was visible, and hid itself again, at
the next `hidestock`), and so does `/reload`. Our Open All must hide it on every open.

**Taint (item 7, partial).** **Our own row button** (a UIParent child at HIGH strata, anchored
to `MailItem3`) took that mail's item with `TakeInboxItem`. There was no `ADDON_ACTION_BLOCKED`.

**Sending (item 6, partial).**
- A send from Blizzard's Send button (an item to an own character) logged
  `SendMail("Cowruzo Test", "Coarse Stone", "", nil)`, the fourth argument nil.
- `MAIL_SEND_SUCCESS` and `MAIL_SUCCESS` came **15 s later**.
- **No `SECURE_TRANSFER_CONFIRM_SEND_MAIL` fired.**
- `SEND_MAIL_MONEY_CHANGED` / `SEND_MAIL_COD_CHANGED` fire when the draft resets.

(The gamepad path can't be tested: no gamepad.)

## Session 2 findings (2026-10-09, 5 mails, bags 0-3 full)

**Lifecycle (item 1).**
- **`MAIL_CLOSED` never fired**, in about 10 open/close cycles and a logout at the mailbox. The
  close signal is `PLAYER_INTERACTION_MANAGER_FRAME_HIDE` with type 17.
- **Open:** `MAIL_SHOW` and `PLAYER_INTERACTION_MANAGER_FRAME_SHOW (17)` fire in the same frame, in
  that order. `MAIL_INBOX_UPDATE` follows 0.15-0.3 s later.
- **Close:** in the same frame, Blizzard hides `OpenAllMail` (its `OnHide` calls
  `C_Mail.SetOpeningAll(false)`), then `SECURE_TRANSFER_CANCEL`, then
  `PLAYER_INTERACTION_MANAGER_FRAME_HIDE (17)`.
- **Logout at the mailbox:** `SECURE_TRANSFER_CANCEL` fired 4 times and the HIDE twice, then
  `PLAYER_LEAVING_WORLD`. Handlers must be idempotent.
- `UPDATE_PENDING_MAIL` comes in pairs, about 0.3 s apart, when mail arrives.

**Open All ownership (item 5, partial).** `OpenAllMail:Hide()` from our code calls
`C_Mail.SetOpeningAll(false)` at once (`/mailprobe hidestock`). So an Open All of our own must
hide the stock button *before* it calls `SetOpeningAll(true)`. Every mailbox close also clears
it. The gamepad path has not been tried.

**Data (item 8).**
- **Senders:**
  - Players come with their surname: `"Cowruzo Kashmere"`.
  - The auction house is **faction-specific**: `"Horde Auction House"`. Never match on a sender
    string; classify by the subject templates (`AUCTION_*_MAIL_SUBJECT`) and invoice info.
  - AH mail has `canReply = false`; player mail `true`.
- **`itemCount` is `nil`, not 0, for mail without items** (mail 3: money only).
- **`firstItemLink` is set only for single-item mail.** It was nil for a 3-item mail.
- **Items not in the cache come back as `""` with quality `nil`, not as nil**, from `GetInboxItem`
  (IDs 268415 and 2672). The itemID and count are still right. Test for an attachment by
  itemID, never by name, and refresh names on `GET_ITEM_INFO_RECEIVED`.
- Forever has item IDs far above the Vanilla range (268415).
- `daysLeft` is fractional (29.9997). AH mail starts at 30 days, player mail at 31.

**Inbox identity (item 2, partial).** Mails 4 and 5 are identical in every field the API gives
(same sender, subject, item and count). Only `daysLeft` differs, by 0.0002 days (about 20 s, the
time between the two sends), and that drifts as both age. This confirms there is no stable mail
ID: when two mails look identical, a remembered selection must not pick one.

**Still to run:** `money`, `take`, `readtest`, `taketimer`, `dupes` on a real inbox, the gamepad,
`rows`, `picker`, the send tests.

## Session 1 findings (2026-10-09)

- **`Enum.PlayerInteractionType.MailInfo` = 17.**
- **`UnitName("player")` returned the name split**: `"Kaleid", "Sumner"`. This is the split shape
  `API.PlayerFullName` already joins (AltStable #56). The mail address is "Kaleid Sumner".
- **`C_Container.CalculateTotalNumberOfFreeBagSlots()` counts only general-purpose bags.** It
  returned 0 while bag 4 (family 1, a specialty bag) had 8 free slots. Bags 0-3 (family 0) were
  full. Blizzard's Open All stops on this same total, so "keep N slots free" (I1) must count
  family-0 slots the same way, and items that fit a specialty bag need their own check.

```
state: loaded=0 total=0 canCheck=true wait=0 pending=false
state: hasNewMail=false latest senders=nil, nil, nil
state: freeSlots=0 money secret=false UnitName="Kaleid", "Sumner"
state: mail frame shown=true MailInfo type=17
I inbox loaded=0 total=0
bag 0: 20 slots, 0 free, family 0
bag 1: 6 slots, 0 free, family 0
bag 2: 6 slots, 0 free, family 0
bag 3: 6 slots, 0 free, family 0
bag 4: 10 slots, 8 free, family 1
bags: total free 0
```
