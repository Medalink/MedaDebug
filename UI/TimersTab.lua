--[[
    MedaDebug Timers Tab
    Active timer tracking display
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local TimersTab = {}
MedaDebug.TimersTab = TimersTab

TimersTab.frame = nil
TimersTab.scrollList = nil
TimersTab.addonFilter = "all"

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
            self:RefreshData()
            self:RefreshFilterDropdown()
        end
        MedaDebug.TimerTracker.onTimerRemoved = function()
            self:RefreshData()
        end
    end
    
    -- Update countdown display
    self.updateFrame = CreateFrame("Frame")
    self.updateFrame:SetScript("OnUpdate", function(_, elapsed)
        self:OnUpdate(elapsed)
    end)
    
    self:RefreshFilterDropdown()
    self:RefreshData()
    self:UpdateEnabledState()
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
    else
        self.disabledMsg:Show()
        self.disabledHint:Show()
        self.enableBtn:Show()
        self.filterDropdown:Hide()
        self.countLabel:Hide()
        self.scrollList:Hide()
        self.enabledCheckbox:Hide()
    end
end

function TimersTab:RenderRow(row, data, index)
    if not data then return end
    
    local Theme = MedaUI:GetTheme()
    
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
    local typeText = "[" .. data.type:upper() .. "]"
    row.typeLabel:SetText(typeText)
    row.typeLabel:SetTextColor(unpack(Theme.gold))
    
    -- Addon name
    row.addonLabel:SetText(data.sourceAddon or "Unknown")
    row.addonLabel:SetTextColor(0.6, 0.8, 1)
    
    -- Duration/interval
    if data.type == "ticker" then
        row.durationLabel:SetText("every " .. string.format("%.2f", data.duration) .. "s")
    else
        row.durationLabel:SetText("fires: " .. string.format("%.1f", data.duration) .. "s")
    end
    row.durationLabel:SetTextColor(unpack(Theme.textDim))
    
    -- Source
    row.sourceLabel:SetText("└─ " .. (data.sourceLine or "unknown"))
    row.sourceLabel:SetTextColor(unpack(Theme.textDim))
    
    -- Countdown
    local remaining = data.timeRemaining or (data.nextFireAt - GetTime())
    local countdownText = "next: " .. MedaDebug.TimerTracker:FormatTimeRemaining(remaining)
    if data.type == "ticker" then
        if data.iterations then
            countdownText = countdownText .. " #" .. data.currentIteration .. "/" .. data.iterations
        else
            countdownText = countdownText .. " ∞"
        end
    end
    row.countdownLabel:SetText(countdownText)
    row.countdownLabel:SetTextColor(unpack(Theme.text))
    
    -- High frequency warning
    if data.isHighFrequency then
        row.warningIcon:Show()
        row.warningIcon:SetTextColor(1, 0.8, 0)
    else
        row.warningIcon:Hide()
    end
    
    -- Store data for updates
    row.timerData = data
end

function TimersTab:RefreshData()
    if not self.scrollList or not MedaDebug.TimerTracker then return end
    
    local timers = MedaDebug.TimerTracker:GetFilteredTimers(self.addonFilter)
    self.scrollList:SetData(timers)
    
    -- Update count
    local total = MedaDebug.TimerTracker:GetActiveCount()
    self.countLabel:SetText("Active: " .. total)
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
    -- Refresh countdowns periodically
    if not self.lastUpdate then self.lastUpdate = 0 end
    self.lastUpdate = self.lastUpdate + elapsed
    
    if self.lastUpdate > 0.1 then
        self.lastUpdate = 0
        if self.frame and self.frame:IsShown() then
            self.scrollList:Refresh()
        end
    end
end

function TimersTab:OnShow()
    self:UpdateEnabledState()
    if MedaDebug.TimerTracker and MedaDebug.TimerTracker:IsEnabled() then
        self:RefreshFilterDropdown()
        self:RefreshData()
    end
end

function TimersTab:Clear()
    -- Can't really clear timers, just refresh
    self:RefreshData()
end
