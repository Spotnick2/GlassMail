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
| 3 | Looting limits and failures | Bag facts below; looting itself needs mail. |
| 4 | Take / Return from a timer | *pending* |
| 5 | Open All ownership (gamepad, OnHide) | Hiding the stock button calls `SetOpeningAll(false)` at once. Gamepad untested. |
| 6 | Sending, splitting, secure transfer | *pending* |
| 7 | Taint: row controls, picker, combat | *pending* |
| 8 | Sender formats, secrets, read state | `GetMoney` was **not** secret (out of combat, in town). Players "First Surname"; AH "Horde Auction House" (faction-specific). Item count nil without items; uncached items named "". |

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
