-- Core/Bank.lua: N1's saved banks and rules, the groups, and the plan of one
-- mail to the bank, over fake bags (docs/PLAN.md, "N1: the bank character").
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local HERB, ORE, CLOTH, BREAD, RECIPE, SWORD = 765, 2770, 2589, 4540, 2553, 8177
WoW.itemInfo = {
    [HERB] = { class = 7, sub = 9 }, [ORE] = { class = 7, sub = 7 }, [CLOTH] = { class = 7, sub = 5 },
    [BREAD] = { class = 0, sub = 5 }, [RECIPE] = { class = 9, sub = 6 }, [SWORD] = { class = 2, sub = 7 },
}
WoW.bags = { [0] = { size = 16, family = 0, items = {} }, [1] = { size = 4, family = 0, items = {} },
    [2] = { size = 4, family = 1, items = {} } }

-- Saved junk, each entry judged alone.
local saved = { bank = {
    banks = {
        ["Horde:Normal"] = { name = "Cowruzo Banks", guid = "Player-1-BNK" },
        ["Alliance:PvP"] = { name = "Ally Bank" },
        ["nogroup"] = { name = "X" },
        ["Horde:RP"] = { name = "" },
        ["Horde:RPPvP"] = { guid = "Player-1-ZZZ" },
    },
    rules = {
        { item = ORE, keep = 20 },
        { item = ORE, keep = 5 },           -- a duplicate: the first wins
        { class = 7, sub = 9, keep = 0 },
        { class = 9, keep = 1 },            -- a whole class (Recipes)
        { class = 7, sub = 3, keep = 0 },   -- not an offered category
        { item = -4, keep = 0 },
        { item = CLOTH, keep = 10000 },     -- over the cap
        { item = CLOTH, class = 7, keep = 0 },
        { item = BREAD, keep = 1.5 },
        "junk",
    },
} }
local GM = loadAddon({ db = saved })
local Bank, Store = GM.Bank, GM.Store
local B = GlassMailDB.bank

eq(B.banks["Horde:Normal"] and B.banks["Horde:Normal"].name, "Cowruzo Banks", "load: a sound bank stays")
eq(B.banks["Alliance:PvP"] and B.banks["Alliance:PvP"].guid, nil, "  one without a GUID too")
check(B.banks["nogroup"] == nil and B.banks["Horde:RP"] == nil and B.banks["Horde:RPPvP"] == nil,
    "  a bad group, an empty name, a missing name: each dropped alone")
