--[[
    MedaDebug Error Grabber (Bootstrap)
    
    CRITICAL: This file MUST load first in the TOC.
    It has ZERO dependencies - no MedaUI, no other MedaDebug modules.
    This ensures we can capture errors from everything that loads after,
    including MedaDebug's own modules.
]]

-- Create global error grabber (UI will connect to this later)
local ErrorGrabber = {}
_G.MedaDebugErrorGrabber = ErrorGrabber

-- Initialize error storage (uses SavedVariables for persistence)
MedaDebugErrors = MedaDebugErrors or {
    errors = {},
    grabberVersion = 1,
    sessionStart = time(),
}

-- In-memory storage for current session
ErrorGrabber.errors = {}
ErrorGrabber.isReady = false           -- UI sets this when connected
ErrorGrabber.onNewError = nil          -- Callback for UI
ErrorGrabber.lastChatError = 0         -- Throttle chat output
ErrorGrabber.errorCount = 0

-- Capture the previous error handler for chaining
local previousHandler = geterrorhandler()

-- Our error handler
local function MedaDebugErrorHandler(errorMessage)
    -- Skip if BugGrabber is handling errors (we'll get them via callback)
    if ErrorGrabber.usingBugGrabber then
        -- Just chain to previous handler
        if previousHandler then
            pcall(previousHandler, errorMessage)
        end
        return
    end

    local timestamp = time()
    local stack = debugstack(3) -- Skip error handler frames

    -- Create error entry
    local entry = {
        message = tostring(errorMessage) or "Unknown error",
        stack = stack,
        timestamp = timestamp,
        datetime = date("%Y-%m-%d %H:%M:%S", timestamp),
        processed = false,
        id = ErrorGrabber.errorCount + 1,
    }

    ErrorGrabber.errorCount = ErrorGrabber.errorCount + 1

    -- Store in memory
    table.insert(ErrorGrabber.errors, entry)

    -- Store in SavedVariables for AI agent access
    table.insert(MedaDebugErrors.errors, {
        message = entry.message,
        stack = entry.stack,
        timestamp = entry.timestamp,
        datetime = entry.datetime,
    })

    -- Limit SavedVariables size (keep last 500 errors)
    while #MedaDebugErrors.errors > 500 do
        table.remove(MedaDebugErrors.errors, 1)
    end

    -- Notify UI if connected
    if ErrorGrabber.isReady and ErrorGrabber.onNewError then
        -- pcall to prevent errors in our error handler
        pcall(ErrorGrabber.onNewError, entry)
    else
        -- Fallback: throttled chat output if UI not ready
        if timestamp - ErrorGrabber.lastChatError > 2 then
            local shortMsg = tostring(errorMessage):sub(1, 100)
            print("|cffff4444[MedaDebug Error]|r " .. shortMsg)
            ErrorGrabber.lastChatError = timestamp
        end
    end

    -- Chain to previous handler (BugSack, etc.)
    if previousHandler then
        pcall(previousHandler, errorMessage)
    end
end

-- Install our error handler
seterrorhandler(MedaDebugErrorHandler)

-- Minimal slash command that works even if UI is broken
SLASH_MEDADEBUGERRORS1 = "/mderrors"
SlashCmdList["MEDADEBUGERRORS"] = function(msg)
    local errors = ErrorGrabber.errors
    local count = #errors
    
    print("|cff00ff00[MedaDebug]|r " .. count .. " errors captured this session")
    
    if count == 0 then
        print("  No errors to display.")
        return
    end
    
    -- Show last 5 errors
    local startIdx = math.max(1, count - 4)
    for i = startIdx, count do
        local e = errors[i]
        if e then
            local shortMsg = e.message:sub(1, 80)
            if #e.message > 80 then shortMsg = shortMsg .. "..." end
            print(string.format("  |cffff6666#%d|r %s - %s", i, e.datetime, shortMsg))
        end
    end
    
    if count > 5 then
        print("  ... and " .. (count - 5) .. " more. Use /mdebug errors to see all.")
    end
end

-- API for other addons to check if grabber is active
function ErrorGrabber:IsActive()
    return true
end

-- API to get error count
function ErrorGrabber:GetErrorCount()
    return #self.errors
end

-- API to get all errors
function ErrorGrabber:GetErrors()
    return self.errors
end

-- API to clear errors (UI might want this)
function ErrorGrabber:ClearErrors()
    wipe(self.errors)
    wipe(MedaDebugErrors.errors)
    self.errorCount = 0
end

-- BugGrabber integration - register as a listener if BugGrabber is present
local function RegisterWithBugGrabber()
    if not BugGrabber then return false end

    -- BugGrabber callback for new errors
    local function OnBugGrabberError(event, errorObject)
        if not errorObject then return end

        local timestamp = time()
        local entry = {
            message = errorObject.message or "Unknown error",
            stack = errorObject.stack or "",
            timestamp = timestamp,
            datetime = date("%Y-%m-%d %H:%M:%S", timestamp),
            processed = false,
            id = ErrorGrabber.errorCount + 1,
            fromBugGrabber = true,
        }

        ErrorGrabber.errorCount = ErrorGrabber.errorCount + 1

        -- Store in memory
        table.insert(ErrorGrabber.errors, entry)

        -- Store in SavedVariables
        table.insert(MedaDebugErrors.errors, {
            message = entry.message,
            stack = entry.stack,
            timestamp = entry.timestamp,
            datetime = entry.datetime,
        })

        -- Limit SavedVariables size
        while #MedaDebugErrors.errors > 500 do
            table.remove(MedaDebugErrors.errors, 1)
        end

        -- Notify UI if connected
        if ErrorGrabber.isReady and ErrorGrabber.onNewError then
            pcall(ErrorGrabber.onNewError, entry)
        end
    end

    -- Register with BugGrabber
    BugGrabber.RegisterCallback(ErrorGrabber, "BugGrabber_BugGrabbed", OnBugGrabberError)
    ErrorGrabber.usingBugGrabber = true
    return true
end

-- Try to register with BugGrabber now (if already loaded)
if BugGrabber then
    RegisterWithBugGrabber()
else
    -- Try again after ADDON_LOADED
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(self, event, addon)
        if addon == "BugGrabber" or addon == "!BugGrabber" then
            C_Timer.After(0, function()
                if RegisterWithBugGrabber() then
                    -- print("|cff00ff00[MedaDebug]|r Integrated with BugGrabber")
                end
            end)
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end

-- Debug: Print that grabber is loaded
-- print("|cff00ff00[MedaDebug]|r Error grabber initialized")
