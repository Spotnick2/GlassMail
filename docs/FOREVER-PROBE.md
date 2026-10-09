# MailProbe results

Measured on the live client with `Tools/MailProbe` (`pwsh Tools/deploy.ps1 -Probe`, then
`/mailprobe help`). Item numbers match the probe checklist in [PLAN.md](PLAN.md). The probe keeps its
log in `MailProbeDB.log` (`WTF\Account\<account>\SavedVariables\MailProbe.lua`) after a full client
exit; paste the relevant lines under each item.

Build: 1.60.1.70291 (session 1, 2026-10-09, an empty inbox).

| # | Question | Result |
|---|---|---|
| 1 | Lifecycle events, order, duplicates | *pending* (needs the `L` lines from the log) |
| 2 | Inbox identity and capacity | Empty inbox: `GetInboxNumItems` = 0, 0; `CanCheckInbox` = true, 0; no command pending. The rest needs mail. |
| 3 | Looting limits and failures | Bag facts below; looting itself needs mail. |
| 4 | Take / Return from a timer | *pending* |
| 5 | Open All ownership (gamepad, OnHide) | *pending* |
| 6 | Sending, splitting, secure transfer | *pending* |
| 7 | Taint: row controls, picker, combat | *pending* |
| 8 | Sender formats, secrets, read state | `GetMoney` was **not** secret (out of combat, in town). Sender formats need mail. |

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
