-- Bootstrap: saved settings, the login build warning, /gmail and the options page.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

-- Missing SavedVariables still load.
GlassMailboxDB = nil
local GM = loadAddon()
eq(type(GlassMailboxDB), "table", "missing saved variables become a table")
eq(GM.db, GlassMailboxDB, "the addon keeps the saved table")
eq(type(GlassMailboxCharDB), "table", "missing per-character saved variables become a table")
check(not chatHas("differs from"), "no build warning on the measured build")

-- Only what the player set is saved; the rest follows the shipped defaults.
eq(rawget(GlassMailboxDB, "glass"), nil, "an untouched setting isn't saved")
eq(GM.db.glass, true, "it reads the shipped default")
GM.Settings.SetGlass(false)
eq(rawget(GlassMailboxDB, "glass"), false, "a setting the player changed is saved")
GlassMailboxDB = { glass = true }
GM._test.ensureDefaults()
eq(rawget(GlassMailboxDB, "glass"), nil, "a saved value equal to the default is dropped")
GM.db = GlassMailboxDB

-- The options page: registered once at login, and blank-proof (hidden at
-- creation, built on its first OnShow).
eq(#WoW.categories, 1, "one options category")
check(WoW.categories[1].registered, "it is an AddOns category")
local panel = GM.Options._test.panel
check(not panel:IsShown(), "the page is hidden at creation")
panel:Show()
check(GM.Options.built, "the page builds on its first show")

-- /gmail
newChat()
SlashCmdList.GLASSMAILBOX("")
eq(#newChat(), #GM.HelpLines(), "/gmail prints the help list")
SlashCmdList.GLASSMAILBOX("failures")
local lines = newChat()
check(lines[1] and lines[1]:find("no failures"), "/gmail failures reports none")
SlashCmdList.GLASSMAILBOX("version")
lines = newChat()
check(lines[1] and lines[1]:find("1.60.1.70291", 1, true), "/gmail version names the measured build")
check(lines[1] and lines[1]:find("version dev", 1, true), "a deployed copy reports dev")
SlashCmdList.GLASSMAILBOX("glass off")
eq(GM.db.glass, false, "/gmail glass off")
SlashCmdList.GLASSMAILBOX("glass on")
eq(GM.db.glass, true, "/gmail glass on")
SlashCmdList.GLASSMAILBOX("options")
eq(WoW.openedCategory, WoW.categories[1]:GetID(), "/gmail options opens the page")

-- A failure recorded anywhere shows up in /gmail failures.
GM.API.Fail("demo", "boom")
newChat()
SlashCmdList.GLASSMAILBOX("failures")
lines = newChat()
check(lines[1] and lines[1]:find("demo: boom", 1, true), "/gmail failures lists recorded failures")
GM.failures.demo = nil

-- The build warning: at a real login on another build, in a dev build only.
-- Never on /reload.
local realBuild = GetBuildInfo
GetBuildInfo = function() return "1.60.1", "99999", "Oct 9 2026", 16001 end
local function warned()
    for _, l in ipairs(newChat()) do if l:find("differs from") then return true end end
    return false
end
newChat()
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
check(warned(), "a dev build warns at login on another build")
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
check(not warned(), "never on /reload")
WoW.addonVersion = "1.2.0"
WoW.fire("PLAYER_ENTERING_WORLD", true, false)
check(not warned(), "a release never warns")
eq(GM.VersionText(), "1.2.0", "a release shows its version")
WoW.addonVersion = "dev"
GetBuildInfo = realBuild

done("test_boot")
