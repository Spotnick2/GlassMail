-- Address.lua: S1's completion in the To box (PLAN.md, "S1: completing a name
-- as you type"), against the stubs' Blizzard autocomplete (wow_stubs.lua).
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GM = loadAddon()
local Address = GM.Address
local db = GlassMailDB
local box = SendMailNameEditBox

-- The box's text, its highlighted part and the cursor (bytes).
local function state()
    return ("%s [%s] @%d"):format(box:GetText(), box._highlighted or "", box:GetCursorPosition())
end
local function fresh()
    WoW.autocomplete, WoW.charFirst, box._ime = {}, nil, nil
    box:SetText("")
    WoW.focus = box
end
local function typed(s) WoW.typeText(box, s) end
local function enter() box:GetScript("OnEnterPressed")(box) end
local function dropdown() return AutoCompleteBox:IsShown() end

-- Another WoW account's alt, from AltStable: Blizzard knows nothing of it.
local altstable = { { guid = "Player-2-VVV", name = "Vex Morrow", realm = "Doomhowl", faction = "Horde",
    provenance = "own-account" } }
rawset(_G, "AltStable", { PUBLIC_API_VERSION = 1, PUBLIC_API_FEATURES = { provenance = true },
    GetCharacters = function() return altstable end })

fresh()
typed("ve")
eq(state(), "Vex Morrow [x Morrow] @2", "another account's alt completes, the rest highlighted, the cursor after the typed part")
check(not dropdown(), "  Blizzard's dropdown stays hidden")
WoW.charFirst = true
box:SetText("")
typed("ve")
eq(state(), "Vex Morrow [x Morrow] @2", "  OnChar before OnTextChanged: the same")
WoW.charFirst = nil

typed("x")
eq(state(), "Vex Morrow [ Morrow] @3", "the next matching letter keeps it")
typed("q")
eq(state(), "Vexq [] @4", "a letter that doesn't match leaves what was typed")

fresh()
typed("ve")
enter()
eq(box:GetText(), "Vex Morrow", "Enter keeps the completion")
eq(WoW.focus, nil, "  and moves on (Blizzard's: the subject)")

fresh()
typed("VE")
eq(state(), "Vex Morrow [x Morrow] @2", "the case is the name's")

-- Blizzard's own completion wins -------------------------------------------------
fresh()
WoW.autocomplete = { "Vexa Guildie" }
typed("ve")
eq(state(), "Vexa Guildie [xa Guildie] @2", "a name Blizzard knows: its completion, unchanged")
check(dropdown(), "  its dropdown shown")
enter()
eq(box:GetText(), "Vexa Guildie", "  Enter takes Blizzard's entry")

-- Blizzard's exact match: it adds nothing, the cursor is at the end, but the name is Blizzard's.
fresh()
WoW.autocomplete = { "Vex Mo" }
typed("Vex Mo")
eq(state(), "Vex Mo [] @6", "Blizzard's exact match isn't lengthened into ours")
check(WoW.autocompleteCalls > 0, "  (Blizzard's source was asked)")

-- A dropdown left from the previous letter ----------------------------------------
-- "v" has Blizzard's "Va Guild"; "ve" has nothing of Blizzard's but our Vex.
fresh()
WoW.autocomplete = { "Va Guild" }
WoW.charFirst = true
typed("v")
check(dropdown(), "Blizzard's dropdown shows for the first letter")
typed("e")
eq(state(), "Ve [] @2", "OnChar first, the dropdown still up from the last letter: not completed")
check(not dropdown(), "  then Blizzard's update hides it")
enter()
eq(box:GetText(), "Ve", "  and Enter keeps what was typed, no stale entry")
WoW.charFirst = nil
fresh()
WoW.autocomplete = { "Va Guild" }
typed("ve")
eq(state(), "Vex Morrow [x Morrow] @2", "OnTextChanged first: the dropdown is gone by OnChar, so it completes")

-- Nothing --------------------------------------------------------------------------
fresh()
box._ime = true
typed("ve")
eq(state(), "ve [] @2", "IME composition: nothing")

fresh()
box:SetText("Vx")
box:SetCursorPosition(1)
WoW.typeInto(box, "e")
eq(state(), "Vex [] @2", "typing in the middle: nothing")
box:SetText("Vxa")
box:HighlightText(1, 2)
WoW.typeInto(box, "e")
eq(state(), "Vea [] @2", "a selection in the middle replaced: nothing")
eq(Address.Complete(""), nil, "Complete: an empty text, nil")
eq(Address.Complete(WoW.Secret("ve")), nil, "  a secret one, nil")
eq(Address.Complete("Vex Morrow"), nil, "  a whole name, nil")

-- The fill's whole highlight, then a letter: a selection through the end.
fresh()
box:SetText("Kaleid Sumner")
box:HighlightText()
typed("v")
eq(state(), "Vex Morrow [ex Morrow] @1", "the last-recipient fill's highlight typed over: completes")
-- A pick, highlighted whole, typed over.
Address.Pick("Somebody Else")
box:HighlightText()
typed("ve")
eq(state(), "Vex Morrow [x Morrow] @2", "a pick typed over: completes")

