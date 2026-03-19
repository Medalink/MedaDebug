--[[
    MedaDebug Error Handler
    Connects to ErrorGrabber and provides smart error parsing
]]

local addonName, MedaDebug = ...

local ErrorHandler = {}
MedaDebug.ErrorHandler = ErrorHandler

-- Processed errors
ErrorHandler.errors = {}
ErrorHandler.errorGroups = {} -- Grouped by signature

-- Error classification patterns
local ERROR_PATTERNS = {
    {type = "NIL_ACCESS", pattern = "attempt to index.-%(a nil value%)", hint = "Variable is nil - check initialization order or typos"},
    {type = "NIL_ACCESS", pattern = "attempt to index field '([^']+)'.-nil", hint = "Field '%s' is nil - check if parent object exists"},
    {type = "NIL_CALL", pattern = "attempt to call.-%(a nil value%)", hint = "Function doesn't exist - check spelling or load order"},
    {type = "NIL_CALL", pattern = "attempt to call method '([^']+)'.-nil", hint = "Method '%s' doesn't exist on this object"},
    {type = "TYPE_MISMATCH", pattern = "attempt to perform arithmetic on", hint = "Wrong variable type - expected number"},
    {type = "CONCAT_NIL", pattern = "attempt to concatenate.-nil", hint = "String concatenation with nil value"},
    {type = "INVALID_ARGUMENT", pattern = "bad argument #(%d+)", hint = "Wrong argument type to function (arg #%s)"},
    {type = "SECURE_HOOK", pattern = "Cannot call.-in combat", hint = "Protected function called in combat - queue for after combat"},
    {type = "TAINT", pattern = "Action.*was blocked", hint = "Tainted code execution - check for secure frame modifications"},
    {type = "LUA_WARNING", pattern = "^LUA_WARNING:", hint = "Client warning (usually Blizzard UI) - typically harmless and safe to suppress"},

    -- Secrets-related errors (WoW 12.0.0+)
    -- Hints updated with empirical findings from Midnight 12.0 testing
    {type = "SECRET_ARITHMETIC", pattern = "attempt to perform arithmetic on.-secret",
     hint = "Cannot do math on secret values. Use issecretvalue() or pcall to detect first. Note: UnitPowerMax(unit,type,true) may still be readable even when UnitPower is secret"},
    {type = "SECRET_COMPARE", pattern = "attempt to compare.-secret",
     hint = "Cannot compare secret values. WARNING: tostring(secret) returns a secret STRING that taints everything it touches via concat. Use pcall + forced comparison to verify strings are clean before embedding in messages"},
    {type = "SECRET_BOOLEAN", pattern = "attempt to.-boolean.-secret",
     hint = "Cannot branch on tainted boolean. Comparisons on secret numbers may return tainted booleans that crash if/and/or. Wrap in pcall and use issecretvalue() before conditional logic"},
    {type = "SECRET_LENGTH", pattern = "attempt to get length of.-secret",
     hint = "Cannot use # on secret values - the length itself would reveal information"},
    {type = "SECRET_INDEX", pattern = "attempt to index.-secret",
     hint = "Cannot index into secret values - if you need table access, check canaccesstable() first"},
    {type = "SECRET_KEY", pattern = "secret.-as table key",
     hint = "Cannot use secret as table key - store by a non-secret identifier (e.g., unit token or GUID) instead"},
    {type = "SECRET_CALL", pattern = "attempt to call.-secret",
     hint = "Secret value is not callable - it's data, not a function"},
    {type = "SECRET_ACCESS", pattern = "cannot access secret",
     hint = "Tainted code cannot access this secret - check canaccessvalue() or use in untainted context"},
    {type = "SECRET_STRING", pattern = "secret string value",
     hint = "This is a secret STRING (often from tostring(secretNumber)). Taint propagates through concatenation silently - the string looks normal but crashes on compare/find/match/sub. Verify with pcall comparison before use"},
}

-- Addon detection patterns
local function DetectAddon(stack)
    -- Try to find addon name from stack
    local addon = stack:match("Interface/AddOns/([^/]+)/")
    if addon then return addon end
    
    addon = stack:match("AddOns\\([^\\]+)\\")
    if addon then return addon end
    
    return "Unknown"
end

