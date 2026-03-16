--[[
    MedaDebug Output Manager
    Routes messages to debug frame, chat, and log files
]]

local _, MedaDebug = ...

local OutputManager = {}
MedaDebug.OutputManager = OutputManager

-- Message storage
OutputManager.messages = {}
OutputManager.newestMessages = {}
OutputManager.maxMessages = 1000

-- Callbacks for UI updates
OutputManager.onNewMessage = nil

local function IsReloadSeparator(message)
    if type(message) ~= "string" then
        return false
    end

    local ok, isSeparator = pcall(function()
        return message:match("^%-%-%-") ~= nil
    end)

    return ok and isSeparator or false
end

local function BuildDisplayMessage(message)
    if type(message) ~= "string" then
        return tostring(message or "")
    end

    if IsReloadSeparator(message) then
        return message
    end

    local ok, displayMessage = pcall(function()
        if #message <= 180 then
            return message
        end

        return message:sub(1, 177) .. "..."
    end)

    if ok and type(displayMessage) == "string" then
        return displayMessage
    end

    return "(message unavailable)"
end

local function BuildSearchText(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end

    local ok, lowered = pcall(function()
        return value:lower()
    end)

    if ok and type(lowered) == "string" then
        return lowered
    end

    return nil
end

local function BuildCountText(count)
    if count and count >= 3 then
        return "|cffFFAA00x" .. count .. "|r"
    end

    return ""
end

local function NormalizeEntryForUI(entry)
    if not entry then
        return
    end

    entry.isReloadSeparator = IsReloadSeparator(entry.message)
    entry.displayMessage = BuildDisplayMessage(entry.message)
    entry.addonLabel = "[" .. (entry.addon or "?") .. "]"
    entry.searchMessage = BuildSearchText(entry.message)
    entry.searchAddon = BuildSearchText(entry.addon) or ""
    entry.countText = BuildCountText(entry.count)
end

local function RebuildNewestMessages(messages, newestMessages)
    wipe(newestMessages)
    for i = #messages, 1, -1 do
        newestMessages[#newestMessages + 1] = messages[i]
    end
end

function OutputManager:Initialize()
    -- Load settings
    if MedaDebug.db then
        self.maxMessages = MedaDebug.db.options.maxMessages or 1000
    end
    
    -- Restore session messages if enabled
    if MedaDebug.db and MedaDebug.db.options.restoreSessionData then
        if MedaDebug.log and MedaDebug.log.session and MedaDebug.log.session.messages then
            for _, msg in ipairs(MedaDebug.log.session.messages) do
                NormalizeEntryForUI(msg)
                self.messages[#self.messages + 1] = msg
            end
            RebuildNewestMessages(self.messages, self.newestMessages)
        end
    end
end

--- Handle a new message
--- @param entry table Message entry {timestamp, datetime, addon, level, message, levelColor, addonColor}
function OutputManager:HandleMessage(entry)
    local profile = MedaDebug.ProfilerLite and MedaDebug.ProfilerLite:BeginSample("Output.HandleMessage", "output", entry and entry.addon)

    -- Check if this is a duplicate of the last message (same addon, level, and message).
    -- pcall guards against secret/tainted strings that cannot be compared.
    local lastMsg = self.messages[#self.messages]
    local isDuplicate = false
    if lastMsg then
        local ok, result = pcall(function()
            return lastMsg.addon == entry.addon
               and lastMsg.level == entry.level
               and lastMsg.message == entry.message
        end)
        isDuplicate = ok and result
    end
    if isDuplicate then
        -- Increment count on existing message
        if not lastMsg.displayMessage then
            NormalizeEntryForUI(lastMsg)
        end
        lastMsg.count = (lastMsg.count or 1) + 1
        lastMsg.lastTimestamp = entry.timestamp
        lastMsg.lastDatetime = entry.datetime
        lastMsg.countText = BuildCountText(lastMsg.count)

        -- Notify UI of update (pass the updated message)
        if self.onNewMessage then
            self.onNewMessage(lastMsg, true)  -- true = update existing
        end
        if profile then
            MedaDebug.ProfilerLite:EndSample(profile)
        end
        return
    end

    -- New unique message
    entry.count = 1
    NormalizeEntryForUI(entry)
    self.messages[#self.messages + 1] = entry
    table.insert(self.newestMessages, 1, entry)

    -- Trim if over limit
    while #self.messages > self.maxMessages do
        table.remove(self.messages, 1)
        table.remove(self.newestMessages)
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

    if profile then
        MedaDebug.ProfilerLite:EndSample(profile)
    end
end

--- Get all messages
--- @return table Array of messages
function OutputManager:GetMessages()
    return self.messages
end

--- Get all messages ordered newest-first for UI views
--- @return table Array of messages
function OutputManager:GetMessagesNewestFirst()
    return self.newestMessages
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
    wipe(self.newestMessages)
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

--- Get unique addon names from messages
--- @return table Array of addon names (sorted)
function OutputManager:GetAddonsFromMessages()
    local addonSet = {}
    for _, msg in ipairs(self.messages) do
        if msg.addon and msg.addon ~= "" then
            addonSet[msg.addon] = true
        end
    end

    local addons = {}
    for addon in pairs(addonSet) do
        addons[#addons + 1] = addon
    end
    table.sort(addons)
    return addons
end

--- Get messages from current session for copying
--- Formatted with just timestamp and message, no addon/channel
--- @return string Formatted text ready for copying
function OutputManager:GetMessagesForCopy()
    local messages = self.messages
    if #messages == 0 then
        return "No messages found."
    end

    -- Find all reload separator indices
    local reloadIndices = {}
    for i = 1, #messages do
        local msg = messages[i]
        if msg and IsReloadSeparator(msg.message) then
            reloadIndices[#reloadIndices + 1] = i
        end
    end

    -- Determine range based on reload separators
    local startIndex, endIndex

    if #reloadIndices == 0 then
        -- No reloads: get all messages
        startIndex = 1
        endIndex = #messages
    elseif #reloadIndices == 1 then
        local reloadIdx = reloadIndices[1]
        -- Check if there are messages after the reload
        if reloadIdx < #messages then
            -- Get messages after the reload
            startIndex = reloadIdx + 1
            endIndex = #messages
        else
            -- Reload is at end, get messages before it
            startIndex = 1
            endIndex = reloadIdx - 1
        end
    else
        -- Multiple reloads: get messages after the last reload
        local lastReloadIdx = reloadIndices[#reloadIndices]
        local prevReloadIdx = reloadIndices[#reloadIndices - 1]

        if lastReloadIdx < #messages then
            -- Get messages after the last reload
            startIndex = lastReloadIdx + 1
            endIndex = #messages
        else
            -- Last reload is at end, get messages between prev and last reload
            startIndex = prevReloadIdx + 1
            endIndex = lastReloadIdx - 1
        end
    end

    -- Build formatted output
    local lines = {}
    for i = startIndex, endIndex do
        local msg = messages[i]
        if msg and msg.message then
            -- Skip reload separators in output
            if not IsReloadSeparator(msg.message) then
                local timestamp = msg.datetime or ""
                local countSuffix = ""
                if msg.count and msg.count > 1 then
                    countSuffix = " (x" .. msg.count .. ")"
                end
                lines[#lines + 1] = timestamp .. " " .. msg.message .. countSuffix
            end
        end
    end

    if #lines == 0 then
        return "No messages found."
    end

    return table.concat(lines, "\n")
end

--- Update the in-memory message cap and trim existing messages if needed
--- @param maxMessages number
function OutputManager:SetMaxMessages(maxMessages)
    self.maxMessages = math.max(1, maxMessages or self.maxMessages or 1000)

    while #self.messages > self.maxMessages do
        table.remove(self.messages, 1)
        table.remove(self.newestMessages)
    end

    if self.onNewMessage then
        self.onNewMessage(nil)
    end
end

if MedaDebug.RuntimeRegistry then
    MedaDebug.RuntimeRegistry:RegisterModule("OutputManager", {
        order = 20,
    })
end
