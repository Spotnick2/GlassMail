-- I2 selection and I3 row extras (Inbox.lua), through Core/Ops.lua, against
-- the scripted mail server (WoW.serve answers each recorded call when the
-- test says so).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local FOOD, ORE = 6290, 2770
WoW.itemInfo = { [FOOD] = { maxStack = 20, family = 0 }, [ORE] = { maxStack = 20, family = 0 } }
WoW.bags = { [0] = { size = 16, family = 0, items = {} } }
WoW.now = 100

local function supplies()
    return { sender = "Cowruzo Kashmere", subject = "supplies", money = 250,
             items = { [1] = { id = FOOD, count = 2 }, [2] = { id = ORE, count = 5 } } }
end
local function hello(n) return { sender = "Kaleid Sumner", subject = "hello " .. n } end
local function auction() return { sender = "Horde Auction House", subject = "Auction won: Copper Ore", canReply = false,
                                   items = { [1] = { id = ORE, count = 3 } } } end
local function empty() return { sender = "Horde Auction House", subject = "Sale Pending: Ore", canReply = false } end

-- Blizzard's names that must keep their fields: snapshot before loading.
local function fields(w)
    local t = {}
    for k, v in pairs(w) do t[k] = v end
    return t
end
local WATCHED = { "InboxFrame", "OpenMailFrame", "MailItem1", "MailItem1Button", "MailItem1Subject" }
local before = {}
for _, n in ipairs(WATCHED) do before[n] = fields(_G[n]) end

WoW.inbox = { supplies(), hello(1), auction(), empty() }
local GM = loadAddon()
local I = GM._test.inbox
local rows, bar = I.rows, I.bar()
local OA = GM._test.openAll
local function update() InboxFrame:Update() end
local function step(dt) WoW.now = WoW.now + (dt or 0.2); WoW.tick(dt or 0.2) end
local function last() return WoW.mailCalls[#WoW.mailCalls] end
local function callText(c) return c and (c[1] .. "(" .. tostring(c[2]) .. (c[3] and (", " .. c[3]) or "") .. ")") end
local function click(b) b._scripts.OnClick(b, "LeftButton") end
local function selectedCount() local n = 0; for _ in pairs(I.selected()) do n = n + 1 end; return n end
local function calls() return #WoW.mailCalls end

WoW.fire("MAIL_SHOW")
update()

-- The row controls: ours, inside InboxFrame, on each row with a mail.
eq(rows[1].check:GetParent(), InboxFrame, "the checkbox is ours, in InboxFrame")
check(rows[1].check:IsShown() and rows[4].check:IsShown(), "a checkbox on each row with a mail")
check(not rows[5].check:IsShown() and not rows[5].icon:IsShown(), "  none on an empty row")
eq(MailItem1Subject:GetWidth(), 204, "Blizzard's subject is narrowed to make room")
eq(rows[1].action, "return", "a player's mail: Return")
eq(rows[2].action, "return", "  another")
eq(rows[3].action, nil, "an AH mail with an item: no icon (Return never falls through to Delete)")
check(not rows[3].icon:IsShown(), "  hidden")
eq(rows[4].action, "delete", "an empty mail Blizzard deletes: Delete")
check(not bar.frame:IsShown(), "no bar while nothing is selected")
check(OA.count():IsShown(), "  the message count shows")

-- Twins and loading mail can't be ticked.
table.insert(WoW.inbox, hello(1))
update()
check(not rows[2].check:IsEnabled() and not rows[5].check:IsEnabled(), "identical mails: both checkboxes disabled")
check(not rows[2].icon:IsEnabled(), "  and their icons")
eq(rows[2].why, "Identical to another mail: use the row itself", "  with why")
table.remove(WoW.inbox, 5)
WoW.inbox[2].items = { [1] = { id = ORE, count = 1, link = false } }
update()
check(not rows[2].check:IsEnabled(), "an attachment not linked yet: disabled")
eq(rows[2].why, "Loading...", "  loading")
WoW.inbox[2].items = nil
update()
check(rows[2].check:IsEnabled(), "linked: enabled")

-- Selecting follows the mail, not the row.
click(rows[2].check)
eq(selectedCount(), 1, "a click selects")
check(rows[2].check:GetChecked(), "  ticked")
check(bar.frame:IsShown(), "the bar shows")
check(not OA.count():IsShown(), "  in the message count's place")
eq(bar.open:GetText(), "Open (1)", "  Open (1)")
eq(bar.ret:GetText(), "Return next (1 left)", "  Return next (1 left)")
table.insert(WoW.inbox, 1, hello(9))
WoW.fire("MAIL_INBOX_UPDATE")
check(rows[3].check:GetChecked() and not rows[2].check:GetChecked(), "a mail arriving above: the tick moves with the mail")
table.insert(WoW.inbox, hello(1))
WoW.fire("MAIL_INBOX_UPDATE")
eq(selectedCount(), 0, "a twin appears: the selection drops it")
table.remove(WoW.inbox)
table.remove(WoW.inbox, 1)
update()

-- Shift adds a range from the last plain click; ctrl adds the sender's mail.
for n = 2, 6 do table.insert(WoW.inbox, hello(n)) end   -- 9 mails: 1 supplies, 2 hello1, 3 AH, 4 empty, 5-9 hello2-6
update()
click(rows[1].check)
WoW.shift = true
click(rows[4].check)
WoW.shift = false
eq(selectedCount(), 4, "shift: the range from the anchor, every eligible mail")
click(I.bar().clear)
eq(selectedCount(), 0, "Clear empties it")
WoW.ctrl = true
click(rows[2].check)
WoW.ctrl = false
eq(selectedCount(), 6, "ctrl: every mail from that sender, across pages")
InboxFrame.pageNum = 2
update()
check(rows[1].check:GetChecked() and rows[2].check:GetChecked(), "page 2 shows its selected mails")
eq(rows[3].check:IsShown(), false, "  and no row past the inbox")
InboxFrame.pageNum = 1
update()
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)
eq(selectedCount(), 0, "closing the mailbox clears the selection")
for _ = 1, 5 do table.remove(WoW.inbox) end
update()

