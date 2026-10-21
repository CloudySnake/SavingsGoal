-- WoW API stubs so SavingsGoal's logic can run under plain Lua.
-- Only core.lua and goals.lua are loaded in tests (no UI, no broker).

local M = {}

M.state = {
    money = 0,                 -- copper, returned by GetMoney()
    playerName = "Testrogue",
    realmName = "Testrealm",
    inbox = {},                -- { sender=, subject=, money= }
    time = 1000000,            -- GetTime()
}

M.hooks = {}   -- hooksecurefunc registry
M.frames = {}  -- CreateFrame registry (for inspection)

function M.reset()
    M.state.money = 0
    M.state.playerName = "Testrogue"
    M.state.realmName = "Testrealm"
    M.state.inbox = {}
    M.state.time = 1000000
    M.hooks = {}
    M.frames = {}
end

function M.callHook(name, ...)
    for _, fn in ipairs(M.hooks[name] or {}) do fn(...) end
end

-- ------------------------------------------------------------ API surface --
function GetMoney() return M.state.money end
function UnitName(unit) return M.state.playerName end
function GetRealmName() return M.state.realmName end
function GetTime() return M.state.time end

-- WoW's date() is os.date with the same signature
function date(fmt, t) return os.date(fmt, t) end
function time(t) return os.time(t) end

function GetInboxNumItems() return #M.state.inbox end
function GetInboxHeaderInfo(i)
    local m = M.state.inbox[i]
    if not m then return nil end
    -- packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft,
    -- hasItem, wasRead, wasReturned, textCreated, canReply, isGM
    return nil, nil, m.sender, m.subject, m.money, 0, 30, false, true, false, false, true, false
end

function hooksecurefunc(name, fn)
    M.hooks[name] = M.hooks[name] or {}
    table.insert(M.hooks[name], fn)
end

local function newFrame()
    local f = { _scripts = {}, _events = {} }
    function f:SetScript(k, fn) self._scripts[k] = fn end
    function f:GetScript(k) return self._scripts[k] end
    function f:RegisterEvent(e) self._events[e] = true end
    function f:UnregisterEvent(e) self._events[e] = nil end
    return f
end

function CreateFrame(ftype, name, parent, template)
    local f = newFrame()
    table.insert(M.frames, f)
    return f
end

return M
