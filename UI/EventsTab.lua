--[[
    MedaDebug Events Tab
    Live event stream with filtering
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-2.0")

local EventsTab = {}
MedaDebug.EventsTab = EventsTab

EventsTab.frame = nil
EventsTab.scrollList = nil
EventsTab.categoryFilter = "all"
EventsTab.isPaused = false
EventsTab.searchText = ""
EventsTab.searchLower = nil
EventsTab.viewData = nil

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

function EventsTab:FindVisibleRow(entry)
    if not self.scrollList or not self.scrollList.visibleRows then
        return nil
    end

    for i = 1, #self.scrollList.visibleRows do
        local row = self.scrollList.visibleRows[i]
        if row and row.boundData == entry then
            return row
        end
    end

    return nil
end

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
            if not self.isPaused and self.frame and self.frame:IsShown() then
                if entry == nil then
                    self:RefreshData()
                elseif isUpdate then
                    if self:MatchesFilters(entry) then
                        local row = self:FindVisibleRow(entry)
                        if row then
                            self:RenderRow(row, entry, row._dataIndex or 0)
                        else
                            self.scrollList:Refresh()
                        end
                    else
                        self:RefreshData()
                    end
                elseif not self:HasActiveSearch() and self:MatchesFilters(entry) and self.viewData then
                    self.scrollList:AddItem(entry, MedaDebug.db and MedaDebug.db.options.autoScroll)
                    self.countLabel:SetText(self.scrollList:GetItemCount() .. " events")
                else
                    self:RefreshData()
                end
            end
        end
    end
    
    self:RefreshData()
    self:UpdateEnabledState()
end

function EventsTab:HasActiveSearch()
    return self.searchText and self.searchText ~= ""
end

function EventsTab:MatchesFilters(entry)
    if self.categoryFilter ~= "all" and entry.category ~= self.categoryFilter then
        return false
    end

    local search = self.searchLower
    if search then
        local matchesEvent = entry.searchEvent and entry.searchEvent:find(search, 1, true)
        local matchesArgs = entry.searchArgs and entry.searchArgs:find(search, 1, true)
        local matchesCategory = entry.searchCategory and entry.searchCategory:find(search, 1, true)
        if not matchesEvent and not matchesArgs and not matchesCategory then
            return false
        end
    end

    return true
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
    
    local Theme = MedaUI.Theme or MedaUI:GetTheme()
    row.boundData = data
    
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
    
    SetFontStringText(row.timestamp, data.datetime or "")
    SetFontStringColor(row.timestamp, Theme.textDim)
    
    SetFontStringText(row.eventName, data.event or "")
    SetFontStringColor(row.eventName, Theme.gold)
    
    SetFontStringText(row.args, data.displayArgs or "(no args)")
    SetFontStringColor(row.args, Theme.text)
    
    if data.throttleCount and data.throttleCount > 1 then
        SetFontStringText(row.count, "x" .. data.throttleCount)
        SetFontStringColor(row.count, Theme.levelWarn)
    else
        SetFontStringText(row.count, "")
    end
end

function EventsTab:RefreshData()
    if not self.scrollList or not MedaDebug.EventMonitor then return end
    local profile = MedaDebug.ProfilerLite and MedaDebug.ProfilerLite:BeginSample("Events.RefreshData", "ui", "EventsTab")
    
    local events = MedaDebug.EventMonitor:GetFilteredEvents(self.categoryFilter)
    local filtered = {}

    for _, event in ipairs(events) do
        if self:MatchesFilters(event) then
            filtered[#filtered + 1] = event
        end
    end

    self.viewData = filtered
    self.scrollList:SetData(self.viewData)
    
    -- Update count
    self.countLabel:SetText(#self.viewData .. " events")
    
    -- Auto-scroll
    if MedaDebug.db and MedaDebug.db.options.autoScroll and not self.isPaused then
        self.scrollList:ScrollToBottom()
    end

    if profile then
        MedaDebug.ProfilerLite:EndSample(profile)
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
    self.searchText = text or ""
    self.searchLower = self.searchText ~= "" and self.searchText:lower() or nil
    self:RefreshData()
end

if MedaDebug.WorkspaceRegistry then
    MedaDebug.WorkspaceRegistry:RegisterPage("events", {
        label = "Events",
        title = "Event Monitor",
        subtitle = "Live event traffic with category filtering and throttling.",
        summary = "Enable only when needed; this page is intended for targeted runtime inspection.",
        moduleKey = "EventsTab",
        height = 1200,
        groupId = "streams",
        groupLabel = "Streams",
        groupOrder = 10,
        pageOrder = 30,
    })
end
