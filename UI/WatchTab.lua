--[[
    MedaDebug Watch Tab
    Variable/table monitoring with live updates
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local WatchTab = {}
MedaDebug.WatchTab = WatchTab

WatchTab.frame = nil
WatchTab.treeView = nil

function WatchTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()
    
    -- Add watch input
    self.addInput = MedaUI:CreateEditBox(parent, 200, 24)
    self.addInput:SetPoint("TOPLEFT", 0, 0)
    self.addInput:SetPlaceholder("Variable path (e.g. MyAddon.db)")
    
    self.addBtn = MedaUI:CreateButton(parent, "Add", 50, 22)
    self.addBtn:SetPoint("LEFT", self.addInput, "RIGHT", 4, 0)
    self.addBtn:SetScript("OnClick", function()
        self:AddWatch()
    end)
    
    self.addInput.OnEnterPressed = function()
        self:AddWatch()
    end
    
    -- Clear all button
    self.clearBtn = MedaUI:CreateButton(parent, "Clear All", 70, 22)
    self.clearBtn:SetPoint("LEFT", self.addBtn, "RIGHT", 8, 0)
    self.clearBtn:SetScript("OnClick", function()
        if MedaDebug.VariableWatch then
            MedaDebug.VariableWatch:ClearAll()
        end
        self:RefreshData()
    end)
    
    -- Tree view for watches
    self.treeView = MedaUI:CreateTreeView(parent, parent:GetWidth(), parent:GetHeight() - 30)
    self.treeView:SetPoint("TOPLEFT", 0, -28)
    self.treeView:SetPoint("BOTTOMRIGHT", 0, 0)
    
    self.treeView.OnNodeClick = function(_, node, path)
        if node.watchPath then
            -- Toggle expanded
            if MedaDebug.VariableWatch then
                MedaDebug.VariableWatch:ToggleExpanded(node.watchPath)
            end
            self:RefreshData()
        end
    end
    
    self.treeView.OnNodeRightClick = function(_, node, path)
        if node.watchPath then
            -- Show context menu to remove
            self:ShowWatchContextMenu(node)
        end
    end
    
    -- Connect to variable watch
    if MedaDebug.VariableWatch then
        MedaDebug.VariableWatch.onWatchUpdated = function(watch, changed)
            self:RefreshData()
        end
        MedaDebug.VariableWatch.onWatchAdded = function(watch)
            self:RefreshData()
        end
        MedaDebug.VariableWatch.onWatchRemoved = function(watch)
            self:RefreshData()
        end
    end
    
    self:RefreshData()
end

function WatchTab:AddWatch()
    local path = self.addInput:GetText()
    if path and path ~= "" and MedaDebug.VariableWatch then
        if MedaDebug.VariableWatch:AddWatch(path) then
            self.addInput:SetText("")
            self:RefreshData()
        end
    end
end

function WatchTab:RefreshData()
    if not self.treeView or not MedaDebug.VariableWatch then return end
    
    local watches = MedaDebug.VariableWatch:GetWatches()
    local treeData = {}
    
    for _, watch in ipairs(watches) do
        local node = self:BuildWatchNode(watch)
        treeData[#treeData + 1] = node
    end
    
    self.treeView:SetData(treeData)
end

function WatchTab:BuildWatchNode(watch)
    local Theme = MedaUI:GetTheme()
    
    local node = {
        label = watch.path,
        watchPath = watch.path,
        expanded = watch.expanded,
        children = {},
    }
    
    -- Add value info
    if not watch.exists then
        node.children[#node.children + 1] = {
            label = "= (undefined)",
        }
    elseif watch.valueType == "table" and watch.expanded then
        -- Show table contents
        local value = watch.currentValue
        if type(value) == "table" then
            local count = 0
            for k, v in pairs(value) do
                count = count + 1
                if count > 20 then
                    node.children[#node.children + 1] = {label = "... (more entries)"}
                    break
                end
                local keyStr = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
                local valStr = MedaDebug.VariableWatch:SerializeValue(v, 1)
                node.children[#node.children + 1] = {
                    label = keyStr .. " = " .. valStr,
                }
            end
        end
    else
        local valStr = MedaDebug.VariableWatch:SerializeValue(watch.currentValue, 2)
        node.children[#node.children + 1] = {
            label = "= " .. valStr,
        }
    end
    
    -- Show change info
    if watch.lastChanged then
        local ago = GetTime() - watch.lastChanged
        if ago < 5 then
            node.children[#node.children + 1] = {
                label = "(changed " .. string.format("%.1f", ago) .. "s ago)",
            }
        end
    end
    
    return node
end

function WatchTab:ShowWatchContextMenu(node)
    local menu = MedaUI:CreateContextMenu({
        {label = "Remove Watch", onClick = function()
            if MedaDebug.VariableWatch then
                MedaDebug.VariableWatch:RemoveWatch(node.watchPath)
            end
        end},
        {label = "Copy Path", onClick = function()
            if MedaUI.copyDialog then
                MedaUI.copyDialog.editBox:SetText(node.watchPath)
                MedaUI.copyDialog.editBox:HighlightText()
                MedaUI.copyDialog:Show()
            end
        end},
    })
    menu:ShowAtCursor()
end

function WatchTab:OnShow()
    self:RefreshData()
end

function WatchTab:Clear()
    if MedaDebug.VariableWatch then
        MedaDebug.VariableWatch:ClearAll()
    end
    self:RefreshData()
end
