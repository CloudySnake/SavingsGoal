-- SavingsGoal core: event plumbing, DB, and per-character money tracking.
-- Money is stored in copper internally; the UI formats it into gold.

local ADDON_NAME = ...
SavingsGoal = {}
local SG = SavingsGoal

SG.VERSION = "1.0.16"
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

function SG:FormatEta(days) -- "~100 days" / "~48 years"; nil -> "no surplus yet"
    if days == nil then return "no surplus yet" end
    if days == 0 then return "complete!" end
    if days >= 730 then return "~" .. math.floor(days / 365 + 0.5) .. " years" end
    return "~" .. days .. " days"
end

function SG:OwnChar(name)
    -- any character we've ever seen on this account counts as "own".
    -- Compare bare names (before the first "-"), case-insensitively,
    -- and plain strings only: the inbox sender can arrive as just
    -- "Nox", or as the full "Nox-CAMWOW EU4 Realm 1 PvE", and the
    -- old pattern match failed on the full form (it demanded a
    -- trailing "-" after the realm, and "-" in a Lua pattern is a
    -- quantifier, not a literal). That made mail from your own alt
    -- look like a stranger's, so it landed in "Other" income.
    if not name then return false end
    local bare = (name:match("^([^-]+)") or name):lower()
    for key, _ in pairs(self.db.chars) do
        if key:lower() == name:lower() then return true end
        local kbare = (key:match("^([^-]+)") or key):lower()
        if kbare == bare then return true end
    end
    return false
end

-- --------------------------------------------------------------------- DB --
local function newCharRecord()
    return {
        income = 0, outgoing = 0,
        bySource = { ah = 0, vendor = 0, quest = 0, loot = 0, trade = 0, other = 0 },
        spentBySource = { ah = 0, vendor = 0, quest = 0, loot = 0, mail = 0, repair = 0, trade = 0, trainer = 0, taxi = 0, other = 0 },
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
    if s.dailyKeep == nil then s.dailyKeep = { mode = "pct", value = 0 } end -- held back for spending each day; 0 = off
    if s.look == nil then s.look = "modern" end -- info-screen look: "modern" or "classic"
    db.outgoingMoves = db.outgoingMoves or {} -- sent transfers awaiting receipt: {amount=, day=, from=}
    db.log = db.log or {} -- activity log: last 100 money changes, the source of truth
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
    questAmount = 0,               -- exact money reward from QUEST_TURNED_IN (see below)
    questAt = 0,                   -- GetTime() it was set (stale amounts expire)
    questSeen = false,             -- QUEST_TURNED_IN fired for this turn-in
    loot = 0,                      -- accumulated: looted gold awaiting its PLAYER_MONEY delta
    sendMoney = 0,                 -- gold attached to outgoing mail
    mailSending = false,           -- a mail send is in progress (fee may follow)
    mailOpen = false,              -- mailbox is open
    repair = 0,                    -- cost captured by the RepairAllItems hook (see below)
    lootWindowAt = 0,              -- GetTime() of the last LOOT_OPENED (see grace period below)
    lootAt = 0,                    -- GetTime() pending loot was last added (see stale-loot expiry)
    ah = false,                    -- auction house window is open
    trainer = false,               -- class trainer window is open
    trainerClosedAt = 0,
    taxi = false,                  -- taxi map is open
    taxiClosedAt = 0,
    trade = false,                 -- trade window is open
    tradeClosedAt = 0,
    bank = false,                  -- a bank frame is open (personal, guild or warband)
    bankClosedAt = 0,
}

-- A context window counts as active while open, and for a few seconds
-- after it closes: the money change can arrive after the close (the
-- loot window taught us that — auto-loot closes it before PLAYER_MONEY).
function SG:ContextActive(name)
    local p = self.pending
    if p[name] then return true end
    return GetTime() - (p[name .. "ClosedAt"] or 0) <= 5
