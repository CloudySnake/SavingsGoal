-- SavingsGoal slash commands: /sg and /savingsgoal
local SG = SavingsGoal

local function help()
    print("|cff33ff99SavingsGoal commands:|r")
    print("  /sg — open the info screen")
    print("  /sg add <name> <target gold> — e.g. /sg add EpicMount 1000")
    print("  /sg list — show goals and forecasts")
    print("  /sg seed <name> <gold> — allocate current gold to a goal")
    print("  /sg rate <name> <50%|10g> — set the savings rate")
    print("  /sg minimap — toggle the minimap button")
    print("  /sg reset — wipe ALL SavingsGoal data (asks for confirmation)")
end

local function findGoal(name)
    name = (name or ""):lower()
    for _, g in ipairs(SG:GetGoals()) do
        if g.name:lower() == name or g.name:lower():find(name, 1, true) then
            return g
        end
    end
end

SLASH_SAVINGSGOAL1, SLASH_SAVINGSGOAL2 = "/sg", "/savingsgoal"
SlashCmdList["SAVINGSGOAL"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        SG:ToggleUI()
    elseif cmd == "add" then
        local name, target = rest:match("^(.-)%s+(%d+)%s*$")
        if name and target then
            local g = SG:AddGoal(name, tonumber(target))
            if g then
                print("|cff33ff99SavingsGoal:|r goal '" .. g.name .. "' added: " .. SG:FormatGoldShort(g.target))
                SG:RefreshUI(); SG:RefreshBroker()
            end
        else
            print("|cff33ff99SavingsGoal:|r usage: /sg add <name> <target gold>")
        end
    elseif cmd == "list" then
        for _, g in ipairs(SG:GetGoals()) do
            local days = SG:GoalDaysLeft(g)
            local eta = days == nil and "?" or (days .. "d")
            print(string.format("  %s: %s / %s (~%s) [%s]", g.name,
                SG:FormatGoldShort((g.seed or 0) + (g.saved or 0)),
                SG:FormatGoldShort(g.target), eta, SG:RateLabel(g)))
        end
        print("  Safe to spend: " .. SG:FormatGold(SG:SafeToSpend()))
    elseif cmd == "seed" then
        local name, gold = rest:match("^(.-)%s+(%d+)%s*$")
        local g = name and findGoal(name)
        if g and gold then
            SG:SetSeed(g, tonumber(gold))
            print("|cff33ff99SavingsGoal:|r '" .. g.name .. "' seeded with " .. SG:FormatGoldShort(g.seed))
            SG:RefreshUI(); SG:RefreshBroker()
        else
            print("|cff33ff99SavingsGoal:|r usage: /sg seed <name> <gold>")
        end
    elseif cmd == "rate" then
        local name, rate = rest:match("^(.-)%s+(%S+)%s*$")
        local g = name and findGoal(name)
        if g and rate then
            SG:SetRate(g, rate)
            print("|cff33ff99SavingsGoal:|r '" .. g.name .. "' rate: " .. SG:RateLabel(g))
            SG:RefreshUI(); SG:RefreshBroker()
        else
            print("|cff33ff99SavingsGoal:|r usage: /sg rate <name> <50%|10g>")
        end
    elseif cmd == "minimap" then
        SG:ToggleMinimap()
    elseif cmd == "reset" then
        StaticPopup_Show("SG_RESET_CONFIRM")
    else
        help()
    end
end

StaticPopupDialogs["SG_RESET_CONFIRM"] = {
    text = "Wipe ALL SavingsGoal data (goals, history, everything)?",
    button1 = "Wipe it", button2 = "Cancel",
    OnAccept = function()
        SavingsGoalDB = nil
        SG:InitDB()
        SG:RefreshUI(); SG:RefreshBroker()
        print("|cff33ff99SavingsGoal:|r all data wiped.")
    end,
    whileDead = true, hideOnEscape = true,
}
