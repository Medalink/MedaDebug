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
ErrorsTab.expandedErrors = {}
ErrorsTab.selectedError = nil

function ErrorsTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()
    
    -- Create scroll list
    self.scrollList = MedaUI:CreateScrollList(parent, parent:GetWidth(), parent:GetHeight(), {
        rowHeight = 50, -- Taller rows for error summary + hint
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
    local isExpanded = self.expandedErrors[data.id]
    
    -- Create elements if needed
    if not row.icon then
        row.icon = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.icon:SetPoint("TOPLEFT", 4, -4)
        row.icon:SetText("[!]")
    end
    
    if not row.addonLabel then
        row.addonLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.addonLabel:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    end
    
    if not row.countLabel then
        row.countLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.countLabel:SetPoint("RIGHT", -4, 8)
    end
    
    if not row.summary then
        row.summary = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.summary:SetPoint("TOPLEFT", 24, -4)
        row.summary:SetPoint("RIGHT", row.countLabel, "LEFT", -8, 0)
        row.summary:SetJustifyH("LEFT")
        row.summary:SetWordWrap(false)
    end
    
    if not row.hint then
        row.hint = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.hint:SetPoint("TOPLEFT", 32, -22)
        row.hint:SetPoint("RIGHT", -40, 0)
        row.hint:SetJustifyH("LEFT")
        row.hint:SetWordWrap(false)
    end
    
    if not row.expandBtn then
        row.expandBtn = CreateFrame("Button", nil, row)
        row.expandBtn:SetSize(60, 16)
        row.expandBtn:SetPoint("BOTTOMRIGHT", -4, 4)
        row.expandBtn.text = row.expandBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.expandBtn.text:SetPoint("CENTER")
        row.expandBtn.text:SetTextColor(unpack(Theme.textDim))
    end
    
    if not row.copyBtn then
        row.copyBtn = CreateFrame("Button", nil, row)
        row.copyBtn:SetSize(40, 16)
        row.copyBtn:SetPoint("RIGHT", row.expandBtn, "LEFT", -4, 0)
        row.copyBtn.text = row.copyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.copyBtn.text:SetPoint("CENTER")
        row.copyBtn.text:SetText("Copy")
        row.copyBtn.text:SetTextColor(unpack(Theme.textDim))
    end
    
    -- Set values
    row.icon:SetTextColor(unpack(Theme.levelError))
    
    local summary = data.summary or {}
    row.addonLabel:SetText(summary.sourceAddon or "Unknown")
    row.addonLabel:SetTextColor(0.6, 0.8, 1)
    
    row.summary:SetText(string.format("%s in %s:%d", 
        summary.type or "ERROR",
        summary.sourceFile or "?",
        summary.sourceLine or 0
    ))
    row.summary:SetTextColor(unpack(Theme.text))
    
    row.hint:SetText("└─ " .. (summary.hint or "No hint available"))
    row.hint:SetTextColor(unpack(Theme.textDim))
    
    local occurrences = data.occurrences or {}
    local count = occurrences.count or 1
    row.countLabel:SetText("(x" .. count .. ")")
    row.countLabel:SetTextColor(count > 1 and unpack(Theme.levelWarn) or unpack(Theme.textDim))
    
    -- Expand button
    row.expandBtn.text:SetText(isExpanded and "[Less]" or "[More]")
    row.expandBtn:SetScript("OnClick", function()
        self:ToggleExpand(data.id)
    end)
    row.expandBtn:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(Theme.text))
    end)
    row.expandBtn:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(Theme.textDim))
    end)
    
    -- Copy button
    row.copyBtn:SetScript("OnClick", function()
        self:CopyError(data)
    end)
    row.copyBtn:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(Theme.text))
    end)
    row.copyBtn:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(Theme.textDim))
    end)
    
    -- Click to select
    row:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            self:SelectError(data)
        end
    end)
    
    -- Selection highlight
    if self.selectedError == data.id then
        row:SetBackdropColor(unpack(Theme.highlight))
    end
end

function ErrorsTab:RefreshData()
    if not self.scrollList or not MedaDebug.ErrorHandler then return end
    
    local errors = MedaDebug.ErrorHandler:GetErrors()
    self.scrollList:SetData(errors)
end

function ErrorsTab:OnNewError(entry)
    self:RefreshData()
    
    -- Auto-scroll to new error
    if MedaDebug.db and MedaDebug.db.options.autoScroll then
        self.scrollList:ScrollToBottom()
    end
end

function ErrorsTab:ToggleExpand(errorId)
    self.expandedErrors[errorId] = not self.expandedErrors[errorId]
    self.scrollList:Refresh()
end

function ErrorsTab:SelectError(data)
    self.selectedError = data.id
    _G.SELECTED = data -- For console access
    self.scrollList:Refresh()
end

function ErrorsTab:CopyError(data)
    if not MedaDebug.ErrorHandler then return end
    
    local text = MedaDebug.ErrorHandler:FormatForCopy(data)
    
    -- Show copy dialog
    if MedaUI.copyDialog then
        MedaUI.copyDialog.editBox:SetText(text)
        MedaUI.copyDialog.editBox:HighlightText()
        MedaUI.copyDialog:Show()
    else
        -- Fallback: create simple dialog
        StaticPopupDialogs["MEDADEBUG_COPY"] = {
            text = "Press Ctrl+C to copy",
            button1 = "Close",
            hasEditBox = true,
            editBoxWidth = 350,
            OnShow = function(self)
                self.editBox:SetText(text)
                self.editBox:HighlightText()
                self.editBox:SetFocus()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("MEDADEBUG_COPY")
    end
end

function ErrorsTab:Clear()
    if MedaDebug.ErrorHandler then
        MedaDebug.ErrorHandler:ClearErrors()
    end
    wipe(self.expandedErrors)
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
