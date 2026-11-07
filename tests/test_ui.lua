-- Tests for ui.lua popups: the AddGoal wizard.
-- Run via run.lua (needs wow_stubs.lua loaded first).
-- Regression test for 7 Nov 2026: clicking Next on SG_GOAL_NAME did
-- nothing and the popup stayed on screen, because OnAccept read
-- `self.editBox:GetText()` directly (nil/unreliable on Forever's
-- Retail 12.x StaticPopup) and showed the next popup synchronously
-- from inside OnAccept.
--
-- The harness mimics Blizzard's StaticPopup_OnClick: OnAccept runs,
-- then the dialog is hidden UNLESS OnAccept returns true; a
-- C_Timer.After(0) callback only fires after that hide, as in-game.

return function(stubs, ADDON)
    print("ui.lua")

    local shown = {}      -- StaticPopup_Show calls: { which=, data= }
    local timers = {}     -- queued C_Timer.After callbacks

    _G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
    _G.StaticPopup_Show = function(which, _, _, data)
        table.insert(shown, { which = which, data = data })
        return { which = which, data = data }
    end
    _G.C_Timer = {
        After = function(_, fn) table.insert(timers, fn) end,
    }

    local function flushTimers()
        local q = timers; timers = {}
        for _, fn in ipairs(q) do fn() end
    end

    local function fresh()
        shown = {}; timers = {}
        _G.SavingsGoalDB = nil
        stubs.reset()
        dofile(ADDON .. "core.lua")
        dofile(ADDON .. "goals.lua")
        local SG = SavingsGoal
        SG:InitDB()
        for _, h in ipairs(SG.handlers["PLAYER_LOGIN"]) do h(SG) end
        SG.RefreshBroker = function() end -- broker.lua, not loaded here
        dofile(ADDON .. "ui.lua")
        return SG
    end

    -- a mock StaticPopup frame. variant controls where the edit box lives:
    -- "lower" = dialog.editBox, "upper" = dialog.EditBox, "global" = _G[name.."EditBox"]
    local function makeDialog(which, variant, data)
        local ebText = ""
        local eb
        eb = {
            GetText = function() return ebText end,
            SetText = function(_, t) ebText = t or "" end,
            SetFocus = function() end,
        }
        -- allow tests to set text through the mock
        eb._set = function(t) ebText = t end
        local dialog = {
            which = which, data = data, shown = true,
            button1 = { enabled = true,
                Enable = function(self) self.enabled = true end,
                Disable = function(self) self.enabled = false end },
            GetName = function() return "StaticPopup1" end,
            Hide = function(self) self.shown = false end,
        }
        dialog.GetParent = function() return dialog end
        eb.GetParent = function() return dialog end
        if variant == "lower" then dialog.editBox = eb
        elseif variant == "upper" then dialog.EditBox = eb
        elseif variant == "global" then _G["StaticPopup1EditBox"] = eb end
        dialog._eb = eb
        return dialog
    end

    -- type `text` into the dialog's edit box the way a player does:
    -- SetText + the TextChanged callback Blizzard fires
    local function typeText(which, dialog, text)
        dialog._eb._set(text)
        local info = StaticPopupDialogs[which]
        if info.EditBoxOnTextChanged then info.EditBoxOnTextChanged(dialog._eb) end
    end

    -- click button1 the way Blizzard does: OnAccept, then hide unless it returns true
    local function clickAccept(which, dialog)
        local info = StaticPopupDialogs[which]
        local result = info.OnAccept(dialog, dialog.data)
        if result ~= true then dialog:Hide() end
        flushTimers() -- C_Timer.After(0) runs after the hide, as in-game
        return result
    end

    local function pressEnter(which, dialog)
        local info = StaticPopupDialogs[which]
        info.EditBoxOnEnterPressed(dialog._eb)
        flushTimers()
    end

    test("AddGoal Next works when editBox is dialog.EditBox (12.x)", function()
        local SG = fresh()
        local dialog = makeDialog("SG_GOAL_NAME", "upper")
        StaticPopupDialogs["SG_GOAL_NAME"].OnShow(dialog)
        typeText("SG_GOAL_NAME", dialog, "Epic Mount")
        clickAccept("SG_GOAL_NAME", dialog)
        assertEq(dialog.shown, false)
        assertEq(#shown, 1)
        assertEq(shown[1].which, "SG_GOAL_TARGET")
        assertEq(shown[1].data, "Epic Mount")
    end)

    test("AddGoal Next works when editBox is only _G[name..'EditBox']", function()
        local SG = fresh()
        local dialog = makeDialog("SG_GOAL_NAME", "global")
        StaticPopupDialogs["SG_GOAL_NAME"].OnShow(dialog)
        -- no TextChanged capture: OnAccept must fall back to the global box
        dialog._eb._set("Swift Zulian Tiger")
        clickAccept("SG_GOAL_NAME", dialog)
        assertEq(dialog.shown, false)
        assertEq(shown[1].which, "SG_GOAL_TARGET")
        assertEq(shown[1].data, "Swift Zulian Tiger")
    end)

    test("AddGoal Next works with the old dialog.editBox field too", function()
        local SG = fresh()
        local dialog = makeDialog("SG_GOAL_NAME", "lower")
        StaticPopupDialogs["SG_GOAL_NAME"].OnShow(dialog)
        typeText("SG_GOAL_NAME", dialog, "Mount")
        clickAccept("SG_GOAL_NAME", dialog)
        assertEq(shown[1].data, "Mount")
    end)

    test("AddGoal Next with empty name keeps the popup open", function()
        local SG = fresh()
        local dialog = makeDialog("SG_GOAL_NAME", "upper")
        StaticPopupDialogs["SG_GOAL_NAME"].OnShow(dialog)
        typeText("SG_GOAL_NAME", dialog, "")
        local result = clickAccept("SG_GOAL_NAME", dialog)
        assertEq(result, true)
        assertEq(dialog.shown, true)
        assertEq(#shown, 0)
    end)

    test("AddGoal Enter creates the target step, Next path creates the goal", function()
        local SG = fresh()
        local dialog = makeDialog("SG_GOAL_NAME", "upper")
        StaticPopupDialogs["SG_GOAL_NAME"].OnShow(dialog)
        typeText("SG_GOAL_NAME", dialog, "Epic Mount")
        pressEnter("SG_GOAL_NAME", dialog)
        assertEq(shown[1].data, "Epic Mount")
        local target = makeDialog("SG_GOAL_TARGET", "upper", "Epic Mount")
        StaticPopupDialogs["SG_GOAL_TARGET"].OnShow(target)
        typeText("SG_GOAL_TARGET", target, "1000")
        clickAccept("SG_GOAL_TARGET", target)
        assertEq(#SG:GetGoals(), 1)
        assertEq(SG:GetGoals()[1].name, "Epic Mount")
        assertEq(SG:GetGoals()[1].target, 10000000)
    end)

    test("Target Enter no longer errors (old GetScript('OnAccept') bug)", function()
        local SG = fresh()
        local target = makeDialog("SG_GOAL_TARGET", "upper", "Mount")
        StaticPopupDialogs["SG_GOAL_TARGET"].OnShow(target)
        typeText("SG_GOAL_TARGET", target, "500")
        pressEnter("SG_GOAL_TARGET", target)
        assertEq(#SG:GetGoals(), 1)
        assertEq(target.shown, false)
    end)

    test("Target with invalid amount keeps the popup open, no goal", function()
        local SG = fresh()
        local target = makeDialog("SG_GOAL_TARGET", "upper", "Mount")
        StaticPopupDialogs["SG_GOAL_TARGET"].OnShow(target)
        typeText("SG_GOAL_TARGET", target, "abc")
        local result = clickAccept("SG_GOAL_TARGET", target)
        assertEq(result, true)
        assertEq(target.shown, true)
        assertEq(#SG:GetGoals(), 0)
    end)

    test("Seed popup works when editBox is dialog.EditBox", function()
        local SG = fresh()
        SG:Char().lastMoney = 1000000
        local g = SG:AddGoal("Mount", 100)
        local dialog = makeDialog("SG_GOAL_SEED", "upper", g)
        StaticPopupDialogs["SG_GOAL_SEED"].OnShow(dialog, g)
        typeText("SG_GOAL_SEED", dialog, "10")
        clickAccept("SG_GOAL_SEED", dialog)
        assertEq(g.seed, 100000)
    end)

    test("Rate popup works when editBox is dialog.EditBox", function()
        local SG = fresh()
        local g = SG:AddGoal("Mount", 100)
        local dialog = makeDialog("SG_GOAL_RATE", "upper", g)
        StaticPopupDialogs["SG_GOAL_RATE"].OnShow(dialog, g)
        typeText("SG_GOAL_RATE", dialog, "50%")
        clickAccept("SG_GOAL_RATE", dialog)
        assertEq(g.rate.value, 50)
    end)

    -- helpers for RefreshUI layout tests: texts of currently visible labels
    local function visibleLabelTexts()
        local texts = {}
        for _, fs in ipairs(stubs.fontstrings) do
            if fs:IsShown() then table.insert(texts, fs:GetText()) end
        end
        return texts
    end
    local function countVisible(text)
        local n = 0
        for _, t in ipairs(visibleLabelTexts()) do if t == text then n = n + 1 end end
        return n
    end
    local function anyVisibleMatching(pattern)
        for _, t in ipairs(visibleLabelTexts()) do if t:find(pattern) then return true end end
        return false
    end

    -- Regression test for 7 Nov 2026 (screenshot): the info screen showed
    -- overlapping text — "No goals yet" over the goal row, "CHARACTERS"
    -- twice — because wipe() only hid child frames, and labels are
    -- FontStrings, which GetChildren() never returns.
    test("RefreshUI hides stale labels when a goal is added", function()
        local SG = fresh()
        local char = SG:Char()
        char.lastMoney = 1522
        char.bySource.other = 7
        char.daily[SG:TodayKey()] = { income = 7, outgoing = 0 }
        SG:ShowUI()
        assertEq(countVisible("No goals yet — click Add goal to save for your first mount."), 1)
        assertEq(countVisible("CHARACTERS"), 1)
        SG:AddGoal("Epic Mount", 100)
        SG:RefreshUI()
        assertEq(countVisible("No goals yet — click Add goal to save for your first mount."), 0)
        assertEq(countVisible("CHARACTERS"), 1)
        assertEq(countVisible("1. Epic Mount"), 1)
    end)

    test("Huge ETAs show in years, not tens of thousands of days", function()
        local SG = fresh()
        local char = SG:Char()
        char.lastMoney = 1522
        char.bySource.other = 7
        char.daily[SG:TodayKey()] = { income = 7, outgoing = 0 }
        SG:AddGoal("Epic Mount", 100)
        SG:ShowUI()
        assertEq(anyVisibleMatching("391 years"), true)
        assertEq(anyVisibleMatching("142858 days"), false)
    end)

    test("Normal ETAs still show in days", function()
        local SG = fresh()
        local char = SG:Char()
        char.lastMoney = 1000000
        char.daily[SG:TodayKey()] = { income = 10000, outgoing = 0 }
        SG:AddGoal("Epic Mount", 100)
        SG:ShowUI()
        assertEq(anyVisibleMatching("~100 days"), true)
    end)

    -- Regression test for 7 Nov 2026: the Rate button did nothing because
    -- its dialog text contained a bare "%" ("e.g. 50% ...") and Blizzard
    -- runs dialog text through SetFormattedText, so StaticPopup_Show threw
    -- before the popup appeared. Any bare % in any dialog text breaks that
    -- dialog the same way.
    test("No popup text contains a bare percent sign", function()
        local SG = fresh()
        _G.SlashCmdList = _G.SlashCmdList or {}
        dofile(ADDON .. "slash.lua")
        for which, info in pairs(StaticPopupDialogs) do
            local text = info.text or ""
            local stripped = text:gsub("%%%%", "")
            assertEq(stripped:find("%", 1, true), nil, which .. " has a bare % in its text")
        end
    end)

    test("Daily Keep popup sets the keep", function()
        local SG = fresh()
        local dialog = makeDialog("SG_DAILY_KEEP", "upper")
        StaticPopupDialogs["SG_DAILY_KEEP"].OnShow(dialog)
        typeText("SG_DAILY_KEEP", dialog, "1g")
        clickAccept("SG_DAILY_KEEP", dialog)
        assertEq(SG:DailyKeepAmount(), 10000)
        assertEq(SG:DailyKeepLabel(), "1g/day")
    end)

    test("Daily Keep popup with invalid input keeps the popup open", function()
        local SG = fresh()
        local dialog = makeDialog("SG_DAILY_KEEP", "upper")
        StaticPopupDialogs["SG_DAILY_KEEP"].OnShow(dialog)
        typeText("SG_DAILY_KEEP", dialog, "abc")
        local result = clickAccept("SG_DAILY_KEEP", dialog)
        assertEq(result, true)
        assertEq(dialog.shown, true)
        assertEq(SG:DailyKeepAmount(), 0)
    end)

    test("Info screen shows the daily keep line", function()
        local SG = fresh()
        SG:SetDailyKeep("1g")
        SG:ShowUI()
        assertEq(anyVisibleMatching("Keeping for spending: 1g/day"), true)
    end)

    test("Info screen shows goal % and today's net", function()
        local SG = fresh()
        local char = SG:Char()
        char.lastMoney = 1000000
        char.daily[SG:TodayKey()] = { income = 20000, outgoing = 5000 }
        local g = SG:AddGoal("Epic Mount", 100)
        SG:SetSeed(g, 25) -- 25g of 100g
        SG:ShowUI()
        assertEq(anyVisibleMatching("25%%"), true)
        assertEq(anyVisibleMatching("Today:"), true)
        assertEq(anyVisibleMatching("net 1g 50s 0c"), true)
        -- the goal bar recorded the 25g value and the green (<75%) colour
        local found = false
        for _, f in ipairs(stubs.frames) do
            if f._barValue == 250000 then found = true end
        end
        assertEq(found, true)
    end)

    test("Modern look: gold section headers, flat bars, split headline", function()
        local SG = fresh()
        local char = SG:Char()
        char.lastMoney = 1000000
        char.daily[SG:TodayKey()] = { income = 20000, outgoing = 5000 }
        char.bySource.other = 7
        SG:AddGoal("Epic Mount", 100)
        SG:ShowUI()
        assertEq(anyVisibleMatching("^GOALS$"), true)
        assertEq(anyVisibleMatching("^INCOME BY SOURCE$"), true)
        assertEq(anyVisibleMatching("^CHARACTERS$"), true)
        assertEq(anyVisibleMatching("^Safe to spend:"), true)
        assertEq(anyVisibleMatching("^Account:"), true)
        -- flat bar texture, not the glossy Blizzard status-bar art
        local flat = false
        for _, f in ipairs(stubs.frames) do
            if f._barTexture == "Interface\\Buttons\\WHITE8x8" then flat = true end
        end
        assertEq(flat, true)
    end)

    test("Classic look: plain titles, glossy bars, single headline", function()
        local SG = fresh()
        local char = SG:Char()
        char.lastMoney = 1000000
        char.bySource.other = 7
        char.daily[SG:TodayKey()] = { income = 7, outgoing = 0 }
        SG:AddGoal("Epic Mount", 100)
        SG:SetLook("classic")
        SG:ShowUI()
        assertEq(anyVisibleMatching("^Characters$"), true)
        assertEq(anyVisibleMatching("^CHARACTERS$"), false)
        assertEq(anyVisibleMatching("Account total:"), true)
        assertEq(anyVisibleMatching("^Account:"), false)
        local glossy = false
        for _, f in ipairs(stubs.frames) do
            if f._barTexture == "Interface\\TargetingFrame\\UI-StatusBar" then glossy = true end
        end
        assertEq(glossy, true)
        -- toggle back to modern in the same session
        SG:ToggleLook()
        SG:RefreshUI()
        assertEq(anyVisibleMatching("^CHARACTERS$"), true)
        assertEq(anyVisibleMatching("^Characters$"), false)
    end)

    test("Modern look: bar label clears the bar, rows are not gold", function()
        -- Regression for the 7 Nov 2026 screenshot: the goal bar's
        -- label sat at bar-top - 18 with a 20px bar, so its top (the
        -- "~" in "~5 years" first) was hidden behind the bar; and
        -- goal names / character rows with no explicit colour came
        -- out gold in-game.
        local SG = fresh()
        local char = SG:Char()
        char.lastMoney = 1000000
        SG:AddGoal("Epic Mount", 100)
        SG:ShowUI()
        local barY, barH = nil, nil
        for _, f in ipairs(stubs.frames) do
            if f._barTexture then barY, barH = f._pointY, f._height end
        end
        assertEq(barH, 20)
        local labelY, nameColor, charColor = nil, nil, nil
        for _, fs in ipairs(stubs.fontstrings) do
            if fs._shown and fs._text:find("/ 100g") then labelY = fs._pointY end
            if fs._shown and fs._text == "1. Epic Mount" then nameColor = fs._textColor end
            if fs._shown and fs._text:find("safe") then charColor = fs._textColor end
        end
        -- label top at least one bar-height + 4px below the bar top
        assertEq(labelY ~= nil and labelY <= barY - 24, true)
        assertEq(nameColor and nameColor[1], 1)
        assertEq(charColor and charColor[1], 0.78)
    end)

    test("BrokerText shows years for huge ETAs", function()
        local SG = fresh()
        dofile(ADDON .. "broker.lua")
        local char = SG:Char()
        char.lastMoney = 1522
        char.bySource.other = 7
        char.daily[SG:TodayKey()] = { income = 7, outgoing = 0 }
        SG:AddGoal("Epic Mount", 100)
        assertEq(SG:BrokerText(), "0g safe | Epic Mount 0g/100g ~391 years")
    end)
end
