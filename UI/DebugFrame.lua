--[[
    MedaDebug Debug Frame
    Main tabbed debug window
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local DebugFrame = {}
MedaDebug.DebugFrame = DebugFrame

-- Frame state
DebugFrame.frame = nil
DebugFrame.tabBar = nil
DebugFrame.tabContents = {}
DebugFrame.activeTab = "messages"
DebugFrame.currentFilter = "all"

-- Tab definitions
local TABS = {
    {id = "messages", label = "Msgs"},
    {id = "errors", label = "Errors", badge = 0},
    {id = "events", label = "Events"},
    {id = "console", label = "Console"},
    {id = "inspector", label = "Inspect"},
    {id = "watch", label = "Watch"},
    {id = "timers", label = "Timers"},
    {id = "system", label = "Sys"},
}

function DebugFrame:Initialize()
    if self.frame then return end
    
    local Theme = MedaUI:GetTheme()
    
    -- Create main panel
    local frameState = MedaDebug.db.frameState
    local width = frameState.size.width or 700
    local height = frameState.size.height or 500
    
    self.frame = MedaUI:CreatePanel("MedaDebugFrame", width, height, "MedaDebug")
    self.frame:SetResizable(true, {
        minWidth = 500,
        minHeight = 400,
        maxWidth = 1400,
        maxHeight = 900,
    })
    
    -- Override close button to use our Hide method (saves state)
    if self.frame.closeButton then
        self.frame.closeButton:SetScript("OnClick", function()
            self:Hide()
        end)
    end
    
    -- Restore position
    local pos = frameState.position
    if pos and pos.point then
        self.frame:ClearAllPoints()
        local relativeTo = pos.relativeTo and _G[pos.relativeTo] or UIParent
        self.frame:SetPoint(pos.point, relativeTo, pos.relativePoint, pos.x, pos.y)
    end
    
    -- Handle resize
    self.frame.OnResize = function(_, w, h)
        self:OnResize(w, h)
    end
    
    local content = self.frame:GetContent()
    
    -- Main content wrapper with darker background
    self.mainContent = CreateFrame("Frame", nil, content, "BackdropTemplate")
    self.mainContent:SetPoint("TOPLEFT", 0, 0)
    self.mainContent:SetPoint("BOTTOMRIGHT", 0, 0)
    self.mainContent:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    self.mainContent:SetBackdropColor(unpack(Theme.backgroundDark))
    
    -- Toolbar area (tabs + filter row)
    self.toolbar = CreateFrame("Frame", nil, self.mainContent, "BackdropTemplate")
    self.toolbar:SetHeight(56)
    self.toolbar:SetPoint("TOPLEFT", 0, 0)
    self.toolbar:SetPoint("TOPRIGHT", 0, 0)
    self.toolbar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    self.toolbar:SetBackdropColor(unpack(Theme.background))
    
    -- Tab bar (full width on first row)
    self.tabBar = MedaUI:CreateTabBar(self.toolbar, TABS)
    self.tabBar:SetPoint("TOPLEFT", 4, -4)
    self.tabBar:SetPoint("TOPRIGHT", -4, -4)
    self.tabBar.OnTabChanged = function(_, tabId, prevTab)
        self:OnTabChanged(tabId, prevTab)
    end
    
    -- Toolbar separator line
    local toolbarSep = self.toolbar:CreateTexture(nil, "OVERLAY")
    toolbarSep:SetHeight(1)
    toolbarSep:SetPoint("BOTTOMLEFT", 0, 0)
    toolbarSep:SetPoint("BOTTOMRIGHT", 0, 0)
    toolbarSep:SetColorTexture(unpack(Theme.border))
    
    -- Second row: Filter dropdown, Clear, Bookmark, Search
    -- Filter dropdown
    self.filterDropdown = MedaUI:CreateDropdown(self.toolbar, 120, {
        {value = "all", label = "All Addons"},
    })
    self.filterDropdown:SetPoint("TOPLEFT", 4, -30)
    self.filterDropdown.OnValueChanged = function(_, value)
        self:OnFilterChanged(value)
    end
    
    -- Clear button
    self.clearBtn = MedaUI:CreateButton(self.toolbar, "Clear", 60, 22)
    self.clearBtn:SetPoint("LEFT", self.filterDropdown, "RIGHT", 8, 0)
    self.clearBtn:SetScript("OnClick", function()
        self:ClearCurrentTab()
    end)
    
    -- Bookmark indicator
    self.bookmarkBtn = CreateFrame("Button", nil, self.toolbar, "BackdropTemplate")
    self.bookmarkBtn:SetSize(32, 22)
    self.bookmarkBtn:SetPoint("LEFT", self.clearBtn, "RIGHT", 8, 0)
    self.bookmarkBtn:SetBackdrop(MedaUI:CreateBackdrop(false))
    self.bookmarkBtn:SetBackdropColor(0, 0, 0, 0)
    self.bookmarkBtn.text = self.bookmarkBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.bookmarkBtn.text:SetPoint("CENTER")
    self.bookmarkBtn.text:SetText("* 0")  -- Bookmark count
    self.bookmarkBtn.text:SetTextColor(unpack(Theme.textDim))
    
    -- Search bar (right side of second row)
    self.searchBox = MedaUI:CreateSearchBox(self.toolbar, 150)
    self.searchBox:SetPoint("TOPRIGHT", -4, -30)
    self.searchBox:SetPlaceholder("Search...")
    self.searchBox.OnSearch = function(_, text)
        self:OnSearch(text)
    end
    
    -- Tab content container (main area)
    self.contentArea = CreateFrame("Frame", nil, self.mainContent)
    self.contentArea:SetPoint("TOPLEFT", 4, -60)
    self.contentArea:SetPoint("BOTTOMRIGHT", -4, 36)
    
    -- Quick actions bar
    self.quickActions = CreateFrame("Frame", nil, self.mainContent, "BackdropTemplate")
    self.quickActions:SetHeight(32)
    self.quickActions:SetPoint("BOTTOMLEFT", 0, 0)
    self.quickActions:SetPoint("BOTTOMRIGHT", 0, 0)
    self.quickActions:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    self.quickActions:SetBackdropColor(unpack(Theme.background))
    
    -- Quick actions top border
    local quickActionsSep = self.quickActions:CreateTexture(nil, "OVERLAY")
    quickActionsSep:SetHeight(1)
    quickActionsSep:SetPoint("TOPLEFT", 0, 0)
    quickActionsSep:SetPoint("TOPRIGHT", 0, 0)
    quickActionsSep:SetColorTexture(unpack(Theme.border))
    
    -- Quick action buttons
    local reloadBtn = MedaUI:CreateButton(self.quickActions, "/reload", 60, 22)
    reloadBtn:SetPoint("LEFT", 4, 0)
    reloadBtn:SetScript("OnClick", function()
        ReloadUI()
    end)
    
    local gcBtn = MedaUI:CreateButton(self.quickActions, "GC", 40, 22)
    gcBtn:SetPoint("LEFT", reloadBtn, "RIGHT", 4, 0)
    gcBtn:SetScript("OnClick", function()
        local before = collectgarbage("count")
        collectgarbage("collect")
        local after = collectgarbage("count")
        local freed = before - after
        MedaDebug:Log("MedaDebug", string.format("Garbage collected: %.1f KB freed", freed), "INFO")
    end)
    
    -- Settings button (right side)
    local settingsBtn = CreateFrame("Button", nil, self.quickActions, "BackdropTemplate")
    settingsBtn:SetSize(24, 22)
    settingsBtn:SetPoint("RIGHT", -4, 0)
    settingsBtn:SetBackdrop(MedaUI:CreateBackdrop(false))
    settingsBtn:SetBackdropColor(0, 0, 0, 0)
    
    -- Gear icon
    settingsBtn.icon = settingsBtn:CreateTexture(nil, "OVERLAY")
    settingsBtn.icon:SetSize(16, 16)
    settingsBtn.icon:SetPoint("CENTER")
    settingsBtn.icon:SetAtlas("Options")  -- Gear icon atlas
    settingsBtn.icon:SetDesaturated(true)
    settingsBtn.icon:SetVertexColor(unpack(Theme.textDim))
    
    settingsBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(Theme.buttonHover))
        self.icon:SetVertexColor(unpack(Theme.text))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("MedaDebug Settings")
        GameTooltip:Show()
    end)
    
    settingsBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
        self.icon:SetVertexColor(unpack(Theme.textDim))
        GameTooltip:Hide()
    end)
    
    settingsBtn:SetScript("OnClick", function()
        if MedaDebug.SettingsPanel then
            MedaDebug.SettingsPanel:Toggle()
        end
    end)
    
    -- Initialize tab content modules
    self:InitializeTabContents()
    
    -- Update filter dropdown with registered addons
    self:RefreshFilterDropdown()
    
    -- Restore active tab
    local savedTab = frameState.activeTab or "messages"
    self.tabBar:SetActiveTab(savedTab)
    
    -- Register for ESC
    tinsert(UISpecialFrames, "MedaDebugFrame")
    
    -- Track show/hide state for persistence through reload
    -- Only save isOpen=true on show; isOpen=false is saved explicitly in Hide/Toggle
    -- We don't use OnHide because it fires during reload cleanup
    self.frame:HookScript("OnShow", function()
        if MedaDebug.db then
            MedaDebug.db.frameState.isOpen = true
        end
    end)
    
    -- Connect to output manager for updates
    if MedaDebug.OutputManager then
        MedaDebug.OutputManager.onNewMessage = function(entry)
            if self.tabContents.messages and self.tabContents.messages.OnNewMessage then
                self.tabContents.messages:OnNewMessage(entry)
            end
        end
    end
    
    -- Connect to error handler
    if MedaDebug.ErrorHandler then
        MedaDebug.ErrorHandler.onNewError = function(entry)
            self:UpdateErrorBadge()
            if self.tabContents.errors and self.tabContents.errors.OnNewError then
                self.tabContents.errors:OnNewError(entry)
            end
        end
        MedaDebug.ErrorHandler.onErrorUpdated = function(entry)
            self:UpdateErrorBadge()
        end
    end
