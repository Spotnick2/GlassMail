-- Bag.lua (I4): every item in the loaded inbox in one grid, a click taking
-- every copy through Core/Ops.lua's `items` run (PLAN.md, "The grid PR in
-- detail"), against the scripted mail server (WoW.serve answers each call).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local FOOD, ORE, HERB = 6290, 2770, 2447
WoW.itemInfo = { [FOOD] = { maxStack = 20, family = 0 }, [ORE] = { maxStack = 20, family = 0 },
    [HERB] = { maxStack = 20, family = 0 } }
WoW.itemNames = { [ORE] = "Copper Ore" }
WoW.bags = { [0] = { size = 16, family = 0, items = {} } }
WoW.now = 100
local function inbox()
    WoW.inbox = {
        { sender = "A", subject = "ore and money", money = 250,
          items = { [1] = { id = ORE, count = 5 }, [3] = { id = ORE, count = 2 } } },
        { sender = "B", subject = "food", items = { [1] = { id = FOOD, count = 2 } } },
        { sender = "C", subject = "cod ore", cod = 100, items = { [1] = { id = ORE, count = 1 } } },
        { sender = "D", subject = "twin", items = { [1] = { id = ORE, count = 3 } } },
        { sender = "D", subject = "twin", items = { [1] = { id = ORE, count = 3 } } },
        { sender = "E", subject = "token", items = { [1] = { id = 99, count = 1, currency = true } } },
    }
