--[[
    MedaDebug System Tab
    System info, memory, and SV diff display
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local SystemTab = {}
MedaDebug.SystemTab = SystemTab

SystemTab.frame = nil

function SystemTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()
    
    -- Disabled message (shown when system monitoring is off)
    self.disabledMsg = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.disabledMsg:SetPoint("CENTER", 0, 20)
    self.disabledMsg:SetText("System Monitoring is disabled")
    self.disabledMsg:SetTextColor(1, 0.8, 0)
    
    self.disabledHint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.disabledHint:SetPoint("TOP", self.disabledMsg, "BOTTOM", 0, -8)
    self.disabledHint:SetText("Polls FPS, memory, and latency stats")
    self.disabledHint:SetTextColor(unpack(Theme.textDim))
    
    -- Enable button (shown when disabled)
    self.enableBtn = MedaUI:CreateButton(parent, "Enable System Monitoring", 170, 28)
    self.enableBtn:SetPoint("TOP", self.disabledHint, "BOTTOM", 0, -12)
    self.enableBtn:SetScript("OnClick", function()
        MedaDebug.db.options.enableSystemMonitor = true
        if MedaDebug.SystemMonitor then
            MedaDebug.SystemMonitor:Enable()
        end
        self:UpdateEnabledState()
        self:RefreshAll()
    end)
    
    -- Toggle checkbox in toolbar (shown when enabled, positioned after snapshot button later)
    self.enabledCheckbox = MedaUI:CreateCheckbox(parent, "Enabled")
    self.enabledCheckbox:SetPoint("TOPRIGHT", -4, 2)
    self.enabledCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.enableSystemMonitor = checked
        if checked then
            if MedaDebug.SystemMonitor then MedaDebug.SystemMonitor:Enable() end
            self:RefreshAll()
        else
            if MedaDebug.SystemMonitor then MedaDebug.SystemMonitor:Disable() end
        end
        self:UpdateEnabledState()
    end
    
    -- Stats section
    self.statsFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self.statsFrame:SetHeight(80)
    self.statsFrame:SetPoint("TOPLEFT", 0, 0)
    self.statsFrame:SetPoint("TOPRIGHT", 0, 0)
    self.statsFrame:SetBackdrop(MedaUI:CreateBackdrop(true))
    self.statsFrame:SetBackdropColor(unpack(Theme.backgroundDark))
    self.statsFrame:SetBackdropBorderColor(unpack(Theme.border))
    
    -- Stats labels
    self.fpsLabel = self:CreateStatLabel(self.statsFrame, "FPS:", 10, -10)
    self.memoryLabel = self:CreateStatLabel(self.statsFrame, "Memory:", 10, -28)
    self.latencyLabel = self:CreateStatLabel(self.statsFrame, "Latency:", 10, -46)
    self.uptimeLabel = self:CreateStatLabel(self.statsFrame, "Uptime:", 10, -64)
    
    self.versionLabel = self:CreateStatLabel(self.statsFrame, "WoW:", 200, -10)
    self.addonsLabel = self:CreateStatLabel(self.statsFrame, "Addons:", 200, -28)
    self.combatLabel = self:CreateStatLabel(self.statsFrame, "Combat:", 200, -46)
    self.reloadsLabel = self:CreateStatLabel(self.statsFrame, "Reloads:", 200, -64)
    
    -- Memory breakdown section
    self.memoryTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.memoryTitle:SetPoint("TOPLEFT", self.statsFrame, "BOTTOMLEFT", 0, -10)
    self.memoryTitle:SetText("Memory by Addon")
    self.memoryTitle:SetTextColor(unpack(Theme.gold))
    
    -- Refresh memory button (memory scan is expensive, so manual refresh is useful)
    self.refreshMemBtn = MedaUI:CreateButton(parent, "Refresh", 70, 20)
    self.refreshMemBtn:SetPoint("LEFT", self.memoryTitle, "RIGHT", 10, 0)
    self.refreshMemBtn:SetScript("OnClick", function()
        if MedaDebug.SystemMonitor then
            MedaDebug.SystemMonitor:RefreshMemory()
            self:RefreshMemory()
        end
    end)
    
    -- Memory update hint
    self.memoryHint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.memoryHint:SetPoint("LEFT", self.refreshMemBtn, "RIGHT", 8, 0)
    self.memoryHint:SetText("(updates every 10s)")
    self.memoryHint:SetTextColor(unpack(Theme.textDim))
    
    self.memoryList = MedaUI:CreateScrollList(parent, parent:GetWidth() / 2 - 10, parent:GetHeight() - 130, {
        rowHeight = 20,
        renderRow = function(row, data, index)
            self:RenderMemoryRow(row, data, index)
        end,
    })
    self.memoryList:SetPoint("TOPLEFT", self.memoryTitle, "BOTTOMLEFT", 0, -4)
    
    -- SV Diff section
    self.diffTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.diffTitle:SetPoint("TOPLEFT", self.statsFrame, "BOTTOMLEFT", parent:GetWidth() / 2 + 10, -10)
    self.diffTitle:SetText("SavedVariables Changes")
    self.diffTitle:SetTextColor(unpack(Theme.gold))
    
    self.snapshotBtn = MedaUI:CreateButton(parent, "Snapshot", 70, 20)
    self.snapshotBtn:SetPoint("LEFT", self.diffTitle, "RIGHT", 8, 0)
    self.snapshotBtn:SetScript("OnClick", function()
        if MedaDebug.SVDiff then
            MedaDebug.SVDiff:TakeSnapshot()
            self:RefreshDiff()
        end
    end)
    
    self.diffBlock = MedaUI:CreateCodeBlock(parent, parent:GetWidth() / 2 - 10, parent:GetHeight() - 150, {
        showLineNumbers = false,
    })
    self.diffBlock:SetPoint("TOPLEFT", self.diffTitle, "BOTTOMLEFT", 0, -24)
    
    -- Connect to system monitor
    if MedaDebug.SystemMonitor then
        MedaDebug.SystemMonitor.onStatsUpdated = function(stats)
            self:UpdateStats(stats)
        end
    end
    
    -- Initial update
    self:RefreshAll()
end

function SystemTab:CreateStatLabel(parent, label, x, y)
    local Theme = MedaUI:GetTheme()
    
    local labelText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("TOPLEFT", x, y)
    labelText:SetText(label)
    labelText:SetTextColor(unpack(Theme.textDim))
    
    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueText:SetPoint("LEFT", labelText, "RIGHT", 4, 0)
    valueText:SetTextColor(unpack(Theme.text))
    valueText.value = ""
    
    return valueText
end

function SystemTab:UpdateStats(stats)
    if not stats then return end
    
    local Theme = MedaUI:GetTheme()
    
    -- FPS (using MedaUI status color utility)
    local fps = stats.fps or 0
    self.fpsLabel:SetText(string.format("%.0f", fps))
    self.fpsLabel:SetTextColor(MedaUI:GetFPSColor(fps))
    
    -- Memory
    local mem = stats.memory or 0
    self.memoryLabel:SetText(MedaDebug.SystemMonitor:FormatMemory(mem))
    
    -- Latency
    self.latencyLabel:SetText(string.format("%dms / %dms", 
        stats.latencyHome or 0, 
        stats.latencyWorld or 0
    ))
    
    -- Uptime
    self.uptimeLabel:SetText(MedaDebug.SystemMonitor:FormatUptime(stats.sessionUptime or 0))
    
    -- WoW Version
    local version = MedaDebug.SystemMonitor:GetWoWVersion()
    if version then
        self.versionLabel:SetText(version.version or "?")
    end
    
    -- Addon count
    self.addonsLabel:SetText(tostring(stats.addonCount or 0))
    
    -- Combat (using MedaUI status color utility)
    self.combatLabel:SetText(stats.inCombat and "Yes" or "No")
    self.combatLabel:SetTextColor(MedaUI:GetCombatColor(stats.inCombat))
    
    -- Reloads
    if MedaDebug.log and MedaDebug.log.session then
        self.reloadsLabel:SetText(tostring(MedaDebug.log.session.reloadCount or 0))
    end
end

function SystemTab:RenderMemoryRow(row, data, index)
    if not data then return end
    
    local Theme = MedaUI:GetTheme()
    
    if not row.nameLabel then
        row.nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.nameLabel:SetPoint("LEFT", 4, 0)
        row.nameLabel:SetWidth(150)
        row.nameLabel:SetJustifyH("LEFT")
    end
    
    if not row.memLabel then
        row.memLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.memLabel:SetPoint("RIGHT", -4, 0)
    end
    
    row.nameLabel:SetText(data.name)
    row.nameLabel:SetTextColor(unpack(Theme.text))
    
    row.memLabel:SetText(MedaDebug.SystemMonitor:FormatMemory(data.memory))
    row.memLabel:SetTextColor(unpack(Theme.textDim))
end

function SystemTab:RefreshMemory()
    if not MedaDebug.SystemMonitor then return end
    
    local memData = MedaDebug.SystemMonitor:GetAddonMemory(true)
    self.memoryList:SetData(memData)
end

function SystemTab:RefreshDiff()
    if not MedaDebug.SVDiff then return end
    
    MedaDebug.SVDiff:CalculateDiff()
    local diffText = MedaDebug.SVDiff:FormatDiff()
    self.diffBlock:SetText(diffText)
end

function SystemTab:RefreshAll()
    if MedaDebug.SystemMonitor then
        MedaDebug.SystemMonitor:Update()
        self:UpdateStats(MedaDebug.SystemMonitor:GetStats())
    end
    self:RefreshMemory()
    self:RefreshDiff()
end

function SystemTab:OnShow()
    self:UpdateEnabledState()
    if MedaDebug.SystemMonitor and MedaDebug.SystemMonitor:IsEnabled() then
        self:RefreshAll()
    end
end

function SystemTab:UpdateEnabledState()
    local enabled = MedaDebug.SystemMonitor and MedaDebug.SystemMonitor:IsEnabled()
    
    -- Update checkbox state
    self.enabledCheckbox:SetChecked(enabled)
    
    if enabled then
        self.disabledMsg:Hide()
        self.disabledHint:Hide()
        self.enableBtn:Hide()
        self.statsFrame:Show()
        self.memoryTitle:Show()
        self.refreshMemBtn:Show()
        self.memoryHint:Show()
        self.memoryList:Show()
        self.diffTitle:Show()
        self.snapshotBtn:Show()
        self.diffBlock:Show()
        self.enabledCheckbox:Show()
    else
        self.disabledMsg:Show()
        self.disabledHint:Show()
        self.enableBtn:Show()
        self.statsFrame:Hide()
        self.memoryTitle:Hide()
        self.refreshMemBtn:Hide()
        self.memoryHint:Hide()
        self.memoryList:Hide()
        self.diffTitle:Hide()
        self.snapshotBtn:Hide()
        self.diffBlock:Hide()
        self.enabledCheckbox:Hide()
    end
end

function SystemTab:Clear()
    -- Nothing to clear really
end
