--[[
    MedaDebug Search Bar
    Global search functionality
    
    Note: The search bar is created directly in DebugFrame.lua using MedaUI:CreateSearchBox
    This file is reserved for advanced search functionality
]]

local addonName, MedaDebug = ...

local SearchBar = {}
MedaDebug.SearchBar = SearchBar

-- Search state
SearchBar.lastSearch = ""
SearchBar.results = {}

--- Perform global search across all tabs
--- @param query string Search query
--- @return table Search results
function SearchBar:Search(query)
    if not query or query == "" then
        wipe(self.results)
        return self.results
    end
    
    self.lastSearch = query
    wipe(self.results)
    
    local queryLower = query:lower()
    
    -- Search messages
    if MedaDebug.OutputManager then
        for i, msg in ipairs(MedaDebug.OutputManager:GetMessages()) do
            if msg.message:lower():find(queryLower, 1, true) or
               (msg.addon and msg.addon:lower():find(queryLower, 1, true)) then
                self.results[#self.results + 1] = {
                    type = "message",
                    tab = "messages",
                    index = i,
                    data = msg,
                    preview = msg.message:sub(1, 50),
                }
            end
        end
    end
    
    -- Search errors
    if MedaDebug.ErrorHandler then
        for i, err in ipairs(MedaDebug.ErrorHandler:GetErrors()) do
            local summary = err.summary or {}
            if (summary.shortMessage and summary.shortMessage:lower():find(queryLower, 1, true)) or
               (summary.sourceAddon and summary.sourceAddon:lower():find(queryLower, 1, true)) then
                self.results[#self.results + 1] = {
                    type = "error",
                    tab = "errors",
                    index = i,
                    data = err,
                    preview = summary.shortMessage:sub(1, 50),
                }
            end
        end
    end
    
    -- Search events
    if MedaDebug.EventMonitor then
        for i, event in ipairs(MedaDebug.EventMonitor:GetEvents()) do
            if event.event:lower():find(queryLower, 1, true) then
                self.results[#self.results + 1] = {
                    type = "event",
                    tab = "events",
                    index = i,
                    data = event,
                    preview = event.event,
                }
            end
        end
    end
    
    return self.results
end

--- Get search results
--- @return table Search results
function SearchBar:GetResults()
    return self.results
end

--- Clear search
function SearchBar:Clear()
    self.lastSearch = ""
    wipe(self.results)
end
