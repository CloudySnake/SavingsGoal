-- SavingsGoal UI: the info screen. Toggle with /sg or by clicking the broker/minimap button.
local SG = SavingsGoal

local mainFrame = nil
local content = nil

local SOURCE_LABELS = { ah = "Auction House", vendor = "Vendoring", quest = "Quests", loot = "Loot", other = "Other" }

local function smallButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 60, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function label(parent, text, size)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetFont("Fonts\\FRIZQT__.TTF", size or 12)
    f:SetText(text)
    return f
end

function SG:ToggleUI()
    if mainFrame and mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:ShowUI()
    end
end

function SG:ShowUI()
    if not mainFrame then self:BuildUI() end
    self:RefreshUI()
    mainFrame:Show()
end

function SG:BuildUI()
    mainFrame = CreateFrame("Frame", "SavingsGoalFrame", UIParent, "BasicFrameTemplateWithInset")
    mainFrame:SetSize(560, 600)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame.TitleText:SetText("SavingsGoal")
    mainFrame:Hide()
    tinsert(UISpecialFrames, "SavingsGoalFrame") -- Esc closes

    local addBtn = smallButton(mainFrame, "Add goal", 90, function()
        StaticPopup_Show("SG_GOAL_NAME")
    end)
    addBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -28, -28)

    local scroll = CreateFrame("ScrollFrame", nil, mainFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 12, -60)
    scroll:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -32, 12)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(500, 10)
    scroll:SetScrollChild(content)
end

local function wipe(parent)
    for _, child in ipairs({ parent:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
end

function SG:RefreshUI()
    if not content then return end
    wipe(content)
    local y = -6
    local W = 500

    local function nextY(h) y = y - h; return y end

    -- headline numbers
    local head = label(content, string.format("Safe to spend: %s    Account total: %s",
        self:FormatGold(self:SafeToSpend()), self:FormatGold(self:AccountGold())), 13)
    head:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(24)

    local surplus = self:DailySurplus()
    local sl = label(content, string.format("Daily surplus (trailing %dd): %s",
        self.db.settings.windowDays, self:FormatGold(surplus)), 12)
    sl:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(30)

    -- goals
    local goals = self:GetGoals()
    if #goals == 0 then
        local e = label(content, "No goals yet — click Add goal to save for your first mount.", 12)
        e:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(30)
    end
    for _, g in ipairs(goals) do
        local need = self:GoalNeed(g)
        local have = (g.seed or 0) + (g.saved or 0)
        local days = self:GoalDaysLeft(g)
        local eta = need <= 0 and "|cff33ff99complete!|r"
            or (days == nil and "no surplus yet" or ("~" .. days .. " days"))

        local name = label(content, string.format("%d. %s", g.priority or 0, g.name), 13)
        name:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y)

        local del = smallButton(content, "x", 26, function() self:DeleteGoal(g); self:RefreshUI() end)
        del:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, y + 4)
        local dn = smallButton(content, "v", 26, function() self:MoveGoal(g, 1); self:RefreshUI() end)
        dn:SetPoint("RIGHT", del, "LEFT", -2, 0)
        local up = smallButton(content, "^", 26, function() self:MoveGoal(g, -1); self:RefreshUI() end)
        up:SetPoint("RIGHT", dn, "LEFT", -2, 0)
        local rate = smallButton(content, "Rate", 52, function()
            StaticPopup_Show("SG_GOAL_RATE", nil, nil, g)
        end)
        rate:SetPoint("RIGHT", up, "LEFT", -2, 0)
        local seed = smallButton(content, "Seed", 52, function()
            StaticPopup_Show("SG_GOAL_SEED", nil, nil, g)
        end)
        seed:SetPoint("RIGHT", rate, "LEFT", -2, 0)

        nextY(20)
        local bar = CreateFrame("StatusBar", nil, content)
        bar:SetSize(W - 12, 16)
        bar:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetStatusBarColor(0.2, 0.8, 0.4)
        bar:SetMinMaxValues(0, math.max(1, g.target))
        bar:SetValue(math.min(have, g.target))
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(bar)
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
        local bl = label(content, string.format("%s / %s  (%s)   [%s]",
            self:FormatGoldShort(have), self:FormatGoldShort(g.target), eta, self:RateLabel(g)), 11)
        bl:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y - 18)
        nextY(44)
    end

    if #goals > 1 then
        local all = self:WaterfallDaysLeft()
        local wl = label(content, "All goals, focused in priority order: " ..
            (all == nil and "no surplus yet" or ("~" .. all .. " days")), 12)
        wl:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(30)
    end

    -- income by source
    local sh = label(content, "Income by source (account lifetime)", 13)
    sh:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(22)
    for _, key in ipairs({ "ah", "vendor", "quest", "loot", "other" }) do
        local amt = (self:IncomeBySource())[key] or 0
        if amt > 0 then
            local l = label(content, string.format("  %s: %s", SOURCE_LABELS[key], self:FormatGold(amt)), 11)
            l:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(18)
        end
    end
    nextY(8)

    -- per character
    local ch = label(content, "Characters", 13)
    ch:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(22)
    for key, char in pairs(self.db.chars) do
        local l = label(content, string.format("  %s: %s  (+%s / -%s)",
            key, self:FormatGoldShort(char.lastMoney or 0),
            self:FormatGoldShort(char.income or 0), self:FormatGoldShort(char.outgoing or 0)), 11)
        l:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(18)
    end

    content:SetHeight(math.abs(y) + 20)
