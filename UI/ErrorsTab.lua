--[[
    MedaDebug Errors Tab
    Displays errors with smart formatting and hints
]]

local _, MedaDebug = ...
local MedaUI = LibStub("MedaUI-2.0")

local ErrorsTab = {}
MedaDebug.ErrorsTab = ErrorsTab

ErrorsTab.frame = nil
ErrorsTab.scrollList = nil
ErrorsTab.selectedError = nil
ErrorsTab.currentFilter = "all"
ErrorsTab.searchText = ""
ErrorsTab.searchLower = nil
ErrorsTab.viewData = nil
local DEFAULT_SELECTED_BACKDROP = { 0.3, 0.3, 0.5, 0.5 }
local DEFAULT_CLEAR_BACKDROP = { 0, 0, 0, 0 }

local function SetFontStringText(fontString, text)
    text = text or ""
    if fontString._medaText ~= text then
        fontString:SetText(text)
        fontString._medaText = text
    end
end

local function SetFontStringColor(fontString, r, g, b, a)
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

function ErrorsTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()
    
    -- Suppressed count status bar at top
    self.statusBar = CreateFrame("Frame", nil, parent)
    self.statusBar:SetHeight(20)
    self.statusBar:SetPoint("TOPLEFT", 0, 0)
    self.statusBar:SetPoint("TOPRIGHT", 0, 0)
    self.statusBar:Hide()
    
    self.statusText = self.statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.statusText:SetPoint("LEFT", 10, 0)
    self.statusText:SetTextColor(unpack(Theme.textDim))
    
    -- Create scroll list with taller rows for expanded view
    self.scrollList = MedaUI:CreateScrollList(parent, parent:GetWidth(), parent:GetHeight(), {
        rowHeight = 56,
        safeRender = true,
        renderRow = function(row, data, index)
            self:RenderRow(row, data, index)
        end,
    })
    self.scrollList:SetPoint("TOPLEFT", 0, 0)
    self.scrollList:SetPoint("BOTTOMRIGHT", 0, 0)

    self.emptyState = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.emptyState:SetPoint("TOPLEFT", 12, -12)
    self.emptyState:SetPoint("TOPRIGHT", -12, -12)
    self.emptyState:SetJustifyH("LEFT")
    self.emptyState:SetJustifyV("TOP")
    self.emptyState:SetWordWrap(true)
    self.emptyState:SetTextColor(unpack(Theme.textDim))
    self.emptyState:Hide()
    
    -- Initial data load
    self:RefreshData()
end

function ErrorsTab:HasActiveSearch()
    return self.searchText and self.searchText ~= ""
end

function ErrorsTab:MatchesFilters(entry)
    local summary = entry.summary or {}
    local sourceAddon = summary.sourceAddon or "Unknown"

    if self.currentFilter ~= "all" and sourceAddon ~= self.currentFilter then
        return false
    end

    local search = self.searchLower
    if search then
        if not SafeContains(summary.shortMessage, search) and
           not SafeContains(summary.hint, search) and
           not SafeContains(sourceAddon, search) and
           not SafeContains(entry.raw and entry.raw.message, search) then
            return false
        end
    end

    return true
end

