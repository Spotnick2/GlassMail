-- Core/Loot.lua: what Open All takes next, and whether it fits. Pure
-- functions over a Scan snapshot and a bag model; Core/Ops.lua dispatches.
--
-- Measured (FOREVER-PROBE sessions 1, 3, 5): money needs no bag slot; a
-- partial stack of the item is room enough; a specialty bag of a matching
-- family takes its items first and even when the general bags are full; the
-- free-slot reserve ("keep N free") counts general bags only, as Blizzard's
-- own total does. Bags 0-4 only: the reagent bag (5) is unmeasured.

GlassMailbox = GlassMailbox or {}
local GM = GlassMailbox
local Loot = {}
GM.Loot = Loot

Loot.KEEP_FREE = { 0, 2, 5, 10 }

-- { general = free general slots, specialty = { { free, family }, ... },
--   stacks = { [itemID] = { stackCount, ... } } } over the unlocked stacks.
function Loot.Bags()
    local bags = { general = 0, specialty = {}, stacks = {} }
    for b = 0, NUM_BAG_SLOTS or 4 do
        local free, family = C_Container.GetContainerNumFreeSlots(b)
        free, family = free or 0, family or 0
        if family == 0 then bags.general = bags.general + free
        elseif free > 0 then bags.specialty[#bags.specialty + 1] = { free = free, family = family } end
        for s = 1, C_Container.GetContainerNumSlots(b) or 0 do
            local info = C_Container.GetContainerItemInfo(b, s)
            -- A locked stack (on the cursor, mid-move) offers no room.
            if info and info.itemID and not info.isLocked then
                local list = bags.stacks[info.itemID] or {}
                list[#list + 1] = info.stackCount or 1
                bags.stacks[info.itemID] = list
            end
        end
    end
    return bags
end

-- true, false, or nil when it can't be told yet (item facts not cached).
function Loot.Fits(item, bags, keepFree)
    if item.isCurrency then return true end
    local maxStack = C_Item.GetItemMaxStackSizeByID(item.itemID)
    if not maxStack then return nil end
    local room = 0
    for _, count in ipairs(bags.stacks[item.itemID] or {}) do
        if count < maxStack then room = room + maxStack - count end
    end
    if item.count <= room then return true end
    if #bags.specialty > 0 then
        local family = C_Item.GetItemFamily(item.itemID)
        if family == nil then return nil end
        for _, bag in ipairs(bags.specialty) do
            if bit.band(family, bag.family) ~= 0 then return true end
        end
    end
    return bags.general > (keepFree or 0)
end

-- What this mail offers now, or nil, and why not: "cod", "filtered",
-- "loading", "full", "failed". Money first (it needs no slot), then the
-- occupied slots from the lowest; COD and GM mail are left to the player, as
-- Blizzard's Open All does.
local function mailAction(m, bags, opts)
    if not m.resolved then return nil, "loading" end
    if m.cod > 0 then return nil, "cod" end
    if m.isGM then return nil, "gm" end
    if opts.types and opts.types[m.type] == false then return nil, "filtered" end
    if m.money > 0 then return { mail = m, kind = "money" } end
    local why
    for _, it in ipairs(m.items) do
        if not it.isCurrency and opts.failed and opts.failed[it.itemID] then
            why = why or "failed"
        else
            local fits = Loot.Fits(it, bags, opts.keepFree)
            if fits then return { mail = m, kind = "item", slot = it.slot, itemID = it.itemID } end
            why = (fits == nil) and "loading" or (why or "full")
        end
    end
    return nil, why
end

-- The next action in inbox order, or nil.
function Loot.Next(snap, bags, opts)
    for _, m in ipairs(snap.mails) do
        local action = mailAction(m, bags, opts)
        if action then return action end
    end
end

-- How many mails still offer something, and why the others don't:
-- { left = n, cod = n, full = n, loading = n, failed = n, filtered = n, gm = n }.
-- Read once at the end of a run for the summary, and for "Stop (n)".
function Loot.Tally(snap, bags, opts)
    local t = { left = 0 }
    for _, m in ipairs(snap.mails) do
        local action, why = mailAction(m, bags, opts)
        if action then t.left = t.left + 1
        elseif why then t[why] = (t[why] or 0) + 1 end
    end
    return t
end
