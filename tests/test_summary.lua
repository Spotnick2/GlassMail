-- Core/Summary.lua: AltStable's mail rule over a snapshot (PLAN.md, "Inbox (X1)").
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local GM = loadAddon()
local Of = GM.Summary.Of
local NOW = 1793000000

local function mail(over)
    local m = { expires = NOW + 86400, type = "player", money = 0, items = {} }
    for k, v in pairs(over or {}) do m[k] = v end
    return m
end

eq(Of({ mails = {} }, NOW), nil, "no mails: no summary")
eq(Of({ mails = { mail() } }, NOW), nil, "a letter with nothing in it doesn't count")
eq(Of({ mails = { mail({ money = 500, expires = NOW - 1 }) } }, NOW), nil, "an expired mail doesn't count")
eq(Of({ mails = { mail({ money = 500, expires = NOW }) } }, NOW), nil, "  nor one expiring this second")

local s = Of({ mails = {
    mail({ money = 500, expires = NOW + 3 * 86400 }),
    mail({ items = { { id = 2589, count = 5 } }, expires = NOW + 2 * 86400 }),
    mail({ subject = "hello" }),
    mail({ money = 100, items = { { id = 1, count = 1 } }, expires = NOW + 9 * 86400 }),
} }, NOW)
eq(s.count, 3, "money only, items only, both: three count")
eq(s.money, 600, "  their money summed")
eq(s.soonest, NOW + 2 * 86400, "  the soonest expiry")
eq(Of(nil, NOW), nil, "no snapshot: nil")

done("test_summary")
