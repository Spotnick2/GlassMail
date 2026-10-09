# MailProbe results

Measured on the live client with `Tools/MailProbe` (`pwsh Tools/deploy.ps1 -Probe`, then
`/mprobe help`). Item numbers match the probe checklist in [PLAN.md](PLAN.md). The probe keeps its
log in `MailProbeDB.log` (`WTF\Account\<account>\SavedVariables\MailProbe.lua`) after a full client
exit; paste the relevant lines under each item.

Build: *(not yet measured)*

| # | Question | Result |
|---|---|---|
| 1 | Lifecycle events, order, duplicates | *pending* |
| 2 | Inbox identity and capacity | *pending* |
| 3 | Looting limits and failures | *pending* |
| 4 | Take / Return from a timer | *pending* |
| 5 | Open All ownership (gamepad, OnHide) | *pending* |
| 6 | Sending, splitting, secure transfer | *pending* |
| 7 | Taint: row controls, picker, combat | *pending* |
| 8 | Sender formats, secrets, read state | *pending* |
