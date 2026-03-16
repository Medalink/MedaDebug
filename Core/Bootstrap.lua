--[[
    MedaDebug Bootstrap
    Shared addon identity, defaults, and DB helpers
]]

local addonName, MedaDebug = ...
_G.MedaDebug = MedaDebug

MedaDebug.version = "1.0.0"
MedaDebug.addonName = addonName

local DEFAULT_DB = {
    version = 1,
    options = {
        devMode = false,
        outputToChat = false,
        muteSounds = false,
        logMode = "session",
        maxLogEntries = 5000,
        restoreSessionData = true,
        autoScroll = true,
        maxMessages = 1000,
        timestampFormat = "time",
        fontSize = 12,
        enableTimerTracking = false,
        enableEventMonitor = false,
        enableSystemMonitor = false,
        enableDungeonObjectCapture = false,
        eventCategories = {
            addon = true,
            player = true,
            ui = true,
            unit = false,
            combat = false,
            spell = false,
            bag = false,
        },
        eventThrottle = 10,
        maxEvents = 500,
        consoleHistorySize = 100,
        consoleAutocomplete = true,
        consolePrettyPrint = true,
        consoleMaxTableDepth = 4,
        inspectorHighlightColor = { 1, 1, 0, 0.3 },
        inspectorShowHidden = false,
        inspectorRefreshInterval = 0.5,
        variableWatchInterval = 0.5,
        customActions = {},
        systemUpdateInterval = 1,
        memoryUpdateInterval = 10,
        showMemoryBreakdown = true,
        dungeonCaptureWindow = 5,
        dungeonCaptureMaxEntries = 200,
        dungeonCaptureTrackPartyAuras = true,
        dungeonCaptureIncludeCombatLog = true,
        errorNotification = {
            enabled = true,
            size = 64,
            opacity = 1.0,
        },
        tameBlizzardErrors = true,
    },
    suppressedSignatures = {},
    registeredAddons = {},
    minimapButton = { hide = false },
    bookmarks = {},
    consoleHistory = {},
    frameState = {
        isOpen = false,
        position = {
            point = "CENTER",
            relativeTo = nil,
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        },
        size = {
            width = 980,
            height = 620,
        },
        activeTab = "messages",
        filter = "all",
        navGroups = {
            streams = true,
            tools = true,
            runtime = true,
        },
    },
    errorNotificationPosition = {
        point = "TOPRIGHT",
        x = -100,
        y = -100,
    },
}

local DEFAULT_LOG = {
    session = {
        messages = {},
        errors = {},
        events = {},
        dungeonObjectCapture = {
            records = {},
            nextCaptureId = 0,
        },
        startTime = 0,
        reloadCount = 0,
    },
    persistent = {
        messages = {},
        errors = {},
    },
}

local function DeepCopy(source)
    if type(source) ~= "table" then
        return source
    end

    local copy = {}
    for key, value in pairs(source) do
        copy[key] = DeepCopy(value)
    end
    return copy
end

local function MergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = type(value) == "table" and DeepCopy(value) or value
        elseif type(value) == "table" and type(target[key]) == "table" then
            MergeDefaults(target[key], value)
        end
    end
end

function MedaDebug:GetDefaultDB()
    return DEFAULT_DB
end

function MedaDebug:GetDefaultLog()
    return DEFAULT_LOG
end

function MedaDebug:InitializeDB()
    if not MedaDebugDB then
        MedaDebugDB = DeepCopy(DEFAULT_DB)
    else
        MergeDefaults(MedaDebugDB, DEFAULT_DB)
    end

    if not MedaDebugLog then
        MedaDebugLog = DeepCopy(DEFAULT_LOG)
    else
        MergeDefaults(MedaDebugLog, DEFAULT_LOG)
    end

    self.db = MedaDebugDB
    self.log = MedaDebugLog
end

function MedaDebug:ResetToDefaults()
    wipe(MedaDebugDB)
    for key, value in pairs(DEFAULT_DB) do
        MedaDebugDB[key] = DeepCopy(value)
    end
    self.db = MedaDebugDB

    if MedaDebugLog then
        wipe(MedaDebugLog)
        for key, value in pairs(DEFAULT_LOG) do
            MedaDebugLog[key] = DeepCopy(value)
        end
        MedaDebugLog.session.startTime = time()
        self.log = MedaDebugLog
    end

    print("|cff00ff00[MedaDebug]|r Settings reset to defaults. Reload UI to apply all changes.")
end

function MedaDebug:Debug(message)
    if self.db and self.db.options.devMode then
        print("|cff888888[MedaDebug Debug]|r " .. tostring(message))
    end
end

function MedaDebug:LogInternal(addon, message, level)
    if self.API then
        self.API:Output(addon, message, level or "INFO")
    end
end
