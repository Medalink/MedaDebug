--[[
    MedaDebug Secrets Tab
    Dedicated tab for exploring WoW 12.0.0+ secrets system
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")
local Pixel = MedaUI.Pixel

local SecretsTab = {}
MedaDebug.SecretsTab = SecretsTab

SecretsTab.frame = nil
SecretsTab.scrollList = nil
SecretsTab.searchResults = {}

function SecretsTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()

    -- Top row: Refresh, Copy All buttons
    self.refreshBtn = MedaUI:CreateButton(parent, "Refresh", 70, 22)
    self.refreshBtn:SetPoint("TOPLEFT", 0, 0)
    self.refreshBtn:SetScript("OnClick", function()
        self:RefreshAll()
    end)

    self.copyAllBtn = MedaUI:CreateButton(parent, "Copy All", 70, 22)
    self.copyAllBtn:SetPoint("LEFT", self.refreshBtn, "RIGHT", 4, 0)
    self.copyAllBtn:SetScript("OnClick", function()
        self:CopyAll()
    end)

    -- Search row (below buttons with proper spacing)
    self.searchLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.searchLabel:SetPoint("LEFT", self.copyAllBtn, "RIGHT", 16, 0)
    self.searchLabel:SetText("Search:")
    self.searchLabel:SetTextColor(unpack(Theme.text))

    self.searchInput = MedaUI:CreateEditBox(parent, 150, 22)
    self.searchInput:SetPoint("LEFT", self.searchLabel, "RIGHT", 4, 0)
    self.searchInput:SetPlaceholder("mana, health, aura...")

    self.searchBtn = MedaUI:CreateButton(parent, "Search", 60, 22)
    self.searchBtn:SetPoint("LEFT", self.searchInput, "RIGHT", 4, 0)
    self.searchBtn:SetScript("OnClick", function()
        self:DoSearch()
    end)

    self.searchInput.OnEnterPressed = function()
        self:DoSearch()
    end

    -- Main content area - create a container for scrolling
    self.contentContainer = CreateFrame("Frame", nil, parent)
    self.contentContainer:SetPoint("TOPLEFT", 0, -28)
    self.contentContainer:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Scroll frame (AF custom scrollbar)
    self.scrollParent = MedaUI:CreateScrollFrame(self.contentContainer)
    Pixel.SetPoint(self.scrollParent, "TOPLEFT", 0, 0)
    Pixel.SetPoint(self.scrollParent, "BOTTOMRIGHT", 0, 0)
    self.scrollParent:SetScrollStep(30)

    self.scrollChild = self.scrollParent.scrollContent
    Pixel.SetHeight(self.scrollChild, 1)

    -- Build sections
    self:BuildSections()

    -- Connect to SecretsExplorer callbacks
    if MedaDebug.SecretsExplorer then
        MedaDebug.SecretsExplorer.onPredicatesUpdated = function(predicates)
            self:RefreshPredicates()
        end

        MedaDebug.SecretsExplorer.onRestrictionChanged = function(restrictions)
            self:RefreshRestrictions()
        end
    end

    -- Initial refresh
    C_Timer.After(0.1, function()
        self:RefreshAll()
    end)
end

function SecretsTab:BuildSections()
    local Theme = MedaUI:GetTheme()
    local yOffset = 0

    -- Search Results Section
    self.searchResultsSection = self:CreateSection(self.scrollChild, "Search Results", yOffset)
    self.searchResultsContent = self.searchResultsSection.content
    yOffset = yOffset - self.searchResultsSection.height - 8

    -- Placeholder text for search results
    self.searchPlaceholder = self.searchResultsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.searchPlaceholder:SetPoint("TOPLEFT", 4, -4)
    self.searchPlaceholder:SetText("Enter a search term above (e.g., mana, health, aura)")
    self.searchPlaceholder:SetTextColor(unpack(Theme.textDim))

    -- Context & Simulation Section
    self.contextSection = self:CreateSection(self.scrollChild, "Context & Simulation", yOffset)
    self.contextContent = self.contextSection.content
    yOffset = yOffset - self.contextSection.height - 8
    self:BuildContextContent()

    -- Global Predicates Section
    self.predicatesSection = self:CreateSection(self.scrollChild, "Global Predicates (C_Secrets)", yOffset)
    self.predicatesContent = self.predicatesSection.content
    yOffset = yOffset - self.predicatesSection.height - 8
    self:BuildPredicatesContent()

    -- AddOn Restrictions Section
    self.restrictionsSection = self:CreateSection(self.scrollChild, "AddOn Restrictions (C_RestrictedActions)", yOffset)
    self.restrictionsContent = self.restrictionsSection.content
    self:BuildRestrictionsContent()

    -- Reflow sections after their real heights are known.
    self:RecalculateScrollHeight()
end

function SecretsTab:CreateSection(parent, title, yOffset)
    local Theme = MedaUI:GetTheme()

    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    section:SetPoint("TOPLEFT", 0, yOffset)
    section:SetPoint("RIGHT", -4, 0)
    section:SetBackdrop(MedaUI:CreateBackdrop(true))
    section:SetBackdropColor(unpack(Theme.backgroundDark))
    section:SetBackdropBorderColor(unpack(Theme.border))

    -- Header
    local header = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 8, -8)
    header:SetText(title)
    header:SetTextColor(unpack(Theme.accent))

    -- Content area
    local content = CreateFrame("Frame", nil, section)
    content:SetPoint("TOPLEFT", 8, -28)
    content:SetPoint("BOTTOMRIGHT", -8, 8)

    section.content = content
    section.height = 80 -- Default height, will be adjusted per section

    -- Adjust section height based on content
    section:SetHeight(section.height)

    return section
end

function SecretsTab:BuildContextContent()
    local Theme = MedaUI:GetTheme()
    local content = self.contextContent

    -- Current context labels (inline layout)
    self.contextLabels = {}

    local labels = {
        {key = "combat", text = "Combat:"},
        {key = "mythicPlus", text = "M+:"},
        {key = "raid", text = "Raid:"},
        {key = "instance", text = "Instance:"},
    }

    local xPos = 0
    for i, label in ipairs(labels) do
        local labelText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelText:SetPoint("TOPLEFT", xPos, -4)
        labelText:SetText(label.text)
        labelText:SetTextColor(unpack(Theme.textDim))

        local valueText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valueText:SetPoint("LEFT", labelText, "RIGHT", 4, 0)
        valueText:SetText("--")
        valueText:SetTextColor(unpack(Theme.text))

        self.contextLabels[label.key] = valueText
        xPos = xPos + 100
    end

    -- Simulation checkboxes header
    local simLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    simLabel:SetPoint("TOPLEFT", 0, -26)
    simLabel:SetText("Simulation Mode:")
    simLabel:SetTextColor(unpack(Theme.accent))

    self.simCheckboxes = {}

    local simOptions = {
        {key = "combat", text = "Combat"},
        {key = "mythicPlus", text = "M+"},
        {key = "raid", text = "Raid"},
    }

    -- Inline checkboxes
    xPos = 0
    for _, opt in ipairs(simOptions) do
        local checkbox = MedaUI:CreateCheckbox(content, opt.text)
        checkbox:SetPoint("TOPLEFT", xPos, -44)

        checkbox.OnValueChanged = function(cb, checked)
            if MedaDebug.SecretsExplorer then
                MedaDebug.SecretsExplorer:SetSimulation(opt.key, checked)
            end
        end

        self.simCheckboxes[opt.key] = checkbox
        xPos = xPos + 100
    end

    -- Note about simulation
    local noteText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteText:SetPoint("TOPLEFT", 0, -70)
    noteText:SetText("Simulation shows 'would be secret' for target/enemy APIs")
    noteText:SetTextColor(unpack(Theme.textDim))

    -- Adjust section height (more compact now)
    self.contextSection:SetHeight(110)
    self.contextSection.height = 110
end

function SecretsTab:BuildPredicatesContent()
    local Theme = MedaUI:GetTheme()
    local content = self.predicatesContent

    self.predicateLabels = {}

    -- Two-column layout
    local predicates = MedaDebug.SecretsExplorer and MedaDebug.SecretsExplorer.PREDICATES or {}
    local colWidth = 200

    for i, predicate in ipairs(predicates) do
        local col = ((i - 1) % 2)
        local row = math.floor((i - 1) / 2)

        local xPos = col * colWidth
        local thisYPos = -4 - (row * 18)

        -- Short name (remove "Should" and "BeSecret")
        local shortName = predicate:gsub("^Should", ""):gsub("BeSecret$", "")

        local labelText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelText:SetPoint("TOPLEFT", xPos, thisYPos)
        labelText:SetText(shortName .. ":")
        labelText:SetTextColor(unpack(Theme.textDim))

        local valueText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valueText:SetPoint("LEFT", labelText, "RIGHT", 4, 0)
        valueText:SetText("--")
        valueText:SetTextColor(unpack(Theme.text))

        self.predicateLabels[predicate] = valueText
    end

    -- Calculate height
    local rows = math.ceil(#predicates / 2)
    local height = 40 + (rows * 18)
    self.predicatesSection:SetHeight(height)
    self.predicatesSection.height = height
end

function SecretsTab:BuildRestrictionsContent()
    local Theme = MedaUI:GetTheme()
    local content = self.restrictionsContent

    self.restrictionLabels = {}

    local restrictions = {
        {key = "allowProtectedFunctions", text = "Protected Functions Allowed:"},
        {key = "restrictionState", text = "Restriction State:"},
        {key = "restrictionActive", text = "Restriction Active:"},
    }

    local yPos = -4
    for _, restriction in ipairs(restrictions) do
        local labelText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelText:SetPoint("TOPLEFT", 0, yPos)
        labelText:SetText(restriction.text)
        labelText:SetTextColor(unpack(Theme.textDim))

        local valueText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valueText:SetPoint("LEFT", labelText, "RIGHT", 4, 0)
        valueText:SetText("--")
        valueText:SetTextColor(unpack(Theme.text))

        self.restrictionLabels[restriction.key] = valueText
        yPos = yPos - 18
    end

    -- Adjust section height
    self.restrictionsSection:SetHeight(90)
    self.restrictionsSection.height = 90
end

function SecretsTab:DoSearch()
    local query = self.searchInput:GetText()
    if not query or query == "" then
        self.searchPlaceholder:Show()
        self:ClearSearchResults()
        self.searchResultsSection:SetHeight(80)
        self.searchResultsSection.height = 80
        self:RecalculateScrollHeight()
        return
    end

    self.searchPlaceholder:Hide()

    if not MedaDebug.SecretsExplorer then return end

    -- Search APIs
    local results = MedaDebug.SecretsExplorer:SearchAPIs(query)
    self:DisplaySearchResults(results)
end

function SecretsTab:ClearSearchResults()
    -- Clear existing result rows
    if self.resultRows then
        for _, row in ipairs(self.resultRows) do
            row:Hide()
        end
    end
    self.resultRows = {}
end

function SecretsTab:DisplaySearchResults(results)
    self:ClearSearchResults()

    local Theme = MedaUI:GetTheme()
    local content = self.searchResultsContent

    if #results == 0 then
        self.searchPlaceholder:SetText("No results found for query")
        self.searchPlaceholder:Show()
        self.searchResultsSection:SetHeight(80)
        self.searchResultsSection.height = 80
        self:RecalculateScrollHeight()
        return
    end

    self.resultRows = {}
    local yPos = -4
    local rowHeight = 50

    -- Test with relevant units for better coverage
    local testUnits = {"player", "target", "party1"}

    for i, result in ipairs(results) do
        if i > 10 then
            -- Limit results shown
            local moreText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            moreText:SetPoint("TOPLEFT", 0, yPos)
            moreText:SetText("... and " .. (#results - 10) .. " more results")
            moreText:SetTextColor(unpack(Theme.textDim))
            self.resultRows[#self.resultRows + 1] = moreText
            yPos = yPos - 20
            break
        end

        local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetPoint("TOPLEFT", 0, yPos)
        row:SetPoint("RIGHT", 0, 0)
        row:SetHeight(rowHeight - 4)
        row:SetBackdrop(MedaUI:CreateBackdrop(false))
        row:SetBackdropColor(0.15, 0.15, 0.15, 0.5)

        -- API name and description
        local apiLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        apiLabel:SetPoint("TOPLEFT", 4, -4)
        apiLabel:SetText("|cff88bbff" .. result.api.name .. "|r - " .. result.api.desc)
        apiLabel:SetTextColor(unpack(Theme.text))

        -- Test with each unit
        local unitResults = {}
        if MedaDebug.SecretsExplorer then
            unitResults = MedaDebug.SecretsExplorer:TestAPIWithSimulation(
                result.api.name,
                result.api.args,
                testUnits
            )
        end

        -- Display unit results
        local xPos = 4
        local resultY = -22
        for _, unit in ipairs(testUnits) do
            local unitResult = unitResults[unit]
            if unitResult then
                local unitLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                unitLabel:SetPoint("TOPLEFT", xPos, resultY)

                local statusColor = "|cff00ff00"
                local statusText = "OK"

                if unitResult.error then
                    statusColor = "|cff888888"
                    statusText = "err"
                elseif unitResult.isSecret then
                    statusColor = "|cffff4444"
                    statusText = "SECRET"
                elseif unitResult.wouldBeSecret then
                    statusColor = "|cffffaa00"
                    statusText = "~secret"
                end

                local displayValue = unitResult.valueStr or "?"
                if #displayValue > 15 then
                    displayValue = displayValue:sub(1, 15) .. ".."
                end

                local labelStr = unit .. ": " .. statusColor .. statusText .. "|r " .. displayValue

                -- Show taint behavior for secret values
                if unitResult.taintBehavior then
                    local tb = unitResult.taintBehavior
                    local taintParts = {}
                    if tb.tostring then taintParts[#taintParts + 1] = "str:" .. tb.tostring end
                    if tb.compare then taintParts[#taintParts + 1] = "cmp:" .. tb.compare end
                    if tb.arithmetic then taintParts[#taintParts + 1] = "math:" .. tb.arithmetic end
                    if #taintParts > 0 then
                        labelStr = labelStr .. " |cff666666[" .. table.concat(taintParts, " ") .. "]|r"
                    end
                end

                unitLabel:SetText(labelStr)
                unitLabel:SetTextColor(unpack(Theme.textDim))

                xPos = xPos + 220
            end
        end

        self.resultRows[#self.resultRows + 1] = row
        yPos = yPos - rowHeight
    end

    -- Update section height
    local totalHeight = 40 + math.abs(yPos)
    self.searchResultsSection:SetHeight(math.max(80, totalHeight))
    self.searchResultsSection.height = math.max(80, totalHeight)

    -- Recalculate total scroll height
    self:RecalculateScrollHeight()
end

function SecretsTab:RecalculateScrollHeight()
    local totalHeight = 0
    totalHeight = totalHeight + self.searchResultsSection.height + 8
    totalHeight = totalHeight + self.contextSection.height + 8
    totalHeight = totalHeight + self.predicatesSection.height + 8
    totalHeight = totalHeight + self.restrictionsSection.height + 8
    totalHeight = totalHeight + 50 -- padding

    self.scrollChild:SetHeight(totalHeight)

    -- Reposition sections
    local yOffset = 0

    self.searchResultsSection:ClearAllPoints()
    self.searchResultsSection:SetPoint("TOPLEFT", 0, yOffset)
    self.searchResultsSection:SetPoint("RIGHT", -4, 0)
    yOffset = yOffset - self.searchResultsSection.height - 8

    self.contextSection:ClearAllPoints()
    self.contextSection:SetPoint("TOPLEFT", 0, yOffset)
    self.contextSection:SetPoint("RIGHT", -4, 0)
    yOffset = yOffset - self.contextSection.height - 8

    self.predicatesSection:ClearAllPoints()
    self.predicatesSection:SetPoint("TOPLEFT", 0, yOffset)
    self.predicatesSection:SetPoint("RIGHT", -4, 0)
    yOffset = yOffset - self.predicatesSection.height - 8

    self.restrictionsSection:ClearAllPoints()
    self.restrictionsSection:SetPoint("TOPLEFT", 0, yOffset)
    self.restrictionsSection:SetPoint("RIGHT", -4, 0)
end

function SecretsTab:RefreshContext()
    if not MedaDebug.SecretsExplorer then return end

    local context = MedaDebug.SecretsExplorer:GetCurrentContext()

    if self.contextLabels then
        if self.contextLabels.combat then
            self.contextLabels.combat:SetText(context.inCombat and "|cffff4444Yes|r" or "|cff00ff00No|r")
        end
        if self.contextLabels.mythicPlus then
            self.contextLabels.mythicPlus:SetText(context.inMythicPlus and "|cffff9900Yes|r" or "|cff00ff00No|r")
        end
        if self.contextLabels.raid then
            self.contextLabels.raid:SetText(context.inRaid and "|cff9999ffYes|r" or "|cff888888No|r")
        end
        if self.contextLabels.instance then
            self.contextLabels.instance:SetText(context.instanceType or "none")
        end
    end

    -- Update simulation checkboxes to match state (MedaUI checkboxes)
    if self.simCheckboxes then
        local simState = MedaDebug.SecretsExplorer:GetSimulation()
        for key, checkbox in pairs(self.simCheckboxes) do
            if checkbox.SetChecked then
                checkbox:SetChecked(simState[key])
            end
        end
    end
end

function SecretsTab:RefreshPredicates()
    if not MedaDebug.SecretsExplorer then return end

    local predicates = MedaDebug.SecretsExplorer:GetAllPredicates()

    for predicate, label in pairs(self.predicateLabels or {}) do
        local value = predicates[predicate]
        if value == true then
            label:SetText("|cffff4444Secret|r")
        elseif value == false then
            label:SetText("|cff00ff00Not Secret|r")
        else
            label:SetText("|cff888888N/A|r")
        end
    end
end

function SecretsTab:RefreshRestrictions()
    if not MedaDebug.SecretsExplorer then return end

    local restrictions = MedaDebug.SecretsExplorer:GetAddOnRestrictions()

    if self.restrictionLabels then
        if self.restrictionLabels.allowProtectedFunctions then
            local value = restrictions.allowProtectedFunctions
            self.restrictionLabels.allowProtectedFunctions:SetText(value and "|cff00ff00Yes|r" or "|cffff4444No|r")
        end

        if self.restrictionLabels.restrictionState then
            local value = restrictions.restrictionState or "none"
            local color = value == "none" and "|cff00ff00" or "|cffff9900"
            self.restrictionLabels.restrictionState:SetText(color .. '"' .. value .. '"|r')
        end

        if self.restrictionLabels.restrictionActive then
            local value = restrictions.restrictionActive
            self.restrictionLabels.restrictionActive:SetText(value and "|cffff4444Yes|r" or "|cff00ff00No|r")
        end
    end
end

function SecretsTab:RefreshAll()
    self:RefreshContext()
    self:RefreshPredicates()
    self:RefreshRestrictions()

    -- Re-run search if we have one
    local query = self.searchInput and self.searchInput:GetText()
    if query and query ~= "" then
        self:DoSearch()
    end
end

function SecretsTab:CopyAll()
    if not MedaDebug.SecretsExplorer then return end

    local text = MedaDebug.SecretsExplorer:FormatForCopy()

    -- Use MedaUI's shared TextViewer
    MedaUI:ShowTextViewer("Secrets Report - Press Ctrl+C to copy", text)
end

function SecretsTab:OnShow()
    self:RefreshAll()
end

function SecretsTab:Clear()
    self:ClearSearchResults()
    if self.searchInput then
        self.searchInput:SetText("")
    end
    self.searchPlaceholder:SetText("Enter a search term above (e.g., mana, health, aura)")
    self.searchPlaceholder:Show()
    self.searchResultsSection:SetHeight(80)
    self.searchResultsSection.height = 80
    self:RecalculateScrollHeight()
end

function SecretsTab:OnFilterChanged(filter)
    -- Secrets tab doesn't use addon filter
end

function SecretsTab:OnSearch(text)
    -- Global search from DebugFrame
    if self.searchInput then
        self.searchInput:SetText(text)
        self:DoSearch()
    end
end
