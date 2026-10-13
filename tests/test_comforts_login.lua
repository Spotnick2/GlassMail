-- X3 trade block, at login: the last session ended while our block held
-- (the saved claim), so it is undone; nothing else is touched.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

WoW.cvars.blockTrades = "1"
local GM = loadAddon({ charDB = { tradeBlocked = true } })
eq(WoW.cvars.blockTrades, "0", "our block left from the last session: undone at login")
eq(GlassMailCharDB.tradeBlocked, nil, "  the claim cleared")
check(GM.Comforts ~= nil, "  (Comforts started)")

done("test_comforts_login")
