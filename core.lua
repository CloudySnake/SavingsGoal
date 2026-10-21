-- SavingsGoal core: event plumbing, DB, and per-character money tracking.
-- Money is stored in copper internally; the UI formats it into gold.

local ADDON_NAME = ...
SavingsGoal = {}
local SG = SavingsGoal

SG.VERSION = "1.0.0"
SG.WINDOW_DAYS = 14 -- trailing window for daily surplus

-- ---------------------------------------------------------------- events --
local frame = CreateFrame("Frame")
SG.handlers = {}
frame:SetScript("OnEvent", function(_, event, ...)
    local list = SG.handlers[event]
    if list then
        for _, h in ipairs(list) do h(SG, ...) end
    end
end)

function SG:Register(event, handler)
    self.handlers[event] = self.handlers[event] or {}
    table.insert(self.handlers[event], handler)
    frame:RegisterEvent(event)
end

-- ------------------------------------------------------------------ utils --
function SG:CharKey()
    return (UnitName("player") or "Unknown") .. "-" .. (GetRealmName() or "Unknown")
end

function SG:TodayKey()
    return date("%Y-%m-%d")
end

function SG:DaysBetween(a, b) -- "YYYY-MM-DD" strings
    local function toTime(s)
        local y, m, d = s:match("(%d+)-(%d+)-(%d+)")
        return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    end
    return math.floor((toTime(b) - toTime(a)) / 86400 + 0.5)
end

function SG:Comma(n)
    local s = tostring(math.floor(math.abs(n)))
    while true do
        local replaced
        s, replaced = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if replaced == 0 then break end
    end
    return (n < 0 and "-" or "") .. s
end

function SG:FormatGold(copper) -- "1,240g 12s 30c"
    local neg = copper < 0
    copper = math.floor(math.abs(copper) + 0.5)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local t = string.format("%sg %ds %dc", self:Comma(g), s, c)
    return neg and ("-" .. t) or t
end

function SG:FormatGoldShort(copper) -- "1,240g"
    local g = math.floor(math.abs(copper) / 10000 + 0.5)
    return (copper < 0 and "-" or "") .. self:Comma(g) .. "g"
end

function SG:OwnChar(name)
    -- any character we've ever seen on this account counts as "own"
    if not name then return false end
    for key, _ in pairs(self.db.chars) do
        if key == name .. "-" .. (GetRealmName() or "") or key:match("^" .. name .. "%-") then
            return true
        end
    end
    return false
end

-- --------------------------------------------------------------------- DB --
local function newCharRecord()
    return {
        income = 0, outgoing = 0,
        bySource = { ah = 0, vendor = 0, quest = 0, loot = 0, other = 0 },
        spentBySource = { ah = 0, vendor = 0, quest = 0, loot = 0, other = 0 },
        moneyMoves = 0, -- gold moved between own chars (tracked, excluded from surplus)
        daily = {},    -- ["YYYY-MM-DD"] = { income = n, outgoing = n }
        lastMoney = 0,
    }
end

function SG:InitDB()
    SavingsGoalDB = SavingsGoalDB or {}
    local db = SavingsGoalDB
    db.chars = db.chars or {}
    db.goals = db.goals or {}
    db.settings = db.settings or {}
    local s = db.settings
    if s.windowDays == nil then s.windowDays = self.WINDOW_DAYS end
    if s.minimap == nil then s.minimap = true end
    if s.spendBuffer == nil then s.spendBuffer = 0 end -- copper never locked
    self.db = db
end

function SG:Char()
    local key = self:CharKey()
    if not self.db.chars[key] then
        self.db.chars[key] = newCharRecord()
    end
    return self.db.chars[key]
end

function SG:PruneDaily(char)
    -- keep 45 days of history; surplus uses settings.windowDays
    local cutoff = self:DaysBetween("2000-01-01", self:TodayKey()) - 45
    for day, _ in pairs(char.daily) do
        if self:DaysBetween("2000-01-01", day) < cutoff then
            char.daily[day] = nil
        end
    end
end

-- ------------------------------------------------------ money attribution --
-- pending context: what the next PLAYER_MONEY delta probably was
SG.pending = {
    merchant = false,
    quest = false,
    loot = 0,
    sendMoney = 0,                 -- gold attached to outgoing mail
}
-- inbox money-mails waiting to be taken: [mailKey] = { amount = n, kind = "ah"|"move" }
SG.pendingMail = {}
SG.claimedMail = {} -- keys already consumed, so identical re-sent mails can count again once gone
SG.ready = false  -- set on PLAYER_LOGIN; ignore money noise before that

function SG:RecordDelta(char, delta, source)
    local today = self:TodayKey()
    char.daily[today] = char.daily[today] or { income = 0, outgoing = 0 }
    if delta > 0 then
        char.income = char.income + delta
        char.daily[today].income = char.daily[today].income + delta
        char.bySource[source] = (char.bySource[source] or 0) + delta
    else
        local d = -delta
        char.outgoing = char.outgoing + d
        char.daily[today].outgoing = char.daily[today].outgoing + d
        char.spentBySource[source] = (char.spentBySource[source] or 0) + d
    end
end

function SG:RecordMoneyMove(char, amount) -- amount signed; never touches income/outgoing
    char.moneyMoves = char.moneyMoves + math.abs(amount)
end

