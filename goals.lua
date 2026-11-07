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
    self:AnnounceGoalComplete(goal)
    return goal.seed
end

-- shared "50%" / "10g" parsing for goal rates and the daily keep.
-- Accepts "50%", "50", or "10g" / "10g/day"; returns nil for anything else.
local function parseRate(text)
    if not text then return nil end
    text = text:gsub("%s+", ""):lower()
    local perday = text:match("^(%d+)g")
    if perday then return { mode = "perday", value = tonumber(perday) * 10000 } end
    local pct = text:match("^(%d+)%%?$")
    if pct then return { mode = "pct", value = math.min(100, math.max(0, tonumber(pct))) } end
    return nil
end

function SG:SetRate(goal, text)
    local rate = parseRate(text)
    if rate then goal.rate = rate end
end

-- ------------------------------------------------------------ daily keep --
-- Gold held back for day-to-day spending: a fixed amount per day ("1g") or
-- a % of daily surplus ("50%"), in the same syntax as goal rates. Kept gold
-- is never allocated to goals, so it stays inside "safe to spend" — it only
-- shrinks the surplus the forecasts and the waterfall have to work with.
-- 0 (the default) means no keep: everything goes to goals as before.
function SG:SetDailyKeep(text)
    local keep = parseRate(text)
    if not keep then return nil end
    self.db.settings.dailyKeep = keep
    return keep
end

function SG:DailyKeepLabel()
    local k = self.db.settings.dailyKeep or { mode = "pct", value = 0 }
    if k.mode == "perday" then return self:FormatGoldShort(k.value) .. "/day" end
    return k.value .. "% of surplus"
end

function SG:DailyKeepAmount() -- copper/day held back for spending
    local k = self.db.settings.dailyKeep or { mode = "pct", value = 0 }
    if k.mode == "perday" then return k.value end
    local surplus = self:DailySurplus()
    if surplus <= 0 then return 0 end
    return surplus * (k.value / 100)
end

function SG:SurplusAfterKeep() -- copper/day actually available to goals
    return math.max(0, self:DailySurplus() - self:DailyKeepAmount())
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

-- Per-character safe-to-spend: what this toon can spend right now, without
-- mailing gold from another character. Locked gold is virtual — it isn't
-- tied to any one character — so this is the smaller of the toon's own gold
-- and the account safe-to-spend. It never tells a toon it can spend gold
-- that is locked in total, and it needs no assumption about where the
-- locked gold lives. Caveat, by design: per-toon figures do NOT add up to
-- the account safe-to-spend — each is that toon's individual maximum.
-- Accepts a char record, or a char key ("Name-Realm").
function SG:CharSafeToSpend(char)
    if type(char) == "string" then char = self.db.chars[char] end
    if not char then return 0 end
    return math.max(0, math.min(char.lastMoney or 0, self:SafeToSpend()))
end

-- ------------------------------------------------------- money moves --
-- Parse "1g", "50s", "30c", "1g 20s 30c" (or a plain copper number)
-- into copper; nil for anything else.
function SG:ParseGold(text)
    if not text then return nil end
    text = text:gsub("%s+", ""):lower()
    if text == "" then return nil end
    local g = tonumber(text:match("(%d+)g")) or 0
    local s = tonumber(text:match("(%d+)s")) or 0
    local c = tonumber(text:match("(%d+)c")) or 0
    if g > 0 or s > 0 or c > 0 then return g * 10000 + s * 100 + c end
    return tonumber(text) -- plain number: copper
end

function SG:MoneyMovesTotal()
    local t = 0
    for _, char in pairs(self.db.chars) do t = t + (char.moneyMoves or 0) end
    return t
end

