-- The glass look on the mail windows: a panel under each, a reading pane under
-- the inbox rows, a dark letter with light text, the stock art faded (never hidden, never a field written on
-- a Blizzard frame), and the clear / smoked / stock choice, switched live.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

-- Snapshot every field of the mail windows before the addon loads: the skin
-- may call their methods, but must not write onto them.
local function fields(w)
    local t = {}
    for k, v in pairs(w) do t[k] = v end
    return t
end
local WINDOWS = { "MailFrame", "OpenMailFrame", "InboxFrame", "SendMailFrame", "SendMailScrollFrame",
    "OpenMailScrollFrame" }
local DARK = { SendMailBodyEditBox:GetTextColor() }
local function fontObjectState() return MailTextFontNormal._textColor, InvoiceTextFontNormal._textColor end
local before = {}
for _, name in ipairs(WINDOWS) do before[name] = fields(_G[name]) end

local GM = loadAddon()
eq(GM.db.skin, "clear", "the default look is clear glass")
local T = GM._test.skin

for _, name in ipairs(WINDOWS) do
    local w = _G[name]
    local after = fields(w)
    for k, v in pairs(after) do
        local hooked = WoW.hooked[w] and WoW.hooked[w][k]
        check(hooked or before[name][k] == v, name .. ": no field written: " .. tostring(k))
    end
    for k in pairs(before[name]) do check(after[k] ~= nil, name .. ": no field removed: " .. tostring(k)) end
end

for _, name in ipairs({ "MailFrame", "OpenMailFrame" }) do
    local w = _G[name]
    check(GM.Skin.IsSkinned(w), name .. " is skinned")
    local s = T.skinned[w]
    check(s.panel:IsShown(), name .. ": the glass panel shows")
    check(s.panel:GetFrameLevel() < w:GetFrameLevel(), name .. ": the panel sits under the window")
    for _, key in ipairs(T.ART) do
        eq(w[key]:GetAlpha(), 0, name .. ": stock " .. key .. " faded")
        check(w[key]:IsShown(), name .. ": stock " .. key .. " not hidden (Blizzard keeps control)")
    end
    eq(w.Inset.Bg:GetAlpha(), 0, name .. ": the inset's marble faded")
    eq(w.Inset.NineSlice:GetAlpha(), 0, name .. ": the inset's border faded")
end