function SG:OnMoney()
    if not self.ready then return end
    local char = self:Char()
    local now = GetMoney()
    local delta = now - (char.lastMoney or now)
    char.lastMoney = now
    if delta == 0 then return end
    local p = self.pending

    if delta < 0 then
        -- gold sent by mail: recorded as a money move, never as spending.
        -- PLAYER_MONEY and MAIL_SEND_SUCCESS can arrive in either order, so
        -- both directions are guarded.
        if self.recentMoveOut and (-delta) == self.recentMoveOut then
            self.recentMoveOut = nil
            return
        end
        if p.sendMoney > 0 and (-delta) == p.sendMoney then
            self:RecordMoneyMove(char, -p.sendMoney)
            p.sendMoney = 0
            return
        end
        self:RecordDelta(char, delta, p.merchant and "vendor" or "other")
        self:CheckLockedDip()
        return
    end

    -- positive delta: match against pending contexts
    for key, m in pairs(self.pendingMail) do
        if m.amount == delta then
            self.pendingMail[key] = nil
            self.claimedMail[key] = true
            if m.kind == "move" then
                self:RecordMoneyMove(char, delta)
            else
                self:RecordDelta(char, delta, "ah")
            end
            return
        end
    end
    if p.loot > 0 and delta == p.loot then
        p.loot = 0
        self:RecordDelta(char, delta, "loot")
        return
    end
    if p.quest then
        p.quest = false
        self:RecordDelta(char, delta, "quest")
        return
    end
    if p.merchant then
        self:RecordDelta(char, delta, "vendor")
        return
    end
    self:RecordDelta(char, delta, "other")
end

-- --------------------------------------------------------------- mail scan --
local function mailKey(sender, subject, money)
    return (sender or "?") .. "|" .. (subject or "?") .. "|" .. tostring(money)
end

function SG:ScanInbox()
    local n = GetInboxNumItems() or 0
    local seen = {}
    for i = 1, n do
        local _, _, sender, subject, money = GetInboxHeaderInfo(i)
        money = money or 0
        if money > 0 then
            local key = mailKey(sender, subject, money)
            seen[key] = true
            if not self.pendingMail[key] and not self.claimedMail[key] then
                local kind = nil
                if sender and sender:lower():find("auction") then
                    kind = "ah"
                elseif self:OwnChar(sender) then
                    kind = "move"
                end
                -- unknown senders: left untracked, counted as ordinary income when taken
                if kind then
                    self.pendingMail[key] = { amount = money, kind = kind }
                end
            end
        end
    end
    -- mails that vanished were taken or deleted: drop them from pending,
    -- and forget claimed keys so an identical re-sent mail counts again
    for key, _ in pairs(self.pendingMail) do
        if not seen[key] then self.pendingMail[key] = nil end
    end
    for key, _ in pairs(self.claimedMail) do
        if not seen[key] then self.claimedMail[key] = nil end
    end
end

-- ------------------------------------------------------------------ events --
SG:Register("ADDON_LOADED", function(self, name)
    if name ~= ADDON_NAME then return end
    self:InitDB()
end)

SG:Register("PLAYER_LOGIN", function(self)
    local char = self:Char()
    if char.lastMoney == 0 then
        char.lastMoney = GetMoney() -- baseline; no delta on first sight
    end
    self.ready = true
    self:PruneDaily(char)
    self:TickGoals()
    -- broker.lua provides these; guarded so core also stands alone (e.g. in tests)
    if self.RefreshBroker then self:RefreshBroker() end
    if self.RefreshMinimap then self:RefreshMinimap() end
end)

SG:Register("PLAYER_MONEY", function(self) self:OnMoney() end)

SG:Register("MERCHANT_SHOW", function(self) self.pending.merchant = true end)
SG:Register("MERCHANT_CLOSED", function(self) self.pending.merchant = false end)

SG:Register("QUEST_TURN_IN_COMPLETE", function(self) self.pending.quest = true end)

SG:Register("CHAT_MSG_MONEY", function(self, msg)
    -- "You loot 12 Gold, 34 Silver, 56 Copper."
    local g = tonumber(msg:match("(%d+) [Gg]old")) or 0
    local s = tonumber(msg:match("(%d+) [Ss]ilver")) or 0
    local c = tonumber(msg:match("(%d+) [Cc]opper")) or 0
    local amount = g * 10000 + s * 100 + c
    if amount > 0 then self.pending.loot = amount end
end)

SG:Register("MAIL_INBOX_UPDATE", function(self) self:ScanInbox() end)

-- outgoing mail: hook the money setter; MAIL_SEND_SUCCESS confirms it sent
hooksecurefunc("SetSendMailMoney", function(copper)
    SG.pending.sendMoney = copper or 0
end)

SG:Register("MAIL_SEND_SUCCESS", function(self)
    local amt = self.pending.sendMoney
    self.pending.sendMoney = 0
    if amt and amt > 0 then
        -- assumption (documented in SPEC): gold mailed goes to your own bank alt.
        -- If PLAYER_MONEY hasn't fired yet, its delta arrives next: swallow it.
        self:RecordMoneyMove(self:Char(), -amt)
        self.recentMoveOut = amt
    end
end)

print("|cff33ff99SavingsGoal|r v" .. SG.VERSION .. " loaded. Type |cffffff00/sg|r to open.")