end

function DebugFrame:InitializeTabContents()
    -- Each tab module will create its content when the tab is first shown
    -- This provides lazy loading
end

function DebugFrame:OnTabChanged(tabId, prevTab)
    self.activeTab = tabId
    
    -- Hide previous tab content
    if prevTab and self.tabContents[prevTab] and self.tabContents[prevTab].frame then
        self.tabContents[prevTab].frame:Hide()
    end
    
    -- Show/create current tab content
    local tabModule = self.tabContents[tabId]
    if not tabModule then
        -- Lazy load tab content
        tabModule = self:CreateTabContent(tabId)
        self.tabContents[tabId] = tabModule
    end
    
    if tabModule and tabModule.frame then
        tabModule.frame:Show()
        if tabModule.OnShow then
            tabModule:OnShow()
        end
    end
end

function DebugFrame:CreateTabContent(tabId)
    -- Create frame for tab content
    local tabFrame = CreateFrame("Frame", nil, self.contentArea)
    tabFrame:SetAllPoints()
    
    local module = {frame = tabFrame}
    
    -- Initialize based on tab type
    if tabId == "messages" and MedaDebug.MessagesTab then
        MedaDebug.MessagesTab:Initialize(tabFrame)
        module = MedaDebug.MessagesTab
    elseif tabId == "errors" and MedaDebug.ErrorsTab then
        MedaDebug.ErrorsTab:Initialize(tabFrame)
        module = MedaDebug.ErrorsTab
    elseif tabId == "events" and MedaDebug.EventsTab then
        MedaDebug.EventsTab:Initialize(tabFrame)
        module = MedaDebug.EventsTab
    elseif tabId == "console" and MedaDebug.ConsoleTab then
        MedaDebug.ConsoleTab:Initialize(tabFrame)
        module = MedaDebug.ConsoleTab
    elseif tabId == "inspector" and MedaDebug.InspectorTab then
        MedaDebug.InspectorTab:Initialize(tabFrame)
        module = MedaDebug.InspectorTab
    elseif tabId == "watch" and MedaDebug.WatchTab then
        MedaDebug.WatchTab:Initialize(tabFrame)
        module = MedaDebug.WatchTab
    elseif tabId == "timers" and MedaDebug.TimersTab then
        MedaDebug.TimersTab:Initialize(tabFrame)
        module = MedaDebug.TimersTab
    elseif tabId == "system" and MedaDebug.SystemTab then
        MedaDebug.SystemTab:Initialize(tabFrame)
        module = MedaDebug.SystemTab
    else
        -- Placeholder for unimplemented tabs
        local placeholder = tabFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        placeholder:SetPoint("CENTER")
        placeholder:SetText(tabId .. " tab - Coming soon")
        placeholder:SetTextColor(0.5, 0.5, 0.5)
    end
    
    module.frame = tabFrame
    return module
