-- Address.lua: S1, the address book on the send tab (PLAN.md, "S1: the address
-- book picker", "S1: the last recipient", "The address PR in detail").
--
-- - The picker: our button right of the To box opens a menu of names (my
--   characters, recent recipients, friends, the guild). A pick only writes the
--   name into the box; the player still clicks Send, and any confirmation
--   (session 6: SetText then Send passed, through the stranger dialog).
-- - The fill: the To box starts with the last name this character mailed
--   (chars[guid].lastTo, set and cleared by Core/Sent.lua), when the send tab
--   opens and again after an attributed send, only while the box is empty.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Store, Names, Registry = GM.Store, GM.Names, GM.Registry
local Address = {}
GM.Address = Address

local ICON = "Interface\\Icons\\INV_Misc_Book_09"
local SCROLL = 400   -- the menu's and the guild submenu's height before they scroll

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

local function pick(name)
    local b = box()
    if b then b:SetText(name) end
end
Address.Pick = pick

local function menu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    local ok, err = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
        root:SetScrollMode(SCROLL)
        local sections = Address.Sections()
        if #sections == 0 then
            root:CreateTitle("No names yet")
            return
        end
        for _, s in ipairs(sections) do
            local parent = root
            if s.title == "Guild" then
                parent = root:CreateButton("Guild")
                parent:SetScrollMode(SCROLL)
            else
                root:CreateTitle(s.title)
            end
            for _, name in ipairs(s.names) do
                parent:CreateButton(name, function() pick(name) end)
            end
        end
    end)
    if not ok then API.Fail("address menu", err) end
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
    button:SetScript("OnClick", function(self) menu(self) end)
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

GM._test = GM._test or {}
GM._test.address = { candidate = candidate, menu = menu }
