--[[
    MedaDebug Workspace Registry
    Declares workspace groups and page metadata for the main shell
]]

local _, MedaDebug = ...

local WorkspaceRegistry = {}
MedaDebug.WorkspaceRegistry = WorkspaceRegistry

WorkspaceRegistry.groups = {}
WorkspaceRegistry.pages = {}

local function CopyDefinition(definition)
    local copy = {}
    for key, value in pairs(definition or {}) do
        copy[key] = value
    end
    return copy
end

local function SortGroups(a, b)
    if a.order ~= b.order then
        return a.order < b.order
    end

    return a.id < b.id
end

function WorkspaceRegistry:RegisterGroup(id, definition)
    local entry = CopyDefinition(definition)
    entry.id = id
    entry.order = entry.order or 100
    entry.pages = entry.pages or {}
    self.groups[id] = entry
    return entry
end

local function RemovePageFromGroup(group, pageId)
    if not group or not group.pages then
        return
    end

    for index = #group.pages, 1, -1 do
        if group.pages[index] == pageId then
            table.remove(group.pages, index)
        end
    end
end

local function SortGroupPages(self, group)
    table.sort(group.pages, function(leftId, rightId)
        local leftPage = self.pages[leftId] or {}
        local rightPage = self.pages[rightId] or {}
        local leftOrder = leftPage.pageOrder or 100
        local rightOrder = rightPage.pageOrder or 100
        if leftOrder ~= rightOrder then
            return leftOrder < rightOrder
        end

        return leftId < rightId
    end)
end

function WorkspaceRegistry:EnsureGroup(groupId, definition)
    local group = self.groups[groupId]
    if not group then
        group = self:RegisterGroup(groupId, definition)
    else
        if definition.label then
            group.label = definition.label
        end
        if definition.order then
            group.order = definition.order
        end
    end

    return group
end

function WorkspaceRegistry:RegisterPage(id, definition)
    local existing = self.pages[id]
    if existing and existing.groupId then
        RemovePageFromGroup(self.groups[existing.groupId], id)
    end

    local entry = CopyDefinition(definition)
    entry.id = id
    self.pages[id] = entry

    if entry.groupId then
        local group = self:EnsureGroup(entry.groupId, {
            label = entry.groupLabel or entry.groupId,
            order = entry.groupOrder or 100,
        })
        group.pages[#group.pages + 1] = id
        SortGroupPages(self, group)
    end

    return entry
end

function WorkspaceRegistry:GetGroup(id)
    return self.groups[id]
end

function WorkspaceRegistry:GetGroups()
    local result = {}

    for _, entry in pairs(self.groups) do
        result[#result + 1] = entry
    end

    table.sort(result, SortGroups)
    return result
end

function WorkspaceRegistry:GetPage(id)
    return self.pages[id]
end

function WorkspaceRegistry:GetPages()
    return self.pages
end

function WorkspaceRegistry:GetDefaultPageId()
    local groups = self:GetGroups()
    for i = 1, #groups do
        local group = groups[i]
        if group.pages and group.pages[1] then
            return group.pages[1]
        end
    end

    return nil
end

function WorkspaceRegistry:BuildNavigation(groupState, context)
    local items = {}
    context = context or {}

    for _, group in ipairs(self:GetGroups()) do
        local children = {}

        for i = 1, #group.pages do
            local pageId = group.pages[i]
            local page = self.pages[pageId]
            if page then
                local label = page.label
                if page.navLabel then
                    label = page.navLabel(page, context)
                end

                children[#children + 1] = {
                    pageId = pageId,
                    label = label,
                }
            end
        end

        items[#items + 1] = {
            pageId = group.id,
            label = group.label,
            expanded = groupState[group.id] ~= false,
            children = children,
        }
    end

    return items
end
