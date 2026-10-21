-- SavingsGoal goals: CRUD, surplus math, forecasts, waterfall allocation.
local SG = SavingsGoal

-- ------------------------------------------------------------------ goals --
-- goal = { name, target (copper), seed (copper), saved (copper),
--          rate = { mode = "pct"|"perday", value = n }, priority = n, owner = charKey|nil }

function SG:GetGoals()
    local t = {}
    for i, g in ipairs(self.db.goals) do t[#t + 1] = g end
    table.sort(t, function(a, b) return (a.priority or 99) < (b.priority or 99) end)
    return t
end

function SG:AddGoal(name, targetGold)
    local target = math.floor((tonumber(targetGold) or 0) * 10000)
    if not name or name == "" or target <= 0 then return nil end
    local g = {
        name = name, target = target, seed = 0, saved = 0,
        rate = { mode = "pct", value = 100 },
        priority = #self.db.goals + 1,
    }
    self.db.goals[#self.db.goals + 1] = g
    return g
end

function SG:DeleteGoal(goal)
    for i, g in ipairs(self.db.goals) do
        if g == goal then
            table.remove(self.db.goals, i)
            break
        end
    end
    self:RenumberPriorities()
end

function SG:RenumberPriorities()
    local goals = self:GetGoals()
    for i, g in ipairs(goals) do g.priority = i end
end

function SG:MoveGoal(goal, dir) -- dir = -1 up, +1 down
    local goals = self:GetGoals()
    for i, g in ipairs(goals) do
        if g == goal then
            local j = i + dir
            if goals[j] then
                goals[j].priority, g.priority = g.priority, goals[j].priority
            end
            break
        end
    end
end

function SG:SetSeed(goal, gold)
    local seed = math.floor((tonumber(gold) or 0) * 10000)
    seed = math.max(0, math.min(seed, goal.target)) -- can't seed more than the target
    -- can't lock more gold than the account holds (minus the spend buffer)
    local maxLock = math.max(0, self:AccountGold() - self:LockedTotal() + (goal.seed or 0) - self.db.settings.spendBuffer)
    goal.seed = math.min(seed, maxLock)
    return goal.seed
end

function SG:SetRate(goal, text)
    -- accepts "50%", "50", or "10g" / "10g/day"
    if not text then return end
    text = text:gsub("%s+", ""):lower()
    local pct = text:match("^(%d+)%%?$")
    local perday = text:match("^(%d+)g")
    if perday then
        goal.rate = { mode = "perday", value = tonumber(perday) * 10000 }
    elseif pct then
        goal.rate = { mode = "pct", value = math.min(100, math.max(0, tonumber(pct))) }
    end
end

function SG:RateLabel(goal)
    if goal.rate.mode == "perday" then
        return self:FormatGoldShort(goal.rate.value) .. "/day"
    end
    return goal.rate.value .. "% of surplus"
end

-- ------------------------------------------------------------- aggregates --
function SG:AccountGold()
    local total = 0
    for _, char in pairs(self.db.chars) do
        total = total + (char.lastMoney or 0)
    end
    return total
end

function SG:DailySurplus(windowDays)
    windowDays = windowDays or self.db.settings.windowDays or self.WINDOW_DAYS
    local surplus, days = 0, 0
    local today = self:TodayKey()
    for _, char in pairs(self.db.chars) do
        for day, d in pairs(char.daily) do
            local age = self:DaysBetween(day, today)
            if age >= 0 and age < windowDays then
                surplus = surplus + (d.income - d.outgoing)
                days = math.max(days, age + 1)
            end
        end
    end
    if days == 0 then return 0 end
    return surplus / days -- copper per day, across the account
end

function SG:LockedTotal()
    local t = 0
    for _, g in ipairs(self.db.goals) do
        t = t + (g.seed or 0) + (g.saved or 0)
    end
    return t
end

function SG:SafeToSpend()
    local safe = self:AccountGold() - self:LockedTotal() - (self.db.settings.spendBuffer or 0)
    return math.max(0, safe)
end

function SG:IncomeBySource()
    local t = { ah = 0, vendor = 0, quest = 0, loot = 0, other = 0 }
    for _, char in pairs(self.db.chars) do
        for k, v in pairs(char.bySource or {}) do
            t[k] = (t[k] or 0) + v
        end
    end
    return t
end

-- --------------------------------------------------------------- forecasts --
function SG:GoalNeed(goal)
    return math.max(0, goal.target - (goal.seed or 0) - (goal.saved or 0))
end

function SG:GoalDailyBudget(goal, dailySurplus)
    -- how much of today's surplus this goal claims, before the waterfall
    if goal.rate.mode == "perday" then
        return goal.rate.value
    end
    return dailySurplus * (goal.rate.value / 100)
end

function SG:GoalDaysLeft(goal)
    local need = self:GoalNeed(goal)
    if need <= 0 then return 0 end
    local budget = self:GoalDailyBudget(goal, self:DailySurplus())
    if budget <= 0 then return nil end -- no surplus: can't forecast
    return math.ceil(need / budget)
end

function SG:WaterfallDaysLeft()
    -- days until ALL goals are filled, surplus shared in priority order
    local totalNeed = 0
    for _, g in ipairs(self:GetGoals()) do totalNeed = totalNeed + self:GoalNeed(g) end
    if totalNeed <= 0 then return 0 end
    local surplus = self:DailySurplus()
    if surplus <= 0 then return nil end
    return math.ceil(totalNeed / surplus)
end

function SG:TickGoals()
    -- allocate surplus earned since the last tick, in priority order (waterfall)
    local db = self.db
    local today = self:TodayKey()
    if not db.lastTick then
        db.lastTick = today
        return
    end
    local days = self:DaysBetween(db.lastTick, today)
    db.lastTick = today
    if days <= 0 then return end
    local surplus = self:DailySurplus()
    if surplus <= 0 then return end
    local pool = surplus * days
    for _, goal in ipairs(self:GetGoals()) do
        local need = self:GoalNeed(goal)
        if need > 0 and pool > 0 then
            local claim = self:GoalDailyBudget(goal, surplus) * days
            local take = math.min(need, claim, pool)
            goal.saved = (goal.saved or 0) + take
            pool = pool - take
        end
    end
    if self.RefreshBroker then self:RefreshBroker() end
end

-- ------------------------------------------------- locked-bucket watchdog --
function SG:CheckLockedDip()
    -- warn (at most once a minute) if spendable gold is gone: you're into locked gold
    if self:SafeToSpend() <= 0 and self:LockedTotal() > 0 then
        local now = GetTime()
        if now - (self.lastDipWarning or 0) > 60 then
            self.lastDipWarning = now
            print("|cff33ff99SavingsGoal:|r |cffff5555warning — you're spending into locked goal gold.|r")
        end
    end
end
