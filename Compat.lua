-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else calls through
-- GlassMailbox.API. Nothing is injected into _G.
--
-- A subset of GlassChat's Compat.lua (same measured rules); lift more from
-- there, or from GlassRaidFrames', when needed rather than rewriting.

GlassMailbox = GlassMailbox or {}
local GM = GlassMailbox
local API = {}
GM.API = API

-- The build the notes in docs/ were measured on. Bump only after re-measuring
-- in game; tests/test_toc.lua pins the same literal.
GM.MEASURED_ON_BUILD = "1.60.1.70291"

function API.Print(msg)
    print("|cff7fd4ffGlassMailbox|r " .. msg)
end

-- True for a Retail secret value. Such a value may be handed back to the
-- client (SetText) but never compared, concatenated, tostring'd,
-- pattern-matched or truth-tested in Lua. GetMoney() can return one.
function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

function API.ClientBuild()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

-- RegisterEvent throws on an unknown name and returns false on a refusal.
-- Both count as failure, and every failure is reported: a silently missing
-- handler is the bug this exists to prevent.
GM.eventFailures = {}

local function report(name, why)
    table.insert(GM.eventFailures, name .. ": " .. why)
    API.Print("|cffff6060could not register|r " .. name .. " (" .. why .. ")")
end

function API.RegisterEvents(frame, events)
    for _, name in ipairs(events) do
        local ok, registered = pcall(frame.RegisterEvent, frame, name)
        if not ok then report(name, tostring(registered))
        elseif registered == false then report(name, "refused") end
    end
end

-- The one place failures are recorded (first error per key), read by
-- /gmail failures and the tests.
GM.failures = GM.failures or {}
function API.Fail(key, err)
    if GM.failures[key] == nil then GM.failures[key] = tostring(err) end
end

-- The player's full name, "First Surname", or nil. The client has given it
-- whole in UnitName's first return, or split across both returns (AltStable
-- #56). Lifted from GlassChat's API.PlayerFullName. It is also the mail
-- address: Forever names carry no realm.
function API.PlayerFullName()
    local name, second = UnitName("player")
    if API.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    if name:find(" ") then return name end
    if not API.IsSecret(second) and type(second) == "string" and second ~= "" then
        return name .. " " .. second
    end
    return name
end

-- An addon's TOC Version, or nil (absent API, error, secret, not a string).
function API.AddOnVersion(addon)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, addon, "Version")
    if not ok or API.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end

-- A frame from a template, and whether the template really applied: a missing
-- template doesn't throw, it returns a bare frame, so `proof` names a field
-- the template makes (GlassUnitFrames' API.SafeFrame).
function API.SafeFrame(ftype, parent, template, proof)
    local ok, f = pcall(CreateFrame, ftype, nil, parent, template)
    if ok and f then return f, (proof == nil) or f[proof] ~= nil end
    return CreateFrame(ftype, nil, parent), false
end

-- A plain Blizzard button (UIPanelButtonTemplate, as GlassPanel uses it).
function API.Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end
