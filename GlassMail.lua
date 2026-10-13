-- GlassMail.lua: bootstrap, saved settings, the settings helpers and the
-- /gmail command. Loads last: every module is defined by now.

local ADDON = ...
GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local say = API.Print

-- Account-wide (GlassMailDB): settings, the same on every character.
-- Per character (GlassMailCharDB): tradeBlocked, set while our trade block
-- holds the CVar (Comforts.lua).
local DEFAULTS = {
    skin = "clear",   -- the mail windows' look: "clear" or "smoked" glass, or "stock" (Blizzard's own art)
    -- Open All (I1): which mail it takes, and the general bag slots it keeps free.
    openAH = true, openSystem = true, openPlayer = true,
    keepFree = 0,     -- one of GM.Loot.KEEP_FREE
    -- X3: trades blocked while the mailbox is open, a chat line when new mail comes.
    tradeBlock = true, newMailAlert = true,
}
GM.DEFAULTS = DEFAULTS

-- Only what the player SET is saved: everything else falls through to
-- DEFAULTS, so a changed default reaches everyone. Saved keys equal to the
-- default are dropped. Nothing may REQUIRE a value to have survived
-- (GlassChat's rule).
local function validKeepFree(n)
    for _, v in ipairs(GM.Loot.KEEP_FREE) do if v == n then return true end end
    return false
end

local function ensureDefaults()
    if type(GlassMailDB) ~= "table" then GlassMailDB = {} end
    local db = GlassMailDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == v then db[k] = nil end
    end
    -- A skin this version doesn't know falls back to the default.
    if db.skin ~= nil and not GM.Skin.IsValid(db.skin) then db.skin = nil end
    if db.keepFree ~= nil and not validKeepFree(db.keepFree) then db.keepFree = nil end
    db.glass = nil   -- M0's on/off switch (dev builds only), replaced by skin
    setmetatable(db, { __index = DEFAULTS })
    if type(GlassMailCharDB) ~= "table" then GlassMailCharDB = {} end
    return db, GlassMailCharDB
end

-- Every setting goes through here: /gmail and the options page.
local Settings = {}
GM.Settings = Settings

-- False for a name that isn't a skin; the setting is left as it was.
function Settings.SetSkin(name)
    if not GM.Skin.IsValid(name) then return false end
    GM.db.skin = name
    GM.Skin.Refresh()
    return true
end

-- Open All's mail types: openAH, openSystem, openPlayer.
local FILTERS = { openAH = true, openSystem = true, openPlayer = true }
function Settings.SetOpenFilter(key, on)
    if not FILTERS[key] then return false end
    GM.db[key] = on == true
    return true
end

-- False unless n is one of the offered reserves (0, 2, 5, 10).
function Settings.SetKeepFree(n)
    if not validKeepFree(n) then return false end
    GM.db.keepFree = n
    return true
end

function Settings.SetTradeBlock(on)
    GM.db.tradeBlock = on == true
    GM.Comforts.Sync()
    return true
end

function Settings.SetNewMailAlert(on)
    GM.db.newMailAlert = on == true
    return true
end

-- A dev build, by its version: "dev" from the deploy script, or the
-- packager's token left unreplaced (matched as a pattern, never written whole:
-- the packager would replace it here too). Unreadable is NOT dev.
function GM.IsDev()
    local v = API.AddOnVersion(ADDON or "GlassMail")
    return v ~= nil and (v == "dev" or v:find("@project%-version@") ~= nil)
end

function GM.VersionText()
    local v = API.AddOnVersion(ADDON or "GlassMail")
    if v == nil or v == "" or GM.IsDev() then return "dev" end
    return v
end

local function failures()
    local any = false
    for key, err in pairs(GM.failures) do
        any = true
        say(key .. ": " .. err)
    end
    for _, line in ipairs(GM.eventFailures) do
        any = true
        say("event " .. line)
    end
    if not any then say("no failures recorded") end
