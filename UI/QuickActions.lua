--[[
    MedaDebug Quick Actions
    Action bar with common developer tools
    
    Note: The quick actions bar is created directly in DebugFrame.lua
    This file is reserved for future expansion of custom action functionality
]]

local addonName, MedaDebug = ...

local QuickActions = {}
MedaDebug.QuickActions = QuickActions

-- Custom action storage
QuickActions.customActions = {}

function QuickActions:Initialize()
    -- Load custom actions from saved variables
    if MedaDebug.db and MedaDebug.db.options.customActions then
        self.customActions = MedaDebug.db.options.customActions
    end
end

--- Add a custom action button
--- @param name string Button name
--- @param code string Lua code to execute
function QuickActions:AddCustomAction(name, code)
    self.customActions[#self.customActions + 1] = {
        name = name,
        code = code,
    }
    
    -- Save
    if MedaDebug.db then
        MedaDebug.db.options.customActions = self.customActions
    end
end

--- Remove a custom action
--- @param index number Action index
function QuickActions:RemoveCustomAction(index)
    table.remove(self.customActions, index)
    
    -- Save
    if MedaDebug.db then
        MedaDebug.db.options.customActions = self.customActions
    end
end

--- Execute a custom action
--- @param index number Action index
function QuickActions:ExecuteAction(index)
    local action = self.customActions[index]
    if action and action.code then
        local func, err = loadstring(action.code)
        if func then
            local success, result = pcall(func)
            if not success then
                MedaDebug:Log("MedaDebug", "Action error: " .. tostring(result), "ERROR")
            end
        else
            MedaDebug:Log("MedaDebug", "Action compile error: " .. tostring(err), "ERROR")
        end
    end
end

--- Get all custom actions
--- @return table Array of custom actions
function QuickActions:GetCustomActions()
    return self.customActions
end