end
inbox()
local GM = loadAddon()
local Bag, Ops = GM.Bag, GM.Ops
local T = GM._test.bag
local function step(dt) WoW.now = WoW.now + (dt or 0.2); WoW.tick(dt or 0.2) end
local function last() return WoW.mailCalls[#WoW.mailCalls] end
local function callText(c) return c and (c[1] .. "(" .. tostring(c[2]) .. (c[3] and (", " .. c[3]) or "") .. ")") end
local function click(b) b:GetScript("OnClick")(b, "LeftButton") end
local function buttons() return T.ui().buttons end
local function said(part)
    for _, line in ipairs(WoW.chat or {}) do if tostring(line):find(part, 1, true) then return true end end
    return false
end

MailFrame:Show()
WoW.fire("MAIL_SHOW")

-- The entries: merged by itemID, in order of first appearance ---------------------
local e = Bag.Entries(GM.Scan.Inbox())
eq(#e, 2, "two distinct items; the currency left out")
eq(e[1].id, ORE, "  ore first (it appears first)")
eq(e[1].count, 5 + 2 + 1 + 3 + 3, "  its total count, every stack")
eq(e[1].mails, 4, "  in four mails (two stacks in one mail count once)")
eq(e[1].cod, 1, "  one of them COD")
eq(e[2].id, FOOD, "  then food")
eq(e[2].mails, 1, "  in one mail")

-- The toggle and the panel ----------------------------------------------------------
check(Bag.toggle and Bag.toggle:GetParent() == InboxFrame, "the Items button is on the inbox")
eq(T.panel(), nil, "the panel is built on first use")
local ownBefore = #GM._test.skin.own
click(Bag.toggle)
eq(#GM._test.skin.own, ownBefore + 1, "  its glass joins the skin's repaint list (Skin.AddWindow)")
local panel = T.panel()
check(panel and panel:IsShown(), "the button shows the panel")
eq(panel:GetParent(), InboxFrame, "  a child of the inbox")
eq(#T.entries(), 2, "  its first show reads the inbox")
eq(buttons()[1].entry.id, ORE, "  ore in the first button")
eq(buttons()[1].count:GetText(), 14, "  with its count")
check(not buttons()[3]:IsShown(), "  the unused buttons are hidden")
eq(T.ui().footer:GetText(), "Click an item to take every copy", "  the footer says what a click does")
-- The tooltip.
buttons()[1]:GetScript("OnEnter")(buttons()[1])
eq(GameTooltip._itemID, ORE, "the tooltip shows the item")
check(table.concat(GameTooltip._lines, "|"):find("in 4 mails", 1, true) ~= nil, "  in how many mails")
check(table.concat(GameTooltip._lines, "|"):find("1 COD, left to you", 1, true) ~= nil, "  and the COD ones")
buttons()[1]:GetScript("OnLeave")(buttons()[1])

-- A click takes every copy ----------------------------------------------------------
WoW.openingAll = nil
click(buttons()[1])
eq(Ops.Kind(), "items", "a click starts an items run")
eq(Ops.Items()[ORE], true, "  for that item")
eq(WoW.openingAll, true, "  opening-all is on")
check(T.ui().stop:IsShown(), "  the footer's Stop shows")
eq(T.ui().footer:GetText(), "Taking Copper Ore", "  and says what it takes")
check(buttons()[1].glow:IsShown(), "  the item's button glows")
check(not buttons()[2]:IsEnabled(), "  the others are disabled")
check(not GM._test.openAll.button():IsEnabled(), "  and so is Open All")
step()
eq(callText(last()), "TakeInboxItem(1, 1)", "no money: the ore in slot 1 of the first mail")
WoW.serve(last())
WoW.fire("BAG_UPDATE_DELAYED")
step()
eq(callText(last()), "TakeInboxItem(1, 3)", "  then slot 3 of the same mail")
-- The stock Open All shown mid-run: hiding it turns opening-all off; it goes back on.
InboxFrame.OpenAllMail:Show()
eq(WoW.openingAll, true, "the stock button shown mid-run: opening-all stays on")
WoW.serve(last())
WoW.fire("BAG_UPDATE_DELAYED")
step()
eq(callText(last()), "TakeInboxItem(4, 1)", "  then the twins (the COD mail left), the first one")
WoW.serve(last())
WoW.fire("BAG_UPDATE_DELAYED")
step()
eq(callText(last()), "TakeInboxItem(4, 1)", "  and the other, now at that index")
WoW.serve(last())
WoW.fire("BAG_UPDATE_DELAYED")
step()
eq(Ops.Running(), false, "every copy taken: the run ends")
eq(WoW.openingAll, false, "  opening-all is off")
eq(WoW.inbox[1].money, 250, "the money stayed")
eq(#WoW.inbox, 4, "  the twins (emptied) went; the money mail, the food, the COD ore and the token stay")
eq(WoW.inbox[3].cod, 100, "  the COD mail stays")
check(said("took 13 Copper Ore"), "the end line names the item and every unit taken")
check(said("left 1 COD"), "  and the COD mail left")
eq(T.ui().footer:GetText(), "Click an item to take every copy", "the footer is back")
check(not T.ui().stop:IsShown(), "  the Stop hidden")
eq(#T.entries(), 2, "the grid follows the inbox (the COD ore and the food)")

-- Units: a failed take adds none; MAIL_FAILED skips that item for the run.
inbox()
WoW.mailCalls = {}
WoW.fire("MAIL_INBOX_UPDATE")
click(buttons()[1])
step()
WoW.fire("MAIL_FAILED", ORE)
step()
eq(Ops.Running(), false, "MAIL_FAILED on the item: no other copy is tried, the run ends")
eq(#WoW.mailCalls, 1, "  after one attempt")
check(said("failed"), "  the end line says so")
-- An unconfirmed attempt adds no units either: stopped before it is confirmed.
WoW.chat = {}
click(buttons()[1])
step()
T.ui().stop:GetScript("OnClick")(T.ui().stop)
eq(Ops.Running(), false, "the footer's Stop stops the run")
check(said("nothing taken"), "  an unconfirmed take counts no unit")

-- The item's button stops it wherever it moved -----------------------------------
-- 60 other items first, ore at the start and the end: taking the first copy
-- moves ore past the visible rows.
WoW.inbox = { { sender = "A", subject = "ore", items = { [1] = { id = ORE, count = 1 } } } }
for i = 1, 60 do
    WoW.itemInfo[5000 + i] = { maxStack = 20, family = 0 }
    WoW.inbox[#WoW.inbox + 1] = { sender = "S", subject = "s" .. i, items = { [1] = { id = 5000 + i, count = 1 } } }
end
WoW.inbox[#WoW.inbox + 1] = { sender = "Z", subject = "more ore", items = { [1] = { id = ORE, count = 2 } } }
WoW.fire("MAIL_INBOX_UPDATE")
click(buttons()[1])
step()
WoW.serve(last())
eq(Ops.Items()[ORE], true, "the first ore taken, the run goes on")
check(buttons()[1].entry.id ~= ORE, "  ore left the first button")
check(not buttons()[1].glow:IsShown(), "  which has no glow now")
check(not buttons()[1]:IsEnabled(), "  and is disabled like the others")
local found
for _, b in ipairs(buttons()) do if b.entry and b.entry.id == ORE then found = b end end
eq(found, nil, "  ore is out of view")
check(T.ui().stop:IsShown(), "  the footer's Stop is still there")
T.setOffset(100)
for _, b in ipairs(buttons()) do if b.entry and b.entry.id == ORE then found = b end end
check(found and found.glow:IsShown(), "scrolled to it: the ore's button glows")
click(found)
eq(Ops.Running(), false, "  and a click on it stops the run")

-- The pool and the scroll ---------------------------------------------------------
local frames = #WoW.frames
WoW.inbox = {}
for i = 1, 200 do
    WoW.inbox[i] = { sender = "S", subject = "s" .. i, items = { [1] = { id = 7000 + i, count = 1 } } }
end
WoW.fire("MAIL_INBOX_UPDATE")
T.setOffset(0)
eq(#T.entries(), 200, "200 distinct items")
eq(#WoW.frames, frames, "  build no new frames")
eq(#buttons(), Bag.COLS * Bag.ROWS, "  the pool stays its buttons")
T.ui().content:GetScript("OnMouseWheel")(T.ui().content, -1)
eq(T.offset(), 1, "the wheel scrolls a row")
T.setOffset(1000)
local maxRows = math.ceil(200 / Bag.COLS) - Bag.ROWS
eq(T.offset(), maxRows, "  never past the end")
-- Entries going: the offset is clamped, and reused buttons keep nothing.
WoW.inbox = { { sender = "S", subject = "one", items = { [1] = { id = ORE, count = 1 } } } }
WoW.fire("MAIL_INBOX_UPDATE")
eq(T.offset(), 0, "entries gone: the offset is clamped")
eq(buttons()[1].entry.id, ORE, "  the first button shows what is left")
check(not buttons()[2]:IsShown() and buttons()[2].entry == nil, "  a reused button keeps no item")
check(not buttons()[2].glow:IsShown(), "  nor a glow")

-- Disabled: combat, a letter, another run, gamepad mode -----------------------------
local function enabled() return buttons()[1]:IsEnabled() end
check(enabled(), "idle: enabled")
WoW.fire("PLAYER_REGEN_DISABLED")
check(not enabled(), "disabled in combat")
click(buttons()[1])
eq(Ops.Running(), false, "  a click does nothing")
WoW.fire("PLAYER_REGEN_ENABLED")
check(enabled(), "  enabled after")
OpenMailFrame:Show()
check(not enabled(), "disabled while a letter is open")
OpenMailFrame:Hide()
check(enabled(), "  enabled once it closes")
WoW.gamepad = true
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION")
check(not enabled(), "disabled in gamepad mode, with no other event")
WoW.gamepad = false
WoW.fire("INPUT_DEVICE_INTERFACE_TRANSITION")
check(enabled(), "  and back")
WoW.inbox[2] = { sender = "M", subject = "m", money = 10 }
WoW.fire("MAIL_INBOX_UPDATE")
click(GM._test.openAll.button())
check(Ops.Kind() == "openall" and not enabled(), "disabled during another run")
click(buttons()[1])
eq(Ops.Kind(), "openall", "  a click doesn't start or stop anything")
Ops.Stop("stopped")

-- Refresh only while visible; the first show and a reopen read the inbox as it is.
click(Bag.toggle)
check(not panel:IsShown(), "the button hides the panel")
WoW.inbox = { { sender = "S", subject = "x", items = { [1] = { id = FOOD, count = 4 } } } }
WoW.fire("MAIL_INBOX_UPDATE")
eq(T.entries()[1].id, ORE, "hidden: no refresh")
click(Bag.toggle)
eq(T.entries()[1].id, FOOD, "shown again: the inbox as it is now")
InboxFrame:Hide()
WoW.inbox = { { sender = "S", subject = "y", items = { [1] = { id = HERB, count = 1 } } } }
WoW.fire("MAIL_INBOX_UPDATE")
eq(T.entries()[1].id, FOOD, "the inbox hidden (the send tab): no refresh, though the panel is shown")
InboxFrame:Show()
-- The client fires a shown child's OnShow when its parent shows; the pinned
-- kit doesn't, so the test does.
panel:GetScript("OnShow")(panel)
eq(T.entries()[1].id, HERB, "  back on the inbox: refreshed")

-- The selection: a take changes the mail's fingerprint, and it leaves the selection.
WoW.inbox = {
    { sender = "A", subject = "sel", items = { [1] = { id = ORE, count = 1 }, [2] = { id = FOOD, count = 1 } } },
    { sender = "B", subject = "untouched", items = { [1] = { id = FOOD, count = 1 } } },
}
WoW.fire("MAIL_INBOX_UPDATE")
InboxFrame:Update()
local snap = GM.Scan.Inbox()
local S = GM.Selection
local changes = 0
S.OnChange(function() changes = changes + 1 end)
GM._test.inbox.selected()[snap.mails[1].fp] = true
GM._test.inbox.selected()[snap.mails[2].fp] = true
InboxFrame:Update()
changes = 0
local n = 0
for _ in pairs(S.Get()) do n = n + 1 end
eq(n, 2, "two mails selected")
for _, b in ipairs(buttons()) do if b.entry and b.entry.id == ORE then click(b) end end
step()
WoW.serve(last())
local sel = S.Get()   -- { [inbox index] = true }
check(sel[1] == nil, "a take from a selected mail drops it from the selection")
check(sel[2] == true, "  an untouched selected mail stays")
check(changes > 0, "  OnChange was called")
Ops.Stop("stopped")

done("test_bag")
