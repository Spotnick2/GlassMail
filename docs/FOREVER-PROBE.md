# MailProbe results

Measured on the live client with `Tools/MailProbe` (`pwsh Tools/deploy.ps1 -Probe`, then
`/mailprobe help`). Item numbers match the probe checklist in [PLAN.md](PLAN.md). The probe keeps its
log in `MailProbeDB.log` (`WTF\Account\<account>\SavedVariables\MailProbe.lua`) after a full client
exit; paste the relevant lines under each item.

Build: 1.60.1.70291 (session 1, 2026-10-09, an empty inbox).

| # | Question | Result |
|---|---|---|
| 1 | Lifecycle events, order, duplicates | **`MAIL_CLOSED` never fires**; close = interaction HIDE (17). See session 2. |
| 2 | Inbox identity and capacity | Empty inbox: `GetInboxNumItems` = 0, 0; `CanCheckInbox` = true, 0; no command pending. Two identical mails differ only by `daysLeft` (session 2). |
| 3 | Looting limits and failures | Specialty bags take items when general bags are full; money needs no slot; `MAIL_FAILED(itemID)` + error type 3. Session 3. |
| 4 | Take / Return from a timer | `TakeInboxItem` from timers: **works**. `ReturnInboxItem` from a timer: pending. |
| 5 | Open All ownership (gamepad, OnHide) | Hiding calls `SetOpeningAll(false)`; the button comes back on every mailbox open and on /reload. No gamepad available (owner): untestable. Our engine re-checks its own state each step instead of relying on the stock button staying inert. |
| 6 | Sending, splitting, secure transfer | Blizzard Send: no secure-transfer confirm for an own character; success 15 s later. Timer send, split: pending. |
| 7 | Taint: row controls, picker, combat | Our row button took an item with no block. Picker, combat: pending. |
| 8 | Sender formats, secrets, read state | `GetMoney` was **not** secret (out of combat, in town). Players "First Surname"; AH "Horde Auction House" (faction-specific). Item count nil without items; uncached items named "". |

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

**Still to run:** `returntimer`, `picker` then Send, `split`, `sendtimer`. (The gamepad path can't be tested: no gamepad.)

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
