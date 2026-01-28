--[[
    MedaDebug Error Notification
    Floating icon that appears when errors occur
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local ErrorNotification = {}
MedaDebug.ErrorNotification = ErrorNotification

ErrorNotification.frame = nil
ErrorNotification.errorCount = 0

function ErrorNotification:Initialize()
    if self.frame then return end
    
    local Theme = MedaUI:GetTheme()
    local db = MedaDebug.db
    local settings = db.options.errorNotification
    local pos = db.errorNotificationPosition
    
    -- Create main frame
    local frame = CreateFrame("Button", "MedaDebugErrorNotification", UIParent)
    frame:SetSize(settings.size, settings.size)
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:Hide()
    
    -- Make draggable
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        local point, _, _, x, y = self:GetPoint()
        db.errorNotificationPosition.point = point
        db.errorNotificationPosition.x = x
        db.errorNotificationPosition.y = y
    end)
    
    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "BACKGROUND")
    frame.icon:SetAllPoints()
    frame.icon:SetTexture("Interface\\AddOns\\MedaDebug\\Media\\debug")
    
    -- Badge background (red circle)
    frame.badgeBg = frame:CreateTexture(nil, "OVERLAY")
    frame.badgeBg:SetSize(24, 24)
    frame.badgeBg:SetPoint("BOTTOMRIGHT", 4, -4)
    frame.badgeBg:SetColorTexture(0.8, 0.2, 0.2, 1)
    
    -- Make badge background circular using mask
    local badgeMask = frame:CreateMaskTexture()
    badgeMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    badgeMask:SetAllPoints(frame.badgeBg)
    frame.badgeBg:AddMaskTexture(badgeMask)
    
    -- Badge text (error count)
    frame.badge = frame:CreateFontString(nil, "OVERLAY")
    frame.badge:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    frame.badge:SetPoint("CENTER", frame.badgeBg, "CENTER", 0, 0)
    frame.badge:SetTextColor(1, 1, 1)
    frame.badge:SetText("0")
    
    -- Click handlers
    frame:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            -- Show debug window and switch to errors tab
            if MedaDebug.DebugFrame then
                MedaDebug.DebugFrame:Show()
                MedaDebug.DebugFrame:SetActiveTab("errors")
            end
        elseif button == "RightButton" then
            -- Clear all errors
            if MedaDebug.ErrorHandler then
                MedaDebug.ErrorHandler:ClearErrors()
            end
        end
    end)
    
    -- Tooltip
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("MedaDebug Errors", 1, 0.8, 0)
        GameTooltip:AddLine(" ")
        local count = ErrorNotification.errorCount
        if count == 1 then
            GameTooltip:AddLine("1 error this session", 1, 0.4, 0.4)
        else
            GameTooltip:AddLine(count .. " errors this session", 1, 0.4, 0.4)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: View errors", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click: Clear errors", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    self.frame = frame
    
    -- Apply initial settings
    self:ApplySettings()
    
    -- Check if we should show (in case errors happened before initialization)
    if MedaDebug.ErrorHandler then
        local count = MedaDebug.ErrorHandler:GetErrorCount()
        if count > 0 then
            self:UpdateCount(count)
        end
    end
end

function ErrorNotification:Show()
    if not self.frame then return end
    if not MedaDebug.db.options.errorNotification.enabled then return end
    
    -- Fade in
    self.frame:SetAlpha(0)
    self.frame:Show()
    
    local targetAlpha = MedaDebug.db.options.errorNotification.opacity
    local fadeIn = self.frame:CreateAnimationGroup()
    local alpha = fadeIn:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(targetAlpha)
    alpha:SetDuration(0.3)
    alpha:SetSmoothing("OUT")
    fadeIn:SetScript("OnFinished", function()
        self.frame:SetAlpha(targetAlpha)
    end)
    fadeIn:Play()
end

function ErrorNotification:Hide()
    if not self.frame then return end
    if not self.frame:IsShown() then return end
    
    -- Fade out
    local currentAlpha = self.frame:GetAlpha()
    local fadeOut = self.frame:CreateAnimationGroup()
    local alpha = fadeOut:CreateAnimation("Alpha")
    alpha:SetFromAlpha(currentAlpha)
    alpha:SetToAlpha(0)
    alpha:SetDuration(0.2)
    alpha:SetSmoothing("IN")
    fadeOut:SetScript("OnFinished", function()
        self.frame:Hide()
        self.frame:SetAlpha(MedaDebug.db.options.errorNotification.opacity)
    end)
    fadeOut:Play()
end

function ErrorNotification:UpdateCount(count)
    self.errorCount = count
    
    if not self.frame then return end
    
    -- Update badge text
    if count > 99 then
        self.frame.badge:SetText("99+")
    else
        self.frame.badge:SetText(tostring(count))
    end
    
    -- Adjust badge size based on digit count
    local badgeSize = 24
    if count > 99 then
        badgeSize = 32
        self.frame.badge:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    elseif count > 9 then
        badgeSize = 28
        self.frame.badge:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    else
        self.frame.badge:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    end
    self.frame.badgeBg:SetSize(badgeSize, badgeSize)
    
    -- Show or hide based on count and enabled state
    if count > 0 and MedaDebug.db.options.errorNotification.enabled then
        if not self.frame:IsShown() then
            self:Show()
        end
    else
        if self.frame:IsShown() then
            self:Hide()
        end
    end
end

function ErrorNotification:ApplySettings()
    if not self.frame then return end
    
    local settings = MedaDebug.db.options.errorNotification
    
    -- Apply size
    self.frame:SetSize(settings.size, settings.size)
    
    -- Scale badge proportionally
    local badgeScale = settings.size / 64
    local baseBadgeSize = 24 * badgeScale
    self.frame.badgeBg:SetSize(baseBadgeSize, baseBadgeSize)
    self.frame.badge:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, 12 * badgeScale), "OUTLINE")
    
    -- Apply opacity
    self.frame:SetAlpha(settings.opacity)
    
    -- Show/hide based on enabled state and error count
    if settings.enabled and self.errorCount > 0 then
        if not self.frame:IsShown() then
            self.frame:Show()
        end
    else
        if self.frame:IsShown() then
            self.frame:Hide()
        end
    end
end

function ErrorNotification:SetEnabled(enabled)
    MedaDebug.db.options.errorNotification.enabled = enabled
    self:ApplySettings()
end

function ErrorNotification:SetSize(size)
    MedaDebug.db.options.errorNotification.size = size
    self:ApplySettings()
end

function ErrorNotification:SetOpacity(opacity)
    MedaDebug.db.options.errorNotification.opacity = opacity
    if self.frame then
        self.frame:SetAlpha(opacity)
    end
end
