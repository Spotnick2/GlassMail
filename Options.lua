-- Options.lua: the page in Esc > Options > AddOns, built with the porting
-- guide's measured recipe ("An Options page with sub-pages and an About page"):
-- a plain Frame with .name, hidden at creation (or the first visit is blank),
-- controls built on the first OnShow, every value re-read on every OnShow,
-- registered once at PLAYER_LOGIN from GlassMail.lua.
--
-- The look (clear / smoked / stock) and the version; each feature adds its own
-- controls here as it lands. Choices are radio groups, not dropdowns (the
-- porting guide's measured recipe).

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Options = {}
GM.Options = Options

local RADIO_ART = "Interface\\Buttons\\UI-RadioButton"   -- 4 cells: normal, checked, highlight, pushed

local panel = CreateFrame("Frame")
panel.name = "Glass Mail"
panel:Hide()

local category
local refreshers = {}

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    fs:SetText(text)
    return fs
end

-- A labelled radio button: UIRadioButtonTemplate when the client has it (its
-- own label, rb.text, takes the text), else the client's own radio art and a
-- label of ours.
local function radioButton(parent, text)
    local rb, templated = API.SafeFrame("CheckButton", parent, "UIRadioButtonTemplate", "text")
    if templated then
        rb.text:SetFontObject("GameFontHighlight")
        rb.text:SetText(text)
        return rb
    end
    rb:SetSize(16, 16)
    rb:SetNormalTexture(RADIO_ART)
    rb:GetNormalTexture():SetTexCoord(0, 0.25, 0, 1)
    rb:SetCheckedTexture(RADIO_ART)
    rb:GetCheckedTexture():SetTexCoord(0.25, 0.5, 0, 1)
    rb:SetHighlightTexture(RADIO_ART)
    rb:GetHighlightTexture():SetTexCoord(0.5, 0.75, 0, 1)
    rb:GetHighlightTexture():SetBlendMode("ADD")   -- as the template's (CheckButtonTemplates.xml:18)
    local fs = label(parent, text)
    fs:SetPoint("LEFT", rb, "RIGHT", 4, 0)
    return rb
end

-- An on/off setting under `anchor`: our own label beside the template's box.
local function checkbox(parent, anchor, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    local fs = label(parent, text)
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    local function sync() cb:SetChecked(get() == true) end
    cb:SetScript("OnClick", function() set(cb:GetChecked() == true); sync() end)
    refreshers[#refreshers + 1] = sync
    return cb
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
    local title = label(panel, "Glass Mail", "GameFontNormalHuge")
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
    local comforts = label(panel, "At the mailbox", "GameFontNormal")
    comforts:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -16)
    local trade = checkbox(panel, comforts, "Block trades while the mailbox is open",
        function() return GM.db.tradeBlock end, GM.Settings.SetTradeBlock)
    local alert = checkbox(panel, trade, "Say in chat who sent new mail",
        function() return GM.db.newMailAlert end, GM.Settings.SetNewMailAlert)
    Options._test.trade, Options._test.alert = trade, alert
    local hint = label(panel, "Type /gmail help for every command.", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", alert, "BOTTOMLEFT", 0, -16)
end

panel:SetScript("OnShow", function()
    if not Options.built then
        Options.built = true
        build()
    end
    for _, refresh in ipairs(refreshers) do refresh() end
end)

-- Called once at PLAYER_LOGIN by GlassMail.lua.
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
