-- Bank.lua: N1's button on the Send tab's title bar (Fill, Prepare), the chat
-- line at the mailbox, and the Bank page (docs/PLAN.md, "N1: the bank
-- character"). The stubs' bags, cursor and draft follow session 7: a pickup
-- swaps with a held item, a drop takes the whole source stack, a split into an
-- empty slot shows only when served.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local ORE, HERB, SWORD = 2770, 765, 8177
WoW.itemInfo = { [ORE] = { class = 7, sub = 7 }, [HERB] = { class = 7, sub = 9 }, [SWORD] = { class = 2, sub = 7 } }
WoW.itemNames = { [ORE] = "Copper Ore", [HERB] = "Peacebloom" }
WoW.bags = { [0] = { size = 16, family = 0, items = {} } }
local GM = loadAddon()
local Bank, UI, Store = GM.Bank, GM.BankUI, GM.Store
local T = GM._test.bankui
local BANK = "Cowruzo Banks"
Store.SetChar("Player-1-BNK", { name = BANK, realm = "Doomhowl", faction = "Horde", lastPlayDay = 1 })
Bank.Set("Horde:Normal", BANK, "Player-1-BNK")
Bank.AddItem(ORE, 20)

local function has(s, part) return type(s) == "string" and s:find(part, 1, true) ~= nil end
local function said(part)
    for _, l in ipairs(newChat()) do if has(l, part) then return true end end
    return false
end
local function bags(items) WoW.bags[0].items = items end
local function attached()
    local out = {}
    for a = 1, 12 do
        local it = WoW.draft.items and WoW.draft.items[a]
        if it then out[#out + 1] = it.id .. "x" .. it.count end
    end
    return table.concat(out, " ")
end
local function clearDraft()
    WoW.draft.items = {}
    for _, it in pairs(WoW.bags[0].items) do it.locked = nil end
    SendMailNameEditBox:SetText("")
end
local function open()
    WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 17)
    WoW.fire("MAIL_SHOW")
    MailFrameTab_OnClick(nil, 2)
    WoW.advance(0)
end
local function close()
    WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)
    MailFrame:Hide()
end
local button = UI.button
local function click() UI.Refresh(); button._scripts.OnClick(button, "LeftButton"); end
local function mode() return (UI.State()) end

-- The button: on the Send tab's title bar, left of the address book's.
check(button and button:GetParent() == SendMailFrame, "the bank button is on the Send tab")
local p = button._points[1]
check(p and p[1] == "TOPRIGHT" and p[2] == MailFrame and p[4] == -72 and p[5] == -2, "  on the title bar, left of the address book's")

-- The chat line, once per visit, only when something is ready.
bags({ [1] = { id = ORE, count = 20 }, [2] = { id = ORE, count = 7 }, [3] = { id = ORE, count = 5 },
    [4] = { id = ORE, count = 3 } })
newChat()
open()
check(said("15 items ready for " .. BANK), "at the mailbox: what is ready, in chat")
MailFrameTab_OnClick(nil, 1)
MailFrameTab_OnClick(nil, 2)
WoW.advance(0)
check(not said("ready for"), "  once per visit")
close()
GM.Settings.SetBankNotice(false)
open()
check(not said("ready for"), "  not with the setting off")
GM.Settings.SetBankNotice(true)

-- Fill: the 3, the 5 and the 7 (15 = 35 - keep 20); the 20 stays.
eq(mode(), "fill", "an empty draft and something to send: Fill")
eq(select(2, UI.State()), "Fill for " .. BANK .. ": 15 items in 3 stacks. Then check the draft and press Send.",
    "  its tooltip says how much")
eq(UI.Count(1, "item") .. " in " .. UI.Count(1, "stack"), "1 item in 1 stack", "  one of each: no plural")
check(button:IsEnabled(), "  the button is on")
click()
eq(SendMailNameEditBox:GetText(), BANK, "Fill: the bank in the To box")
eq(attached(), "2770x3 2770x5 2770x7", "  the three stacks, smallest first")
check(WoW.cursor == nil, "  the cursor empty")
check(not said("check it"), "  no mismatch line")
eq(mode(), "off", "a filled draft: the button is off")

-- Each part of an empty draft, alone.
local function offWith(setup, undo, label)
    clearDraft()
    setup()
    UI.Refresh()
    check(mode() == "off" and not button:IsEnabled(), "off: " .. label)
    undo()
    UI.Refresh()
    check(mode() == "fill", "  back on when it goes")
end
offWith(function() SendMailSubjectEditBox:SetText("hi") end, function() SendMailSubjectEditBox:SetText("") end,
    "a subject")
