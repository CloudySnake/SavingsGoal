-- SavingsGoal UI: the info screen. Toggle with /sg or by clicking the broker/minimap button.
local SG = SavingsGoal

local mainFrame = nil
local content = nil
local lookBtn = nil -- Look toggle button; its text follows the current look

local SOURCE_LABELS = { ah = "Auction House", vendor = "Vendoring", quest = "Quests", loot = "Loot", other = "Other" }

local function smallButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 60, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- Modern look (v1.0.6): flat dark panels, thin gold dividers, gold
-- section headers, muted secondary text — the PlayerUIWoW / isiLive
-- pattern of stripping the bulky classic chrome inside the window.
-- The outer window deliberately stays BasicFrameTemplateWithInset:
-- its title bar, close button, drag and Esc handling are Blizzard-tested
-- on Forever, and replacing them with a custom BackdropTemplate shell
-- would risk breaking exactly those bits.
local GOLD_R, GOLD_G, GOLD_B = 1, 0.82, 0
local MUTED_R, MUTED_G, MUTED_B = 0.78, 0.78, 0.78

local function label(parent, text, size, r, g, b)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetFont("Fonts\\FRIZQT__.TTF", size or 12)
    f:SetText(text)
    if r then f:SetTextColor(r, g, b) end
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
    mainFrame:SetSize(580, 620)
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

    local keepBtn = smallButton(mainFrame, "Keep", 60, function()
        StaticPopup_Show("SG_DAILY_KEEP")
    end)
    keepBtn:SetPoint("RIGHT", addBtn, "LEFT", -6, 0)

    lookBtn = smallButton(mainFrame, "Modern", 70, function()
        SG:ToggleLook()
        SG:RefreshUI()
    end)
    lookBtn:SetPoint("RIGHT", keepBtn, "LEFT", -6, 0)

    local scroll = CreateFrame("ScrollFrame", nil, mainFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 12, -60)
    scroll:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -32, 12)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(520, 10)
    scroll:SetScrollChild(content)
end

