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
end
