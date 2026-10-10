-- The glass look on the mail windows: a panel under each, a reading pane under
-- the inbox rows, the stock art faded (never hidden, never a field written on
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
local WINDOWS = { "MailFrame", "OpenMailFrame", "InboxFrame", "SendMailFrame" }
local before = {}
for _, name in ipairs(WINDOWS) do before[name] = fields(_G[name]) end

local GM = loadAddon()
eq(GM.db.skin, "clear", "the default look is clear glass")
local T = GM._test.skin

for _, name in ipairs(WINDOWS) do
    local w = _G[name]
    local after = fields(w)
    for k, v in pairs(after) do check(before[name][k] == v, name .. ": no field written: " .. tostring(k)) end
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
eq(OpenStationeryBackgroundLeft:GetAlpha(), 1, "the letter's stationery stays (dark text needs it)")

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

-- Switched live, both ways, from the setting.
check(GM.Settings.SetSkin("smoked"), "smoked is accepted")
eq(GM.db.skin, "smoked", "and saved")
check(painted("smoked"), "smoked: the same surfaces repainted, no reload")
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
GM.Settings.SetSkin("smoked")
eq(MailFrame.Bg:GetAlpha(), 0, "glass again fades it again")
check(painted("smoked"), "  in the chosen preset")

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
eq(next(GM.failures), nil, "no failures recorded")

done("test_skin")
