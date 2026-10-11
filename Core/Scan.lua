-- Core/Scan.lua: the inbox as plain values, read without side effects.
--
-- Never calls GetInboxText (it marks mail read, FOREVER-PROBE session 3).
-- There is no stable mail ID: an index is good until the next
-- MAIL_INBOX_UPDATE, so each mail carries a fingerprint, and a remembered
-- target is found again by fingerprint before any action (CLAUDE.md).

GlassMailbox = GlassMailbox or {}
local GM = GlassMailbox
local API = GM.API
local Scan = {}
GM.Scan = Scan

-- The six AH subjects (session 5), by global name: localized with the client.
-- AH mail is classified by these, never by its faction-specific sender.
local AH_SUBJECTS = {
    "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_INVOICE_MAIL_SUBJECT", "AUCTION_OUTBID_MAIL_SUBJECT",
    "AUCTION_REMOVED_MAIL_SUBJECT", "AUCTION_SOLD_MAIL_SUBJECT", "AUCTION_WON_MAIL_SUBJECT",
}

-- A format string as an anchored Lua pattern: %s, %d, %i and %1$s become
-- ".+", %% a literal %, every other magic character escaped.
local function templatePattern(fmt)
    local p = fmt:gsub("%%%%", "\2"):gsub("%%%d*%$?[sdi]", "\1")
    p = p:gsub("[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
    p = p:gsub("\1", ".+"):gsub("\2", "%%%%")
    return "^" .. p .. "$"
end

local patterns   -- built once, from the globals that exist
local function isAH(subject)
    if not patterns then
        patterns = {}
        for _, name in ipairs(AH_SUBJECTS) do
            local fmt = rawget(_G, name)
            if type(fmt) == "string" and fmt ~= "" then patterns[#patterns + 1] = templatePattern(fmt) end
        end
    end
    for _, p in ipairs(patterns) do
        if subject:find(p) then return true end
    end
    return false
end

-- Fields joined with a length prefix each, so a delimiter inside a subject or
-- a link can't make two different mails look the same.
local function encode(parts)
    local out = {}
    for i, v in ipairs(parts) do
        local s = tostring(v)
        out[i] = #s .. ":" .. s
    end
    return table.concat(out)
end

-- The fingerprint over what identifies a mail for this session: sender,
-- subject, money, COD, returned, and each occupied slot's number, link and
-- count. Not daysLeft (it drifts) nor wasRead (a take flips it).
local function fingerprint(m)
    local parts = { m.sender, m.subject, m.money, m.cod, m.wasReturned and 1 or 0 }
    for _, it in ipairs(m.items) do
        parts[#parts + 1] = it.slot
        parts[#parts + 1] = it.link
        parts[#parts + 1] = it.count
    end
    return encode(parts)
end
Scan.Fingerprint = fingerprint

local function secret(...)
    for i = 1, select("#", ...) do
        if API.IsSecret((select(i, ...))) then return true end
    end
    return false
end

local function attachments(i)
    local items, resolved = {}, true
    local max = rawget(_G, "ATTACHMENTS_MAX_RECEIVE") or 16
    for a = 1, max do
        local _, itemID, _, count, _, _, isCurrency = GetInboxItem(i, a)
        -- Secrecy first: a secret may not even be compared (CLAUDE.md).
        if secret(itemID, count, isCurrency) then return items, false end
        -- Occupied when it has an ID: an uncached item's name is "".
        if itemID ~= nil then
            local link = GetInboxItemLink(i, a)
            if secret(link) then return items, false end
            if link == nil then resolved = false end
            items[#items + 1] = { slot = a, itemID = itemID, link = link, count = count or 1,
                isCurrency = isCurrency == true }
        end
    end
    return items, resolved
end

-- One mail, or nil past the loaded inbox. `resolved` false (a secret field, an
-- attachment without a link) means no fingerprint: nothing is dispatched
-- against it and no scan holding it confirms anything.
local function readMail(i)
    local _, _, sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned, _, canReply, isGM =
        GetInboxHeaderInfo(i)
    -- Secrecy first, before any comparison, truth test or copy (CLAUDE.md):
    -- such a mail is kept only as unresolved, with no values.
    if secret(sender, subject, money, cod, daysLeft, itemCount, wasRead, wasReturned, canReply, isGM) then
        return { index = i, resolved = false, items = {} }
    end
    if sender == nil and subject == nil and money == nil then return nil end
    local m = { index = i, daysLeft = daysLeft, wasRead = wasRead == true, wasReturned = wasReturned == true,
        canReply = canReply == true, isGM = isGM == true, items = {} }
    m.sender, m.subject, m.money, m.cod = sender or "", subject or "", money or 0, cod or 0
    local resolved
    if itemCount then m.items, resolved = attachments(i) else resolved = true end
    if m.isGM then m.type = "system"
    elseif isAH(m.subject) then m.type = "ah"
    elseif not m.canReply then m.type = "system"
    else m.type = "player" end
    m.resolved = resolved
    if resolved then m.fp = fingerprint(m) end
    return m
end

-- The loaded inbox: { loaded, total, mails, resolved }. `resolved` is false
-- when any mail is.
function Scan.Inbox()
    local loaded, total = GetInboxNumItems()
    if secret(loaded, total) then return { loaded = 0, total = 0, mails = {}, resolved = false } end
    local snap = { loaded = loaded or 0, total = total or loaded or 0, mails = {}, resolved = true }
    for i = 1, snap.loaded do
        local m = readMail(i)
        if m then
            snap.mails[#snap.mails + 1] = m
            if not m.resolved then snap.resolved = false end
        end
    end
    return snap
end

-- { [fp] = n } over the resolved mails.
function Scan.Count(snap)
    local n = {}
    for _, m in ipairs(snap.mails) do
        if m.fp then n[m.fp] = (n[m.fp] or 0) + 1 end
    end
    return n
end

-- The fingerprint the mail should have after taking its money ("money") or
-- slot k: the same mail without it. The second return is true when that
-- empties a mail that had items: the server may then remove it (session 3),
-- or keep it, empty, when it has letter text (Blizzard deletes such a mail
-- itself when the letter closes, MailFrame.lua:581). A money-only mail stays
-- at money 0 (session 3).
function Scan.Residual(m, kind, slot)
    local after = { sender = m.sender, subject = m.subject, money = m.money, cod = m.cod,
        wasReturned = m.wasReturned, items = {} }
    for _, it in ipairs(m.items) do
        if not (kind == "item" and it.slot == slot) then after.items[#after.items + 1] = it end
    end
    if kind == "money" then after.money = 0 end
    return fingerprint(after), #m.items > 0 and #after.items == 0 and after.money == 0
end

GM._test = GM._test or {}
GM._test.scan = { templatePattern = templatePattern, encode = encode, resetPatterns = function() patterns = nil end }
