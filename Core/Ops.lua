-- Core/Ops.lua: the one owner of every mail action this addon takes.
--
-- One run at a time (PR 3: Open All), one attempt at a time. Each attempt
-- records the fingerprint it acts on and the residual it expects, and is
-- confirmed only from the inbox (MAIL_SUCCESS carries no itemID, session 3):
-- the acted-on fingerprint's count fell by one AND its residual's count rose
-- by one, or, for a mail the take empties, the loaded count fell by one (it
-- was removed) instead. Anything else is still pending; 5 s without a confirmation stops the
-- run as uncertain, never a blind retry.
--
-- Open All has no remembered target: each dispatch takes the mail that a
-- fresh scan finds eligible now, so identical mails (twins) are fine here.
-- Remembered targets (the selection, a Return or Delete) are acted on only
-- when exactly one mail has their fingerprint.
--
-- Nothing is dispatched while a letter is open: Blizzard keeps the open
-- letter as a bare inbox index (InboxFrame.openMailID), re-read on every
-- MAIL_INBOX_UPDATE, and closing it may delete the mail at that index
-- (MailFrame.lua:146, 581). A mail removed above it would shift it. A letter
-- opened mid-run stops the run; the one action already sent can't be
-- recalled, the same window Blizzard's own Open All and shift-click leave.

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

-- "openall", "selected", "return", "delete", or nil.
function Ops.Kind() return run and run.kind end

-- A selected run's live targets: the selection, moved to each residual.
function Ops.Targets() return run and run.opts.only end

-- A letter open in OpenMailFrame (see the header).
function Ops.LetterOpen()
    local f = rawget(_G, "OpenMailFrame")
    return f ~= nil and f:IsShown() == true
end

-- The active run's counters, for the UI: { money, items, failed }.
function Ops.Stats() return run and run.stats end

local function now() return GetTime() end

