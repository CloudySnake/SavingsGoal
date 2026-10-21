-- SavingsGoal broker: Titan Panel / LibDataBroker feed + minimap button.
-- Both are optional: if the libraries aren't installed, the addon still works via /sg.
local SG = SavingsGoal

local ldbObject = nil
local iconObject = nil

function SG:BrokerText()
    local goals = self:GetGoals()
    local safe = self:FormatGoldShort(self:SafeToSpend())
    if #goals == 0 then
        return "SavingsGoal: " .. safe .. " safe"
    end
    local g = goals[1]
    local days = self:GoalDaysLeft(g)
    local prog = self:FormatGoldShort((g.seed or 0) + (g.saved or 0)) .. "/" .. self:FormatGoldShort(g.target)
    local eta = (days == nil) and "?" or (days .. "d")
    return string.format("%s safe | %s %s ~%s", safe, g.name, prog, eta)
end

function SG:BrokerTooltip(tooltip)
    tooltip:AddLine("SavingsGoal", 0.2, 1, 0.6)
    tooltip:AddLine(" ")
    for _, g in ipairs(self:GetGoals()) do
        local days = self:GoalDaysLeft(g)
        local eta = (days == nil) and "no surplus yet" or (days == 0 and "complete!" or ("~" .. days .. " days"))
        tooltip:AddDoubleLine(g.name,
            string.format("%s / %s (%s)", self:FormatGoldShort((g.seed or 0) + (g.saved or 0)),
                self:FormatGoldShort(g.target), eta))
    end
    if #self:GetGoals() > 1 then
        local all = self:WaterfallDaysLeft()
        tooltip:AddDoubleLine("All goals (waterfall)", all == nil and "?" or ("~" .. all .. " days"))
    end
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("Safe to spend", self:FormatGold(self:SafeToSpend()), 1, 1, 1, 0.2, 1, 0.6)
    tooltip:AddDoubleLine("Account total", self:FormatGold(self:AccountGold()), 1, 1, 1, 1, 1, 1)
    tooltip:AddLine(" ")
    tooltip:AddLine("Click to open.", 0.7, 0.7, 0.7)
end

function SG:RefreshBroker()
    if ldbObject then
        ldbObject.text = self:BrokerText()
    end
end

local function setupBroker()
    if ldbObject then return end
    local ok, LDB = pcall(function() return LibStub:GetLibrary("LibDataBroker-1.1", true) end)
    if not ok or not LDB then return end
    ldbObject = LDB:NewDataObject("SavingsGoal", {
        type = "data source",
        text = "SavingsGoal",
        icon = "Interface\\Icons\\INV_Misc_Coin_02",
        OnClick = function() SG:ToggleUI() end,
        OnTooltipShow = function(tt) SG:BrokerTooltip(tt) end,
    })
    SG:RefreshBroker()
end

local function setupMinimap()
    if iconObject then return end
    local ok, DBIcon = pcall(function() return LibStub:GetLibrary("LibDBIcon-1.0", true) end)
    if not ok or not DBIcon then return end
    local db = SG.db.settings
    db.minimapPos = db.minimapPos or {}
    iconObject = {
        icon = "Interface\\Icons\\INV_Misc_Coin_02",
        OnClick = function() SG:ToggleUI() end,
        OnTooltipShow = function(tt)
            tt:AddLine("SavingsGoal")
            tt:AddLine("Click to open.", 0.7, 0.7, 0.7)
        end,
    }
    DBIcon:Register("SavingsGoal", iconObject, db.minimapPos)
    SG:RefreshMinimap()
end

function SG:RefreshMinimap()
    local ok, DBIcon = pcall(function() return LibStub:GetLibrary("LibDBIcon-1.0", true) end)
    if not ok or not DBIcon or not iconObject then return end
    if self.db.settings.minimap then
        DBIcon:Show("SavingsGoal")
    else
        DBIcon:Hide("SavingsGoal")
    end
end

function SG:ToggleMinimap()
    self.db.settings.minimap = not self.db.settings.minimap
    self:RefreshMinimap()
    print("|cff33ff99SavingsGoal:|r minimap button " .. (self.db.settings.minimap and "shown" or "hidden"))
end

SG:Register("PLAYER_LOGIN", function(self)
    -- run after the core login handler; libraries are loaded by now
    C_Timer.After(1, function()
        setupBroker()
        setupMinimap()
    end)
end)
