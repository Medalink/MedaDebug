--[[
    MedaDebug Main Host
    Workspace host and page registry for the runtime debug UI
]]

local _, MedaDebug = ...
local MedaUI = LibStub("MedaUI-2.0")
local tinsert = table.insert
local WorkspaceRegistry = MedaDebug.WorkspaceRegistry

local MainHost = {}
MedaDebug.MainHost = MainHost

MainHost.frame = nil
MainHost.workspace = nil
MainHost.activeTab = "messages"
MainHost.currentFilter = "all"
MainHost.searchText = ""
MainHost.pageFilters = nil
MainHost.knownMessageFilters = {}
MainHost.pageToolbars = nil

local TOOLBAR_WIDTH = 680

local function GetFrameState()
    return MedaDebug.db and MedaDebug.db.frameState
end

local function EnsurePageFilters(frameState)
    if not frameState then
        return {
            messages = "all",
            errors = "all",
        }
    end

    local legacyFilter = frameState.filter or "all"
    local pageFilters = frameState.pageFilters
    if type(pageFilters) ~= "table" then
        pageFilters = {
            messages = legacyFilter,
            errors = legacyFilter,
        }
        frameState.pageFilters = pageFilters
        return pageFilters
    end

    if pageFilters.messages == nil then
        pageFilters.messages = legacyFilter
    end
    if pageFilters.errors == nil then
        pageFilters.errors = legacyFilter
    end

    return pageFilters
end

local function SaveWindowState(state)
    local frameState = GetFrameState()
    if not frameState or not state then
        return
    end

    frameState.position = state.position
    frameState.size = state.size
end

local function GetPageModule(pageId)
    local page = WorkspaceRegistry and WorkspaceRegistry:GetPage(pageId)
    if not page then
        return nil
    end
    return MedaDebug[page.moduleKey]
end

function MainHost:GetActiveModule()
    return GetPageModule(self.activeTab)
end

function MainHost:GetPageDefinition(pageId)
    if not WorkspaceRegistry then
        return nil
    end

    return WorkspaceRegistry:GetPage(pageId)
end

function MainHost:GetFilterForPage(pageId)
    if not self.pageFilters then
        return "all"
    end

    return self.pageFilters[pageId] or "all"
end

function MainHost:SetFilterForPage(pageId, filterValue)
    if not pageId then
        return
    end

    self.pageFilters = self.pageFilters or {}
    self.pageFilters[pageId] = filterValue or "all"

    if MedaDebug.db and MedaDebug.db.frameState then
        MedaDebug.db.frameState.pageFilters = self.pageFilters
        if pageId == self.activeTab then
            MedaDebug.db.frameState.filter = self.pageFilters[pageId]
        end
    end
end

function MainHost:GetToolbarState(pageId)
    local page = self:GetPageDefinition(pageId)
    local module = GetPageModule(pageId)

    return {
        page = page,
        module = module,
        showAddonFilter = page and page.useAddonFilter == true or false,
        showSearch = page and page.useGlobalSearch == true or false,
        showClear = page and page.useGlobalClear == true or false,
        showCopy = page and page.useGlobalCopy == true or false,
    }
end

function MainHost:EnsurePageToolbar(pageId)
    local module = GetPageModule(pageId)
    if not module or not module.BuildToolbar or not self.pageToolbarHost then
        return nil, module
    end

    self.pageToolbars = self.pageToolbars or {}

    local toolbarFrame = self.pageToolbars[pageId]
    if not toolbarFrame then
        toolbarFrame = CreateFrame("Frame", nil, self.pageToolbarHost)
        toolbarFrame:SetAllPoints()
        toolbarFrame:Hide()
        self.pageToolbars[pageId] = toolbarFrame
        module:BuildToolbar(toolbarFrame, self)
    end

    return toolbarFrame, module
end

function MainHost:RefreshPageToolbar(pageId)
    if self.pageToolbars then
        for _, frame in pairs(self.pageToolbars) do
            frame:Hide()
        end
    end

    local toolbarFrame, module = self:EnsurePageToolbar(pageId)
    if toolbarFrame then
        toolbarFrame:Show()
    end

    if module and module.RefreshToolbar then
        module:RefreshToolbar(toolbarFrame, self)
    end
end

