--[[
    MedaDebug Settings Panel
    Configuration UI using MedaUI widgets
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local SettingsPanel = {}
MedaDebug.SettingsPanel = SettingsPanel

SettingsPanel.frame = nil

function SettingsPanel:Initialize()
    if self.frame then return end
    
    local Theme = MedaUI:GetTheme()
    
    -- Create panel
    self.frame = MedaUI:CreatePanel("MedaDebugSettings", 420, 520, "MedaDebug Settings")
    self.frame:SetResizable(true, {
        minWidth = 380,
        minHeight = 400,
        maxWidth = 600,
        maxHeight = 750,
    })
    
    local panelContent = self.frame:GetContent()
    
    -- Dark inner background
    local innerBg = CreateFrame("Frame", nil, panelContent, "BackdropTemplate")
    innerBg:SetPoint("TOPLEFT", 0, 0)
    innerBg:SetPoint("BOTTOMRIGHT", 0, 0)
    innerBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    innerBg:SetBackdropColor(unpack(Theme.backgroundDark))
    
    -- Scroll frame for content
    local scrollFrame = CreateFrame("ScrollFrame", nil, innerBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 4, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", -24, 4)
    
    -- Style the scrollbar
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 4, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4, 16)
    end
    
    -- Scroll child (actual content)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth() - 8)
    content:SetHeight(600)  -- Will be adjusted
    scrollFrame:SetScrollChild(content)
    
    local yPos = -8
    
    -- Helper to create section headers
    local function CreateSection(title)
        -- Section header background
        local headerBg = CreateFrame("Frame", nil, content, "BackdropTemplate")
        headerBg:SetHeight(24)
        headerBg:SetPoint("TOPLEFT", 0, yPos)
        headerBg:SetPoint("TOPRIGHT", 0, yPos)
        headerBg:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        headerBg:SetBackdropColor(unpack(Theme.background))
        
        local header = headerBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("LEFT", 8, 0)
        header:SetText(title)
        header:SetTextColor(unpack(Theme.gold))
        
        yPos = yPos - 28
    end
    
    -- Helper to create separator
    local function CreateSeparator()
        local sep = content:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", 8, yPos)
        sep:SetPoint("TOPRIGHT", -8, yPos)
        sep:SetColorTexture(unpack(Theme.border))
        yPos = yPos - 8
    end
    
    -- =====================
    -- General Section
    -- =====================
    CreateSection("General")
    
    -- Dev Mode
    local devModeCheckbox = MedaUI:CreateCheckbox(content, "Development Mode (auto-show on login)")
    devModeCheckbox:SetPoint("TOPLEFT", 12, yPos)
    devModeCheckbox:SetChecked(MedaDebug.db.options.devMode)
    devModeCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.devMode = checked
    end
    yPos = yPos - 24
    
    -- Output to chat
    local chatCheckbox = MedaUI:CreateCheckbox(content, "Output messages to chat")
    chatCheckbox:SetPoint("TOPLEFT", 12, yPos)
    chatCheckbox:SetChecked(MedaDebug.db.options.outputToChat)
    chatCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.outputToChat = checked
    end
    yPos = yPos - 24
    
    -- Auto-scroll
    local autoScrollCheckbox = MedaUI:CreateCheckbox(content, "Auto-scroll to new messages")
    autoScrollCheckbox:SetPoint("TOPLEFT", 12, yPos)
    autoScrollCheckbox:SetChecked(MedaDebug.db.options.autoScroll)
    autoScrollCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.autoScroll = checked
    end
    yPos = yPos - 24
    
    -- Restore session data
    local restoreCheckbox = MedaUI:CreateCheckbox(content, "Restore messages after /reload")
    restoreCheckbox:SetPoint("TOPLEFT", 12, yPos)
    restoreCheckbox:SetChecked(MedaDebug.db.options.restoreSessionData)
    restoreCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.restoreSessionData = checked
    end
    yPos = yPos - 16
    
    CreateSeparator()
    
    -- =====================
    -- Error Notifications Section
    -- =====================
    CreateSection("Error Notifications")
    
    -- Enable error notifications
    local errorNotifCheckbox = MedaUI:CreateCheckbox(content, "Enable Error Notifications")
    errorNotifCheckbox:SetPoint("TOPLEFT", 12, yPos)
    errorNotifCheckbox:SetChecked(MedaDebug.db.options.errorNotification.enabled)
    errorNotifCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.errorNotification.enabled = checked
        if MedaDebug.ErrorNotification then
            MedaDebug.ErrorNotification:ApplySettings()
        end
    end
    yPos = yPos - 24
    
    -- Icon size slider
    local iconSizeLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconSizeLabel:SetPoint("TOPLEFT", 12, yPos)
    iconSizeLabel:SetText("Icon size:")
    iconSizeLabel:SetTextColor(unpack(Theme.text))
    
    local iconSizeSlider = MedaUI:CreateSlider(content, 180, 32, 128, 8)
    iconSizeSlider:SetPoint("TOPLEFT", 140, yPos + 4)
    iconSizeSlider:SetValue(MedaDebug.db.options.errorNotification.size)
    iconSizeSlider.OnValueChanged = function(_, value)
        MedaDebug.db.options.errorNotification.size = value
        if MedaDebug.ErrorNotification then
            MedaDebug.ErrorNotification:ApplySettings()
        end
    end
    yPos = yPos - 32
    
    -- Opacity slider
    local opacityLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    opacityLabel:SetPoint("TOPLEFT", 12, yPos)
    opacityLabel:SetText("Opacity:")
    opacityLabel:SetTextColor(unpack(Theme.text))
    
    local opacitySlider = MedaUI:CreateSlider(content, 180, 0.3, 1.0, 0.1)
    opacitySlider:SetPoint("TOPLEFT", 140, yPos + 4)
    opacitySlider:SetValue(MedaDebug.db.options.errorNotification.opacity)
    opacitySlider.OnValueChanged = function(_, value)
        MedaDebug.db.options.errorNotification.opacity = value
        if MedaDebug.ErrorNotification then
            MedaDebug.ErrorNotification:SetOpacity(value)
        end
    end
    yPos = yPos - 16
    
    CreateSeparator()
    
    -- =====================
    -- Real-time Monitoring Section
    -- =====================
    CreateSection("Real-time Monitoring")
    
    local warningLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warningLabel:SetPoint("TOPLEFT", 12, yPos)
    warningLabel:SetText("These features add overhead. Enable only when needed.")
    warningLabel:SetTextColor(0.9, 0.6, 0.2)
    yPos = yPos - 20
    
    -- Timer Tracking
    local timerCheckbox = MedaUI:CreateCheckbox(content, "Timer Tracking (hooks C_Timer)")
    timerCheckbox:SetPoint("TOPLEFT", 12, yPos)
    timerCheckbox:SetChecked(MedaDebug.db.options.enableTimerTracking)
    timerCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.enableTimerTracking = checked
        if checked then
            if MedaDebug.TimerTracker then MedaDebug.TimerTracker:Enable() end
        else
            if MedaDebug.TimerTracker then MedaDebug.TimerTracker:Disable() end
        end
    end
    yPos = yPos - 24
    
    -- Event Monitoring
    local eventCheckbox = MedaUI:CreateCheckbox(content, "Event Monitoring")
    eventCheckbox:SetPoint("TOPLEFT", 12, yPos)
    eventCheckbox:SetChecked(MedaDebug.db.options.enableEventMonitor)
    eventCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.enableEventMonitor = checked
        if checked then
            if MedaDebug.EventMonitor then MedaDebug.EventMonitor:Enable() end
        else
            if MedaDebug.EventMonitor then MedaDebug.EventMonitor:Disable() end
        end
    end
    yPos = yPos - 24
    
    -- System Monitoring
    local sysCheckbox = MedaUI:CreateCheckbox(content, "System Monitor (FPS/Memory/Latency)")
    sysCheckbox:SetPoint("TOPLEFT", 12, yPos)
    sysCheckbox:SetChecked(MedaDebug.db.options.enableSystemMonitor)
    sysCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.enableSystemMonitor = checked
        if checked then
            if MedaDebug.SystemMonitor then MedaDebug.SystemMonitor:Enable() end
        else
            if MedaDebug.SystemMonitor then MedaDebug.SystemMonitor:Disable() end
        end
    end
    yPos = yPos - 16
    
    CreateSeparator()
    
    -- =====================
    -- Display Section
    -- =====================
    CreateSection("Display")
    
    -- Max messages
    local maxMsgsLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxMsgsLabel:SetPoint("TOPLEFT", 12, yPos)
    maxMsgsLabel:SetText("Max messages:")
    maxMsgsLabel:SetTextColor(unpack(Theme.text))
    
    local maxMsgsSlider = MedaUI:CreateSlider(content, 180, 100, 5000, 100)
    maxMsgsSlider:SetPoint("TOPLEFT", 140, yPos + 4)
    maxMsgsSlider:SetValue(MedaDebug.db.options.maxMessages)
    maxMsgsSlider.OnValueChanged = function(_, value)
        MedaDebug.db.options.maxMessages = value
    end
    yPos = yPos - 32
    
    -- Font size
    local fontLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fontLabel:SetPoint("TOPLEFT", 12, yPos)
    fontLabel:SetText("Font size:")
    fontLabel:SetTextColor(unpack(Theme.text))
    
    local fontSlider = MedaUI:CreateSlider(content, 180, 8, 16, 1)
    fontSlider:SetPoint("TOPLEFT", 140, yPos + 4)
    fontSlider:SetValue(MedaDebug.db.options.fontSize)
    fontSlider.OnValueChanged = function(_, value)
        MedaDebug.db.options.fontSize = value
    end
    yPos = yPos - 16
    
    CreateSeparator()
    
    -- =====================
    -- Event Monitor Section
    -- =====================
    CreateSection("Event Monitor")
    
    -- Throttle
    local throttleLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    throttleLabel:SetPoint("TOPLEFT", 12, yPos)
    throttleLabel:SetText("Throttle (events/sec):")
    throttleLabel:SetTextColor(unpack(Theme.text))
    
    local throttleSlider = MedaUI:CreateSlider(content, 180, 1, 50, 1)
    throttleSlider:SetPoint("TOPLEFT", 140, yPos + 4)
    throttleSlider:SetValue(MedaDebug.db.options.eventThrottle)
    throttleSlider.OnValueChanged = function(_, value)
        MedaDebug.db.options.eventThrottle = value
    end
    yPos = yPos - 16
    
    CreateSeparator()
    
    -- =====================
    -- System Monitor Section
    -- =====================
    CreateSection("System Monitor")
    
    -- Update interval
    local updateLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    updateLabel:SetPoint("TOPLEFT", 12, yPos)
    updateLabel:SetText("Update interval (sec):")
    updateLabel:SetTextColor(unpack(Theme.text))
    
    local updateSlider = MedaUI:CreateSlider(content, 180, 0.5, 5, 0.5)
    updateSlider:SetPoint("TOPLEFT", 140, yPos + 4)
    updateSlider:SetValue(MedaDebug.db.options.systemUpdateInterval)
    updateSlider.OnValueChanged = function(_, value)
        MedaDebug.db.options.systemUpdateInterval = value
        if MedaDebug.SystemMonitor then
            MedaDebug.SystemMonitor:SetUpdateInterval(value)
        end
    end
    yPos = yPos - 32
    
    -- Memory breakdown
    local memBreakdownCheckbox = MedaUI:CreateCheckbox(content, "Show memory breakdown by addon")
    memBreakdownCheckbox:SetPoint("TOPLEFT", 12, yPos)
    memBreakdownCheckbox:SetChecked(MedaDebug.db.options.showMemoryBreakdown)
    memBreakdownCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.showMemoryBreakdown = checked
    end
    yPos = yPos - 16
    
    CreateSeparator()
    
    -- =====================
    -- Quick Actions Section
    -- =====================
    CreateSection("Quick Actions")
    
    -- Confirm reload
    local confirmReloadCheckbox = MedaUI:CreateCheckbox(content, "Confirm before /reload")
    confirmReloadCheckbox:SetPoint("TOPLEFT", 12, yPos)
    confirmReloadCheckbox:SetChecked(MedaDebug.db.options.confirmReload)
    confirmReloadCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.confirmReload = checked
    end
    yPos = yPos - 32
    
    -- Set final content height
    content:SetHeight(math.abs(yPos) + 20)
    
    -- Register for ESC
    tinsert(UISpecialFrames, "MedaDebugSettings")
end

function SettingsPanel:Show()
    if not self.frame then
        self:Initialize()
    end
    self.frame:Show()
end

function SettingsPanel:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function SettingsPanel:Toggle()
    if not self.frame then
        self:Initialize()
        self.frame:Show()
    elseif self.frame:IsShown() then
        self.frame:Hide()
    else
        self.frame:Show()
    end
end

function SettingsPanel:IsShown()
    return self.frame and self.frame:IsShown()
end
