--[[
    MedaDebug Profiler Tab
    Lightweight performance view for MedaDebug hot paths
]]

local _, MedaDebug = ...
local MedaUI = LibStub("MedaUI-2.0")

local ProfilerTab = {}
MedaDebug.ProfilerTab = ProfilerTab

ProfilerTab.frame = nil
ProfilerTab.scrollList = nil
ProfilerTab.categoryFilter = "all"
ProfilerTab.searchText = ""

local PROFILER_CATEGORIES = {
    { value = "all", label = "All Categories" },
    { value = "ui", label = "UI" },
    { value = "event", label = "Events" },
    { value = "timer", label = "Timers" },
    { value = "frame", label = "Frames" },
    { value = "output", label = "Output" },
    { value = "system", label = "System" },
}

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

function ProfilerTab:BuildToolbar(parent)
    local Theme = MedaUI.Theme or MedaUI:GetTheme()

    self.enabledCheckbox = MedaUI:CreateCheckbox(parent, "Capture")
    self.enabledCheckbox:SetPoint("LEFT", parent, "LEFT", 0, 0)
    self.enabledCheckbox.OnValueChanged = function(_, checked)
        if MedaDebug.ProfilerLite then
            MedaDebug.ProfilerLite:SetEnabled(checked)
        end
        self:RefreshData()
    end

    self.categoryDropdown = MedaUI:CreateDropdown(parent, 120, PROFILER_CATEGORIES)
    self.categoryDropdown:SetPoint("LEFT", self.enabledCheckbox, "RIGHT", 10, 0)
    self.categoryDropdown.OnValueChanged = function(_, value)
        self.categoryFilter = value
        self:RefreshData()
    end

    self.summaryText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.summaryText:SetPoint("LEFT", self.categoryDropdown, "RIGHT", 10, 0)
    self.summaryText:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    self.summaryText:SetJustifyH("LEFT")
    self.summaryText:SetWordWrap(false)
    self.summaryText:SetTextColor(unpack(Theme.textDim))
end

function ProfilerTab:RefreshToolbar()
    if self.categoryDropdown then
        self.categoryDropdown:SetSelected(self.categoryFilter or "all")
    end
    self:RefreshData()
end

function ProfilerTab:Initialize(parent)
    self.frame = parent
    self.scrollList = MedaUI:CreateScrollList(parent, parent:GetWidth(), parent:GetHeight(), {
        rowHeight = 24,
        renderRow = function(row, data)
            self:RenderRow(row, data)
        end,
    })
    self.scrollList:SetPoint("TOPLEFT", 0, 0)
    self.scrollList:SetPoint("BOTTOMRIGHT", 0, 0)

    if MedaDebug.ProfilerLite then
        MedaDebug.ProfilerLite.onUpdated = function()
            if self.frame and self.frame:IsShown() then
                self:RefreshData()
            end
        end
    end

    self:RefreshData()
end

function ProfilerTab:RenderRow(row, data)
    if not data then
        return
    end

    local Theme = MedaUI:GetTheme()

    if not row.category then
        row.category = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.category:SetPoint("LEFT", 4, 0)
        row.category:SetWidth(55)
        row.category:SetJustifyH("LEFT")
    end

    if not row.name then
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row.category, "RIGHT", 8, 0)
        row.name:SetWidth(180)
        row.name:SetJustifyH("LEFT")
    end

    if not row.count then
        row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.count:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        row.count:SetWidth(50)
        row.count:SetJustifyH("RIGHT")
    end

    if not row.avg then
        row.avg = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.avg:SetPoint("LEFT", row.count, "RIGHT", 8, 0)
        row.avg:SetWidth(65)
        row.avg:SetJustifyH("RIGHT")
    end

    if not row.max then
        row.max = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.max:SetPoint("LEFT", row.avg, "RIGHT", 8, 0)
        row.max:SetWidth(65)
        row.max:SetJustifyH("RIGHT")
    end

    if not row.total then
        row.total = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.total:SetPoint("LEFT", row.max, "RIGHT", 8, 0)
        row.total:SetWidth(75)
        row.total:SetJustifyH("RIGHT")
    end

    if not row.source then
        row.source = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.source:SetPoint("LEFT", row.total, "RIGHT", 8, 0)
        row.source:SetPoint("RIGHT", -8, 0)
        row.source:SetJustifyH("LEFT")
        row.source:SetWordWrap(false)
    end

    row.category:SetText(data.category or "?")
    row.category:SetTextColor(unpack(Theme.gold))

    row.name:SetText(data.name or "?")
    row.name:SetTextColor(unpack(Theme.text))

    row.count:SetText(tostring(data.count or 0))
    row.count:SetTextColor(unpack(Theme.textDim))

    row.avg:SetText(string.format("%.2fms", data.avgMs or 0))
    row.avg:SetTextColor(unpack(Theme.textDim))

    row.max:SetText(string.format("%.2fms", data.maxMs or 0))
    row.max:SetTextColor(unpack(Theme.levelWarn))

    row.total:SetText(string.format("%.1fms", data.totalMs or 0))
    row.total:SetTextColor(unpack(Theme.text))

    row.source:SetText(data.source or "")
    row.source:SetTextColor(unpack(Theme.textDim))
end

function ProfilerTab:RefreshData()
    if not self.scrollList or not MedaDebug.ProfilerLite then
        return
    end

    self.enabledCheckbox:SetChecked(MedaDebug.ProfilerLite:IsEnabled())

    local rows = MedaDebug.ProfilerLite:GetStats(self.categoryFilter)
    if self.searchText ~= "" then
        local filtered = {}
        local search = self.searchText:lower()
        for _, row in ipairs(rows) do
            if SafeContains(row.name, search) or
               SafeContains(row.category, search) or
               SafeContains(row.source, search) then
                filtered[#filtered + 1] = row
            end
        end
        rows = filtered
    end

    self.scrollList:SetData(rows)

    local summary = MedaDebug.ProfilerLite:GetSummary()
    self.summaryText:SetText(string.format("%d metrics / %.1fms total", summary.entries or 0, summary.totalMs or 0))
end

function ProfilerTab:OnShow()
    self:RefreshData()
end

function ProfilerTab:OnFilterChanged(filter)
    -- Uses category filter instead of addon filter.
end

function ProfilerTab:OnSearch(text)
    self.searchText = text or ""
    self:RefreshData()
end

function ProfilerTab:Clear()
    if MedaDebug.ProfilerLite then
        MedaDebug.ProfilerLite:Clear()
    end
end

if MedaDebug.WorkspaceRegistry then
    MedaDebug.WorkspaceRegistry:RegisterPage("perf", {
        label = "Profiler",
        title = "Profiler",
        subtitle = "Lightweight timings for MedaDebug hot paths.",
        summary = "Use this to inspect UI, timer, and output costs while the workspace is open.",
        moduleKey = "ProfilerTab",
        height = 1000,
        useGlobalSearch = true,
        useGlobalClear = true,
        groupId = "runtime",
        groupLabel = "Runtime",
        groupOrder = 30,
        pageOrder = 10,
    })
end