-- Called with no arguments whenever a run starts or stops, so every control
-- can enable or disable itself (Open All, the selection bar, the rows).
local watchers = {}
function Ops.Watch(fn) watchers[#watchers + 1] = fn end
local function notify()
    for _, fn in ipairs(watchers) do
        local ok, err = pcall(fn)
        if not ok then API.Fail("ops watcher", err) end
    end
end

local function finish(reason)
    if not run then return end
    local r = run
    run = nil
    driver:Hide()
    if r.kind == "openall" or r.kind == "selected" then
        C_Mail.SetOpeningAll(false)
        local ok, tally = pcall(function() return Loot.Tally(Scan.Inbox(), Loot.Bags(), r.opts) end)
        r.tally = ok and tally or {}
        if not ok then API.Fail("ops tally", tally) end
    end
    r.stopReason = reason
    local loaded, total = GetInboxNumItems()
    r.more = (total or 0) > (loaded or 0)
    if r.onStop then
        local okStop, err = pcall(r.onStop, r)
        if not okStop then API.Fail("ops onStop", err) end
    end
    notify()
end

-- Stop the run, with why. Idempotent: the mailbox close can fire twice.
function Ops.Stop(reason) finish(reason or "stopped") end

local function start(kind, opts, onStop, onChange)
    if run or InputUtil.IsGamepadUIEnabled() or Ops.LetterOpen() then return false end
    run = { kind = kind, opts = opts, stats = { money = 0, items = 0, failed = 0 }, lastDispatch = -math.huge,
        onStop = onStop, onChange = onChange }
    if kind == "openall" or kind == "selected" then C_Mail.SetOpeningAll(true) end
    driver:Show()
    notify()
    return true
end

-- Start an Open All run. opts: { types = { ah, system, player }, keepFree };
-- onStop(run) gets { stats, stopReason, tally, more }; onChange() after each
-- confirmed step. False if a run is already active, a letter is open, or in
-- gamepad UI mode.
function Ops.OpenAll(opts, onStop, onChange)
    return start("openall", { types = opts.types, keepFree = opts.keepFree, failed = {} }, onStop, onChange)
end

-- Take from the selected mails only (a set of fingerprints, copied): no type
-- filter, COD and GM still left, keepFree kept. Each confirmed take moves its
-- target to the residual, onChange(from, to) (to nil: the mail was removed);
-- onStop's run.opts.only is what is left of the selection.
function Ops.OpenSelected(fps, opts, onStop, onChange)
    local only = {}
    for fp in pairs(fps) do only[fp] = true end
    return start("selected", { only = only, keepFree = opts.keepFree, failed = {} }, onStop, onChange)
end

-- Return or delete the one mail with this fingerprint: kind "return" (only
-- when Blizzard would return it: not InboxItemCanDelete) or "delete" (only
-- an empty mail it lets us delete). onStop(run): stopReason "done" once the
-- mail left the inbox.
function Ops.Act(kind, fp, onStop)
    if kind ~= "return" and kind ~= "delete" then return false end
    return start(kind, { target = fp }, onStop)
end

-- A scanned mail's row action: "return", "delete" (empty mail only) or nil.
-- Return never falls through to Delete.
function Ops.RowAction(m)
    if InboxItemCanDelete(m.index) then
        if m.money == 0 and m.cod == 0 and #m.items == 0 then return "delete" end
        return nil
    end
    return "return"
end

local function call(fn, ...)
    ours = true
    local ok, err = pcall(_G[fn], ...)
    ours = false
    if not ok then API.Fail("ops " .. fn, err) end
    return ok
end

-- A Return or Delete: the one current match, its rule checked again now.
local function dispatchAct(t, snap)
    if not snap.resolved then return end   -- wait: a mail still loading may be the target's twin
    local fp = run.opts.target
    if (Scan.Count(snap)[fp] or 0) ~= 1 then return finish("mail changed") end
    local m
    for _, mail in ipairs(snap.mails) do if mail.fp == fp then m = mail end end
    if Ops.RowAction(m) ~= run.kind then return finish("mail changed") end
    run.attempt = { fp = fp, kind = run.kind, mayVanish = true, before = 1, residualBefore = 0,
        loaded = snap.loaded, deadline = t + Ops.TIMEOUT }
    run.lastDispatch = t
    if not call(run.kind == "return" and "ReturnInboxItem" or "DeleteInboxItem", m.index) then finish("error") end
end

local function dispatch(t)
    if InputUtil.IsGamepadUIEnabled() then return finish("input mode changed") end
    if Ops.LetterOpen() then return finish("a letter was opened") end
    if C_Mail.IsCommandPending() or t - run.lastDispatch < Ops.MIN_DELAY then return end
    if run.bagWait and not run.bagSeen and t - run.bagWait < Ops.BAG_WAIT then return end
    run.bagWait = nil
    local snap, bags = Scan.Inbox(), Loot.Bags()
    if run.opts.target then return dispatchAct(t, snap) end
    local only = run.opts.only
    if only and snap.resolved then
        -- A target that is gone, or now has a twin, leaves the selection.
        local counts = Scan.Count(snap)
        for fp in pairs(only) do
            if counts[fp] ~= 1 then only[fp] = nil end
        end
    end
    local action = Loot.Next(snap, bags, run.opts)
    if not action then return finish("done") end
    local m, counts = action.mail, Scan.Count(snap)
    local residual, mayVanish = Scan.Residual(m, action.kind, action.slot)
    run.attempt = { fp = m.fp, kind = action.kind, itemID = action.itemID, money = m.money, residual = residual,
        mayVanish = mayVanish,
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
    local stayed = a.residual ~= nil and (counts[a.residual] or 0) == a.residualBefore + 1
    local removed = a.mayVanish and snap.loaded == a.loaded - 1
    if not (stayed or removed) then return end
    run.attempt = nil
    if a.kind == "return" or a.kind == "delete" then return finish("done") end
    local only = run.opts.only
    if only and only[a.fp] then
        only[a.fp] = nil
        if stayed then only[a.residual] = true end
    end
    if a.kind == "money" then
        run.stats.money = run.stats.money + a.money
    else
        run.stats.items = run.stats.items + 1
        run.bagWait = now()
    end
    if run.onChange then
        local ok, err = pcall(run.onChange, a.fp, stayed and a.residual or nil)
        if not ok then API.Fail("ops onChange", err) end
    end
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
            finish(a.kind .. " failed")
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

-- A letter the player opens mid-run stops the run before its next dispatch.
-- Called at PLAYER_LOGIN (OpenMailFrame is Blizzard_MailFrame's).
local hooked = false
function Ops.Start()
    local f = rawget(_G, "OpenMailFrame")
    if not f or hooked then return end
    hooked = true
    f:HookScript("OnShow", function() if run then finish("a letter was opened") end end)
end

GM._test = GM._test or {}
GM._test.ops = { run = function() return run end, driver = driver }
