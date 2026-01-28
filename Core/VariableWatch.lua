--[[
    MedaDebug Variable Watch
    Monitor variables and tables in real-time
]]

local addonName, MedaDebug = ...

local VariableWatch = {}
MedaDebug.VariableWatch = VariableWatch

-- Watched variables
VariableWatch.watches = {}
VariableWatch.watchOrder = {} -- Maintain order

-- Update settings
VariableWatch.updateInterval = 0.5
VariableWatch.updateTimer = nil

-- Callbacks
VariableWatch.onWatchUpdated = nil
VariableWatch.onWatchAdded = nil
VariableWatch.onWatchRemoved = nil

function VariableWatch:Initialize()
    -- Load settings
    if MedaDebug.db then
        self.updateInterval = MedaDebug.db.options.variableWatchInterval or 0.5
    end
    
    -- Start update timer
    self:StartUpdates()
end

--- Start periodic updates
function VariableWatch:StartUpdates()
    if self.updateTimer then
        self.updateTimer:Cancel()
    end
    
    self.updateTimer = C_Timer.NewTicker(self.updateInterval, function()
        self:UpdateAll()
    end)
end

--- Stop updates
function VariableWatch:StopUpdates()
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
end

--- Resolve a path string to a value
--- @param path string Variable path (e.g., "MyAddon.db.options")
--- @return any, boolean Value and whether it exists
function VariableWatch:ResolvePath(path)
    local parts = {}
    for part in path:gmatch("[^%.%[%]]+") do
        parts[#parts + 1] = part
    end
    
    if #parts == 0 then return nil, false end
    
    local current = _G
    for i, part in ipairs(parts) do
        if current == nil then return nil, false end
        
        -- Try as key
        local key = tonumber(part) or part
        if type(current) == "table" then
            current = current[key]
        else
            return nil, false
        end
    end
    
    return current, true
end

--- Add a variable to watch
--- @param path string Variable path
--- @return boolean Success
function VariableWatch:AddWatch(path)
    if self.watches[path] then
        return false -- Already watching
    end
    
    local value, exists = self:ResolvePath(path)
    
    local watch = {
        path = path,
        currentValue = value,
        previousValue = nil,
        valueType = type(value),
        exists = exists,
        lastChanged = exists and GetTime() or nil,
        changeCount = 0,
        changeHistory = {},
        expanded = false,
    }
    
    self.watches[path] = watch
    self.watchOrder[#self.watchOrder + 1] = path
    
    -- Notify UI
    if self.onWatchAdded then
        self.onWatchAdded(watch)
    end
    
    return true
end

--- Remove a watch
--- @param path string Variable path
function VariableWatch:RemoveWatch(path)
    if not self.watches[path] then return end
    
    local watch = self.watches[path]
    self.watches[path] = nil
    
    -- Remove from order
    for i, p in ipairs(self.watchOrder) do
        if p == path then
            table.remove(self.watchOrder, i)
            break
        end
    end
    
    -- Notify UI
    if self.onWatchRemoved then
        self.onWatchRemoved(watch)
    end
end

--- Update all watches
function VariableWatch:UpdateAll()
    local now = GetTime()
    
    for path, watch in pairs(self.watches) do
        local newValue, exists = self:ResolvePath(path)
        local changed = false
        
        -- Check if value changed
        if exists ~= watch.exists then
            changed = true
        elseif type(newValue) ~= type(watch.currentValue) then
            changed = true
        elseif type(newValue) == "table" then
            -- For tables, do shallow comparison
            changed = not self:ShallowEqual(newValue, watch.currentValue)
        else
            changed = newValue ~= watch.currentValue
        end
        
        if changed then
            -- Record change
            watch.previousValue = watch.currentValue
            watch.currentValue = newValue
            watch.valueType = type(newValue)
            watch.exists = exists
            watch.lastChanged = now
            watch.changeCount = watch.changeCount + 1
            
            -- Add to history (keep last 10)
            table.insert(watch.changeHistory, 1, {
                time = now,
                value = self:SerializeValue(newValue, 2),
                previous = self:SerializeValue(watch.previousValue, 2),
            })
            while #watch.changeHistory > 10 do
                table.remove(watch.changeHistory)
            end
            
            -- Notify UI
            if self.onWatchUpdated then
                self.onWatchUpdated(watch, true) -- true = changed
            end
        end
    end
end

--- Shallow equality check for tables
--- @param t1 table First table
--- @param t2 table Second table
--- @return boolean Equal
function VariableWatch:ShallowEqual(t1, t2)
    if type(t1) ~= "table" or type(t2) ~= "table" then
        return t1 == t2
    end
    
    -- Check same keys
    for k in pairs(t1) do
        if t2[k] == nil then return false end
    end
    for k in pairs(t2) do
        if t1[k] == nil then return false end
    end
    
    -- Check values (shallow)
    for k, v in pairs(t1) do
        if type(v) ~= type(t2[k]) then return false end
        if type(v) ~= "table" and v ~= t2[k] then return false end
    end
    
    return true
end

--- Serialize a value for display
--- @param value any The value
--- @param maxDepth number Maximum depth for tables
--- @return string Serialized value
function VariableWatch:SerializeValue(value, maxDepth)
    maxDepth = maxDepth or 3
    
    local function serialize(v, depth, visited)
        if depth > maxDepth then return "..." end
        
        local t = type(v)
        if t == "nil" then
            return "nil"
        elseif t == "boolean" then
            return v and "true" or "false"
        elseif t == "number" then
            return tostring(v)
        elseif t == "string" then
            if #v > 50 then
                return '"' .. v:sub(1, 50) .. '..."'
            end
            return '"' .. v .. '"'
        elseif t == "table" then
            if visited[v] then return "<circular>" end
            visited[v] = true
            
            local parts = {}
            local count = 0
            for k, val in pairs(v) do
                count = count + 1
                if count > 10 then
                    parts[#parts + 1] = "..."
                    break
                end
                local keyStr = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
                parts[#parts + 1] = keyStr .. "=" .. serialize(val, depth + 1, visited)
            end
            return "{" .. table.concat(parts, ", ") .. "}"
        elseif t == "function" then
            return "<function>"
        elseif t == "userdata" then
            return "<userdata>"
        else
            return tostring(v)
        end
    end
    
    return serialize(value, 0, {})
end

--- Get all watches
--- @return table Array of watches in order
function VariableWatch:GetWatches()
    local result = {}
    for _, path in ipairs(self.watchOrder) do
        result[#result + 1] = self.watches[path]
    end
    return result
end

--- Get a specific watch
--- @param path string Variable path
--- @return table|nil Watch data
function VariableWatch:GetWatch(path)
    return self.watches[path]
end

--- Clear all watches
function VariableWatch:ClearAll()
    wipe(self.watches)
    wipe(self.watchOrder)
    
    if self.onWatchRemoved then
        self.onWatchRemoved(nil) -- nil signals clear all
    end
end

--- Toggle expanded state
--- @param path string Variable path
function VariableWatch:ToggleExpanded(path)
    local watch = self.watches[path]
    if watch then
        watch.expanded = not watch.expanded
    end
end

--- Set update interval
--- @param interval number Interval in seconds
function VariableWatch:SetUpdateInterval(interval)
    self.updateInterval = interval
    self:StartUpdates()
end
