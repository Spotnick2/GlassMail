-- Address.lua: S1, the address book on the send tab (PLAN.md, "S1: the address
-- book picker", "S1: the last recipient", "The address PR in detail", "The
-- searchable picker").
--
-- - The picker: our button right of the To box opens our panel: a search box
--   (focused) over the names (my characters, recent recipients, friends, the
--   guild), filtered as you type. A pick only writes the name into the box;
--   the player still clicks Send, and any confirmation (session 6: SetText
--   then Send passed, through the stranger dialog).
-- - The fill: the To box starts with the last name this character mailed
--   (chars[guid].lastTo, set and cleared by Core/Sent.lua), when the send tab
--   opens and again after an attributed send, only while the box is empty.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Store, Names, Registry = GM.Store, GM.Names, GM.Registry
local Glass, Skin = GM.Glass, GM.Skin
local Address = {}
GM.Address = Address

local ICON = "Interface\\Icons\\INV_Misc_Book_09"

local function box() return rawget(_G, "SendMailNameEditBox") end

--------------------------------------------------------------------------------
-- The fill
--------------------------------------------------------------------------------

-- The name to fill for the current character, or nil.
function Address.LastName()
    if not Store.Ready() then return nil end
    local me = Registry.CurrentGUID()
    local c = me and Store.Chars()[me]
    local key = c and c.lastTo
    if type(key) ~= "string" then return nil end
    local r = Store.Recents()[key]
    return r and r.name or nil
end

-- Every condition is checked at the moment of filling.
local function fill()
    local b, frame = box(), rawget(_G, "SendMailFrame")
    if not (GM.db.autofill and b and frame and frame:IsVisible()) then return end
    if b:GetText() ~= "" then return end
    local name = Address.LastName()
    if not name then return end
    b:SetText(name)
    b:HighlightText()
end
Address.Fill = fill

local function safely(key, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then API.Fail(key, err) end
    end
end

--------------------------------------------------------------------------------
-- The picker
--------------------------------------------------------------------------------

-- The name as offered, or nil: secret or blank, another realm's, or the
-- current character's own.
local function candidate(name, me)
    local display = Names.Display(name)
    if not display then return nil end
    local ok, short = pcall(Ambiguate, display, "none")
    if ok and type(short) == "string" and not API.IsSecret(short) then display = short end
    if display:find("-", 1, true) then return nil end   -- another realm: a character name has no "-"
    if me and Names.Key(display) == me then return nil end
    return display
end

local function byName(a, b) return a:lower() < b:lower() end

local function friends()
    local out = {}
    if not (C_FriendList and C_FriendList.GetNumFriends) then return out end
    for i = 1, C_FriendList.GetNumFriends() or 0 do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if type(info) == "table" then out[#out + 1] = info.name end
    end
    return out
end

local function guild()
    local out = {}
    if not IsInGuild() then return out end
    for i = 1, GetNumGuildMembers() or 0 do
        out[#out + 1] = (GetGuildRosterInfo(i))
    end
    return out
end

-- The menu's sections, each { title, names }, empty ones left out; each name
-- once across sections (the first wins).
function Address.Sections()
    local me = Names.Key(API.PlayerFullName())
    local seen = {}
    local function section(title, raw, sorted)
        local names = {}
        for _, n in ipairs(raw) do
            local c = candidate(n, me)
            local key = c and Names.Key(c)
            if key and not seen[key] then
                seen[key] = true
                names[#names + 1] = c
            end
        end
        if sorted then table.sort(names, byName) end
        return { title = title, names = names }
    end
    local mine = {}
    for _, c in ipairs(Registry.Characters()) do
        if not c.hidden and Registry.Reachable(c) then mine[#mine + 1] = c.name end
    end
    local recent = {}
    if Store.Ready() then
        local list = {}
        for _, r in pairs(Store.Recents()) do list[#list + 1] = r end
        table.sort(list, function(a, b)
            if a.day ~= b.day then return a.day > b.day end
            return byName(a.name, b.name)
        end)
        for _, r in ipairs(list) do recent[#recent + 1] = r.name end
    end
    local out = {}
    for _, s in ipairs({ section("My characters", mine, true), section("Recent", recent, false),
        section("Friends", friends(), true), section("Guild", guild(), true) }) do
        if #s.names > 0 then out[#out + 1] = s end
    end
    return out
end

--------------------------------------------------------------------------------
-- The picker's panel: a search box over the sections (PLAN.md, "The
-- searchable picker"). Built once; its data read when it opens.
--------------------------------------------------------------------------------

local PICK_W, PICK_H = 240, 330
local ROWS, ROW_H = 15, 18
local GOLD = { 1, 0.82, 0 }
Address.ROWS = ROWS

local panel, ui
local sections = {}        -- Address.Sections(), read at open and on a roster update
local rows = {}            -- what the list shows: { title = s } or { name = s }
local query = ""
local offset = 0

local function words()
    local out = {}
    for w in query:gmatch("%S+") do out[#out + 1] = w end
    return out
end

local function matches(name, ws)
    local low = name:lower()
    for _, w in ipairs(ws) do
        if not low:find(w, 1, true) then return false end
    end
    return true
end

-- The sections, filtered: a section's title only when a name of it is left.
local function filter()
    local out, ws = {}, words()
    for _, sec in ipairs(sections) do
        local first = true
        for _, name in ipairs(sec.names) do
            if matches(name, ws) then
                if first then out[#out + 1] = { title = sec.title }; first = false end
                out[#out + 1] = { name = name }
            end
        end
    end
    return out
end

local function maxOffset() return math.max(0, #rows - ROWS) end

-- Every pooled row repainted whole: nothing of its last use stays.
local function paint()
    for i, r in ipairs(ui.rows) do
        local e = rows[offset + i]
        r.name = e and e.name or nil
        r:SetEnabled(r.name ~= nil)
        if e then
            r.label:SetText(e.title or e.name)
            if e.title then r.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else r.label:SetTextColor(1, 1, 1) end
            r:Show()
        else
            r:Hide()
        end
    end
    local max = maxOffset()
    ui.scroll:SetMinMaxValues(0, max)
    ui.scroll:SetValue(offset)
    ui.scroll:SetShown(max > 0)
    local empty = ""
    if #rows == 0 then empty = (query == "" and "No names yet" or "No match") end
    ui.empty:SetText(empty)
end

local function setOffset(n)
    n = math.max(0, math.min(math.floor(n), maxOffset()))
    if n == offset then return end
    offset = n
    paint()
end

-- keep: a roster update keeps the offset (clamped); anything else starts at
-- the top.
local function refilter(keep)
    rows = filter()
    offset = keep and math.max(0, math.min(offset, maxOffset())) or 0
    paint()
end

-- Every close is this one cleanup.
local function close()
    if not panel then return end
    ui.search:ClearFocus()
    panel:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    panel:UnregisterEvent("GUILD_ROSTER_UPDATE")
    panel:Hide()
end
Address.Close = close

local function pick(name)
    local b = box()
    if b then b:SetText(name) end
    close()
end
Address.Pick = pick

local function firstName()
    for _, r in ipairs(rows) do
        if r.name then return r.name end
    end
end

local function newRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -(i - 1) * ROW_H)
    r.label = Glass.Font(r, 13, "LEFT")
    r.label:SetPoint("LEFT", r, "LEFT", 6, 0)
    r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    r:SetScript("OnClick", function(self) if self.name then pick(self.name) end end)
    return r
end

local function build(button)
    panel = CreateFrame("Frame", nil, rawget(_G, "SendMailFrame"))
    panel:SetSize(PICK_W, PICK_H)
    panel:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    Skin.AddWindow(panel)
    ui = { rows = {} }
    local content = CreateFrame("Frame", nil, panel)
    content:SetAllPoints(panel)
    content:SetFrameLevel(Glass.ContentLevel(panel))
    local title = Glass.Font(content, 14, "LEFT")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -8)
    title:SetText("Pick a recipient")
    local x = CreateFrame("Button", nil, content, "UIPanelCloseButton")
    x:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    x:SetScript("OnClick", close)
    ui.close = x

    local search = CreateFrame("EditBox", nil, content)
    search:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -30)
    search:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, -30)
    search:SetHeight(22)
    search:SetAutoFocus(false)
    search:SetFontObject("ChatFontNormal")
    search:SetTextInsets(8, 8, 0, 0)
    Skin.AddPane(search, "pane")
    local hint = Glass.Font(search, 12, "LEFT")
    hint:SetPoint("LEFT", search, "LEFT", 8, 0)
    hint:SetText("|cff9d9d9dSearch|r")
    search:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        hint:SetShown(text == "")
        query = text:lower()
        refilter(false)
    end)
    search:SetScript("OnEscapePressed", close)
    search:SetScript("OnEnterPressed", function()
        local name = firstName()
        if name then pick(name) end
    end)
    ui.search = search

    local list = CreateFrame("Frame", nil, content)
    list:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
    list:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -6)
    list:SetHeight(ROWS * ROW_H)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) setOffset(offset - delta * 3) end)
    for i = 1, ROWS do ui.rows[i] = newRow(list, i) end
    ui.list = list

    local scroll = CreateFrame("Slider", nil, list)
    scroll:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
    scroll:SetWidth(8)
    scroll:SetOrientation("VERTICAL")
    scroll:SetValueStep(1)
    scroll:SetObeyStepOnDrag(true)
    scroll:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = scroll:GetThumbTexture()
    if thumb then
        thumb:SetSize(8, 32)
        thumb:SetVertexColor(1, 1, 1, 0.35)
    end
    scroll:SetScript("OnValueChanged", function(_, v) setOffset(v) end)
    ui.scroll = scroll
    ui.empty = Glass.Font(list, 13, "CENTER")
    ui.empty:SetPoint("TOP", list, "TOP", 0, -30)

    panel:SetScript("OnEvent", function(_, event, arg1)
        local ok, err = pcall(function()
            if event == "GLOBAL_MOUSE_DOWN" then
                if arg1 ~= "LeftButton" and arg1 ~= "RightButton" then return end
                if panel:IsMouseOver() or button:IsMouseOver() then return end
                close()
            elseif event == "GUILD_ROSTER_UPDATE" then
                sections = Address.Sections()
                refilter(true)
            end
        end)
        if not ok then API.Fail("address picker " .. event, err) end
    end)
    -- The send tab or the mailbox going: closed for good, not just hidden.
    panel:GetParent():HookScript("OnHide", close)
end

local function open(button)
    if not panel then build(button) end
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    sections = Address.Sections()
    ui.search:SetText("")
    query, offset = "", 0
    refilter(false)
    panel:Show()
    API.RegisterEvents(panel, { "GLOBAL_MOUSE_DOWN", "GUILD_ROSTER_UPDATE" })
    ui.search:SetFocus()
end

function Address.Toggle(button)
    if panel and panel:IsShown() then return close() end
    open(button or Address.button)
end

--------------------------------------------------------------------------------
-- Start (PLAYER_LOGIN; Blizzard_MailFrame isn't load-on-demand)
--------------------------------------------------------------------------------

local started = false
function Address.Start()
    local frame, b = rawget(_G, "SendMailFrame"), box()
    if started or not (frame and b) then return end
    started = true
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(20, 20)
    button:SetPoint("LEFT", b, "RIGHT", 4, 0)
    button:SetNormalTexture(ICON)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", safely("address picker", function(self) Address.Toggle(self) end))
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Glass Mail: pick a recipient")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Address.button = button
    -- Any tab click: fill() needs the send tab visible, which only tab 2
    -- leaves it (MailFrame.lua:189-222; Reply goes through tab 2 too).
    if type(rawget(_G, "MailFrameTab_OnClick")) == "function" then
        hooksecurefunc("MailFrameTab_OnClick", safely("address tab", fill))
    end
end

-- After an attributed send (Core/Sent.lua): a frame later, once every
-- MAIL_SEND_SUCCESS handler has run (Blizzard's reset of the box among them).
-- fill() reads lastTo then: a later unattributed success has cleared it.
GM.Sent.onConfirmed = function()
    C_Timer.After(0, safely("address fill", fill))
end

-- A send succeeded: Blizzard's reset focuses the To box (MailFrame.lua:1422),
-- so the picker steps aside, attributed or not, and takes no focus back.
local events = CreateFrame("Frame")
events:SetScript("OnEvent", safely("address send", close))
API.RegisterEvents(events, { "MAIL_SEND_SUCCESS" })

GM._test = GM._test or {}
GM._test.address = {
    candidate = candidate, panel = function() return panel end, ui = function() return ui end,
    rows = function() return rows end, offset = function() return offset end, setOffset = setOffset,
}
