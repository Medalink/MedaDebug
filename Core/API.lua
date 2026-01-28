--[[
    MedaDebug Public API
    Interface for external addons to send debug messages
]]

local addonName, MedaDebug = ...

local API = {}
MedaDebug.API = API

-- Registered addons
API.registeredAddons = {}

-- Default colors for log levels
local LEVEL_COLORS = {
    DEBUG = {0.5, 0.5, 0.5},
    INFO = {0.9, 0.9, 0.9},
    WARN = {1, 0.8, 0},
    ERROR = {1, 0.3, 0.3},
}

--- Register an addon for debug output
--- @param addonName string The addon name
--- @param config table|nil Optional configuration {color, prefix}
function MedaDebug:RegisterAddon(addonName, config)
    config = config or {}
    API.registeredAddons[addonName] = {
        name = addonName,
        color = config.color or {0.6, 0.8, 1},
        prefix = config.prefix or ("[" .. addonName .. "]"),
        enabled = true,
    }
    
    -- Save to DB for persistence
    if self.db then
        self.db.registeredAddons[addonName] = API.registeredAddons[addonName]
    end
end

--- Check if an addon is registered
--- @param addonName string The addon name
--- @return boolean Whether the addon is registered
function MedaDebug:IsAddonRegistered(addonName)
    return API.registeredAddons[addonName] ~= nil
end

--- Get registered addon info
--- @param addonName string The addon name
--- @return table|nil Addon info
function MedaDebug:GetAddonInfo(addonName)
    return API.registeredAddons[addonName]
end

--- Get all registered addons
--- @return table Array of addon names
function MedaDebug:GetRegisteredAddons()
    local addons = {}
    for name in pairs(API.registeredAddons) do
        addons[#addons + 1] = name
    end
    table.sort(addons)
    return addons
end

-- Internal output function
function API:Output(addonName, message, level)
    level = level or "INFO"
    
    -- Create entry
    local entry = {
        timestamp = time(),
        datetime = date("%H:%M:%S"),
        addon = addonName,
        level = level,
        message = tostring(message),
        levelColor = LEVEL_COLORS[level] or LEVEL_COLORS.INFO,
    }
    
    -- Get addon color
    local addonInfo = self.registeredAddons[addonName]
    if addonInfo then
        entry.addonColor = addonInfo.color
    else
        entry.addonColor = {0.6, 0.8, 1}
    end
    
    -- Send to output manager
    if MedaDebug.OutputManager then
        MedaDebug.OutputManager:HandleMessage(entry)
    end
    
    return entry
end

--- Print a standard message
--- @param addonName string The source addon name
--- @param message string The message to print
function MedaDebug:Print(addonName, message)
    return API:Output(addonName, message, "INFO")
end

--- Print a debug message
--- @param addonName string The source addon name
--- @param message string The message to print
function MedaDebug:DebugMsg(addonName, message)
    return API:Output(addonName, message, "DEBUG")
end

--- Print a warning message
--- @param addonName string The source addon name
--- @param message string The message to print
function MedaDebug:Warn(addonName, message)
    return API:Output(addonName, message, "WARN")
end

--- Print an error message
--- @param addonName string The source addon name
--- @param message string The message to print
function MedaDebug:Error(addonName, message)
    return API:Output(addonName, message, "ERROR")
end

--- Pretty-print a table
--- @param addonName string The source addon name
--- @param tbl table The table to print
--- @param name string|nil Optional name for the table
--- @param maxDepth number|nil Maximum depth to print (default 3)
function MedaDebug:Table(addonName, tbl, name, maxDepth)
    maxDepth = maxDepth or 3
    name = name or "table"
    
    local function serialize(t, depth, visited)
        if depth > maxDepth then return "..." end
        if visited[t] then return "<circular>" end
        visited[t] = true
        
        local result = "{\n"
        local indent = string.rep("  ", depth)
        
        for k, v in pairs(t) do
            local keyStr = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
            local valStr
            
            if type(v) == "table" then
                valStr = serialize(v, depth + 1, visited)
            elseif type(v) == "string" then
                valStr = '"' .. v:sub(1, 100) .. '"'
            else
                valStr = tostring(v)
            end
            
            result = result .. indent .. "  " .. keyStr .. " = " .. valStr .. ",\n"
        end
        
        return result .. indent .. "}"
    end
    
    local output = name .. " = " .. serialize(tbl, 0, {})
    return API:Output(addonName, output, "DEBUG")
end

--- Quick log (auto-detects calling addon)
--- @param message string The message to log
function MedaDebug:Log(message)
    -- Try to detect calling addon from stack
    local stack = debugstack(2, 1, 0)
    local addon = stack:match("AddOns/([^/]+)/") or "Unknown"
    return API:Output(addon, message, "INFO")
end

-- Make API globally accessible for other addons
_G.MedaDebugAPI = MedaDebug
