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

    test("loot: several loots batched into one delta stay loot", function()
        -- Regression 7 Nov 2026: loot showed as "Other" when loots
        -- were batched, because pending loot held only one amount
        -- and needed an exact match.
        local SG = fresh(0)
        fire(SG, "CHAT_MSG_MONEY", "You loot 1 Gold.")
        fire(SG, "CHAT_MSG_MONEY", "You loot 50 Silver.")
        setMoney(SG, 15000)
        assertEq(SG:Char().bySource.loot, 15000)
        assertEq(SG:Char().bySource.other, 0)
    end)

    test("loot: a delta split between loot and the rest", function()
        local SG = fresh(0)
        fire(SG, "CHAT_MSG_MONEY", "You loot 1 Gold.")
        setMoney(SG, 15000) -- 1g loot + 50s from elsewhere in one tick
        assertEq(SG:Char().bySource.loot, 10000)
        assertEq(SG:Char().bySource.other, 5000)
    end)

    test("loot: chat arriving after the money reclassifies it", function()
        local SG = fresh(0)
        setMoney(SG, 5000) -- money first: filed as other
        assertEq(SG:Char().bySource.other, 5000)
        fire(SG, "CHAT_MSG_MONEY", "You loot 50 Silver.")
        assertEq(SG:Char().bySource.loot, 5000)
        assertEq(SG:Char().bySource.other, 0)
        assertEq(SG:Char().income, 5000) -- total unchanged, only the bucket moved
    end)

    test("mail fee: sent gold plus postage splits into move and mail", function()
        local SG = fresh(100000)
        stubs.callHook("SetSendMailMoney", 50000)
        setMoney(SG, 49970) -- 50000 gold sent + 30c postage in one delta
        local char = SG:Char()
        assertEq(char.moneyMoves, 50000)
        assertEq(char.spentBySource.mail, 30)
        assertEq(char.outgoing, 30)
        assertEq(SG:SpendingBySource().mail, 30)
    end)

    test("repair: Repair All click is filed as Repairs, not Vendor", function()
        local SG = fresh(100000)
        fire(SG, "MERCHANT_SHOW")
        stubs.state.repairCost = 2500
        stubs.callHook("RepairAllItems")
        setMoney(SG, 97500)
        local char = SG:Char()
        assertEq(char.spentBySource.repair, 2500)
        assertEq(char.spentBySource.vendor, 0)
        assertEq(char.outgoing, 2500)
        assertEq(SG:SpendingBySource().repair, 2500)
    end)

    test("repair: guild covering part of the bill still files as Repairs", function()
        local SG = fresh(100000)
        fire(SG, "MERCHANT_SHOW")
        stubs.state.repairCost = 5000
        stubs.callHook("RepairAllItems")
        setMoney(SG, 97000) -- player paid 3000 of a 5000 bill
        assertEq(SG:Char().spentBySource.repair, 3000)
    end)

    test("repair: a purchase bigger than the repair cost is not a repair", function()
        local SG = fresh(100000)
        fire(SG, "MERCHANT_SHOW")
        stubs.state.repairCost = 2500
        stubs.callHook("RepairAllItems")
        setMoney(SG, 96000) -- bought something for 4000; repair never happened
        assertEq(SG:Char().spentBySource.repair, 0)
        assertEq(SG:Char().spentBySource.vendor, 4000)
    end)

    test("loot: money arriving with the loot window open is loot", function()
        -- GoldLedger's other loot signal: no chat message needed.
        local SG = fresh(0)
        fire(SG, "LOOT_OPENED")
        setMoney(SG, 5000)
        assertEq(SG:Char().bySource.loot, 5000)
        assertEq(SG:Char().bySource.other, 0)
    end)

    test("mail fee: postage on a mail with no gold attached", function()
        local SG = fresh(100000)
        fire(SG, "MAIL_SHOW")
        setMoney(SG, 99970)
        assertEq(SG:Char().spentBySource.mail, 30)
        assertEq(SG:Char().outgoing, 30)
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

    test("inbox: full Name-Realm sender from own alt is a money move", function()
        -- Regression 7 Nov 2026: mail from your own alt showed as
        -- "Other" income. The inbox sender can arrive as the full
        -- "Bankalt-Testrealm", and OwnChar failed on that form.
        local SG = fresh(0)
        SG.db.chars["Bankalt-Testrealm"] = { lastMoney = 0 }
        stubs.state.inbox = {
            { sender = "Bankalt-Testrealm", subject = "gold", money = 20000 },
            { sender = "BANKALT", subject = "gold", money = 30000 },
        }
        fire(SG, "MAIL_INBOX_UPDATE")
        setMoney(SG, 20000)
        assertEq(SG:Char().moneyMoves, 20000)
        assertEq(SG:Char().income, 0)
        setMoney(SG, 50000)
        assertEq(SG:Char().moneyMoves, 50000)
        assertEq(SG:Char().income, 0)
    end)

    test("ledger: transfer recognised on the receiving alt with no inbox scan", function()
        -- The sender leaves a ledger note; the receiver matches the
        -- amount against it even if its inbox scan never ran.
        local SG = fresh(100000)
        stubs.callHook("SetSendMailMoney", 50000)
        fire(SG, "MAIL_SEND_SUCCESS")
        assertEq(SG:Char().moneyMoves, 50000)
        stubs.state.playerName = "Bankalt"
        stubs.state.money = 0
        for _, h in ipairs(SG.handlers["PLAYER_LOGIN"]) do h(SG) end
        setMoney(SG, 50000)
        local alt = SG:Char()
        assertEq(alt.moneyMoves, 50000)
        assertEq(alt.income, 0)
        assertEq(alt.bySource.other, 0)
    end)

    test("reclassify income source: other -> loot, totals unchanged", function()
        local SG = fresh(0)
        setMoney(SG, 5000)
        assertEq(SG:Char().bySource.other, 5000)
        assertEq(SG:ReclassifyIncomeSource("other", "loot", 5000), 5000)
        assertEq(SG:Char().bySource.other, 0)
        assertEq(SG:Char().bySource.loot, 5000)
        assertEq(SG:Char().income, 5000)
        assertEq(SG:ReclassifyIncomeSource("other", "loot", 5000), 0)
    end)

    test("last gain records what a change was filed as", function()
        local SG = fresh(0)
        fire(SG, "CHAT_MSG_MONEY", "You loot 1 Gold.")
        setMoney(SG, 10000)
        assertEq(SG.lastGain.source, "loot")
        assertEq(SG.lastGain.amount, 10000)
        assertEq(SG.lastGain.pendingLoot, 10000)
    end)

    test("reclassify move: 'Other' income becomes a money move", function()
        local SG = fresh(0)
        setMoney(SG, 5000) -- plain gain -> other
        assertEq(SG:Char().bySource.other, 5000)
        assertEq(SG:ReclassifyMove(5000), 5000)
        local char = SG:Char()
        assertEq(char.bySource.other, 0)
        assertEq(char.income, 0)
        assertEq(char.moneyMoves, 5000)
        assertEq(char.daily[SG:TodayKey()].income, 0)
        assertEq(SG:ReclassifyMove(5000), 0) -- nothing left to move
    end)

    test("ParseGold handles g/s/c", function()
        local SG = fresh(0)
        assertEq(SG:ParseGold("50s"), 5000)
        assertEq(SG:ParseGold("1g 20s 30c"), 12030)
        assertEq(SG:ParseGold("bogus"), nil)
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