-- The rest of the stock art, picked out by structure.
eq(InboxFrameBg:GetAlpha(), 0, "the inbox background faded")
for i = 1, 7 do
    local row = _G["MailItem" .. i]
    for _, r in ipairs({ row:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            eq(r:GetAlpha(), 0, "row " .. i .. ": its border and divider faded")
        else
            eq(r:GetAlpha(), 1, "row " .. i .. ": its text stays")
        end
    end
end
for _, owner in ipairs({ SendMailFrame, OpenMailFrame }) do
    for _, r in ipairs({ owner:GetRegions() }) do
        local _, rel = r:GetPoint(1)
        if r:GetName() and r:GetName():find("HorizontalBar") then
            eq(r:GetAlpha(), 0, r:GetName() .. " faded")
        elseif rel and rel.GetName and rel:GetName() and rel:GetName():find("HorizontalBar") then
            eq(r:GetAlpha(), 0, "the unnamed right-hand piece of " .. rel:GetName() .. " faded")
        end
    end
end
eq(SendMailMoneyInset.Bg:GetAlpha(), 0, "the send tab's money inset faded")
eq(SendMailMoneyInset.NineSlice:GetAlpha(), 0, "  and its border")
eq(SendMailMoneyBg:GetAlpha(), 1, "the money value field keeps its frame")
eq(SendMailErrorIcon:GetAlpha(), 1, "a texture anchored to something else stays")

-- The letters go dark: the stationery faded (not hidden), a pane in its place,
-- the text light. Only the mail widgets are recoloured, never the shared fonts.
local L = GM.Skin.LETTER_TEXT
local function light(r, g, b) return close(r, L[1]) and close(g, L[2]) and close(b, L[3]) end
local function isDark(r, g, b) return close(r, DARK[1]) and close(g, DARK[2]) and close(b, DARK[3]) end
for _, n in ipairs({ "SendStationeryBackgroundLeft", "SendStationeryBackgroundRight", "OpenStationeryBackgroundLeft",
        "OpenStationeryBackgroundRight" }) do
    eq(_G[n]:GetAlpha(), 0, n .. " faded under glass")
    check(_G[n]:IsShown(), "  not hidden")
end
for name, scroll in pairs({ MailFrame = SendMailScrollFrame, OpenMailFrame = OpenMailScrollFrame }) do
    local lp = T.letters[name] and T.letters[name].pane
    check(lp and lp.frame:IsShown(), name .. ": the letter has a pane")
    eq(lp.frame:GetParent(), scroll:GetParent(), "  beside the scroll frame")
    eq(lp.frame:GetFrameLevel(), scroll:GetFrameLevel(), "  at its level, under the scroll child's text")
    local _, rel = lp.frame:GetPoint(1)
    check(rel == _G[name == "MailFrame" and "SendStationeryBackgroundLeft" or "OpenStationeryBackgroundLeft"],
        "  anchored to the stationery, so it follows its height")
end
check(light(SendMailBodyEditBox:GetTextColor()), "the send tab's letter text is light")
local H = GM.Skin.LETTER_HIGHLIGHT
local function darkSelection() local r, g, b = SendMailBodyEditBox:GetHighlightColor()
    return close(r, H[1]) and close(g, H[2]) and close(b, H[3]) end
check(darkSelection(), "  and its selection dark enough to read it on")

-- The sections: a pane over each window's content box (its Inset, which
-- Blizzard moves per tab), at the window's level so its children draw above;
-- and the send tab's footer, from the money inset to Cancel.
for _, w in ipairs({ MailFrame, OpenMailFrame }) do
    local sp = T.sections[w:GetName()]
    check(sp and sp.frame:IsShown(), w:GetName() .. ": its content box has a pane")
    eq(sp.frame:GetParent(), w, "  in the window")
    eq(sp.frame:GetFrameLevel(), w:GetFrameLevel(), "  at its level, under its children")
    local _, tl = sp.frame:GetPoint(1)
    local _, br = sp.frame:GetPoint(2)
    check(tl == w.Inset and br == w.Inset, "  on its Inset, so it follows the tab's layout")
end
local foot = T.sections.footer
check(foot and foot.frame:IsShown(), "the send tab has a footer pane")
eq(foot.frame:GetParent(), SendMailFrame, "  in the send tab, hidden with it")
local _, fl = foot.frame:GetPoint(1)
local _, fr = foot.frame:GetPoint(2)
check(fl == SendMailMoneyInset and fr == SendMailCancelButton, "  from the money inset to Cancel")
check(light(OpenMailBodyText:GetTextColor("P")), "the open letter's body is light")
check(light(OpenMailInvoiceItemLabel:GetTextColor()), "the invoice's labels are light, a frame deeper too")
check(light(OpenMailInvoiceSalePrice:GetTextColor()), "  all of them")
eq(OpenMailInvoiceMoneyAmount:GetTextColor(), 1, "a font string in another font is left alone")
local mailFont, invoiceFont = fontObjectState()
check(mailFont == nil and invoiceFont == nil, "the shared font objects are never recoloured")

-- The reading pane under the rows: ours, in the inbox, under the rows.
local pane = T.pane()
check(pane and pane.frame:IsShown(), "the reading pane shows")
eq(pane.frame:GetParent(), InboxFrame, "the pane lives in the inbox")
check(pane.frame:GetFrameLevel() < MailItem1:GetFrameLevel(), "the pane sits under the rows")

-- A surface painted in a preset: the body's tint, grain and wash, and the pane.
local function painted(name)
    local p = GM.Skin.PRESETS[name]
    local ok = true
    for _, window in ipairs({ MailFrame, OpenMailFrame }) do
        local g = T.skinned[window].g
        local c = g.tint._color
        ok = ok and c and close(c[1], p.tint[1]) and close(c[2], p.tint[2]) and close(c[3], p.tint[3])
            and close(c[4], p.tint[4])
        ok = ok and close(g.grain:GetAlpha(), p.grain)
        local wash = g.wash._gradient
        ok = ok and wash and close(wash[3].a, p.wash)
    end
    local pc = pane.tex._color
    ok = ok and pc and close(pc[4], p.pane[4]) and close(pc[1], p.pane[1])
    return ok
end
check(painted("clear"), "clear: the body and the pane carry the clear numbers")
local function lettersPainted(name)
    local pc = GM.Skin.PRESETS[name].pane
    for _, letter in pairs(T.letters) do local lp = letter.pane
        local c = lp.tex._color
        if not (c and close(c[4], pc[4]) and close(c[1], pc[1])) then return false end
    end
    return true
end
check(lettersPainted("clear"), "  and the letter panes")
local function sectionsPainted(name)
    local pc, n = GM.Skin.PRESETS[name].section, 0
    for _, sp in pairs(T.sections) do
        local c = sp.tex._color
        if not (c and close(c[4], pc[4]) and close(c[1], pc[1])) then return false end
        n = n + 1
    end
    return n == 3
end
check(sectionsPainted("clear"), "  and the sections")

-- Switched live, both ways, from the setting.
check(GM.Settings.SetSkin("smoked"), "smoked is accepted")
eq(GM.db.skin, "smoked", "and saved")
check(painted("smoked"), "smoked: the same surfaces repainted, no reload")
check(lettersPainted("smoked"), "  the letter panes too")
check(sectionsPainted("smoked"), "  and the sections")
check(light(SendMailBodyEditBox:GetTextColor()), "  the letter text stays light")
check(GM.Skin.PRESETS.smoked.tint[4] > GM.Skin.PRESETS.clear.tint[4], "smoked is denser than clear")
check(GM.Skin.PRESETS.smoked.tint[1] < GM.Skin.PRESETS.clear.tint[1], "  and darker")
local rim = T.skinned[MailFrame].g.rim:GetAlpha()
check(GM.Settings.SetSkin("clear"), "back to clear")
eq(T.skinned[MailFrame].g.rim:GetAlpha(), rim, "the rim never changes with the preset")
check(painted("clear"), "clear again: repainted back")

-- The preset goes into LibGlass's STYLE for later surfaces, as a COPY.
GM.Settings.SetSkin("smoked")
GM.Glass.STYLE.tint[4] = 0.99
eq(GM.Skin.PRESETS.smoked.tint[4], 0.62, "writing STYLE's tint never edits the preset (copied, not aliased)")
GM.Settings.SetSkin("clear")

-- Stock: Blizzard's own art back, our panels and pane gone.
check(GM.Settings.SetSkin("stock"), "stock is accepted")
local s = T.skinned[MailFrame]
check(not s.panel:IsShown(), "stock hides the panel")
check(not pane.frame:IsShown(), "stock hides the pane")
eq(MailFrame.Bg:GetAlpha(), 1, "stock restores the stock art")
eq(InboxFrameBg:GetAlpha(), 1, "  the inbox background too")
eq(SendMailHorizontalBarLeft:GetAlpha(), 1, "  and the bars")
eq(OpenStationeryBackgroundLeft:GetAlpha(), 1, "  and the letter's stationery")
for _, letter in pairs(T.letters) do local lp = letter.pane check(not lp.frame:IsShown(), "stock hides the letter panes") end
check(isDark(SendMailBodyEditBox:GetTextColor()), "stock gives the letter text Blizzard's colour back")
for _, sp in pairs(T.sections) do check(not sp.frame:IsShown(), "stock hides the sections") end
check(isDark(OpenMailBodyText:GetTextColor("P")), "  the open letter's body")
check(isDark(OpenMailInvoiceItemLabel:GetTextColor()), "  and the invoice")
eq(select(1, SendMailBodyEditBox:GetHighlightColor()), 0.82, "  and the send body's selection colour")
GM.Settings.SetSkin("smoked")
eq(MailFrame.Bg:GetAlpha(), 0, "glass again fades it again")
check(painted("smoked"), "  in the chosen preset")
check(light(OpenMailBodyText:GetTextColor("P")), "  and the letter light again")

-- With the letter open, a switch asks Blizzard to show it again, so the body
-- (laid out on SetText) takes the new colour; a closed letter isn't touched,
-- nor one whose look doesn't change.
OpenMailFrame:Show()
local updates = OpenMailFrame._updates or 0
GM.Settings.SetSkin("stock")
eq(OpenMailFrame._updates, updates + 1, "an open letter is shown again on a switch")
check(isDark(unpack(OpenMailBodyText._shownColor)), "  and its body shows dark")
GM.Settings.SetSkin("clear")
check(light(unpack(OpenMailBodyText._shownColor)), "  then light")
GM.Settings.SetSkin("smoked")
eq(OpenMailFrame._updates, updates + 2, "  but not between two glass presets")
OpenMailFrame:Hide()
GM.Settings.SetSkin("stock")
eq(OpenMailFrame._updates, updates + 2, "a closed letter isn't refreshed")
GM.Settings.SetSkin("smoked")

-- A name that isn't a skin is refused and changes nothing.
check(not GM.Settings.SetSkin("frosted"), "an unknown skin is refused")
eq(GM.db.skin, "smoked", "  and the setting stays")

-- /gmail skin, and M0's /gmail glass on/off as its alias.
SlashCmdList.GLASSMAILBOX("skin clear")
eq(GM.db.skin, "clear", "/gmail skin clear")
SlashCmdList.GLASSMAILBOX("glass off")
eq(GM.db.skin, "stock", "/gmail glass off is stock")
SlashCmdList.GLASSMAILBOX("glass on")
eq(GM.db.skin, "clear", "/gmail glass on is clear glass")
newChat()
SlashCmdList.GLASSMAILBOX("skin purple")
check(chatHas("/gmail skin clear/smoked/stock"), "an unknown skin prints the choices")
eq(GM.db.skin, "clear", "  and changes nothing")

-- The options page: one radio per look, the current one checked, re-read on
-- every show, and a click sets it.
local O = GM.Options._test
O.panel:Show()
local radios = O.skinRadios
eq(#radios, 3, "three looks on the options page")
eq(radios[2].text:GetText(), "Smoked glass", "each radio carries its label in the template's own text")
local function checked()
    for _, rb in ipairs(radios) do if rb:GetChecked() then return rb.value end end
end
eq(checked(), "clear", "the current look is checked")
GM.Settings.SetSkin("smoked")
O.panel:Hide(); O.panel:Show()
eq(checked(), "smoked", "a change made elsewhere shows on the next visit")
radios[3]._scripts.OnClick(radios[3])
eq(GM.db.skin, "stock", "clicking a look sets it")
eq(checked(), "stock", "  and the group follows")

-- Starting twice (PLAYER_LOGIN, then ADDON_LOADED for the mail frame) builds
-- one panel per window and one pane.
local n = 0
for _ in pairs(T.skinned) do n = n + 1 end
WoW.fire("ADDON_LOADED", "Blizzard_MailFrame")
local m = 0
for _ in pairs(T.skinned) do m = m + 1 end
eq(m, n, "a second start adds no panels")
eq(T.pane(), pane, "  nor a second pane")
local open = T.letters.OpenMailFrame
WoW.fire("ADDON_LOADED", "Blizzard_MailFrame")
eq(T.letters.OpenMailFrame, open, "  nor reads the letter text again (stock would then restore our own colour)")
eq(next(GM.failures), nil, "no failures recorded")

done("test_skin")
