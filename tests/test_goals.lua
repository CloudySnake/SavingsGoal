-- Tests for goals.lua: surplus math, forecasts, waterfall, seeding guards.
-- Run via run.lua (needs wow_stubs.lua loaded first).

return function(stubs, ADDON)
    print("goals.lua")

    local function dayKey(offsetDays)
        return os.date("%Y-%m-%d", os.time() - offsetDays * 86400)
    end

    local function fresh(money)
        _G.SavingsGoalDB = nil
        stubs.reset()
        stubs.state.money = money or 0
        dofile(ADDON .. "core.lua")
        dofile(ADDON .. "goals.lua")
        local SG = SavingsGoal
        SG:InitDB()
        for _, h in ipairs(SG.handlers["PLAYER_LOGIN"]) do h(SG) end
        return SG
    end

    -- seed daily history: daysAgo -> {income, outgoing} on the current char
    local function seedDaily(SG, entries)
        local char = SG:Char()
        for daysAgo, v in pairs(entries) do
            char.daily[dayKey(daysAgo)] = { income = v[1], outgoing = v[2] }
        end
    end

    test("AddGoal rejects bad input", function()
        local SG = fresh()
        assertEq(SG:AddGoal("", 100), nil)
        assertEq(SG:AddGoal("X", 0), nil)
        assertEq(SG:AddGoal("X", -5), nil)
        local g = SG:AddGoal("Epic Mount", 1000)
        assertEq(g.target, 10000000)
        assertEq(g.rate.mode, "pct")
    end)

    test("DailySurplus averages trailing days", function()
        local SG = fresh()
        seedDaily(SG, { [0] = { 20000, 5000 }, [1] = { 10000, 0 } })
        -- (15000 + 10000) / 2 days
        assertEq(SG:DailySurplus(), 12500)
    end)

    test("DailySurplus spans characters", function()
        local SG = fresh()
        seedDaily(SG, { [0] = { 20000, 0 } })
        SG.db.chars["Bankalt-Testrealm"] = {
            lastMoney = 0,
            daily = { [dayKey(0)] = { income = 40000, outgoing = 0 } },
        }
        assertEq(SG:DailySurplus(), 60000)
    end)

    test("GoalDaysLeft from surplus", function()
        local SG = fresh()
        seedDaily(SG, { [0] = { 12500, 0 } })
        local g = SG:AddGoal("Mount", 10) -- 10g = 100000c
        assertEq(SG:GoalDaysLeft(g), 8)
        g.seed = 20000 -- 2g seeded: need 80000 -> 6.4 -> 7
        assertEq(SG:GoalDaysLeft(g), 7)
    end)

    test("GoalDaysLeft is nil with no surplus", function()
        local SG = fresh()
        local g = SG:AddGoal("Mount", 10)
        assertEq(SG:GoalDaysLeft(g), nil)
    end)

    test("per-day rate forecast", function()
        local SG = fresh()
        local g = SG:AddGoal("Mount", 2) -- 20000c
        SG:SetRate(g, "10g")             -- 100000c/day, way more than need
        assertEq(SG:GoalDaysLeft(g), 1)
        SG:SetRate(g, "5g")              -- 50000c/day... need 20000 -> 1 day
        local g2 = SG:AddGoal("Mount2", 10) -- 100000c need
        SG:SetRate(g2, "5g")
        assertEq(SG:GoalDaysLeft(g2), 2)
    end)

    test("waterfall fills goals in priority order", function()
        local SG = fresh()
        seedDaily(SG, { [0] = { 20000, 0 } }) -- 20000c/day surplus
        local g1 = SG:AddGoal("First", 5)      -- 50000c
        local g2 = SG:AddGoal("Second", 10)    -- 100000c
        SG.db.lastTick = dayKey(3)            -- 3 days elapsed -> 60000 pool
        SG:TickGoals()
        assertEq(g1.saved, 50000)             -- filled completely
        assertEq(g2.saved, 10000)             -- remainder rolls down
        assertEq(SG:WaterfallDaysLeft(), 5)    -- 90000c left / 20000c per day
    end)

    test("SetSeed capped by available gold", function()
        local SG = fresh()
        SG:Char().lastMoney = 30000 -- 3g on the account
        local g = SG:AddGoal("Mount", 100)    -- 100g target
        SG:SetSeed(g, 50)                     -- ask for 50g, only 3g exists
        assertEq(g.seed, 30000)
    end)

    test("SetSeed capped by goal target", function()
        local SG = fresh()
        SG:Char().lastMoney = 1000000 -- plenty of gold
        local g = SG:AddGoal("Cheap", 1)      -- 1g target
        SG:SetSeed(g, 50)                     -- ask for 50g
        assertEq(g.seed, 10000)
    end)

    test("SafeToSpend subtracts locked gold", function()
        local SG = fresh()
        SG:Char().lastMoney = 100000
        local g = SG:AddGoal("Mount", 100)
        SG:SetSeed(g, 4) -- 4g of 10g available
        assertEq(SG:SafeToSpend(), 60000)
    end)

    test("CharSafeToSpend is min of char gold and account safe", function()
        local SG = fresh()
        SG:Char().lastMoney = 100000 -- 10g on this char
        SG.db.chars["Bankalt-Testrealm"] = { lastMoney = 900000, daily = {} } -- 90g elsewhere
        -- account 100g, nothing locked: every toon can spend its whole purse
        assertEq(SG:CharSafeToSpend(SG:Char()), 100000)
        assertEq(SG:CharSafeToSpend("Bankalt-Testrealm"), 900000)
        -- lock 60g: account safe is 40g, so the rich char is capped at 40g
        -- while the 10g char is still fully spendable; per-toon figures
        -- deliberately do not sum to the account safe (40g, not 50g)
        local g = SG:AddGoal("Mount", 100)
        SG:SetSeed(g, 60)
        assertEq(SG:SafeToSpend(), 400000)
        assertEq(SG:CharSafeToSpend(SG:Char()), 100000)
        assertEq(SG:CharSafeToSpend("Bankalt-Testrealm"), 400000)
        assertEq(SG:CharSafeToSpend("Nobody-Testrealm"), 0)
    end)

    test("GoalPercent and bar colour", function()
        local SG = fresh()
        local g = SG:AddGoal("Mount", 100) -- 100g target
        assertEq(SG:GoalPercent(g), 0)
        local r, gg, b = SG:GoalBarColor(g)
        assertEq(r, 0.2)
        g.seed = 750000 -- 75g: gold bar at 75%
        assertEq(SG:GoalPercent(g), 75)
        r, gg, b = SG:GoalBarColor(g)
        assertEq(r, 1)
        g.seed = 1000000 -- complete: bright green
        assertEq(SG:GoalPercent(g), 100)
        r, gg, b = SG:GoalBarColor(g)
        assertEq(gg, 1)
    end)

    test("TodayTotals sums today across characters", function()
        local SG = fresh()
        seedDaily(SG, { [0] = { 20000, 5000 }, [1] = { 10000, 0 } })
        local i, o, n = SG:TodayTotals()
        assertEq(i, 20000)
        assertEq(o, 5000)
        assertEq(n, 15000)
    end)

    test("AnnounceGoalComplete prints once", function()
        local SG = fresh()
        SG:Char().lastMoney = 1000000
        local g = SG:AddGoal("Mount", 10)
        SG:SetSeed(g, 10) -- fills it: celebrated set
        assertEq(g.celebrated, true)
        g.celebrated = false
        SG:AnnounceGoalComplete(g)
        assertEq(g.celebrated, true)
    end)

    test("Look defaults to modern, toggles to classic", function()
        local SG = fresh()
        assertEq(SG:Look(), "modern")
        assertEq(SG:SetLook("classic"), "classic")
        assertEq(SG:Look(), "classic")
        assertEq(SG:ToggleLook(), "modern")
        assertEq(SG:SetLook("bogus"), nil)
        assertEq(SG:Look(), "modern")
    end)

    test("SetRate parsing", function()
        local SG = fresh()
        local g = SG:AddGoal("Mount", 100)
        SG:SetRate(g, "50%")
        assertEq(g.rate.mode, "pct")
        assertEq(g.rate.value, 50)
        SG:SetRate(g, "10g")
        assertEq(g.rate.mode, "perday")
        assertEq(g.rate.value, 100000)
        SG:SetRate(g, "25")
        assertEq(g.rate.mode, "pct")
        assertEq(g.rate.value, 25)
        assertEq(SG:RateLabel(g), "25% of surplus")
    end)

    test("priority reorder", function()
        local SG = fresh()
        local g1 = SG:AddGoal("A", 1)
        local g2 = SG:AddGoal("B", 1)
        SG:MoveGoal(g2, -1)
        local goals = SG:GetGoals()
        assertEq(goals[1], g2)
        assertEq(goals[2], g1)
        SG:DeleteGoal(g2)
        assertEq(#SG:GetGoals(), 1)
    end)

    test("FormatEta shows years for huge ETAs", function()
        local SG = fresh()
        assertEq(SG:FormatEta(142858), "~391 years")
        assertEq(SG:FormatEta(17544), "~48 years")
        assertEq(SG:FormatEta(100), "~100 days")
        assertEq(SG:FormatEta(729), "~729 days")
        assertEq(SG:FormatEta(730), "~2 years")
        assertEq(SG:FormatEta(nil), "no surplus yet")
        assertEq(SG:FormatEta(0), "complete!")
    end)

    test("SetDailyKeep parsing", function()
        local SG = fresh()
        assertEq(SG:SetDailyKeep("1g").mode, "perday")
        assertEq(SG:SetDailyKeep("1g").value, 10000)
        assertEq(SG:SetDailyKeep("50%").mode, "pct")
        assertEq(SG:SetDailyKeep("50%").value, 50)
        assertEq(SG:SetDailyKeep("abc"), nil)
        assertEq(SG:DailyKeepLabel(), "50% of surplus") -- invalid input leaves it unchanged
        SG:SetDailyKeep("0%")
        assertEq(SG:DailyKeepAmount(), 0)
    end)

    test("DailyKeep shrinks the surplus goals see", function()
        local SG = fresh()
        seedDaily(SG, { [0] = { 20000, 0 } }) -- 20000c/day surplus
        SG:SetDailyKeep("1g") -- hold back 10000c/day
        assertEq(SG:DailyKeepAmount(), 10000)
        assertEq(SG:SurplusAfterKeep(), 10000)
        local g = SG:AddGoal("Mount", 10) -- 100000c need
        assertEq(SG:GoalDaysLeft(g), 10) -- was 5 with the full surplus
        SG:SetDailyKeep("50%")
        assertEq(SG:DailyKeepAmount(), 10000)
        assertEq(SG:SurplusAfterKeep(), 10000)
    end)

    test("DailyKeep as percent of surplus", function()
        local SG = fresh()
        seedDaily(SG, { [0] = { 20000, 0 } })
        SG:SetDailyKeep("25%")
        assertEq(SG:DailyKeepAmount(), 5000)
        assertEq(SG:SurplusAfterKeep(), 15000)
    end)

    test("DailyKeep of more than the surplus leaves nothing for goals", function()
        local SG = fresh()
        seedDaily(SG, { [0] = { 5000, 0 } }) -- 5000c/day surplus
        SG:SetDailyKeep("1g") -- 10000c/day keep
        assertEq(SG:SurplusAfterKeep(), 0)
        local g = SG:AddGoal("Mount", 10)
        assertEq(SG:GoalDaysLeft(g), nil)
    end)

    test("TickGoals respects the daily keep", function()
        local SG = fresh()
        seedDaily(SG, { [0] = { 20000, 0 } }) -- 20000c/day surplus
        SG:SetDailyKeep("1g") -- 10000c/day kept back
        local g = SG:AddGoal("Mount", 10) -- 100000c
        SG.db.lastTick = dayKey(3) -- 3 days elapsed
        SG:TickGoals()
        assertEq(g.saved, 30000) -- 3 days x 10000c after keep, not 60000
    end)
end
