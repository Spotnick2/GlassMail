-- Subject.lua: S2, the subject filled from the first item or the gold (PLAN.md,
-- "S2: the subject", #59).
--
-- Client 1.60.1.70959 moved Blizzard's own subject fill under
-- C_Mail.IsCODEnabled() (MailFrame.lua:1323), and COD is off on Forever, so an
-- attached item no longer names the mail. While COD is off this applies
-- Blizzard's rule itself; and, from the money box, the gold sent (never a COD
-- amount). Only an empty subject or the one written here is ever changed.

GlassMail = GlassMail or {}
local GM = GlassMail
local API = GM.API
local Subject = {}
GM.Subject = Subject

-- What the box held after our last write (its 64 letters may cut a title), and
-- the title written; both dropped once the subject is the player's.
local ours, oursFor

local function str(v)
    if API.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

-- Blizzard's item title (MailFrame.lua:1302-1309): the first attachment with a
-- name, "Name (count)" when more than one.
local function itemTitle()
    for a = 1, rawget(_G, "ATTACHMENTS_MAX_SEND") or 12 do
        if HasSendMailItem(a) then
            local name, _, _, count = GetSendMailItem(a)
            name = str(name)
            if name then
                if API.IsSecret(count) or type(count) ~= "number" then return nil end
                if count <= 1 then return name end
                return name .. " (" .. count .. ")"
            end
        end
    end
    return nil
end

-- The gold to send, in the client's words; never a COD amount.
local function goldTitle()
    local sendMoney, money = rawget(_G, "SendMailSendMoneyButton"), rawget(_G, "SendMailMoney")
    if not (sendMoney and money and sendMoney:GetChecked()) then return nil end
    local copper = MoneyInputFrame_GetCopper(money)
    if API.IsSecret(copper) or type(copper) ~= "number" or copper <= 0 then return nil end
    return str(C_CurrencyInfo.GetCoinText(copper, ", "))
end

-- The subject Glass Mail would give the draft now, or nil.
function Subject.Wanted()
    local text
    if not C_Mail.IsCODEnabled() then text = itemTitle() end
    text = text or goldTitle()
    if not text or text:find("|", 1, true) then return nil end
    return text
end

local function refresh()
    local b = rawget(_G, "SendMailSubjectEditBox")
    if not b then return end
    local current = b:GetText()
    if API.IsSecret(current) then ours, oursFor = nil, nil; return end
    current = current or ""
    if current ~= "" and current ~= ours then ours, oursFor = nil, nil; return end   -- the player's
    if not GM.db.subjectFill then
        if current == "" then ours, oursFor = nil, nil end
        return
    end
    local want = Subject.Wanted()
    if want then
        if current == ours and want == oursFor then return end   -- already written
        b:SetText(want)
        local kept = b:GetText()
        if API.IsSecret(kept) then ours, oursFor = nil, nil; return end
        ours, oursFor = kept, want
    else
        if current ~= "" then b:SetText("") end
        ours, oursFor = nil, nil
    end
end

-- A key typed in the subject makes it the player's, even if it comes back to
-- our text.
local function typed(_, userInput)
    if userInput then ours, oursFor = nil, nil end
end

local function safeRefresh()
    local ok, err = pcall(refresh)
    if not ok then API.Fail("subject", err) end
end
Subject.Refresh = safeRefresh

function Subject.Start()
    hooksecurefunc("SendMailFrame_Update", safeRefresh)
    hooksecurefunc("SendMailRadioButton_OnClick", safeRefresh)
    local subject = rawget(_G, "SendMailSubjectEditBox")
    if subject then subject:HookScript("OnTextChanged", typed) end
    for _, n in ipairs({ "SendMailMoneyGold", "SendMailMoneySilver", "SendMailMoneyCopper" }) do
        local box = rawget(_G, n)
        if box then box:HookScript("OnTextChanged", safeRefresh) end
    end
end

Subject._test = {
    Ours = function() return ours end,
    Reset = function() ours, oursFor = nil, nil end,
}
