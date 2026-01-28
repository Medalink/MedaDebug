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
            return pattern.type, hint
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
    -- Connect to ErrorGrabber
    local grabber = _G.MedaDebugErrorGrabber
    if not grabber then
        print("|cffff0000[MedaDebug]|r Error: ErrorGrabber not found!")
        return
    end
    
    -- Mark as ready
    grabber.isReady = true
    
    -- Process existing errors
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
    if self.errorGroups[signature] then
        -- Increment existing
        local existing = self.errorGroups[signature]
        existing.occurrences.count = existing.occurrences.count + 1
        existing.occurrences.lastSeen = rawEntry.timestamp
        
        -- Notify UI of update
        if self.onErrorUpdated then
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
        
        -- Notify UI of new error
        if self.onNewError then
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

--- Clear all errors
function ErrorHandler:ClearErrors()
    wipe(self.errors)
    wipe(self.errorGroups)
    
    -- Clear grabber too
    local grabber = _G.MedaDebugErrorGrabber
    if grabber then
        grabber:ClearErrors()
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
    local lines = {
        "=== MedaDebug Error Report ===",
        "Type: " .. entry.summary.type,
        "Addon: " .. entry.summary.sourceAddon,
        "Time: " .. entry.raw.datetime .. " (occurred " .. entry.occurrences.count .. " times)",
        "",
        "Summary:",
        entry.summary.shortMessage,
        "",
        "Location:",
        "File: " .. entry.summary.sourceFile,
        "Line: " .. entry.summary.sourceLine,
        "Function: " .. entry.context.callingFunction,
        "",
        "Call Chain:",
    }
    
    for i, call in ipairs(entry.context.callChain) do
        lines[#lines + 1] = i .. ". " .. call
    end
    
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Hint: " .. entry.summary.hint
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Raw Error:"
    lines[#lines + 1] = entry.raw.message
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Full Stack:"
    lines[#lines + 1] = entry.raw.stack
    lines[#lines + 1] = "==="
    
    return table.concat(lines, "\n")
end
