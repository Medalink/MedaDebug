--[[
    MedaDebug Suite Settings
    Shared settings pages owned by the addon shell rather than a feature tool
]]

local _, MedaDebug = ...

local MedaUI = LibStub("MedaUI-2.0")
local SettingsRegistry = MedaDebug.SettingsRegistry

local function GetOptions()
    return MedaDebug.db and MedaDebug.db.options
end

local function BuildGeneralPage(parent)
    local options = GetOptions()
    local yOff = 0

    local header = MedaUI:CreateSectionHeader(parent, "General", 470)
    header:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 38

    local devModeCheckbox = MedaUI:CreateCheckbox(parent, "Development Mode (auto-show on login)")
    devModeCheckbox:SetPoint("TOPLEFT", 12, yOff)
    devModeCheckbox:SetChecked(options.devMode)
    devModeCheckbox.OnValueChanged = function(_, checked)
        options.devMode = checked
    end
    yOff = yOff - 28

    local restoreCheckbox = MedaUI:CreateCheckbox(parent, "Restore messages after /reload")
    restoreCheckbox:SetPoint("TOPLEFT", 12, yOff)
    restoreCheckbox:SetChecked(options.restoreSessionData)
    restoreCheckbox.OnValueChanged = function(_, checked)
        options.restoreSessionData = checked
    end
    yOff = yOff - 28

    local muteSoundsCheckbox = MedaUI:CreateCheckbox(parent, "Mute all sounds")
    muteSoundsCheckbox:SetPoint("TOPLEFT", 12, yOff)
    muteSoundsCheckbox:SetChecked(options.muteSounds)
    muteSoundsCheckbox.OnValueChanged = function(_, checked)
        options.muteSounds = checked
        MedaUI:SetSoundsEnabled(not checked)
    end
    yOff = yOff - 42

    local consoleHeader = MedaUI:CreateSectionHeader(parent, "Console", 470)
    consoleHeader:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 38

    local maxDepthSlider = MedaUI:CreateLabeledSlider(parent, "Max Table Depth", 220, 1, 8, 1)
    maxDepthSlider:SetPoint("TOPLEFT", 12, yOff)
    maxDepthSlider:SetValue(options.consoleMaxTableDepth or 4)
    maxDepthSlider.OnValueChanged = function(_, value)
        options.consoleMaxTableDepth = value
    end

    return 360
end