end

-- The command list: /gmail help prints it, the options page can show it.
local function helpLines()
    return {
        "/gmail skin clear/smoked/stock - the mailbox's look (" .. GM.db.skin .. ")",
        "/gmail tradeblock on/off - block trades while the mailbox is open (" .. (GM.db.tradeBlock and "on" or "off") .. ")",
        "/gmail alert on/off - a chat line when new mail comes (" .. (GM.db.newMailAlert and "on" or "off") .. ")",
        "/gmail options - open the options page",
        "/gmail failures - what failed to build or register",
        "/gmail version - client build vs the measured one",
    }
end
GM.HelpLines = helpLines

-- /gmail glass on/off, M0's command: clear glass or Blizzard's own art.
local GLASS_ALIAS = { on = "clear", off = "stock" }

local function setSkin(name)
    if Settings.SetSkin(name) then
        say("skin " .. name)
    else
        say("/gmail skin " .. table.concat(GM.Skin.NAMES, "/"))
    end
end

local ONOFF = { on = true, off = false }

local function slash(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "skin" then
        setSkin(arg)
    elseif cmd == "glass" then
        if GLASS_ALIAS[arg] then setSkin(GLASS_ALIAS[arg]) else say("/gmail glass on/off") end
    elseif cmd == "tradeblock" then
        if ONOFF[arg] == nil then
            return say("trade block " .. (GM.db.tradeBlock and "on" or "off") .. ": " .. GM.Comforts.TradeStatus()
                .. ". /gmail tradeblock on/off")
        end
        Settings.SetTradeBlock(ONOFF[arg])
        say("trade block " .. arg)
    elseif cmd == "alert" then
        if ONOFF[arg] == nil then return say("/gmail alert on/off") end
        Settings.SetNewMailAlert(ONOFF[arg])
        say("new-mail alert " .. arg)
    elseif cmd == "options" then
        if not GM.Options.Open() then say("Esc > Options > AddOns > Glass Mail") end
    elseif cmd == "failures" then
        failures()
    elseif cmd == "version" then
        say("version " .. GM.VersionText() .. ", client " .. API.ClientBuild()
            .. ", measured on " .. GM.MEASURED_ON_BUILD)
    else
        for _, line in ipairs(helpLines()) do say(line) end
    end
end

SLASH_GLASSMAIL1 = "/gmail"
SLASH_GLASSMAIL2 = "/glassmail"
SlashCmdList.GLASSMAIL = slash

local function start(key, fn)
    local ok, err = pcall(fn)
    if not ok then API.Fail(key, err) end
end

local boot = CreateFrame("Frame")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            GM.db, GM.charDB = ensureDefaults()
        elseif arg1 == "Blizzard_MailFrame" and GM.db then
            start("skin", GM.Skin.Start)
        end
    elseif event == "PLAYER_LOGIN" then
        -- SavedVariables are read here at the latest (porting guide: not at file scope).
        if not GM.db then GM.db, GM.charDB = ensureDefaults() end
        start("options", GM.Options.Register)
        start("skin", GM.Skin.Start)
        start("ops", GM.Ops.Start)
        start("open all", GM.OpenAll.Start)
        start("inbox", GM.Inbox.Start)
        start("comforts", GM.Comforts.Start)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- arg1 = isInitialLogin. The build warning asks the developer to
        -- re-measure; a player can't act on it, and /reload never repeats it.
        if arg1 and GM.IsDev() and API.ClientBuild() ~= GM.MEASURED_ON_BUILD then
            say("client build " .. API.ClientBuild() .. " differs from the one this addon was measured on ("
                .. GM.MEASURED_ON_BUILD .. "). Things may misbehave until it is re-checked.")
        end
    end
end)
API.RegisterEvents(boot, { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" })

GM._test = GM._test or {}
GM._test.ensureDefaults = ensureDefaults
GM._test.DEFAULTS = DEFAULTS
