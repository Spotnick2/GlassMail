-- OpenAll.lua: I1, Open All with filters, in place of Blizzard's button.
--
-- Left-click starts or stops a Core/Ops run; right-click opens the filters
-- (Auction House, system mail, player mail, and how many general bag slots
-- to keep free). The stock InboxFrame.OpenAllMail is hidden in mouse mode,
-- on every show (it comes back on every mailbox open and /reload, session 3).
-- In gamepad UI mode, Blizzard hides it itself and drives it from a footer
-- binding: we leave it alone there and don't offer ours. Reasoned, not
-- measured (no gamepad); a mode change stops our run (Core/Ops.lua).

GlassMailbox = GlassMailbox or {}
local GM = GlassMailbox
local API = GM.API
local Scan, Loot, Ops = GM.Scan, GM.Loot, GM.Ops
local say = API.Print
local OpenAll = {}
GM.OpenAll = OpenAll

local button, count   -- ours: the button and the message count

local function gamepad() return InputUtil.IsGamepadUIEnabled() == true end

local function stock()
    local inbox = rawget(_G, "InboxFrame")
    return inbox and inbox.OpenAllMail
end

local function opts()
    local db = GM.db
    return { types = { ah = db.openAH, system = db.openSystem, player = db.openPlayer }, keepFree = db.keepFree }
end

local function money(c) return C_CurrencyInfo.GetCoinTextureString(c) end

-- "Open All", or "Stop (n)" with the mails still offering something.
local function refresh()
    if not button then return end
    if Ops.Running() then
        local ok, t = pcall(Loot.Tally, Scan.Inbox(), Loot.Bags(), opts())
        button:SetText("Stop (" .. (ok and t.left or "?") .. ")")
        button:Enable()
    else
        button:SetText("Open All")
        local loaded = GetInboxNumItems()
        button:SetEnabled((loaded or 0) > 0 and not InCombatLockdown())
    end
end

-- The message count: "5 messages", or "5 of 120 messages" past the loaded window.
local function refreshCount()
    if not count then return end
    local loaded, total = GetInboxNumItems()
    loaded, total = loaded or 0, total or loaded or 0
    local noun = total == 1 and "message" or "messages"
    if total > loaded then count:SetText(loaded .. " of " .. total .. " " .. noun)
    else count:SetText(total .. " " .. noun) end
end

-- Mouse mode: ours shown, Blizzard's hidden. Gamepad mode: Blizzard's own flow.
local function applyMode()
    if not button then return end
    button:SetShown(not gamepad())
    local b = stock()
    if b and not gamepad() and b:IsShown() then b:Hide() end
    refresh()
end

-- One line at the end of a run.
local function summary(r)
    local parts = {}
    if r.stats.items > 0 then parts[#parts + 1] = r.stats.items .. (r.stats.items == 1 and " item" or " items") end
    if r.stats.money > 0 then parts[#parts + 1] = money(r.stats.money) end
    local line = #parts > 0 and ("took " .. table.concat(parts, " and ")) or "nothing taken"
    local t, left = r.tally or {}, {}
    if (t.cod or 0) > 0 then left[#left + 1] = t.cod .. " COD" end
    if (t.full or 0) > 0 then left[#left + 1] = t.full .. " with no bag room" end
    if (t.loading or 0) > 0 then left[#left + 1] = t.loading .. " still loading" end
    if r.stats.failed > 0 then left[#left + 1] = r.stats.failed .. " failed" end
    if #left > 0 then line = line .. "; left " .. table.concat(left, ", ") end
    if r.stopReason ~= "done" then line = line .. " (stopped: " .. r.stopReason .. ")" end
    if r.more then line = line .. ". More mail waits on the server: reopen the mailbox." end
    say(line)
end

local function onStop(r)
    summary(r)
    refresh()
end

function OpenAll.Toggle()
    if Ops.Running() then return Ops.Stop("stopped") end
    if gamepad() or InCombatLockdown() then return end
    -- The stock button must be hidden BEFORE SetOpeningAll(true): hiding it
    -- calls SetOpeningAll(false) (session 2).
    local b = stock()
    if b and b:IsShown() then b:Hide() end
    if Ops.OpenAll(opts(), onStop, refresh) then refresh() end
end

local TYPES = { { "openAH", "Auction House" }, { "openSystem", "System mail" }, { "openPlayer", "Player mail" } }

local function menu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local ok, err = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
        root:CreateTitle("Open All takes")
        for _, t in ipairs(TYPES) do
            root:CreateCheckbox(t[2], function() return GM.db[t[1]] end,
                function() GM.Settings.SetOpenFilter(t[1], not GM.db[t[1]]) end)
        end
        root:CreateTitle("Keep bag slots free")
        for _, n in ipairs(Loot.KEEP_FREE) do
            root:CreateRadio(tostring(n), function(v) return GM.db.keepFree == v end,
                function(v) GM.Settings.SetKeepFree(v) end, n)
        end
    end)
    if not ok then API.Fail("open all menu", err) end
end

function OpenAll.Start()
    local inbox = rawget(_G, "InboxFrame")
    if not inbox or button then return end
    button = API.Button(inbox, "Open All", 120, function(_, mouse)
        if mouse == "RightButton" then menu(button) else OpenAll.Toggle() end
    end)
    -- A plain button: one edge per mouse button (the porting guide's
    -- both-edges rule is for secure action buttons).
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetPoint("CENTER", inbox, "BOTTOM", 0, 26)   -- the stock button's place (MailFrame.xml:446)
    count = inbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("TOPRIGHT", inbox, "TOPRIGHT", -16, -40)
    local b = stock()
    if b then
        b:HookScript("OnShow", function(self)
            if gamepad() then return end
            self:Hide()
            -- Hiding called SetOpeningAll(false): put ours back if a run is on.
            if Ops.Running() then C_Mail.SetOpeningAll(true) end
        end)
    end
    if inbox.Update then hooksecurefunc(inbox, "Update", function() refreshCount(); refresh() end) end
    local events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event)
        if event == "MAIL_SHOW" or event == "INPUT_DEVICE_INTERFACE_TRANSITION" then applyMode() end
        if event == "MAIL_INBOX_UPDATE" then refreshCount() end
        refresh()
    end)
    API.RegisterEvents(events, { "MAIL_SHOW", "MAIL_INBOX_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "INPUT_DEVICE_INTERFACE_TRANSITION" })
    applyMode()
    refreshCount()
end

GM._test = GM._test or {}
GM._test.openAll = { button = function() return button end, count = function() return count end }
