-- Core/Ops.lua: the one owner of every mail action this addon takes.
--
-- One run at a time (PR 3: Open All), one attempt at a time. Each attempt
-- records the fingerprint it acts on and the residual it expects, and is
-- confirmed only from the inbox (MAIL_SUCCESS carries no itemID, session 3):
-- the acted-on fingerprint's count fell by one AND its residual's count rose
-- by one, or, for a mail that should be gone, the loaded count fell by one
-- too. Anything else is still pending; 5 s without a confirmation stops the
-- run as uncertain, never a blind retry.
--
-- Open All has no remembered target: each dispatch takes the mail that a
-- fresh scan finds eligible now, so identical mails (twins) are fine here.
-- Remembered targets (PR 4: selection, Return) will need a unique match.

GlassMailbox = GlassMailbox or {}
local GM = GlassMailbox
local API = GM.API
local Scan, Loot = GM.Scan, GM.Loot
local Ops = {}
GM.Ops = Ops

Ops.MIN_DELAY = 0.15   -- between commands, as Blizzard's Open All (OPEN_ALL_MAIL_MIN_DELAY)
Ops.TIMEOUT = 5        -- an attempt not confirmed by then: uncertain
Ops.BAG_WAIT = 1       -- after an item, wait for the bags to update, at most this long
local MAILBOX = 17     -- Enum.PlayerInteractionType.MailInfo (session 1)

local run              -- the active run, or nil
local ours = false     -- true only around our own mail call
local driver = CreateFrame("Frame")
driver:Hide()

function Ops.Running() return run ~= nil end

-- The active run's counters, for the UI: { money, items, failed }.
function Ops.Stats() return run and run.stats end

local function now() return GetTime() end

local function finish(reason)
    if not run then return end
    local r = run
    run = nil
    driver:Hide()
    C_Mail.SetOpeningAll(false)
    r.stopReason = reason
    local ok, tally = pcall(function() return Loot.Tally(Scan.Inbox(), Loot.Bags(), r.opts) end)
    r.tally = ok and tally or {}
    if not ok then API.Fail("ops tally", tally) end
    local loaded, total = GetInboxNumItems()
    r.more = (total or 0) > (loaded or 0)
    if r.onStop then
        local okStop, err = pcall(r.onStop, r)
        if not okStop then API.Fail("ops onStop", err) end
    end
end

-- Stop the run, with why. Idempotent: the mailbox close can fire twice.
function Ops.Stop(reason) finish(reason or "stopped") end

-- Start an Open All run. opts: { types = { ah, system, player }, keepFree };
-- onStop(run) gets { stats, stopReason, tally, more }; onChange() after each
-- confirmed step. False if a run is already active or in gamepad UI mode.
function Ops.OpenAll(opts, onStop, onChange)
    if run or InputUtil.IsGamepadUIEnabled() then return false end
    run = { opts = { types = opts.types, keepFree = opts.keepFree, failed = {} },
        stats = { money = 0, items = 0, failed = 0 }, lastDispatch = -math.huge,
        onStop = onStop, onChange = onChange }
    C_Mail.SetOpeningAll(true)
    driver:Show()
    return true
end

local function call(fn, ...)
    ours = true
    local ok, err = pcall(_G[fn], ...)
    ours = false
    if not ok then API.Fail("ops " .. fn, err) end
    return ok
end

local function dispatch(t)
    if InputUtil.IsGamepadUIEnabled() then return finish("input mode changed") end
    if C_Mail.IsCommandPending() or t - run.lastDispatch < Ops.MIN_DELAY then return end
    if run.bagWait and not run.bagSeen and t - run.bagWait < Ops.BAG_WAIT then return end
    run.bagWait = nil
    local snap, bags = Scan.Inbox(), Loot.Bags()
    local action = Loot.Next(snap, bags, run.opts)
    if not action then return finish("done") end
    local m, counts = action.mail, Scan.Count(snap)
    local residual = Scan.Residual(m, action.kind, action.slot)
    run.attempt = { fp = m.fp, kind = action.kind, itemID = action.itemID, money = m.money, residual = residual,
        before = counts[m.fp] or 0, residualBefore = counts[residual] or 0, loaded = snap.loaded,
        deadline = t + Ops.TIMEOUT }
    run.bagSeen = false
    run.lastDispatch = t
    local ok
    if action.kind == "money" then ok = call("TakeInboxMoney", m.index)
    else ok = call("TakeInboxItem", m.index, action.slot) end
    if not ok then finish("error") end
end

-- Confirm the attempt from the inbox, or leave it pending.
local function resolve()
    local a = run and run.attempt
    if not a then return end
    local snap = Scan.Inbox()
    if not snap.resolved then return end   -- a mail still loading confirms nothing
    local counts = Scan.Count(snap)
    if (counts[a.fp] or 0) ~= a.before - 1 then return end
    if a.residual == Scan.GONE then
        if snap.loaded ~= a.loaded - 1 then return end
    elseif (counts[a.residual] or 0) ~= a.residualBefore + 1 then
        return
    end
    run.attempt = nil
    if a.kind == "money" then
        run.stats.money = run.stats.money + a.money
    else
        run.stats.items = run.stats.items + 1
        run.bagWait = now()
    end
    if run.onChange then pcall(run.onChange) end
end

driver:SetScript("OnUpdate", function()
    if not run then return driver:Hide() end
    local t = now()
    local a = run.attempt
    if a then
        if t > a.deadline then finish("uncertain") end
        return
    end
    local ok, err = pcall(dispatch, t)
    if not ok then
        API.Fail("ops dispatch", err)
        finish("error")
    end
end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1)
    if not run then return end
    if event == "MAIL_INBOX_UPDATE" then
        local ok, err = pcall(resolve)
        if not ok then API.Fail("ops resolve", err); finish("error") end
    elseif event == "MAIL_FAILED" then
        local a = run.attempt
        if not a then return end
        run.attempt = nil
        if a.kind == "item" and arg1 ~= nil then
            -- That item is skipped for the rest of the run, as Blizzard's Open All does.
            run.opts.failed[arg1] = true
            run.stats.failed = run.stats.failed + 1
        elseif a.kind == "item" then
            finish("uncertain")
        else
            finish("money failed")
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        run.bagSeen = true
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if arg1 == MAILBOX then finish("mailbox closed") end
    elseif event == "PLAYER_REGEN_DISABLED" then
        finish("combat")
    elseif event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        finish("input mode changed")
    end
end)
API.RegisterEvents(events, { "MAIL_INBOX_UPDATE", "MAIL_FAILED", "BAG_UPDATE_DELAYED",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "PLAYER_REGEN_DISABLED", "INPUT_DEVICE_INTERFACE_TRANSITION" })

-- Any mail action that isn't ours, while a run is active, ends the run: the
-- player, Blizzard's own Open All, or another addon now owns the inbox.
for _, fn in ipairs({ "TakeInboxItem", "TakeInboxMoney", "AutoLootMailItem", "ReturnInboxItem", "DeleteInboxItem" }) do
    if type(rawget(_G, fn)) == "function" then
        hooksecurefunc(fn, function()
            if run and not ours then finish("another mail action ran") end
        end)
    end
end

GM._test = GM._test or {}
GM._test.ops = { run = function() return run end, driver = driver }