eq(#B.rules, 3, "load: three sound rules of ten")
eq(B.rules[1].item, ORE, "  the item rule")
eq(B.rules[1].keep, 20, "  its first copy wins")
check(B.rules[2].class == 7 and B.rules[2].sub == 9, "  the Herb category")
check(B.rules[3].class == 9 and B.rules[3].sub == nil, "  the whole Recipes class")

-- Groups.
eq(Bank.Group({ faction = "Horde", realm = "Doomhowl" }), "Horde:Normal", "a group: faction and ruleset")
eq(Bank.Group({ faction = "Horde", realm = "Sunfire PvP" }), "Horde:PvP", "  any realm of a ruleset")
eq(Bank.Group({ faction = "Horde" }), nil, "  no realm: no group")
eq(Bank.Group({ realm = "Doomhowl" }), nil, "  no faction: no group")
eq(Bank.CurrentGroup(), "Horde:Normal", "the playing character's group")
eq(Bank.GroupLabel("Horde:Normal"), "Horde, Normal", "  its label")

-- Bank.For: who the bank is, or why not.
Store.SetChar("Player-1-BNK", { name = "Cowruzo Banks", realm = "Doomhowl", faction = "Horde", lastPlayDay = 1 })
local b = Bank.For()
eq(b and b.name, "Cowruzo Banks", "For: the group's bank")
check(b and b.char ~= nil, "  resolved to a known character")
Bank.Clear("Horde:Normal")
local none, why = Bank.For()
check(none == nil and why == Bank.WHY_NONE, "  none set: why")
Bank.Set("Horde:Normal", "Karuzo Morphisto", WoW.playerGUID)
none, why = Bank.For()
check(none == nil and why == Bank.WHY_SELF, "  the bank is this character (by GUID)")
Bank.Set("Horde:Normal", "Karuzo Morphisto")
none, why = Bank.For()
check(none == nil and why == Bank.WHY_SELF, "  the bank is this character (by name, no GUID)")
Store.SetChar("Player-1-ALY", { name = "Ally Banks", realm = "Doomhowl", faction = "Alliance", lastPlayDay = 1 })
Bank.Set("Horde:Normal", "Ally Banks", "Player-1-ALY")
none, why = Bank.For()
check(none == nil and why == Bank.WHY_REACH, "  a bank of the other faction: not reachable")
Bank.Set("Horde:Normal", "Unknown Banks", "Player-1-XXX")
b = Bank.For()
check(b and b.name == "Unknown Banks" and b.char == nil, "  a bank no list knows: its saved name")
-- AltStable's list: a bank on the player's other account resolves by GUID, with its current name.
AltStable = { PUBLIC_API_VERSION = 1, PUBLIC_API_FEATURES = { provenance = true }, GetCharacters = function()
    return { { guid = "Player-1-XXX", name = "Renamed Banks", realm = "Doomhowl", faction = "Horde",
        provenance = "own-account" } }
end }
b = Bank.For()
check(b and b.name == "Renamed Banks" and b.char ~= nil, "  through AltStable's list (another account)")
AltStable = nil
WoW.realm = ""
none, why = Bank.For()
check(none == nil and why == Bank.WHY_GROUP, "  a realm that can't be read: no group")
WoW.realm = "Doomhowl"
Bank.Set("Horde:Normal", "Cowruzo Banks", "Player-1-BNK")
check(not Bank.Set("Horde:Normal", "", nil), "Set: an empty name refused")

-- Rules.
eq(Bank.Rule(ORE).item, ORE, "Rule: the item rule")
eq(Bank.Rule(HERB).sub, 9, "  else its category")
eq(Bank.Rule(RECIPE).class, 9, "  a whole class")
eq(Bank.Rule(BREAD), nil, "  else none")
check(Bank.AddCategory(7, 7, 3), "a category rule for Metal & Stone")
eq(Bank.Rule(ORE).item, ORE, "  the item rule still beats it")
check(Bank.AddItem(ORE, 8), "AddItem on an existing item")
eq(Bank.Rule(ORE).keep, 8, "  updates its keep")
local n = #Bank.Rules()
check(Bank.AddCategory(7, 7, 2), "AddCategory again")
eq(#Bank.Rules(), n, "  no duplicate")
check(not Bank.AddCategory(7, 3, 0), "  an unoffered category refused")
check(not Bank.AddItem(ORE, 10000), "  a keep over the cap refused")
check(not Bank.SetKeep(Bank.Rule(ORE), -1), "SetKeep: a negative keep refused")
check(Bank.SetKeep(Bank.Rule(ORE), 20), "SetKeep")
eq(Bank.Rule(ORE).keep, 20, "  saved")
local metal = Bank.Rule(9999) -- none
eq(metal, nil, "(an item without a rule)")
for _, r in ipairs(Bank.Rules()) do if r.class == 7 and r.sub == 7 then metal = r end end
check(Bank.Remove(metal), "Remove")
check(Bank.Rule(ORE) and Bank.Rule(ORE).item == ORE, "  the others stay")
local herbs
for _, r in ipairs(Bank.Rules()) do if r.class == 7 and r.sub == 9 then herbs = r end end
check(herbs ~= nil, "  the Herb category too")
local before = #Bank.Rules()
check(Bank.Remove(Bank.Rule(ORE)), "Remove the first rule")
eq(#Bank.Rules(), before - 1, "  one fewer")
eq(Bank.Rule(ORE), nil, "  the one asked for, not another")
Bank.AddItem(ORE, 20)
local changes = 0
Bank.OnChange(function() changes = changes + 1 end)
Bank.AddItem(BREAD, 0)
eq(changes, 1, "a change calls the watchers")
Bank.Remove(Bank.Rule(BREAD))

-- The plan. Ore keep 20: stacks 20, 7, 5, 3 and a bound 4 (counted, never moved).
local function bags(list0, list1, list2)
    WoW.bags[0].items, WoW.bags[1].items, WoW.bags[2].items = list0 or {}, list1 or {}, list2 or {}
end
bags({ [1] = { id = ORE, count = 20 }, [2] = { id = ORE, count = 7 }, [3] = { id = ORE, count = 5 },
    [4] = { id = ORE, count = 3 }, [5] = { id = ORE, count = 4, bound = true } })
-- total 39, keep 20: excess 19. Smallest first while each fits: 3, 5, 7 (15), then a split of 4 off the 20.
local p = Bank.Plan()
eq(#p.attach, 3, "Plan: three whole stacks")
check(p.attach[1].count == 3 and p.attach[2].count == 5 and p.attach[3].count == 7, "  smallest first")
eq(#p.splits, 1, "  and one split")
local sp = p.splits[1]
check(sp and sp.source.slot == 1 and sp.source.before == 20 and sp.source.after == 16 and sp.n == 4,
    "  4 off the 20, which keeps 16 (+ the bound 4 = keep 20)")
check(sp and sp.dest.bag == 0 and sp.dest.slot == 6, "  into the first empty general slot")
eq(p.units, 19, "  19 units in all")

-- Keep at or above the total: nothing.
Bank.SetKeep(Bank.Rule(ORE), 39)
p = Bank.Plan()
check(#p.attach == 0 and #p.splits == 0, "keep equal to the total: nothing")
Bank.SetKeep(Bank.Rule(ORE), 500)
check(#Bank.Plan().attach == 0, "keep above the total: nothing")
Bank.SetKeep(Bank.Rule(ORE), 0)
p = Bank.Plan()
eq(#p.attach, 4, "keep 0: every movable stack")
eq(#p.splits, 0, "  no split")

-- A locked stack and a refused item: counted, not moved.
bags({ [1] = { id = ORE, count = 5, locked = true }, [2] = { id = ORE, count = 6 } })
Bank.SetKeep(Bank.Rule(ORE), 5)
p = Bank.Plan()
check(#p.attach == 1 and p.attach[1].count == 6, "a locked stack counts toward keep, isn't moved")
Bank.Refuse(ORE)
p = Bank.Plan()
check(#p.attach == 0, "a refused item: not moved this session")
GM._test.bank.refused[ORE] = nil

-- No empty general slot: no split (keep at least N). Bag 2 is a specialty bag.
bags({ [1] = { id = ORE, count = 6 }, [2] = { id = ORE, count = 5 } }, {}, {})
for s = 3, 16 do WoW.bags[0].items[s] = { id = SWORD, count = 1 } end
for s = 1, 4 do WoW.bags[1].items[s] = { id = SWORD, count = 1 } end
Bank.SetKeep(Bank.Rule(ORE), 2)
p = Bank.Plan()
-- excess 9: the 5 fits, then a split of 4 off the 6, but no empty general slot.
check(#p.attach == 1 and p.attach[1].count == 5 and #p.splits == 0, "no empty general slot: no split, keep at least N")
WoW.bags[1].items[4] = nil
p = Bank.Plan()
check(#p.splits == 1 and p.splits[1].dest.bag == 1 and p.splits[1].dest.slot == 4, "  an empty slot: the split")

-- The 12-attachment cap, and what's left.
local many = {}
for s = 1, 15 do many[s] = { id = CLOTH, count = 2 } end
bags(many)
Bank.AddItem(CLOTH, 0)
p = Bank.Plan()
eq(#p.attach, 12, "a mail holds 12 attachments")
eq(p.left, 6, "  6 units left for the next")
local units, mails = Bank.Available()
eq(units, 30, "Available: everything movable")
eq(mails, 2, "  in two mails")

-- A category rule, a bound item under it, an item without a rule.
bags({ [1] = { id = HERB, count = 4 }, [2] = { id = RECIPE, count = 1 }, [3] = { id = BREAD, count = 5 },
    [4] = { id = HERB, count = 1, bound = true } })
p = Bank.Plan()
local got = {}
for _, s in ipairs(p.attach) do got[s.itemID] = s.count end
eq(got[HERB], 4, "a category rule: the herbs")
eq(got[RECIPE], nil, "  the Recipes rule keeps 1: nothing of the one recipe")
eq(got[BREAD], nil, "  no rule: no bread")
eq(#p.attach, 1, "  the bound herb stays")

-- Totals: everything in bags 0-4, bound and locked included.
bags({ [1] = { id = ORE, count = 5, bound = true }, [2] = { id = ORE, count = 6, locked = true } })
eq(Bank.Totals({ ORE })[ORE], 11, "Totals: bound and locked units count")

-- An unreadable count: the item is left out of the plan.
bags({ [1] = { id = ORE, count = WoW.Secret("n") }, [2] = { id = ORE, count = 6 } })
Bank.SetKeep(Bank.Rule(ORE), 0)
eq(#Bank.Plan().attach, 0, "a secret count: the item is left out")

-- The clean copy is what is saved.
eq(GlassMailDB.bank.banks["Horde:Normal"].name, "Cowruzo Banks", "the banks are saved in GlassMailDB.bank")

done("test_bank")