-- Reclassify `amount` copper of this character's "Other" income as a
-- money move (a transfer from your own alt that was misfiled, e.g.
-- before the inbox/ledger fix). Fixes lifetime income, "Other" and
-- today's daily income (clamped at zero if the amount was earned on
-- an earlier day), and adds it to moneyMoves. Returns what moved.
function SG:ReclassifyMove(amount)
    local char = self:Char()
    local other = (char.bySource and char.bySource.other) or 0
    local n = math.min(amount or 0, other)
    if n <= 0 then return 0 end
    char.bySource.other = other - n
    char.income = (char.income or 0) - n
    local today = char.daily[self:TodayKey()]
    if today then today.income = math.max(0, (today.income or 0) - n) end
    char.moneyMoves = (char.moneyMoves or 0) + n
    return n
end

-- ------------------------------------------------------------ look --
-- Classic vs Modern info-screen look. Modern is the default; Classic
-- is the pre-1.0.6 layout (single-sentence headline, plain section
-- titles, glossy Blizzard bars). Toggle in-game with /sg look, or the
-- Look button on the info screen.
function SG:Look()
    return self.db.settings.look or "modern"
end

function SG:SetLook(mode)
    mode = (mode or ""):lower()
    if mode == "classic" or mode == "modern" then
        self.db.settings.look = mode
        return mode
    end
    return nil
end

function SG:ToggleLook()
    return self:SetLook(self:Look() == "modern" and "classic" or "modern")
end

-- ------------------------------------------------------------ polish --
-- % complete for a goal (0-100, capped), and the bar colour for it:
-- green while working, gold at 75%+, bright green when complete.
function SG:GoalPercent(goal)
    if not goal or not goal.target or goal.target <= 0 then return 0 end
    local have = (goal.seed or 0) + (goal.saved or 0)
    return math.min(100, math.floor(100 * have / goal.target + 0.5))
end

function SG:GoalBarColor(goal)
    if self:GoalNeed(goal) <= 0 then return 0.2, 1, 0.4 end
    if self:GoalPercent(goal) >= 75 then return 1, 0.84, 0 end
    return 0.2, 0.8, 0.4
end

-- Today's net across the account: income, outgoing, net (copper).
function SG:TodayTotals()
    local today = self:TodayKey()
    local income, outgoing = 0, 0
    for _, char in pairs(self.db.chars) do
        local d = char.daily and char.daily[today]
        if d then
            income = income + (d.income or 0)
            outgoing = outgoing + (d.outgoing or 0)
        end
    end
    return income, outgoing, income - outgoing
end

-- One-time celebration when a goal fills up (seed or surplus tick).
-- Sets goal.celebrated so opening the info screen again never repeats it.
function SG:AnnounceGoalComplete(goal)
    if not goal or goal.celebrated then return end
    if self:GoalNeed(goal) > 0 then return end
    goal.celebrated = true
    print("|cff33ff99SavingsGoal:|r Goal complete: " .. goal.name .. " — "
        .. self:FormatGoldShort(goal.target) .. " saved!")
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

function SG:SpendingBySource()
    local t = { ah = 0, vendor = 0, quest = 0, loot = 0, mail = 0, repair = 0, other = 0 }
    for _, char in pairs(self.db.chars) do
        for k, v in pairs(char.spentBySource or {}) do
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
    local budget = self:GoalDailyBudget(goal, self:SurplusAfterKeep())
    if budget <= 0 then return nil end -- no surplus: can't forecast
    return math.ceil(need / budget)
end

function SG:WaterfallDaysLeft()
    -- days until ALL goals are filled, surplus shared in priority order
    local totalNeed = 0
    for _, g in ipairs(self:GetGoals()) do totalNeed = totalNeed + self:GoalNeed(g) end
    if totalNeed <= 0 then return 0 end
    local surplus = self:SurplusAfterKeep()
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
    local surplus = self:SurplusAfterKeep()
    if surplus <= 0 then return end
    local pool = surplus * days
    for _, goal in ipairs(self:GetGoals()) do
        local need = self:GoalNeed(goal)
        if need > 0 and pool > 0 then
            local claim = self:GoalDailyBudget(goal, surplus) * days
            local take = math.min(need, claim, pool)
            goal.saved = (goal.saved or 0) + take
            pool = pool - take
            self:AnnounceGoalComplete(goal)
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
