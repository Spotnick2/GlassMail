-- MailProbe, session 7 (M4, N1): filling the send draft from the bags by code,
-- against fake bags, a fake cursor and a fake draft (runs locally only:
-- ForeverProbe is private, CI skips it). What it measures needs the live
-- client; this keeps the probe honest: never a bound item but in its own step,
-- never a pickup while the cursor holds something (it would swap), each stack
-- used once, and a refused item put back.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Bags: a bound Hearthstone first, a stack too small to split 2 off, a locked one.
WoW.bags[0] = { size = 4, items = {
    [1] = { id = 6948, count = 1, bound = true },
    [2] = { id = 2770, count = 20 },
    [3] = { id = 2589, count = 2 },
    [4] = { id = 2592, count = 10 },
} }
WoW.bags[1] = { size = 4, items = {
    [1] = { id = 4306, count = 5 },
    [2] = { id = 4338, count = 4, locked = true },
    [3] = { id = 2772, count = 8 },
    [4] = { id = 2771, count = 6 },
} }
WoW.bags[2] = { size = 6, items = { [1] = { id = 2840, count = 3 }, [2] = { id = 2841, count = 4 },
    [3] = { id = 2842, count = 5 }, [4] = { id = 2843, count = 6 }, [5] = { id = 2844, count = 7 },
    [6] = { id = 2845, count = 8 } } }
local function item(b, s) return WoW.bags[b] and WoW.bags[b].items[s] end

