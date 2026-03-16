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
MainHost.knownMessageAddons = {}

local TOOLBAR_WIDTH = 520

local function GetFrameState()
    return MedaDebug.db and MedaDebug.db.frameState
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
    self.workspace:SetFreshnessSources({
        {
            id = "session",
            label = "Session",
            lastFetched = sessionStart,
            color = MedaUI.Theme and MedaUI.Theme.gold or { 0.9, 0.7, 0.15, 1 },
        },
        {
            id = "runtime",
            label = "Runtime",
            lastFetched = time(),
            color = MedaUI.Theme and MedaUI.Theme.textDim or { 0.65, 0.65, 0.65, 1 },
        },
    })
end

function MainHost:RefreshFilterDropdown()
    if not self.filterDropdown then
        return
    end

    local options = {
        { value = "all", label = "All Addons" },
    }
    wipe(self.knownMessageAddons)

    if MedaDebug.OutputManager then
        local addons = MedaDebug.OutputManager:GetAddonsFromMessages()
        for _, addon in ipairs(addons) do
            self.knownMessageAddons[addon] = true
            options[#options + 1] = { value = addon, label = addon }
        end
    end

    self.filterDropdown:SetOptions(options)
    self.filterDropdown:SetSelected(self.currentFilter or "all")
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
                        module:OnFilterChanged(self.currentFilter)
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
                        module:OnFilterChanged(self.currentFilter)
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
    self.workspace:SetActivePage(pageId)
    self:ApplyPageChrome(pageId)
    self.workspace:RefreshActivePage()
    if self.workspace.ScheduleLayoutRefresh and self:IsShown() then
        self.workspace:ScheduleLayoutRefresh(true)
    end
    self:RefreshFilterDropdown()
    self:UpdateErrorBadge()

    if MedaDebug.db then
        MedaDebug.db.frameState.activeTab = pageId
        MedaDebug.db.frameState.filter = self.currentFilter
    end
end

function MainHost:InitializeToolbar()
    local toolbar = self.workspace:GetToolbar()

    self.filterDropdown = MedaUI:CreateDropdown(toolbar, 108, {
        { value = "all", label = "All Addons" },
    })
    self.filterDropdown:SetPoint("LEFT", 0, 0)
    self.filterDropdown.OnValueChanged = function(_, value)
        self.currentFilter = value
        if MedaDebug.db then
            MedaDebug.db.frameState.filter = value
        end
        local module = self:GetActiveModule()
        if module and module.OnFilterChanged then
            module:OnFilterChanged(value)
        end
    end

    self.clearBtn = MedaUI:CreateButton(toolbar, "Clear", 48, 22)
    self.clearBtn:SetPoint("LEFT", self.filterDropdown, "RIGHT", 6, 0)
    self.clearBtn:SetScript("OnClick", function()
        self:ClearCurrentPage()
    end)

    self.copyBtn = MedaUI:CreateButton(toolbar, "Copy", 44, 22)
    self.copyBtn:SetPoint("LEFT", self.clearBtn, "RIGHT", 6, 0)
    self.copyBtn:SetScript("OnClick", function()
        self:CopyCurrentPage()
    end)

    self.reloadBtn = MedaUI:CreateButton(toolbar, "/reload", 52, 22)
    self.reloadBtn:SetPoint("LEFT", self.copyBtn, "RIGHT", 6, 0)
    self.reloadBtn:SetScript("OnClick", function()
        ReloadUI()
    end)

    self.gcBtn = MedaUI:CreateButton(toolbar, "GC", 32, 22)
    self.gcBtn:SetPoint("LEFT", self.reloadBtn, "RIGHT", 6, 0)
    self.gcBtn:SetScript("OnClick", function()
        local before = collectgarbage("count")
        collectgarbage("collect")
        local after = collectgarbage("count")
        MedaDebug:LogInternal("MedaDebug", string.format("Garbage collected: %.1f KB freed", before - after), "INFO")
    end)

    self.searchBox = MedaUI:CreateSearchBox(toolbar, 128)
    self.searchBox:SetPoint("LEFT", self.gcBtn, "RIGHT", 6, 0)
    self.searchBox:SetPlaceholder("Search...")
    self.searchBox.OnSearch = function(_, text)
        self.searchText = text or ""
        local module = self:GetActiveModule()
        if module and module.OnSearch then
            module:OnSearch(self.searchText)
        end
    end

    self.settingsBtn = MedaUI:CreateButton(toolbar, "Settings", 60, 22)
    self.settingsBtn:SetPoint("LEFT", self.searchBox, "RIGHT", 6, 0)
    self.settingsBtn:SetScript("OnClick", function()
        if MedaDebug.ToggleSettings then
            MedaDebug:ToggleSettings()
        end
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
    self.currentFilter = frameState and frameState.filter or "all"
    self.searchText = ""

    self.frame = MedaUI:CreatePanel("MedaDebugFrame", 980, 620, "MedaDebug")
    self.frame:SetResizable(true, {
        minWidth = 760,
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
end

function MainHost:UpdateErrorBadge()
    if not self.workspace then
        return
    end
    self:BuildNavigation()
end

function MainHost:HandleNewMessage(entry, isUpdate)
    if entry == nil then
        self:RefreshFilterDropdown()
    elseif entry.addon and not self.knownMessageAddons[entry.addon] then
        self:RefreshFilterDropdown()
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
    self:UpdateErrorBadge()

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
