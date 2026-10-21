-- Tests for core.lua: money tracking, source attribution, money moves.
-- Run via run.lua (needs wow_stubs.lua loaded first).

return function(stubs, ADDON)
    print("core.lua")

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

    local function fire(SG, event, ...)
        for _, h in ipairs(SG.handlers[event]) do h(SG, ...) end
    end

    local function setMoney(SG, copper)
        stubs.state.money = copper
        fire(SG, "PLAYER_MONEY")
    end

    test("login baselines lastMoney with no phantom delta", function()
        local SG = fresh(100000)
        local char = SG:Char()
        assertEq(char.lastMoney, 100000)
        assertEq(char.income, 0)
    end)

    test("plain gain is income from 'other'", function()
        local SG = fresh(100000)
        setMoney(SG, 110000)
        local char = SG:Char()
        assertEq(char.income, 10000)
        assertEq(char.bySource.other, 10000)
        assertEq(char.daily[SG:TodayKey()].income, 10000)
    end)

    test("merchant window attributes vendoring", function()
        local SG = fresh(100000)
        fire(SG, "MERCHANT_SHOW")
        setMoney(SG, 105000) -- sold greys
        local char = SG:Char()
        assertEq(char.bySource.vendor, 5000)
        setMoney(SG, 103000) -- repairs
        assertEq(char.outgoing, 2000)
        assertEq(char.spentBySource.vendor, 2000)
        fire(SG, "MERCHANT_CLOSED")
        setMoney(SG, 104000) -- outside merchant: back to other
        assertEq(char.bySource.other, 1000)
    end)

    test("quest turn-in attributed to quests", function()
        local SG = fresh(0)
        fire(SG, "QUEST_TURN_IN_COMPLETE", 12345)
        setMoney(SG, 3000)
        assertEq(SG:Char().bySource.quest, 3000)
    end)

    test("loot message attributes loot gold", function()
        local SG = fresh(0)
        fire(SG, "CHAT_MSG_MONEY", "You loot 1 Gold, 2 Silver, 3 Copper.")
        setMoney(SG, 10203)
        assertEq(SG:Char().bySource.loot, 10203)
    end)

    test("outgoing mail is a money move, not spending", function()
        local SG = fresh(100000)
        stubs.callHook("SetSendMailMoney", 50000)
        fire(SG, "MAIL_SEND_SUCCESS")
        local char = SG:Char()
        assertEq(char.moneyMoves, 50000)
        assertEq(char.income, 0)
        assertEq(char.outgoing, 0)
        -- the follow-up PLAYER_MONEY delta for the sent gold is swallowed
        setMoney(SG, 50000)
        assertEq(char.outgoing, 0)
    end)

    test("outgoing mail: money delta before send confirmation", function()
        -- some clients fire PLAYER_MONEY before MAIL_SEND_SUCCESS; still a move
        local SG = fresh(100000)
        stubs.callHook("SetSendMailMoney", 50000)
        setMoney(SG, 50000)
        fire(SG, "MAIL_SEND_SUCCESS")
        local char = SG:Char()
        assertEq(char.moneyMoves, 50000)
        assertEq(char.outgoing, 0)
    end)

    test("inbox: AH mail is income, own-char mail is a money move", function()
        local SG = fresh(0)
        SG.db.chars["Bankalt-Testrealm"] = { lastMoney = 0 } -- own alt
        stubs.state.inbox = {
            { sender = "Auction House", subject = "Auction successful", money = 10000 },
            { sender = "Bankalt", subject = "gold", money = 20000 },
            { sender = "Stranger", subject = "thanks!", money = 5000 },
        }
        fire(SG, "MAIL_INBOX_UPDATE")
        assertEq(2, 0 + (function() local n = 0 for _ in pairs(SG.pendingMail) do n = n + 1 end return n end)())
        local char = SG:Char()
        setMoney(SG, 10000) -- take the AH gold
        assertEq(char.bySource.ah, 10000)
        setMoney(SG, 30000) -- take the alt's gold
        assertEq(char.moneyMoves, 20000)
        assertEq(char.income, 10000) -- only the AH gold counted as income
        setMoney(SG, 35000) -- stranger's gold: ordinary income
        assertEq(char.bySource.other, 5000)
    end)

    test("reopening the mailbox does not lose pending mail", function()
        local SG = fresh(0)
        SG.db.chars["Bankalt-Testrealm"] = { lastMoney = 0 }
        stubs.state.inbox = {
            { sender = "Auction House", subject = "Auction successful", money = 10000 },
        }
        fire(SG, "MAIL_INBOX_UPDATE")
        fire(SG, "MAIL_INBOX_UPDATE") -- reopen: scan runs again
        fire(SG, "MAIL_INBOX_UPDATE")
        setMoney(SG, 10000)
        assertEq(SG:Char().bySource.ah, 10000)
    end)

    test("daily buckets accumulate within a day", function()
        local SG = fresh(0)
        setMoney(SG, 5000)
        setMoney(SG, 8000)
        local d = SG:Char().daily[SG:TodayKey()]
        assertEq(d.income, 8000)
    end)
end
