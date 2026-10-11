-- Core/Loot.lua: what to take next, and whether it fits (FOREVER-PROBE
-- sessions 1, 3, 5).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local FOOD, ARROW, ORE = 6290, 2512, 2770
WoW.itemInfo = { [FOOD] = { maxStack = 20, family = 0 }, [ARROW] = { maxStack = 200, family = 1 },
    [ORE] = { maxStack = 20, family = 0 } }
-- Bag 0: general, full except what each test frees; bag 4: a quiver.
local function bags(generalFree, quiverFree, stacks)
    WoW.bags = { [0] = { size = 4, family = 0, items = {} }, [4] = { size = 4, family = 1, items = {} } }
    for s = 1, 4 - generalFree do WoW.bags[0].items[s] = { id = 9000 + s, count = 1 } end
    for s = 1, 4 - quiverFree do WoW.bags[4].items[s] = { id = 9100 + s, count = 1 } end
    for s, st in pairs(stacks or {}) do WoW.bags[0].items[s] = st end
end
local GM = loadAddon()
local Loot = GM.Loot
local function fits(id, count, keepFree)
    return Loot.Fits({ itemID = id, count = count }, Loot.Bags(), keepFree)
end

-- A partial stack is room enough, with no free slot (session 5: 10 fish into 3/20).
bags(0, 0, { [1] = { id = FOOD, count = 3 } })
eq(fits(FOOD, 10), true, "a partial stack takes it with no free slot")
eq(fits(FOOD, 18), false, "  but not more than its room")
bags(0, 0, { [1] = { id = FOOD, count = 3, locked = true } })
eq(fits(FOOD, 10), false, "a locked stack offers no room")

-- A specialty bag of the item's family, even with the general bags full (session 3).
bags(0, 2)
eq(fits(ARROW, 20), true, "an arrow fits the quiver with the general bags full")
eq(fits(ORE, 5), false, "  ore doesn't")
-- keepFree counts general slots only; a quiver item doesn't use the reserve.
bags(2, 2)
eq(fits(ORE, 5, 2), false, "keep 2 free: 2 general slots left is no room")
eq(fits(ORE, 5, 0), true, "  keep 0: it fits")
eq(fits(ARROW, 20, 2), true, "  an arrow goes to the quiver, the reserve untouched")
bags(3, 0)
eq(fits(ORE, 5, 2), true, "3 general free with 2 kept: room for one")

-- Unknown: no max stack (not cached), or no family with a specialty bag free.
eq(fits(4242, 1), nil, "an uncached item can't be told yet")
WoW.itemInfo[4243] = { maxStack = 20 }
bags(1, 2)
eq(fits(4243, 1), nil, "  nor one without a family while a specialty bag has room")
bags(1, 0)
eq(fits(4243, 1), true, "  with no specialty bag free, the family doesn't matter")
eq(Loot.Fits({ itemID = 1, count = 1, isCurrency = true }, Loot.Bags()), true, "a currency always fits")

-- Next: money first, then slots from the lowest; COD, GM, filters, failed items skipped.
bags(4, 4)
WoW.inbox = {
    { sender = "A", subject = "cod", cod = 500, items = { [1] = { id = ORE, count = 1 } } },
    { sender = "B", subject = "hi", isGM = true, money = 10 },
    { sender = "Horde Auction House", subject = "Auction won: Copper Ore", canReply = false, money = 300,
      items = { [1] = { id = ORE, count = 5 } } },
    { sender = "C", subject = "two", items = { [2] = { id = ORE, count = 1 }, [3] = { id = FOOD, count = 1 } } },
}
local opts = { keepFree = 0, failed = {}, types = { ah = true, system = true, player = true } }
local a = Loot.Next(GM.Scan.Inbox(), Loot.Bags(), opts)
eq(a and a.mail.index, 3, "COD and GM mail are left to the player")
eq(a.kind, "money", "  money first")
WoW.inbox[3].money = 0
a = Loot.Next(GM.Scan.Inbox(), Loot.Bags(), opts)
eq(a.kind .. ":" .. a.slot, "item:1", "  then the attachments")
opts.types.ah = false
a = Loot.Next(GM.Scan.Inbox(), Loot.Bags(), opts)
eq(a.mail.index, 4, "a filtered-out type is skipped")
eq(a.slot, 2, "  the lowest occupied slot, by its own number")
opts.failed[ORE] = true
a = Loot.Next(GM.Scan.Inbox(), Loot.Bags(), opts)
eq(a.slot, 3, "an item that failed this run is skipped, the next slot taken")
WoW.inbox[4].items[3] = { id = FOOD, count = 1, link = false }
eq(Loot.Next(GM.Scan.Inbox(), Loot.Bags(), opts), nil, "a mail with an attachment not linked yet is never taken from")
WoW.inbox[4].items[3] = nil
eq(Loot.Next(GM.Scan.Inbox(), Loot.Bags(), opts), nil, "nothing left: nil")

-- Tally: what's left and why the rest isn't, read once for the summary.
opts.failed = {}
opts.types.ah = true
WoW.inbox[4].items[3] = { id = 4242, count = 1 }
bags(0, 0)
local t = Loot.Tally(GM.Scan.Inbox(), Loot.Bags(), opts)
eq(t.cod, 1, "tally: one COD mail")
eq(t.gm, 1, "  one GM mail")
eq(t.full, 1, "  one whose items don't fit")
eq(t.loading, 1, "  one with an item not cached yet")
eq(t.left, 0, "  nothing left to take")

done("test_loot")