function ErrorsTab:InitializeRow(row)
    if row._medaInitialized then
        return
    end

    row.mainText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.mainText:SetPoint("TOPLEFT", 10, -10)
    row.mainText:SetPoint("TOPRIGHT", -150, -8)
    row.mainText:SetJustifyH("LEFT")
    row.mainText:SetWordWrap(false)

    row.hintText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.hintText:SetPoint("TOPLEFT", 24, -30)
    row.hintText:SetPoint("TOPRIGHT", -150, -30)
    row.hintText:SetJustifyH("LEFT")
    row.hintText:SetWordWrap(false)

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.countText:SetPoint("TOPRIGHT", -90, -8)

    row.suppressBtn = MedaUI:CreateIconButton(row, {
        size = 18,
        icon = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
        iconActive = "Interface\\Buttons\\UI-GuildButton-PublicNote-Disabled",
        tooltip = "Suppress this error",
        tooltipActive = "Unsuppress this error",
        toggle = true,
    })
    row.suppressBtn:SetPoint("TOPRIGHT", -62, -8)
    row.suppressBtn.OnClick = function(_, _, isActive)
        local data = row.boundData
        if not data or not MedaDebug.ErrorHandler then
            return
        end
        if isActive then
            MedaDebug.ErrorHandler:SuppressError(data)
        else
            MedaDebug.ErrorHandler:UnsuppressError(data)
        end
    end

    row.copyBtn = CreateFrame("Button", nil, row)
    row.copyBtn:SetSize(50, 18)
    row.copyBtn:SetPoint("RIGHT", -10, 0)
    row.copyBtn.text = row.copyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.copyBtn.text:SetPoint("CENTER")
    row.copyBtn.text:SetText("Copy")
    row.copyBtn:SetScript("OnClick", function()
        if row.boundData then
            self:CopyError(row.boundData)
        end
    end)
    row.copyBtn:SetScript("OnEnter", function(btn)
        local Theme = MedaUI.Theme or MedaUI:GetTheme()
        SetFontStringColor(btn.text, unpack(Theme.text))
    end)
    row.copyBtn:SetScript("OnLeave", function(btn)
        local Theme = MedaUI.Theme or MedaUI:GetTheme()
        SetFontStringColor(btn.text, unpack(Theme.textDim))
    end)

    row:EnableMouse(true)
    row:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and row.boundData then
            self:SelectError(row.boundData)
        end
    end)

    row._medaInitialized = true
end

function ErrorsTab:FindVisibleRow(entry)
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

function ErrorsTab:RenderRow(row, data, index)
    if not data then return end
    
    local Theme = MedaUI.Theme or MedaUI:GetTheme()
    
    -- Ensure data has required structure (protect against corrupt saved data)
    if not data.summary then
        data.summary = {
            type = "UNKNOWN",
            sourceAddon = "Unknown",
            sourceFile = "?",
            sourceLine = 0,
            hint = "No hint available",
            shortMessage = "",
        }
    end
    if not data.occurrences then
        data.occurrences = { count = 1 }
    end
    if not data.raw then
        data.raw = { message = "", stack = "", datetime = "" }
    end
    if not data.context then
        data.context = { callChain = {} }
    end
    
    self:InitializeRow(row)
    row.boundData = data
    
    -- Extract data
    local summary = data.summary
    local addonName = summary.sourceAddon or "Unknown"
    local errorType = summary.type or "ERROR"
    local sourceFile = summary.sourceFile or "?"
    local sourceLine = summary.sourceLine or 0
    local hint = summary.hint or "No hint available"
    local count = (data.occurrences and data.occurrences.count) or 1
    local isSuppressed = data.suppressed or false
    
    -- Main line: [!] [Addon] TYPE in file:line
    local mainLine
    if isSuppressed then
        mainLine = string.format("|cff666666[S]|r |cff556677[%s]|r %s in %s:%d",
            addonName, errorType, sourceFile, sourceLine)
    else
        mainLine = string.format("|cffff4444[!]|r |cff88bbff[%s]|r %s in %s:%d",
            addonName, errorType, sourceFile, sourceLine)
    end
    SetFontStringText(row.mainText, mainLine)
    
    -- Hint line
    if isSuppressed then
        SetFontStringText(row.hintText, "|cff555555> " .. hint .. "|r")
    else
        SetFontStringText(row.hintText, "|cff888888> " .. hint .. "|r")
    end
    
    SetFontStringText(row.countText, "(x" .. count .. ")")
    if isSuppressed then
        SetFontStringColor(row.countText, 0.4, 0.4, 0.4)
    elseif count > 1 then
        SetFontStringColor(row.countText, unpack(Theme.levelWarn))
    else
        SetFontStringColor(row.countText, unpack(Theme.textDim))
    end
    
    row.suppressBtn:SetActive(isSuppressed)
    SetFontStringColor(row.copyBtn.text, unpack(Theme.textDim))
    
    row:SetAlpha(isSuppressed and 0.6 or 1.0)
    if self.selectedError == data.id then
        row:SetBackdropColor(unpack(DEFAULT_SELECTED_BACKDROP))
    else
        row:SetBackdropColor(unpack(DEFAULT_CLEAR_BACKDROP))
    end
end

