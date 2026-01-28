--[[
    MedaDebug Output Manager
    Routes messages to debug frame, chat, and log files
]]

local addonName, MedaDebug = ...

local OutputManager = {}
MedaDebug.OutputManager = OutputManager

-- Message storage
OutputManager.messages = {}
OutputManager.maxMessages = 1000

-- Callbacks for UI updates
OutputManager.onNewMessage = nil

function OutputManager:Initialize()
    -- Load settings
    if MedaDebug.db then
        self.maxMessages = MedaDebug.db.options.maxMessages or 1000
    end
    
    -- Restore session messages if enabled
    if MedaDebug.db and MedaDebug.db.options.restoreSessionData then
        if MedaDebug.log and MedaDebug.log.session and MedaDebug.log.session.messages then
            for _, msg in ipairs(MedaDebug.log.session.messages) do
                self.messages[#self.messages + 1] = msg
            end
        end
    end
end

--- Handle a new message
--- @param entry table Message entry {timestamp, datetime, addon, level, message, levelColor, addonColor}
function OutputManager:HandleMessage(entry)
    -- Add to messages
    self.messages[#self.messages + 1] = entry
    
    -- Trim if over limit
    while #self.messages > self.maxMessages do
        table.remove(self.messages, 1)
    end
    
    -- Save to session log
    if MedaDebug.log and MedaDebug.log.session then
        MedaDebug.log.session.messages[#MedaDebug.log.session.messages + 1] = {
            timestamp = entry.timestamp,
            datetime = entry.datetime,
            addon = entry.addon,
            level = entry.level,
            message = entry.message,
        }
        
        -- Trim session log
        local maxLog = MedaDebug.db and MedaDebug.db.options.maxLogEntries or 5000
        while #MedaDebug.log.session.messages > maxLog do
            table.remove(MedaDebug.log.session.messages, 1)
        end
    end
    
    -- Output to chat if enabled
    if MedaDebug.db and MedaDebug.db.options.outputToChat then
        local color = entry.levelColor or {1, 1, 1}
        local r, g, b = unpack(color)
        local prefix = string.format("|cff%02x%02x%02x[%s]|r", r*255, g*255, b*255, entry.addon)
        print(prefix .. " " .. entry.message)
    end
    
    -- Notify UI
    if self.onNewMessage then
        self.onNewMessage(entry)
    end
end

--- Get all messages
--- @return table Array of messages
function OutputManager:GetMessages()
    return self.messages
end

--- Get messages filtered by addon
--- @param addonName string|nil Addon name or nil for all
--- @return table Filtered messages
function OutputManager:GetFilteredMessages(addonName)
    if not addonName or addonName == "all" then
        return self.messages
    end
    
    local filtered = {}
    for _, msg in ipairs(self.messages) do
        if msg.addon == addonName then
            filtered[#filtered + 1] = msg
        end
    end
    return filtered
end

--- Clear all messages
function OutputManager:ClearAll()
    wipe(self.messages)
    if MedaDebug.log and MedaDebug.log.session then
        wipe(MedaDebug.log.session.messages)
    end
    
    -- Notify UI
    if self.onNewMessage then
        self.onNewMessage(nil) -- nil signals clear
    end
end

--- Clear current tab (messages only for now)
function OutputManager:ClearCurrent()
    self:ClearAll()
end

--- Export session to log
function OutputManager:ExportSession()
    if not MedaDebug.log then return end
    
    -- Copy session to persistent if mode allows
    local mode = MedaDebug.db and MedaDebug.db.options.logMode or "session"
    if mode == "persistent" or mode == "both" then
        for _, msg in ipairs(self.messages) do
            MedaDebug.log.persistent.messages[#MedaDebug.log.persistent.messages + 1] = {
                timestamp = msg.timestamp,
                datetime = msg.datetime,
                addon = msg.addon,
                level = msg.level,
                message = msg.message,
            }
        end
        
        -- Trim persistent log
        local maxLog = MedaDebug.db and MedaDebug.db.options.maxLogEntries or 5000
        while #MedaDebug.log.persistent.messages > maxLog do
            table.remove(MedaDebug.log.persistent.messages, 1)
        end
    end
    
    print("|cff00ff00[MedaDebug]|r Session exported to log (" .. #self.messages .. " messages)")
end

--- Get message count
--- @return number Total message count
function OutputManager:GetMessageCount()
    return #self.messages
end
