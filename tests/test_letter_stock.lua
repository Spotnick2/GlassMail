-- A player on Blizzard's own look: the letter's widgets are never recoloured,
-- so they keep following their font objects. And a widget whose colour can't
-- be read keeps its letter unbuilt, rather than "restored" to nothing later.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

OpenMailBodyText.GetTextColor = function() return nil end
local GM = loadAddon({ db = { skin = "stock" } })
local T = GM._test.skin
check(WoW.methodsCalled["EditBox:SetTextColor"] == nil, "under stock the send body's colour is never set")
check(WoW.methodsCalled["EditBox:SetHighlightColor"] == nil, "  nor its selection colour")
check(T.letters.MailFrame ~= nil, "  though its letter is built, ready for glass")
eq(T.letters.OpenMailFrame, nil, "a letter whose text colour can't be read isn't built")
check(GM.failures["skin letter OpenMailFrame"] ~= nil, "  and the failure is recorded")
GM.Settings.SetSkin("clear")
check(SendMailBodyEditBox:GetTextColor() > 0.5, "glass turns the send body light")
GM.Settings.SetSkin("stock")
check(SendMailBodyEditBox:GetTextColor() < 0.5, "  and stock gives Blizzard's colour back")
eq(select(1, SendMailBodyEditBox:GetHighlightColor()), 0.82, "  and its selection colour")
eq(next(OpenMailBodyText._htmlColor or {}) and OpenMailBodyText._htmlColor.P[1], 0.18,
    "the unbuilt letter's body is never touched")

done("test_letter_stock")