function ErrorsTab:RefreshData()
    if not self.scrollList or not MedaDebug.ErrorHandler then return end
    local profile = MedaDebug.ProfilerLite and MedaDebug.ProfilerLite:BeginSample("Errors.RefreshData", "ui", "ErrorsTab")
    
    local errors = MedaDebug.ErrorHandler:GetErrors()
    local filtered = {}

    for _, err in ipairs(errors) do
        if self:MatchesFilters(err) then
            filtered[#filtered + 1] = err
        end
    end

    self.viewData = filtered
    self.scrollList:SetData(self.viewData)

    if self.emptyState then
        if #filtered == 0 then
            self.emptyState:SetText(string.format(
                "No error rows matched.\nTracked errors: %d\nVisible badge count: %d\nFilter: %s\nSearch: %s",
                #errors,
                MedaDebug.ErrorHandler:GetVisibleErrorCount(),
                tostring(self.currentFilter),
                self.searchText ~= "" and self.searchText or "(none)"
            ))
            self.emptyState:Show()
        else
            self.emptyState:Hide()
        end
    end
    
    -- Update suppressed count status bar
    if self.statusBar then
        local suppressed = MedaDebug.ErrorHandler:GetSuppressedErrorCount()
        if suppressed > 0 then
            self.statusText:SetText(suppressed .. " error(s) suppressed")
            self.statusBar:Show()
            self.scrollList:SetPoint("TOPLEFT", 0, -20)
        else
            self.statusBar:Hide()
            self.scrollList:SetPoint("TOPLEFT", 0, 0)
        end
    end

    if profile then
        MedaDebug.ProfilerLite:EndSample(profile)
    end
end

function ErrorsTab:OnNewError(entry)
    if not self.scrollList then
        return
    end

    if self:HasActiveSearch() or not self:MatchesFilters(entry) or not self.viewData then
        self:RefreshData()
    else
        self.scrollList:AddItem(entry, MedaDebug.db and MedaDebug.db.options.autoScroll)
    end
end

function ErrorsTab:OnErrorUpdated(entry)
    if not self.scrollList then
        return
    end

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
end

function ErrorsTab:SelectError(data)
    self.selectedError = data.id
    _G.SELECTED = data -- For console access
    self.scrollList:Refresh()
    
    -- Log selection for debugging in console
    if MedaDebug.db and MedaDebug.db.options.devMode then
        print("|cff00ff00[MedaDebug]|r Error selected - access via SELECTED global in console")
    end
end

function ErrorsTab:CopyError(data)
    if not MedaDebug.ErrorHandler then return end

    local text = MedaDebug.ErrorHandler:FormatForCopy(data)

    -- Use MedaUI's shared TextViewer
    MedaUI:ShowTextViewer("Error Report - Press Ctrl+C to copy", text)
end

function ErrorsTab:Clear()
    if MedaDebug.ErrorHandler then
        MedaDebug.ErrorHandler:ClearErrors()
    end
    self.selectedError = nil
    self:RefreshData()
end

function ErrorsTab:Copy()
    if not MedaDebug.ErrorHandler then
        return
    end

    if self.selectedError and self.viewData then
        for i = 1, #self.viewData do
            local entry = self.viewData[i]
            if entry and entry.id == self.selectedError then
                self:CopyError(entry)
                return
            end
        end
    end

    local firstVisible = self.viewData and self.viewData[1]
    if firstVisible then
        self:CopyError(firstVisible)
    end
end

function ErrorsTab:OnShow()
    self:RefreshData()
end

function ErrorsTab:OnFilterChanged(filter)
    self.currentFilter = filter
    self:RefreshData()
end

function ErrorsTab:OnSearch(text)
    self.searchText = text or ""
    self.searchLower = self.searchText ~= "" and self.searchText:lower() or nil
    self:RefreshData()
end

if MedaDebug.WorkspaceRegistry then
    MedaDebug.WorkspaceRegistry:RegisterPage("errors", {
        label = "Errors",
        title = "Captured Errors",
        subtitle = "Structured errors grouped by signature and source addon.",
        summary = "Suppress noisy signatures, inspect grouped stacks, or jump here from error notifications.",
        moduleKey = "ErrorsTab",
        height = 1200,
        useAddonFilter = true,
        useGlobalSearch = true,
        useGlobalClear = true,
        useGlobalCopy = true,
        groupId = "streams",
        groupLabel = "Streams",
        groupOrder = 10,
        pageOrder = 20,
        navLabel = function(page, context)
            local errorCount = context.errorCount or 0
            if errorCount > 0 then
                return string.format("%s (%d)", page.label, errorCount)
            end

            return page.label
        end,
    })
end
