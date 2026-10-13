-- X3 trade block, at login: the last session ended while our block held
-- (the saved claim), so it is undone; nothing else is touched.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.cvars.blockTrades = "1"
local GM = loadAddon({ charDB = { tradeBlocked = true } })
eq(WoW.cvars.blockTrades, "0", "our block left from the last session: undone at login")
eq(GlassMailCharDB.tradeBlocked, nil, "  the claim cleared")
check(GM.Comforts ~= nil, "  (Comforts started)")

-- A refused restore at login keeps the claim for the next try.
WoW.cvars.blockTrades, WoW.cvarRefuse = "1", true
GlassMailCharDB.tradeBlocked = true
GM.Comforts.Start()
eq(WoW.cvars.blockTrades, "1", "the restore refused at login: still blocked")
eq(GlassMailCharDB.tradeBlocked, true, "  the claim kept")
WoW.cvarRefuse = nil
WoW.fire("PLAYER_REGEN_ENABLED")
eq(WoW.cvars.blockTrades, "0", "  retried on the next change")

done("test_comforts_login")
