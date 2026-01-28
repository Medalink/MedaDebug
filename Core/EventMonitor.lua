--[[
    MedaDebug Event Monitor
    Logs WoW events for debugging event-driven code
]]

local addonName, MedaDebug = ...

local EventMonitor = {}
MedaDebug.EventMonitor = EventMonitor

-- Event storage
EventMonitor.events = {}
EventMonitor.maxEvents = 500
EventMonitor.isEnabled = false

-- Watched events
EventMonitor.watchedEvents = {}
EventMonitor.watchAll = false
EventMonitor.isPaused = false

-- Event throttling
EventMonitor.throttleData = {}
EventMonitor.throttleInterval = 1 -- seconds
EventMonitor.throttleThreshold = 10 -- events per second

-- Event categories
EventMonitor.categories = {
    addon = {"ADDON_LOADED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN"},
    unit = {"UNIT_HEALTH", "UNIT_POWER", "UNIT_AURA", "UNIT_TARGET", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP"},
    combat = {"COMBAT_LOG_EVENT_UNFILTERED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_DIED"},
    spell = {"SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "SPELL_UPDATE_CHARGES", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"},
    bag = {"BAG_UPDATE", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "ITEM_UNLOCKED"},
    ui = {"UI_ERROR_MESSAGE", "UI_INFO_MESSAGE", "CURSOR_CHANGED", "MODIFIER_STATE_CHANGED"},
    player = {"PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "ZONE_CHANGED"},
}

-- Callbacks
EventMonitor.onNewEvent = nil

-- Event frame
local eventFrame = CreateFrame("Frame")

--- Enable event monitoring at runtime
function EventMonitor:Enable()
    if self.isEnabled then return end
    self:Initialize()
    MedaDebug:LogInternal("MedaDebug", "Event monitoring enabled", "INFO")
end

--- Disable event monitoring at runtime
function EventMonitor:Disable()
    if not self.isEnabled then return end
    self.isEnabled = false
    
    -- Unregister all events
    eventFrame:UnregisterAllEvents()
    wipe(self.watchedEvents)
    
    MedaDebug:LogInternal("MedaDebug", "Event monitoring disabled", "INFO")
end

--- Check if enabled
function EventMonitor:IsEnabled()
    return self.isEnabled
end

function EventMonitor:Initialize()
    if self.isEnabled then return end
    self.isEnabled = true
    
    -- Load settings
    if MedaDebug.db then
        self.maxEvents = MedaDebug.db.options.maxEvents or 500
        self.throttleThreshold = MedaDebug.db.options.eventThrottle or 10
        
        -- Start watching default categories
        local cats = MedaDebug.db.options.eventCategories or {}
        for cat, enabled in pairs(cats) do
            if enabled and self.categories[cat] then
                for _, event in ipairs(self.categories[cat]) do
                    self:WatchEvent(event)
                end
            end
        end
    end
    
    -- Set up event handler
    eventFrame:SetScript("OnEvent", function(_, event, ...)
        self:HandleEvent(event, ...)
    end)
end

--- Handle an event
--- @param event string Event name
--- @param ... Event arguments
function EventMonitor:HandleEvent(event, ...)
    if self.isPaused then return end
    
    local timestamp = GetTime()
    local args = {...}
    
    -- Throttle check
    local throttleKey = event
    if not self.throttleData[throttleKey] then
        self.throttleData[throttleKey] = {count = 0, lastTime = timestamp, lastEntry = nil}
    end
    
    local throttle = self.throttleData[throttleKey]
    
    if timestamp - throttle.lastTime < self.throttleInterval then
        throttle.count = throttle.count + 1
        
        -- If over threshold, update last entry instead of creating new
        if throttle.count > self.throttleThreshold and throttle.lastEntry then
            throttle.lastEntry.throttleCount = throttle.count
            if self.onNewEvent then
                self.onNewEvent(throttle.lastEntry, true) -- true = update
            end
            return
        end
    else
        throttle.count = 1
        throttle.lastTime = timestamp
    end
    
    -- Create event entry
    local entry = {
        timestamp = timestamp,
        datetime = date("%H:%M:%S") .. string.format(".%03d", (timestamp % 1) * 1000),
        event = event,
        args = args,
        argCount = #args,
        category = self:GetEventCategory(event),
        throttleCount = 1,
        id = #self.events + 1,
    }
    
    -- Store reference for throttling
    throttle.lastEntry = entry
    
    -- Add to events
    self.events[#self.events + 1] = entry
    
    -- Trim if over limit
    while #self.events > self.maxEvents do
        table.remove(self.events, 1)
    end
    
    -- Notify UI
    if self.onNewEvent then
        self.onNewEvent(entry, false)
    end
end

--- Get event category
--- @param event string Event name
--- @return string Category name
function EventMonitor:GetEventCategory(event)
    for cat, events in pairs(self.categories) do
        for _, e in ipairs(events) do
            if e == event then return cat end
        end
    end
    return "other"
end

--- Watch a specific event
--- @param event string Event name
function EventMonitor:WatchEvent(event)
    if not self.watchedEvents[event] then
        self.watchedEvents[event] = true
        eventFrame:RegisterEvent(event)
    end
end

--- Stop watching an event
--- @param event string Event name
function EventMonitor:UnwatchEvent(event)
    if self.watchedEvents[event] then
        self.watchedEvents[event] = nil
        eventFrame:UnregisterEvent(event)
    end
end

--- Watch a category of events
--- @param category string Category name
function EventMonitor:WatchCategory(category)
    local events = self.categories[category]
    if events then
        for _, event in ipairs(events) do
            self:WatchEvent(event)
        end
    end
end

--- Stop watching a category
--- @param category string Category name
function EventMonitor:UnwatchCategory(category)
    local events = self.categories[category]
    if events then
        for _, event in ipairs(events) do
            self:UnwatchEvent(event)
        end
    end
end

--- Watch all events (performance warning!)
function EventMonitor:WatchAllEvents()
    self.watchAll = true
    eventFrame:RegisterAllEvents()
end

--- Stop watching all events
function EventMonitor:UnwatchAllEvents()
    self.watchAll = false
    eventFrame:UnregisterAllEvents()
    
    -- Re-register specific watched events
    for event in pairs(self.watchedEvents) do
        eventFrame:RegisterEvent(event)
    end
end

--- Pause event monitoring
function EventMonitor:Pause()
    self.isPaused = true
end

--- Resume event monitoring
function EventMonitor:Resume()
    self.isPaused = false
end

--- Toggle pause state
function EventMonitor:TogglePause()
    self.isPaused = not self.isPaused
    return self.isPaused
end

--- Get all events
--- @return table Array of events
function EventMonitor:GetEvents()
    return self.events
end

--- Get events filtered by category
--- @param category string|nil Category or nil for all
--- @return table Filtered events
function EventMonitor:GetFilteredEvents(category)
    if not category or category == "all" then
        return self.events
    end
    
    local filtered = {}
    for _, event in ipairs(self.events) do
        if event.category == category then
            filtered[#filtered + 1] = event
        end
    end
    return filtered
end

--- Clear all events
function EventMonitor:ClearEvents()
    wipe(self.events)
    wipe(self.throttleData)
    
    if self.onNewEvent then
        self.onNewEvent(nil, false) -- nil signals clear
    end
end

--- Format event args for display
--- @param args table Event arguments
--- @return string Formatted args
function EventMonitor:FormatArgs(args)
    if not args or #args == 0 then
        return "(no args)"
    end
    
    local parts = {}
    for i, arg in ipairs(args) do
        local str
        if type(arg) == "string" then
            str = '"' .. arg:sub(1, 30) .. (arg:len() > 30 and "..." or "") .. '"'
        elseif type(arg) == "table" then
            str = "{table}"
        elseif type(arg) == "boolean" then
            str = arg and "true" or "false"
        else
            str = tostring(arg)
        end
        parts[#parts + 1] = str
    end
    
    return table.concat(parts, ", ")
end

--- Check if event is being watched
--- @param event string Event name
--- @return boolean
function EventMonitor:IsWatching(event)
    return self.watchAll or self.watchedEvents[event]
end

--- Get watched event count
--- @return number
function EventMonitor:GetWatchedCount()
    local count = 0
    for _ in pairs(self.watchedEvents) do
        count = count + 1
    end
    return count
end
