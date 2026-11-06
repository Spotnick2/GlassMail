-- Core/Names.lua: the comparison key and the display form of a mail address.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GM = loadAddon()
local Names = GM.Names

eq(Names.Key("Kaleid Sumner"), "kaleid sumner", "lower-cased")
eq(Names.Key("  Kaleid   Sumner \t"), "kaleid sumner", "trimmed, inner spaces collapsed")
eq(Names.Key("KALEID SUMNER"), Names.Key("kaleid sumner"), "case doesn't matter")
eq(Names.Key("Kaleid Sumner-Doomhowl"), "kaleid sumner-doomhowl", "a realm suffix is kept")
check(Names.Key("Kaleid Sumner-Doomhowl") ~= Names.Key("Kaleid Sumner"), "  so it never merges with the plain name")
eq(Names.Key(WoW.Secret("name")), nil, "a secret name is never keyed")
eq(Names.Key(""), nil, "a blank name has no key")
eq(Names.Key("   "), nil, "  nor one of spaces")
eq(Names.Key(42), nil, "  nor a non-string")

eq(Names.Display("  Kaleid Sumner "), "Kaleid Sumner", "the display form is trimmed, case kept")
eq(Names.Display(WoW.Secret("name")), nil, "a secret name has no display form")

done("test_names")
