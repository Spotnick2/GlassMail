-- Bag.lua: I4, every item in the loaded inbox in one grid beside it (PLAN.md,
-- "I4: mail bag grid", "The grid PR in detail").
--
-- Our "Items" button on the inbox's title bar toggles our panel (a child of
-- InboxFrame, so it goes with the inbox tab and the mailbox), anchored right
-- of MailFrame. Each grid button is one itemID, merged across mails: its icon,
-- the total count, and in a tooltip how many mails hold it (and how many of
-- those are COD, left to the player). A click takes every copy: an Ops run of
-- kind "items" (Core/Ops.lua), stopped by the footer's Stop or by a click on
-- that item again.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Glass, Skin, Scan, Ops = GM.Glass, GM.Skin, GM.Scan, GM.Ops
local Bag = {}
GM.Bag = Bag

local COLS, ROWS, SIZE, GAP = 6, 9, 36, 4
local PAD, TITLE_H, FOOT_H = 10, 30, 34
local ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local GLOW = "Interface\\Buttons\\CheckButtonHilight"
Bag.COLS, Bag.ROWS = COLS, ROWS

local toggle, panel, ui
local entries, offset = {}, 0   -- offset in rows

-- Every non-currency attachment in the loaded inbox, merged by itemID, in
-- order of first appearance: { id, count, mails, cod }. cod counts the mails
-- Open All and a click leave alone (COD, GM).
function Bag.Entries(snap)
    local out, byID = {}, {}
    for _, m in ipairs(snap.mails) do
        local inMail = {}
        for _, it in ipairs(m.items) do
            if not it.isCurrency and it.itemID then
                local e = byID[it.itemID]
                if not e then
                    e = { id = it.itemID, count = 0, mails = 0, cod = 0 }
                    byID[it.itemID] = e
                    out[#out + 1] = e
                end
                e.count = e.count + (it.count or 1)
                if not inMail[it.itemID] then
                    inMail[it.itemID] = true
                    e.mails = e.mails + 1
                    if (m.cod or 0) > 0 or m.isGM then e.cod = e.cod + 1 end
                end
            end
        end
    end
    return out
end

local function idle()
    return not (Ops.Running() or Ops.LetterOpen() or API.InCombat() or InputUtil.IsGamepadUIEnabled())
end

local function maxOffset() return math.max(0, math.ceil(#entries / COLS) - ROWS) end

local function itemName(id)
    local name = C_Item.GetItemNameByID(id)
    if API.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    return name
end

-- The tooltip of a button's item: what a click on it takes.
local function showTip(b)
    local e = b.entry
    if not e then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(e.id)
    GameTooltip:AddLine("in " .. e.mails .. (e.mails == 1 and " mail" or " mails"), 1, 1, 1)
    if e.cod > 0 then GameTooltip:AddLine(e.cod .. " COD, left to you", 1, 0.7, 0.3) end
    GameTooltip:Show()
end

-- Every pooled button repainted whole: nothing of its last item stays, its
-- tooltip included (a scroll or an inbox update rebinds a hovered button).
local function paint()
    local active = Ops.Items()
    local free = idle()
    for i, b in ipairs(ui.buttons) do
        local e = entries[offset * COLS + i]
        b.entry = e
        if e then
            b.icon:SetTexture(C_Item.GetItemIconByID(e.id))
            b.count:SetText(e.count > 1 and e.count or "")
            local mine = active ~= nil and active[e.id] == true
            b.glow:SetShown(mine)
            b:SetEnabled(free or mine)
            b.icon:SetDesaturated(not (free or mine))
            b:Show()
        else
            b.icon:SetTexture(nil)
            b.count:SetText("")
            b:Hide()
        end
        if GameTooltip:IsOwned(b) then
            if e then showTip(b) else GameTooltip:Hide() end
        end
    end
    if active then
        local id = next(active)
        ui.footer:SetText("Taking " .. (itemName(id) or "items"))
        ui.stop:Show()
    else
        ui.footer:SetText(#entries == 0 and "No items in the mailbox" or "Click an item to take every copy")
        ui.stop:Hide()
    end
end

function Bag.Refresh()
    if not (panel and panel:IsVisible()) then return end
    entries = Bag.Entries(Scan.Inbox())
    offset = math.max(0, math.min(offset, maxOffset()))
    paint()
end

local function setOffset(n)
    n = math.max(0, math.min(math.floor(n), maxOffset()))
    if n == offset then return end
    offset = n
    paint()
end

local function onStop(r) GM.OpenAll.Summary(r) end

local function click(b)
    local e = b.entry
    if not e then return end
    local active = Ops.Items()
    if active then
        if active[e.id] then Ops.Stop("stopped") end
        return
    end
    if not idle() then return end
    Ops.TakeItems({ [e.id] = true }, { keepFree = GM.db.keepFree }, onStop, Bag.Refresh)
end

local function newButton(parent, i)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIZE, SIZE)
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + col * (SIZE + GAP), -(TITLE_H + row * (SIZE + GAP)))
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.count = Glass.Font(b, 11, "RIGHT")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture(GLOW)
    b.glow:SetBlendMode("ADD")
    b.glow:SetAllPoints(b)
    b.glow:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", click)
    b:SetScript("OnEnter", showTip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function build()
    local mail, inbox = rawget(_G, "MailFrame"), rawget(_G, "InboxFrame")
    panel = CreateFrame("Frame", nil, inbox)
    panel:SetWidth(PAD * 2 + COLS * SIZE + (COLS - 1) * GAP)
    panel:SetPoint("TOPLEFT", mail, "TOPRIGHT", 2, 0)
    panel:SetPoint("BOTTOMLEFT", mail, "BOTTOMRIGHT", 2, 0)
    panel:EnableMouse(true)
    panel:Hide()
    Skin.AddWindow(panel, true)
    ui = { buttons = {} }
    local content = CreateFrame("Frame", nil, panel)
    content:SetAllPoints(panel)
    content:SetFrameLevel(Glass.ContentLevel(panel))
    local title = Glass.Font(content, 14, "LEFT")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -8)
    title:SetText("Items in the mailbox")
    for i = 1, COLS * ROWS do ui.buttons[i] = newButton(content, i) end
    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta) setOffset(offset - delta) end)
    ui.content = content
    ui.footer = Glass.Font(content, 12, "LEFT")
    ui.footer:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", PAD, 12)
    ui.stop = API.Button(content, "Stop", 60, function() if Ops.Items() then Ops.Stop("stopped") end end)
    ui.stop:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -PAD, 8)
    ui.stop:Hide()
    panel:SetScript("OnShow", Bag.Refresh)
