--[[
    MedaDebug Dungeon Capture Tab
    Review and copy correlated object/NPC interaction captures.
]]

local _, MedaDebug = ...
local MedaUI = LibStub("MedaUI-2.0")

local DungeonCaptureTab = {}
MedaDebug.DungeonCaptureTab = DungeonCaptureTab

DungeonCaptureTab.frame = nil
DungeonCaptureTab.scrollList = nil
DungeonCaptureTab.detailBlock = nil
DungeonCaptureTab.selectedCaptureId = nil
DungeonCaptureTab.searchText = ""
DungeonCaptureTab.searchLower = nil
DungeonCaptureTab.viewData = nil

local CONFIDENCE_COLORS = {
    high = { 0.35, 0.9, 0.55, 1 },
    medium = { 0.95, 0.78, 0.28, 1 },
    low = { 0.75, 0.75, 0.75, 1 },
}

local DEFAULT_SELECTED_BACKDROP = { 0.3, 0.3, 0.5, 0.5 }
local DEFAULT_CLEAR_BACKDROP = { 0, 0, 0, 0 }

local function SetFontStringText(fontString, text)
    text = text or ""
    if fontString._medaText ~= text then
        fontString:SetText(text)
        fontString._medaText = text
    end
end

local function SetFontStringColor(fontString, color)
    color = color or { 1, 1, 1, 1 }
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

function DungeonCaptureTab:GetRuntime()
    return MedaDebug.DungeonObjectCapture
end

function DungeonCaptureTab:MatchesFilters(capture)
    if not self.searchLower then
        return true
    end

    local searchText = capture and capture.searchText
    return searchText and searchText:find(self.searchLower, 1, true) ~= nil or false
end

function DungeonCaptureTab:InitializeRow(row)
    if row._medaInitialized then
        return
    end

    row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.timeText:SetPoint("TOPLEFT", 8, -8)
    row.timeText:SetWidth(78)
    row.timeText:SetJustifyH("LEFT")

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.nameText:SetPoint("TOPLEFT", row.timeText, "TOPRIGHT", 8, 0)
    row.nameText:SetPoint("TOPRIGHT", -80, -8)
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetWordWrap(false)

    row.summaryText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.summaryText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -4)
    row.summaryText:SetPoint("TOPRIGHT", -120, -28)
    row.summaryText:SetJustifyH("LEFT")
    row.summaryText:SetWordWrap(false)

    row.confidenceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.confidenceText:SetPoint("TOPRIGHT", -8, -8)
    row.confidenceText:SetJustifyH("RIGHT")

    row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.statusText:SetPoint("TOPRIGHT", -8, -28)
    row.statusText:SetJustifyH("RIGHT")

    row:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and row.boundData then
            self:SelectCapture(row.boundData)
        end
    end)

    row._medaInitialized = true
end

function DungeonCaptureTab:RenderRow(row, capture)
    if not capture then
        return
    end

    self:InitializeRow(row)
    local Theme = MedaUI.Theme or MedaUI:GetTheme()

    row.boundData = capture

    local context = capture.context or {}
    local instance = context.instance or {}
    local contextLabel = context.name or "Unknown target"
    if instance.instanceName then
        contextLabel = contextLabel .. " |cff888888[" .. instance.instanceName .. "]|r"
    end

    SetFontStringText(row.timeText, context.datetime or "")
    SetFontStringColor(row.timeText, Theme.textDim)

    SetFontStringText(row.nameText, contextLabel)
    SetFontStringColor(row.nameText, Theme.gold)

    SetFontStringText(row.summaryText, capture.summary or context.name or "")
    SetFontStringColor(row.summaryText, Theme.text)

    SetFontStringText(row.confidenceText, string.upper(capture.confidence or "low"))
    SetFontStringColor(row.confidenceText, CONFIDENCE_COLORS[capture.confidence] or Theme.textDim)

    SetFontStringText(row.statusText, capture.status or "pending")
    SetFontStringColor(row.statusText, Theme.textDim)

    if self.selectedCaptureId == capture.id then
        row:SetBackdropColor(unpack(DEFAULT_SELECTED_BACKDROP))
    else
        row:SetBackdropColor(unpack(DEFAULT_CLEAR_BACKDROP))
    end
end