end

function DebugFrame:OnFilterChanged(value)
    self.currentFilter = value
    
    -- Notify current tab
    local currentTab = self.tabContents[self.activeTab]
    if currentTab and currentTab.OnFilterChanged then
        currentTab:OnFilterChanged(value)
    end
end

function DebugFrame:OnSearch(text)
    -- Notify current tab
    local currentTab = self.tabContents[self.activeTab]
    if currentTab and currentTab.OnSearch then
        currentTab:OnSearch(text)
    end
end

function DebugFrame:OnResize(width, height)
    -- Notify tabs of resize
    for _, tab in pairs(self.tabContents) do
        if tab.OnResize then
            tab:OnResize(width, height)
        end
    end
end

function DebugFrame:RefreshFilterDropdown()
    local options = {{value = "all", label = "All Addons"}}
    
    -- Get registered addons
    local addons = MedaDebug:GetRegisteredAddons()
    for _, addon in ipairs(addons) do
        options[#options + 1] = {value = addon, label = addon}
    end
    
    self.filterDropdown:SetOptions(options)
end

function DebugFrame:UpdateErrorBadge()
    if self.tabBar and MedaDebug.ErrorHandler then
        local count = MedaDebug.ErrorHandler:GetErrorCount()
        self.tabBar:SetBadge("errors", count)
    end
end

function DebugFrame:ClearCurrentTab()
    local currentTab = self.tabContents[self.activeTab]
    if currentTab and currentTab.Clear then
        currentTab:Clear()
    elseif self.activeTab == "messages" and MedaDebug.OutputManager then
        MedaDebug.OutputManager:ClearAll()
    elseif self.activeTab == "errors" and MedaDebug.ErrorHandler then
        MedaDebug.ErrorHandler:ClearErrors()
        self:UpdateErrorBadge()
    elseif self.activeTab == "events" and MedaDebug.EventMonitor then
        MedaDebug.EventMonitor:ClearEvents()
    end
end

function DebugFrame:SetActiveTab(tabId)
    if self.tabBar then
        self.tabBar:SetActiveTab(tabId)
    end
end

function DebugFrame:Show()
    if self.frame then
        self.frame:Show()
        -- isOpen is saved via OnShow hook
    end
end

function DebugFrame:Hide()
    if self.frame then
        self.frame:Hide()
        -- Explicitly save closed state (user action)
        if MedaDebug.db then
            MedaDebug.db.frameState.isOpen = false
        end
    end
end

function DebugFrame:Toggle()
    if self.frame then
        if self.frame:IsShown() then
            self:Hide()  -- Use our Hide() to save state
        else
            self:Show()
        end
    end
end

function DebugFrame:IsShown()
    return self.frame and self.frame:IsShown()
end