local function BuildDisplayPage(parent)
    local options = GetOptions()
    local yOff = 0

    local header = MedaUI:CreateSectionHeader(parent, "Output & Display", 470)
    header:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 38

    local chatCheckbox = MedaUI:CreateCheckbox(parent, "Output messages to chat")
    chatCheckbox:SetPoint("TOPLEFT", 12, yOff)
    chatCheckbox:SetChecked(options.outputToChat)
    chatCheckbox.OnValueChanged = function(_, checked)
        options.outputToChat = checked
    end
    yOff = yOff - 28

    local autoScrollCheckbox = MedaUI:CreateCheckbox(parent, "Auto-scroll to new messages")
    autoScrollCheckbox:SetPoint("TOPLEFT", 12, yOff)
    autoScrollCheckbox:SetChecked(options.autoScroll)
    autoScrollCheckbox.OnValueChanged = function(_, checked)
        options.autoScroll = checked
    end
    yOff = yOff - 42

    local logHeader = MedaUI:CreateSectionHeader(parent, "Logging", 470)
    logHeader:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 38

    local logModeDropdown = MedaUI:CreateLabeledDropdown(parent, "Log Mode", 220, {
        { value = "session", label = "Session Only" },
        { value = "persistent", label = "Persistent Only" },
        { value = "both", label = "Session + Persistent" },
    })
    logModeDropdown:SetPoint("TOPLEFT", 12, yOff)
    logModeDropdown:SetSelected(options.logMode or "session")
    logModeDropdown.OnValueChanged = function(_, value)
        options.logMode = value
    end
    yOff = yOff - 62

    local maxLogSlider = MedaUI:CreateLabeledSlider(parent, "Max Log Entries", 220, 500, 10000, 100)
    maxLogSlider:SetPoint("TOPLEFT", 12, yOff)
    maxLogSlider:SetValue(options.maxLogEntries or 5000)
    maxLogSlider.OnValueChanged = function(_, value)
        options.maxLogEntries = value
    end
    yOff = yOff - 62

    local maxMsgsSlider = MedaUI:CreateLabeledSlider(parent, "Max Messages", 220, 100, 5000, 100)
    maxMsgsSlider:SetPoint("TOPLEFT", 12, yOff)
    maxMsgsSlider:SetValue(options.maxMessages or 1000)
    maxMsgsSlider.OnValueChanged = function(_, value)
        options.maxMessages = value
        if MedaDebug.OutputManager then
            MedaDebug.OutputManager:SetMaxMessages(value)
        end
    end
    yOff = yOff - 62

    local fontSlider = MedaUI:CreateLabeledSlider(parent, "Font Size", 220, 8, 16, 1)
    fontSlider:SetPoint("TOPLEFT", 12, yOff)
    fontSlider:SetValue(options.fontSize or 12)
    fontSlider.OnValueChanged = function(_, value)
        options.fontSize = value
    end
    yOff = yOff - 62

    local timestampDropdown = MedaUI:CreateLabeledDropdown(parent, "Timestamp Format", 220, {
        { value = "time", label = "Time" },
        { value = "datetime", label = "Date + Time" },
        { value = "elapsed", label = "Elapsed" },
    })
    timestampDropdown:SetPoint("TOPLEFT", 12, yOff)
    timestampDropdown:SetSelected(options.timestampFormat or "time")
    timestampDropdown.OnValueChanged = function(_, value)
        options.timestampFormat = value
    end

    return 560
end

local function BuildDangerPage(parent)
    local yOff = 0

    local header = MedaUI:CreateSectionHeader(parent, "Danger Zone", 470)
    header:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 38

    local dangerLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dangerLabel:SetPoint("TOPLEFT", 12, yOff)
    dangerLabel:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
    dangerLabel:SetJustifyH("LEFT")
    dangerLabel:SetWordWrap(true)
    dangerLabel:SetText("Reset all settings and clear saved data. The UI will reload immediately after confirmation.")
    dangerLabel:SetTextColor(unpack(MedaUI.Theme.error))
    yOff = yOff - dangerLabel:GetStringHeight() - 20

    local resetBtn = MedaUI:CreateButton(parent, "Reset to Defaults", 160, 30)
    resetBtn:SetPoint("TOPLEFT", 12, yOff)
    resetBtn:SetScript("OnClick", function()
        StaticPopupDialogs["MEDADEBUG_RESET_CONFIRM"] = {
            text = "Are you sure you want to reset MedaDebug to defaults?\n\nThis will clear all settings and message history.\n\nThe UI will reload automatically.",
            button1 = "Reset",
            button2 = "Cancel",
            OnAccept = function()
                MedaDebug:ResetToDefaults()
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("MEDADEBUG_RESET_CONFIRM")
    end)

    return 220
end

SettingsRegistry:RegisterModule("suite", {
    title = "General",
    description = "Shared MedaDebug behavior, output, and console display settings.",
    sidebarGroup = "Settings",
    sidebarOrder = 10,
    entryType = "nav",
    pages = {
        { id = "general", label = "General" },
        { id = "display", label = "Output & Display" },
    },
    pageHeights = {
        general = 360,
        display = 560,
    },
    buildPage = function(pageName, parent)
        if pageName == "display" then
            return BuildDisplayPage(parent)
        end
        return BuildGeneralPage(parent)
    end,
})

SettingsRegistry:RegisterModule("danger", {
    title = "Danger Zone",
    description = "Destructive reset actions for MedaDebug state and saved data.",
    sidebarGroup = "Settings",
    sidebarOrder = 100,
    entryType = "nav",
    pages = {
        { id = "danger", label = "Danger Zone" },
    },
    pageHeights = {
        danger = 220,
    },
    buildPage = function(_, parent)
        return BuildDangerPage(parent)
    end,
})
