--[[
    MedaDebug Inspector Tab
    Frame inspection UI with tree navigation
]]

local _, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")
local Pixel = MedaUI.Pixel

local InspectorTab = {}
MedaDebug.InspectorTab = InspectorTab

InspectorTab.frame = nil
InspectorTab.treeView = nil
InspectorTab.currentFrame = nil
InspectorTab.currentInfo = nil
InspectorTab.isLocked = false
InspectorTab.isPreview = false

function InspectorTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()
    
    -- Inspect button
    self.inspectBtn = MedaUI:CreateButton(parent, "Inspect Mode", 100, 22)
    self.inspectBtn:SetPoint("TOPLEFT", 0, 0)
    self.inspectBtn:SetScript("OnClick", function()
        if MedaDebug.FrameInspector then
            -- Unlock to allow new previews
            self.isLocked = false
            self.isPreview = false
            MedaDebug.FrameInspector:StartInspectMode()
        end
    end)
    
    -- Current frame label
    self.frameLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    self.frameLabel:SetPoint("LEFT", self.inspectBtn, "RIGHT", 8, 0)
    self.frameLabel:SetTextColor(unpack(Theme.text))
    self.frameLabel:SetText("No frame selected")
    
    -- Tree view for frame hierarchy
    self.treeView = MedaUI:CreateTreeView(parent, parent:GetWidth(), parent:GetHeight() - 60)
    self.treeView:SetPoint("TOPLEFT", 0, -28)
    self.treeView:SetPoint("BOTTOMRIGHT", 0, 32)
    
    self.treeView.OnNodeClick = function(_, node, path)
        self:OnNodeSelected(node)
    end
    
    -- Action buttons
    self.copyInfoBtn = MedaUI:CreateButton(parent, "Copy Info", 70, 22)
    self.copyInfoBtn:SetPoint("BOTTOMLEFT", 0, 0)
    self.copyInfoBtn:SetScript("OnClick", function()
        self:Copy()
    end)

    self.copyPathBtn = MedaUI:CreateButton(parent, "Copy Path", 70, 22)
    self.copyPathBtn:SetPoint("LEFT", self.copyInfoBtn, "RIGHT", 4, 0)
    self.copyPathBtn:SetScript("OnClick", function()
        self:CopyFramePath()
    end)

    self.watchBtn = MedaUI:CreateButton(parent, "Watch", 50, 22)
    self.watchBtn:SetPoint("LEFT", self.copyPathBtn, "RIGHT", 4, 0)
    self.watchBtn:SetScript("OnClick", function()
        self:WatchFrame()
    end)

    self.ignoredBtn = MedaUI:CreateButton(parent, "Ignored", 60, 22)
    self.ignoredBtn:SetPoint("LEFT", self.watchBtn, "RIGHT", 4, 0)
    self.ignoredBtn:SetScript("OnClick", function()
        self:ShowIgnoredFramesPanel()
    end)

    -- Connect to frame inspector
    if MedaDebug.FrameInspector then
        MedaDebug.FrameInspector.onFrameInspected = function(frame, info)
            self:OnFrameInspected(frame, info, false)  -- false = locked (final selection)
        end

        MedaDebug.FrameInspector.onFramePreview = function(frame, info, isPreview)
            self:OnFrameInspected(frame, info, true)  -- true = preview mode
        end
    end
end

function InspectorTab:OnFrameInspected(frame, info, isPreview)
    -- Don't overwrite locked frame with preview
    if isPreview and self.isLocked then return end

    self.currentFrame = frame
    self.currentInfo = info
    self.isPreview = isPreview

    -- Lock in when not preview
    if not isPreview then
        self.isLocked = true
    end

    if not info then return end

    -- Update label with preview/locked indicator
    if isPreview then
        self.frameLabel:SetTextColor(1, 1, 0)  -- Yellow for preview
    else
        self.frameLabel:SetTextColor(0, 1, 0)  -- Green for locked
    end
    local statusText = isPreview and "|cffFFFF00[PREVIEW]|r " or "|cff00FF00[LOCKED]|r "
    local sourceText = info.source and info.source ~= "Unknown" and (" |cff888888[" .. info.source .. "]|r") or ""
    self.frameLabel:SetText(statusText .. info.name .. " (" .. info.type .. ")" .. sourceText)

    -- Build tree data
    local treeData = self:BuildTreeData(info)
    self.treeView:SetData(treeData)
