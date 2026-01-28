--[[
    MedaDebug Inspector Tab
    Frame inspection UI with tree navigation
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local InspectorTab = {}
MedaDebug.InspectorTab = InspectorTab

InspectorTab.frame = nil
InspectorTab.treeView = nil
InspectorTab.currentFrame = nil

function InspectorTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()
    
    -- Inspect button
    self.inspectBtn = MedaUI:CreateButton(parent, "Inspect Mode", 100, 22)
    self.inspectBtn:SetPoint("TOPLEFT", 0, 0)
    self.inspectBtn:SetScript("OnClick", function()
        if MedaDebug.FrameInspector then
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
    self.copyPathBtn = MedaUI:CreateButton(parent, "Copy Path", 80, 22)
    self.copyPathBtn:SetPoint("BOTTOMLEFT", 0, 0)
    self.copyPathBtn:SetScript("OnClick", function()
        self:CopyFramePath()
    end)
    
    self.watchBtn = MedaUI:CreateButton(parent, "Watch", 60, 22)
    self.watchBtn:SetPoint("LEFT", self.copyPathBtn, "RIGHT", 4, 0)
    self.watchBtn:SetScript("OnClick", function()
        self:WatchFrame()
    end)
    
    -- Connect to frame inspector
    if MedaDebug.FrameInspector then
        MedaDebug.FrameInspector.onFrameInspected = function(frame, info)
            self:OnFrameInspected(frame, info)
        end
    end
end

function InspectorTab:OnFrameInspected(frame, info)
    self.currentFrame = frame
    self.currentInfo = info
    
    if not info then return end
    
    -- Update label
    self.frameLabel:SetText(info.name .. " (" .. info.type .. ")")
    
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
            {label = "Size: " .. math.floor(info.width) .. " x " .. math.floor(info.height)},
            {label = "Visible: " .. (info.isVisible and "Yes" or "No")},
            {label = "Alpha: " .. string.format("%.2f", info.alpha)},
            {label = "Level: " .. tostring(info.frameLevel)},
            {label = "Strata: " .. tostring(info.frameStrata)},
        }
    }
    frameNode.children[#frameNode.children + 1] = propsNode
    
    -- Anchors
    if info.points and #info.points > 0 then
        local anchorsNode = {
            label = "Anchors (" .. #info.points .. ")",
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
            children = {}
        }
        for _, child in ipairs(info.children) do
            childrenNode.children[#childrenNode.children + 1] = {
                label = child.name .. " (" .. child.type .. ")",
                childFrame = child,
            }
        end
        frameNode.children[#frameNode.children + 1] = childrenNode
    end
    
    -- Regions
    if info.regions and #info.regions > 0 then
        local regionsNode = {
            label = "Regions (" .. #info.regions .. ")",
            children = {}
        }
        for _, region in ipairs(info.regions) do
            local label = region.name .. " (" .. region.type .. ")"
            if region.text then
                label = label .. ': "' .. region.text:sub(1, 30) .. '"'
            end
            regionsNode.children[#regionsNode.children + 1] = {label = label}
        end
        frameNode.children[#frameNode.children + 1] = regionsNode
    end
    
    data[1] = frameNode
    return data
end

function InspectorTab:OnNodeSelected(node)
    -- If it's a child frame, inspect it
    if node.childFrame and self.currentFrame then
        local children = {self.currentFrame:GetChildren()}
        for _, child in ipairs(children) do
            local name = child:GetName()
            if name == node.childFrame.name then
                if MedaDebug.FrameInspector then
                    MedaDebug.FrameInspector:InspectFrame(child)
                end
                break
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

function InspectorTab:OnShow()
    -- If we have an inspected frame, refresh the view
    if self.currentInfo then
        self:OnFrameInspected(self.currentFrame, self.currentInfo)
    end
end

function InspectorTab:Clear()
    self.currentFrame = nil
    self.currentInfo = nil
    self.frameLabel:SetText("No frame selected")
    self.treeView:SetData({})
end
