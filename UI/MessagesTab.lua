--[[
    MedaDebug Messages Tab
    Displays debug messages from addons
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local MessagesTab = {}
MedaDebug.MessagesTab = MessagesTab

MessagesTab.frame = nil
MessagesTab.scrollList = nil
MessagesTab.currentFilter = "all"
MessagesTab.searchText = ""

function MessagesTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()
    
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

    if not row.message then
        row.message = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.message:SetPoint("LEFT", row.addon, "RIGHT", 8, 0)
        row.message:SetPoint("RIGHT", -8, 0)
        row.message:SetJustifyH("LEFT")
        row.message:SetWordWrap(false)
    end
    
    -- Check for reload separator
    if data.message:match("^%-%-%-") then
        row.timestamp:SetText("")
        row.addon:SetText("")
        row.message:SetText(data.message)
        row.message:SetTextColor(unpack(Theme.gold))
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
end

function MessagesTab:RefreshData()
    if not self.scrollList or not MedaDebug.OutputManager then return end

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
            if msg.message:lower():find(search, 1, true) or
               (msg.addon and msg.addon:lower():find(search, 1, true)) then
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

    self.scrollList:SetData(reversed)

    -- Auto-scroll to top (newest) if enabled
    if MedaDebug.db and MedaDebug.db.options.autoScroll then
        self.scrollList:ScrollToTop()
    end
end

function MessagesTab:OnNewMessage(entry)
    if not entry then
        -- Clear signal
        self:RefreshData()
        return
    end

    -- Check filter
    if self.currentFilter ~= "all" and entry.addon ~= self.currentFilter then
        return
    end

    -- Check search
    if self.searchText and self.searchText ~= "" then
        local search = self.searchText:lower()
        if not entry.message:lower():find(search, 1, true) and
           not (entry.addon and entry.addon:lower():find(search, 1, true)) then
            return
        end
    end

    -- Refresh to show new message at top (reversed order)
    self:RefreshData()
end

function MessagesTab:OnFilterChanged(filter)
    self.currentFilter = filter
    self:RefreshData()
end

function MessagesTab:OnSearch(text)
    self.searchText = text
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