end

function InspectorTab:BuildTreeData(info)
    local data = {}
    
    -- Main frame node
    local frameNode = {
        label = info.name .. " (" .. info.type .. ")",
        expanded = true,
        children = {},
        data = info,
    }
    
    -- Properties
    local propsNode = {
        label = "Properties",
        expanded = true,
        children = {
            {label = "Source: " .. (info.source or "Unknown")},
            {label = "Size: " .. math.floor(info.width) .. " x " .. math.floor(info.height)},
            {label = "Visible: " .. (info.isVisible and "Yes" or "No")},
            {label = "Alpha: " .. string.format("%.2f", info.alpha)},
            {label = "Level: " .. tostring(info.frameLevel)},
            {label = "Strata: " .. tostring(info.frameStrata)},
        }
    }
    frameNode.children[#frameNode.children + 1] = propsNode

    -- Widget Values (type-specific)
    if info.widgetValues then
        local wv = info.widgetValues
        if wv.statusBar then
            local sb = wv.statusBar
            local valuesNode = {
                label = "|cff00FF00Values (StatusBar)|r",
                expanded = true,
                children = {
                    {label = "Value: " .. tostring(sb.value) .. " / " .. tostring(sb.max) .. " (" .. tostring(sb.percent) .. "%)"},
                    {label = "Min: " .. tostring(sb.min)},
                    {label = "Max: " .. tostring(sb.max)},
                    {label = "Orientation: " .. tostring(sb.orientation)},
                    {label = "Fill Style: " .. tostring(sb.fillStyle)},
                }
            }
            if sb.texture then
                valuesNode.children[#valuesNode.children + 1] = {label = "Texture: " .. tostring(sb.texture)}
            end
            if sb.color then
                valuesNode.children[#valuesNode.children + 1] = {label = "Color (RGBA): " .. tostring(sb.color)}
            end
            frameNode.children[#frameNode.children + 1] = valuesNode
        end
        if wv.button then
            local btn = wv.button
            local valuesNode = {
                label = "|cff00FF00Values (Button)|r",
                expanded = true,
                children = {
                    {label = "Text: " .. tostring(btn.text or "(none)")},
                    {label = "Enabled: " .. tostring(btn.enabled)},
                }
            }
            if btn.normalTexture then
                valuesNode.children[#valuesNode.children + 1] = {label = "Texture: " .. tostring(btn.normalTexture)}
            end
            frameNode.children[#frameNode.children + 1] = valuesNode
        end
        if wv.slider then
            local sl = wv.slider
            local valuesNode = {
                label = "|cff00FF00Values (Slider)|r",
                expanded = true,
                children = {
                    {label = "Value: " .. tostring(sl.value)},
                    {label = "Range: " .. tostring(sl.min) .. " - " .. tostring(sl.max)},
                    {label = "Step: " .. tostring(sl.step)},
                    {label = "Orientation: " .. tostring(sl.orientation)},
                }
            }
            frameNode.children[#frameNode.children + 1] = valuesNode
        end
        if wv.editBox then
            local eb = wv.editBox
            local valuesNode = {
                label = "|cff00FF00Values (EditBox)|r",
                expanded = true,
                children = {
                    {label = "Text: " .. tostring(eb.text or "(empty)")},
                    {label = "Max Letters: " .. tostring(eb.maxLetters)},
                    {label = "Multi-line: " .. tostring(eb.isMultiLine)},
                    {label = "Numeric: " .. tostring(eb.isNumeric)},
                }
            }
            frameNode.children[#frameNode.children + 1] = valuesNode
        end
        if wv.checkButton then
            local cb = wv.checkButton
            local valuesNode = {
                label = "|cff00FF00Values (CheckButton)|r",
                expanded = true,
                children = {
                    {label = "Checked: " .. tostring(cb.checked)},
                    {label = "Text: " .. tostring(cb.text or "(none)")},
                }
            }
            frameNode.children[#frameNode.children + 1] = valuesNode
        end
        if wv.cooldown then
            local cd = wv.cooldown
            local valuesNode = {
                label = "|cff00FF00Values (Cooldown)|r",
                expanded = true,
                children = {
                    {label = "Start: " .. tostring(cd.start)},
                    {label = "Duration: " .. tostring(cd.duration)},
                    {label = "Enabled: " .. tostring(cd.enabled)},
                }
            }
            frameNode.children[#frameNode.children + 1] = valuesNode
        end
    end
    
    -- Anchors
    if info.points and #info.points > 0 then
        local anchorsNode = {
            label = "Anchors (" .. #info.points .. ")",
            expanded = true,
            children = {}
        }
        for i, point in ipairs(info.points) do
            anchorsNode.children[#anchorsNode.children + 1] = {
                label = string.format("%s -> %s (%s, %.0f, %.0f)",
                    point.point,
                    point.relativeTo or "nil",
                    point.relativePoint,
                    point.x or 0,
                    point.y or 0
                )
            }
        end
        frameNode.children[#frameNode.children + 1] = anchorsNode
    end

    -- Scripts
    if info.scripts and #info.scripts > 0 then
        local scriptsNode = {
            label = "Scripts (" .. #info.scripts .. ")",
            expanded = true,
            children = {}
        }
        for _, script in ipairs(info.scripts) do
            scriptsNode.children[#scriptsNode.children + 1] = {label = script}
        end
        frameNode.children[#frameNode.children + 1] = scriptsNode
    end

    -- Children
    if info.children and #info.children > 0 then
        local childrenNode = {
            label = "Children (" .. #info.children .. ")",
            expanded = true,
            children = {}
        }
        for i, child in ipairs(info.children) do
            childrenNode.children[#childrenNode.children + 1] = {
                label = child.name .. " (" .. child.type .. ")",
                childFrame = child,
                childIndex = i,  -- Store index for unnamed frames
            }
        end
        frameNode.children[#frameNode.children + 1] = childrenNode
    end

    -- Regions
    if info.regions and #info.regions > 0 then
        local regionsNode = {
            label = "Regions (" .. #info.regions .. ")",
            expanded = true,
            children = {}
        }
        for _, region in ipairs(info.regions) do
            local regionNode = {
                label = region.name .. " (" .. region.type .. ")",
                children = {}
            }

            -- Add type-specific details as children
            if region.type == "FontString" then
                if region.text then
                    regionNode.children[#regionNode.children + 1] = {label = 'Text: "' .. region.text:sub(1, 50) .. '"'}
                end
                if region.font then
                    regionNode.children[#regionNode.children + 1] = {label = "Font: " .. tostring(region.font)}
                end
                if region.fontSize then
                    regionNode.children[#regionNode.children + 1] = {label = "Size: " .. tostring(region.fontSize)}
                end
                if region.textColor then
                    regionNode.children[#regionNode.children + 1] = {label = "Color: " .. region.textColor}
                end
            elseif region.type == "Texture" or region.type == "MaskTexture" then
                if region.texture then
                    regionNode.children[#regionNode.children + 1] = {label = "Texture: " .. tostring(region.texture)}
                end
                if region.texCoord then
                    regionNode.children[#regionNode.children + 1] = {label = "TexCoord: " .. region.texCoord}
                end
                if region.vertexColor then
                    regionNode.children[#regionNode.children + 1] = {label = "Color: " .. region.vertexColor}
                end
                if region.blendMode then
                    regionNode.children[#regionNode.children + 1] = {label = "Blend: " .. region.blendMode}
                end
            end

            -- Only make it expandable if it has children
            if #regionNode.children > 0 then
                regionNode.expanded = false  -- Collapsed by default to reduce clutter
            else
                regionNode.children = nil
            end

            regionsNode.children[#regionsNode.children + 1] = regionNode
        end
        frameNode.children[#frameNode.children + 1] = regionsNode
    end

    -- Secrets (WoW 12.0.0+)
    if info.secrets then
        local secrets = info.secrets
        local hasAnySecret = secrets.hasSecretValues or secrets.isAnchoringSecret or
                            (secrets.secretAspects and #secrets.secretAspects > 0)

        local secretsNode = {
            label = hasAnySecret and "|cffff9900Secrets|r" or "Secrets",
            children = {}
        }

        -- Has Secret Values
        local hasSecretLabel = "Has Secret Values: " .. (secrets.hasSecretValues and "|cffff4444Yes|r" or "No")
        secretsNode.children[#secretsNode.children + 1] = {label = hasSecretLabel}

        -- Anchoring Secret
        local anchoringLabel = "Anchoring Secret: " .. (secrets.isAnchoringSecret and "|cffff4444Yes|r" or "No")
        secretsNode.children[#secretsNode.children + 1] = {label = anchoringLabel}

        -- Preventing Secrets
        local preventingLabel = "Preventing Secrets: " .. (secrets.isPreventingSecretValues and "|cff00ff00Yes|r" or "No")
        secretsNode.children[#secretsNode.children + 1] = {label = preventingLabel}

        -- Secret Aspects
        if secrets.secretAspects and #secrets.secretAspects > 0 then
            local aspectsNode = {
                label = "Secret Aspects (" .. #secrets.secretAspects .. ")",
                children = {}
            }
            for _, aspect in ipairs(secrets.secretAspects) do
                aspectsNode.children[#aspectsNode.children + 1] = {label = "|cffff9900" .. aspect .. "|r"}
            end
            secretsNode.children[#secretsNode.children + 1] = aspectsNode
        else
            secretsNode.children[#secretsNode.children + 1] = {label = "Secret Aspects: None"}
        end

        frameNode.children[#frameNode.children + 1] = secretsNode
    end

    data[1] = frameNode
    return data
end

function InspectorTab:OnNodeSelected(node)
    -- If it's a child frame, inspect it
    if node.childFrame and self.currentFrame then
        local children = {self.currentFrame:GetChildren()}
        -- Use index if available (works for unnamed frames)
        if node.childIndex and children[node.childIndex] then
            if MedaDebug.FrameInspector then
                self.isLocked = false  -- Unlock to allow new inspection
                MedaDebug.FrameInspector:InspectFrame(children[node.childIndex])
            end
        end
    end
end

function InspectorTab:CopyFramePath()
    if not self.currentFrame or not MedaDebug.FrameInspector then return end
    
    local path = MedaDebug.FrameInspector:GetFramePath(self.currentFrame)
    
    -- Copy to clipboard via edit box
    if MedaUI.copyDialog then
        MedaUI.copyDialog.editBox:SetText(path)
        MedaUI.copyDialog.editBox:HighlightText()
        MedaUI.copyDialog:Show()
    end
end

function InspectorTab:WatchFrame()
    if not self.currentFrame then return end

    local name = self.currentFrame:GetName()
    if name and MedaDebug.VariableWatch then
        MedaDebug.VariableWatch:AddWatch(name)
        MedaDebug:LogInternal("MedaDebug", "Added " .. name .. " to watch list", "INFO")
    end
end

function InspectorTab:CopySecrets()
    if not self.currentInfo or not MedaDebug.SecretsExplorer then return end

    local text = MedaDebug.SecretsExplorer:FormatForCopy(self.currentInfo)

    -- Use MedaUI's shared TextViewer
    MedaUI:ShowTextViewer("Secrets Report - Press Ctrl+C to copy", text)
end

function InspectorTab:Copy()
    if not self.currentInfo then return end

    local info = self.currentInfo
    local lines = {
        "=== MedaDebug Frame Inspector ===",
        "Frame: " .. (info.name or "(unnamed)"),
        "Type: " .. (info.type or "?"),
        "Parent: " .. (info.parent or "nil"),
        "Source: " .. (info.source or "Unknown"),
        "",
        "=== Properties ===",
        "Size: " .. math.floor(info.width or 0) .. " x " .. math.floor(info.height or 0),
        "Visible: " .. (info.isVisible and "Yes" or "No"),
        "Shown: " .. (info.isShown and "Yes" or "No"),
        "Alpha: " .. string.format("%.2f", info.alpha or 1),
        "Frame Level: " .. tostring(info.frameLevel or "N/A"),
        "Frame Strata: " .. tostring(info.frameStrata or "N/A"),
        "Effective Scale: " .. string.format("%.3f", info.effectiveScale or 1),
        "",
    }

    -- Anchors
    if info.points and #info.points > 0 then
        lines[#lines + 1] = "=== Anchors ==="
        for i, point in ipairs(info.points) do
            lines[#lines + 1] = string.format("%d. %s -> %s (%s, %.0f, %.0f)",
                i, point.point, point.relativeTo or "nil",
                point.relativePoint, point.x or 0, point.y or 0)
        end
        lines[#lines + 1] = ""
    end

    -- Scripts
    if info.scripts and #info.scripts > 0 then
        lines[#lines + 1] = "=== Scripts ==="
        lines[#lines + 1] = table.concat(info.scripts, ", ")
        lines[#lines + 1] = ""
    end

    -- Children
    if info.children and #info.children > 0 then
        lines[#lines + 1] = "=== Children (" .. #info.children .. ") ==="
        for _, child in ipairs(info.children) do
            lines[#lines + 1] = "- " .. child.name .. " (" .. child.type .. ")"
        end
        lines[#lines + 1] = ""
    end

    -- Widget Values
    if info.widgetValues then
        local wv = info.widgetValues
        if wv.statusBar then
            local sb = wv.statusBar
            lines[#lines + 1] = "=== StatusBar Values ==="
            lines[#lines + 1] = "Value: " .. tostring(sb.value) .. " / " .. tostring(sb.max) .. " (" .. tostring(sb.percent) .. "%)"
            lines[#lines + 1] = "Min: " .. tostring(sb.min) .. ", Max: " .. tostring(sb.max)
            lines[#lines + 1] = "Orientation: " .. tostring(sb.orientation)
            if sb.texture then lines[#lines + 1] = "Texture: " .. tostring(sb.texture) end
            if sb.color then lines[#lines + 1] = "Color (RGBA): " .. tostring(sb.color) end
            lines[#lines + 1] = ""
        end
        if wv.button then
            local btn = wv.button
            lines[#lines + 1] = "=== Button Values ==="
            lines[#lines + 1] = "Text: " .. tostring(btn.text or "(none)")
            lines[#lines + 1] = "Enabled: " .. tostring(btn.enabled)
            lines[#lines + 1] = ""
        end
        if wv.slider then
            local sl = wv.slider
            lines[#lines + 1] = "=== Slider Values ==="
            lines[#lines + 1] = "Value: " .. tostring(sl.value) .. " (Range: " .. tostring(sl.min) .. " - " .. tostring(sl.max) .. ")"
            lines[#lines + 1] = ""
        end
    end

    -- Regions
    if info.regions and #info.regions > 0 then
        lines[#lines + 1] = "=== Regions (" .. #info.regions .. ") ==="
        for _, region in ipairs(info.regions) do
            local label = "- " .. region.name .. " (" .. region.type .. ")"
            if region.text then
                label = label .. ': "' .. region.text:sub(1, 50) .. '"'
            end
            lines[#lines + 1] = label
            -- Add texture/font details
            if region.texture then
                lines[#lines + 1] = "    Texture: " .. tostring(region.texture)
            end
            if region.textColor then
                lines[#lines + 1] = "    Color: " .. region.textColor
            end
        end
        lines[#lines + 1] = ""
    end

    -- Secrets
    if info.secrets then
        local secrets = info.secrets
        lines[#lines + 1] = "=== Secrets ==="
        lines[#lines + 1] = "Has Secret Values: " .. (secrets.hasSecretValues and "Yes" or "No")
        lines[#lines + 1] = "Anchoring Secret: " .. (secrets.isAnchoringSecret and "Yes" or "No")
        lines[#lines + 1] = "Preventing Secrets: " .. (secrets.isPreventingSecretValues and "Yes" or "No")
        if secrets.secretAspects and #secrets.secretAspects > 0 then
            lines[#lines + 1] = "Secret Aspects: " .. table.concat(secrets.secretAspects, ", ")
        end
    end

    local text = table.concat(lines, "\n")
    MedaUI:ShowTextViewer("Frame Info - Press Ctrl+C to copy", text)
end

function InspectorTab:ShowIgnoredFramesPanel()
    local Theme = MedaUI:GetTheme()

    -- Create panel if it doesn't exist
    if not self.ignoredPanel then
        local panel = CreateFrame("Frame", "MedaDebugIgnoredFramesPanel", UIParent, "BackdropTemplate")
        panel:SetSize(300, 400)
        panel:SetPoint("CENTER")
        panel:SetFrameStrata("DIALOG")
        panel:SetMovable(true)
        panel:EnableMouse(true)
        panel:RegisterForDrag("LeftButton")
        panel:SetScript("OnDragStart", panel.StartMoving)
        panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
        panel:SetBackdrop(MedaUI:CreateBackdrop(true))
        panel:SetBackdropColor(unpack(Theme.background))
        panel:SetBackdropBorderColor(unpack(Theme.border))
        panel:Hide()

        -- Title bar
        local titleBar = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        titleBar:SetPoint("TOPLEFT", 1, -1)
        titleBar:SetPoint("TOPRIGHT", -1, -1)
        titleBar:SetHeight(24)
        titleBar:SetBackdrop(MedaUI:CreateBackdrop(false))
        titleBar:SetBackdropColor(unpack(Theme.backgroundLight))

        local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", 8, 0)
        title:SetText("Ignored Frames")
        title:SetTextColor(unpack(Theme.gold))

        -- Close button
        local closeBtn = CreateFrame("Button", nil, titleBar)
        closeBtn:SetSize(20, 20)
        closeBtn:SetPoint("RIGHT", -2, 0)
        closeBtn:SetNormalFontObject("GameFontNormal")
        closeBtn:SetText("x")
        closeBtn:GetFontString():SetTextColor(unpack(Theme.textDim))
        closeBtn:SetScript("OnClick", function() panel:Hide() end)
        closeBtn:SetScript("OnEnter", function(button) button:GetFontString():SetTextColor(1, 0.3, 0.3) end)
        closeBtn:SetScript("OnLeave", function(button) button:GetFontString():SetTextColor(unpack(Theme.textDim)) end)

        -- Hint text
        local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", 8, -32)
        hint:SetPoint("TOPRIGHT", -8, -32)
        hint:SetJustifyH("LEFT")
        hint:SetText("|cffaaaaaa(Press 'I' during inspect mode to ignore hovered frame)|r")
        panel.hint = hint

        -- Scroll frame for list (AF custom scrollbar)
        local scrollParent = MedaUI:CreateScrollFrame(panel)
        Pixel.SetPoint(scrollParent, "TOPLEFT", 8, -50)
        Pixel.SetPoint(scrollParent, "BOTTOMRIGHT", -8, 40)
        scrollParent:SetScrollStep(30)

        panel.content = scrollParent.scrollContent
        Pixel.SetHeight(panel.content, 1)

        -- Clear All button
        local clearAllBtn = MedaUI:CreateButton(panel, "Clear All User", 100, 22)
        clearAllBtn:SetPoint("BOTTOMLEFT", 8, 8)
        clearAllBtn:SetScript("OnClick", function()
            if MedaDebug.FrameInspector then
                MedaDebug.FrameInspector:ClearIgnoredFrames()
                self:RefreshIgnoredFramesPanel()
            end
        end)

        -- Close button at bottom
        local closeBottomBtn = MedaUI:CreateButton(panel, "Close", 60, 22)
        closeBottomBtn:SetPoint("BOTTOMRIGHT", -8, 8)
        closeBottomBtn:SetScript("OnClick", function() panel:Hide() end)

        self.ignoredPanel = panel

        -- Allow ESC to close
        tinsert(UISpecialFrames, "MedaDebugIgnoredFramesPanel")
    end

    self:RefreshIgnoredFramesPanel()
    self.ignoredPanel:Show()
end

function InspectorTab:RefreshIgnoredFramesPanel()
    if not self.ignoredPanel or not MedaDebug.FrameInspector then return end

    local Theme = MedaUI:GetTheme()
    local content = self.ignoredPanel.content

    -- Clear existing rows
    if content.rows then
        for _, row in ipairs(content.rows) do
            row:Hide()
            row:SetParent(nil)
        end
    end
    content.rows = {}

    local defaults, userIgnored = MedaDebug.FrameInspector:GetIgnoredFrames()
    local yOffset = 0

    -- Default frames section
    if #defaults > 0 then
        local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", 0, -yOffset)
        header:SetText("|cffFFCC00Default (built-in):|r")
        content.rows[#content.rows + 1] = header
        yOffset = yOffset + 18

        for _, name in ipairs(defaults) do
            local row = CreateFrame("Frame", nil, content)
            row:SetSize(250, 18)
            row:SetPoint("TOPLEFT", 0, -yOffset)

            local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", 8, 0)
            text:SetText("|cff888888" .. name .. "|r")
            text:SetJustifyH("LEFT")

            content.rows[#content.rows + 1] = row
            yOffset = yOffset + 18
        end

        yOffset = yOffset + 10
    end

    -- User frames section
    local userHeader = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    userHeader:SetPoint("TOPLEFT", 0, -yOffset)
    userHeader:SetText("|cff00FF00User Ignored:|r")
    content.rows[#content.rows + 1] = userHeader
    yOffset = yOffset + 18

    if #userIgnored == 0 then
        local emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        emptyText:SetPoint("TOPLEFT", 8, -yOffset)
        emptyText:SetText("|cff666666(none)|r")
        content.rows[#content.rows + 1] = emptyText
        yOffset = yOffset + 18
    else
        for _, name in ipairs(userIgnored) do
            local row = CreateFrame("Button", nil, content)
            row:SetSize(250, 18)
            row:SetPoint("TOPLEFT", 0, -yOffset)

            local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", 8, 0)
            text:SetText(name)
            text:SetTextColor(unpack(Theme.text))
            row.text = text

            local removeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            removeText:SetPoint("RIGHT", -4, 0)
            removeText:SetText("|cffFF4444[x]|r")
            removeText:Hide()
            row.removeText = removeText

            row:SetScript("OnEnter", function(button)
                button.text:SetTextColor(1, 1, 1)
                button.removeText:Show()
            end)
            row:SetScript("OnLeave", function(button)
                button.text:SetTextColor(unpack(Theme.text))
                button.removeText:Hide()
            end)
            row:SetScript("OnClick", function()
                MedaDebug.FrameInspector:RemoveIgnoredFrame(name)
                self:RefreshIgnoredFramesPanel()
            end)

            content.rows[#content.rows + 1] = row
            yOffset = yOffset + 18
        end
    end

    content:SetHeight(yOffset + 10)
end

function InspectorTab:OnShow()
    -- If we have an inspected frame, refresh the view
    if self.currentInfo then
        self:OnFrameInspected(self.currentFrame, self.currentInfo)
    end
end

function InspectorTab:Clear()
    self.currentFrame = nil
    self.currentInfo = nil
    self.isLocked = false
    self.isPreview = false
    local Theme = MedaUI:GetTheme()
    self.frameLabel:SetTextColor(unpack(Theme.text))
    self.frameLabel:SetText("No frame selected")
    self.treeView:SetData({})
end