-- The cursor and the draft: a bound item, or any while `refuse`, stays on the
-- cursor. A pickup while the cursor holds something swaps, as the client does.
local cursor, sendItems, refuse, calls = nil, {}, false, {}
local swapped = false
local function call(s) calls[#calls + 1] = s end
local function called(s) for _, c in ipairs(calls) do if c == s then return true end end return false end
C_Container.GetContainerItemInfo = function(b, s)
    local it = item(b, s)
    if it then return { itemID = it.id, stackCount = it.count, isLocked = it.locked == true, isBound = it.bound == true } end
end
C_Container.PickupContainerItem = function(b, s)
    call("pickup " .. b .. "." .. s)
    local it = item(b, s)
    if not it then   -- an empty slot: the held item goes there (a split leaves the rest in its source)
        if cursor then
            WoW.bags[b].items[s] = { id = cursor.id, count = cursor.count }
            local src = item(cursor.b, cursor.s)
            if cursor.split and src then src.count = src.count - cursor.count end
            if src then src.locked = nil end
            cursor = nil
        end
        return
    end
    if cursor then   -- the swap: the held item goes in the slot, the slot's item on the cursor
        WoW.bags[b].items[s] = { id = cursor.id, count = cursor.count }
        swapped = true
    end
    cursor = { b = b, s = s, id = it.id, count = it.count, bound = it.bound }
    it.locked = true
end
C_Container.SplitContainerItem = function(b, s, n)
    call("split " .. b .. "." .. s .. " " .. n)
    local it = item(b, s)
    if cursor or not it then return end
    cursor = { b = b, s = s, id = it.id, count = n, split = true }
    it.locked = true
end
local function unlock(x) local it = item(x.b, x.s); if it then it.locked = nil end end
rawset(_G, "ClickSendMailItemButton", function(a, clear)
    call("click " .. tostring(a) .. (clear and " clear" or ""))
    if clear then
        if sendItems[a] then unlock(sendItems[a]); sendItems[a] = nil end
    elseif cursor and not cursor.bound and not refuse then
        sendItems[a], cursor = cursor, nil
    else
        return
    end
    WoW.fire("MAIL_SEND_INFO_UPDATE")
end)
rawset(_G, "HasSendMailItem", function(a) return sendItems[a] ~= nil end)
rawset(_G, "GetSendMailItem", function(a)
    local x = sendItems[a]
    if x then return "item " .. x.id, x.id, 134, x.count end
end)
rawset(_G, "CursorHasItem", function() return cursor ~= nil end)
rawset(_G, "GetCursorInfo", function() if cursor then return "item", cursor.id end end)
rawset(_G, "ClearCursor", function() call("clearcursor"); if cursor then unlock(cursor); cursor = nil end end)
C_Item.GetItemInfoInstant = function(id) return id, "Trade Goods", "Parts", "", 134, 7, 0 end
C_Item.IsBound = function(loc) local it = item(loc.b, loc.s); return it and it.bound == true end
C_Item.IsBoundToAccountUntilEquip = function() return false end
rawset(_G, "ItemLocation", { CreateFromBagAndSlot = function(_, b, s) return { b = b, s = s } end })
rawset(_G, "MailProbeDB", nil)

local from = 0
local function mark() from = #MailProbeDB.log end
local function saw(text)
    for i = from + 1, #MailProbeDB.log do if MailProbeDB.log[i]:find(text, 1, true) then return true end end
    return false
end
local function count()
    local n = 0
    for _ in pairs(sendItems) do n = n + 1 end
    return n
end
local function fp(cmd) SlashCmdList.FOREVERPROBE(cmd) end

MailFrame:Show()
SendMailFrame:Show()
loadForeverProbe()
local NS = {}
assert(loadfile("Tools/MailProbe/MailProbe.lua"))("MailProbe", NS)
WoW.fire("ADDON_LOADED", "MailProbe")
WoW.fire("PLAYER_LOGIN")

-- bagscan: each item as N1 would judge it.
mark()
fp("mail bagscan")
check(saw("bag 0.1 id=6948 x1 isBound=true C_Item.IsBound=true accountUntilEquip=false locked=false class=7.0"),
    "bagscan: a bound item, both ways")
check(saw("bag 1.2 id=4338 x4 isBound=false C_Item.IsBound=false accountUntilEquip=false locked=true"),
    "  a locked one")
check(saw("bagscan: 14 item(s) in bags 0-4"), "  every item")

-- attach: the first unbound, unlocked stack, whole, into attachment 1.
mark()
fp("mail attach")
check(called("pickup 0.2") and not called("pickup 0.1"), "attach: the first unbound stack, never the bound one")
check(called("click 1"), "  dropped on the first free attachment")
eq(sendItems[1] and sendItems[1].id, 2770, "  and it is in the draft")
check(saw("attach: the stack 0.2 id=2770 x20 -> attachment 1"), "  logged")
check(saw("attach: the stack 0.2 id=2770 x20 -> attachment 1, at once: attachments=1:2770x20"), "  with the draft at once")
WoW.advance(0.6)
check(saw("0.5 s later: attachments=1:2770x20"), "  and 0.5 s later")

-- attach split 2: a stack of 3 or more (0.3 has 2), 2 split off.
fp("mail attach split 2")
check(called("split 0.4 2") and not called("split 0.3 2"), "split 2: from a stack of 3 or more")
eq(sendItems[2] and sendItems[2].count, 2, "  the 2 in attachment 2")

-- The cursor holds something: no pickup (it would swap), an error line.
cursor = { b = 9, s = 9, id = 1, count = 1 }
local n = #calls
mark()
fp("mail attach")
eq(#calls, n, "a busy cursor: nothing picked up")
check(saw("the cursor holds something"), "  and it says so")
cursor = nil

-- attachmany: stops at once when a drop is refused (the cursor still holds it).
refuse = true
n = #calls
fp("mail attachmany 3")
eq(#calls - n, 3, "attachmany: a refused drop stops it (one pickup, one click)")
eq(calls[#calls], "clearcursor", "  and puts the refused stack back")
check(cursor == nil, "  the cursor is empty")
refuse = false

-- attachmany 3: three more stacks, each once, the locked one skipped.
fp("mail attachmany 3")
check(called("pickup 1.1") and called("pickup 1.3") and called("pickup 1.4") and not called("pickup 1.2"),
    "attachmany 3: three new stacks, not the locked one")
eq(count(), 5, "  five attachments now")

-- attachbound: the bound item, refused; it goes back from the cursor.
mark()
fp("mail attachbound")
check(called("pickup 0.1"), "attachbound: the bound item")
check(cursor ~= nil, "  refused: still on the cursor")
WoW.advance(0.7)
check(cursor == nil and called("clearcursor"), "  put back")
check(saw("attachbound (refused): put back with ClearCursor"), "  and logged")

-- unattach: the last attachment back, Blizzard's right-click.
fp("mail unattach")
check(called("click 5 clear") and sendItems[5] == nil, "unattach: the last attachment back")

-- landed (the wait steps): exactly the item and count meant, nothing else.
fp("mail attach split 2")
local slot = 5
check(sendItems[slot] and sendItems[slot].count == 2, "(a split of 2 in attachment 5)")
check(NS._test.landed7(), "landed: the split as meant")
sendItems[slot].count = 3
check(not NS._test.landed7(), "landed: a different count fails")
sendItems[slot].count = 2

-- A refused drop goes back to its bag 0.6 s later, while the cursor holds it.
refuse = true
mark()
fp("mail attach")
check(cursor ~= nil, "a refused drop: still on the cursor")
WoW.advance(0.7)
check(cursor == nil and saw("(refused): put back with ClearCursor"), "  put back")
refuse = false

-- Only stack (b, s) can be picked: every other item locked for the test.
local function only(b, s)
    local was = {}
    for bag, def in pairs(WoW.bags) do
        for slot, it in pairs(def.items) do
            if not (bag == b and slot == s) then was[it] = it.locked or false; it.locked = true end
        end
    end
    return function() for it, l in pairs(was) do it.locked = l or nil end end
end
WoW.bags[3] = { size = 6, items = { [1] = { id = 6949, count = 1, bound = true }, [2] = { id = 3001, count = 4 },
    [3] = { id = 3002, count = 4 }, [4] = { id = 3003, count = 4 }, [5] = { id = 3004, count = 4 },
    [6] = { id = 3005, count = 4 } } }
for k in pairs(sendItems) do sendItems[k] = nil end

-- Never clear a cursor that holds something else by then.
local restore = only(3, 1)
mark()
fp("mail attachbound")
check(called("pickup 3.1"), "(the second bound item picked up)")
cursor = { b = 9, s = 9, id = 77, count = 1 }   -- the player swapped in their own item
WoW.advance(0.7)
eq(cursor and cursor.id, 77, "a cursor that changed hands: not cleared, the player's item stays")
check(saw("the cursor holds something else now; left alone"), "  and it says so")
cursor = nil
restore()

-- attachtimer: every check again when the timer runs.
restore = only(3, 2)
n = #calls
mark()
fp("mail attachtimer")
cursor = { b = 9, s = 9, id = 77, count = 1 }   -- the player picks something up meanwhile
WoW.advance(1.1)
eq(#calls, n, "attachtimer: a cursor busy by then: no pickup (it would swap)")
check(not swapped and saw("STOPPED, the cursor holds something"), "  stopped, nothing swapped")
cursor = nil
restore()
restore = only(3, 3)
mark()
fp("mail attachtimer")
item(3, 3).count = 1                             -- the source changed meanwhile
WoW.advance(1.1)
check(not called("pickup 3.3") and saw("STOPPED, bag 3.3 changed"), "  a changed source: stopped")
restore()
restore = only(3, 4)
mark()
fp("mail attachtimer")
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)   -- the mailbox closes meanwhile
WoW.advance(1.1)
check(not called("pickup 3.4") and saw("STOPPED, the mailbox closed"), "  a mailbox close: stopped")
restore()
restore = only(3, 5)
mark()
fp("mail attachtimer")
WoW.fire("PLAYER_REGEN_DISABLED")
WoW.advance(1.1)
check(not called("pickup 3.5") and saw("STOPPED, the mailbox closed, combat began"), "  combat: stopped")
restore()
-- A send, the Send tab going, a changed draft: each stops it too.
local cases = {
    { "a send", function() SendMail("Cowruzo Banks", "x", "") end },
    { "the Send tab hidden", function() SendMailFrame:Hide(); SendMailFrame:Show() end },
    { "the draft changed", function() SendMailBodyEditBox:SetText("hello") end },
}
WoW.bags[3].size = 9
WoW.bags[3].items[7] = { id = 3011, count = 4 }
WoW.bags[3].items[8] = { id = 3012, count = 4 }
WoW.bags[3].items[9] = { id = 3013, count = 4 }
for i, c in ipairs(cases) do
    restore = only(3, i + 6)
    n = #calls
    mark()
    fp("mail attachtimer")
    c[2]()
    WoW.advance(1.1)
    eq(#calls, n, "attachtimer: " .. c[1] .. " meanwhile: nothing picked up")
    check(saw("STOPPED"), "  stopped")
    check(not NS._test.landed7(), "  and the check after it fails (not \"nothing expected\")")
    restore()
end
SendMailBodyEditBox:SetText("")

-- The close-during-a-delay step reads the delayed action's outcome, once it ran.
WoW.bags[3].size = 10
WoW.bags[3].items[10] = { id = 3014, count = 4 }
restore = only(3, 10)
fp("mail attachtimer 3")
check(not NS._test.delayed7().done, "a delayed attach: pending until it runs")
WoW.fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 17)
WoW.advance(3.1)
local d7 = NS._test.delayed7()
check(d7.done and d7.outcome:find("^stopped: the mailbox closed") ~= nil, "  then stopped by the close: " .. tostring(d7.outcome))
restore()

-- attachmany 3 with only one stack left: the check fails (only 1 of 3).
WoW.bags[3].size = 11
WoW.bags[3].items[11] = { id = 3015, count = 4 }
for k in pairs(sendItems) do sendItems[k] = nil end
restore = only(3, 11)
fp("mail attachmany 3")
eq(count(), 1, "attachmany 3 with one stack: one attached")
check(not NS._test.landed7(), "  and the check fails: not all 3")
restore()

-- splitback when the split gives nothing: an error, and the check fails.
WoW.bags[3].size = 12
WoW.bags[3].items[12] = { id = 3016, count = 5 }
restore = only(3, 12)
local realSplit = C_Container.SplitContainerItem
C_Container.SplitContainerItem = function(b, sl, k) call("split " .. b .. "." .. sl .. " " .. k) end
mark()
fp("mail splitback 2")
check(saw("the split didn't put our item on the cursor"), "splitback: a split that gives nothing is an error")
check(not NS._test.landed7(), "  and the check fails")
C_Container.SplitContainerItem = realSplit
restore()

-- splitback: a split put straight back leaves the stack whole.
restore = only(3, 6)
fp("mail splitback 2")
check(called("split 3.6 2") and cursor == nil and not item(3, 6).locked, "splitback: the stack is whole again")
check(NS._test.landed7(), "  and landed says so")
restore()

-- splitfree: 2 split off into an empty general bag slot, the rest left; then
-- attachplaced attaches just those 2.
WoW.bags[4] = { size = 3, items = { [1] = { id = 4001, count = 7 } } }
for k in pairs(sendItems) do sendItems[k] = nil end
restore = only(4, 1)
fp("mail splitfree 2")
check(called("split 4.1 2") and called("pickup 4.2"), "splitfree: split, then dropped on the first empty slot")
eq(item(4, 2) and item(4, 2).count, 2, "  the new stack holds 2")
eq(item(4, 1).count, 5, "  the old one the rest")
check(NS._test.landed7(), "  and landed says so")
restore()
fp("mail attachplaced")
eq(sendItems[1] and sendItems[1].count, 2, "attachplaced: just the 2 in the draft")
check(NS._test.landed7(), "  as meant")
WoW.bags[4].items[2] = nil
WoW.bags[4].items[3] = { id = 4002, count = 6 }
for k in pairs(sendItems) do sendItems[k] = nil end
restore = only(4, 3)
fp("mail splitfree 2")
check(called("split 4.3 2") and item(4, 2) and item(4, 2).count == 2, "(a second split, into 4.2)")
item(4, 3).count = 3    -- one more gone from the source meanwhile: not as meant
check(not NS._test.landed7(), "  a source left with the wrong count fails")
item(4, 3).count = 4
check(NS._test.landed7(), "  (as meant again)")
item(4, 3).id = 9999    -- another item in the source's place, same count
check(not NS._test.landed7(), "  another item in the source's slot fails")
item(4, 3).id = 4002
restore()

-- attachtimer: nothing at the click, all of it a second later.
n = #calls
fp("mail attachtimer")
eq(#calls, n, "attachtimer: nothing at the click")
WoW.advance(1.1)
check(#calls > n and cursor == nil and count() == 1, "  the stack a second later")
check(not swapped, "nothing was ever swapped")

-- The procedure: Start refuses until the Send Mail tab shows.
local FPS = ForeverProbe.Steps
MailFrame:Show()
SendMailFrame:Hide()
mark()
fp("steps mail bank")
FPS.Run()
check(saw("open the Send Mail tab first"), "the bank procedure: Start needs the Send Mail tab")
SendMailFrame:Show()
for k in pairs(sendItems) do sendItems[k] = nil end
FPS.Run()
check(saw("item(s) in bags 0-4"), "  then logs the bags")
fp("steps stop")

done("test_probe7")
