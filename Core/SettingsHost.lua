local addonName, MedaDebug = ...

local MedaUI = LibStub("MedaUI-2.0")
local tinsert = table.insert
local SettingsRegistry = MedaDebug.SettingsRegistry

local SettingsHost = {}
MedaDebug.SettingsHost = SettingsHost

local settingsHost

local PANEL_WIDTH = 980
local PANEL_HEIGHT = 760
local SIDEBAR_WIDTH = 260

local function SaveState()
    if settingsHost and MedaDebug.db then
        MedaDebug.db.settingsPanelState = settingsHost:GetState()
    end
end

local function BuildModuleConfig(moduleDef)
    local config = {}

    for key, value in pairs(moduleDef) do
        if key ~= "id" then
            config[key] = value
        end
    end

    return config
end

local function BuildHost()
    if settingsHost then
        return settingsHost
    end

    settingsHost = MedaUI:CreateOptionsHost({
        name = "MedaDebugSettings",
        width = PANEL_WIDTH,
        height = PANEL_HEIGHT,
        sidebarWidth = SIDEBAR_WIDTH,
        title = "MedaDebug",
        subtitle = "D E V E L O P E R   S E T T I N G S",
        minWidth = SIDEBAR_WIDTH + 360,
        minHeight = 480,
        watermarkTexture = "Interface\\AddOns\\MedaDebug\\Media\\debug",
        groupOrder = { "Settings" },
    })

    if SettingsRegistry then
        for _, moduleDef in ipairs(SettingsRegistry:GetModules()) do
            settingsHost:RegisterModule(moduleDef.id, BuildModuleConfig(moduleDef))
        end
    end

    settingsHost:SetFooterButtons({
        {
            text = "Close",
            width = 108,
            align = "right",
            onClick = function()
                settingsHost:Hide()
            end,
        },
    })

    local frame = settingsHost:GetFrame()
    if MedaDebug.db and MedaDebug.db.settingsPanelState then
        settingsHost:RestoreState(MedaDebug.db.settingsPanelState)
    end
    frame.OnMove = SaveState
    frame.OnResize = SaveState

    tinsert(UISpecialFrames, "MedaDebugSettings")
    settingsHost:RebuildSidebar()

    if SettingsRegistry then
        local defaultModuleId, defaultPageId = SettingsRegistry:GetDefaultSelection()
        if defaultModuleId and defaultPageId then
            settingsHost:SelectModule(defaultModuleId, defaultPageId)
        end
    end

    return settingsHost
end

function SettingsHost:Toggle()
    local host = BuildHost()
    host:Toggle()
    if host:IsShown() then
        if host.ScheduleLayoutRefresh then
            host:ScheduleLayoutRefresh()
        end
        SaveState()
    end
end

function SettingsHost:IsShown()
    return settingsHost and settingsHost:IsShown() or false
end

function MedaDebug:ToggleSettings()
    SettingsHost:Toggle()
end
