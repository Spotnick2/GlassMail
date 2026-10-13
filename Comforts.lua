-- Comforts.lua: X3, three small comforts.
--
-- - The gold collected this visit, one line when the mailbox closes. Only the
--   money Core/Ops.lua confirmed taken counts: money taken by hand from an
--   open letter isn't (GetMoney can be secret, and a post-hook confirms
--   nothing).
-- - Trades blocked while the mailbox is open, through the client's own
--   blockTrades CVar (Settings > Social), as Postal does. We only ever undo a
--   block we made: a change we didn't make (the player, another addon) ends
--   our claim, and an "off" made during a visit is kept until it closes.
--   Nothing is written in combat; a pending change waits for it to end. A
--   per-character flag restores the CVar at the next login after a session
--   that ended while we held it (best effort).
-- - An alert when the latest senders change while you are away from the
--   mailbox. UPDATE_PENDING_MAIL comes in pairs, the first at login without
--   names (FOREVER-PROBE); a sender list isn't an arrival ID, so a second mail
--   from the same senders isn't announced.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Ops = GM.Ops
local say = API.Print
local Comforts = {}
GM.Comforts = Comforts

local MAILBOX = 17           -- Enum.PlayerInteractionType.MailInfo
local CVAR = "blockTrades"

local open = false           -- the mailbox, from the interaction events

-- Gold collected ------------------------------------------------------------

local function rake()
    local c = Ops.TakeVisitMoney()
    if c > 0 then say("Collected " .. C_CurrencyInfo.GetCoinTextureString(c) .. " this visit.") end
end

-- Trade block ---------------------------------------------------------------

local owned = false          -- the CVar's "1" is ours to undo
local yielded = false        -- someone else turned it off during this visit
local ours = false           -- true only around our own write (CVAR_UPDATE is synchronous)
local last                   -- the value last seen, to tell a change from any other CVAR_UPDATE
local warned = false         -- a failed unblock was said in chat (once, until one works)
local UNBLOCK_HELP = "Turn off Settings > Social > Block Trades yourself."

local function value()
    local v = GetCVar(CVAR)
    if API.IsSecret(v) then return nil end
    return v
end

-- Any change of the claim starts the failed-unblock warning afresh.
local function claim(on)
    owned = on
    warned = false
    GM.charDB.tradeBlocked = on or nil
end

-- True only when the CVar now reads v: SetCVar can refuse by returning
-- false, not only by throwing. The claim changes only on a write that held.
local function write(v)
    ours = true
    local ok, err = pcall(SetCVar, CVAR, v)
    ours = false
    last = value()
    if not ok then
        API.Fail("trade block", err)
    elseif last ~= v then
        API.Fail("trade block", "blockTrades refused " .. v)
    end
    return ok and last == v
end

-- One rule, re-run on every change: blocked while the mailbox is open and the
-- setting is on, unless someone else turned it off this visit.
local function sync()
    if API.InCombat() then return end
    local want = GM.db.tradeBlock and open and not yielded
    if want and not owned and value() == "0" then
        if write("1") then claim(true) end
    elseif not want and owned then
        -- A block left on by mistake is hard to trace in game: never fail silently.
        if write("0") then
            claim(false)
        elseif not warned then
            warned = true
            say("|cffff6060couldn't unblock trades|r (it retries). " .. UNBLOCK_HELP)
        end
    end
end
Comforts.Sync = sync

-- For /gmail tradeblock: who blocks trades right now.
function Comforts.TradeStatus()
    if owned and open then return "trades are blocked by GlassMail until the mailbox closes" end
    if owned then return "trades are still blocked by GlassMail: unblocking failed (it retries). " .. UNBLOCK_HELP end
    if value() == "1" then return "trades are blocked by the game's Block Trades setting, not by GlassMail" end
    return "trades aren't blocked"
end

local function onCVar()
    if ours then return end
    local v = value()
    if v == last then return end   -- another CVar changed
    last = v
    if v ~= "1" then
        if owned then claim(false) end
        if open then yielded = true end
    end
end

-- New-mail alert ------------------------------------------------------------

local announced              -- the sender list last announced (or seen at the mailbox)

local function senders()
    local list, got = {}, { GetLatestThreeSenders() }
    for i = 1, 3 do
        local name = got[i]
        if not API.IsSecret(name) and type(name) == "string" and name ~= "" then list[#list + 1] = name end
    end
    return list
end

local function onPendingMail()
    local has = HasNewMail()
    if API.IsSecret(has) or not has then
        announced = nil
        return
    end
    local list = senders()
    if #list == 0 then return end   -- the first of the login pair: the names come next
    local key = table.concat(list, "\n")
    if key == announced then return end
    announced = key
    if open or not GM.db.newMailAlert then return end
    say("New mail from " .. table.concat(list, ", ") .. ".")
end

-- Events --------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1)
    API.NoteCombat(event)
    if not GM.db then return end   -- the settings are read at ADDON_LOADED
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if arg1 ~= MAILBOX then return end
        open = true
        Ops.TakeVisitMoney()   -- a new visit starts at 0
        sync()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if arg1 ~= MAILBOX then return end
        open, yielded = false, false
        rake()
        sync()
    elseif event == "PLAYER_LEAVING_WORLD" then
        open, yielded = false, false
        sync()
    elseif event == "PLAYER_REGEN_ENABLED" then
        sync()
    elseif event == "CVAR_UPDATE" then
        onCVar()
    elseif event == "UPDATE_PENDING_MAIL" then
        onPendingMail()
    end
end)

-- Called once at PLAYER_LOGIN by GlassMail.lua (the saved flag is readable by then).
function Comforts.Start()
    last = value()
    -- The last session ended while we held the block: undo it (sync, out of combat).
    local leftover = GM.charDB.tradeBlocked == true
    if leftover then owned = true end
    sync()
    if leftover and not owned then say("unblocked trades, left blocked when the game last closed at a mailbox.") end
end
-- Registered at load: the login UPDATE_PENDING_MAIL pair may come before PLAYER_LOGIN.
API.RegisterEvents(events, { "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "PLAYER_LEAVING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "CVAR_UPDATE", "UPDATE_PENDING_MAIL" })

GM._test = GM._test or {}
GM._test.comforts = { owned = function() return owned end }
