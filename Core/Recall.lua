-- Core/Recall.lua: N2, return assistance for misdirected mail (PLAN.md, "N2:
-- recall"). No frames: Inbox.lua shows what Recall.Inbox finds, Window.lua
-- marks and unmarks.
--
-- A send to one of your characters on this WoW account is marked `recall` in
-- Sent (Store.SetRecall: `recall` and the sender's name, `fromName`). When
-- that character opens a mailbox, the mails that could be it are found by
-- comparison: sender, subject, money, COD and the attachments as (itemID,
-- count), whatever their slots. There is no mail ID, so "sure" means the one
-- actionable candidate, not proven identity: both ends are the player's own
-- characters, so a wrong match only sends a mail back to another of them.
-- Returning is the player's click (Inbox.lua, through Ops.Act); a confirmed
-- return, ours or by hand, ends the oldest matching recall (Trash calls
-- OnReturned).
--
-- No test of the mail's type: LibMailbox classifies by the AH subject
-- templates first, so an alt's mail titled like one is `ah`; the sender's name
-- (one of your characters) already rules out real AH and system mail.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Store, Names, Registry, Ops = GM.Store, GM.Names, GM.Registry, GM.Ops
local Recall = {}
GM.Recall = Recall

local DAY = 86400

Recall.WHY_UNREAD = "Glass Mail couldn't read all of this mail when it was sent."
Recall.WHY_EMPTY = "Nothing was attached: only mail with items or gold can be recalled."
Recall.WHY_SENDER = "Glass Mail no longer knows the character that sent it."
Recall.WHY_RECIPIENT = "Only mail to your characters on this WoW account can be recalled, and only once "
    .. "they have logged in with Glass Mail. Log in to it once with Glass Mail."
Recall.WHY_REACH = "%s can't get mail from %s (another faction or ruleset)."

local function plain(v, kind)
    if API.IsSecret(v) or type(v) ~= kind then return nil end
    if kind == "number" and v ~= v then return nil end
    return v
end

-- The attachments as a sorted multiset key: saved items { id, count } or a
-- scanned mail's { itemID, count, isCurrency } (a currency is never sent: left
-- out, as Memory leaves it out). nil when a field isn't a plain number.
local function itemsKey(items)
    if type(items) ~= "table" then return nil end
    local out = {}
    for _, it in ipairs(items) do
        if type(it) ~= "table" then return nil end
        if it.isCurrency ~= true then
            local id, count = plain(it.id or it.itemID, "number"), plain(it.count or 1, "number")
            if not (id and count) then return nil end
            out[#out + 1] = id .. "x" .. count
        end
    end
    table.sort(out)
    return table.concat(out, ",")
end

-- A record that can be compared: a sender name, and every field that says
-- what was in it (one the Store dropped is unknown, never 0).
local function comparable(rec)
    if type(rec) ~= "table" then return nil end
    local key = Names.Key(rec.fromName)
    if not key or not plain(rec.subject, "string") or not plain(rec.money, "number")
        or not plain(rec.cod, "number") then
        return nil
    end
    local items = itemsKey(rec.items)
    if not items then return nil end
    return key, items
end

-- True when the mail m (a scanned one, with its inbox index, or a snapshot's)
-- could be the recalled send rec.
function Recall.Matches(rec, m)
    local key, items = comparable(rec)
    if not key or type(m) ~= "table" or m.secret or m.wasReturned then return false end
    if Names.Key(m.sender) ~= key or m.subject ~= rec.subject then return false end
    if m.money ~= rec.money or m.cod ~= rec.cod then return false end
    -- A scanned mail: every attachment read (a secret stops the list part way).
    if m.index ~= nil and #(m.items or {}) ~= (m.itemCount or 0) then return false end
    return itemsKey(m.items or {}) == items
end

-- The saved character named `name`, other than the GUID `not`: guid, entry.
local function charNamed(name, notGUID)
    local key = Names.Key(name)
    if not key or not Store.Ready() then return nil end
    for guid, c in pairs(Store.Chars()) do
        if guid ~= notGUID and Names.Key(c.name) == key then return guid, c end
    end
end

-- Mail from a can reach b: the same faction and the same known ruleset,
-- judged from the two saved characters (not the one playing). Two unknowns
-- don't agree.
local function reaches(a, b)
    if not (plain(a.faction, "string") and plain(b.faction, "string")) or a.faction ~= b.faction then return false end
    local ruleset = Registry.RulesetOf(a.realm)
    return ruleset ~= "Unknown" and Registry.RulesetOf(b.realm) == ruleset
end

-- Whether a Sent record can be marked: true and the sender's name, or false
-- and why (nil for a return: it gets no toggle).
function Recall.CanMark(rec)
    if type(rec) ~= "table" or rec.kind ~= "send" then return false, nil end
    if not plain(rec.subject, "string") or not plain(rec.money, "number") or not plain(rec.cod, "number")
        or not itemsKey(rec.items) then
        return false, Recall.WHY_UNREAD
    end
    if #rec.items == 0 and rec.money <= 0 then return false, Recall.WHY_EMPTY end
    local sender = Store.Ready() and Store.Chars()[rec.from]
    if not sender or not Names.Key(sender.name) then return false, Recall.WHY_SENDER end
    local key = Names.Key(rec.to)
    local found
    for guid, c in pairs(key and Store.Chars() or {}) do
        if guid ~= rec.from and Names.Key(c.name) == key then
            if reaches(sender, c) then return true, sender.name end
            found = c
        end
    end
    if found then return false, Recall.WHY_REACH:format(rec.to, sender.name) end
    return false, Recall.WHY_RECIPIENT
end

-- Mark (with the sender's name) or unmark. False when it can't be marked.
function Recall.Toggle(rec)
    if type(rec) ~= "table" then return false end
    if rec.recall then return Store.SetRecall(rec, false) end
    local ok, name = Recall.CanMark(rec)
    return ok and Store.SetRecall(rec, true, name) or false
end

-- The marked records sent to the character playing, oldest first.
function Recall.Mine()
    local out = {}
    local me = Names.Key(API.PlayerFullName())
    if not me or not Store.Ready() then return out end
    for _, r in ipairs(Store.Sent()) do
        if r.recall == true and r.kind == "send" and Names.Key(r.to) == me then out[#out + 1] = r end
    end
    return out
end

-- What the inbox shows (snap and counts: Inbox.lua's own scan). { rows =
-- { [inbox index] = "sure" | "possible" }, found = { { rec, mails, sure } }
-- for each recall with a matching mail, in Mine's order }. sure is the
-- recall's only matching mail when it is unique and Blizzard would return it.
function Recall.Inbox(snap, counts)
    local out = { rows = {}, found = {} }
    local mine = Recall.Mine()
    if #mine == 0 or type(snap) ~= "table" then return out end
    for _, rec in ipairs(mine) do
        local mails = {}
        for _, m in ipairs(snap.mails or {}) do
            if Recall.Matches(rec, m) then mails[#mails + 1] = m end
        end
        if #mails > 0 then
            local one = #mails == 1 and mails[1]
            local sure = one and one.fp and counts[one.fp] == 1 and Ops.RowAction(one) == "return" and one or nil
            out.found[#out.found + 1] = { rec = rec, mails = mails, sure = sure }
            for _, m in ipairs(mails) do
                if sure == m then out.rows[m.index] = "sure"
                elseif out.rows[m.index] ~= "sure" then out.rows[m.index] = "possible" end
            end
        end
    end
    return out
end

-- A return Trash confirmed (m as it was before it): the oldest matching
-- recall ends, and chat says so. True when one did.
function Recall.OnReturned(m)
    for _, rec in ipairs(Recall.Mine()) do
        if Recall.Matches(rec, m) then
            Store.SetRecall(rec, false)
            API.Print("sent back to " .. (Names.Display(m.sender) or "its sender") .. ": \"" .. m.subject .. "\"")
            return true
        end
    end
    return false
end

local function ago(at)
    local d = math.floor((time() - at) / DAY)
    if d <= 0 then return "today" end
    return (d == 1 and "1 day" or (d .. " days")) .. " ago"
end

-- Where a marked send is, from the recipient's snapshot: a short form for the
-- row and the full sentence for its tooltip. A miss is said of Glass Mail's
-- memory, never of the mailbox: a mail forgotten in the window or pruned at
-- its expiry is gone from the snapshot, not from the mailbox.
function Recall.Seen(rec)
    local to = rec.to or "?"
    local guid = charNamed(rec.to, rec.from)
    local snap = guid and Store.Snapshots()[guid]
    if not snap or snap.at < rec.at then
        return "not seen yet", to .. "'s mailbox hasn't been seen since it was sent"
    end
    for _, m in ipairs(snap.mails) do
        if Recall.Matches(rec, m) then
            return "in " .. to .. "'s mailbox", "A matching mail is in " .. to .. "'s mailbox (seen " .. ago(snap.at) .. ")"
        end
    end
    if snap.complete then
        return "not found", "No matching mail in what Glass Mail saved of " .. to .. "'s mailbox (read "
            .. ago(snap.at) .. ")"
    end
    return "not read whole", to .. "'s mailbox wasn't read whole at its last visit (" .. ago(snap.at) .. ")"
end

GM._test = GM._test or {}
GM._test.recall = { itemsKey = itemsKey, reaches = reaches }