-- Return next: the unique match, found again after an index shift; one click each.
click(rows[1].check)   -- supplies: returnable
click(rows[2].check)   -- hello 1
click(rows[3].check)   -- the AH mail: Blizzard deletes it, so it isn't returnable
eq(bar.ret:GetText(), "Return next (2 left)", "Return next counts only what Blizzard would return")
click(bar.ret)
check(GM.Ops.Kind() == "return", "a click starts one return")
check(not rows[1].check:IsEnabled() and not bar.open:IsEnabled(), "  everything else waits")
check(not OA.button():IsEnabled(), "  Open All too")
click(OA.button())
eq(GM.Ops.Kind(), "return", "  a click on it doesn't stop the return")
check(not bar.clear:IsEnabled(), "  Clear waits too")
click(bar.clear)
eq(selectedCount(), 3, "  and its click changes nothing")
table.insert(WoW.inbox, 1, hello(9))   -- arrives before the dispatch: indices shift
step()
eq(callText(last()), "ReturnInboxItem(2)", "  the mail found again at its new index")
step(); step()
eq(calls(), 1, "  one attempt")
WoW.serve(last())
eq(GM.Ops.Kind(), nil, "confirmed: the mail left")
eq(selectedCount(), 2, "  it leaves the selection")
eq(bar.ret:GetText(), "Return next (1 left)", "  one left")
check(OA.button():IsEnabled(), "Open All is back")
table.remove(WoW.inbox, 1)
update()

-- A twin appearing between the click and the dispatch: nothing is returned.
newChat()
click(bar.ret)
table.insert(WoW.inbox, hello(1))
WoW.fire("MAIL_INBOX_UPDATE")
local n = calls()
step()
eq(calls(), n, "a twin appeared: no return")
check(chatHas("return stopped: mail changed"), "  said why")
table.remove(WoW.inbox)
update()