-- Parse stack trace into structured frames
local function ParseStack(stack)
    local frames = {}
    for line in stack:gmatch("[^\n]+") do
        local file, lineNum, func = line:match("([^:]+):(%d+): in function [`']?([^'`]+)")
        if file and lineNum then
            local addon = file:match("AddOns/([^/]+)/") or file:match("AddOns\\([^\\]+)\\")
            local isAddonCode = addon ~= nil
            
            frames[#frames + 1] = {
                file = file,
                line = tonumber(lineNum),
                func = func or "?",
                isAddonCode = isAddonCode,
                addon = addon,
                raw = line,
            }
        end
    end
    return frames
end

-- Classify error type
local function ClassifyError(message)
    for _, pattern in ipairs(ERROR_PATTERNS) do
        local match1, match2 = message:match(pattern.pattern)
        if match1 then
            local hint = pattern.hint
            if match1 and hint:find("%%s") then
                hint = hint:format(match1)
            end

            -- Add link to secrets tab for SECRET_* errors
            local errorType = pattern.type
            if errorType:match("^SECRET_") and MedaDebug.SecretsExplorer then
                hint = hint .. " | Use /mdebug secrets to explore what's secret"
            end

            return errorType, hint
        end
    end
    return "UNKNOWN", "Unknown error type - inspect stack trace"
end

-- Create error signature for grouping
local function CreateSignature(entry)
    -- Signature based on file + line + error type
    local frame = entry.stackFrames and entry.stackFrames[1]
    if frame then
        return string.format("%s:%d:%s", frame.file or "", frame.line or 0, entry.summary.type)
    end
    return entry.raw.message:sub(1, 50)
end

function ErrorHandler:Initialize()
    -- Restore saved errors from session (before connecting to grabber)
    if MedaDebug.db and MedaDebug.db.options.restoreSessionData then
        if MedaDebug.log and MedaDebug.log.session and MedaDebug.log.session.errors then
            for _, savedError in ipairs(MedaDebug.log.session.errors) do
                self:RestoreSavedError(savedError)
            end
        end
    end
    
    -- Connect to ErrorGrabber
    local grabber = _G.MedaDebugErrorGrabber
    if not grabber then
        print("|cffff0000[MedaDebug]|r Error: ErrorGrabber not found!")
        return
    end
    
    -- Mark as ready
    grabber.isReady = true
    
    -- Process existing errors (from before UI loaded)
    for _, entry in ipairs(grabber.errors) do
        if not entry.processed then
            self:ProcessError(entry)
            entry.processed = true
        end
    end
    
    -- Hook for new errors
    grabber.onNewError = function(entry)
        self:ProcessError(entry)
        entry.processed = true
    end
end

