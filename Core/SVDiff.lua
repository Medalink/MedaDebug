--[[
    MedaDebug SavedVariables Diff
    Track what changed in SavedVariables between reloads
]]

local addonName, MedaDebug = ...

local SVDiff = {}
MedaDebug.SVDiff = SVDiff

-- Snapshot storage
SVDiff.snapshot = {}
SVDiff.lastSnapshot = nil
SVDiff.diff = {}

-- Known SavedVariables to track
SVDiff.trackedSVs = {}

function SVDiff:Initialize()
    -- Discover SavedVariables from loaded addons
    self:DiscoverSavedVariables()
    
    -- Take initial snapshot
    self:TakeSnapshot()
end

--- Discover SavedVariables from TOC files
function SVDiff:DiscoverSavedVariables()
    wipe(self.trackedSVs)
    
    -- C_AddOns API for WoW 11.0+
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        local sv = C_AddOns.GetAddOnMetadata(i, "SavedVariables")
        local svpc = C_AddOns.GetAddOnMetadata(i, "SavedVariablesPerCharacter")
        
        if sv then
            for varName in sv:gmatch("[^,%s]+") do
                self.trackedSVs[varName] = name
            end
        end
        if svpc then
            for varName in svpc:gmatch("[^,%s]+") do
                self.trackedSVs[varName] = name
            end
        end
    end
end

--- Deep copy a table
--- @param tbl table Table to copy
--- @param maxDepth number Maximum depth
--- @return table Copy
local function DeepCopy(tbl, maxDepth, depth)
    depth = depth or 0
    maxDepth = maxDepth or 5
    
    if depth > maxDepth then return "..." end
    if type(tbl) ~= "table" then return tbl end
    
    local copy = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            copy[k] = DeepCopy(v, maxDepth, depth + 1)
        else
            copy[k] = v
        end
    end
    return copy
end

--- Take a snapshot of all tracked SavedVariables
function SVDiff:TakeSnapshot()
    self.lastSnapshot = self.snapshot
    self.snapshot = {}
    
    for varName, addonName in pairs(self.trackedSVs) do
        local value = _G[varName]
        if value ~= nil then
            self.snapshot[varName] = {
                addon = addonName,
                data = DeepCopy(value, 4),
                timestamp = GetTime(),
            }
        end
    end
    
    return self.snapshot
end

--- Compare two values
--- @param old any Old value
--- @param new any New value
--- @param path string Current path
--- @param changes table Changes accumulator
local function CompareValues(old, new, path, changes, maxDepth, depth)
    depth = depth or 0
    maxDepth = maxDepth or 4
    
    if depth > maxDepth then return end
    
    local oldType = type(old)
    local newType = type(new)
    
    if oldType ~= newType then
        changes[#changes + 1] = {
            path = path,
            type = "type_changed",
            old = tostring(old),
            new = tostring(new),
            oldType = oldType,
            newType = newType,
        }
        return
    end
    
    if oldType == "table" then
        -- Check for removed keys
        for k in pairs(old) do
            local newPath = path .. "." .. tostring(k)
            if new[k] == nil then
                changes[#changes + 1] = {
                    path = newPath,
                    type = "removed",
                    old = old[k],
                }
            end
        end
        
        -- Check for added or changed keys
        for k, v in pairs(new) do
            local newPath = path .. "." .. tostring(k)
            if old[k] == nil then
                changes[#changes + 1] = {
                    path = newPath,
                    type = "added",
                    new = v,
                }
            else
                CompareValues(old[k], v, newPath, changes, maxDepth, depth + 1)
            end
        end
    elseif old ~= new then
        changes[#changes + 1] = {
            path = path,
            type = "changed",
            old = old,
            new = new,
        }
    end
end

--- Calculate diff between snapshots
--- @return table Diff results
function SVDiff:CalculateDiff()
    if not self.lastSnapshot then
        return {}
    end
    
    self.diff = {}
    
    for varName, newSnap in pairs(self.snapshot) do
        local oldSnap = self.lastSnapshot[varName]
        local changes = {}
        
        if not oldSnap then
            changes[#changes + 1] = {
                path = varName,
                type = "added",
                new = "(new variable)",
            }
        else
            CompareValues(oldSnap.data, newSnap.data, varName, changes)
        end
        
        if #changes > 0 then
            self.diff[varName] = {
                addon = newSnap.addon,
                changes = changes,
            }
        end
    end
    
    -- Check for removed variables
    for varName, oldSnap in pairs(self.lastSnapshot) do
        if not self.snapshot[varName] then
            self.diff[varName] = {
                addon = oldSnap.addon,
                changes = {{
                    path = varName,
                    type = "removed",
                    old = "(variable removed)",
                }},
            }
        end
    end
    
    return self.diff
end

--- Get diff results
--- @return table Diff by variable
function SVDiff:GetDiff()
    return self.diff
end

--- Get diff for a specific addon
--- @param addonName string Addon name
--- @return table Changes for addon
function SVDiff:GetAddonDiff(addonName)
    local result = {}
    for varName, data in pairs(self.diff) do
        if data.addon == addonName then
            result[varName] = data
        end
    end
    return result
end

--- Format diff for display
--- @return string Formatted diff text
function SVDiff:FormatDiff()
    local lines = {}
    
    if next(self.diff) == nil then
        return "No changes detected since last snapshot."
    end
    
    -- Group by addon
    local byAddon = {}
    for varName, data in pairs(self.diff) do
        local addon = data.addon or "Unknown"
        if not byAddon[addon] then byAddon[addon] = {} end
        byAddon[addon][varName] = data
    end
    
    for addon, vars in pairs(byAddon) do
        lines[#lines + 1] = addon .. ":"
        for varName, data in pairs(vars) do
            for _, change in ipairs(data.changes) do
                local desc
                if change.type == "added" then
                    desc = "+ " .. change.path .. " (new)"
                elseif change.type == "removed" then
                    desc = "- " .. change.path .. " (removed)"
                elseif change.type == "changed" then
                    local oldStr = tostring(change.old):sub(1, 20)
                    local newStr = tostring(change.new):sub(1, 20)
                    desc = "  " .. change.path .. ": " .. oldStr .. " → " .. newStr
                elseif change.type == "type_changed" then
                    desc = "  " .. change.path .. ": type " .. change.oldType .. " → " .. change.newType
                end
                lines[#lines + 1] = "  " .. desc
            end
        end
        lines[#lines + 1] = ""
    end
    
    return table.concat(lines, "\n")
end

--- Show diff (via chat or UI)
function SVDiff:ShowDiff()
    self:CalculateDiff()
    
    if next(self.diff) == nil then
        print("|cff00ff00[MedaDebug]|r No SavedVariables changes since last snapshot")
        return
    end
    
    print("|cff00ff00[MedaDebug]|r SavedVariables changes:")
    
    local count = 0
    for varName, data in pairs(self.diff) do
        count = count + #data.changes
        print("  |cffffcc00" .. data.addon .. "/" .. varName .. "|r: " .. #data.changes .. " change(s)")
    end
    
    print("  Total: " .. count .. " changes. Use /mdebug system to see details.")
end

--- Check if there are any changes
--- @return boolean
function SVDiff:HasChanges()
    return next(self.diff) ~= nil
end

--- Get change count
--- @return number
function SVDiff:GetChangeCount()
    local count = 0
    for _, data in pairs(self.diff) do
        count = count + #data.changes
    end
    return count
end
