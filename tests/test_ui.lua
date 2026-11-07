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
end
