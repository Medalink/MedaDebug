--[[
    MedaDebug Messages Tab
    Displays debug messages from addons
]]

local _, MedaDebug = ...
local MedaUI = LibStub("MedaUI-2.0")

local MessagesTab = {}
MedaDebug.MessagesTab = MessagesTab
local DEFAULT_ADDON_COLOR = { 0.6, 0.8, 1 }

MessagesTab.frame = nil
MessagesTab.scrollList = nil
MessagesTab.currentFilter = "all"
MessagesTab.searchText = ""
MessagesTab.searchLower = nil
MessagesTab.viewData = nil

local function SetFontStringText(fontString, text)
    text = text or ""
    if fontString._medaText ~= text then
        fontString:SetText(text)
        fontString._medaText = text
    end
end

local function SetFontStringColor(fontString, color)
    if not color then
        return
    end

    local r = color[1] or 1
    local g = color[2] or 1
    local b = color[3] or 1
    local a = color[4]

    if fontString._medaColorR ~= r
        or fontString._medaColorG ~= g
        or fontString._medaColorB ~= b
        or fontString._medaColorA ~= a then
        if a ~= nil then
            fontString:SetTextColor(r, g, b, a)
        else
            fontString:SetTextColor(r, g, b)
        end
        fontString._medaColorR = r
        fontString._medaColorG = g
        fontString._medaColorB = b
        fontString._medaColorA = a
    end
end

function MessagesTab:FindVisibleRow(entry)
    if not self.scrollList or not self.scrollList.visibleRows then
        return nil
    end

    for i = 1, #self.scrollList.visibleRows do
        local row = self.scrollList.visibleRows[i]
        if row and row.boundData == entry then
            return row
        end
    end

    return nil
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

    local search = self.searchLower
    if search then
        local matchesMessage = entry.searchMessage and entry.searchMessage:find(search, 1, true)
        local matchesAddon = entry.searchAddon and entry.searchAddon:find(search, 1, true)
        if not matchesMessage and not matchesAddon then
            return false
        end
    end

    return true
end

function MessagesTab:RenderRow(row, data, index)
    if not data then return end

    local Theme = MedaUI.Theme or MedaUI:GetTheme()
    row.boundData = data

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

    if data.isReloadSeparator then
        SetFontStringText(row.timestamp, "")
        SetFontStringText(row.addon, "")
        SetFontStringText(row.message, data.displayMessage or "")
        SetFontStringColor(row.message, Theme.gold)
        SetFontStringText(row.count, "")
        row:SetBackdropColor(unpack(Theme.backgroundLight))
        return
    end

    SetFontStringText(row.timestamp, data.datetime or "")
    SetFontStringColor(row.timestamp, Theme.textDim)

    SetFontStringText(row.addon, data.addonLabel or "[?]")
    SetFontStringColor(row.addon, data.addonColor or DEFAULT_ADDON_COLOR)

    SetFontStringText(row.message, data.displayMessage or "")
    SetFontStringColor(row.message, data.levelColor or Theme.text)

    SetFontStringText(row.count, data.countText or "")
end

function MessagesTab:RefreshData()
    if not self.scrollList or not MedaDebug.OutputManager then return end
    local profile = MedaDebug.ProfilerLite and MedaDebug.ProfilerLite:BeginSample("Messages.RefreshData", "ui", "MessagesTab")

    local messages
    if self:CanIncrementallyUpdate() then
        messages = MedaDebug.OutputManager:GetMessagesNewestFirst()
    else
        local source = MedaDebug.OutputManager:GetMessages()
        local filtered = {}
        for i = #source, 1, -1 do
            local entry = source[i]
            if self:MatchesFilters(entry) then
                filtered[#filtered + 1] = entry
            end
        end
        messages = filtered
    end

    self.viewData = messages
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
            local row = self:FindVisibleRow(entry)
            if row then
                self:RenderRow(row, entry, row._dataIndex or 0)
            else
                self.scrollList:Refresh()
            end
        else
            self:RefreshData()
        end
        return
    end

    if not self:CanIncrementallyUpdate() or not self.viewData then
        self:RefreshData()
        return
    end

    local newestMessages = MedaDebug.OutputManager:GetMessagesNewestFirst()
    if self.viewData ~= newestMessages then
        self.viewData = newestMessages
        self.scrollList:SetData(self.viewData)
    else
        self.scrollList:Refresh()
    end

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
    self.searchLower = self.searchText ~= "" and self.searchText:lower() or nil
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

if MedaDebug.WorkspaceRegistry then
    MedaDebug.WorkspaceRegistry:RegisterPage("messages", {
        label = "Messages",
        title = "Message Stream",
        subtitle = "Session output from MedaDebug-enabled addons.",
        summary = "Filter by addon, search the active stream, or copy the current visible output.",
        moduleKey = "MessagesTab",
        height = 1200,
        groupId = "streams",
        groupLabel = "Streams",
        groupOrder = 10,
        pageOrder = 10,
    })
end