offWith(function() SendMailBodyEditBox:SetText("hi") end, function() SendMailBodyEditBox:SetText("") end, "a letter")
offWith(function() WoW.moneyInput = 500 end, function() WoW.moneyInput = 0 end, "money in the money box")
offWith(function() SendMailCODButton:SetChecked(true) end, function() SendMailCODButton:SetChecked(false) end, "C.O.D.")
offWith(function() WoW.draft.items = { [3] = { id = HERB, count = 1 } } end, function() WoW.draft.items = {} end,
    "an attachment")
offWith(function() WoW.cursor = { b = 9, s = 9, id = SWORD, count = 1 } end, function() WoW.cursor = nil end,
    "something on the cursor")
offWith(function() WoW.fire("PLAYER_REGEN_DISABLED") end, function() WoW.fire("PLAYER_REGEN_ENABLED") end, "combat")
local running = GM.Ops.Running
offWith(function() GM.Ops.Running = function() return true end end, function() GM.Ops.Running = running end,
    "a mail action running")
offWith(function() SendMail("Someone", "x", "") end, function() WoW.fire("MAIL_SEND_SUCCESS") end, "a send in flight")
offWith(function() SendMail("Someone", "x", "") end, function() WoW.fire("MAIL_FAILED") end, "  (a failure ends it too)")
offWith(function() SendMail("Someone", "x", "") end, function() WoW.advance(61) end, "  (and 60 s)")
offWith(function() WoW.fire("SECURE_TRANSFER_CONFIRM_SEND_MAIL") end, function() WoW.fire("SECURE_TRANSFER_CANCEL") end,
    "the stranger dialog up")
local copper = MoneyInputFrame_GetCopper
offWith(function() MoneyInputFrame_GetCopper = function() return WoW.Secret("m") end end,
    function() MoneyInputFrame_GetCopper = copper end, "an unreadable money box")

-- The bank: none, this character, nothing to send.
clearDraft()
Bank.Clear("Horde:Normal")
check(mode() == "off" and select(2, UI.State()) == Bank.WHY_NONE, "no bank: off, and why")
Bank.Set("Horde:Normal", BANK, "Player-1-BNK")
bags({ [1] = { id = ORE, count = 20 } })
check(mode() == "off" and has(select(2, UI.State()), "Nothing for"), "nothing above keep: off")

-- Each step's checks stop the fill.
local function stops(setup, undo, expect, label)
    clearDraft()
    bags({ [1] = { id = ORE, count = 20 }, [2] = { id = ORE, count = 7 }, [3] = { id = ORE, count = 5 },
        [4] = { id = ORE, count = 3 } })
    newChat()
    setup()
    click()
    undo()
    check(said(expect), label .. ": stopped, and said why")
    check(WoW.cursor == nil or WoW.cursor.id == SWORD, "  nothing of ours left on the cursor")
end
local pickup = C_Container.PickupContainerItem
stops(function()   -- the slot holds another item by the pickup
    C_Container.PickupContainerItem = function(b, s)
        WoW.bags[0].items[s] = { id = HERB, count = 1 }
        pickup(b, s)
    end
end, function() C_Container.PickupContainerItem = pickup end, "the pickup didn't give", "the wrong item picked up")
eq(attached(), "", "  nothing attached")
check(WoW.bags[0].items[4] and WoW.bags[0].items[4].id == HERB and not WoW.bags[0].items[4].locked,
    "  the other item went back to its slot")
local drop = ClickSendMailItemButton
stops(function() WoW.refuse[ORE] = true end, function() WoW.refuse[ORE] = nil end, "refused", "a refused drop")
check(not WoW.bags[0].items[4].locked, "  the refused stack back in its bag, unlocked")
eq(mode(), "off", "  and skipped from now on (nothing else of it to send)")
GM._test.bank.refused[ORE] = nil
stops(function()
    ClickSendMailItemButton = function(a, c)
        drop(a, c)
        WoW.cursor = { b = 9, s = 9, id = SWORD, count = 1 }   -- something else lands on the cursor
    end
end, function() ClickSendMailItemButton = drop; WoW.cursor = nil end, "left alone", "a foreign item on the cursor")
stops(function()
    ClickSendMailItemButton = function(a, c)
        drop(a, c)
        WoW.fire("MAIL_LOCK_SEND_ITEMS", a, "link")
    end
end, function() ClickSendMailItemButton = drop; WoW.fire("MAIL_UNLOCK_SEND_ITEMS") end, "confirm an item",
    "Blizzard's refund confirmation")