function DungeonCaptureTab:RefreshData()
    local runtime = self:GetRuntime()
    if not runtime or not self.scrollList then
        return
    end

    local captures = runtime:GetCaptures()
    local filtered = {}

    for index = 1, #captures do
        local capture = captures[index]
        if self:MatchesFilters(capture) then
            filtered[#filtered + 1] = capture
        end
    end

    self.viewData = filtered
    self.scrollList:SetData(filtered)

    if self.selectedCaptureId then
        local found = false
        for index = 1, #filtered do
            if filtered[index].id == self.selectedCaptureId then
                found = true
                self:UpdateDetails(filtered[index])
                break
            end
        end

        if not found then
            self.selectedCaptureId = nil
            self:UpdateDetails(filtered[1])
        end
    else
        self:UpdateDetails(filtered[1])
    end

    if self.countLabel then
        self.countLabel:SetText(string.format("%d captures", #filtered))
    end
end

function DungeonCaptureTab:SelectCapture(capture)
    self.selectedCaptureId = capture and capture.id or nil
    self:UpdateDetails(capture)
    if self.scrollList then
        self.scrollList:Refresh()
    end
end

function DungeonCaptureTab:UpdateDetails(capture)
    if not self.detailBlock then
        return
    end

    local runtime = self:GetRuntime()
    if not runtime then
        self.detailBlock:SetText("Dungeon object capture runtime unavailable.")
        return
    end

    if not capture then
        self.detailBlock:SetText("No captures recorded.")
        return
    end

    self.detailBlock:SetText(runtime:BuildCaptureReport(capture))
end

function DungeonCaptureTab:BuildToolbar(parent)
    local runtime = self:GetRuntime()

    self.enabledCheckbox = MedaUI:CreateCheckbox(parent, "Enabled")
    self.enabledCheckbox:SetPoint("LEFT", parent, "LEFT", 0, 0)
    self.enabledCheckbox.OnValueChanged = function(_, checked)
        MedaDebug.db.options.enableDungeonObjectCapture = checked
        if runtime then
            if checked then
                runtime:Enable()
            else
                runtime:Disable()
            end
        end
        self:RefreshToolbar()
        self:RefreshData()
    end

    self.countLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.countLabel:SetPoint("LEFT", self.enabledCheckbox, "RIGHT", 12, 0)
    self.countLabel:SetJustifyH("LEFT")
end

function DungeonCaptureTab:RefreshToolbar()
    local runtime = self:GetRuntime()
    if self.enabledCheckbox and runtime then
        self.enabledCheckbox:SetChecked(runtime:IsEnabled())
    end
    if self.countLabel and self.viewData then
        self.countLabel:SetText(string.format("%d captures", #self.viewData))
    end
end

function DungeonCaptureTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()
    local runtime = self:GetRuntime()

    self.scrollList = MedaUI:CreateScrollList(parent, parent:GetWidth(), 300, {
        rowHeight = 54,
        renderRow = function(row, data)
            self:RenderRow(row, data)
        end,
    })
    self.scrollList:SetPoint("TOPLEFT", 0, 0)
    self.scrollList:SetPoint("TOPRIGHT", 0, 0)
    self.scrollList:SetHeight(320)

    self.detailTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.detailTitle:SetPoint("TOPLEFT", self.scrollList, "BOTTOMLEFT", 0, -12)
    self.detailTitle:SetText("Selected Capture")
    self.detailTitle:SetTextColor(unpack(Theme.gold))

    self.detailBlock = MedaUI:CreateCodeBlock(parent, parent:GetWidth(), 420, {
        showLineNumbers = false,
    })
    self.detailBlock:SetPoint("TOPLEFT", self.detailTitle, "BOTTOMLEFT", 0, -8)
    self.detailBlock:SetPoint("BOTTOMRIGHT", 0, 0)

    if runtime then
        runtime.onDataChanged = function()
            if self.frame and self.frame:IsShown() then
                self:RefreshData()
            end
        end
    end

    self:RefreshToolbar()
    self:RefreshData()
end

function DungeonCaptureTab:OnShow()
    self:RefreshToolbar()
    self:RefreshData()
end

function DungeonCaptureTab:OnSearch(text)
    self.searchText = text or ""
    self.searchLower = self.searchText ~= "" and self.searchText:lower() or nil
    self:RefreshData()
end

function DungeonCaptureTab:Clear()
    local runtime = self:GetRuntime()
    if runtime then
        runtime:Clear()
    end
    self.selectedCaptureId = nil
    self:RefreshData()
end

function DungeonCaptureTab:Copy()
    local runtime = self:GetRuntime()
    if not runtime then
        MedaUI:ShowTextViewer("Dungeon Capture - Press Ctrl+C to copy", "Dungeon object capture runtime unavailable.")
        return
    end

    if self.selectedCaptureId and self.viewData then
        for index = 1, #self.viewData do
            if self.viewData[index].id == self.selectedCaptureId then
                MedaUI:ShowTextViewer("Dungeon Capture - Press Ctrl+C to copy", runtime:BuildCaptureReport(self.viewData[index]))
                return
            end
        end
    end

    MedaUI:ShowTextViewer("Dungeon Capture - Press Ctrl+C to copy", runtime:BuildCopyText(self.viewData or runtime:GetCaptures()))
end

if MedaDebug.WorkspaceRegistry then
    MedaDebug.WorkspaceRegistry:RegisterPage("dungeon-capture", {
        label = "Object Capture",
        title = "Dungeon Object Capture",
        subtitle = "Correlate hovered objects and NPCs with buffs, loot, and spell results.",
        summary = "Enable targeted capture runs here, then use the shared Copy button to export the current evidence set.",
        moduleKey = "DungeonCaptureTab",
        height = 1200,
        useGlobalSearch = true,
        useGlobalClear = true,
        useGlobalCopy = true,
        groupId = "runtime",
        groupLabel = "Runtime",
        groupOrder = 30,
        pageOrder = 40,
    })
end