function MainHost:LayoutToolbar(pageId)
    if not self.workspace then
        return
    end

    local toolbar = self.workspace:GetToolbar()
    local state = self:GetToolbarState(pageId)
    local previous
    local gap = 6

    local function PlaceRight(control)
        control:ClearAllPoints()
        if previous then
            control:SetPoint("RIGHT", previous, "LEFT", -gap, 0)
        else
            control:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
        end
        previous = control
    end

    self.actionsBtn:Show()
    PlaceRight(self.actionsBtn)

    if state.showSearch then
        self.searchBox:Show()
        PlaceRight(self.searchBox)
    else
        self.searchBox:Hide()
    end

    if state.showCopy then
        self.copyBtn:Show()
        PlaceRight(self.copyBtn)
    else
        self.copyBtn:Hide()
    end

    if state.showClear then
        self.clearBtn:Show()
        PlaceRight(self.clearBtn)
    else
        self.clearBtn:Hide()
    end

    if state.showAddonFilter then
        self.filterDropdown:Show()
        PlaceRight(self.filterDropdown)
    else
        self.filterDropdown:Hide()
    end

    self.pageToolbarHost:ClearAllPoints()
    self.pageToolbarHost:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 0, 0)
    if previous then
        self.pageToolbarHost:SetPoint("BOTTOMRIGHT", previous, "LEFT", -12, 0)
    else
        self.pageToolbarHost:SetPoint("BOTTOMRIGHT", toolbar, "BOTTOMRIGHT", 0, 0)
    end

    self:RefreshPageToolbar(pageId)
end

function MainHost:BuildNavigation()
    local frameState = GetFrameState()
    local groupState = frameState and frameState.navGroups or {}
    local errorCount = MedaDebug.ErrorHandler and MedaDebug.ErrorHandler:GetVisibleErrorCount() or 0
    local items = WorkspaceRegistry and WorkspaceRegistry:BuildNavigation(groupState, {
        errorCount = errorCount,
    }) or {}

    self.workspace:SetNavigation(items)
end

