--[[
    MedaDebug Errors Tab
    Displays errors with smart formatting and hints
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local ErrorsTab = {}
MedaDebug.ErrorsTab = ErrorsTab

ErrorsTab.frame = nil
ErrorsTab.scrollList = nil
ErrorsTab.selectedError = nil

function ErrorsTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()
    
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
        row.mainText:SetPoint("TOPRIGHT", -120, -10)
        row.mainText:SetJustifyH("LEFT")
        row.mainText:SetWordWrap(false)
    end

    if not row.hintText then
        row.hintText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.hintText:SetPoint("TOPLEFT", 24, -30)
        row.hintText:SetPoint("TOPRIGHT", -120, -30)
        row.hintText:SetJustifyH("LEFT")
        row.hintText:SetWordWrap(false)
    end
    
    if not row.countText then
        row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.countText:SetPoint("TOPRIGHT", -60, -8)
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
    
    -- Main line: [!] [Addon] TYPE in file:line
    local mainLine = string.format("|cffff4444[!]|r |cff88bbff[%s]|r %s in %s:%d", 
        addonName, errorType, sourceFile, sourceLine)
    row.mainText:SetText(mainLine)
    
    -- Hint line
    row.hintText:SetText("|cff888888> " .. hint .. "|r")
    
    -- Count
    row.countText:SetText("(x" .. count .. ")")
    if count > 1 then
        row.countText:SetTextColor(unpack(Theme.levelWarn))
    else
        row.countText:SetTextColor(unpack(Theme.textDim))
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
    end
end

function ErrorsTab:RefreshData()
    if not self.scrollList or not MedaDebug.ErrorHandler then return end
    
    local errors = MedaDebug.ErrorHandler:GetErrors()
    self.scrollList:SetData(errors)
    self.scrollList:Refresh()
end

function ErrorsTab:OnNewError(entry)
    self:RefreshData()
    
    -- Auto-scroll to new error
    if MedaDebug.db and MedaDebug.db.options.autoScroll then
        self.scrollList:ScrollToBottom()
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
    -- Errors don't filter by addon currently
    self:RefreshData()
end

function ErrorsTab:OnSearch(text)
    -- TODO: Filter errors by search text
    self:RefreshData()
end
