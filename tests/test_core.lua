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
        -- /sg last must report the final filing, not the original one:
        -- before this fix it still said 'other' after a reclassify
        assertEq(SG.lastGain.source, "loot")
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

    test("loot: coin slot in the loot window files the money as loot, with no chat", function()
        -- the money sits in the window as a coin slot before it is
        -- taken, so this needs no chat text at all (Martin's case:
        -- the loot message never reached the addon)
        local SG = fresh(0)
        stubs.state.lootSlots = {
            { coin = true, quantity = 4, name = "4 Copper" },
            { coin = false, quantity = 1, name = "Linen Cloth" },
        }
        fire(SG, "LOOT_OPENED")
        assertEq(SG.pending.loot, 4)
        setMoney(SG, 4)
        assertEq(SG:Char().bySource.loot, 4)
        assertEq(SG:Char().bySource.other, 0)
    end)

    test("loot: chat arriving after a coin-scanned loot does not double-count it", function()
        local SG = fresh(0)
        stubs.state.lootSlots = { { coin = true, quantity = 4, name = "4 Copper" } }
        fire(SG, "LOOT_OPENED")
        setMoney(SG, 4) -- filed as loot from the coin scan
        assertEq(SG:Char().bySource.loot, 4)
        fire(SG, "CHAT_MSG_MONEY", "You loot 4 Copper") -- arrives late: must not stack pending loot
        assertEq(SG.pending.loot, 0)
        stubs.state.time = stubs.state.time + 5 -- past the loot-window grace period
        setMoney(SG, 8) -- a later, unrelated 4c gain is not loot
        assertEq(SG:Char().bySource.other, 4)
        assertEq(SG:Char().bySource.loot, 4)
    end)

    test("loot: grace period covers a window that closed before the money arrived", function()
        -- auto-loot closes the window before PLAYER_MONEY fires, so
        -- "is the window open now" misses it; the timestamp doesn't
        local SG = fresh(0)
        fire(SG, "LOOT_OPENED") -- empty window: the coin scan finds nothing
        stubs.state.time = stubs.state.time + 1
        setMoney(SG, 5000)
        assertEq(SG:Char().bySource.loot, 5000)
        stubs.state.time = stubs.state.time + 10
        setMoney(SG, 6000) -- 11s after the window: no longer loot
        assertEq(SG:Char().bySource.other, 1000)
    end)

    test("loot: money message arriving as system text is loot", function()
        -- some private servers emit money messages as system text
        -- instead of CHAT_MSG_MONEY (FonzAppraiser's compatibility note)
        local SG = fresh(0)
        fire(SG, "CHAT_MSG_SYSTEM", "You loot 50 Silver.")
        setMoney(SG, 5000)
        assertEq(SG:Char().bySource.loot, 5000)
        assertEq(SG:Char().bySource.other, 0)
    end)

    test("loot: system text that is not about looting is ignored", function()
        local SG = fresh(0)
        fire(SG, "CHAT_MSG_SYSTEM", "You receive 50 Silver.")
        setMoney(SG, 5000)
        assertEq(SG:Char().bySource.other, 5000)
        assertEq(SG:Char().bySource.loot, 0)
    end)

    test("loot: filter-stashed text is used when the event arg is unreadable", function()
        -- on Midnight clients the event arg can be a protected secret;
        -- the chat filter stashes readable text before OnEvent runs
        local SG = fresh(0)
        SG.chatText = { CHAT_MSG_MONEY = "You loot 1 Gold." }
        fire(SG, "CHAT_MSG_MONEY", nil)
        assertEq(SG.pending.loot, 10000)
        fire(SG, "CHAT_MSG_MONEY", {}) -- a non-string arg must not error
        assertEq(SG.pending.loot, 10000)
    end)

    test("activity log records each change with its context", function()
        local SG = fresh(0)
        setMoney(SG, 100)
        fire(SG, "CHAT_MSG_MONEY", "You loot 50 Silver.")
        setMoney(SG, 5100)
        local log = SG:ActivityLog()
        assertEq(#log, 2)
        assertEq(log[1].amount, 100)
        assertEq(log[1].source, "other")
        assertEq(log[2].amount, 5000)
        assertEq(log[2].source, "loot")
        assertEq(log[2].loot, 5000)
        -- capped at 100 entries
        for _ = 1, 105 do SG:LogActivity(1, "other") end
        assertEq(#SG:ActivityLog(), 100)
    end)

    test("mail fee: postage on a mail with no gold attached", function()
        local SG = fresh(100000)
        fire(SG, "MAIL_SHOW")
        setMoney(SG, 99970)
        assertEq(SG:Char().spentBySource.mail, 30)
        assertEq(SG:Char().outgoing, 30)
    end)

    test("ah: listing fee paid while the AH window is open is AH spending", function()
        -- before this the addon never watched the AH window, so the
        -- deposit fell through to "other" (Martin, 7 Nov 2026)
        local SG = fresh(100000)
        fire(SG, "AUCTION_HOUSE_SHOW")
        setMoney(SG, 99900) -- 1s listing fee
        assertEq(SG:Char().spentBySource.ah, 100)
        assertEq(SG:Char().outgoing, 100)
        assertEq(SG:Char().spentBySource.other, 0)
        fire(SG, "AUCTION_HOUSE_CLOSED")
        setMoney(SG, 99800) -- same spend with the window closed: other
        assertEq(SG:Char().spentBySource.other, 100)
    end)

    test("trainer: learning a spell at a trainer is training spending", function()
        local SG = fresh(100000)
        fire(SG, "TRAINER_SHOW")
        setMoney(SG, 99000) -- 10s training cost
        assertEq(SG:Char().spentBySource.trainer, 1000)
        assertEq(SG:Char().outgoing, 1000)
        fire(SG, "TRAINER_CLOSED")
        stubs.state.time = stubs.state.time + 10 -- past the grace period
        setMoney(SG, 98000)
        assertEq(SG:Char().spentBySource.other, 1000)
    end)

    test("taxi: a fare paid as the taxi map closes is travel spending", function()
        -- the map closes as the flight starts, so the money can arrive
        -- after TAXIMAP_CLOSED; the grace period covers it
        local SG = fresh(100000)
        fire(SG, "TAXIMAP_OPENED")
        fire(SG, "TAXIMAP_CLOSED")
        setMoney(SG, 99900)
        assertEq(SG:Char().spentBySource.taxi, 100)
        stubs.state.time = stubs.state.time + 10
        setMoney(SG, 99800)
        assertEq(SG:Char().spentBySource.other, 100)
    end)

    test("trade: gold given and received in the trade window is trading", function()
        local SG = fresh(100000)
        fire(SG, "TRADE_SHOW")
        setMoney(SG, 90000) -- gave 10g to another player
        assertEq(SG:Char().spentBySource.trade, 10000)
        setMoney(SG, 95000) -- received 5g back
        assertEq(SG:Char().bySource.trade, 5000)
        assertEq(SG:Char().income, 5000)
        fire(SG, "TRADE_CLOSED")
        stubs.state.time = stubs.state.time + 10
        setMoney(SG, 94000)
        assertEq(SG:Char().spentBySource.other, 1000)
    end)

    test("bank: deposits and withdrawals are money moves, not spending/income", function()
        -- guild bank events are disputed (Gold Digger says The War
        -- Within folded them into BANKFRAME_*), so both event families
        -- count; a personal-bank move is a move either way
        local SG = fresh(100000)
        fire(SG, "GUILDBANKFRAME_OPENED")
        setMoney(SG, 50000) -- deposited 50g
        assertEq(SG:Char().moneyMoves, 50000)
        assertEq(SG:Char().outgoing, 0)
        setMoney(SG, 70000) -- withdrew 20g
        assertEq(SG:Char().moneyMoves, 70000)
        assertEq(SG:Char().income, 0)
        fire(SG, "GUILDBANKFRAME_CLOSED")
        stubs.state.time = stubs.state.time + 10 -- past the grace period
        setMoney(SG, 60000)
        assertEq(SG:Char().spentBySource.other, 10000)
        -- personal bank via BANKFRAME_* behaves the same
        fire(SG, "BANKFRAME_OPENED")
        setMoney(SG, 10000)
        assertEq(SG:Char().moneyMoves, 120000)
        assertEq(SG:Char().outgoing, 10000)
    end)

    test("ah: an outbid refund reverses the earlier listing expense, not income", function()
        local SG = fresh(100000)
        fire(SG, "AUCTION_HOUSE_SHOW")
        setMoney(SG, 99000) -- 10s bid placed: AH spending
        assertEq(SG:Char().spentBySource.ah, 1000)
        stubs.state.inbox = { { sender = "Auction House", subject = "Outbid on Copper Ore", money = 1000 } }
        fire(SG, "MAIL_INBOX_UPDATE")
        setMoney(SG, 100000) -- the refund arrives by mail
        assertEq(SG:Char().spentBySource.ah, 0) -- expense reversed
        assertEq(SG:Char().outgoing, 0)
        assertEq(SG:Char().income, 0) -- not income
        assertEq(SG:Char().bySource.ah, 0)
    end)

    test("ah: sale proceeds batched with another gain still file the sale as AH", function()
        -- before this, any batched delta missed every exact match and
        -- the whole amount fell through to "other" (Martin, 7 Nov 2026:
        -- 8s 60c from AH sales filed as Other)
        local SG = fresh(0)
        stubs.state.inbox = { { sender = "Auction House", subject = "Auction successful: Copper Ore", money = 860 } }
        fire(SG, "MAIL_INBOX_UPDATE")
        setMoney(SG, 1360) -- 860 sale + 500 from elsewhere, one delta
        assertEq(SG:Char().bySource.ah, 860)
        assertEq(SG:Char().bySource.other, 500)
    end)

    test("ah: sale detected by subject when the sender is not the auction house", function()
        -- the sender alone proved unreliable; Accountant checks the
        -- subject ("Auction successful: ...") instead
        local SG = fresh(0)
        stubs.state.inbox = { { sender = "Someone Else", subject = "Auction successful: Copper Ore", money = 860 } }
        fire(SG, "MAIL_INBOX_UPDATE")
        local entry = nil
        for _, m in pairs(SG.pendingMail) do entry = m end
        assertEq(entry.kind, "ah")
        assertEq(entry.sender, "Someone Else")
        assertEq(entry.subject, "Auction successful: Copper Ore")
        setMoney(SG, 860)
        assertEq(SG:Char().bySource.ah, 860)
    end)

    test("ah: two sale mails taken at once both file as AH", function()
        local SG = fresh(0)
        stubs.state.inbox = {
            { sender = "Auction House", subject = "Auction successful: Copper Ore", money = 860 },
            { sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 500 },
        }
        fire(SG, "MAIL_INBOX_UPDATE")
        setMoney(SG, 1360)
        assertEq(SG:Char().bySource.ah, 1360)
        assertEq(SG:Char().bySource.other, 0)
    end)

    test("mail: MAIL_SHOW scans the inbox, and an early empty scan loses nothing", function()
        local SG = fresh(0)
        local function countPending()
            local n = 0
            for _, _ in pairs(SG.pendingMail) do n = n + 1 end
            return n
        end
        local mail = { sender = "Auction House", subject = "Auction successful: Copper Ore", money = 860 }
        stubs.state.inbox = { mail }
        fire(SG, "MAIL_INBOX_UPDATE")
        assertEq(countPending(), 1)
        stubs.state.inbox = {}
        fire(SG, "MAIL_SHOW") -- inbox not loaded yet: drops the entry...
        assertEq(countPending(), 0)
        stubs.state.inbox = { mail }
        fire(SG, "MAIL_INBOX_UPDATE") -- ...and the next update re-adds it
        assertEq(countPending(), 1)
        setMoney(SG, 860)
        assertEq(SG:Char().bySource.ah, 860)
    end)

    test("ah: an outbid refund bigger than the recorded spend is a move for the rest", function()
        local SG = fresh(100000)
        stubs.state.inbox = { { sender = "Auction House", subject = "Outbid on Copper Ore", money = 1500 } }
        fire(SG, "MAIL_INBOX_UPDATE")
        setMoney(SG, 101500) -- refund, but no bid was recorded as spent
        assertEq(SG:Char().income, 0)
        assertEq(SG:Char().moneyMoves, 1500)
    end)

    test("quest: QUEST_TURNED_IN files the exact money reward", function()
        local SG = fresh(0)
        fire(SG, "QUEST_TURNED_IN", 12345, 100, 5000)
        setMoney(SG, 5000)
        assertEq(SG:Char().bySource.quest, 5000)
        assertEq(SG:Char().bySource.other, 0)
    end)

    test("quest: a turn-in with no money reward does not claim the next gain", function()
        local SG = fresh(0)
        fire(SG, "QUEST_TURNED_IN", 12345, 100, 0)
        fire(SG, "QUEST_TURN_IN_COMPLETE")
        setMoney(SG, 5000) -- unrelated gain after a no-reward turn-in
        assertEq(SG:Char().bySource.other, 5000)
        assertEq(SG:Char().bySource.quest, 0)
    end)

    test("quest: a batched delta splits the reward from the rest", function()
        local SG = fresh(0)
        fire(SG, "QUEST_TURNED_IN", 12345, 100, 5000)
        setMoney(SG, 6000) -- 50s quest reward + 10s from elsewhere
        assertEq(SG:Char().bySource.quest, 5000)
        assertEq(SG:Char().bySource.other, 1000)
    end)

    test("loot: pending loot expires, so it cannot claim a later unrelated gain", function()
        local SG = fresh(0)
        fire(SG, "CHAT_MSG_MONEY", "You loot 50 Silver.")
        assertEq(SG.pending.loot, 5000)
        stubs.state.time = stubs.state.time + 11 -- past the 10s expiry
        setMoney(SG, 5000) -- same amount, but the loot never arrived
        assertEq(SG:Char().bySource.other, 5000)
        assertEq(SG:Char().bySource.loot, 0)
    end)

    test("reclassify: spending can be moved between categories", function()
        local SG = fresh(100000)
        setMoney(SG, 99900) -- 1s spend, filed as other
        assertEq(SG:ReclassifySpendingSource("other", "ah", 500), 100) -- capped at what's there
        assertEq(SG:Char().spentBySource.other, 0)
        assertEq(SG:Char().spentBySource.ah, 100)
        assertEq(SG:Char().outgoing, 100) -- total unchanged, only the bucket moved
        assertEq(SG.lastGain.source, "ah") -- /sg last stays truthful
        assertEq(SG:ReclassifySpendingSource("other", "ah", 100), 0) -- nothing left to move
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
