--[[
    MedaDebug Core
    Main addon initialization and coordination
]]

local addonName, MedaDebug = ...
_G.MedaDebug = MedaDebug

-- Version info
MedaDebug.version = "1.0.0"
MedaDebug.addonName = addonName

-- Default database structure
local DEFAULT_DB = {
    version = 1,
    options = {
        -- General
        devMode = false,
        outputToChat = false,
        logMode = "session", -- "session", "persistent", "both"
        maxLogEntries = 5000,
        restoreSessionData = true,
        
        -- Display
        autoScroll = true,
        maxMessages = 1000,
        timestampFormat = "time", -- "time", "datetime", "elapsed"
        fontSize = 12,
        
        -- Real-time Monitoring Toggles (off by default to reduce overhead)
        enableTimerTracking = false,  -- Hooks C_Timer functions - high overhead
        enableEventMonitor = false,   -- Monitors WoW events
        enableSystemMonitor = false,  -- Polls FPS/memory/latency
        
        -- Event Monitor
        eventCategories = {
            addon = true,
            unit = false,
            combat = false,
            spell = false,
            bag = false,
            ui = false,
        },
        eventThrottle = 10,
        maxEvents = 500,
        
        -- Console
        consoleHistorySize = 100,
        consoleAutocomplete = true,
        consolePrettyPrint = true,
        consoleMaxTableDepth = 4,
        
        -- Inspector
        inspectorHighlightColor = {1, 1, 0, 0.3},
        inspectorShowHidden = false,
        inspectorRefreshInterval = 0.5,
        
        -- Quick Actions
        confirmReload = true,
        customActions = {},
        
        -- System Monitor
        systemUpdateInterval = 1,
        memoryUpdateInterval = 10,  -- Memory scan is expensive, do it less often
        showMemoryBreakdown = true,
        
        -- Error Notifications
        errorNotification = {
            enabled = true,
            size = 64,      -- 32-128 range
            opacity = 1.0,  -- 0.3-1.0 range
        },
    },
    registeredAddons = {},
    minimapButton = { hide = false },
    bookmarks = {},
    consoleHistory = {},
    
    -- Frame state persistence
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
            width = 700,
            height = 500,
        },
        activeTab = "messages",
        filter = "all",
    },
    
    -- Error notification position
    errorNotificationPosition = {
        point = "TOPRIGHT",
        x = -100,
        y = -100,
    },
}

-- Default log structure
local DEFAULT_LOG = {
    session = {
        messages = {},
        errors = {},
        events = {},
        startTime = 0,
        reloadCount = 0,
    },
    persistent = {
        messages = {},
        errors = {},
    },
}

-- Initialize database
local function InitializeDB()
    -- Main settings DB
    if not MedaDebugDB then
        MedaDebugDB = CopyTable(DEFAULT_DB)
    else
        -- Migrate: add missing keys from defaults
        for key, value in pairs(DEFAULT_DB) do
            if MedaDebugDB[key] == nil then
                MedaDebugDB[key] = CopyTable(value)
            elseif type(value) == "table" and type(MedaDebugDB[key]) == "table" then
                for subKey, subValue in pairs(value) do
                    if MedaDebugDB[key][subKey] == nil then
                        MedaDebugDB[key][subKey] = type(subValue) == "table" and CopyTable(subValue) or subValue
                    end
                end
            end
        end
    end
    
    -- Log DB
    if not MedaDebugLog then
        MedaDebugLog = CopyTable(DEFAULT_LOG)
    else
        for key, value in pairs(DEFAULT_LOG) do
            if MedaDebugLog[key] == nil then
                MedaDebugLog[key] = CopyTable(value)
            end
        end
    end
    
    MedaDebug.db = MedaDebugDB
    MedaDebug.log = MedaDebugLog
end