end

-- Shown or not stays for the session: the panel is InboxFrame's child, so it
-- hides and comes back with the inbox.
function Bag.Toggle()
    if not panel then build() end
    panel:SetShown(not panel:IsShown())
end

local function safeRefresh()
    local ok, err = pcall(Bag.Refresh)
    if not ok then API.Fail("bag refresh", err) end
end

-- Called at PLAYER_LOGIN (InboxFrame is Blizzard_MailFrame's).
function Bag.Start()
    local inbox = rawget(_G, "InboxFrame")
    if toggle or not (inbox and rawget(_G, "MailFrame")) then return end
    toggle = CreateFrame("Button", nil, inbox)
    toggle:SetSize(20, 20)
    toggle:SetPoint("TOPRIGHT", inbox, "TOPRIGHT", -50, -2)
    toggle:SetNormalTexture(ICON)
    toggle:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    toggle:SetScript("OnClick", Bag.Toggle)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Items in the mailbox")
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Bag.toggle = toggle
    if inbox.Update then hooksecurefunc(inbox, "Update", safeRefresh) end
    Ops.Watch(Bag.Refresh)
    local letter = rawget(_G, "OpenMailFrame")
    if letter then
        letter:HookScript("OnShow", safeRefresh)
        letter:HookScript("OnHide", safeRefresh)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    API.NoteCombat(event)
    safeRefresh()
end)
API.RegisterEvents(events, { "MAIL_INBOX_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "INPUT_DEVICE_INTERFACE_TRANSITION" })

GM._test = GM._test or {}
GM._test.bag = {
    panel = function() return panel end, ui = function() return ui end,
    entries = function() return entries end, offset = function() return offset end, setOffset = setOffset,
}
