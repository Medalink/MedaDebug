--[[
    MedaDebug Debug Frame
    Main tabbed debug window
]]

local _, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local DebugFrame = {}
MedaDebug.DebugFrame = DebugFrame

-- Frame state
DebugFrame.frame = nil
DebugFrame.tabBar = nil
DebugFrame.tabContents = {}
DebugFrame.activeTab = "messages"
DebugFrame.currentFilter = "all"
DebugFrame.knownMessageAddons = {}

-- Tab definitions
local TABS = {
    {id = "messages", label = "Msgs"},
    {id = "errors", label = "Errors", badge = 0},
    {id = "events", label = "Events"},
    {id = "console", label = "Console"},
    {id = "inspector", label = "Inspect"},
    {id = "secrets", label = "Secrets"},
    {id = "watch", label = "Watch"},
    {id = "timers", label = "Timers"},
    {id = "system", label = "Sys"},
}

function DebugFrame:Initialize()
    if self.frame then return end
    
    local Theme = MedaUI:GetTheme()
    
    -- Create main panel
    self.frame = MedaUI:CreatePanel("MedaDebugFrame", 800, 500, "MedaDebug")
    self.frame:SetResizable(true, {
        minWidth = 650,
        minHeight = 400,
    })

    -- Restore saved state (position and size)
    local frameState = MedaDebug.db.frameState
    if frameState then
        self.frame:RestoreState(frameState)
    end

    -- Save state on move/resize
    local function saveState(state)
        if MedaDebug.db then
            MedaDebug.db.frameState.position = state.position
            MedaDebug.db.frameState.size = state.size
        end
    end

    self.frame.OnMove = function(_, state)
        saveState(state)
    end

    self.frame.OnResize = function(_, state)
        saveState(state)
        -- Notify tabs of resize
        self:OnResize(state.size.width, state.size.height)
    end

    -- Override close button to use our Hide method (saves state)
    if self.frame.closeButton then
        self.frame.closeButton:SetScript("OnClick", function()
            self:Hide()
        end)
    end

    -- Add settings button to title bar (white gear icon)
    local titleSettingsBtn = CreateFrame("Button", nil, self.frame.titleBar, "BackdropTemplate")
    titleSettingsBtn:SetSize(20, 20)
    titleSettingsBtn:SetPoint("RIGHT", self.frame.closeButton, "LEFT", -2, 0)
    titleSettingsBtn:SetBackdrop(MedaUI:CreateBackdrop(false))
    titleSettingsBtn:SetBackdropColor(0, 0, 0, 0)

    titleSettingsBtn.icon = titleSettingsBtn:CreateTexture(nil, "OVERLAY")
    titleSettingsBtn.icon:SetSize(16, 16)
    titleSettingsBtn.icon:SetPoint("CENTER")
    titleSettingsBtn.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    titleSettingsBtn.icon:SetVertexColor(1, 1, 1)  -- White

    titleSettingsBtn:SetScript("OnEnter", function(button)
        button:SetBackdropColor(unpack(Theme.buttonHover))
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText("Settings")
        GameTooltip:Show()
    end)

    titleSettingsBtn:SetScript("OnLeave", function(button)
        button:SetBackdropColor(0, 0, 0, 0)
        GameTooltip:Hide()
    end)

    titleSettingsBtn:SetScript("OnClick", function()
        if MedaDebug.SettingsPanel then
            MedaDebug.SettingsPanel:Toggle()
        end
    end)
    
    local content = self.frame:GetContent()
    
    -- Main content wrapper with darker background
    self.mainContent = CreateFrame("Frame", nil, content, "BackdropTemplate")
    self.mainContent:SetPoint("TOPLEFT", 0, 0)
    self.mainContent:SetPoint("BOTTOMRIGHT", 0, 0)
    self.mainContent:SetBackdrop(MedaUI:CreateBackdrop(false))
    self.mainContent:SetBackdropColor(unpack(Theme.backgroundDark))
    
    -- Toolbar area (tabs + filter row)
    self.toolbar = CreateFrame("Frame", nil, self.mainContent, "BackdropTemplate")
    self.toolbar:SetHeight(68)
    self.toolbar:SetPoint("TOPLEFT", 0, 0)
    self.toolbar:SetPoint("TOPRIGHT", 0, 0)
    self.toolbar:SetBackdrop(MedaUI:CreateBackdrop(false))
    self.toolbar:SetBackdropColor(unpack(Theme.background))
    
    -- Tab bar (full width on first row)
    self.tabBar = MedaUI:CreateTabBar(self.toolbar, TABS)
    self.tabBar:SetPoint("TOPLEFT", 8, -4)
    self.tabBar:SetPoint("TOPRIGHT", -8, -4)
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
    self.filterDropdown:SetPoint("TOPLEFT", 8, -36)
    self.filterDropdown.OnValueChanged = function(_, value)
        self:OnFilterChanged(value)
    end
    
    -- Clear button
    self.clearBtn = MedaUI:CreateButton(self.toolbar, "Clear", 60, 26)
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
    self.searchBox:SetPoint("TOPRIGHT", -8, -36)
    self.searchBox:SetPlaceholder("Search...")
    self.searchBox.OnSearch = function(_, text)
        self:OnSearch(text)
    end
    
    -- Tab content container (main area)
    self.contentArea = CreateFrame("Frame", nil, self.mainContent)
    self.contentArea:SetPoint("TOPLEFT", 8, -72)
    self.contentArea:SetPoint("BOTTOMRIGHT", -8, 36)
    
    -- Quick actions bar
    self.quickActions = CreateFrame("Frame", nil, self.mainContent, "BackdropTemplate")
    self.quickActions:SetHeight(32)
    self.quickActions:SetPoint("BOTTOMLEFT", 0, 0)
    self.quickActions:SetPoint("BOTTOMRIGHT", 0, 0)
    self.quickActions:SetBackdrop(MedaUI:CreateBackdrop(false))
    self.quickActions:SetBackdropColor(unpack(Theme.background))
    
    -- Quick actions top border
    local quickActionsSep = self.quickActions:CreateTexture(nil, "OVERLAY")
    quickActionsSep:SetHeight(1)
    quickActionsSep:SetPoint("TOPLEFT", 0, 0)
    quickActionsSep:SetPoint("TOPRIGHT", 0, 0)
    quickActionsSep:SetColorTexture(unpack(Theme.border))
    
    -- Quick action buttons
    local reloadBtn = MedaUI:CreateButton(self.quickActions, "/reload", 60, 26)
    reloadBtn:SetPoint("LEFT", 8, 0)
    reloadBtn:SetScript("OnClick", function()
        if not (MedaDebug.db and MedaDebug.db.options.confirmReload) then
            ReloadUI()
            return
        end

        StaticPopupDialogs["MEDADEBUG_CONFIRM_RELOAD"] = {
            text = "Reload the UI now?",
            button1 = "Reload",
            button2 = "Cancel",
            OnAccept = function()
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("MEDADEBUG_CONFIRM_RELOAD")
    end)

    local gcBtn = MedaUI:CreateButton(self.quickActions, "GC", 40, 26)
    gcBtn:SetPoint("LEFT", reloadBtn, "RIGHT", 8, 0)
    gcBtn:SetScript("OnClick", function()
        local before = collectgarbage("count")
        collectgarbage("collect")
        local after = collectgarbage("count")
        local freed = before - after
        MedaDebug:LogInternal("MedaDebug", string.format("Garbage collected: %.1f KB freed", freed), "INFO")
    end)

    -- Copy button - copies current tab content
    local copyBtn = MedaUI:CreateButton(self.quickActions, "Copy", 50, 26)
    copyBtn:SetPoint("LEFT", gcBtn, "RIGHT", 8, 0)
    copyBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Copy current tab data")
        GameTooltip:Show()
    end)
    copyBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    copyBtn:SetScript("OnClick", function()
        self:CopyCurrentTab()
    end)
    
    -- Settings button (right side)
    local footerSettingsBtn = CreateFrame("Button", nil, self.quickActions, "BackdropTemplate")
    footerSettingsBtn:SetSize(24, 22)
    footerSettingsBtn:SetPoint("RIGHT", -8, 0)
    footerSettingsBtn:SetBackdrop(MedaUI:CreateBackdrop(false))
    footerSettingsBtn:SetBackdropColor(0, 0, 0, 0)
    
    -- Gear icon
    footerSettingsBtn.icon = footerSettingsBtn:CreateTexture(nil, "OVERLAY")
    footerSettingsBtn.icon:SetSize(16, 16)
    footerSettingsBtn.icon:SetPoint("CENTER")
    footerSettingsBtn.icon:SetAtlas("Options")  -- Gear icon atlas
    footerSettingsBtn.icon:SetDesaturated(true)
    footerSettingsBtn.icon:SetVertexColor(unpack(Theme.textDim))
    
    footerSettingsBtn:SetScript("OnEnter", function(button)
        button:SetBackdropColor(unpack(Theme.buttonHover))
        button.icon:SetVertexColor(unpack(Theme.text))
        GameTooltip:SetOwner(button, "ANCHOR_TOP")
        GameTooltip:SetText("MedaDebug Settings")
        GameTooltip:Show()
    end)
    
    footerSettingsBtn:SetScript("OnLeave", function(button)
        button:SetBackdropColor(0, 0, 0, 0)
        button.icon:SetVertexColor(unpack(Theme.textDim))
        GameTooltip:Hide()
    end)
    
    footerSettingsBtn:SetScript("OnClick", function()
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
        -- Ensure current tab content exists and refresh it
        local currentTab = self.tabContents[self.activeTab]
        if not currentTab then
            -- Tab content not created yet, create it now
            currentTab = self:CreateTabContent(self.activeTab)
            self.tabContents[self.activeTab] = currentTab
        end
        if currentTab then
            if currentTab.frame then
                currentTab.frame:Show()
            end
            if currentTab.OnShow then
                currentTab:OnShow()
            end
        end
    end)
    
    -- Connect to output manager for updates
    if MedaDebug.OutputManager then
        MedaDebug.OutputManager.onNewMessage = function(entry)
            -- Rebuild filter options only when the addon set changes.
            if entry == nil then
                self:RefreshFilterDropdown()
            elseif entry.addon and not self.knownMessageAddons[entry.addon] then
                self:RefreshFilterDropdown()
            end

            -- Only refresh the messages UI while the tab is actually visible.
            if self.tabContents.messages and self.activeTab == "messages" and self.frame:IsShown() then
                if self.tabContents.messages.OnNewMessage then
                    self.tabContents.messages:OnNewMessage(entry)
                end
            elseif self.activeTab == "messages" and self.frame:IsShown() then
                -- Tab not initialized yet but should be visible - force refresh
                C_Timer.After(0.1, function()
                    if self.tabContents.messages and self.tabContents.messages.RefreshData then
                        self.tabContents.messages:RefreshData()
                    end
                end)
            end
        end
    end
    
    -- Connect to error handler (with pcall protection)
    if MedaDebug.ErrorHandler then
        MedaDebug.ErrorHandler.onNewError = function(entry)
            pcall(function() self:UpdateErrorBadge() end)
            if self.tabContents.errors and self.activeTab == "errors" and self.frame:IsShown() and self.tabContents.errors.OnNewError then
                pcall(function() self.tabContents.errors:OnNewError(entry) end)
            end
        end
        MedaDebug.ErrorHandler.onErrorUpdated = function(entry)
            pcall(function() self:UpdateErrorBadge() end)
            if self.tabContents.errors and self.activeTab == "errors" and self.frame:IsShown() and self.tabContents.errors.OnErrorUpdated then
                pcall(function() self.tabContents.errors:OnErrorUpdated(entry) end)
            end
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
    elseif tabId == "secrets" and MedaDebug.SecretsTab then
        MedaDebug.SecretsTab:Initialize(tabFrame)
        module = MedaDebug.SecretsTab
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
    wipe(self.knownMessageAddons)

    -- Get addons from actual messages
    if MedaDebug.OutputManager then
        local addons = MedaDebug.OutputManager:GetAddonsFromMessages()
        for _, addon in ipairs(addons) do
            self.knownMessageAddons[addon] = true
            options[#options + 1] = {value = addon, label = addon}
        end
    end

    self.filterDropdown:SetOptions(options)
end

function DebugFrame:UpdateErrorBadge()
    if self.tabBar and MedaDebug.ErrorHandler then
        local count = MedaDebug.ErrorHandler:GetVisibleErrorCount()
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

function DebugFrame:CopyCurrentTab()
    local currentTab = self.tabContents[self.activeTab]

    -- If current tab has a Copy function, use it
    if currentTab and currentTab.Copy then
        currentTab:Copy()
        return
    end

    -- Default: copy messages
    self:CopyMessages()
end

function DebugFrame:CopyMessages()
    if not MedaDebug.OutputManager then return end

    local text = MedaDebug.OutputManager:GetMessagesForCopy()

    -- Use MedaUI's shared TextViewer
    MedaUI:ShowTextViewer("Messages - Press Ctrl+C to copy", text)
end