end

-- ------------------------------------------------------------------ popups --
-- Bug (7 Nov 2026): clicking Next on SG_GOAL_NAME did nothing and the
-- popup stayed on screen. Two causes, both in this section:
--  1. OnAccept read `self.editBox:GetText()` directly. Forever runs on the
--     Retail (12.x) codebase, where that field is not reliable — other
--     12.0 addons guard `dialog.editBox` / `dialog.EditBox` /
--     `_G[dialogName.."EditBox"]`, and note it can be nil in OnShow.
--     A nil editBox throws inside OnAccept, Blizzard never reaches the
--     Hide() after OnAccept, so the popup just stays there.
--     Fix: capture the text as the user types (EditBoxOnTextChanged,
--     where `self` IS the edit box) and only use the dialog field as a
--     fallback via popupEditBox()/popupText().
--  2. OnAccept called StaticPopup_Show for the next popup synchronously.
--     That second popup can be swallowed when Blizzard hides the first
--     one after OnAccept returns. Fix: defer it with C_Timer.After(0, …).
--  Also fixed in passing: SG_GOAL_TARGET's Enter handler called
--  `parent:GetScript("OnAccept")`, which is not a frame script and would
--  error — Enter now calls the same create-goal helper as OnAccept.
--  The same editBox guard is applied to Seed/Rate, which used it too.

local function trim(s)
    if not s then return "" end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function popupEditBox(dialog)
    if not dialog then return nil end
    local eb = dialog.editBox or dialog.EditBox or dialog.wideEditBox or dialog.WideEditBox
    if eb then return eb end
    local name = dialog.GetName and dialog:GetName()
    if name then
        return _G[name .. "EditBox"] or _G[name .. "WideEditBox"]
    end
    return nil
end

local function popupText(dialog, fallback)
    local eb = popupEditBox(dialog)
    if eb and eb.GetText then
        local t = eb:GetText()
        if t and t ~= "" then return t end
    end
    return fallback
end

local function setPopupText(dialog, text)
    local eb = popupEditBox(dialog)
    if eb and eb.SetText then eb:SetText(text) end
    if eb and eb.SetFocus then eb:SetFocus() end
end

-- text captured as the user types, so OnAccept never depends on the
-- dialog's editBox field existing at click time
local pendingName, pendingTarget, pendingSeed, pendingRate = nil, nil, nil, nil