-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            InitializeDB()
            
            -- Track reload
            MedaDebug.log.session.reloadCount = (MedaDebug.log.session.reloadCount or 0) + 1
            if MedaDebug.log.session.startTime == 0 then
                MedaDebug.log.session.startTime = time()
            end
            
            -- Register slash commands
            SLASH_MEDADEBUG1 = "/mdebug"
            SLASH_MEDADEBUG2 = "/medadebug"
            SlashCmdList["MEDADEBUG"] = function(msg)
                MedaDebug:HandleSlashCommand(msg)
            end
        end
        
    elseif event == "PLAYER_LOGIN" then
        -- Initialize core modules (always enabled)
        if MedaDebug.ErrorHandler and MedaDebug.ErrorHandler.Initialize then
            MedaDebug.ErrorHandler:Initialize()
        end
        if MedaDebug.OutputManager and MedaDebug.OutputManager.Initialize then
            MedaDebug.OutputManager:Initialize()
        end
        
        -- Initialize optional real-time monitors (check enabled flags)
        if MedaDebug.db.options.enableSystemMonitor then
            if MedaDebug.SystemMonitor and MedaDebug.SystemMonitor.Initialize then
                MedaDebug.SystemMonitor:Initialize()
            end
        end
        if MedaDebug.db.options.enableEventMonitor then
            if MedaDebug.EventMonitor and MedaDebug.EventMonitor.Initialize then
                MedaDebug.EventMonitor:Initialize()
            end
        end
        if MedaDebug.db.options.enableTimerTracking then
            if MedaDebug.TimerTracker and MedaDebug.TimerTracker.Initialize then
                MedaDebug.TimerTracker:Initialize()
            end
        end
        
        -- Create UI (delayed slightly to ensure all modules ready)
        C_Timer.After(0.1, function()
            if MedaDebug.DebugFrame and MedaDebug.DebugFrame.Initialize then
                MedaDebug.DebugFrame:Initialize()
            end
            
            -- Restore frame state if dev mode or was open (slight delay to ensure frame is ready)
            C_Timer.After(0.05, function()
                if (MedaDebug.db.options.devMode or MedaDebug.db.frameState.isOpen) and MedaDebug.DebugFrame.frame then
                    MedaDebug.DebugFrame.frame:Show()
                end
            end)
            
            -- Log reload separator if this is a reload (not first login)
            if MedaDebug.log.session.reloadCount > 1 then
                MedaDebug:LogInternal("MedaDebug", "--- Reload #" .. MedaDebug.log.session.reloadCount .. " ---", "INFO")
            end
            
            -- Initialize minimap button
            MedaDebug:InitializeMinimapButton()
            
            -- Initialize error notification
            if MedaDebug.ErrorNotification and MedaDebug.ErrorNotification.Initialize then
                MedaDebug.ErrorNotification:Initialize()
                
                -- Connect error handler callbacks to notification
                if MedaDebug.ErrorHandler then
                    local originalOnNewError = MedaDebug.ErrorHandler.onNewError
                    MedaDebug.ErrorHandler.onNewError = function(entry)
                        -- Update notification
                        if MedaDebug.ErrorNotification then
                            local count = MedaDebug.ErrorHandler:GetErrorCount()
                            MedaDebug.ErrorNotification:UpdateCount(count)
                        end
                        -- Call original handler (DebugFrame)
                        if originalOnNewError then
                            originalOnNewError(entry)
                        end
                    end
                    
                    local originalOnErrorUpdated = MedaDebug.ErrorHandler.onErrorUpdated
                    MedaDebug.ErrorHandler.onErrorUpdated = function(entry)
                        -- Update notification count (occurrences changed)
                        if MedaDebug.ErrorNotification then
                            local count = MedaDebug.ErrorHandler:GetErrorCount()
                            MedaDebug.ErrorNotification:UpdateCount(count)
                        end
                        -- Call original handler
                        if originalOnErrorUpdated then
                            originalOnErrorUpdated(entry)
                        end
                    end
                    
                    MedaDebug.ErrorHandler.onErrorsCleared = function()
                        -- Hide notification
                        if MedaDebug.ErrorNotification then
                            MedaDebug.ErrorNotification:UpdateCount(0)
                        end
                        -- Update DebugFrame badge
                        if MedaDebug.DebugFrame and MedaDebug.DebugFrame.UpdateErrorBadge then
                            MedaDebug.DebugFrame:UpdateErrorBadge()
                        end
                        -- Refresh errors tab
                        if MedaDebug.ErrorsTab and MedaDebug.ErrorsTab.RefreshData then
                            MedaDebug.ErrorsTab:RefreshData()
                        end
                    end
                end
            end
        end)
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Additional initialization if needed
        
    elseif event == "PLAYER_LOGOUT" then
        -- Save frame state before logout/reload
        -- NOTE: isOpen is saved via HookScript on the frame (OnShow/OnHide)
        -- We don't save it here because frame:IsShown() returns false during reload
        if MedaDebug.DebugFrame and MedaDebug.DebugFrame.frame then
            local frame = MedaDebug.DebugFrame.frame
            
            -- Save position (only if frame exists and has a point)
            local point, relativeTo, relativePoint, x, y = frame:GetPoint()
            if point then
                MedaDebug.db.frameState.position = {
                    point = point,
                    relativeTo = relativeTo and relativeTo:GetName() or nil,
                    relativePoint = relativePoint,
                    x = x,
                    y = y,
                }
            end
            
            -- Save size
            MedaDebug.db.frameState.size = {
                width = frame:GetWidth(),
                height = frame:GetHeight(),
            }
        end
        
        -- Save current tab and filter
        if MedaDebug.DebugFrame then
            MedaDebug.db.frameState.activeTab = MedaDebug.DebugFrame.activeTab or "messages"
            MedaDebug.db.frameState.filter = MedaDebug.DebugFrame.currentFilter or "all"
        end
    end
