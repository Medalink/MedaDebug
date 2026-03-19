--[[
    MedaDebug Public API
    Interface for external addons to send debug messages
]]

local _, MedaDebug = ...

local API = {}
MedaDebug.API = API
local debugstack = debugstack

-- Registered addons
API.registeredAddons = {}

-- Default colors for log levels
local LEVEL_COLORS = {
    DEBUG = {0.5, 0.5, 0.5},
    INFO = {0.9, 0.9, 0.9},
    WARN = {1, 0.8, 0},
    ERROR = {1, 0.3, 0.3},
}

local function NormalizeSourceInfo(addonName, sourceInfo)
    if type(sourceInfo) ~= "table" then
        return nil
    end

    local sourceKind = sourceInfo.kind
    local sourceName = sourceInfo.name
    if type(sourceKind) ~= "string" or sourceKind == "" or type(sourceName) ~= "string" or sourceName == "" then
        return nil
    end

    local sourceId = sourceInfo.id
    if type(sourceId) ~= "string" or sourceId == "" then
        sourceId = sourceName
    end

    local label = sourceInfo.label
    if type(label) ~= "string" or label == "" then
        if sourceKind == "service" then
            label = addonName .. " / Service: " .. sourceName
        elseif sourceKind == "core" then
            label = addonName .. " / Core: " .. sourceName
        elseif sourceKind == "custom" then
            label = addonName .. " / Custom: " .. sourceName
        else
            label = addonName .. " / " .. sourceName
        end
    end

    local filter = sourceInfo.filter
    if type(filter) ~= "string" or filter == "" then
        filter = table.concat({
            "source",
            addonName,
            sourceKind,
            sourceId,
        }, ":")
    end

    return {
        kind = sourceKind,
        name = sourceName,
        relativePath = sourceInfo.relativePath,
        label = label,
        filter = filter,
    }
end

local function BuildSourceInfo(addonName)
    if type(addonName) ~= "string" or addonName == "" or not debugstack then
        return nil
    end

    local ok, stack = pcall(debugstack, 4, 16, 0)
    if not ok or type(stack) ~= "string" or stack == "" then
        return nil
    end

    local fallback

    for line in stack:gmatch("[^\n]+") do
        local stackAddon, relativePath = line:match("AddOns/([^/]+)/([^:\n]+%.lua)")
        if not stackAddon then
            stackAddon, relativePath = line:match("AddOns\\([^\\]+)\\([^:\n]+%.lua)")
        end

        if stackAddon == addonName and relativePath then
            relativePath = relativePath:gsub("\\", "/")

            local root, rest = relativePath:match("^([^/]+)/(.+)$")
            local sourceKind
            local sourceName

            if root == "Modules" and rest then
                sourceKind = "module"
                sourceName = rest:match("^([^/]+)") or rest
            elseif root == "Services" and rest then
                sourceKind = "service"
                sourceName = rest:match("^([^/]+)") or rest
            elseif root == "Core" and rest then
                sourceKind = "core"
                sourceName = rest:match("^([^/]+)") or rest
            end

            if sourceKind and sourceName then
                sourceName = sourceName:gsub("%.lua$", "")

                local label = addonName .. " / " .. sourceName
                if sourceKind == "service" then
                    label = addonName .. " / Service: " .. sourceName
                elseif sourceKind == "core" then
                    label = addonName .. " / Core: " .. sourceName
                end

                local candidate = {
                    kind = sourceKind,
                    name = sourceName,
                    relativePath = relativePath,
                    label = label,
                    filter = table.concat({
                        "source",
                        addonName,
                        sourceKind,
                        sourceName,
                    }, ":"),
                }

                if sourceKind ~= "core" then
                    return candidate
                end

                fallback = fallback or candidate
            end
        end
    end

    return fallback
end

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
function API:Output(addonName, message, level, sourceInfo)
    level = level or "INFO"
    sourceInfo = NormalizeSourceInfo(addonName, sourceInfo) or BuildSourceInfo(addonName)
    
    -- Create entry
    local entry = {
        timestamp = time(),
        datetime = date("%H:%M:%S"),
        addon = addonName,
        level = level,
        message = tostring(message),
        levelColor = LEVEL_COLORS[level] or LEVEL_COLORS.INFO,
        sourceKind = sourceInfo and sourceInfo.kind or nil,
        sourceName = sourceInfo and sourceInfo.name or nil,
        sourcePath = sourceInfo and sourceInfo.relativePath or nil,
        sourceLabel = sourceInfo and sourceInfo.label or nil,
        sourceFilter = sourceInfo and sourceInfo.filter or nil,
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
function MedaDebug:Print(addonName, message, sourceInfo)
    return API:Output(addonName, message, "INFO", sourceInfo)
end

--- Print a debug message
--- @param addonName string The source addon name
--- @param message string The message to print
function MedaDebug:DebugMsg(addonName, message, sourceInfo)
    return API:Output(addonName, message, "DEBUG", sourceInfo)
end

--- Print a warning message
--- @param addonName string The source addon name
--- @param message string The message to print
function MedaDebug:Warn(addonName, message, sourceInfo)
    return API:Output(addonName, message, "WARN", sourceInfo)
end

--- Print an error message
--- @param addonName string The source addon name
--- @param message string The message to print
function MedaDebug:Error(addonName, message, sourceInfo)
    return API:Output(addonName, message, "ERROR", sourceInfo)
end

--- Pretty-print a table
--- @param addonName string The source addon name
--- @param tbl table The table to print
--- @param name string|nil Optional name for the table
--- @param maxDepth number|nil Maximum depth to print (default 3)
function MedaDebug:Table(addonName, tbl, name, maxDepth, sourceInfo)
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
    return API:Output(addonName, output, "DEBUG", sourceInfo)
end

--- Quick log (auto-detects calling addon)
--- @param message string The message to log
--- @overload fun(self: table, addonName: string, message: string, level: string|nil): table
function MedaDebug:Log(message, maybeMessage, maybeLevel)
    if maybeMessage ~= nil then
        return API:Output(message, maybeMessage, maybeLevel or "INFO")
    end

    -- Try to detect calling addon from stack
    local stack = debugstack(2, 1, 0)
    local addon = stack:match("AddOns/([^/]+)/") or "Unknown"
    return API:Output(addon, message, "INFO")
end

-- Make API globally accessible for other addons
_G.MedaDebugAPI = MedaDebug
