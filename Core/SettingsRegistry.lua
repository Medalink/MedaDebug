local _, MedaDebug = ...

local SettingsRegistry = {}
MedaDebug.SettingsRegistry = SettingsRegistry

SettingsRegistry.modules = {}

local function CopyDefinition(definition)
    local copy = {}
    for key, value in pairs(definition or {}) do
        copy[key] = value
    end
    return copy
end

local function SortModules(a, b)
    if a.sidebarOrder ~= b.sidebarOrder then
        return a.sidebarOrder < b.sidebarOrder
    end

    return a.id < b.id
end

function SettingsRegistry:RegisterModule(id, definition)
    local entry = CopyDefinition(definition)
    entry.id = id
    self.modules[id] = entry
    return entry
end

function SettingsRegistry:GetModule(id)
    return self.modules[id]
end

function SettingsRegistry:GetModules()
    local result = {}

    for _, entry in pairs(self.modules) do
        result[#result + 1] = entry
    end

    table.sort(result, SortModules)
    return result
end

function SettingsRegistry:GetDefaultSelection()
    local modules = self:GetModules()
    local firstModule = modules[1]
    if not firstModule then
        return nil, nil
    end

    local firstPage = firstModule.pages and firstModule.pages[1]
    return firstModule.id, firstPage and firstPage.id or nil
end
