-- Options.lua: the page in Esc > Options > AddOns, built with the porting
-- guide's measured recipe ("An Options page with sub-pages and an About page"):
-- a plain Frame with .name, hidden at creation (or the first visit is blank),
-- controls built on the first OnShow, every value re-read on every OnShow,
-- registered once at PLAYER_LOGIN from GlassMailbox.lua.
--
-- The look (clear / smoked / stock) and the version; each feature adds its own
-- controls here as it lands. Choices are radio groups, not dropdowns (the
-- porting guide's measured recipe).

GlassMailbox = GlassMailbox or {}
local GM = GlassMailbox
local API = GM.API
local Options = {}
GM.Options = Options

local CHECK_ART = {
    normal = "Interface\\Buttons\\UI-CheckBox-Up",
    pushed = "Interface\\Buttons\\UI-CheckBox-Down",
    highlight = "Interface\\Buttons\\UI-CheckBox-Highlight",
    checked = "Interface\\Buttons\\UI-CheckBox-Check",
}

local RADIO_ART = "Interface\\Buttons\\UI-RadioButton"   -- 4 cells: normal, checked, highlight, pushed

local panel = CreateFrame("Frame")
panel.name = "Glass Mailbox"
panel:Hide()

local category
local refreshers = {}

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fs:SetText(text)
    return fs
end

-- A labelled check button: UICheckButtonTemplate when the client has it, else
-- the client's own checkbox art.
local function checkButton(parent, text, get, set)
    local cb, templated = API.SafeFrame("CheckButton", parent, "UICheckButtonTemplate", "text")
    if not templated then
        cb:SetNormalTexture(CHECK_ART.normal)
        cb:SetPushedTexture(CHECK_ART.pushed)
        cb:SetHighlightTexture(CHECK_ART.highlight)
        cb:SetCheckedTexture(CHECK_ART.checked)
    end
    cb:SetSize(24, 24)
    local fs = label(parent, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
    return cb
end

-- A labelled radio button: UIRadioButtonTemplate when the client has it, else
-- the client's own radio art.
local function radioButton(parent, text)
    local rb, templated = API.SafeFrame("CheckButton", parent, "UIRadioButtonTemplate", "text")
    if not templated then
        rb:SetSize(16, 16)
        rb:SetNormalTexture(RADIO_ART)
        rb:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
        rb:SetCheckedTexture(RADIO_ART)
        rb:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
        rb:SetHighlightTexture(RADIO_ART)
        rb:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
    end
    local fs = label(parent, text)
    fs:SetPoint("LEFT", rb, "RIGHT", 4, 0)
    return rb
end

-- Mutually exclusive choices, stacked under `anchor`: { {value, text}, ... }.
-- Returns the last button, to anchor what follows. The whole group re-syncs
-- after a click, so a refused choice snaps back.
local function radios(parent, anchor, options, get, set)
    local group = {}
    local function sync()
        local current = get()
        for _, rb in ipairs(group) do rb:SetChecked(rb.value == current) end
    end
    local prev = anchor
    for _, o in ipairs(options) do
        local rb = radioButton(parent, o[2])
        rb.value = o[1]
        rb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, prev == anchor and -8 or -4)
        rb:SetScript("OnClick", function() set(o[1]); sync() end)
        group[#group + 1] = rb
        prev = rb
    end
    refreshers[#refreshers + 1] = sync
    return prev, group
end

local function build()
    local title = label(panel, "Glass Mailbox", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    local version = label(panel, "", "GameFontDisableSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    refreshers[#refreshers + 1] = function()
        version:SetText("Version " .. GM.VersionText() .. " for World of Warcraft: Forever, by Spotnick")
    end
    local look = label(panel, "The mailbox windows' look", "GameFontNormal")
    look:SetPoint("TOPLEFT", version, "BOTTOMLEFT", 0, -16)
    local options = {}
    for _, name in ipairs(GM.Skin.NAMES) do options[#options + 1] = { name, GM.Skin.LABELS[name] } end
    local last, group = radios(panel, look, options, function() return GM.db.skin end, GM.Settings.SetSkin)
    Options._test.skinRadios = group
    local hint = label(panel, "Type /gmail help for every command.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
end

panel:SetScript("OnShow", function()
    if not Options.built then
        Options.built = true
        build()
    end
    for _, refresh in ipairs(refreshers) do refresh() end
end)

-- Called once at PLAYER_LOGIN by GlassMailbox.lua.
function Options.Register()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
end

-- Open the page; false when the Settings framework can't.
function Options.Open()
    if not (category and Settings and Settings.OpenToCategory) then return false end
    return pcall(Settings.OpenToCategory, category:GetID()) and true or false
end

Options._test = { panel = panel, refreshers = refreshers }
