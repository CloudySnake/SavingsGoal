-- SavingsGoal slash commands: /sg and /savingsgoal
local SG = SavingsGoal

local function help()
    print("|cff33ff99SavingsGoal commands:|r")
    print("  /sg — open the info screen")
    print("  /sg add <name> <target gold> — e.g. /sg add EpicMount 1000")
    print("  /sg list — show goals and forecasts")
    print("  /sg seed <name> <gold> — allocate current gold to a goal")
    print("  /sg rate <name> <50%|10g> — set the savings rate")
    print("  /sg keep <50%|1g> — hold back for day-to-day spending (0% switches it off)")
    print("  /sg look <classic|modern> — switch the info-screen look")
    print("  /sg move <50s|1g> — reclassify that much 'Other' income as a transfer from your own alt")
    print("  /sg reclassify <50s|1g> <from> <to> — move income between categories, e.g. /sg reclassify 50s other loot")
    print("  /sg last — show what the last gain/spend was filed as")
    print("  /sg log — show the last 10 activity-log entries (time, amount, source, what the addon saw)")
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
            print(string.format("  %s: %s / %s (%s) [%s]", g.name,
                SG:FormatGoldShort((g.seed or 0) + (g.saved or 0)),
                SG:FormatGoldShort(g.target), SG:FormatEta(SG:GoalDaysLeft(g)), SG:RateLabel(g)))
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
    elseif cmd == "keep" then
        if rest == "" then
            print("|cff33ff99SavingsGoal:|r keeping for spending: " .. SG:DailyKeepLabel())
        elseif SG:SetDailyKeep(rest) then
            print("|cff33ff99SavingsGoal:|r keeping for spending: " .. SG:DailyKeepLabel())
            SG:RefreshUI(); SG:RefreshBroker()
        else
            print("|cff33ff99SavingsGoal:|r usage: /sg keep <50%|1g> (0% switches it off)")
        end
    elseif cmd == "look" then
        if rest == "" then
            print("|cff33ff99SavingsGoal:|r look: " .. SG:Look() .. " (classic or modern)")
        elseif SG:SetLook(rest) then
            print("|cff33ff99SavingsGoal:|r look: " .. SG:Look())
            SG:RefreshUI(); SG:RefreshBroker()
        else
            print("|cff33ff99SavingsGoal:|r usage: /sg look <classic|modern>")
        end
    elseif cmd == "move" then
        local amount = SG:ParseGold(rest)
        local moved = amount and SG:ReclassifyMove(amount) or 0
        if moved > 0 then
            print("|cff33ff99SavingsGoal:|r reclassified " .. SG:FormatGold(moved) .. " of 'Other' income as a transfer from your own alt")
            SG:RefreshUI(); SG:RefreshBroker()
        else
            print("|cff33ff99SavingsGoal:|r usage: /sg move <50s|1g> — nothing in 'Other' income to reclassify")
        end
    elseif cmd == "reclassify" then
        local amountText, from, to = rest:match("^(%S+)%s+(%S+)%s+(%S+)%s*$")
        local amount = amountText and SG:ParseGold(amountText)
        local sources = { ah = true, vendor = true, quest = true, loot = true, other = true }
        from = from and from:lower()
        to = to and to:lower()
        local moved = (amount and sources[from] and sources[to]) and SG:ReclassifyIncomeSource(from, to, amount) or 0
        if moved > 0 then
            print("|cff33ff99SavingsGoal:|r reclassified " .. SG:FormatGold(moved) .. " from '" .. from .. "' to '" .. to .. "'")
            SG:RefreshUI(); SG:RefreshBroker()
        else
            print("|cff33ff99SavingsGoal:|r usage: /sg reclassify <50s|1g> <from> <to> — from/to are ah, vendor, quest, loot or other")
        end
    elseif cmd == "last" then
        local g = SG.lastGain
        if g then
            local bySource = SG:IncomeBySource()
            print("|cff33ff99SavingsGoal:|r last change: " .. SG:FormatGold(g.amount) .. " filed as '" .. g.source .. "' (pending loot at the time: " .. SG:FormatGold(g.pendingLoot or 0) .. ")")
            print("|cff33ff99SavingsGoal:|r totals now — Loot: " .. SG:FormatGold(bySource.loot or 0) .. ", Other: " .. SG:FormatGold(bySource.other or 0))
        else
            print("|cff33ff99SavingsGoal:|r no money change recorded yet this session")
        end
    elseif cmd == "log" then
        local log = SG:ActivityLog()
        if #log == 0 then
            print("|cff33ff99SavingsGoal:|r activity log is empty")
        else
            for i = math.max(1, #log - 9), #log do
                local e = log[i]
                print(string.format("|cff33ff99SavingsGoal:|r %s %s %s (loot %s, window %s, merch %s, quest %s)",
                    e.t, SG:FormatGold(e.amount), e.source, SG:FormatGold(e.loot or 0),
                    e.win == 1 and "yes" or "no", e.merch == 1 and "yes" or "no", e.quest == 1 and "yes" or "no"))
            end
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
