-- WoW API stubs so SavingsGoal's logic can run under plain Lua.
-- Only core.lua and goals.lua are loaded in tests (no UI, no broker).

local M = {}

M.state = {
    money = 0,                 -- copper, returned by GetMoney()
    playerName = "Testrogue",
    realmName = "Testrealm",
    inbox = {},                -- { sender=, subject=, money=, cod= }
    time = 1000000,            -- GetTime()
    repairCost = 0,            -- GetRepairAllCost()
    taxiCost = 0,              -- TaxiNodeCost()
    lootSlots = {},            -- { coin=bool, quantity=, name= } per loot-window slot
}

M.hooks = {}   -- hooksecurefunc registry
M.frames = {}  -- CreateFrame registry (for inspection)
M.fontstrings = {} -- CreateFontString registry (for inspection)

function M.reset()
    M.state.money = 0
    M.state.playerName = "Testrogue"
    M.state.realmName = "Testrealm"
    M.state.inbox = {}
    M.state.time = 1000000
    M.state.repairCost = 0
    M.state.taxiCost = 0
    M.state.lootSlots = {}
    M.hooks = {}
    M.frames = {}
    M.fontstrings = {}
end

function M.callHook(name, ...)
    for _, fn in ipairs(M.hooks[name] or {}) do fn(...) end
end

-- ------------------------------------------------------------ API surface --
function GetMoney() return M.state.money end
function GetRepairAllCost() return M.state.repairCost end
function RepairAllItems(...) end -- hooked by core.lua; tests drive it via callHook
function TakeTaxiNode(...) end -- hooked by core.lua; tests drive it via callHook
function TaxiNodeCost(nodeIndex) return M.state.taxiCost end
function UnitName(unit) return M.state.playerName end
function GetRealmName() return M.state.realmName end
function GetTime() return M.state.time end

-- WoW's date() is os.date with the same signature
function date(fmt, t) return os.date(fmt, t) end
function time(t) return os.time(t) end

function GetNumLootItems() return #M.state.lootSlots end
function GetLootSlotInfo(i)
    local s = M.state.lootSlots[i]
    if not s then return nil end
    -- texture, item name, quantity
    return "Interface\\MoneyFrame\\UI-Coin", s.name, s.quantity
end
function LootSlotIsCoin(i)
    local s = M.state.lootSlots[i]
    return s and s.coin or false
end

function GetInboxNumItems() return #M.state.inbox end
function GetInboxHeaderInfo(i)
    local m = M.state.inbox[i]
    if not m then return nil end
    -- packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft,
    -- hasItem, wasRead, wasReturned, textCreated, canReply, isGM
    return nil, nil, m.sender, m.subject, m.money, m.cod or 0, 30, false, true, false, false, true, false
end

function hooksecurefunc(name, fn)
    M.hooks[name] = M.hooks[name] or {}
    table.insert(M.hooks[name], fn)
end

-- WoW aliases plain Lua lacks
tinsert = table.insert
local unpack = unpack or table.unpack

local function newRegion(kind)
    local r = { _kind = kind, _shown = true, _text = "" }
    function r:SetText(t) self._text = t or "" end
    function r:GetText() return self._text end
    function r:SetFont(...) end
    function r:SetTextColor(r, g, b) self._textColor = { r, g, b } end
    function r:SetJustifyH(...) end
    function r:SetSize(...) end
    -- record the Y offset so layout tests can check clearance, e.g.
    -- a bar label must sit below its bar, not tucked under it
    function r:SetPoint(...) local a = { ... }; self._pointY = a[5] end
    function r:Hide() self._shown = false end
    function r:Show() self._shown = true end
    function r:IsShown() return self._shown end
    function r:SetAllPoints(...) end
    function r:SetColorTexture(...) end
    return r
end

local function newFrame()
    local f = { _scripts = {}, _events = {}, _children = {}, _regions = {}, _shown = false, _parent = nil }
    function f:SetScript(k, fn) self._scripts[k] = fn end
    function f:GetScript(k) return self._scripts[k] end
    function f:RegisterEvent(e) self._events[e] = true end
    function f:UnregisterEvent(e) self._events[e] = nil end
    function f:SetSize(w, h) self._width, self._height = w, h end
    function f:SetHeight(...) end
    function f:SetPoint(...) local a = { ... }; self._pointY = a[5] end
    function f:SetMovable(...) end
    function f:EnableMouse(...) end
    function f:RegisterForDrag(...) end
    function f:Hide() self._shown = false end
    function f:Show() self._shown = true end
    function f:IsShown() return self._shown end
    function f:SetText(t) self._text = t end
    function f:SetParent(p)
        if self._parent and self._parent._children then
            for i, c in ipairs(self._parent._children) do
                if c == self then table.remove(self._parent._children, i) break end
            end
        end
        self._parent = p
        if p and p._children then table.insert(p._children, self) end
    end
    function f:GetChildren() return unpack(self._children) end
    function f:GetRegions() return unpack(self._regions) end
    function f:CreateFontString(name, layer, template)
        local fs = newRegion("FontString")
        table.insert(self._regions, fs)
        table.insert(M.fontstrings, fs)
        return fs
    end
    function f:CreateTexture(name, layer)
        local t = newRegion("Texture")
        table.insert(self._regions, t)
        return t
    end
    function f:SetScrollChild(child) self._scrollChild = child end
    -- StatusBar methods: record colour/value so polish tests can check them
    function f:SetStatusBarTexture(t) self._barTexture = t end
    function f:SetStatusBarColor(r, g, b) self._barColor = { r, g, b } end
    function f:SetMinMaxValues(a, b) self._barMinMax = { a, b } end
    function f:SetValue(v) self._barValue = v end
    return f
end

function CreateFrame(ftype, name, parent, template)
    local f = newFrame()
    if template == "BasicFrameTemplateWithInset" then
        f.TitleText = { SetText = function(_, t) end }
    end
    if parent then f:SetParent(parent) end
    table.insert(M.frames, f)
    return f
end

UIParent = CreateFrame("Frame", "UIParent")
UISpecialFrames = {}

return M
