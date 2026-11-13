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
WoW.bags[2] = { size = 1, items = { [1] = { id = 2840, count = 3 } } }
local function item(b, s) return WoW.bags[b] and WoW.bags[b].items[s] end

-- The cursor and the draft: a bound item, or any while `refuse`, stays on the cursor.
local cursor, sendItems, refuse, calls = nil, {}, false, {}
local function call(s) calls[#calls + 1] = s end
local function called(s) for _, c in ipairs(calls) do if c == s then return true end end return false end
C_Container.GetContainerItemInfo = function(b, s)
    local it = item(b, s)
    if it then return { itemID = it.id, stackCount = it.count, isLocked = it.locked == true, isBound = it.bound == true } end
end
C_Container.PickupContainerItem = function(b, s)
    call("pickup " .. b .. "." .. s)
    local it = item(b, s)
    if cursor or not it then return end
    cursor = { b = b, s = s, id = it.id, count = it.count, bound = it.bound }
    it.locked = true
end
C_Container.SplitContainerItem = function(b, s, n)
    call("split " .. b .. "." .. s .. " " .. n)
    local it = item(b, s)
    if cursor or not it then return end
    cursor = { b = b, s = s, id = it.id, count = n }
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

loadForeverProbe()
assert(loadfile("Tools/MailProbe/MailProbe.lua"))("MailProbe", {})
WoW.fire("ADDON_LOADED", "MailProbe")
WoW.fire("PLAYER_LOGIN")

-- bagscan: each item as N1 would judge it.
mark()
fp("mail bagscan")
check(saw("bag 0.1 id=6948 x1 isBound=true C_Item.IsBound=true accountUntilEquip=false locked=false class=7.0"),
    "bagscan: a bound item, both ways")
check(saw("bag 1.2 id=4338 x4 isBound=false C_Item.IsBound=false accountUntilEquip=false locked=true"),
    "  a locked one")
check(saw("bagscan: 9 item(s) in bags 0-4"), "  every item")

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
eq(#calls - n, 2, "attachmany: a refused drop stops it (one pickup, one click)")
refuse = false
ClearCursor()

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
check(saw("attachbound: still on the cursor; ClearCursor"), "  and logged")

-- unattach: the last attachment back, Blizzard's right-click.
fp("mail unattach")
check(called("click 5 clear") and sendItems[5] == nil, "unattach: the last attachment back")

-- attachtimer: nothing at the click, all of it a second later.
n = #calls
fp("mail attachtimer")
eq(#calls, n, "attachtimer: nothing at the click")
WoW.advance(1.1)
check(called("pickup 2.1") and sendItems[5] and sendItems[5].id == 2840, "  the stack a second later")

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
check(saw("bagscan: 9 item(s)"), "  then logs the bags")
fp("steps stop")

done("test_probe7")
