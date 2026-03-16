--[[
    MedaDebug Timers Tab
    Active timer tracking display
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-2.0")

local TimersTab = {}
MedaDebug.TimersTab = TimersTab
local DEFAULT_ADDON_COLOR = { 0.6, 0.8, 1 }

TimersTab.frame = nil
TimersTab.scrollList = nil
TimersTab.addonFilter = "all"
TimersTab.lastUpdate = 0

local function SetFontStringText(fontString, text)
    text = text or ""
    if fontString._medaText ~= text then
        fontString:SetText(text)
        fontString._medaText = text
    end
end

local function SetFontStringColor(fontString, color)
    if not color then
        return
    end

    local r = color[1] or 1
    local g = color[2] or 1
    local b = color[3] or 1
    local a = color[4]

    if fontString._medaColorR ~= r
        or fontString._medaColorG ~= g
        or fontString._medaColorB ~= b
        or fontString._medaColorA ~= a then
        if a ~= nil then
            fontString:SetTextColor(r, g, b, a)
        else
            fontString:SetTextColor(r, g, b)
        end
        fontString._medaColorR = r
        fontString._medaColorG = g
        fontString._medaColorB = b
        fontString._medaColorA = a
    end
end

local function BuildCountdownText(timer)
    if not timer then
        return ""
    end

    local remaining = timer.timeRemaining or (timer.nextFireAt - GetTime())
    local countdownText = "next: " .. MedaDebug.TimerTracker:FormatTimeRemaining(remaining)
    if timer.type == "ticker" then
        if timer.iterations then
            countdownText = countdownText .. " #" .. timer.currentIteration .. "/" .. timer.iterations
        else
            countdownText = countdownText .. " ∞"
        end
    end

    return countdownText
end

function TimersTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()
    
    -- Disabled message (shown when timer tracking is off)
    self.disabledMsg = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.disabledMsg:SetPoint("CENTER", 0, 20)
    self.disabledMsg:SetText("Timer Tracking is disabled")
    self.disabledMsg:SetTextColor(1, 0.8, 0)
    
    self.disabledHint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.disabledHint:SetPoint("TOP", self.disabledMsg, "BOTTOM", 0, -8)
    self.disabledHint:SetText("Hooks C_Timer functions to track all timers")
    self.disabledHint:SetTextColor(unpack(Theme.textDim))
    
    -- Enable button (shown when disabled)
    self.enableBtn = MedaUI:CreateButton(parent, "Enable Timer Tracking", 160, 28)
    self.enableBtn:SetPoint("TOP", self.disabledHint, "BOTTOM", 0, -12)
    self.enableBtn:SetScript("OnClick", function()
        MedaDebug.db.options.enableTimerTracking = true
        if MedaDebug.TimerTracker then
            MedaDebug.TimerTracker:Enable()
        end
        self:UpdateEnabledState()
    end)
    
    -- Toggle checkbox in toolbar (shown when enabled)
    self.enabledCheckbox = MedaUI:CreateCheckbox(parent, "Enabled")
    self.enabledCheckbox:SetPoint("TOPRIGHT", -4, 2)
    self.enabledCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.enableTimerTracking = checked
        if checked then
            if MedaDebug.TimerTracker then MedaDebug.TimerTracker:Enable() end
        else
            if MedaDebug.TimerTracker then MedaDebug.TimerTracker:Disable() end
        end
        self:UpdateEnabledState()
    end
    
    -- Filter dropdown
    self.filterDropdown = MedaUI:CreateDropdown(parent, 120, {
        {value = "all", label = "All Addons"},
    })
    self.filterDropdown:SetPoint("TOPLEFT", 0, 0)
    self.filterDropdown.OnValueChanged = function(_, value)
        self.addonFilter = value
        self:RefreshData()
    end
    
    -- Timer count
    self.countLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.countLabel:SetPoint("LEFT", self.filterDropdown, "RIGHT", 8, 0)
    self.countLabel:SetTextColor(unpack(Theme.textDim))
    
    -- Scroll list
    self.scrollList = MedaUI:CreateScrollList(parent, parent:GetWidth(), parent:GetHeight() - 30, {
        rowHeight = 40,
        renderRow = function(row, data, index)
            self:RenderRow(row, data, index)
        end,
    })
    self.scrollList:SetPoint("TOPLEFT", 0, -28)
    self.scrollList:SetPoint("BOTTOMRIGHT", 0, 0)
    
    -- Connect to timer tracker
    if MedaDebug.TimerTracker then
        MedaDebug.TimerTracker.onTimerAdded = function()
            if self.frame and self.frame:IsShown() then
                self:RefreshData()
                self:RefreshFilterDropdown()
            end
        end
        MedaDebug.TimerTracker.onTimerRemoved = function()
            if self.frame and self.frame:IsShown() then
                self:RefreshData()
            end
        end
    end
    
    self.updateFrame = CreateFrame("Frame")
    self.updateFrame:Hide()

    self.frame:HookScript("OnShow", function()
        self:StartVisibleUpdates()
    end)
    self.frame:HookScript("OnHide", function()
        self:StopVisibleUpdates()
    end)
    
    self:RefreshFilterDropdown()
    self:RefreshData()
    self:UpdateEnabledState()
end

function TimersTab:StartVisibleUpdates()
    if not self.updateFrame or not self.frame or not self.frame:IsShown() then
        return
    end

    self.updateFrame:SetScript("OnUpdate", function(_, elapsed)
        self:OnUpdate(elapsed)
    end)
    self.updateFrame:Show()
end

function TimersTab:StopVisibleUpdates()
    if not self.updateFrame then
        return
    end

    self.updateFrame:SetScript("OnUpdate", nil)
    self.updateFrame:Hide()
end

function TimersTab:UpdateVisibleCountdowns()
    if not self.scrollList or not self.scrollList.visibleRows then
        return
    end

    local Theme = MedaUI.Theme or MedaUI:GetTheme()
    for i = 1, #self.scrollList.visibleRows do
        local row = self.scrollList.visibleRows[i]
        if row and row.timerData and row.countdownLabel then
            SetFontStringText(row.countdownLabel, BuildCountdownText(row.timerData))
            SetFontStringColor(row.countdownLabel, Theme.text)

            if row.warningIcon then
                if row.timerData.isHighFrequency then
                    row.warningIcon:Show()
                    SetFontStringColor(row.warningIcon, { 1, 0.8, 0 })
                else
                    row.warningIcon:Hide()
                end
            end
        end
    end
end

function TimersTab:UpdateEnabledState()
    local enabled = MedaDebug.TimerTracker and MedaDebug.TimerTracker:IsEnabled()
    
    -- Update checkbox state
    self.enabledCheckbox:SetChecked(enabled)
    
    if enabled then
        self.disabledMsg:Hide()
        self.disabledHint:Hide()
        self.enableBtn:Hide()
        self.filterDropdown:Show()
        self.countLabel:Show()
        self.scrollList:Show()
        self.enabledCheckbox:Show()
        self:StartVisibleUpdates()
    else
        self.disabledMsg:Show()
        self.disabledHint:Show()
        self.enableBtn:Show()
        self.filterDropdown:Hide()
        self.countLabel:Hide()
        self.scrollList:Hide()
        self.enabledCheckbox:Hide()
        self:StopVisibleUpdates()
    end
end

function TimersTab:RenderRow(row, data, index)
    if not data then return end
    
    local Theme = MedaUI.Theme or MedaUI:GetTheme()
    
    if not row.typeLabel then
        row.typeLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.typeLabel:SetPoint("TOPLEFT", 4, -4)
    end
    
    if not row.addonLabel then
        row.addonLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.addonLabel:SetPoint("LEFT", row.typeLabel, "RIGHT", 4, 0)
    end
    
    if not row.durationLabel then
        row.durationLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.durationLabel:SetPoint("RIGHT", -4, 4)
    end
    
    if not row.sourceLabel then
        row.sourceLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.sourceLabel:SetPoint("TOPLEFT", 20, -20)
    end
    
    if not row.countdownLabel then
        row.countdownLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.countdownLabel:SetPoint("LEFT", row.sourceLabel, "RIGHT", 8, 0)
    end
    
    if not row.warningIcon then
        row.warningIcon = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.warningIcon:SetPoint("RIGHT", row.durationLabel, "LEFT", -4, 0)
        row.warningIcon:SetText("!")
    end
    
    -- Type badge
    SetFontStringText(row.typeLabel, "[" .. data.type:upper() .. "]")
    SetFontStringColor(row.typeLabel, Theme.gold)
    
    SetFontStringText(row.addonLabel, data.sourceAddon or "Unknown")
    SetFontStringColor(row.addonLabel, DEFAULT_ADDON_COLOR)
    
    if data.type == "ticker" then
        SetFontStringText(row.durationLabel, "every " .. string.format("%.2f", data.duration) .. "s")
    else
        SetFontStringText(row.durationLabel, "fires: " .. string.format("%.1f", data.duration) .. "s")
    end
    SetFontStringColor(row.durationLabel, Theme.textDim)
    
    SetFontStringText(row.sourceLabel, "└─ " .. (data.sourceLine or "unknown"))
    SetFontStringColor(row.sourceLabel, Theme.textDim)
    
    SetFontStringText(row.countdownLabel, BuildCountdownText(data))
    SetFontStringColor(row.countdownLabel, Theme.text)
    
    if data.isHighFrequency then
        row.warningIcon:Show()
        SetFontStringColor(row.warningIcon, { 1, 0.8, 0 })
    else
        row.warningIcon:Hide()
    end
    
    -- Store data for updates
    row.timerData = data
end

function TimersTab:RefreshData()
    if not self.scrollList or not MedaDebug.TimerTracker then return end
    local profile = MedaDebug.ProfilerLite and MedaDebug.ProfilerLite:BeginSample("Timers.RefreshData", "ui", "TimersTab")
    
    local timers = MedaDebug.TimerTracker:GetFilteredTimers(self.addonFilter)
    self.scrollList:SetData(timers)
    
    -- Update count
    local total = MedaDebug.TimerTracker:GetActiveCount()
    self.countLabel:SetText("Active: " .. total)

    if profile then
        MedaDebug.ProfilerLite:EndSample(profile)
    end
end

function TimersTab:RefreshFilterDropdown()
    if not MedaDebug.TimerTracker then return end
    
    local options = {{value = "all", label = "All Addons"}}
    local addons = MedaDebug.TimerTracker:GetAddonsWithTimers()
    
    for _, addon in ipairs(addons) do
        options[#options + 1] = {value = addon, label = addon}
    end
    
    self.filterDropdown:SetOptions(options)
end

function TimersTab:OnUpdate(elapsed)
    self.lastUpdate = self.lastUpdate + elapsed
    
    if self.lastUpdate > 0.1 then
        self.lastUpdate = 0
        if self.frame and self.frame:IsShown() then
            self:UpdateVisibleCountdowns()
        end
    end
end

function TimersTab:OnShow()
    self:UpdateEnabledState()
    if MedaDebug.TimerTracker and MedaDebug.TimerTracker:IsEnabled() then
        self:RefreshFilterDropdown()
        self:RefreshData()
        self:StartVisibleUpdates()
    end
end

function TimersTab:Clear()
    -- Can't really clear timers, just refresh
    self:RefreshData()
end

if MedaDebug.WorkspaceRegistry then
    MedaDebug.WorkspaceRegistry:RegisterPage("timers", {
        label = "Timers",
        title = "Timer Tracker",
        subtitle = "Observe scheduled timers and callback churn.",
        summary = "This page is most useful when timer tracking is enabled for a short, focused capture.",
        moduleKey = "TimersTab",
        height = 1000,
        groupId = "runtime",
        groupLabel = "Runtime",
        groupOrder = 30,
        pageOrder = 20,
    })
end