local function wipe(parent)
    for _, child in ipairs({ parent:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
    -- Labels are FontStrings (regions, not frames): GetChildren() never
    -- returns them, so they must be hidden too. Before this fix every
    -- RefreshUI() left all previous labels visible at their old positions,
    -- so once the layout shifted (e.g. a goal added: the "No goals yet"
    -- line should vanish and everything below moves down) the stale text
    -- stayed on screen overlapping the new rows — "No goals yet" over the
    -- goal row, "Income by source" / "Characters" each shown twice.
    -- (Bug seen in-game 7 Nov 2026; the buttons and bars were wiped fine,
    -- which is why only the text overlapped.)
    for _, region in ipairs({ parent:GetRegions() }) do
        region:Hide()
    end
end

-- ETA formatting lives in core.lua now (SG:FormatEta) so the info screen,
-- the Titan feed and /sg list all show the same "~100 days" / "~48 years".
-- A 7c/day surplus against a 100g goal is ~142,858 days — true, but useless
-- on screen; "~391 years" says the same thing.

function SG:RefreshUI()
    if not content then return end
    wipe(content)
    local y = -6
    local W = 520
    local modern = self:Look() == "modern"
    -- muted secondary text only in the modern look; classic uses
    -- Blizzard's default label colour throughout
    local mr, mg, mb = modern and MUTED_R or nil, modern and MUTED_G or nil, modern and MUTED_B or nil
    if lookBtn then lookBtn:SetText(modern and "Modern" or "Classic") end

    local function nextY(h) y = y - h; return y end

    -- section header: gold + thin divider in modern, plain title in classic
    local function header(mText, cText)
        if modern then
            local h = label(content, mText, 12, GOLD_R, GOLD_G, GOLD_B)
            h:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(20)
            local div = content:CreateTexture(nil, "OVERLAY")
            div:SetSize(W - 12, 1)
            div:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y)
            div:SetColorTexture(0.8, 0.65, 0.2, 0.5)
            nextY(10)
        elseif cText then
            local h = label(content, cText, 13)
            h:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(22)
        end
    end

    if modern then
        -- headline: safe-to-spend big and gold on the left, account total
        -- muted on the right — a dashboard headline, not a sentence
        local head = label(content, "Safe to spend: " .. self:FormatGold(self:SafeToSpend()),
            14, GOLD_R, GOLD_G, GOLD_B)
        head:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y)
        local acct = label(content, "Account: " .. self:FormatGold(self:AccountGold()),
            12, MUTED_R, MUTED_G, MUTED_B)
        acct:SetJustifyH("RIGHT")
        acct:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, y)
        nextY(28)
    else
        local head = label(content, string.format("Safe to spend: %s    Account total: %s",
            self:FormatGold(self:SafeToSpend()), self:FormatGold(self:AccountGold())), 13)
        head:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(24)
    end

    local surplus = self:DailySurplus()
    local sl = label(content, string.format("Daily surplus (trailing %dd): %s",
        self.db.settings.windowDays, self:FormatGold(surplus)), 12, mr, mg, mb)
    sl:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(22)

    local tIn, tOut, tNet = self:TodayTotals()
    -- Full gold/silver/copper here, not the rounded-to-gold short form:
    -- today's amounts are often only a few silver, and "2g" for 1g 50s
    -- would be misleading.
    local tl = label(content, string.format("Today: +%s / -%s  (net %s)",
        self:FormatGold(tIn), self:FormatGold(tOut), self:FormatGold(tNet)), 12, mr, mg, mb)
    tl:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(30)

    local keep = self:DailyKeepAmount()
    if keep > 0 then
        local kl = label(content, "Keeping for spending: " .. self:DailyKeepLabel(), 12, mr, mg, mb)
        kl:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(24)
    end

    -- goals
    local goals = self:GetGoals()
    if #goals > 0 then header("GOALS") end
    if #goals == 0 then
        local e = label(content, "No goals yet — click Add goal to save for your first mount.", 12)
        e:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(30)
    end
    for _, g in ipairs(goals) do
        local need = self:GoalNeed(g)
        local have = (g.seed or 0) + (g.saved or 0)
        local days = self:GoalDaysLeft(g)
        local eta = need <= 0 and "|cff33ff99complete!|r" or self:FormatEta(days)

        self:AnnounceGoalComplete(g) -- one-time chat line if it filled before this version
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
        if modern then
            bar:SetSize(W - 12, 20)
        else
            bar:SetSize(W - 12, 16)
        end
        bar:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y)
        -- flat bar in modern: plain white texture, no glossy Blizzard
        -- status-bar art. Classic keeps the original Blizzard texture.
        if modern then
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        else
            bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        end
        local br, bgc, bb = self:GoalBarColor(g)
        bar:SetStatusBarColor(br, bgc, bb)
        bar:SetMinMaxValues(0, math.max(1, g.target))
        bar:SetValue(math.min(have, g.target))
        local bg = bar:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(bar)
        if modern then
            bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)
        else
            bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
        end
        local bl = label(content, string.format("%s / %s (%d%%)  (%s)   [%s]",
            self:FormatGoldShort(have), self:FormatGoldShort(g.target), self:GoalPercent(g), eta, self:RateLabel(g)), 11, mr, mg, mb)
        bl:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y - 18)
        nextY(44)
    end

    if #goals > 1 then
        local all = self:WaterfallDaysLeft()
        local wl = label(content, "All goals, focused in priority order: " .. self:FormatEta(all), 12)
        wl:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(30)
    end

    -- income by source
    header("INCOME BY SOURCE", "Income by source (account lifetime)")
    for _, key in ipairs({ "ah", "vendor", "quest", "loot", "other" }) do
        local amt = (self:IncomeBySource())[key] or 0
        if amt > 0 then
            local l = label(content, string.format("  %s: %s", SOURCE_LABELS[key], self:FormatGold(amt)), 11, mr, mg, mb)
            l:SetPoint("TOPLEFT", content, "TOPLEFT", 6, y); nextY(18)
        end
    end
    nextY(8)

    -- per character
    header("CHARACTERS", "Characters")
    for key, char in pairs(self.db.chars) do
        local l = label(content, string.format("  %s: %s (safe %s)  (+%s / -%s)",
            key, self:FormatGoldShort(char.lastMoney or 0),
            self:FormatGoldShort(self:CharSafeToSpend(char)),
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
--  Correction (7 Nov 2026, checked against Blizzard's own StaticPopup.lua,
--  live branch, Blizzard_StaticPopup/StaticPopup.lua): chaining is NOT
--  the cause. StaticPopup_Show allocates a different frame for the second
--  dialog, and StaticPopup_OnClick's dialog:Hide() after OnAccept only
--  hides the first frame (hide = not OnAccept(...), so a truthy return
--  keeps it open — which is why invalid input now returns true).
--  The defer with C_Timer.After(0, …) is kept anyway as belt-and-braces:
--  it runs after the first popup's hide, and guards the edge case where
--  no StaticPopup frame is free and a synchronous Show returns nil.
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
local pendingName, pendingTarget, pendingSeed, pendingRate, pendingKeep = nil, nil, nil, nil, nil

local function captureAndGate(editBox, store)
    -- `self` here is the edit box; store its text and gate button1 on it
    local text = editBox:GetText() or ""
    if store == "name" then pendingName = text
    elseif store == "target" then pendingTarget = text
    elseif store == "seed" then pendingSeed = text
    elseif store == "rate" then pendingRate = text
    elseif store == "keep" then pendingKeep = text end
    local parent = editBox.GetParent and editBox:GetParent()
    if parent and parent.button1 then
        if text ~= "" then parent.button1:Enable() else parent.button1:Disable() end
    end
end

-- Pre-fill for a rate/keep edit box: "100% of surplus" -> "100%",
-- "10g/day" -> "10g". (The old code turned "10g/day" into "10gg".)
local function ratePrefill(label)
    return label:gsub(" of surplus", ""):gsub("g/day", "g")
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

-- Daily keep: gold held back for day-to-day spending, "50%" or "1g" syntax
-- just like goal rates. 0 / "0%" switches it off again.
StaticPopupDialogs["SG_DAILY_KEEP"] = {
    text = "Keep back for day-to-day spending — e.g. half of surplus, or 1g per day:",
    button1 = "Set", button2 = "Cancel",
    hasEditBox = true, maxLetters = 12,
    OnShow = function(self)
        pendingKeep = nil
        setPopupText(self, ratePrefill(SG:DailyKeepLabel()))
    end,
    EditBoxOnTextChanged = function(self) captureAndGate(self, "keep") end,
    OnAccept = function(self)
        local text = popupText(self, pendingKeep)
        if text and text ~= "" and SG:SetDailyKeep(text) then
            pendingKeep = nil
            SG:RefreshUI(); SG:RefreshBroker()
        else
            return true -- empty or invalid: keep popup open so it can be corrected
        end
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

-- NOTE: never put a bare % in a dialog's `text`. Blizzard runs it through
-- SetFormattedText, so "50%" throws a format error inside StaticPopup_Show
-- and the popup simply never appears — with script errors off, the button
-- looks dead. That was the Rate button bug (7 Nov 2026): only the Rate
-- dialog had a % in its text, so only Rate did nothing. The % in the
-- *prefill* is fine — that goes through edit-box SetText, not formatting.
StaticPopupDialogs["SG_GOAL_RATE"] = {
    text = "Savings rate for this goal — e.g. half of surplus, or 10g per day:",
    button1 = "Set", button2 = "Cancel",
    hasEditBox = true, maxLetters = 12,
    OnShow = function(self, goal)
        pendingRate = nil
        setPopupText(self, ratePrefill(SG:RateLabel(goal)))
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