--- Restore a saved error from session log
--- @param savedError table Saved error entry from log
function ErrorHandler:RestoreSavedError(savedError)
    if not savedError.error then return end
    
    local err = savedError.error
    local rawStack = err.rawStack or ""
    local stackFrames = ParseStack(rawStack)
    
    -- Reconstruct the processed error format
    local entry = {
        summary = {
            type = err.type or "UNKNOWN",
            shortMessage = err.shortMessage or err.rawMessage or "Unknown error",
            sourceAddon = err.addon or "Unknown",
            sourceFile = err.file or "unknown",
            sourceLine = err.line or 0,
            hint = err.hint or "No hint available",
        },
        context = {
            callingFunction = "?",
            callChain = err.callChain or {},
        },
        stackFrames = stackFrames,
        raw = {
            message = err.rawMessage or "",
            stack = rawStack,
            timestamp = savedError.timestamp or time(),
            datetime = savedError.datetime or date("%H:%M:%S"),
        },
        occurrences = {
            count = 1,
            firstSeen = savedError.timestamp or time(),
            lastSeen = savedError.timestamp or time(),
        },
        id = #self.errors + 1,
        restored = true, -- Mark as restored
    }

    entry.signature = CreateSignature(entry)
    entry.suppressed = self:IsErrorSuppressed(entry)

    local existing = self.errorGroups[entry.signature]
    if existing then
        existing.occurrences.count = existing.occurrences.count + 1
        existing.occurrences.lastSeen = math.max(existing.occurrences.lastSeen or 0, entry.raw.timestamp or 0)
        existing.occurrences.firstSeen = math.min(existing.occurrences.firstSeen or entry.raw.timestamp or 0, entry.raw.timestamp or 0)
        existing.restored = existing.restored and entry.restored
        existing.suppressed = self:IsErrorSuppressed(existing)
        return existing
    end

    self.errors[#self.errors + 1] = entry
    self.errorGroups[entry.signature] = entry
    return entry
end

--- Process a raw error into structured format
--- @param rawEntry table Raw error from ErrorGrabber
function ErrorHandler:ProcessError(rawEntry)
    local message = rawEntry.message or ""
    local stack = rawEntry.stack or ""
    
    -- Classify error
    local errorType, hint = ClassifyError(message)
    
    -- Parse stack
    local stackFrames = ParseStack(stack)
    
    -- Detect source addon
    local sourceAddon = DetectAddon(stack)
    local sourceFile = stackFrames[1] and stackFrames[1].file:match("([^/\\]+%.lua)") or "unknown"
    local sourceLine = stackFrames[1] and stackFrames[1].line or 0
    
    -- Create processed entry
    local entry = {
        -- Summary
        summary = {
            type = errorType,
            shortMessage = message:sub(1, 100),
            sourceAddon = sourceAddon,
            sourceFile = sourceFile,
            sourceLine = sourceLine,
            hint = hint,
        },
        
        -- Context
        context = {
            callingFunction = stackFrames[1] and stackFrames[1].func or "?",
            callChain = {},
        },
        
        -- Stack frames
        stackFrames = stackFrames,
        
        -- Raw data (preserved)
        raw = {
            message = message,
            stack = stack,
            timestamp = rawEntry.timestamp,
            datetime = rawEntry.datetime,
        },
        
        -- Occurrence tracking
        occurrences = {
            count = 1,
            firstSeen = rawEntry.timestamp,
            lastSeen = rawEntry.timestamp,
        },
        
        -- Unique ID
        id = #self.errors + 1,
    }
    
    -- Build call chain
    for i, frame in ipairs(stackFrames) do
        if i <= 5 then -- Limit to 5 frames
            local desc = frame.func .. "()"
            if frame.addon then
                desc = frame.addon .. "/" .. (frame.file:match("([^/\\]+)$") or frame.file) .. ":" .. frame.line
            end
            entry.context.callChain[#entry.context.callChain + 1] = desc
        end
    end
    
    -- Check for duplicate (group)
    local signature = CreateSignature(entry)
    entry.signature = signature
    
    -- Check if this error signature is suppressed
    local isSuppressed = MedaDebug.db and MedaDebug.db.suppressedSignatures
        and MedaDebug.db.suppressedSignatures[signature] or false
    entry.suppressed = isSuppressed
    
    if self.errorGroups[signature] then
        -- Increment existing
        local existing = self.errorGroups[signature]
        existing.occurrences.count = existing.occurrences.count + 1
        existing.occurrences.lastSeen = rawEntry.timestamp
        
        -- Only notify UI if not suppressed
        if not existing.suppressed and self.onErrorUpdated then
            self.onErrorUpdated(existing)
        end
    else
        -- New error
        self.errors[#self.errors + 1] = entry
        self.errorGroups[signature] = entry
        
        -- Save to log
        if MedaDebug.log and MedaDebug.log.session then
            MedaDebug.log.session.errors[#MedaDebug.log.session.errors + 1] = {
                type = "error",
                timestamp = rawEntry.timestamp,
                datetime = rawEntry.datetime,
                error = {
                    type = entry.summary.type,
                    addon = entry.summary.sourceAddon,
                    file = entry.summary.sourceFile,
                    line = entry.summary.sourceLine,
                    shortMessage = entry.summary.shortMessage,
                    hint = entry.summary.hint,
                    callChain = entry.context.callChain,
                    rawMessage = message,
                    rawStack = stack,
                },
            }
        end
        
        -- Output to chat if enabled (skip for suppressed)
        if not isSuppressed and MedaDebug.db and MedaDebug.db.options.outputToChat then
            print(string.format("|cffff4444[Error]|r |cff88bbff[%s]|r %s in %s:%d", 
                entry.summary.sourceAddon,
                entry.summary.type,
                entry.summary.sourceFile,
                entry.summary.sourceLine))
            print("  └─ " .. entry.summary.hint)
        end
        
        -- Only notify UI if not suppressed (skip notification icon + badge)
        if not isSuppressed and self.onNewError then
            self.onNewError(entry)
        end
    end
    
    return entry
end

--- Get all processed errors
--- @return table Array of processed errors
function ErrorHandler:GetErrors()
    return self.errors
end

--- Get unique source addons from captured errors.
--- @return table
function ErrorHandler:GetAddonsFromErrors()
    local addonSet = {}
    for _, err in ipairs(self.errors) do
        local summary = err and err.summary
        local addon = summary and summary.sourceAddon
        if addon and addon ~= "" then
            addonSet[addon] = true
        end
    end

    local addons = {}
    for addon in pairs(addonSet) do
        addons[#addons + 1] = addon
    end
    table.sort(addons)
    return addons
end

--- Get error count
--- @return number Number of unique errors
function ErrorHandler:GetErrorCount()
    return #self.errors
end

--- Get total occurrence count
--- @return number Total error occurrences
function ErrorHandler:GetTotalOccurrences()
    local total = 0
    for _, err in ipairs(self.errors) do
        total = total + err.occurrences.count
    end
    return total
end

--- Get count of non-suppressed errors (used by notification icon and badge)
--- @return number
function ErrorHandler:GetVisibleErrorCount()
    local count = 0
    for _, err in ipairs(self.errors) do
        if not err.suppressed then
            count = count + 1
        end
    end
    return count
end

--- Get count of suppressed errors
--- @return number
function ErrorHandler:GetSuppressedErrorCount()
    local count = 0
    for _, err in ipairs(self.errors) do
        if err.suppressed then
            count = count + 1
        end
    end
    return count
end

--- Check if an error entry is suppressed
--- @param entry table Error entry
--- @return boolean
function ErrorHandler:IsErrorSuppressed(entry)
    if not entry or not entry.signature then return false end
    return MedaDebug.db and MedaDebug.db.suppressedSignatures
        and MedaDebug.db.suppressedSignatures[entry.signature] or false
end

--- Suppress an error by its signature
--- @param entry table Error entry to suppress
function ErrorHandler:SuppressError(entry)
    if not entry or not entry.signature then return end
    if not MedaDebug.db then return end

    MedaDebug.db.suppressedSignatures[entry.signature] = true
    entry.suppressed = true

    -- Also suppress any grouped duplicates with the same signature
    for _, err in ipairs(self.errors) do
        if err.signature == entry.signature then
            err.suppressed = true
        end
    end

    if self.onSuppressChanged then
        self.onSuppressChanged()
    end
end

--- Unsuppress an error by its signature
--- @param entry table Error entry to unsuppress
function ErrorHandler:UnsuppressError(entry)
    if not entry or not entry.signature then return end
    if not MedaDebug.db then return end

    MedaDebug.db.suppressedSignatures[entry.signature] = nil
    entry.suppressed = false

    for _, err in ipairs(self.errors) do
        if err.signature == entry.signature then
            err.suppressed = false
        end
    end

    if self.onSuppressChanged then
        self.onSuppressChanged()
    end
end

--- Clear all errors
function ErrorHandler:ClearErrors()
    wipe(self.errors)
    wipe(self.errorGroups)
    
    -- Clear grabber too
    local grabber = _G.MedaDebugErrorGrabber
    if grabber then
        grabber:ClearErrors()
    end
    
    -- Clear session log errors too
    if MedaDebug.log and MedaDebug.log.session and MedaDebug.log.session.errors then
        wipe(MedaDebug.log.session.errors)
    end
    
    -- Notify UI
    if self.onErrorsCleared then
        self.onErrorsCleared()
    end
end

--- Format error for copying
--- @param entry table Error entry
--- @return string Formatted error text
function ErrorHandler:FormatForCopy(entry)
    -- Ensure all required fields exist
    local summary = entry.summary or {}
    local raw = entry.raw or {}
    local occurrences = entry.occurrences or {}
    local context = entry.context or {}
    
    local lines = {
        "=== MedaDebug Error Report ===",
        "Type: " .. (summary.type or "UNKNOWN"),
        "Addon: " .. (summary.sourceAddon or "Unknown"),
        "Time: " .. (raw.datetime or "?") .. " (occurred " .. (occurrences.count or 1) .. " times)",
        "",
        "Summary:",
        summary.shortMessage or raw.message or "No message",
        "",
        "Location:",
        "File: " .. (summary.sourceFile or "?"),
        "Line: " .. tostring(summary.sourceLine or 0),
        "Function: " .. (context.callingFunction or "?"),
        "",
        "Call Chain:",
    }
    
    local callChain = context.callChain or {}
    if #callChain > 0 then
        for i, call in ipairs(callChain) do
            lines[#lines + 1] = i .. ". " .. call
        end
    else
        lines[#lines + 1] = "(no call chain available)"
    end
    
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Hint: " .. (summary.hint or "No hint available")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Raw Error:"
    lines[#lines + 1] = raw.message or "(no message)"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Full Stack:"
    lines[#lines + 1] = raw.stack or "(no stack trace)"
    lines[#lines + 1] = "==="

    return table.concat(lines, "\n")
end

if MedaDebug.RuntimeRegistry then
    MedaDebug.RuntimeRegistry:RegisterModule("ErrorHandler", {
        order = 10,
    })
end