end)

-- Slash command handler
function MedaDebug:HandleSlashCommand(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    
    if cmd == "" or cmd == "toggle" then
        -- Toggle main frame
        if self.DebugFrame then
            self.DebugFrame:Toggle()
        end
        
    elseif cmd == "settings" or cmd == "config" then
        if self.SettingsPanel then
            self.SettingsPanel:Toggle()
        end
        
    elseif cmd == "dev" then
        self.db.options.devMode = not self.db.options.devMode
        print("|cff00ff00[MedaDebug]|r Development mode: " .. (self.db.options.devMode and "ON" or "OFF"))
        
    elseif cmd == "msgs" or cmd == "messages" then
        if self.DebugFrame then
            self.DebugFrame:Show()
            self.DebugFrame:SetActiveTab("messages")
        end
        
    elseif cmd == "errors" then
        if self.DebugFrame then
            self.DebugFrame:Show()
            self.DebugFrame:SetActiveTab("errors")
        end
        
    elseif cmd == "events" then
        if self.DebugFrame then
            self.DebugFrame:Show()
            self.DebugFrame:SetActiveTab("events")
        end
        
    elseif cmd == "console" then
        if self.DebugFrame then
            self.DebugFrame:Show()
            self.DebugFrame:SetActiveTab("console")
        end
        
    elseif cmd == "inspect" then
        if self.DebugFrame then
            self.DebugFrame:Show()
            self.DebugFrame:SetActiveTab("inspector")
        end
        if self.FrameInspector then
            self.FrameInspector:StartInspectMode()
        end
        
    elseif cmd == "watch" then
        if rest and rest ~= "" then
            if self.VariableWatch then
                self.VariableWatch:AddWatch(rest)
            end
        end
        if self.DebugFrame then
            self.DebugFrame:Show()
            self.DebugFrame:SetActiveTab("watch")
        end
        
    elseif cmd == "timers" then
        if self.DebugFrame then
            self.DebugFrame:Show()
            self.DebugFrame:SetActiveTab("timers")
        end
        
    elseif cmd == "system" or cmd == "sys" then
        if self.DebugFrame then
            self.DebugFrame:Show()
            self.DebugFrame:SetActiveTab("system")
        end
        
    elseif cmd == "clear" then
        if rest == "all" then
            if self.OutputManager then self.OutputManager:ClearAll() end
        else
            if self.OutputManager then self.OutputManager:ClearCurrent() end
        end
        
    elseif cmd == "run" then
        if rest and rest ~= "" and self.Console then
            self.Console:Execute(rest)
        end
        
    elseif cmd == "var" then
        if rest and rest ~= "" and self.VariableWatch then
            self.VariableWatch:AddWatch(rest)
        end
        
    elseif cmd == "unvar" then
        if rest and rest ~= "" and self.VariableWatch then
            self.VariableWatch:RemoveWatch(rest)
        end
        
    elseif cmd == "snapshot" then
        if self.SVDiff then
            self.SVDiff:TakeSnapshot()
            print("|cff00ff00[MedaDebug]|r SavedVariables snapshot taken")
        end
        
    elseif cmd == "diff" then
        if self.SVDiff then
            self.SVDiff:ShowDiff()
        end
        
    elseif cmd == "export" then
        if self.OutputManager then
            self.OutputManager:ExportSession()
        end
        
    elseif cmd == "help" then
        print("|cff00ff00[MedaDebug]|r Commands:")
        print("  /mdebug - Toggle debug frame")
        print("  /mdebug settings - Open settings")
        print("  /mdebug dev - Toggle development mode")
        print("  /mdebug msgs|errors|events|console|inspect|watch|timers|system - Show tab")
        print("  /mdebug clear [all] - Clear messages")
        print("  /mdebug run <code> - Execute Lua code")
        print("  /mdebug var <path> - Watch variable")
        print("  /mdebug snapshot - Take SV snapshot")
        print("  /mdebug diff - Show SV diff")
        
    else
        print("|cff00ff00[MedaDebug]|r Unknown command. Type /mdebug help for commands.")
    end
end

-- Quick debug print (for internal use)
function MedaDebug:Debug(msg)
    if self.db and self.db.options.devMode then
        print("|cff888888[MedaDebug Debug]|r " .. tostring(msg))
    end
end

-- Log a message (internal shorthand - use LogInternal to avoid conflict with API:Log)
function MedaDebug:LogInternal(addon, message, level)
    if self.API then
        self.API:Output(addon, message, level or "INFO")
    end
end

-- ============================================================================
-- Minimap Button (using MedaUI)
-- ============================================================================

function MedaDebug:InitializeMinimapButton()
    local MedaUI = LibStub("MedaUI-1.0", true)
    if not MedaUI then return end
    
    -- Use custom debug icon
    self.minimapButton = MedaUI:CreateMinimapButton(
        "MedaDebug",
        "Interface\\AddOns\\MedaDebug\\Media\\debug",
        function() -- Left click - toggle debug window
            if self.DebugFrame then
                self.DebugFrame:Toggle()
            end
        end,
        function() -- Right click - toggle settings
            if self.SettingsPanel then
                self.SettingsPanel:Toggle()
            end
        end,
        self.db
    )
    
    -- Customize tooltip if button was created
    if self.minimapButton then
        local LDB = LibStub("LibDataBroker-1.1", true)
        if LDB then
            self.minimapButton.OnTooltipShow = function(tooltip)
                local Theme = MedaUI:GetTheme()
                tooltip:AddLine("MedaDebug", unpack(Theme.gold))
                tooltip:AddLine(" ")
                tooltip:AddLine("Left-click to toggle debug window", unpack(Theme.text))
                tooltip:AddLine("Right-click for settings", unpack(Theme.text))
                tooltip:AddLine("Drag to move", unpack(Theme.textDim))
                
                -- Show error count if any
                if self.ErrorHandler then
                    local errorCount = self.ErrorHandler:GetErrorCount()
                    if errorCount > 0 then
                        tooltip:AddLine(" ")
                        tooltip:AddLine(errorCount .. " error(s) captured", 1, 0.3, 0.3)
                    end
                end
            end
        end
    end
end

-- Show/hide minimap button
function MedaDebug:SetMinimapButtonShown(show)
    if not self.minimapButton then return end
    
    if show then
        self.minimapButton:ShowButton()
        self.db.minimapButton.hide = false
    else
        self.minimapButton:HideButton()
        self.db.minimapButton.hide = true
    end
end