function MainHost:UpdateFreshness()
    local sessionStart = MedaDebug.log and MedaDebug.log.session and MedaDebug.log.session.startTime or 0
    local messageCount = MedaDebug.OutputManager and MedaDebug.OutputManager:GetMessageCount() or 0
    local visibleErrors = MedaDebug.ErrorHandler and MedaDebug.ErrorHandler:GetVisibleErrorCount() or 0
    local suppressedErrors = MedaDebug.ErrorHandler and MedaDebug.ErrorHandler:GetSuppressedErrorCount() or 0
    local activeMonitors = {}

    if MedaDebug.EventMonitor and MedaDebug.EventMonitor:IsEnabled() then
        activeMonitors[#activeMonitors + 1] = "events"
    end
    if MedaDebug.TimerTracker and MedaDebug.TimerTracker:IsEnabled() then
        activeMonitors[#activeMonitors + 1] = "timers"
    end
    if MedaDebug.SystemMonitor and MedaDebug.SystemMonitor:IsEnabled() then
        activeMonitors[#activeMonitors + 1] = "system"
    end

    local monitorText = #activeMonitors > 0 and table.concat(activeMonitors, ", ") or "idle"
    if self.workspace and self.workspace.navFreshness and self.workspace.navFreshness.label then
        self.workspace.navFreshness.label:SetText("Debug State")
    end

    self.workspace:SetFreshnessSources({
        {
            id = "session",
            label = "Session",
            lastFetched = sessionStart,
            color = MedaUI.Theme and MedaUI.Theme.gold or { 0.9, 0.7, 0.15, 1 },
        },
        {
            id = "messages",
            label = "Messages",
            detailText = tostring(messageCount),
            color = MedaUI.Theme and MedaUI.Theme.textDim or { 0.65, 0.65, 0.65, 1 },
        },
        {
            id = "errors",
            label = "Errors",
            detailText = suppressedErrors > 0
                and string.format("%d visible, %d muted", visibleErrors, suppressedErrors)
                or string.format("%d visible", visibleErrors),
            color = visibleErrors > 0
                and (MedaUI.Theme and MedaUI.Theme.error or { 1, 0.3, 0.3, 1 })
                or (MedaUI.Theme and MedaUI.Theme.textDim or { 0.65, 0.65, 0.65, 1 }),
        },
        {
            id = "monitors",
            label = "Monitors",
            detailText = monitorText,
            color = #activeMonitors > 0
                and (MedaUI.Theme and MedaUI.Theme.warning or { 1, 0.7, 0.2, 1 })
                or (MedaUI.Theme and MedaUI.Theme.textDim or { 0.65, 0.65, 0.65, 1 }),
        },
    })
end

function MainHost:RefreshFilterDropdown()
    if not self.filterDropdown then
        return
    end

    local options
    if self.activeTab == "messages" and MedaDebug.OutputManager and MedaDebug.OutputManager.GetMessageFilterOptions then
        options = MedaDebug.OutputManager:GetMessageFilterOptions()
        wipe(self.knownMessageFilters)
        for i = 1, #options do
            self.knownMessageFilters[options[i].value] = true
        end
    else
        options = {
            { value = "all", label = "All Addons" },
        }

        if MedaDebug.ErrorHandler and MedaDebug.ErrorHandler.GetAddonsFromErrors then
            local addons = MedaDebug.ErrorHandler:GetAddonsFromErrors()
            for _, addon in ipairs(addons) do
                options[#options + 1] = { value = addon, label = addon }
            end
        elseif MedaDebug.OutputManager then
            local addons = MedaDebug.OutputManager:GetAddonsFromMessages()
            for _, addon in ipairs(addons) do
                options[#options + 1] = { value = addon, label = addon }
            end
        end
    end

    local selected = self:GetFilterForPage(self.activeTab)
    local hasSelected = false
    for i = 1, #options do
        if options[i].value == selected then
            hasSelected = true
            break
        end
    end
    if not hasSelected then
        selected = "all"
        self:SetFilterForPage(self.activeTab, selected)
        self.currentFilter = selected

        local module = self:GetActiveModule()
        if module and module.OnFilterChanged then
            module:OnFilterChanged(selected)
        end
    end

    self.filterDropdown:SetOptions(options)
    self.filterDropdown:SetSelected(selected)
end

function MainHost:ApplyPageChrome(pageId)
    local page = WorkspaceRegistry and WorkspaceRegistry:GetPage(pageId)
    if not page then
        return
    end

    self.workspace:SetPageTitle(page.title, page.subtitle)
    self.workspace:SetPageSummary(page.summary)
end

function MainHost:RegisterPages()
    local pages = WorkspaceRegistry and WorkspaceRegistry:GetPages() or {}
    for pageId, page in pairs(pages) do
        self.workspace:RegisterPage(pageId, {
            height = page.height,
            build = function(parent)
                local module = GetPageModule(pageId)
                if module and module.Initialize then
                    module:Initialize(parent)
                    if module.OnFilterChanged then
                        module:OnFilterChanged(self:GetFilterForPage(pageId))
                    end
                    if module.OnSearch then
                        module:OnSearch(self.searchText or "")
                    end
                    if module.OnShow then
                        module:OnShow()
                    end
                else
                    local placeholder = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    placeholder:SetPoint("CENTER")
                    placeholder:SetText(page.label .. " page is unavailable")
                    placeholder:SetTextColor(0.5, 0.5, 0.5)
                end
                return page.height
            end,
            onCacheRestore = function()
                local module = GetPageModule(pageId)
                if module then
                    if module.OnFilterChanged then
                        module:OnFilterChanged(self:GetFilterForPage(pageId))
                    end
                    if module.OnSearch then
                        module:OnSearch(self.searchText or "")
                    end
                    if module.OnShow then
                        module:OnShow()
                    end
                end
            end,
        })
    end
end

function MainHost:ShowPage(pageId)
    if not WorkspaceRegistry or not WorkspaceRegistry:GetPage(pageId) then
        return
    end

    self.activeTab = pageId
    self.currentFilter = self:GetFilterForPage(pageId)
    self:LayoutToolbar(pageId)
    self.workspace:SetActivePage(pageId)
    self:ApplyPageChrome(pageId)
    self.workspace:RefreshActivePage()
    if self.workspace.ScheduleLayoutRefresh and self:IsShown() then
        self.workspace:ScheduleLayoutRefresh(true)
    end
    self:UpdateFreshness()
    self:RefreshFilterDropdown()
    self:UpdateErrorBadge()

    if MedaDebug.db then
        MedaDebug.db.frameState.activeTab = pageId
        MedaDebug.db.frameState.filter = self.currentFilter
        MedaDebug.db.frameState.pageFilters = self.pageFilters
    end
end

function MainHost:InitializeToolbar()
    local toolbar = self.workspace:GetToolbar()

    self.pageToolbarHost = CreateFrame("Frame", nil, toolbar)

    self.filterDropdown = MedaUI:CreateDropdown(toolbar, 176, {
        { value = "all", label = "All Addons" },
    })
    self.filterDropdown.OnValueChanged = function(_, value)
        self.currentFilter = value
        self:SetFilterForPage(self.activeTab, value)
        local module = self:GetActiveModule()
        if module and module.OnFilterChanged then
            module:OnFilterChanged(value)
        end
    end

    self.clearBtn = MedaUI:CreateButton(toolbar, "Clear", 48, 22)
    self.clearBtn:SetScript("OnClick", function()
        self:ClearCurrentPage()
    end)

    self.copyBtn = MedaUI:CreateButton(toolbar, "Copy", 44, 22)
    self.copyBtn:SetScript("OnClick", function()
        self:CopyCurrentPage()
    end)

    self.searchBox = MedaUI:CreateSearchBox(toolbar, 128)
    self.searchBox:SetPlaceholder("Search...")
    self.searchBox.OnSearch = function(_, text)
        self.searchText = text or ""
        local module = self:GetActiveModule()
        if module and module.OnSearch then
            module:OnSearch(self.searchText)
        end
    end

    self.actionsBtn = MedaUI:CreateButton(toolbar, "Actions", 58, 22)
    self.actionsBtn:SetScript("OnClick", function()
        local menu = MedaUI:CreateContextMenu({
            {
                label = "Settings",
                onClick = function()
                    if MedaDebug.ToggleSettings then
                        MedaDebug:ToggleSettings()
                    end
                end,
            },
            {
                label = "Reload UI",
                onClick = function()
                    ReloadUI()
                end,
            },
            {
                label = "Collect Garbage",
                onClick = function()
                    local before = collectgarbage("count")
                    collectgarbage("collect")
                    local after = collectgarbage("count")
                    MedaDebug:LogInternal("MedaDebug", string.format("Garbage collected: %.1f KB freed", before - after), "INFO")
                end,
            },
        })
        menu:ShowAtCursor()
    end)
end

function MainHost:Initialize()
    if self.frame then
        return
    end

    local frameState = GetFrameState()
    local defaultPageId = WorkspaceRegistry and WorkspaceRegistry:GetDefaultPageId() or "messages"
    self.activeTab = frameState and frameState.activeTab or defaultPageId
    if WorkspaceRegistry and not WorkspaceRegistry:GetPage(self.activeTab) then
        self.activeTab = defaultPageId
    end
    self.pageFilters = EnsurePageFilters(frameState)
    self.currentFilter = self:GetFilterForPage(self.activeTab)
    self.searchText = ""

    self.frame = MedaUI:CreatePanel("MedaDebugFrame", 980, 620, "MedaDebug")
    self.frame:SetResizable(true, {
        minWidth = 900,
        minHeight = 480,
    })

    if frameState then
        self.frame:RestoreState(frameState)
    end

    self.frame.OnMove = function(_, state)
        SaveWindowState(state)
    end
    self.frame.OnResize = function(_, state)
        SaveWindowState(state)
    end

    if self.frame.closeButton then
        self.frame.closeButton:SetScript("OnClick", function()
            self:Hide()
        end)
    end

    self.workspace = MedaUI:CreateWorkspaceHost(self.frame:GetContent(), {
        navWidth = 210,
        toolbarWidth = TOOLBAR_WIDTH,
    })

    self.workspace.OnNavigate = function(_, pageId)
        self:ShowPage(pageId)
    end
    self.workspace.OnGroupToggle = function(_, groupId, expanded)
        if MedaDebug.db then
            MedaDebug.db.frameState.navGroups[groupId] = expanded
        end
        self:BuildNavigation()
    end

    self:RegisterPages()
    self:InitializeToolbar()
    self:BuildNavigation()
    self:UpdateFreshness()
    self:RefreshFilterDropdown()
    self.workspace:SetActivePage(self.activeTab)
    self:ShowPage(self.activeTab)

    local frameName = self.frame:GetName()
    if frameName then
        tinsert(UISpecialFrames, frameName)
    end

    self.frame:HookScript("OnShow", function()
        if MedaDebug.db then
            MedaDebug.db.frameState.isOpen = true
        end
        self:ShowPage(self.activeTab)
        if self.workspace and self.workspace.ScheduleLayoutRefresh then
            self.workspace:ScheduleLayoutRefresh(true)
        end
    end)
end

function MainHost:PersistState()
    if not self.frame or not MedaDebug.db then
        return
    end

    local defaultPageId = WorkspaceRegistry and WorkspaceRegistry:GetDefaultPageId() or "messages"

    local point, relativeTo, relativePoint, x, y = self.frame:GetPoint()
    if point then
        MedaDebug.db.frameState.position = {
            point = point,
            relativeTo = relativeTo and relativeTo:GetName() or nil,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end

    MedaDebug.db.frameState.size = {
        width = self.frame:GetWidth(),
        height = self.frame:GetHeight(),
    }
    MedaDebug.db.frameState.activeTab = self.activeTab or defaultPageId
    MedaDebug.db.frameState.filter = self.currentFilter or "all"
    MedaDebug.db.frameState.pageFilters = self.pageFilters
end

function MainHost:UpdateErrorBadge()
    if not self.workspace then
        return
    end
    self:BuildNavigation()
end

function MainHost:HandleNewMessage(entry, isUpdate)
    self:UpdateFreshness()

    if self.activeTab == "messages" then
        if entry == nil then
            self:RefreshFilterDropdown()
        elseif entry.addon and not self.knownMessageFilters[entry.addon] then
            self:RefreshFilterDropdown()
        elseif entry.sourceFilter and not self.knownMessageFilters[entry.sourceFilter] then
            self:RefreshFilterDropdown()
        end
    end

    local module = GetPageModule("messages")
    if not module or self.activeTab ~= "messages" or not self:IsShown() then
        return
    end

    if module.OnNewMessage then
        module:OnNewMessage(entry, isUpdate)
    end
end

function MainHost:HandleErrorChanged(kind, entry)
    self:UpdateFreshness()
    self:UpdateErrorBadge()

    if self.activeTab == "errors" and kind == "new" then
        self:RefreshFilterDropdown()
    end

    local module = GetPageModule("errors")
    if self.activeTab ~= "errors" or not self:IsShown() or not module then
        return
    end

    if kind == "new" and module.OnNewError then
        module:OnNewError(entry)
    elseif kind == "update" and module.OnErrorUpdated then
        module:OnErrorUpdated(entry)
    elseif module.RefreshData then
        module:RefreshData()
    end
end

function MainHost:ClearCurrentPage()
    local module = self:GetActiveModule()
    if module and module.Clear then
        module:Clear()
        return
    end

    if self.activeTab == "messages" and MedaDebug.OutputManager then
        MedaDebug.OutputManager:ClearAll()
    elseif self.activeTab == "errors" and MedaDebug.ErrorHandler then
        MedaDebug.ErrorHandler:ClearErrors()
    elseif self.activeTab == "events" and MedaDebug.EventMonitor then
        MedaDebug.EventMonitor:ClearEvents()
    end
end

function MainHost:CopyCurrentPage()
    local module = self:GetActiveModule()
    if module and module.Copy then
        module:Copy()
        return
    end

    if MedaDebug.OutputManager then
        local text = MedaDebug.OutputManager:GetMessagesForCopy()
        MedaUI:ShowTextViewer("Messages - Press Ctrl+C to copy", text)
    end
end

function MainHost:SetActiveTab(pageId)
    if not self.frame then
        self.activeTab = pageId
        return
    end
    self:ShowPage(pageId)
end

function MainHost:Show()
    self:Initialize()
    if self.frame then
        self.frame:Show()
    end
end

function MainHost:Hide()
    if not self.frame then
        return
    end
    self.frame:Hide()
    if MedaDebug.db then
        MedaDebug.db.frameState.isOpen = false
    end
end

function MainHost:Toggle()
    self:Initialize()
    if self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function MainHost:IsShown()
    return self.frame and self.frame:IsShown()
end
