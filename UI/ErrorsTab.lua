--[[
    MedaDebug Errors Tab
    Displays errors with smart formatting and hints
]]

local _, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local ErrorsTab = {}
MedaDebug.ErrorsTab = ErrorsTab

ErrorsTab.frame = nil
ErrorsTab.scrollList = nil
ErrorsTab.selectedError = nil
ErrorsTab.currentFilter = "all"
ErrorsTab.searchText = ""
ErrorsTab.viewData = nil

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
        renderRow = function(row, data, index)
            self:RenderRow(row, data, index)
        end,
    })
    self.scrollList:SetPoint("TOPLEFT", 0, 0)
    self.scrollList:SetPoint("BOTTOMRIGHT", 0, 0)
    
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

    if self:HasActiveSearch() then
        local search = self.searchText:lower()
        if not SafeContains(summary.shortMessage, search) and
           not SafeContains(summary.hint, search) and
           not SafeContains(sourceAddon, search) and
           not SafeContains(entry.raw and entry.raw.message, search) then
            return false
        end
    end

    return true
end

function ErrorsTab:RenderRow(row, data, index)
    if not data then return end
    
    local Theme = MedaUI:GetTheme()
    
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
    
    -- Create elements if needed
    if not row.mainText then
        row.mainText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.mainText:SetPoint("TOPLEFT", 10, -10)
        row.mainText:SetPoint("TOPRIGHT", -150, -10)
        row.mainText:SetJustifyH("LEFT")
        row.mainText:SetWordWrap(false)
    end

    if not row.hintText then
        row.hintText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.hintText:SetPoint("TOPLEFT", 24, -30)
        row.hintText:SetPoint("TOPRIGHT", -150, -30)
        row.hintText:SetJustifyH("LEFT")
        row.hintText:SetWordWrap(false)
    end
    
    if not row.countText then
        row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.countText:SetPoint("TOPRIGHT", -90, -8)
    end
    
    if not row.suppressBtn then
        row.suppressBtn = MedaUI:CreateIconButton(row, {
            size = 18,
            icon = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
            iconActive = "Interface\\Buttons\\UI-GuildButton-PublicNote-Disabled",
            tooltip = "Suppress this error",
            tooltipActive = "Unsuppress this error",
            toggle = true,
        })
        row.suppressBtn:SetPoint("TOPRIGHT", -62, -8)
    end
    
    if not row.copyBtn then
        row.copyBtn = CreateFrame("Button", nil, row)
        row.copyBtn:SetSize(50, 18)
        row.copyBtn:SetPoint("RIGHT", -10, 0)
        row.copyBtn.text = row.copyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.copyBtn.text:SetPoint("CENTER")
        row.copyBtn.text:SetText("Copy")
    end
    
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
    row.mainText:SetText(mainLine)
    
    -- Hint line
    if isSuppressed then
        row.hintText:SetText("|cff555555> " .. hint .. "|r")
    else
        row.hintText:SetText("|cff888888> " .. hint .. "|r")
    end
    
    -- Count
    row.countText:SetText("(x" .. count .. ")")
    if isSuppressed then
        row.countText:SetTextColor(0.4, 0.4, 0.4)
    elseif count > 1 then
        row.countText:SetTextColor(unpack(Theme.levelWarn))
    else
        row.countText:SetTextColor(unpack(Theme.textDim))
    end
    
    -- Suppress button state
    row.suppressBtn:SetActive(isSuppressed)
    row.suppressBtn.OnClick = function(btn, mouseBtn, isActive)
        if MedaDebug.ErrorHandler then
            if isActive then
                MedaDebug.ErrorHandler:SuppressError(data)
            else
                MedaDebug.ErrorHandler:UnsuppressError(data)
            end
        end
    end
    
    -- Copy button
    row.copyBtn.text:SetTextColor(unpack(Theme.textDim))
    row.copyBtn:SetScript("OnClick", function()
        self:CopyError(data)
    end)
    row.copyBtn:SetScript("OnEnter", function(btn)
        btn.text:SetTextColor(unpack(Theme.text))
    end)
    row.copyBtn:SetScript("OnLeave", function(btn)
        btn.text:SetTextColor(unpack(Theme.textDim))
    end)
    
    -- Dim the whole row when suppressed
    row:SetAlpha(isSuppressed and 0.6 or 1.0)
    
    -- Row click to select
    row:EnableMouse(true)
    row:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            self:SelectError(data)
        end
    end)
    
    -- Selection highlight
    if self.selectedError == data.id then
        row:SetBackdropColor(0.3, 0.3, 0.5, 0.5)
    else
        row:SetBackdropColor(0, 0, 0, 0)
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
    self.scrollList:Refresh()
    
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
        self.scrollList:Refresh()
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

function ErrorsTab:OnShow()
    self:RefreshData()
end

function ErrorsTab:OnFilterChanged(filter)
    self.currentFilter = filter
    self:RefreshData()
end

function ErrorsTab:OnSearch(text)
    self.searchText = text or ""
    self:RefreshData()
end
