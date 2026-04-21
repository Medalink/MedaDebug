local MedaDebug = {
    log = {
        session = {},
    },
    RuntimeRegistry = {
        RegisterModule = function() end,
    },
    SettingsRegistry = {
        RegisterModule = function() end,
    },
}

function MedaDebug:LogInternal() end

local currentInstanceType = "party"

function LibStub()
    return {
        Theme = {
            textDim = {1, 1, 1},
            warning = {1, 0.8, 0},
        },
        CreateSectionHeader = function() return {} end,
        CreateLabeledSlider = function()
            return {
                SetPoint = function() end,
                SetValue = function() end,
            }
        end,
        CreateCheckbox = function()
            return {
                SetPoint = function() end,
                SetChecked = function() end,
            }
        end,
    }
end

function CreateFrame()
    return {
        RegisterEvent = function() end,
        SetScript = function() end,
        UnregisterAllEvents = function() end,
    }
end

Enum = {
    TooltipDataType = {
        Object = 4,
        Unit = 2,
        Corpse = 3,
    },
}

C_Map = {
    GetBestMapForUnit = function() return 2255 end,
    GetPlayerMapPosition = function()
        return {x = 0.25, y = 0.75}
    end,
}

function GetInstanceInfo()
    return "Test Instance", currentInstanceType, 23, "Normal", 5, nil, false, 12345, 5
end

function GetTime()
    return 10
end

function date()
    return "12:00:00"
end

function strsplit(separator, text)
    local parts = {}
    local pattern = "([^" .. separator .. "]+)"
    for value in string.gmatch(text or "", pattern) do
        parts[#parts + 1] = value
    end
    return unpack(parts)
end

local function assertTruthy(value, message)
    if not value then
        error(message, 2)
    end
end

local chunk = assert(loadfile("Core\\DungeonObjectCapture.lua"))
chunk("MedaDebug", MedaDebug)

local capture = MedaDebug.DungeonObjectCapture
local tooltipData = {
    type = Enum.TooltipDataType.Object,
    name = "Ritual Focus",
    guid = "GameObject-0-0-0-0-98765-0000000000",
    lines = {
        {leftText = "Ritual Focus"},
    },
}

currentInstanceType = "party"
assertTruthy(capture:BuildTooltipContext("test", tooltipData), "party instances should be capture-eligible")

currentInstanceType = "scenario"
assertTruthy(capture:BuildTooltipContext("test", tooltipData), "scenario instances should be capture-eligible for 12.0.5 Ritual Sites")
