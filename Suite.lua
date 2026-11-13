-- Suite.lua: following Glass UI's suite (docs/PLAN.md, "Following Glass UI's
-- suite"; Glass UI's docs/SUITE.md and docs/SUITE-LOOK.md, Suite.API 1;
-- GlassChat's Suite.lua is the model).
--
-- Glass UI is optional. Whether Glass Mail follows it is read once per
-- session, at our ADDON_LOADED (## OptionalDeps: GlassUI loads it first, so
-- it is ready: Glass UI's S.2, measured on 70450), before any glass is built:
-- - the material is Theme's preset while following, else Pearl, our own
--   (owner, 2026-11-12); Glass.lua builds it once;
-- - the look is the suite look's tint (clear, smoked, class), live through
--   EventRegistry "GlassUI.Suite.LookChanged", unless the player set one in
--   Glass Mail: an override, in GlassMailDB.suiteOwn, never pruned against
--   our defaults. Blizzard's own look is reported as declined, by our choice;
-- - the accent colours our own gold text (the picker's headers), never a
--   Blizzard label.
-- Not following (no Glass UI, an incompatible one, its switch off): the
-- `skin` setting, as before. An old saved `skin` never becomes an override
-- (owner: everyone starts following).
--
-- Everything read from Glass UI goes through rawget and every call through
-- pcall, and its answers are checked whole before use: a junk or throwing
-- suite means our own look, never an error and never a mix.

local ADDON = ...
GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Suite = {}
GM.Suite = Suite

Suite.ADDON = ADDON or "GlassMail"
Suite.EVENT = "GlassUI.Suite.LookChanged"
Suite.DECLINED = "Blizzard's own"
Suite.TINTS = { clear = true, smoked = true, class = true }   -- the suite's tints we know
-- Our copies of the accents (GlassChat's), for a known name Glass UI can't colour.
Suite.ACCENTS = { gold = { 1, 0.82, 0 }, ice = { 0.65, 0.835, 0.905 } }
Suite.GOLD = "gold"

local S                  -- GlassUI.Suite when it speaks API 1
local status = "absent"  -- "absent" | "incompatible" | "following" | "not-following"
local started = false
local suiteLook = {}     -- the suite's tint and accent we know, copied (its payload is read-only)

local function read(t, k)
    if type(t) == "table" then return rawget(t, k) end
end

-- Glass UI's suite, when it speaks API 1 exactly; else nil, and why.
local function suiteAPI()
    local G = rawget(_G, "GlassUI")
    if type(G) ~= "table" then return nil, "absent" end
    local s = rawget(G, "Suite")
    if type(s) ~= "table" or rawget(s, "API") ~= 1
        or type(rawget(s, "Theme")) ~= "function" or type(rawget(s, "Report")) ~= "function" then
        return nil, "incompatible"
    end
    return s
end

local function fn(name)
    local f = S and rawget(S, name)
    if type(f) == "function" then return f end
end

function Suite.Following() return status == "following" end
function Suite.Status() return status end
function Suite.CanOpen() return fn("Open") ~= nil end
function Suite.Open()
    local f = fn("Open")
    if not f then return false end
    local ok, r = pcall(f)
    return ok and r == true
end

--------------------------------------------------------------------------------
-- The look: the override, the request
--------------------------------------------------------------------------------

function Suite.ValidOwn(v) return v == "clear" or v == "smoked" or v == "stock" end

-- The player's own choice while following ("clear" | "smoked" | "stock"), or nil.
function Suite.Own()
    if status ~= "following" then return nil end
    local t = GM.db and rawget(GM.db, "suiteOwn")
    local v = read(t, "skin")
    if Suite.ValidOwn(v) then return v end
end

-- The suite's tint we know, or nil.
function Suite.SuiteTint() return suiteLook.tint end

-- The look asked for: "clear" | "smoked" | "class" | "stock". Following: the
-- override, else the suite's tint, else (no Look, a tint we don't know) the
-- local skin. Not following: the local skin.
function Suite.Requested()
    local own = Suite.Own()
    if own then return own end
    if status == "following" and suiteLook.tint then return suiteLook.tint end
    return GM.db and GM.db.skin or "clear"
end

-- Set or clear ("suite") the override while following. False otherwise.
function Suite.SetOwn(v)
    if status ~= "following" then return false end
    if v ~= "suite" and not Suite.ValidOwn(v) then return false end
    local t = rawget(GM.db, "suiteOwn")
    if type(t) ~= "table" then t = {} end
    t.skin = v ~= "suite" and v or nil
    GM.db.suiteOwn = next(t) and t or nil
    Suite.Changed()
    return true
end

--------------------------------------------------------------------------------
-- Glass UI's numbers, checked whole
--------------------------------------------------------------------------------

local function unit(v) return type(v) == "number" and v == v and v >= 0 and v <= 1 end
local function colour(t, n)
    if type(t) ~= "table" then return false end
    for i = 1, n do
        if not unit(rawget(t, i)) then return false end
    end
    return true
end
Suite._colour = colour

-- A Body answer we can paint whole: a tint (or a class shade), a backing, and a
-- wash factor whose product with our material's wash is in range.
local function validBody(b)
    if type(b) ~= "table" then return false end
    local tint, shade, backing, wash = rawget(b, "tint"), rawget(b, "classShade"), rawget(b, "backing"), rawget(b, "wash")
    if tint ~= nil then
        if not colour(tint, 4) then return false end
    elseif not unit(shade) then
        return false
    end
    if not colour(backing, 4) then return false end
    if type(wash) ~= "number" or wash ~= wash or wash < 0 then return false end
    return unit(wash * GM.BaseWash())
end
Suite._validBody = validBody

-- Our own body for a tint (Skin.BODIES, in Body's shape).
local function ownBody(name)
    local b, c = GM.Skin.BODIES[name], GM.Skin.BACKING
    if not b then return nil end
    return { tint = b.tint, classShade = b.classShade, wash = b.wash, backing = { c[1], c[2], c[3], b.backing } }
end

-- The body for a tint name: Glass UI's while following and valid, else ours.
-- Plain values: { tint = {r,g,b,a} | nil, classShade = n | nil, wash = factor, backing = {r,g,b,a} }.
function Suite.Body(name)
    local f = status == "following" and fn("Body")
    if f then
        local ok, b = pcall(f, name)
        if ok and validBody(b) then
            local t, k = rawget(b, "tint"), rawget(b, "backing")
            return {
                tint = t and { t[1], t[2], t[3], t[4] } or nil,
                classShade = not t and rawget(b, "classShade") or nil,
                wash = rawget(b, "wash"),
                backing = { k[1], k[2], k[3], k[4] },
            }
        end
    end
    return ownBody(name)
end

-- The accent's name: the suite's when following and we know it, else gold.
function Suite.AccentName()
    if status == "following" and suiteLook.accent then return suiteLook.accent end
    return Suite.GOLD
end

-- The accent's { r, g, b }: Glass UI's for that name, else our copy of it.
function Suite.AccentColor()
    local name = Suite.AccentName()
    local f = status == "following" and fn("Accent")
    if f then
        local ok, c = pcall(f, name)
        if ok and colour(c, 3) then return { c[1], c[2], c[3] } end
    end
    local own = Suite.ACCENTS[name] or Suite.ACCENTS.gold
    return { own[1], own[2], own[3] }
end

--------------------------------------------------------------------------------
-- Report, changes, start
--------------------------------------------------------------------------------

-- What we show, for Glass UI's page: derived each time from the frozen
-- participation, the build and the applied look (plain values only).
function Suite.Report()
    if not S then return end
    local build = GM.GlassBuild() or {}
    local applied = GM.Skin.Applied and GM.Skin.Applied() or Suite.Requested()
    local own = Suite.Own()
    local state = {
        api = 1,
        minor = build.minor,
        look = { tint = applied ~= "stock" and applied or nil, accent = Suite.AccentName() },
        own = { tint = (own == "clear" or own == "smoked") and true or nil },
        options = function() return GM.Options.Open() end,
    }
    if applied == "stock" then
        state.declined = Suite.DECLINED
    elseif status == "following" then
        if build.failed then state.reason = build.failed else state.built = build.preset end
    end
    pcall(rawget(S, "Report"), Suite.ADDON, state)
end

-- Every change: repaint (Skin keeps the applied look through combat), the
-- picker's accent, the open options page, then report.
function Suite.Changed()
    if GM.Skin.Refresh then
        local ok, err = pcall(GM.Skin.Refresh)
        if not ok then API.Fail("suite repaint", err) end
    end
    if GM.Address and GM.Address.RepaintAccent then
        local ok, err = pcall(GM.Address.RepaintAccent)
        if not ok then API.Fail("suite accent", err) end
    end
    if GM.Options and GM.Options.Refresh then pcall(GM.Options.Refresh) end
    Suite.Report()
end

local function copyLook(look)
    local tint, accent = read(look, "tint"), read(look, "accent")
    suiteLook.tint = Suite.TINTS[tint] and tint or nil
    suiteLook.accent = Suite.ACCENTS[accent] and accent or nil
end

local function onLookChanged(_, look)
    copyLook(look)
    Suite.Changed()
end

-- Our ADDON_LOADED, after the settings (PLAYER_LOGIN if that failed): decide,
-- subscribe, pull the look, build the glass. Once per session.
function Suite.Start()
    if started then return end
    started = true
    local s, why = suiteAPI()
    local preset
    if s then
        S = s
        local ok, answer = pcall(rawget(s, "Theme"), Suite.ADDON)
        preset = ok and read(answer, "preset")
        status = type(preset) == "string" and "following" or "not-following"
    else
        status = why
    end
    if status == "following" then
        local look = fn("Look")
        if look then
            if EventRegistry and EventRegistry.RegisterCallback then
                EventRegistry:RegisterCallback(Suite.EVENT, onLookChanged, Suite)
            end
            -- Register first, then pull: nothing is replayed to a late follower.
            local ok, payload = pcall(look)
            if ok then copyLook(payload) end
        end
    end
    GM.BuildGlass(status == "following" and preset or "pearl")
    Suite.Report()
end

Suite._test = { suiteLook = suiteLook, copyLook = copyLook }