-- A failed return stops; it isn't retried.
click(rows[1].check)   -- hello 1 is now at index 1 (supplies left)
update()
newChat()
click(bar.ret)
step()
eq(callText(last()), "ReturnInboxItem(1)", "a return")
WoW.fire("MAIL_FAILED")
eq(GM.Ops.Kind(), nil, "MAIL_FAILED stops it")
check(chatHas("return stopped: return failed"), "  said so")
step(); step()
eq(callText(last()), "ReturnInboxItem(1)", "  no second try")
eq(#WoW.inbox, 3, "  the mail is still there")

-- The row icons: Delete only an empty mail Blizzard deletes; the rule is
-- checked again at dispatch.
eq(rows[3].action, "delete", "the empty AH mail's icon: Delete")
click(rows[3].icon)
step()
eq(callText(last()), "DeleteInboxItem(3)", "Delete")
WoW.serve(last())
eq(GM.Ops.Kind(), nil, "  confirmed")
table.insert(WoW.inbox, hello(7))
update()
eq(rows[3].action, "return", "a player's mail: Return")
click(rows[3].icon)
WoW.inbox[3].canDelete = true   -- Blizzard now says Delete before the dispatch
n = calls()
step()
eq(calls(), n, "Return never falls through to Delete: nothing sent")
WoW.inbox[3].canDelete = nil
update()

-- A letter open: nothing that could shift its index runs.
OpenMailFrame:Show()
check(not rows[3].icon:IsEnabled(), "a letter open: icons disabled")
check(not OA.button():IsEnabled(), "  Open All too")
check(not rows[1].check:IsEnabled() and not bar.clear:IsEnabled(), "  checkboxes and Clear too")
local had = selectedCount()
check(had > 0, "  (something is selected)")
click(rows[2].check)
click(bar.clear)
eq(selectedCount(), had, "  their clicks change nothing")
click(rows[3].icon)
eq(GM.Ops.Kind(), nil, "  a click does nothing")
eq(GM.Ops.OpenAll({ types = {}, keepFree = 0 }), false, "  no run starts")
OpenMailFrame:Hide()
click(rows[3].icon)
OpenMailFrame:Show()
eq(GM.Ops.Kind(), nil, "a letter opened mid-run stops it")
OpenMailFrame:Hide()
update()

-- A mail still loading: a remembered target waits for the whole inbox (it
-- may be a twin), but not forever.
WoW.inbox = { hello(1), hello(2) }
update()
click(bar.clear)
WoW.inbox[2].items = { [1] = { id = ORE, count = 1, link = false } }
update()
check(rows[1].check:IsEnabled(), "another mail loading: the checkbox still works")
check(not rows[1].icon:IsEnabled(), "  the icon waits")
rows[1].icon._scripts.OnEnter(rows[1].icon)
check(table.concat(GameTooltip._lines, "|"):find("Waiting for mail to load", 1, true) ~= nil, "  and says why")
click(rows[1].icon)
eq(GM.Ops.Kind(), nil, "  a click does nothing")
click(rows[1].check)
check(not bar.open:IsEnabled() and not bar.ret:IsEnabled(), "  Open (n) and Return next wait")
click(bar.open)
click(bar.ret)
eq(GM.Ops.Kind(), nil, "  their clicks do nothing")
local stopped
local function onStop(r) stopped = r.stopReason end
eq(GM.Ops.Act("return", rows[1].fp, onStop), true, "Ops: a Return started anyway")
n = calls()
step(); step(1)
eq(calls(), n, "  sends nothing while a mail loads")
eq(GM.Ops.Kind(), "return", "  waits")
step(5)
eq(stopped, "mail still loading", "  stops at the bound")
check(rows[1].check:IsEnabled(), "  the controls come back")
GM.Ops.OpenSelected({ [rows[1].fp] = true }, { keepFree = 0 }, onStop)
n = calls()
step(); step(1)
eq(calls(), n, "a selected run sends nothing while a mail loads")
step(5)
eq(stopped, "mail still loading", "  bounded too")
GM.Ops.Act("return", rows[1].fp, onStop)
step()
WoW.inbox[2].items = nil
step()
eq(callText(last()), "ReturnInboxItem(1)", "loaded in time: the Return goes")
WoW.serve(last())
eq(stopped, "done", "  confirmed")
-- Each wait has its own bound: two short waits in one run don't add up.
WoW.inbox = { supplies(), hello(2) }
WoW.inbox[2].items = { [1] = { id = ORE, count = 1, link = false } }
update()
stopped = nil
GM.Ops.OpenSelected({ [rows[1].fp] = true }, { keepFree = 0 }, onStop)
step()
step(3)
WoW.inbox[2].items = nil
step()
eq(callText(last()), "TakeInboxMoney(1)", "a short wait, then the take")
WoW.serve(last())
WoW.inbox[2].items = { [1] = { id = ORE, count = 1, link = false } }
step(4.5)
eq(GM.Ops.Kind(), "selected", "  a second short wait: still running")
WoW.inbox[2].items = nil
step()
eq(callText(last()), "TakeInboxItem(1, 1)", "  then the next take")
GM.Ops.Stop()
update()

-- Open (n): only the selected mail, through its residuals; no type filter.
WoW.mailCalls = {}
GlassMailboxDB.openPlayer = false
WoW.inbox = { auction(), supplies(), { sender = "A", subject = "cod", cod = 100, items = { [1] = { id = ORE, count = 1 } } } }
update()
click(bar.clear)   -- the AH mail is still selected from above: same fingerprint
click(rows[2].check)
click(rows[3].check)
newChat()
click(bar.open)
eq(GM.Ops.Kind(), "selected", "Open (n) starts the selection's run")
eq(bar.open:GetText(), "Stop", "  its button reads Stop")
check(not OA.button():IsEnabled(), "  Open All waits")
step()
eq(callText(last()), "TakeInboxMoney(2)", "the selected mail, money first (the player filter is off: it doesn't apply)")
WoW.serve(last())
check(rows[2].check:GetChecked(), "after the first take its tick stays (the target moved to the residual)")
check(bar.frame:IsShown() and bar.open:GetText() == "Stop", "  the Stop button stays")
step()
eq(callText(last()), "TakeInboxItem(2, 1)", "then its first item")
WoW.serve(last())
step(1.1)
eq(callText(last()), "TakeInboxItem(2, 2)", "then the second")
WoW.serve(last())
step(1.1)
eq(GM.Ops.Kind(), nil, "done: the COD mail is left, the AH mail never touched")
for _, c in ipairs(WoW.mailCalls) do check(c[2] == 2, "every take was from the selected mail: " .. callText(c)) end
check(chatHas("took 2 items and 250c"), "the summary line")
eq(selectedCount(), 1, "the COD mail stays selected; the emptied one is gone")
GlassMailboxDB.openPlayer = nil

-- Tooltip: each attachment of a mail with two or more, and the full subject.
WoW.inbox = { supplies(), hello(1) }
WoW.inbox[1].items[2].link = false
update()
MailItem1Button.index = 1
MailItem1Subject._text = "supplies"   -- as InboxMixin:Update sets it; it fits
InboxFrameItem_OnEnter(MailItem1Button)
local lines = table.concat(GameTooltip._lines, "|")
check(lines:find("[item 6290]|h x2", 1, true) ~= nil, "a line per attachment, with its count")
check(lines:find("Loading...", 1, true) ~= nil, "  an attachment not linked yet: Loading...")
eq(lines:find("supplies", 1, true), nil, "  a subject that fits isn't repeated")
WoW.inbox[1].items[2].link = nil
MailItem1Subject._truncated, MailItem1Subject._text = true, "supplies for the long road"
InboxFrameItem_OnEnter(MailItem1Button)
lines = table.concat(GameTooltip._lines, "|")
check(lines:find("[item 2770]|h x5", 1, true) ~= nil, "linked now: its link (rebuilt, not cached while loading)")
check(lines:find("supplies for the long road", 1, true) ~= nil, "  a truncated subject in full")
MailItem2Button.index = 2
InboxFrameItem_OnEnter(MailItem2Button)
eq(#GameTooltip._lines, 1, "a mail without attachments: Blizzard's lines only")
WoW.inbox[2].items = { [1] = { id = ORE, count = 2 } }
WoW.fire("MAIL_INBOX_UPDATE")
InboxFrameItem_OnEnter(MailItem2Button)
eq(#GameTooltip._lines, 1, "one attachment: Blizzard shows it itself, no list")
WoW.inbox[2].items = nil
update()

-- Combat disables every control.
click(rows[2].check)
WoW.combat = true
WoW.fire("PLAYER_REGEN_DISABLED")
check(not rows[1].check:IsEnabled() and not rows[1].icon:IsEnabled(), "combat: rows disabled")
check(not bar.open:IsEnabled() and not bar.ret:IsEnabled() and not bar.clear:IsEnabled(), "  the bar too")
click(bar.ret)
eq(GM.Ops.Kind(), nil, "  a click does nothing")
WoW.combat = false
WoW.fire("PLAYER_REGEN_ENABLED")
check(rows[1].check:IsEnabled() and bar.ret:IsEnabled(), "out of combat: back")

-- Open All's run disables the selection's controls.
click(OA.button())
eq(GM.Ops.Kind(), "openall", "Open All runs")
check(not rows[1].check:IsEnabled() and not bar.ret:IsEnabled(), "  the row and bar controls wait")
GM.Ops.Stop()

-- No field written onto Blizzard's frames (hooks are the client's own).
for _, name in ipairs(WATCHED) do
    local w = _G[name]
    for k, v in pairs(fields(w)) do
        local hooked = WoW.hooked[w] and WoW.hooked[w][k]
        -- The stub's own state ("_" fields, what methods record) and the
        -- index the test set as InboxMixin:Update would aren't the addon's.
        local blizzard = k:sub(1, 1) == "_" or (name == "MailItem1Button" and k == "index")
        check(hooked or blizzard or before[name][k] == v, name .. ": no field written: " .. tostring(k))
    end
end

done("test_inbox")