-- Which names ------------------------------------------------------------------------
-- With AltStable loaded, its list is the registry's (live, never saved).
local function alt(guid, name) altstable[#altstable + 1] = { guid = guid, name = name, realm = "Doomhowl",
    faction = "Horde", provenance = "own-account" } end
alt("Player-2-AAA", "Vex Ash")
alt("Player-2-LLL", "Zed Alt")
alt("Player-2-LLM", "Zed Altman")
fresh()
typed("ve")
eq(state(), "Vex Ash [x Ash] @2", "name order: the first")
fresh()
typed("zed alt")
eq(state(), "Zed Alt [] @7", "the text already one of my characters: nothing more, a longer one beside it")
eq(Address.Complete("zed al"), "Zed Alt", "  a shorter text: the first in order")

-- Own characters only, as the picker's: never this one, a hidden or unreachable one,
-- a recent or a guild member.
altstable = {
    { guid = WoW.playerGUID, name = "Karuzo Morphisto", realm = "Doomhowl", faction = "Horde", provenance = "self" },
    { guid = "Player-2-HHH", name = "Hid Den", realm = "Doomhowl", faction = "Horde", hidden = true,
        provenance = "own-account" },
    { guid = "Player-2-AAA", name = "Ali Side", realm = "Doomhowl", faction = "Alliance", provenance = "own-account" },
    { guid = "Player-2-PPP", name = "Pvp Guy", realm = "Elsewhere PvP", faction = "Horde", provenance = "own-account" },
    { guid = "Player-2-OOO", name = "Other Realm", realm = "Doomhowl Two", faction = "Horde", provenance = "own-account" },
    { guid = "Player-2-TTT", name = "Third Party", realm = "Doomhowl", faction = "Horde", provenance = "third-party" },
}
db.recents["rec ent"] = { name = "Rec Ent", day = db.playDay }
WoW.guild = { "Gil Member" }
WoW.friends = { { name = "Fren Dly" } }
for _, t in ipairs({ "kar", "hid", "ali", "pvp", "thi", "rec", "gil", "fre" }) do
    fresh()
    typed(t)
    eq(box:GetText(), t, "never offered: " .. t)
end
fresh()
typed("oth")
eq(box:GetText(), "Other Realm", "a reachable alt on another realm of this ruleset is")
WoW.guild = nil
-- Names as the picker shows them: this realm's suffix dropped, another realm's never offered.
alt("Player-2-DSH", "Dash Alt-Doomhowl")
alt("Player-2-FAR", "Far Off-Elsewhere")
fresh()
typed("das")
eq(state(), "Dash Alt [h Alt] @3", "a name with this realm's suffix completes without it")
fresh()
typed("far")
eq(box:GetText(), "far", "  one with another realm's: nothing")

-- Blizzard's source missing, or throwing -------------------------------------------
local saved = C_AutoComplete
rawset(_G, "C_AutoComplete", nil)
fresh()
typed("oth")
eq(box:GetText(), "oth", "C_AutoComplete missing: nothing (we can't tell, so we don't compete)")
rawset(_G, "C_AutoComplete", {})
fresh()
typed("oth")
eq(box:GetText(), "oth", "  its function missing: nothing")
rawset(_G, "C_AutoComplete", saved)
local list = AUTOCOMPLETE_LIST
rawset(_G, "AUTOCOMPLETE_LIST", nil)
fresh()
typed("oth")
eq(box:GetText(), "oth", "  the mail list missing: nothing")
rawset(_G, "AUTOCOMPLETE_LIST", list)
rawset(_G, "C_AutoComplete", { GetAutoCompleteResults = function() error("boom") end })
fresh()
typed("oth")
eq(box:GetText(), "oth", "it throwing: the box as typed")
check(GM.failures["address complete"] ~= nil, "  and the failure recorded")
rawset(_G, "C_AutoComplete", saved)

-- A multi-byte character in the typed part: positions in bytes.
altstable = { { guid = "Player-2-ZOE", name = "Zoë Ash", realm = "Doomhowl", faction = "Horde",
    provenance = "own-account" } }
fresh()
typed("zoë")
eq(state(), "Zoë Ash [ Ash] @4", "a multi-byte typed prefix: the highlight from its byte length")

-- The debug trace: off, nothing; on, numbered lines, one before our SetText.
fresh()
newChat()
typed("zo")
eq(#newChat(), 0, "debug off: no trace")
SlashCmdList.GLASSMAIL("debug on")
fresh()
newChat()
typed("zo")
local all = table.concat(newChat(), " / ")
check(all:find("To box %d+: OnTextChanged, userInput true; cursor 1 of 1 bytes") ~= nil, "debug on: OnTextChanged traced")
check(all:find("To box %d+: OnChar; cursor 2 of 2 bytes, dropdown false") ~= nil, "  OnChar too")
check(all:find("To box %d+: completing Zoë Ash; cursor 2 of 2") ~= nil, "  and our completion, before its SetText")
SlashCmdList.GLASSMAIL("debug off")

rawset(_G, "AltStable", nil)
done("test_complete")
