-- Core/Summary.lua: what a character's mailbox holds that is worth keeping,
-- from its snapshot (Core/Memory.lua). AltStable's rule exactly
-- (AltStable/Core.lua, ScanMail): the mails with items or money and time left,
-- their count, their money and the soonest expiry. M3 moves it to LibMailbox;
-- AltStable keeps its own mail_* fields.

GlassMail = GlassMail or {}
local GM = GlassMail
local Summary = {}
GM.Summary = Summary

-- { count, money, soonest } over the snapshot's mails at `now`, or nil when
-- none qualifies.
function Summary.Of(snapshot, now)
    if type(snapshot) ~= "table" or type(snapshot.mails) ~= "table" then return nil end
    local count, money, soonest = 0, 0, nil
    for _, m in ipairs(snapshot.mails) do
        local hasStuff = (m.items and #m.items > 0) or (m.money or 0) > 0
        if hasStuff and m.expires > now then
            count = count + 1
            money = money + (m.money or 0)
            if not soonest or m.expires < soonest then soonest = m.expires end
        end
    end
    if count == 0 then return nil end
    return { count = count, money = money, soonest = soonest }
end
