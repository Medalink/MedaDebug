--[[
    MedaDebug Error Notification
    Floating icon that appears when errors occur
]]

local _, MedaDebug = ...
local MedaUI = LibStub("MedaUI-2.0")

local ErrorNotification = {}
MedaDebug.ErrorNotification = ErrorNotification

ErrorNotification.frame = nil
ErrorNotification.errorCount = 0
local DEFAULT_ERROR_ICON_TEXTURE = "Interface\\AddOns\\MedaDebug\\Media\\debug@2x"

local function CreateFadeAnimation(frame, fromAlpha, toAlpha, duration, smoothing, onFinished)
    local animationGroup = frame:CreateAnimationGroup()
    local alpha = animationGroup:CreateAnimation("Alpha")
    alpha:SetFromAlpha(fromAlpha)
    alpha:SetToAlpha(toAlpha)
    alpha:SetDuration(duration)
    alpha:SetSmoothing(smoothing)
    animationGroup:SetScript("OnFinished", onFinished)
    return animationGroup
end

function ErrorNotification:GetIconTexture()
    -- Error notification always uses the high-quality 2x icon asset.
    return DEFAULT_ERROR_ICON_TEXTURE
end

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
    frame:SetScript("OnDragStart", function(button)
        button:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(button)
        button:StopMovingOrSizing()
        -- Save position
        local point, _, _, x, y = button:GetPoint()
        db.errorNotificationPosition.point = point
        db.errorNotificationPosition.x = x
        db.errorNotificationPosition.y = y
    end)
    
    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "BACKGROUND")
    frame.icon:SetAllPoints()
    frame.icon:SetTexture(self:GetIconTexture())
    
    -- Badge background (red circle)
    frame.badgeBg = frame:CreateTexture(nil, "OVERLAY")
    frame.badgeBg:SetSize(24, 24)
    frame.badgeBg:SetPoint("BOTTOMRIGHT", 4, -4)
    frame.badgeBg:SetColorTexture(unpack(Theme.error))
    
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
    frame:SetScript("OnClick", function(buttonFrame, button)
        if button == "LeftButton" then
            MedaDebug:ShowMainPage("errors")
        elseif button == "RightButton" then
            -- Clear all errors
            if MedaDebug.ErrorHandler then
                MedaDebug.ErrorHandler:ClearErrors()
            end
        end
    end)
    
    -- Tooltip
    frame:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
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
    
    frame:SetScript("OnLeave", function(button)
        GameTooltip:Hide()
    end)
    
    self.frame = frame
    
    -- Apply initial settings
    self:ApplySettings()

    self.fadeIn = CreateFadeAnimation(frame, 0, settings.opacity, 0.3, "OUT", function()
        self.frame:SetAlpha(MedaDebug.db.options.errorNotification.opacity)
    end)
    self.fadeOut = CreateFadeAnimation(frame, settings.opacity, 0, 0.2, "IN", function()
        self.frame:Hide()
        self.frame:SetAlpha(MedaDebug.db.options.errorNotification.opacity)
    end)
    
    -- Check if we should show (in case errors happened before initialization)
    if MedaDebug.ErrorHandler then
        local count = MedaDebug.ErrorHandler:GetVisibleErrorCount()
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

    if self.fadeOut and self.fadeOut:IsPlaying() then
        self.fadeOut:Stop()
    end
    if self.fadeIn then
        self.fadeIn:Stop()
        local alpha = self.fadeIn:GetAnimations()
        alpha:SetToAlpha(MedaDebug.db.options.errorNotification.opacity)
        self.fadeIn:Play()
    end
end

function ErrorNotification:Hide()
    if not self.frame then return end
    if not self.frame:IsShown() then return end

    if self.fadeIn and self.fadeIn:IsPlaying() then
        self.fadeIn:Stop()
    end
    if self.fadeOut then
        self.fadeOut:Stop()
        local alpha = self.fadeOut:GetAnimations()
        alpha:SetFromAlpha(self.frame:GetAlpha())
        self.fadeOut:Play()
    end
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

    -- Keep icon synced with the currently configured minimap icon texture.
    self.frame.icon:SetTexture(self:GetIconTexture())
    
    -- Scale badge proportionally
    local badgeScale = settings.size / 64
    local baseBadgeSize = 24 * badgeScale
    self.frame.badgeBg:SetSize(baseBadgeSize, baseBadgeSize)
    self.frame.badge:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, 12 * badgeScale), "OUTLINE")
    
    -- Apply opacity
    self.frame:SetAlpha(settings.opacity)

    if self.fadeIn then
        local fadeInAlpha = self.fadeIn:GetAnimations()
        fadeInAlpha:SetToAlpha(settings.opacity)
    end
    if self.fadeOut then
        local fadeOutAlpha = self.fadeOut:GetAnimations()
        fadeOutAlpha:SetFromAlpha(settings.opacity)
    end
    
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

if MedaDebug.SettingsRegistry then
    MedaDebug.SettingsRegistry:RegisterModule("notifications", {
        title = "Notifications",
        description = "Error surfacing behavior for MedaDebug notifications and Blizzard error suppression.",
        sidebarGroup = "Settings",
        sidebarOrder = 20,
        entryType = "nav",
        pages = {
            { id = "notifications", label = "Notifications" },
        },
        pageHeights = {
            notifications = 320,
        },
        buildPage = function(_, parent)
            local options = MedaDebug.db and MedaDebug.db.options or {}
            local settings = options.errorNotification or {}
            local yOff = 0

            local header = MedaUI:CreateSectionHeader(parent, "Error Notifications", 470)
            header:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 38

            local enabledCheckbox = MedaUI:CreateCheckbox(parent, "Enable Error Notifications")
            enabledCheckbox:SetPoint("TOPLEFT", 12, yOff)
            enabledCheckbox:SetChecked(settings.enabled)
            enabledCheckbox.OnValueChanged = function(_, checked)
                settings.enabled = checked
                ErrorNotification:ApplySettings()
            end
            yOff = yOff - 28

            local tameCheckbox = MedaUI:CreateCheckbox(parent, "Hide Blizzard error popup (show slim error bar instead)")
            tameCheckbox:SetPoint("TOPLEFT", 12, yOff)
            tameCheckbox:SetChecked(options.tameBlizzardErrors)
            tameCheckbox.OnValueChanged = function(_, checked)
                options.tameBlizzardErrors = checked
                if checked then
                    MedaDebug:TameBlizzardErrors()
                end
            end
            yOff = yOff - 42

            local iconSizeSlider = MedaUI:CreateLabeledSlider(parent, "Icon Size", 220, 32, 128, 8)
            iconSizeSlider:SetPoint("TOPLEFT", 12, yOff)
            iconSizeSlider:SetValue(settings.size or 64)
            iconSizeSlider.OnValueChanged = function(_, value)
                settings.size = value
                ErrorNotification:ApplySettings()
            end
            yOff = yOff - 62

            local opacitySlider = MedaUI:CreateLabeledSlider(parent, "Opacity", 220, 0.3, 1.0, 0.1)
            opacitySlider:SetPoint("TOPLEFT", 12, yOff)
            opacitySlider:SetValue(settings.opacity or 1.0)
            opacitySlider.OnValueChanged = function(_, value)
                settings.opacity = value
                ErrorNotification:SetOpacity(value)
            end

            return 320
        end,
    })
end