end
SG.MAIL_FEE = 30 -- copper: the standard postage charged per mail sent
-- inbox money-mails waiting to be taken: [mailKey] = { amount = n, kind = "ah"|"move"|"refund" }
SG.pendingMail = {}
SG.claimedMail = {} -- keys already consumed, so identical re-sent mails can count again once gone
SG.ready = false  -- set on PLAYER_LOGIN; ignore money noise before that

-- Move `amount` copper of spending between source buckets (totals and
-- daily outgoing are unchanged — only the category changes). The
-- spending twin of ReclassifyIncomeSource, for e.g. an auction listing
-- fee filed as "other" before the AH window was tracked.
function SG:ReclassifySpendingSource(from, to, amount)
    local char = self:Char()
    local n = math.min(amount or 0, (char.spentBySource and char.spentBySource[from]) or 0)
    if n <= 0 then return 0 end
    char.spentBySource[from] = char.spentBySource[from] - n
    char.spentBySource[to] = (char.spentBySource[to] or 0) + n
    -- keep /sg last truthful: if this was the last recorded change,
    -- its filing is now the new bucket, not the original one
    if self.lastGain and self.lastGain.source == from and self.lastGain.amount == -n then
        self.lastGain.source = to
    end
    return n
end

-- Undo spending: an outbid refund returns money already spent, so it
-- reverses the earlier expense instead of counting as income
-- (Accountant's approach). Any part with no matching spend recorded
-- (e.g. the bid was placed before tracking) is a money move, not
-- income — the gold was his all along.
function SG:ReverseSpending(char, amount, source)
    local spent = math.min(amount, (char.spentBySource and char.spentBySource[source]) or 0)
    if spent > 0 then
        char.spentBySource[source] = char.spentBySource[source] - spent
        char.outgoing = char.outgoing - spent
        local today = self:TodayKey()
        char.daily[today] = char.daily[today] or { income = 0, outgoing = 0 }
        char.daily[today].outgoing = char.daily[today].outgoing - spent
    end
    local rest = amount - spent
    if rest > 0 then
        self:RecordMoneyMove(char, rest)
    end
    self:LogActivity(amount, "refund")
    return spent
end

-- Move `amount` copper of income between source buckets (totals and
-- daily income are unchanged — only the category changes). Used when a
-- loot chat message arrives after its money was already filed as "other".
function SG:ReclassifyIncomeSource(from, to, amount)
    local char = self:Char()
    local n = math.min(amount or 0, (char.bySource and char.bySource[from]) or 0)
    if n <= 0 then return 0 end
    char.bySource[from] = char.bySource[from] - n
    char.bySource[to] = (char.bySource[to] or 0) + n
    -- keep /sg last truthful: if this was the last recorded gain, its
    -- filing is now the new bucket, not the original one
    if self.lastGain and self.lastGain.source == from and self.lastGain.amount == n then
        self.lastGain.source = to
    end
    return n
end

-- Activity log: every money change, with what the addon could see at
-- the time — the source of truth when a filing looks wrong, instead of
-- guessing from a screenshot. Capped at 100 entries, account-wide.
function SG:LogActivity(amount, source)
    self.db.log = self.db.log or {}
    local p = self.pending
    local entry = {
        t = date("%H:%M:%S"),
        amount = amount,
        source = source,
        loot = self._lootAtDelta or 0,
        win = (GetTime() - (p.lootWindowAt or 0) <= 3) and 1 or 0,
        merch = p.merchant and 1 or 0,
        quest = p.quest and 1 or 0,
        trade = self:ContextActive("trade") and 1 or 0,
        trainer = self:ContextActive("trainer") and 1 or 0,
        taxi = self:ContextActive("taxi") and 1 or 0,
        bank = self:ContextActive("bank") and 1 or 0,
    }
    table.insert(self.db.log, entry)
    while #self.db.log > 100 do table.remove(self.db.log, 1) end
    return entry
end

function SG:ActivityLog()
    return self.db.log or {}
end

function SG:RecordDelta(char, delta, source)
    local today = self:TodayKey()
    char.daily[today] = char.daily[today] or { income = 0, outgoing = 0 }
    -- last gain, for /sg last diagnostics ("what did that loot just file as?")
    self.lastGain = { amount = delta, source = source, pendingLoot = self._lootAtDelta or 0, at = GetTime() }
    self:LogActivity(delta, source)
    if delta > 0 then
        char.income = char.income + delta
        char.daily[today].income = char.daily[today].income + delta
        char.bySource[source] = (char.bySource[source] or 0) + delta
        -- remember the latest gain filed as "other", so a loot chat
        -- message that arrives after its money can still reclassify it
        if source == "other" then
            self.lastOtherGain = { amount = delta, at = GetTime() }
        end
    else
        local d = -delta
        char.outgoing = char.outgoing + d
        char.daily[today].outgoing = char.daily[today].outgoing + d
        char.spentBySource[source] = (char.spentBySource[source] or 0) + d
    end
end

function SG:RecordMoneyMove(char, amount) -- amount signed; never touches income/outgoing
    char.moneyMoves = char.moneyMoves + math.abs(amount)
    self:LogActivity(amount, "move")
end

-- Outgoing transfer: record the move on the sender and leave a note in
-- the shared ledger so the receiving character can recognise the same
-- amount as a transfer even if its inbox scan missed the mail (sender
-- format, timing, mailbox already open). Deduped: the same amount
-- from the same character on the same day is one note.
function SG:RecordOutgoingMove(char, amount)
    self:RecordMoneyMove(char, -amount)
    self.db.outgoingMoves = self.db.outgoingMoves or {}
    for _, m in ipairs(self.db.outgoingMoves) do
        if m.amount == amount and m.from == self:CharKey() and m.day == self:TodayKey() then return end
    end
    table.insert(self.db.outgoingMoves, { amount = amount, day = self:TodayKey(), from = self:CharKey() })
end

-- Consume a ledger note matching an incoming amount, if any.
function SG:TakeOutgoingMove(delta)
    self.db.outgoingMoves = self.db.outgoingMoves or {}
    for i = #self.db.outgoingMoves, 1, -1 do
        local m = self.db.outgoingMoves[i]
        if self:DaysBetween(m.day, self:TodayKey()) > 7 then
            table.remove(self.db.outgoingMoves, i)
        elseif m.amount == delta and m.from ~= self:CharKey() then
            table.remove(self.db.outgoingMoves, i)
            return true
        end
    end
    return false
end

function SG:OnMoney()
    if not self.ready then return end
    local char = self:Char()
    local now = GetMoney()
    local delta = now - (char.lastMoney or now)
    char.lastMoney = now
    if delta == 0 then return end
    local p = self.pending
    -- stale pending loot: a loot signal with no money change behind it
    -- (window closed without taking, corpse despawned) must not claim
    -- the next unrelated gain of the same size
    if p.loot > 0 and GetTime() - (p.lootAt or 0) > 10 then
        p.loot = 0
    end
    self._lootAtDelta = p.loot -- pending loot when this money change arrived

    if delta < 0 then
        -- gold sent by mail: recorded as a money move, never as spending.
        -- PLAYER_MONEY and MAIL_SEND_SUCCESS can arrive in either order, so
        -- both directions are guarded.
        if self.recentMoveOut and (-delta) == self.recentMoveOut then
            self.recentMoveOut = nil
            return
        end
        if p.sendMoney > 0 and (-delta) == p.sendMoney then
            self:RecordOutgoingMove(char, p.sendMoney)
            p.sendMoney = 0
            return
        end
        if p.sendMoney > 0 and (-delta) > p.sendMoney then
            -- sent gold plus postage in one delta: the gold is a move,
            -- the excess is the mail fee
            local fee = (-delta) - p.sendMoney
            self:RecordOutgoingMove(char, p.sendMoney)
            p.sendMoney = 0
            self:RecordDelta(char, -fee, "mail")
            self:CheckLockedDip()
            return
        end
        if self:ContextActive("bank") then
            -- bank deposit (personal, guild or warband): a money move,
            -- like mailing gold to an alt — not spending
            self:RecordMoneyMove(char, delta)
            return
        end
        if (-delta) == self.MAIL_FEE and (p.mailSending or p.mailOpen) then
            -- postage on a mail with no gold attached (or the fee
            -- arriving as its own delta)
            self:RecordDelta(char, delta, "mail")
            self:CheckLockedDip()
            return
        end
        if p.repair and p.repair > 0 then
            -- a Repair All click captured its cost in the hook below.
            -- Exact match, or less than the captured cost (guild funds
            -- covered part of it), is a repair. More than the cost is
            -- not the repair delta at all — it's a purchase, so the
            -- stale flag is dropped and it falls through to vendor.
            local cost = p.repair
            p.repair = 0
            if (-delta) <= cost then
                self:RecordDelta(char, delta, "repair")
                self:CheckLockedDip()
                return
            end
        end
        if p.ah then
            -- auction listing fee (deposit) paid while the AH window
            -- is open. Before this the addon never watched the AH
            -- window, so deposits fell through to "other".
            self:RecordDelta(char, delta, "ah")
            self:CheckLockedDip()
            return
        end
        if self:ContextActive("trainer") then
            -- learning a spell/ability at a class trainer
            self:RecordDelta(char, delta, "trainer")
            self:CheckLockedDip()
            return
        end
        if self:ContextActive("taxi") then
            -- flight master fare: the taxi map closes as the flight
            -- starts, so the window may already be closed when the
            -- money changes (hence the grace period in ContextActive)
            self:RecordDelta(char, delta, "taxi")
            self:CheckLockedDip()
            return
        end
        if self:ContextActive("trade") then
            -- gold given to another player in the trade window
            self:RecordDelta(char, delta, "trade")
            self:CheckLockedDip()
            return
        end
        self:RecordDelta(char, delta, p.merchant and "vendor" or "other")
        self:CheckLockedDip()
        return
    end

    -- positive delta: match against pending mail. An exact match is
    -- the common case, but the money can arrive batched with another
    -- gain (several mails taken at once), so a pending mail smaller
    -- than the delta is taken out of it and the rest is judged on its
    -- own — the same split the loot fix uses. Before this, any batch
    -- missed every match and the whole delta fell through to "other".
    local remaining = delta
    while remaining > 0 do
        local matchKey, match = nil, nil
        for key, m in pairs(self.pendingMail) do
            if m.amount == remaining then matchKey, match = key, m; break end
        end
        if not match then
            for key, m in pairs(self.pendingMail) do
                if m.amount < remaining and (not match or m.amount > match.amount) then
                    matchKey, match = key, m
                end
            end
        end
        if not match then break end
        self.pendingMail[matchKey] = nil
        self.claimedMail[matchKey] = true
        if match.kind == "move" then
            self:RecordMoneyMove(char, match.amount)
        elseif match.kind == "refund" then
            self:ReverseSpending(char, match.amount, "ah")
        else
            self:RecordDelta(char, match.amount, "ah")
        end
        remaining = remaining - match.amount
    end
    if remaining == 0 then return end
    if self:TakeOutgoingMove(remaining) then
        -- transfer from another of your characters, recognised from
        -- the sender's ledger note even though the inbox scan missed it
        self:RecordMoneyMove(char, remaining)
        return
    end
    if self:ContextActive("bank") then
        -- bank withdrawal (personal, guild or warband): a money move, not income
        self:RecordMoneyMove(char, remaining)
        return
    end
    -- Loot used to need an exact match against one loot message, so it
    -- leaked into "other" whenever several loots were batched into one
    -- money delta, or a second loot overwrote the first before the
    -- money arrived. Now the pending loot accumulates, and a delta is
    -- split: the looted part is loot, the rest is judged on its own.
    if p.loot > 0 then
        local lootPart = math.min(remaining, p.loot)
        p.loot = p.loot - lootPart
        remaining = remaining - lootPart
        self:RecordDelta(char, lootPart, "loot")
        if remaining == 0 then return end
    end
    -- Loot-window grace period: with auto-loot the window can already
    -- be closed by the time the money arrives, so a boolean "is it
    -- open now" misses it. Money arriving within a few seconds of the
    -- window opening is loot even if no loot chat message ever reached
    -- us (the case behind "loot still shows as Other").
    if GetTime() - (p.lootWindowAt or 0) <= 2 then
        self:RecordDelta(char, remaining, "loot")
        return
    end
    -- Quest reward by exact amount (pH's method): QUEST_TURNED_IN
    -- passes the money reward, so the reward is filed precisely
    -- instead of relying on a sticky flag.
    if p.questAmount and p.questAmount > 0 then
        if GetTime() - (p.questAt or 0) > 10 then
            p.questAmount = 0
        else
            local questPart = math.min(remaining, p.questAmount)
            p.questAmount = p.questAmount - questPart
            remaining = remaining - questPart
            self:RecordDelta(char, questPart, "quest")
            if remaining == 0 then
                p.quest = false
                p.questSeen = false
                return
            end
        end
    end
    if p.questSeen then
        -- QUEST_TURNED_IN fired: the amount above handled any reward,
        -- so a turn-in with no money reward must not claim the next gain
        p.quest = false
        p.questSeen = false
    elseif p.quest then
        -- fallback for clients where QUEST_TURNED_IN never fires
        p.quest = false
        self:RecordDelta(char, remaining, "quest")
        return
    end
    if p.merchant then
        self:RecordDelta(char, remaining, "vendor")
        return
    end
    if self:ContextActive("trade") then
        -- gold received from another player in the trade window
        self:RecordDelta(char, remaining, "trade")
        return
    end
    self:RecordDelta(char, remaining, "other")
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
                -- AH mail by sender or by subject (Accountant checks
                -- the subject: "Auction successful: ..."). The sender
                -- alone proved unreliable — a sale arrived with no
                -- matching sender and fell through to "other".
                local isAH = (sender and sender:lower():find("auction"))
                    or (subject and subject:lower():find("auction successful", 1, true))
                if isAH then
                    -- an "Outbid" mail returns a bid already paid: it
                    -- reverses the earlier AH expense, it is not income
                    if subject and subject:lower():find("outbid", 1, true) then
                        kind = "refund"
                    else
                        kind = "ah"
                    end
                elseif self:OwnChar(sender) then
                    kind = "move"
                end
                -- unknown senders: left untracked, counted as ordinary income when taken
                if kind then
                    self.pendingMail[key] = { amount = money, kind = kind, sender = sender, subject = subject }
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
SG:Register("MERCHANT_CLOSED", function(self) self.pending.merchant = false; self.pending.repair = 0 end)

SG:Register("AUCTION_HOUSE_SHOW", function(self) self.pending.ah = true end)
SG:Register("AUCTION_HOUSE_CLOSED", function(self) self.pending.ah = false end)

-- the four contexts added in v1.0.15: each counts while open and for
-- a few seconds after closing (ContextActive), because the money
-- change can arrive after the close
SG:Register("TRAINER_SHOW", function(self) self.pending.trainer = true end)
SG:Register("TRAINER_CLOSED", function(self) self.pending.trainer = false; self.pending.trainerClosedAt = GetTime() end)
SG:Register("TAXIMAP_OPENED", function(self) self.pending.taxi = true end)
SG:Register("TAXIMAP_CLOSED", function(self) self.pending.taxi = false; self.pending.taxiClosedAt = GetTime() end)
SG:Register("TRADE_SHOW", function(self) self.pending.trade = true end)
SG:Register("TRADE_CLOSED", function(self) self.pending.trade = false; self.pending.tradeClosedAt = GetTime() end)
-- Bank frames: which events fire is disputed — Gold Digger says
-- The War Within folded guild/warband bank into BANKFRAME_OPENED /
-- BANKFRAME_CLOSED, while Warband Accountant and retail Accountant
-- still register GUILDBANKFRAME_OPENED / CLOSED. Register both, so
-- whichever the Forever client fires is caught. A bank deposit or
-- withdrawal is a money move either way (personal, guild or warband).
SG:Register("GUILDBANKFRAME_OPENED", function(self) self.pending.bank = true end)
SG:Register("GUILDBANKFRAME_CLOSED", function(self) self.pending.bank = false; self.pending.bankClosedAt = GetTime() end)
SG:Register("BANKFRAME_OPENED", function(self) self.pending.bank = true end)
SG:Register("BANKFRAME_CLOSED", function(self) self.pending.bank = false; self.pending.bankClosedAt = GetTime() end)

-- Scan the loot window for coin slots (FonzAppraiser's approach):
-- the money is sitting in the window as a coin slot before it is ever
-- taken, so this does not depend on chat text at all. Works for corpse
-- loot and pickpocketing alike — both open a loot window.
function SG:ScanLootWindow()
    if not GetNumLootItems or not LootSlotIsCoin or not GetLootSlotInfo then return end
    local total = 0
    for i = 1, (GetNumLootItems() or 0) do
        if LootSlotIsCoin(i) then
            local _, name, quantity = GetLootSlotInfo(i)
            local amount = quantity or 0
            if amount == 0 and name then amount = self:ParseLootMoney(name) end
            if amount > 0 then total = total + amount end
        end
    end
    if total > 0 then
        self.pending.loot = self.pending.loot + total
        self.pending.lootAt = GetTime()
        self.lastCoinScan = { amount = total, at = GetTime() }
    end
end

SG:Register("LOOT_OPENED", function(self)
    self.pending.lootWindowAt = GetTime()
    self:ScanLootWindow()
end)
SG:Register("LOOT_CLOSED", function(self) end) -- the timestamp is what matters, not the close

SG:Register("QUEST_TURNED_IN", function(self, questID, xpReward, moneyReward)
    self.pending.questSeen = true
    if moneyReward and moneyReward > 0 then
        self.pending.questAmount = (self.pending.questAmount or 0) + moneyReward
        self.pending.questAt = GetTime()
    end
end)
SG:Register("QUEST_TURN_IN_COMPLETE", function(self) self.pending.quest = true end)

-- Parse "You loot 12 Gold, 34 Silver, 56 Copper." (or just the
-- "12 Gold, 34 Silver, 56 Copper" part) into copper; 0 if no money.
function SG:ParseLootMoney(text)
    if type(text) ~= "string" then return 0 end
    local g = tonumber(text:match("(%d+) [Gg]old")) or 0
    local s = tonumber(text:match("(%d+) [Ss]ilver")) or 0
    local c = tonumber(text:match("(%d+) [Cc]opper")) or 0
    return g * 10000 + s * 100 + c
end

-- One handler for every chat event that can carry a loot-money message.
-- Why three events, and why the filter below: on the Midnight client
-- (which Forever runs on) chat text is handed to event handlers as a
-- protected "secret" that errors when touched — Loot Pro hit exactly
-- this and switched to ChatFrame_AddMessageEventFilter, whose callback
-- runs in an untainted frame and can read the text. And some private
-- servers emit money messages as system text instead of CHAT_MSG_MONEY
-- (FonzAppraiser's compatibility note), so CHAT_MSG_SYSTEM is covered
-- too; CHAT_MSG_LOOT covers the same text arriving as a loot message.
function SG:OnLootMoneyMessage(event, msg)
    -- Prefer text stashed by the chat filter; never touch the event
    -- arg if the stash has it (the arg may be a secret that errors).
    local text = SG.chatText and SG.chatText[event]
    if SG.chatText then SG.chatText[event] = nil end
    local amount = 0
    if text then
        amount = self:ParseLootMoney(text)
    else
        local ok, parsed = pcall(function() return self:ParseLootMoney(msg) end)
        if ok then amount = parsed end
    end
    if amount <= 0 then return end
    -- System and loot messages must actually be about looting ("You
    -- receive 5 Gold" from a quest is not loot); CHAT_MSG_MONEY is
    -- money-specific, so it needs no such check. The event arg is
    -- only read inside pcall — on Midnight clients it may be a
    -- protected secret that errors when touched.
    if event ~= "CHAT_MSG_MONEY" then
        local hay = text
        if not hay then
            local ok, lowered = pcall(function() return msg:lower() end)
            if ok then hay = lowered end
        end
        if not hay or not hay:find("loot", 1, true) then return end
    end
    -- Already filed as loot (chat arrived after the money): don't
    -- stack a pending amount a later gain would then claim.
    local lg = self.lastGain
    if lg and lg.source == "loot" and lg.amount == amount and GetTime() - (lg.at or 0) <= 10 then return end
    -- Already counted by the loot-window coin scan for the same loot.
    local cs = self.lastCoinScan
    if cs and cs.amount == amount and GetTime() - cs.at <= 3 then return end
    -- If the money already arrived and was filed as "other" (chat
    -- after money), move that gain into loot.
    local last = self.lastOtherGain
    if last and last.amount == amount and GetTime() - last.at <= 10 then
        self.lastOtherGain = nil
        self:ReclassifyIncomeSource("other", "loot", amount)
        return
    end
    self.pending.loot = self.pending.loot + amount -- accumulate, don't overwrite
    self.pending.lootAt = GetTime()
end

SG:Register("CHAT_MSG_MONEY", function(self, msg) self:OnLootMoneyMessage("CHAT_MSG_MONEY", msg) end)
SG:Register("CHAT_MSG_SYSTEM", function(self, msg) self:OnLootMoneyMessage("CHAT_MSG_SYSTEM", msg) end)
SG:Register("CHAT_MSG_LOOT", function(self, msg) self:OnLootMoneyMessage("CHAT_MSG_LOOT", msg) end)

-- Stash chat text in the filter, before OnEvent runs: the filter runs
-- in an untainted Blizzard frame and can read the text, while the
-- event handler's arg may be a protected secret on Midnight clients.
if ChatFrame_AddMessageEventFilter then
    for _, ev in ipairs({ "CHAT_MSG_MONEY", "CHAT_MSG_SYSTEM", "CHAT_MSG_LOOT" }) do
        ChatFrame_AddMessageEventFilter(ev, function(_, _, msg)
            SG.chatText = SG.chatText or {}
            SG.chatText[ev] = msg
            return false
        end)
    end
end

SG:Register("MAIL_INBOX_UPDATE", function(self) self:ScanInbox() end)

-- scan on open as well as on inbox updates: a sale mail must be
-- registered before the player can take it, and the inbox contents
-- are re-read on the next update anyway, so an early empty scan
-- cannot lose anything
SG:Register("MAIL_SHOW", function(self) self.pending.mailOpen = true; self:ScanInbox() end)
SG:Register("MAIL_CLOSED", function(self) self.pending.mailOpen = false; self.pending.mailSending = false end)

-- Repairs: the established approach (GoldLedger, Gold Digger) is to
-- hook RepairAllItems and capture GetRepairAllCost() there, *before*
-- the money event fires. Checking the cost after the fact always
-- returns 0, because the gear is already repaired by then. The hook
-- runs when the player clicks Repair All; the next money delta that
-- matches (or is less than, if guild funds covered part of it) is the
-- repair bill. Guild-only repairs deduct nothing from the player, so
-- no delta arrives and the flag is dropped when the merchant closes.
if RepairAllItems then
    hooksecurefunc("RepairAllItems", function()
        local cost = GetRepairAllCost() or 0
        if cost > 0 then SG.pending.repair = cost end
    end)
end

-- outgoing mail: hook the money setter; MAIL_SEND_SUCCESS confirms it sent
hooksecurefunc("SetSendMailMoney", function(copper)
    SG.pending.sendMoney = copper or 0
    SG.pending.mailSending = true
end)

SG:Register("MAIL_SEND_SUCCESS", function(self)
    local amt = self.pending.sendMoney
    self.pending.sendMoney = 0
    self.pending.mailSending = false
    if amt and amt > 0 then
        -- assumption (documented in SPEC): gold mailed goes to your own bank alt.
        -- If PLAYER_MONEY hasn't fired yet, its delta arrives next: swallow it.
        self:RecordOutgoingMove(self:Char(), amt)
        self.recentMoveOut = amt
    end
end)

print("|cff33ff99SavingsGoal|r v" .. SG.VERSION .. " loaded. Type |cffffff00/sg|r to open.")
