-- Skin.lua's inbox guides when a row is missing: nothing of them is built, the
-- failure is recorded once, and the rest of the look stands.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local button = MailItem3Button
rawset(_G, "MailItem3Button", nil)
local GM = loadAddon()
local T = GM._test.skin
eq(T.guides(), nil, "a missing row button: no guides")
check(GM.failures["skin guides"] ~= nil, "  and the failure recorded")
local pane = T.pane()
check(pane and pane.frame:IsShown(), "the reading pane still shows")
eq(#{ pane.frame:GetRegions() }, 1, "  with nothing on it but its own fill")
GM.failures["skin guides"] = nil
rawset(_G, "MailItem3Button", button)
WoW.fire("ADDON_LOADED", "Blizzard_MailFrame")
eq(T.guides(), nil, "a later start doesn't try again")
WoW.inbox = {}
GM.Skin.Refresh()
GM.Settings.SetInboxGuides(false)
GM.Settings.SetInboxGuides(true)
eq(GM.failures["skin guides"], nil, "  and the setting works without them")
done("test_guides_fail")
