--[[
    MedaDebug Messages Tab
    Displays debug messages from addons
]]

local _, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local MessagesTab = {}
MedaDebug.MessagesTab = MessagesTab

MessagesTab.frame = nil
MessagesTab.scrollList = nil
MessagesTab.currentFilter = "all"
MessagesTab.searchText = ""
MessagesTab.viewData = nil

local function IsReloadSeparator(message)
    if type(message) ~= "string" then
        return false
    end

    local ok, isSeparator = pcall(function()
        return message:match("^%-%-%-") ~= nil
    end)

    return ok and isSeparator or false
end

local function SafeContains(text, search)
    if type(text) ~= "string" or search == "" then
        return false
    end

    local ok, lowerText = pcall(function()
        return text:lower()
    end)
    if not ok then
        return false
    end

    return lowerText:find(search, 1, true) ~= nil
end

function MessagesTab:Initialize(parent)
    self.frame = parent
    
    -- Create scroll list
    self.scrollList = MedaUI:CreateScrollList(parent, parent:GetWidth(), parent:GetHeight(), {
        rowHeight = 24,
        renderRow = function(row, data, index)
            self:RenderRow(row, data, index)
        end,
    })
    self.scrollList:SetPoint("TOPLEFT", 0, 0)
    self.scrollList:SetPoint("BOTTOMRIGHT", 0, 0)
    
    -- Initial data load
    self:RefreshData()
end

function MessagesTab:HasActiveSearch()
    return self.searchText and self.searchText ~= ""
end

function MessagesTab:CanIncrementallyUpdate()
    return self.currentFilter == "all" and not self:HasActiveSearch()
end

function MessagesTab:MatchesFilters(entry)
    if self.currentFilter ~= "all" and entry.addon ~= self.currentFilter then
        return false
    end

    if self:HasActiveSearch() then
        local search = self.searchText:lower()
        if not SafeContains(entry.message, search) and not SafeContains(entry.addon, search) then
            return false
        end
    end

    return true
end

function MessagesTab:RenderRow(row, data, index)
    if not data then return end

    local Theme = MedaUI:GetTheme()

    -- Create elements if needed
    if not row.timestamp then
        row.timestamp = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.timestamp:SetPoint("LEFT", 8, 0)
        row.timestamp:SetWidth(60)
        row.timestamp:SetJustifyH("LEFT")
    end

    if not row.addon then
        row.addon = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.addon:SetPoint("LEFT", row.timestamp, "RIGHT", 8, 0)
        row.addon:SetWidth(100)
        row.addon:SetJustifyH("LEFT")
    end

    if not row.count then
        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.count:SetPoint("RIGHT", -8, 0)
        row.count:SetWidth(50)
        row.count:SetJustifyH("RIGHT")
    end

    if not row.message then
        row.message = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.message:SetPoint("LEFT", row.addon, "RIGHT", 8, 0)
        row.message:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
        row.message:SetJustifyH("LEFT")
        row.message:SetWordWrap(false)
    end

    -- Check for reload separator
    if IsReloadSeparator(data.message) then
        row.timestamp:SetText("")
        row.addon:SetText("")
        row.message:SetText(data.message)
        row.message:SetTextColor(unpack(Theme.gold))
        row.count:SetText("")
        row:SetBackdropColor(unpack(Theme.backgroundLight))
        return
    end

    -- Set values
    row.timestamp:SetText(data.datetime or "")
    row.timestamp:SetTextColor(unpack(Theme.textDim))

    row.addon:SetText("[" .. (data.addon or "?") .. "]")
    if data.addonColor then
        row.addon:SetTextColor(unpack(data.addonColor))
    else
        row.addon:SetTextColor(0.6, 0.8, 1)
    end

    row.message:SetText(data.message or "")
    if data.levelColor then
        row.message:SetTextColor(unpack(data.levelColor))
    else
        row.message:SetTextColor(unpack(Theme.text))
    end

    -- Show count if 3 or more duplicates
    if data.count and data.count >= 3 then
        row.count:SetText("|cffFFAA00x" .. data.count .. "|r")
    else
        row.count:SetText("")
    end
end

function MessagesTab:RefreshData()
    if not self.scrollList or not MedaDebug.OutputManager then return end
    local profile = MedaDebug.ProfilerLite and MedaDebug.ProfilerLite:BeginSample("Messages.RefreshData", "ui", "MessagesTab")

    local messages
    if self.currentFilter == "all" then
        messages = MedaDebug.OutputManager:GetMessages()
    else
        messages = MedaDebug.OutputManager:GetFilteredMessages(self.currentFilter)
    end

    -- Apply search filter
    if self.searchText and self.searchText ~= "" then
        local filtered = {}
        local search = self.searchText:lower()
        for _, msg in ipairs(messages) do
            if SafeContains(msg.message, search) or SafeContains(msg.addon, search) then
                filtered[#filtered + 1] = msg
            end
        end
        messages = filtered
    end

    -- Reverse order so newest messages are at top
    local reversed = {}
    for i = #messages, 1, -1 do
        reversed[#reversed + 1] = messages[i]
    end

    self.viewData = reversed
    self.scrollList:SetData(self.viewData)

    -- Auto-scroll to top (newest) if enabled
    if MedaDebug.db and MedaDebug.db.options.autoScroll then
        self.scrollList:ScrollToTop()
    end

    if profile then
        MedaDebug.ProfilerLite:EndSample(profile)
    end
end

function MessagesTab:OnNewMessage(entry, isUpdate)
    if not entry then
        -- Clear signal
        self:RefreshData()
        return
    end

    if isUpdate then
        if self:MatchesFilters(entry) then
            self.scrollList:Refresh()
        else
            self:RefreshData()
        end
        return
    end

    if not self:CanIncrementallyUpdate() or not self.viewData then
        self:RefreshData()
        return
    end

    table.insert(self.viewData, 1, entry)
    while #self.viewData > MedaDebug.OutputManager:GetMessageCount() do
        table.remove(self.viewData)
    end
    self.scrollList:SetData(self.viewData)

    if MedaDebug.db and MedaDebug.db.options.autoScroll then
        self.scrollList:ScrollToTop()
    end
end

function MessagesTab:OnFilterChanged(filter)
    self.currentFilter = filter
    self:RefreshData()
end

function MessagesTab:OnSearch(text)
    self.searchText = text or ""
    self:RefreshData()
end

function MessagesTab:Clear()
    if MedaDebug.OutputManager then
        MedaDebug.OutputManager:ClearAll()
    end
    self:RefreshData()
end

function MessagesTab:OnShow()
    self:RefreshData()
end

function MessagesTab:OnResize(width, height)
    -- ScrollList handles resize internally
end
