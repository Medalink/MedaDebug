--[[
    MedaDebug Runtime Registry
    Declares startup-owned modules and optional runtime gates
]]

local _, MedaDebug = ...

local RuntimeRegistry = {}
MedaDebug.RuntimeRegistry = RuntimeRegistry

RuntimeRegistry.modules = {}

local function CopyDefinition(definition)
    local copy = {}
    for key, value in pairs(definition or {}) do
        copy[key] = value
    end
    return copy
end

local function SortModules(a, b)
    if a.order ~= b.order then
        return a.order < b.order
    end

    return a.id < b.id
end

function RuntimeRegistry:RegisterModule(id, definition)
    local entry = CopyDefinition(definition)
    entry.id = id
    entry.moduleKey = entry.moduleKey or id
    entry.phase = entry.phase or "PLAYER_LOGIN"
    entry.order = entry.order or 100

    self.modules[id] = entry
    return entry
end

function RuntimeRegistry:GetModule(id)
    return self.modules[id]
end

function RuntimeRegistry:GetModulesForPhase(phase)
    local result = {}

    for _, entry in pairs(self.modules) do
        if entry.phase == phase then
            result[#result + 1] = entry
        end
    end

    table.sort(result, SortModules)
    return result
end

function RuntimeRegistry:ShouldInitialize(entry)
    if not entry.optionKey then
        return true
    end

    return MedaDebug.db
        and MedaDebug.db.options
        and MedaDebug.db.options[entry.optionKey]
        or false
end

function RuntimeRegistry:InitializePhase(phase)
    for _, entry in ipairs(self:GetModulesForPhase(phase)) do
        if self:ShouldInitialize(entry) then
            local module = MedaDebug[entry.moduleKey]
            if module and module.Initialize then
                module:Initialize()
            end
        end
    end
end