local function captureAndGate(editBox, store)
    -- `self` here is the edit box; store its text and gate button1 on it
    local text = editBox:GetText() or ""
    if store == "name" then pendingName = text
    elseif store == "target" then pendingTarget = text
    elseif store == "seed" then pendingSeed = text
    elseif store == "rate" then pendingRate = text end
    local parent = editBox.GetParent and editBox:GetParent()
    if parent and parent.button1 then
        if text ~= "" then parent.button1:Enable() else parent.button1:Disable() end
    end
end

local function showTargetPopup(name)
    C_Timer.After(0, function()
        StaticPopup_Show("SG_GOAL_TARGET", nil, nil, name)
    end)
end

local function createGoalFromTarget(dialog, name, text)
    local target = tonumber(trim(text))
    if name and target and target > 0 then
        SG:AddGoal(name, target)
        SG:RefreshUI(); SG:RefreshBroker()
        return true
    end
    return false
end

StaticPopupDialogs["SG_GOAL_NAME"] = {
    text = "New savings goal — what are you saving for?",
    button1 = "Next", button2 = "Cancel",
    hasEditBox = true, maxLetters = 40,
    OnShow = function(self)
        pendingName = nil
        setPopupText(self, "")
    end,
    EditBoxOnTextChanged = function(self) captureAndGate(self, "name") end,
    OnAccept = function(self)
        local name = trim(popupText(self, pendingName))
        if name == "" then return true end -- keep popup open; Blizzard hides unless OnAccept returns true
        pendingName = nil
        showTargetPopup(name)
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local name = trim(self:GetText() or "")
        if name == "" then return end
        pendingName = nil
        parent:Hide()
        showTargetPopup(name)
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["SG_GOAL_TARGET"] = {
    text = "How much does it cost? (in gold)",
    button1 = "Create", button2 = "Cancel",
    hasEditBox = true, maxLetters = 12,
    OnShow = function(self)
        pendingTarget = nil
        setPopupText(self, "")
    end,
    EditBoxOnTextChanged = function(self) captureAndGate(self, "target") end,
    OnAccept = function(self, name)
        if createGoalFromTarget(self, name, popupText(self, pendingTarget)) then
            pendingTarget = nil
        else
            return true -- invalid amount: keep popup open so it can be corrected
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if createGoalFromTarget(parent, parent.data, self:GetText()) then
            pendingTarget = nil
            parent:Hide()
        end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["SG_GOAL_SEED"] = {
    text = "Allocate how much of your current gold to this goal? (gold)",
    button1 = "Set", button2 = "Cancel",
    hasEditBox = true, maxLetters = 12,
    OnShow = function(self, goal)
        pendingSeed = nil
        setPopupText(self, tostring(math.floor((goal.seed or 0) / 10000)))
    end,
    EditBoxOnTextChanged = function(self) captureAndGate(self, "seed") end,
    OnAccept = function(self, goal)
        local gold = tonumber(trim(popupText(self, pendingSeed)))
        if goal and gold and gold >= 0 then
            pendingSeed = nil
            local applied = SG:SetSeed(goal, gold)
            if applied < gold * 10000 then
                print("|cff33ff99SavingsGoal:|r seed capped at " .. SG:FormatGoldShort(applied) .. " — that's all the unlocked gold available.")
            end
            SG:RefreshUI(); SG:RefreshBroker()
        else
            return true -- invalid amount: keep popup open
        end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["SG_GOAL_RATE"] = {
    text = "Savings rate for this goal — e.g. 50% or 10g per day:",
    button1 = "Set", button2 = "Cancel",
    hasEditBox = true, maxLetters = 12,
    OnShow = function(self, goal)
        pendingRate = nil
        setPopupText(self, SG:RateLabel(goal):gsub(" of surplus", ""):gsub("/day", "g"))
    end,
    EditBoxOnTextChanged = function(self) captureAndGate(self, "rate") end,
    OnAccept = function(self, goal)
        if goal then
            local text = popupText(self, pendingRate)
            if text and text ~= "" then
                pendingRate = nil
                SG:SetRate(goal, text)
                SG:RefreshUI(); SG:RefreshBroker()
            else
                return true -- empty rate: keep popup open
            end
        end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    whileDead = true, hideOnEscape = true,
}
