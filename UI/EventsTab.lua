--[[
    MedaDebug Events Tab
    Live event stream with filtering
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local EventsTab = {}
MedaDebug.EventsTab = EventsTab

EventsTab.frame = nil
EventsTab.scrollList = nil
EventsTab.categoryFilter = "all"
EventsTab.isPaused = false

function EventsTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()
    
    -- Disabled message (shown when event monitoring is off)
    self.disabledMsg = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.disabledMsg:SetPoint("CENTER", 0, 20)
    self.disabledMsg:SetText("Event Monitoring is disabled")
    self.disabledMsg:SetTextColor(1, 0.8, 0)
    
    self.disabledHint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.disabledHint:SetPoint("TOP", self.disabledMsg, "BOTTOM", 0, -8)
    self.disabledHint:SetText("Monitors WoW events in real-time")
    self.disabledHint:SetTextColor(unpack(Theme.textDim))
    
    -- Enable button (shown when disabled)
    self.enableBtn = MedaUI:CreateButton(parent, "Enable Event Monitoring", 160, 28)
    self.enableBtn:SetPoint("TOP", self.disabledHint, "BOTTOM", 0, -12)
    self.enableBtn:SetScript("OnClick", function()
        MedaDebug.db.options.enableEventMonitor = true
        if MedaDebug.EventMonitor then
            MedaDebug.EventMonitor:Enable()
        end
        self:UpdateEnabledState()
    end)
    
    -- Toggle checkbox in toolbar (shown when enabled)
    self.enabledCheckbox = MedaUI:CreateCheckbox(parent, "Enabled")
    self.enabledCheckbox:SetPoint("TOPRIGHT", -4, 2)
    self.enabledCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.enableEventMonitor = checked
        if checked then
            if MedaDebug.EventMonitor then MedaDebug.EventMonitor:Enable() end
        else
            if MedaDebug.EventMonitor then MedaDebug.EventMonitor:Disable() end
        end
        self:UpdateEnabledState()
    end
    
    -- Category dropdown at top
    local categories = {
        {value = "all", label = "All Events"},
        {value = "addon", label = "Addon"},
        {value = "unit", label = "Unit"},
        {value = "combat", label = "Combat"},
        {value = "spell", label = "Spell"},
        {value = "player", label = "Player"},
        {value = "other", label = "Other"},
    }
    
    self.categoryDropdown = MedaUI:CreateDropdown(parent, 100, categories)
    self.categoryDropdown:SetPoint("TOPLEFT", 0, 0)
    self.categoryDropdown.OnValueChanged = function(_, value)
        self.categoryFilter = value
        self:RefreshData()
    end
    
    -- Pause button
    self.pauseBtn = MedaUI:CreateButton(parent, "Pause", 60, 22)
    self.pauseBtn:SetPoint("LEFT", self.categoryDropdown, "RIGHT", 8, 0)
    self.pauseBtn:SetScript("OnClick", function()
        self:TogglePause()
    end)
    
    -- Event count
    self.countLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.countLabel:SetPoint("LEFT", self.pauseBtn, "RIGHT", 8, 0)
    self.countLabel:SetTextColor(unpack(Theme.textDim))
    
    -- Scroll list
    self.scrollList = MedaUI:CreateScrollList(parent, parent:GetWidth(), parent:GetHeight() - 30, {
        rowHeight = 24,
        renderRow = function(row, data, index)
            self:RenderRow(row, data, index)
        end,
    })
    self.scrollList:SetPoint("TOPLEFT", 0, -28)
    self.scrollList:SetPoint("BOTTOMRIGHT", 0, 0)
    
    -- Connect to event monitor
    if MedaDebug.EventMonitor then
        MedaDebug.EventMonitor.onNewEvent = function(entry, isUpdate)
            if not self.isPaused then
                self:RefreshData()
            end
        end
    end
    
    self:RefreshData()
    self:UpdateEnabledState()
end

function EventsTab:UpdateEnabledState()
    local enabled = MedaDebug.EventMonitor and MedaDebug.EventMonitor:IsEnabled()
    
    -- Update checkbox state
    self.enabledCheckbox:SetChecked(enabled)
    
    if enabled then
        self.disabledMsg:Hide()
        self.disabledHint:Hide()
        self.enableBtn:Hide()
        self.categoryDropdown:Show()
        self.pauseBtn:Show()
        self.countLabel:Show()
        self.scrollList:Show()
        self.enabledCheckbox:Show()
    else
        self.disabledMsg:Show()
        self.disabledHint:Show()
        self.enableBtn:Show()
        self.categoryDropdown:Hide()
        self.pauseBtn:Hide()
        self.countLabel:Hide()
        self.scrollList:Hide()
        self.enabledCheckbox:Hide()
    end
end

function EventsTab:RenderRow(row, data, index)
    if not data then return end
    
    local Theme = MedaUI:GetTheme()
    
    if not row.timestamp then
        row.timestamp = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.timestamp:SetPoint("LEFT", 4, 0)
        row.timestamp:SetWidth(80)
    end
    
    if not row.eventName then
        row.eventName = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.eventName:SetPoint("LEFT", 90, 0)
        row.eventName:SetWidth(180)
        row.eventName:SetJustifyH("LEFT")
    end
    
    if not row.args then
        row.args = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.args:SetPoint("LEFT", 280, 0)
        row.args:SetPoint("RIGHT", -40, 0)
        row.args:SetJustifyH("LEFT")
        row.args:SetWordWrap(false)
    end
    
    if not row.count then
        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.count:SetPoint("RIGHT", -4, 0)
    end
    
    row.timestamp:SetText(data.datetime or "")
    row.timestamp:SetTextColor(unpack(Theme.textDim))
    
    row.eventName:SetText(data.event or "")
    row.eventName:SetTextColor(unpack(Theme.gold))
    
    local argsStr = MedaDebug.EventMonitor:FormatArgs(data.args)
    row.args:SetText(argsStr)
    row.args:SetTextColor(unpack(Theme.text))
    
    if data.throttleCount and data.throttleCount > 1 then
        row.count:SetText("x" .. data.throttleCount)
        row.count:SetTextColor(unpack(Theme.levelWarn))
    else
        row.count:SetText("")
    end
end

function EventsTab:RefreshData()
    if not self.scrollList or not MedaDebug.EventMonitor then return end
    
    local events = MedaDebug.EventMonitor:GetFilteredEvents(self.categoryFilter)
    self.scrollList:SetData(events)
    
    -- Update count
    self.countLabel:SetText(#events .. " events")
    
    -- Auto-scroll
    if MedaDebug.db and MedaDebug.db.options.autoScroll and not self.isPaused then
        self.scrollList:ScrollToBottom()
    end
end

function EventsTab:TogglePause()
    if MedaDebug.EventMonitor then
        self.isPaused = MedaDebug.EventMonitor:TogglePause()
        self.pauseBtn:SetText(self.isPaused and "Resume" or "Pause")
    end
end

function EventsTab:Clear()
    if MedaDebug.EventMonitor then
        MedaDebug.EventMonitor:ClearEvents()
    end
    self:RefreshData()
end

function EventsTab:OnShow()
    self:UpdateEnabledState()
    if MedaDebug.EventMonitor and MedaDebug.EventMonitor:IsEnabled() then
        self:RefreshData()
    end
end

function EventsTab:OnFilterChanged(filter)
    -- Events filter by category, not addon
end

function EventsTab:OnSearch(text)
    -- TODO: Filter events by search
end