eq(attached(), "2770x3", "  one stack in, then it stopped")
-- The verification line: an extra attachment from somewhere else.
clearDraft()
newChat()
local extra = false
ClickSendMailItemButton = function(a, c)
    drop(a, c)
    if not extra then extra = true; WoW.draft.items[12] = { id = HERB, count = 1 } end
end
click()
ClickSendMailItemButton = drop
check(said("isn't what Glass Mail planned"), "an extra attachment: the verification line")

-- Prepare: keep 20 of 39 (20, 7, 5, 3 and a bound 4): the 3, 5 and 7, and 4 split off the 20.
clearDraft()
bags({ [1] = { id = ORE, count = 20 }, [2] = { id = ORE, count = 7 }, [3] = { id = ORE, count = 5 },
    [4] = { id = ORE, count = 3 }, [5] = { id = ORE, count = 4, bound = true } })
UI.Refresh()
eq(mode(), "prepare", "a split needed: Prepare")
click()
eq(attached(), "", "Prepare attaches nothing")
eq(#WoW.pendingSplits, 1, "  one split, into an empty slot")
eq(WoW.pendingSplits[1].n, 4, "  of 4")
check(WoW.cursor == nil, "  the cursor empty")
eq(mode(), "preparing", "  Preparing...")
check(not button:IsEnabled(), "  the button off meanwhile")
WoW.serveSplits("source")
eq(mode(), "preparing", "the source answered first: still preparing")
WoW.serveSplits("dest")
eq(mode(), "fill", "the new stack shows: Fill")
click()
eq(attached(), "2770x3 2770x5 2770x7 2770x4", "Fill: exactly the prepared batch")
eq(WoW.bags[0].items[1].count, 16, "  the 20 kept 16 (+ the bound 4 = keep 20)")
check(T.prepared() == nil, "  the batch is forgotten")

-- Codex's round 3: 5 and 6, keep 2: prepare 5 + a split of 4 off the 6; Fill takes 5 and 4, leaving 2.
clearDraft()
Bank.SetKeep(Bank.Rule(ORE), 2)
bags({ [1] = { id = ORE, count = 5 }, [2] = { id = ORE, count = 6 } })
click()
WoW.serveSplits("dest")   -- this time the new stack shows first, the source still locked
eq(mode(), "preparing", "the new stack first, the source not yet: still preparing")
WoW.serveSplits("source")
click()
eq(attached(), "2770x5 2770x4", "5 and 6, keep 2: the 5 and the prepared 4")
eq(WoW.bags[0].items[2].count, 2, "  2 left, as set")

-- Codex's round 5: the kept units destroyed after Prepare: nothing attached.
clearDraft()
bags({ [1] = { id = ORE, count = 5 }, [2] = { id = ORE, count = 6 } })
click()
WoW.serveSplits()
eq(mode(), "fill", "(prepared)")
WoW.bags[0].items[2] = nil     -- the kept 2, destroyed
newChat()
click()
eq(attached(), "", "the kept units gone after Prepare: nothing attached")
check(said("changed since Prepare"), "  and it says to click again")

-- Unexpected contents while preparing, and the 5 s limit.
clearDraft()
bags({ [1] = { id = ORE, count = 5 }, [2] = { id = ORE, count = 6 } })
click()
WoW.pendingSplits = {}
WoW.bags[0].items[3] = { id = HERB, count = 1 }   -- another item in the reserved slot
newChat()
WoW.fire("BAG_UPDATE_DELAYED")
check(T.prepared() == nil and said("changed while preparing"), "another item in the reserved slot: forgotten")
WoW.bags[0].items[3] = nil
bags({ [1] = { id = ORE, count = 5 }, [2] = { id = ORE, count = 6 } })
click()
newChat()
WoW.advance(5.1)
check(T.prepared() == nil and said("didn't show"), "no answer in 5 s: forgotten, nothing lost")
WoW.pendingSplits = {}
-- A send, combat and the mailbox closing forget a prepared batch too.
for _, case in ipairs({
    { "a send", function() WoW.fire("MAIL_SEND_SUCCESS") end },
    { "combat", function() WoW.fire("PLAYER_REGEN_DISABLED"); WoW.fire("PLAYER_REGEN_ENABLED") end },
    { "the mailbox closing", function() close(); open() end },
}) do
    clearDraft()
    bags({ [1] = { id = ORE, count = 5 }, [2] = { id = ORE, count = 6 } })
    click()
    WoW.serveSplits()
    case[2]()
    check(T.prepared() == nil, case[1] .. " forgets a prepared batch")
end

-- The Bank page.
newChat()
SlashCmdList.GLASSMAIL("bank")
local page, pui = T.page()
check(page and page:IsShown(), "/gmail bank: the window on its Bank page")
check(not GM._test.window.ui().list:IsShown(), "  the list hidden")
eq(pui.title:GetText(), "Bank for Horde, Normal", "  the group")
eq(pui.choose:GetText(), BANK, "  its bank")
pui.choose._scripts.OnClick(pui.choose)
local names = {}
for _, it in ipairs(WoW.menu.items) do if it.kind == "button" then names[#names + 1] = it.text end end
check(table.concat(names, ","):find(BANK, 1, true) ~= nil, "the bank menu: your characters of the group")
local ally = false
for _, n in ipairs(names) do if n == "Ally Person" then ally = true end end
check(not ally, "  none of the other faction")
Store.SetChar("Player-1-ALT", { name = "Bankie Two", realm = "Doomhowl", faction = "Horde", lastPlayDay = 1 })
pui.choose._scripts.OnClick(pui.choose)
for _, it in ipairs(WoW.menu.items) do if it.text == "Bankie Two" then it.callback() end end
eq(Bank.Get("Horde:Normal").name, "Bankie Two", "  a pick sets the bank")
eq(pui.choose:GetText(), "Bankie Two", "  and the page shows it")
-- Rules: drop an item, a category, keep, remove.
local rows = #Bank.Rules()
WoW.cursor = { b = 0, s = 1, id = HERB, count = 1 }
WoW.bags[0].items[1] = { id = HERB, count = 1, locked = true }
pui.slot._scripts.OnReceiveDrag(pui.slot)
check(Bank.Rule(HERB) and Bank.Rule(HERB).item == HERB, "a dropped item becomes a rule")
check(WoW.cursor == nil and not WoW.bags[0].items[1].locked, "  and goes back to its bag")
pui.add._scripts.OnClick(pui.add)
for _, it in ipairs(WoW.menu.items) do if it.text == "Sub 5" then it.callback() end end
local cloth
for _, r in ipairs(Bank.Rules()) do if r.class == 7 and r.sub == 5 then cloth = r end end
check(cloth ~= nil, "Add a category: Cloth")
eq(#Bank.Rules(), rows + 2, "  two rules more")
local row
for _, r in ipairs(pui.rows) do if r.rule and r.rule.item == HERB then row = r end end
check(row and row.name:GetText() == "Peacebloom", "a row per rule, with the item's name")
local function focus(box) box:SetFocus(); box._scripts.OnEditFocusGained(box) end
focus(row.keep)
row.keep:SetText("12")
row.keep._scripts.OnEnterPressed(row.keep)
eq(Bank.Rule(HERB).keep, 12, "  its keep box saves")
focus(row.keep)
row.keep:SetText("40")
row.keep._scripts.OnEscapePressed(row.keep)
eq(Bank.Rule(HERB).keep, 12, "  Escape cancels the edit")
eq(row.keep:GetText(), "12", "  and shows the saved keep again")
row.remove._scripts.OnClick(row.remove)
eq(Bank.Rule(HERB), nil, "  its x removes it")

-- PR #53's review: a scroll while a keep box has focus. The row is reused for
-- another rule; the edit goes to the rule it was typed for, never the next one.
for id = 3001, 3009 do Bank.AddItem(id, 20) end
GM.BankUI.RefreshPage()
local first = pui.rows[1]
local typedFor = first.rule
local nextKeep = Bank.Rules()[2].keep
check(typedFor.keep ~= 5 and nextKeep ~= 5, "(neither keep is 5 yet)")
focus(first.keep)
first.keep:SetText("5")
local list = first:GetParent()
list._scripts.OnMouseWheel(list, -1)            -- scroll down one: row 1 shows the next rule
local next = first.rule
check(next ~= typedFor, "(row 1 now shows another rule)")
eq(typedFor.keep, 5, "the edit was saved to the rule it was typed for")
eq(next.keep, nextKeep, "  the rule now in that row keeps its own keep")
eq(first.keep:GetText(), tostring(next.keep), "  the row shows the new rule's keep")
first.keep._scripts.OnEnterPressed(first.keep)  -- a late Enter: nothing to commit
first.keep._scripts.OnEditFocusLost(first.keep)
eq(next.keep, nextKeep, "  a late Enter or focus loss changes nothing")

-- /gmail banknotice
SlashCmdList.GLASSMAIL("banknotice off")
eq(GM.db.bankNotice, false, "/gmail banknotice off")
SlashCmdList.GLASSMAIL("banknotice on")
eq(GM.db.bankNotice, true, "/gmail banknotice on")

done("test_bankui")
