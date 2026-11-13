-- Core/Bank.lua: N1, the bank character (docs/PLAN.md, "N1: the bank
-- character"). No frames: the saved banks and rules, the groups, and what one
-- mail to the bank should carry, read fresh from the bags every time.
--
-- Saved in GlassMailDB.bank, checked here on load (a small loader of its own,
-- not Store's): { banks = { [group] = { name, guid? } }, rules = { ... } }.
-- A group is "faction:ruleset"; a rule is { item = id, keep = n } or
-- { class = c, sub = s?, keep = n }. Not expired: the owner sets them.

GlassMail = GlassMail or {}
local GM = GlassMail
local API, Registry, Names = GM.API, GM.Registry, GM.Names
local Bank = {}
GM.Bank = Bank

Bank.MAX_KEEP = 9999
local FIRST_BAG, LAST_BAG = 0, 4

-- The categories offered (ItemSubClass, build 70938, References\Forever\db):
-- Trade Goods' subclasses, then Recipes as a whole class (sub nil).
Bank.CATEGORIES = {
    { class = 7, sub = 5 }, { class = 7, sub = 6 }, { class = 7, sub = 7 }, { class = 7, sub = 8 },
    { class = 7, sub = 9 }, { class = 7, sub = 10 }, { class = 7, sub = 12 }, { class = 7, sub = 1 },
    { class = 7, sub = 11 }, { class = 9 },
}

Bank.WHY_NONE = "No bank set for this character's faction and ruleset: choose one on the Bank page (/gmail bank)."
Bank.WHY_GROUP = "This character's faction or ruleset isn't known yet."
Bank.WHY_SELF = "This character is the bank."
Bank.WHY_REACH = "The bank can't receive mail from this character (another faction or ruleset)."

local data          -- the checked GlassMailDB.bank
local watchers = {}
local refused = {}  -- itemID -> true: a drop the client refused this session

local function maxAttach() return rawget(_G, "ATTACHMENTS_MAX_SEND") or 12 end
Bank.MaxAttach = maxAttach

--------------------------------------------------------------------------------
-- Loading and checking
--------------------------------------------------------------------------------

local function plain(v)   -- v, or nil when it is secret (false stays false)
    if API.IsSecret(v) then return nil end
    return v
end
local function posInt(v) return type(v) == "number" and v > 0 and v % 1 == 0 and v < 2 ^ 31 end
local function keepOk(v) return type(v) == "number" and v >= 0 and v <= Bank.MAX_KEEP and v % 1 == 0 end

-- The offered category { class, sub } matches, or nil.
function Bank.Category(class, sub)
    for _, c in ipairs(Bank.CATEGORIES) do
        if c.class == class and c.sub == sub then return c end
    end
end

local function cleanRule(r)
    if type(r) ~= "table" or not keepOk(rawget(r, "keep")) then return nil end
    local item, class, sub = rawget(r, "item"), rawget(r, "class"), rawget(r, "sub")
    if item ~= nil then
        if class ~= nil or sub ~= nil or not posInt(item) then return nil end
        return { item = item, keep = r.keep }
    end
    if not (type(class) == "number" and Bank.Category(class, sub)) then return nil end
    return { class = class, sub = sub, keep = r.keep }
end

local function ruleKey(r) return r.item and ("i" .. r.item) or ("c" .. r.class .. "." .. tostring(r.sub)) end

local function cleanBank(group, b)
    if type(group) ~= "string" or not group:match("^[^:]+:[^:]+$") or type(b) ~= "table" then return nil end
    local name, guid = rawget(b, "name"), rawget(b, "guid")
    if API.IsSecret(name) or type(name) ~= "string" or not name:find("%S") then return nil end
    if guid ~= nil and (API.IsSecret(guid) or type(guid) ~= "string") then guid = nil end
    return { name = name, guid = guid }
end

-- Read GlassMailDB.bank, keep what is sound (each entry on its own), write
-- the clean copy back.
function Bank.Load()
    local db = type(GlassMailDB) == "table" and GlassMailDB or nil
    local raw = db and rawget(db, "bank")
    local clean = { banks = {}, rules = {} }
    if type(raw) == "table" then
        local banks, rules = rawget(raw, "banks"), rawget(raw, "rules")
        if type(banks) == "table" then
            for group, b in pairs(banks) do clean.banks[group] = cleanBank(group, b) end
        end
        if type(rules) == "table" then
            local seen = {}
            for i = 1, #rules do
                local r = cleanRule(rules[i])
                if r and not seen[ruleKey(r)] then
                    seen[ruleKey(r)] = true
                    clean.rules[#clean.rules + 1] = r
                end
            end
        end
    end
    data = clean
    if db then rawset(db, "bank", clean) end
    return true
end

function Bank.Loaded() return data ~= nil end

local function changed()
    for _, fn in ipairs(watchers) do
        local ok, err = pcall(fn)
        if not ok then API.Fail("bank watcher", err) end
    end
end
function Bank.OnChange(fn) watchers[#watchers + 1] = fn end

--------------------------------------------------------------------------------
-- Groups and banks
--------------------------------------------------------------------------------

-- A character's group ("Horde:Normal"), or nil when its faction or ruleset
-- isn't known.
function Bank.Group(c)
    local faction = c and plain(c.faction)
    local ruleset = c and Registry.RulesetOf(c.realm)
    if type(faction) ~= "string" or faction == "" or ruleset == "Unknown" then return nil end
    return faction .. ":" .. ruleset
end

function Bank.CurrentGroup() return Bank.Group(Registry.Current()) end

-- "Horde, Normal" for a group key.
function Bank.GroupLabel(group)
    local f, r = tostring(group or ""):match("^([^:]+):(.+)$")
    return f and (f .. ", " .. r) or tostring(group)
end

function Bank.Banks() return data and data.banks or {} end
function Bank.Get(group) return group and data and data.banks[group] or nil end

function Bank.Set(group, name, guid)
    local b = data and cleanBank(group, { name = name, guid = guid })
    if not b then return false end
    data.banks[group] = b
    changed()
    return true
end

function Bank.Clear(group)
    if not (data and group and data.banks[group]) then return false end
    data.banks[group] = nil
    changed()
    return true
end

-- The bank as it is now: its GUID looked up in Registry.Characters()
-- (AltStable's list included), else the saved name. { name, guid, char? }.
function Bank.Resolve(b)
    if not b then return nil end
    if b.guid then
        for _, c in ipairs(Registry.Characters()) do
            if c.guid == b.guid then return { name = c.name, guid = c.guid, char = c } end
        end
    end
    return { name = b.name, guid = b.guid }
end

-- The current character's bank { name, guid, char? }, or nil and why.
function Bank.For()
    local group = Bank.CurrentGroup()
    if not group then return nil, Bank.WHY_GROUP end
    local r = Bank.Resolve(Bank.Get(group))
    if not r then return nil, Bank.WHY_NONE end
    local me = Registry.Current()
    if (r.guid and r.guid == me.guid) or (Names.Key(r.name) and Names.Key(r.name) == Names.Key(me.name)) then
        return nil, Bank.WHY_SELF
    end
    if r.char and not Registry.Reachable(r.char) then return nil, Bank.WHY_REACH end
    return r
end

--------------------------------------------------------------------------------
-- Rules
--------------------------------------------------------------------------------

function Bank.Rules() return data and data.rules or {} end

local function find(key)
    for i, r in ipairs(Bank.Rules()) do
        if ruleKey(r) == key then return r, i end
    end
end

-- Add a rule, or update the keep of the one that exists. True when saved.
function Bank.AddItem(itemID, keep)
    local r = data and cleanRule({ item = itemID, keep = keep or 0 })
    if not r then return false end
    local old = find(ruleKey(r))
    if old then old.keep = r.keep else data.rules[#data.rules + 1] = r end
    changed()
    return true
end

function Bank.AddCategory(class, sub, keep)
    local r = data and cleanRule({ class = class, sub = sub, keep = keep or 0 })
    if not r then return false end
    local old = find(ruleKey(r))
    if old then old.keep = r.keep else data.rules[#data.rules + 1] = r end
    changed()
    return true
end

function Bank.SetKeep(rule, keep)
    if not keepOk(keep) then return false end
    local r = rule and find(ruleKey(rule))
    if not r then return false end
    r.keep = keep
    changed()
    return true
end

function Bank.Remove(rule)
    if not rule then return false end
    local r, i = find(ruleKey(rule))
    if not r then return false end
    table.remove(data.rules, i)
    changed()
    return true
end

-- The rule for an item: its item rule, else its category's (class and
-- subclass from GetItemInfoInstant, no cache needed), else nil.
function Bank.Rule(itemID)
    if not posInt(itemID) then return nil end
    local r = find("i" .. itemID)
    if r then return r end
    local ok, _, _, _, _, _, class, sub = pcall(C_Item.GetItemInfoInstant, itemID)
    if not ok or type(class) ~= "number" then return nil end
    return find("c" .. class .. "." .. tostring(sub)) or find("c" .. class .. ".nil")
end

-- A refused drop (the client kept it on the cursor): skipped this session.
function Bank.Refuse(itemID) if itemID then refused[itemID] = true; changed() end end

--------------------------------------------------------------------------------
-- The bags and the plan
--------------------------------------------------------------------------------

-- Every item with a rule in bags 0-4: { [itemID] = { rule, total, stacks =
-- { bag, slot, itemID, count } (movable: unbound, unlocked, not refused),
-- unreadable } }, and the empty general slots { bag, slot }.
function Bank.Scan()
    local items, empty = {}, {}
    for bag = FIRST_BAG, LAST_BAG do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        local _, family = C_Container.GetContainerNumFreeSlots(bag)
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info == nil then
                if family == 0 then empty[#empty + 1] = { bag = bag, slot = slot } end
            elseif type(info) == "table" then
                local id = plain(info.itemID)
                local rule = id and Bank.Rule(id)
                if rule then
                    local e = items[id] or { rule = rule, total = 0, stacks = {} }
                    items[id] = e
                    local count, bound, locked = plain(info.stackCount), plain(info.isBound), plain(info.isLocked)
                    if type(count) ~= "number" or type(bound) ~= "boolean" or type(locked) ~= "boolean" then
                        e.unreadable = true
                    else
                        e.total = e.total + count
                        if not bound and not locked and not refused[id] then
                            e.stacks[#e.stacks + 1] = { bag = bag, slot = slot, itemID = id, count = count }
                        end
                    end
                end
            end
        end
    end
    return items, empty
end

local function ids(items)
    local out = {}
    for id in pairs(items) do out[#out + 1] = id end
    table.sort(out)
    return out
end

-- One item's share: whole stacks smallest first while each fits in what is
-- left of the excess, then the split the rest needs (from the smallest stack
-- larger than it, not taken). { whole = {...}, split = { stack, n } | nil }.
local function share(e)
    local excess = e.total - e.rule.keep
    local out = { whole = {} }
    if e.unreadable or excess <= 0 then return out end
    local stacks = {}
    for _, s in ipairs(e.stacks) do stacks[#stacks + 1] = s end
    table.sort(stacks, function(a, b)
        if a.count ~= b.count then return a.count < b.count end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    local taken = {}
    for i, s in ipairs(stacks) do
        if s.count <= excess then
            out.whole[#out.whole + 1] = s
            taken[i] = true
            excess = excess - s.count
        end
    end
    if excess > 0 then
        for i, s in ipairs(stacks) do
            if not taken[i] and s.count > excess then
                out.split = { stack = s, n = excess }
                break
            end
        end
    end
    return out
end

-- What one mail should carry, from the bags as they are now:
-- { attach = { { bag, slot, itemID, count } }, splits = { { source = { bag,
-- slot, itemID, before, after }, dest = { bag, slot }, n } }, units, left }.
-- `attach` and the splits' new stacks together fit one mail; a split needs an
-- empty general slot of its own. `left`: units movable after this batch.
-- limit = nil: one mail; math.huge: everything (Bank.Available).
function Bank.Plan(limit)
    limit = limit or maxAttach()
    local items, empty = Bank.Scan()
    local plan = { attach = {}, splits = {}, units = 0, left = 0 }
    local used, freeIndex = 0, 1
    for _, id in ipairs(ids(items)) do
        local sh = share(items[id])
        for _, s in ipairs(sh.whole) do
            if used < limit then
                plan.attach[#plan.attach + 1] = s
                plan.units, used = plan.units + s.count, used + 1
            else
                plan.left = plan.left + s.count
            end
        end
        if sh.split then
            local dest = empty[freeIndex]
            if dest and used < limit then
                freeIndex = freeIndex + 1
                local s = sh.split.stack
                plan.splits[#plan.splits + 1] = {
                    source = { bag = s.bag, slot = s.slot, itemID = id, before = s.count, after = s.count - sh.split.n },
                    dest = dest, n = sh.split.n,
                }
                plan.units, used = plan.units + sh.split.n, used + 1
            elseif dest then
                plan.left = plan.left + sh.split.n
            end
        end
    end
    return plan
end

-- Units the plan can move in all, and the mails that takes.
function Bank.Available()
    local p = Bank.Plan(math.huge)
    local n = #p.attach + #p.splits
    return p.units, n > 0 and math.ceil(n / maxAttach()) or 0
end

-- Units of each itemID in bags 0-4, bound and locked ones included (for
-- the keep check after Prepare). nil for an item whose count can't be read.
function Bank.Totals(itemIDs)
    local want, out = {}, {}
    for _, id in ipairs(itemIDs) do want[id], out[id] = true, 0 end
    for bag = FIRST_BAG, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = type(info) == "table" and plain(info.itemID)
            if id and want[id] and out[id] then
                local n = plain(info.stackCount)
                out[id] = type(n) == "number" and out[id] + n or nil
            end
        end
    end
    return out
end

GM._test = GM._test or {}
GM._test.bank = { data = function() return data end, refused = refused, share = share }
