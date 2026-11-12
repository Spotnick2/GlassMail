-- Core/Store.lua: the saved memory (M2), its shape, the play-day clock and
-- expiry. Owns GlassMailDB.version, playDay, lastDate and the subtrees chars,
-- recents, sent, trash and snapshots. The settings in the same table are not ours:
-- GlassMail.lua validates them, key by key, and nothing here touches them.
--
-- Everything saved ends by itself (PLAN.md, M2): records stamped in play days
-- age by expiryDays, Trash by real time (a mail's expiry), and every list has
-- a cap; a snapshot's mails go as they expire, and the snapshot with its
-- character. A subtree of an unreadable shape is dropped whole, never half-read.
-- Only plain values are saved: every field is checked with issecretvalue
-- before it is kept; a secret field is left out, and a record whose required
-- field (a name, a GUID) is secret is not kept at all.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Store = {}
GM.Store = Store

Store.VERSION = 1
Store.SENT_MAX = 1000
Store.TRASH_MAX = 500
Store.MAILS_MAX = 100                          -- a snapshot holds the loaded inbox at most
Store.EXPIRY_CHOICES = { 7, 14, 30, 60, 90 }   -- play days (setting expiryDays)
Store.RECENT_CHOICES = { 10, 20, 50 }          -- recent recipients kept (setting recentMax)

local SUBTREES = { "chars", "recents", "sent", "trash", "snapshots" }
-- Stamped in play days: they belong to the counter, and go when it restarts.
-- Snapshots too: they end with their characters, whose registry goes then.
local PLAY_DAY_SUBTREES = { "chars", "recents", "sent", "snapshots" }

-- Record shapes. `required`: a record without one of these (or of the wrong
-- type, or secret) is invalid. `optional`: a bad one is left out. Fields not
-- listed are not kept. "items" is a list of { id, count } numbers; "mails" a
-- list of records under the `mail` spec, at most MAILS_MAX.
local SPECS = {
    chars = {
        required = { name = "string", lastPlayDay = "number" },
        optional = { realm = "string", faction = "string" },
    },
    recents = {
        required = { name = "string", day = "number" },
        optional = {},
    },
    sent = {
        required = { kind = "string", day = "number", at = "number", from = "string", to = "string",
            state = "string" },
        optional = { subject = "string", money = "number", cod = "number", items = "items" },
        enums = { kind = { send = true, ["return"] = true }, state = { sent = true, unconfirmed = true } },
    },
    trash = {
        required = { at = "number", from = "string", expires = "number" },
        optional = { sender = "string", subject = "string", money = "number", cod = "number", items = "items" },
    },
    -- One character's mailbox as last seen (Core/Memory.lua), keyed by GUID.
    snapshots = {
        required = { at = "number", loaded = "number", total = "number", complete = "boolean", mails = "mails" },
        optional = {},
    },
    mail = {
        required = { expires = "number", type = "string" },
        optional = { sender = "string", subject = "string", money = "number", cod = "number",
            wasReturned = "boolean", items = "items" },
        enums = { type = { ah = true, system = true, player = true } },
    },
}

local clean

local function isList(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
        n = n + 1
    end
    return n == #t
end

local function plain(v, kind)
    if API.IsSecret(v) then return nil end
    if kind == "mails" then
        if not isList(v) or #v > Store.MAILS_MAX then return nil end
        local out = {}
        for i, m in ipairs(v) do
            out[i] = clean("mail", m)
            if out[i] == nil then return nil end
        end
        return out
    end
    if kind == "items" then
        if not isList(v) then return nil end
        local out = {}
        for i, it in ipairs(v) do
            if type(it) ~= "table" then return nil end
            local id, count = it.id, it.count
            if API.IsSecret(id) or API.IsSecret(count) or type(id) ~= "number" or type(count) ~= "number" then
                return nil
            end
            out[i] = { id = id, count = count }
        end
        return out
    end
    if type(v) ~= kind then return nil end
    if kind == "number" and v ~= v then return nil end   -- NaN
    return v
end

-- A clean copy of rec under spec `name`, or nil when it is invalid.
function clean(name, rec)
    local spec = SPECS[name]
    if type(rec) ~= "table" or API.IsSecret(rec) then return nil end
    local out = {}
    for field, kind in pairs(spec.required) do
        local v = plain(rec[field], kind)
        if v == nil then return nil end
        if spec.enums and spec.enums[field] and not spec.enums[field][v] then return nil end
        out[field] = v
    end
    for field, kind in pairs(spec.optional) do
        out[field] = plain(rec[field], kind)
    end
    return out
end
Store.Clean = clean

local function db() return GlassMailDB end

local function today() return date("%Y-%m-%d") end

local function validHeader(t)
    local day, last = rawget(t, "playDay"), rawget(t, "lastDate")
    return type(day) == "number" and day >= 1 and day % 1 == 0
        and type(last) == "string" and last:find("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

-- A keyed subtree (chars by GUID, recents by Names.Key): every entry valid,
-- or the whole subtree goes.
local function loadKeyed(name, t)
    if type(t) ~= "table" then return {} end
    local out = {}
    for k, rec in pairs(t) do
        if type(k) ~= "string" then return {} end
        local c = clean(name, rec)
        if not c then return {} end
        out[k] = c
    end
    return out
end

local function loadList(name, t)
    if not isList(t) then return {} end
    local out = {}
    for i, rec in ipairs(t) do
        local c = clean(name, rec)
        if not c then return {} end
        out[i] = c
    end
    return out
end

-- At ADDON_LOADED, after the settings are read. Never fails half-way: what
-- can't be read is dropped and starts empty.
function Store.Load()
    local t = db()
    if rawget(t, "version") ~= Store.VERSION then
        for _, k in ipairs(SUBTREES) do rawset(t, k, nil) end
        rawset(t, "playDay", nil)
        rawset(t, "lastDate", nil)
        rawset(t, "version", Store.VERSION)
    end
    if not validHeader(t) then
        rawset(t, "playDay", 1)
        rawset(t, "lastDate", today())
        for _, k in ipairs(PLAY_DAY_SUBTREES) do rawset(t, k, nil) end
    end
    rawset(t, "chars", loadKeyed("chars", rawget(t, "chars")))
    rawset(t, "recents", loadKeyed("recents", rawget(t, "recents")))
    rawset(t, "sent", loadList("sent", rawget(t, "sent")))
    rawset(t, "trash", loadList("trash", rawget(t, "trash")))
    rawset(t, "snapshots", loadKeyed("snapshots", rawget(t, "snapshots")))
    Store.loaded = true
end

function Store.Ready() return Store.loaded == true end
function Store.PlayDay() return rawget(db(), "playDay") end
function Store.Chars() return rawget(db(), "chars") end
function Store.Recents() return rawget(db(), "recents") end
function Store.Sent() return rawget(db(), "sent") end
function Store.Trash() return rawget(db(), "trash") end
function Store.Snapshots() return rawget(db(), "snapshots") end

-- Whoever shows the memory (the window): called after every change.
local watchers = {}
function Store.OnChange(fn) watchers[#watchers + 1] = fn end
local function changed()
    for _, fn in ipairs(watchers) do
        local ok, err = pcall(fn)
        if not ok then API.Fail("store watcher", err) end
    end
end

local function age(day) return Store.PlayDay() - day end

-- Expiry: play days for what ages with play, real time for Trash and a
-- snapshot's mails; then the caps. A snapshot goes with its character.
function Store.Prune()
    if not Store.Ready() then return end
    local before = Store.Count()
    local expiry = GM.db.expiryDays
    local current = GM.Registry and GM.Registry.CurrentGUID()
    local chars = Store.Chars()
    for guid, c in pairs(chars) do
        if guid ~= current and age(c.lastPlayDay) >= expiry then chars[guid] = nil end
    end
    local recents = Store.Recents()
    for k, r in pairs(recents) do
        if age(r.day) >= expiry then recents[k] = nil end
    end
    Store.TrimRecents()
    local sent, keep = Store.Sent(), {}
    for _, r in ipairs(sent) do
        if age(r.day) < expiry then keep[#keep + 1] = r end
    end
    while #keep > Store.SENT_MAX do table.remove(keep, 1) end
    rawset(db(), "sent", keep)
    local now, trash = time(), {}
    for _, e in ipairs(Store.Trash()) do
        if e.expires >= now then trash[#trash + 1] = e end
    end
    while #trash > Store.TRASH_MAX do table.remove(trash, 1) end
    rawset(db(), "trash", trash)
    local snapshots = Store.Snapshots()
    for guid, snap in pairs(snapshots) do
        if not chars[guid] then
            snapshots[guid] = nil
        else
            local mails = {}
            for _, m in ipairs(snap.mails) do
                if m.expires >= now then mails[#mails + 1] = m end
            end
            snap.mails = mails
        end
    end
    if Store.Count() ~= before then changed() end
end

-- How many records the memory holds, for Prune's "did anything go".
function Store.Count()
    local n = #Store.Sent() + #Store.Trash()
    for _ in pairs(Store.Chars()) do n = n + 1 end
    for _ in pairs(Store.Recents()) do n = n + 1 end
    for _, snap in pairs(Store.Snapshots()) do n = n + 1 + #snap.mails end
    return n
end

-- The oldest recent recipients past recentMax go (by day, then key: a play
-- day has no finer order).
function Store.TrimRecents()
    local recents = Store.Recents()
    local list = {}
    for k, r in pairs(recents) do list[#list + 1] = { key = k, day = r.day } end
    local max = GM.db.recentMax
    if #list <= max then return end
    table.sort(list, function(a, b)
        if a.day ~= b.day then return a.day < b.day end
        return a.key < b.key
    end)
    for i = 1, #list - max do recents[list[i].key] = nil end
end

-- The clock: at PLAYER_LOGIN, before any write or prune, and every 10
-- minutes. lastDate is a high-water mark: a later date counts once, an
-- earlier one (a clock set back) counts nothing.
function Store.Tick()
    if not Store.Ready() then return end
    local t, d = db(), today()
    if d > rawget(t, "lastDate") then
        rawset(t, "playDay", rawget(t, "playDay") + 1)
        rawset(t, "lastDate", d)
    end
    if GM.Registry then GM.Registry.Touch() end
    Store.Prune()
end

-- Insertions: cleaned, capped. False when the record isn't valid.
function Store.AddSent(rec)
    local c = Store.Ready() and clean("sent", rec)
    if not c then return false end
    local sent = Store.Sent()
    sent[#sent + 1] = c
    while #sent > Store.SENT_MAX do table.remove(sent, 1) end
    changed()
    return true
end

function Store.AddTrash(rec)
    local c = Store.Ready() and clean("trash", rec)
    if not c then return false end
    local trash = Store.Trash()
    trash[#trash + 1] = c
    while #trash > Store.TRASH_MAX do table.remove(trash, 1) end
    changed()
    return true
end

-- A recipient mailed today: keyed by Names.Key, shown as typed.
function Store.AddRecent(name)
    if not Store.Ready() then return false end
    local key, display = GM.Names.Key(name), GM.Names.Display(name)
    if not key then return false end
    Store.Recents()[key] = { name = display, day = Store.PlayDay() }
    Store.TrimRecents()
    return true
end

-- The current character's mailbox as last seen (Core/Memory.lua).
function Store.SetSnapshot(guid, snap)
    local c = Store.Ready() and not API.IsSecret(guid) and type(guid) == "string" and clean("snapshots", snap)
    if not c then return false end
    Store.Snapshots()[guid] = c
    changed()
    return true
end

-- Forget, from the window: only the memory changes, never the mailbox. Each
-- takes the record the window shows (the saved table itself).
local function removeFrom(list, rec)
    for i, r in ipairs(list) do
        if r == rec then
            table.remove(list, i)
            changed()
            return true
        end
    end
    return false
end
function Store.ForgetSent(rec) return Store.Ready() and removeFrom(Store.Sent(), rec) end
function Store.ForgetTrash(rec) return Store.Ready() and removeFrom(Store.Trash(), rec) end
function Store.ForgetSnapshot(guid)
    if not (Store.Ready() and Store.Snapshots()[guid]) then return false end
    Store.Snapshots()[guid] = nil
    changed()
    return true
end
function Store.ForgetMail(guid, mail)
    local snap = Store.Ready() and Store.Snapshots()[guid]
    return snap and removeFrom(snap.mails, mail) or false
end

function Store.SetChar(guid, rec)
    local c = Store.Ready() and not API.IsSecret(guid) and type(guid) == "string" and clean("chars", rec)
    if not c then return false end
    Store.Chars()[guid] = c
    return true
end

local function member(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end
function Store.ValidExpiry(n) return member(Store.EXPIRY_CHOICES, n) end
function Store.ValidRecentMax(n) return member(Store.RECENT_CHOICES, n) end

GM._test = GM._test or {}
GM._test.store = { SPECS = SPECS, today = today }
