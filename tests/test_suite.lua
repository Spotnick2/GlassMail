-- Suite.lua: following Glass UI's suite (docs/PLAN.md, "Following Glass UI's
-- suite"), against a fake GlassUI.Suite (API 1; its Body numbers made
-- distinct from ours, so a test can tell whose were painted). Each case boots
-- a fresh client: participation is frozen at load.
dofile("tests/harness.lua")

local function close(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end
local function copy(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end

-- The fake suite: o.follow (false: Theme says not-following), o.preset, o.api,
-- o.noLook / noBody / noAccent / noOpen, o.throw = { Theme = true, ... }.
local function fake(o)
    o = o or {}
    local f = { reports = {}, look = { tint = "clear", accent = "gold", hover = "glow" }, opened = 0 }
    local S = { API = o.api or 1 }
    local function maybeThrow(name) if o.throw and o.throw[name] then error("boom " .. name) end end
    S.Theme = function(addon)
        maybeThrow("Theme")
        f.asked = addon
        if o.follow == false then return nil, "not-following" end
        return { name = "pearl", preset = o.preset or "pearl" }
    end
    S.Report = function(addon, state) f.reports[#f.reports + 1] = state; f.reporter = addon end
    if not o.noLook then S.Look = function() maybeThrow("Look"); return copy(f.look) end end
    if not o.noBody then
        S.Body = function(name)
            maybeThrow("Body")
            if f.bodyOverride then return f.bodyOverride(name) end
            if name == "clear" then return { tint = { 0.2, 0.3, 0.4, 0.3 }, wash = 1, backing = { 0.1, 0.1, 0.1, 0.4 } } end
            if name == "smoked" then return { tint = { 0.01, 0.02, 0.03, 0.7 }, wash = 0.5, backing = { 0.1, 0.1, 0.1, 0.9 } } end
            if name == "class" then return { classShade = 0.5, wash = 1, backing = { 0.1, 0.1, 0.1, 0.4 } } end
        end
    end
    if not o.noAccent then
        S.Accent = function(name)
            maybeThrow("Accent")
            if name == "gold" then return { 1, 0.82, 0 } end
            if name == "ice" then return { 0.6, 0.8, 0.9 } end
        end
    end
    if not o.noOpen then S.Open = function() f.opened = f.opened + 1; return true end end
    f.S = S
    return f
end

-- A fresh client: stubs, then Glass UI (loaded first, OptionalDeps), then us.
local function boot(f, db)
    rawset(_G, "GlassMail", nil)
    rawset(_G, "GlassMailDB", db)
    rawset(_G, "GlassMailCharDB", nil)
    rawset(_G, "GlassUI", nil)
    dofile("tests/wow_stubs.lua")
    if f then rawset(_G, "GlassUI", { Suite = f.S }) end
    return loadAddon()
end
local function lastReport(f) return f.reports[#f.reports] end
local function change(f, k, v)
    f.look[k] = v
    EventRegistry:TriggerEvent("GlassUI.Suite.LookChanged", copy(f.look))
end
local function tintOf(GM) return GM._test.skin.skinned[MailFrame].g.tint._color end
local function washOf(GM) return GM._test.skin.skinned[MailFrame].g.wash._gradient[3].a end

-- No Glass UI ------------------------------------------------------------------------
local GM = boot(nil)
eq(GM.Suite.Status(), "absent", "no Glass UI: absent")
eq(GM.GlassBuild().preset, "pearl", "  Pearl, our own material")
eq(GM.Skin.Applied(), "clear", "  our own look")
check(close(tintOf(GM)[4], GM.Skin.BODIES.clear.tint[4]), "  our own body")

-- Following ----------------------------------------------------------------------------
local f = fake()
GM = boot(f)
eq(f.asked, "GlassMail", "Theme is asked for GlassMail")
eq(GM.Suite.Status(), "following", "following")
eq(GM.GlassBuild().preset, "pearl", "  the preset Theme named, built")
eq(GM.Skin.Applied(), "clear", "  the suite's tint")
check(close(tintOf(GM)[4], 0.3) and close(tintOf(GM)[1], 0.2), "  painted with Glass UI's Body, not our copy")
check(close(washOf(GM), GM.BaseWash() * 1), "  its wash a factor of our material's")
local r = lastReport(f)
eq(f.reporter, "GlassMail", "a report, as GlassMail")
check(r.api == 1 and r.built == "pearl" and r.reason == nil and r.declined == nil, "  built pearl, nothing declined")
check(r.look.tint == "clear" and r.look.accent == "gold", "  the look we show")
eq(r.own.tint, nil, "  no override")
check(type(r.options) == "function", "  and our options")
eq(r.live, nil, "  no live = false: we repaint live")

local updates = OpenMailFrame._updates or 0
OpenMailFrame:Show()
change(f, "tint", "smoked")
eq(GM.Skin.Applied(), "smoked", "LookChanged: smoked, live")
check(close(tintOf(GM)[4], 0.7) and close(washOf(GM), GM.BaseWash() * 0.5), "  Glass UI's smoked body")
eq(lastReport(f).look.tint, "smoked", "  reported")
eq(OpenMailFrame._updates or 0, updates, "  an open letter isn't re-shown for a tint change")
change(f, "tint", "neon")
eq(GM.Skin.Applied(), "clear", "a tint we don't know: our own skin (clear)")
change(f, "tint", "smoked")
eq(GM.Skin.Applied(), "smoked", "  a known one again: followed")
OpenMailFrame:Hide()

-- Class: the class colour times the shade, at the built alpha; unreadable, the built tint.
local built = GM.Glass.STYLE.tint
change(f, "tint", "class")
local c = tintOf(GM)
check(close(c[1], 0.53 * 0.5) and close(c[3], 0.93 * 0.5), "class: the warlock colour times Glass UI's shade")
check(close(c[4], built[4]), "  at the surface's built alpha")
local keepClass = WoW.playerClass
change(f, "tint", "smoked")
WoW.playerClass = nil
change(f, "tint", "class")
c = tintOf(GM)
check(close(c[1], built[1]) and close(c[4], built[4]), "class unreadable: the built tint, not smoked's")
WoW.playerClass = keepClass
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
check(close(tintOf(GM)[1], 0.53 * 0.5), "  painted at PLAYER_ENTERING_WORLD")
change(f, "tint", "clear")

-- A malformed Body: the whole local body, never a mix.
for label, bad in pairs({
    nan = { tint = { 0 / 0, 0.3, 0.4, 0.3 }, wash = 1, backing = { 0.1, 0.1, 0.1, 0.4 } },
    range = { tint = { 1.2, 0.3, 0.4, 0.3 }, wash = 1, backing = { 0.1, 0.1, 0.1, 0.4 } },
    wash = { tint = { 0.2, 0.3, 0.4, 0.3 }, wash = 50, backing = { 0.1, 0.1, 0.1, 0.4 } },
    negative = { tint = { 0.2, 0.3, 0.4, 0.3 }, wash = -1, backing = { 0.1, 0.1, 0.1, 0.4 } },
    backing = { tint = { 0.2, 0.3, 0.4, 0.3 }, wash = 1 },
    shade = { wash = 1, backing = { 0.1, 0.1, 0.1, 0.4 } },
}) do
    f.bodyOverride = function() return bad end
    change(f, "tint", "smoked")
    change(f, "tint", "clear")
    check(close(tintOf(GM)[4], GM.Skin.BODIES.clear.tint[4]) and close(washOf(GM), GM.BaseWash()),
        "a bad Body (" .. label .. "): our own clear, whole")
    eq(GM.Skin.Applied(), "clear", "  applied")
    eq(GM.failures["suite repaint"], nil, "  without an error")
end
f.bodyOverride = function() error("boom") end
change(f, "tint", "smoked")
check(close(tintOf(GM)[4], GM.Skin.BODIES.smoked.tint[4]), "  a throwing Body: our own")
f.bodyOverride = nil
change(f, "tint", "clear")

-- The override: Glass Mail's own choice wins, survives a reload, "suite" clears it.
check(GM.Settings.SetSkin("smoked"), "following: a look set in Glass Mail")
eq(GM.db.suiteOwn and GM.db.suiteOwn.skin, "smoked", "  is an override")
eq(GM.db.skin, "clear", "  the local skin untouched")
eq(GM.Skin.Applied(), "smoked", "  applied")
eq(lastReport(f).own.tint, true, "  reported as our own")
change(f, "tint", "clear")
eq(GM.Skin.Applied(), "smoked", "  a suite change doesn't move it")
check(GM.Settings.SetSkin("clear"), "an override equal to the default")
GM._test.ensureDefaults()
eq(rawget(GlassMailDB, "suiteOwn") and GlassMailDB.suiteOwn.skin, "clear", "  survives the defaults' pruning")
check(GM.Settings.SetSkin("suite"), "\"suite\" clears it")
eq(rawget(GlassMailDB, "suiteOwn"), nil, "  nothing saved")
eq(lastReport(f).own.tint, nil, "  no longer reported")
GlassMailDB.suiteOwn = { skin = "neon" }
GM._test.ensureDefaults()
eq(rawget(GlassMailDB, "suiteOwn"), nil, "a junk override is dropped at load")
check(not GM.Settings.SetSkin("class"), "class can't be chosen in Glass Mail")

-- Stock while following: declined, the mail windows bare, our own windows glass.
check(GM.Settings.SetSkin("stock"), "Blizzard's own, while following")
r = lastReport(f)
check(r.declined == "Blizzard's own" and r.built == nil and r.reason == nil, "  declined, nothing built reported")
eq(r.own.tint, nil, "  not a tint override")
check(not GM._test.skin.skinned[MailFrame].panel:IsShown(), "  the mail window bare")
SlashCmdList.GLASSMAIL("mail")
check(close(GM._test.skin.own[1].g.tint._color[4], 0.7), "  our own window glass, smoked (Glass UI's smoked)")
GM.Settings.SetSkin("suite")
r = lastReport(f)
check(r.built == "pearl" and r.declined == nil, "back to the suite: built again, nothing declined")

-- The accent: our picker's headers, never the folder highlight or Blizzard's labels.
GM.Store.AddRecent("Kaleid Sumner")
GM.Address.button:GetScript("OnClick")(GM.Address.button)
local picker = GM._test.address.ui()
local function header()
    for _, row in ipairs(picker.rows) do
        if row:IsShown() and not row.name then return row.label end
    end
end
local h = header()
check(h ~= nil, "the picker shows a section header")
local hc = { h:GetTextColor() }
check(close(hc[1], 1) and close(hc[2], 0.82), "  gold by default")
change(f, "accent", "ice")
hc = { header():GetTextColor() }
check(close(hc[1], 0.6) and close(hc[3], 0.9), "  ice, live, Glass UI's colour")
eq(lastReport(f).look.accent, "ice", "  reported")
f.S.Accent = function() error("boom") end
change(f, "accent", "ice")
hc = { header():GetTextColor() }
check(close(hc[1], 0.65) and close(hc[3], 0.905), "Accent throwing: our ice, still ice")
f.S.Accent = function() return { 0 / 0, 1, 1 } end
change(f, "accent", "ice")
hc = { header():GetTextColor() }
check(close(hc[1], 0.65), "  a bad colour: our ice")
change(f, "accent", "neon")
hc = { header():GetTextColor() }
check(close(hc[1], 1) and close(hc[2], 0.82), "an accent we don't know: gold")
eq(lastReport(f).look.accent, "gold", "  reported gold")
local sel = GM._test.window.ui().folders.sent.selected._color
check(close(sel[1], 1) and close(sel[2], 0.82), "the folder highlight stays gold")
change(f, "accent", "gold")

-- The options page while following.
local O = GM.Options._test
O.panel:Show()
local radios = O.skinRadios
eq(#radios, 4, "options: Glass UI, then our three")
eq(radios[1].label:GetText(), "Glass UI (Clear glass)", "  the first names the suite's tint")
check(radios[1]:GetChecked(), "  selected while there's no override")
change(f, "tint", "smoked")
eq(radios[1].label:GetText(), "Glass UI (Smoked glass)", "  updated live by a suite event")
SlashCmdList.GLASSMAIL("skin smoked")
check(radios[3]:GetChecked() and not radios[1]:GetChecked(), "  an override equal to the suite's tint shows as ours")
radios[1]:GetScript("OnClick")(radios[1])
eq(rawget(GlassMailDB, "suiteOwn"), nil, "  clicking Glass UI clears it")
check(O.status:GetText():find("Follows Glass UI", 1, true) ~= nil, "  the status line")
O.openSuite:GetScript("OnClick")(O.openSuite)
eq(f.opened, 1, "  Set in Glass UI opens its page")
O.panel:Hide()

-- Combat: a stock switch waits for its end; glass-to-glass applies at once.
change(f, "tint", "clear")
OpenMailFrame:Show()
updates = OpenMailFrame._updates or 0
WoW.fire("PLAYER_REGEN_DISABLED")
GM.Settings.SetSkin("stock")
eq(GM.db.suiteOwn and GM.db.suiteOwn.skin, "stock", "in combat: the choice is saved")
eq(GM.Skin.Applied(), "clear", "  the look waits")
check(GM.Skin.Pending(), "  pending")
eq(OpenMailFrame._updates or 0, updates, "  the letter isn't re-shown")
GM.Settings.SetInboxGuides(false)
GM.Settings.SetInboxGuides(true)
eq(GM.Skin.Applied(), "clear", "  another refresh paints the applied look")
change(f, "tint", "smoked")
eq(GM.Skin.Applied(), "clear", "  a suite event too")
WoW.fire("PLAYER_REGEN_ENABLED")
eq(GM.Skin.Applied(), "stock", "combat's end: applied")
check(not GM.Skin.Pending(), "  nothing pending")
eq(lastReport(f).declined, "Blizzard's own", "  reported")
WoW.fire("PLAYER_REGEN_DISABLED")
GM.Settings.SetSkin("suite")
GM.Settings.SetSkin("stock")
check(not GM.Skin.Pending() and GM.Skin.Applied() == "stock", "a switch and back in combat: cancelled")
GM.Settings.SetSkin("suite")
WoW.fire("PLAYER_REGEN_ENABLED")
eq(GM.Skin.Applied(), "smoked", "  then applied at combat's end")
WoW.fire("PLAYER_REGEN_DISABLED")
updates = OpenMailFrame._updates or 0
change(f, "tint", "clear")
eq(GM.Skin.Applied(), "clear", "in combat, glass to glass: at once")
eq(OpenMailFrame._updates or 0, updates, "  without re-showing the letter")
WoW.fire("PLAYER_REGEN_ENABLED")
OpenMailFrame:Hide()

-- Local stock, no override: valid suite tint shows glass; unknown falls back to stock (in combat: waits).
GM = boot(fake(), { skin = "stock" })
eq(GM.Skin.Applied(), "clear", "a local stock, following: the suite's glass")
eq(rawget(GlassMailDB, "suiteOwn"), nil, "  the old local choice isn't made an override")
f = nil

-- Not following, and an incompatible or broken Glass UI -------------------------------------
f = fake({ follow = false })
GM = boot(f, { skin = "smoked" })
eq(GM.Suite.Status(), "not-following", "Glass UI's switch off: not following")
eq(GM.GlassBuild().preset, "pearl", "  our Pearl")
eq(GM.Skin.Applied(), "smoked", "  our own look")
check(close(tintOf(GM)[4], GM.Skin.BODIES.smoked.tint[4]), "  in our own body, not Glass UI's")
check(not GM.Suite.SetOwn("clear") and rawget(GlassMailDB, "suiteOwn") == nil, "  no override can be set")
r = lastReport(f)
check(r and r.built == nil and r.reason == nil and r.declined == nil, "  reported: nothing built for the suite")
change(f, "tint", "class")
eq(GM.Skin.Applied(), "smoked", "  a suite event changes nothing")

GM = boot(fake({ api = 2 }))
eq(GM.Suite.Status(), "incompatible", "API 2: incompatible")
eq(GM.Skin.Applied(), "clear", "  our own look")
f = fake({ throw = { Theme = true } })
GM = boot(f)
eq(GM.Suite.Status(), "not-following", "Theme throwing: not following")
f = fake({ noLook = true })
GM = boot(f, { skin = "smoked" })
check(GM.Suite.Following() and GM.Skin.Applied() == "smoked", "no Look: following, our own skin")
f = fake({ throw = { Look = true } })
GM = boot(f)
check(GM.Suite.Following() and GM.Skin.Applied() == "clear", "Look throwing: the same")

-- A followed preset LibGlass can't build: clean, reported.
f = fake({ preset = "neon" })
GM = boot(f)
local b = GM.GlassBuild()
check(b.wanted == "neon" and b.preset == "clean" and b.failed == "build-failed", "an unknown preset: clean instead")
r = lastReport(f)
check(r.built == nil and r.reason == "build-failed" and r.minor == 11, "  reported, with LibGlass's MINOR")
GM.Settings.SetSkin("stock")
GM.Settings.SetSkin("suite")
eq(lastReport(f).reason, "build-failed", "  stock and back: the original result again")

done("test_suite")
