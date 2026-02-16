--[[
    MedaDebug Secrets Explorer
    Analyze WoW 12.0.0+ secret values and widget restrictions
]]

local addonName, MedaDebug = ...

local SecretsExplorer = {}
MedaDebug.SecretsExplorer = SecretsExplorer

-- Update settings
SecretsExplorer.updateInterval = 1.0
SecretsExplorer.updateTimer = nil

-- Callbacks
SecretsExplorer.onPredicatesUpdated = nil
SecretsExplorer.onRestrictionChanged = nil

-- Simulation state
SecretsExplorer.simulateRestrictions = {
    combat = false,
    mythicPlus = false,
    raid = false,
}

-- Cache for predicate states
SecretsExplorer.predicateCache = {}
SecretsExplorer.restrictionCache = {}

-- API Database for search functionality
SecretsExplorer.API_DATABASE = {
    -- Power/Resource APIs
    {
        category = "mana",
        aliases = {"power", "resource", "energy", "rage", "focus"},
        apis = {
            {name = "UnitPower", args = {"unit", "0"}, desc = "Current mana"},
            {name = "UnitPowerMax", args = {"unit", "0"}, desc = "Max mana"},
            {name = "UnitPowerType", args = {"unit"}, desc = "Power type"},
        },
    },
    -- Health APIs
    {
        category = "health",
        aliases = {"hp", "life"},
        apis = {
            {name = "UnitHealth", args = {"unit"}, desc = "Current health"},
            {name = "UnitHealthMax", args = {"unit"}, desc = "Max health"},
            {name = "UnitGetIncomingHeals", args = {"unit"}, desc = "Incoming heals"},
            {name = "UnitGetTotalAbsorbs", args = {"unit"}, desc = "Total absorbs"},
        },
    },
    -- Aura APIs
    {
        category = "aura",
        aliases = {"buff", "debuff", "auras"},
        apis = {
            {name = "C_UnitAuras.GetAuraDataByIndex", args = {"unit", "index"}, desc = "Aura info by index"},
            {name = "C_UnitAuras.GetPlayerAuraBySpellID", args = {"spellID"}, desc = "Player aura by spell"},
            {name = "C_UnitAuras.GetAuraDataBySlot", args = {"unit", "slot"}, desc = "Aura by slot"},
            {name = "C_UnitAuras.GetBuffDataByIndex", args = {"unit", "index"}, desc = "Buff by index"},
            {name = "C_UnitAuras.GetDebuffDataByIndex", args = {"unit", "index"}, desc = "Debuff by index"},
        },
    },
    -- Cooldown APIs
    {
        category = "cooldown",
        aliases = {"cd", "spell", "ability"},
        apis = {
            {name = "C_Spell.GetSpellCooldown", args = {"spellID"}, desc = "Spell cooldown info"},
            {name = "GetSpellCooldown", args = {"spellID"}, desc = "Spell cooldown (legacy)"},
            {name = "C_Spell.GetSpellCharges", args = {"spellID"}, desc = "Spell charges"},
        },
    },
    -- Unit identity
    {
        category = "unit",
        aliases = {"player", "target", "party", "raid", "identity", "name"},
        apis = {
            {name = "UnitName", args = {"unit"}, desc = "Unit name"},
            {name = "UnitGUID", args = {"unit"}, desc = "Unit GUID"},
            {name = "UnitClass", args = {"unit"}, desc = "Unit class"},
            {name = "UnitLevel", args = {"unit"}, desc = "Unit level"},
            {name = "UnitRace", args = {"unit"}, desc = "Unit race"},
            {name = "UnitFactionGroup", args = {"unit"}, desc = "Unit faction"},
            {name = "UnitIsPlayer", args = {"unit"}, desc = "Is a player"},
            {name = "UnitIsEnemy", args = {"player", "unit"}, desc = "Is enemy"},
            {name = "UnitIsFriend", args = {"player", "unit"}, desc = "Is friendly"},
        },
    },
    -- Position/Location
    {
        category = "position",
        aliases = {"location", "coords", "map"},
        apis = {
            {name = "UnitPosition", args = {"unit"}, desc = "Unit map position"},
            {name = "GetPlayerMapPosition", args = {"unit"}, desc = "Map position"},
            {name = "UnitDistanceSquared", args = {"unit"}, desc = "Distance squared"},
        },
    },
    -- Cast info
    {
        category = "cast",
        aliases = {"casting", "channeling", "spell"},
        apis = {
            {name = "UnitCastingInfo", args = {"unit"}, desc = "Current cast info"},
            {name = "UnitChannelInfo", args = {"unit"}, desc = "Current channel info"},
            {name = "C_Spell.GetCurrentCast", args = {}, desc = "Your current cast"},
        },
    },
    -- Combat info
    {
        category = "combat",
        aliases = {"threat", "aggro"},
        apis = {
            {name = "UnitThreatSituation", args = {"unit"}, desc = "Threat situation"},
            {name = "UnitDetailedThreatSituation", args = {"unit", "target"}, desc = "Detailed threat"},
            {name = "UnitAffectingCombat", args = {"unit"}, desc = "In combat"},
        },
    },
}

-- All C_Secrets predicates
SecretsExplorer.PREDICATES = {
    "ShouldUnitIdentityBeSecret",
    "ShouldCooldownsBeSecret",
    "ShouldAurasBeSecret",
    "ShouldSpellsBeSecret",
    "ShouldHealthBeSecret",
    "ShouldPowerBeSecret",
    "ShouldPositionBeSecret",
    "ShouldCastingBeSecret",
    "ShouldThreatBeSecret",
    "ShouldItemsBeSecret",
    "ShouldCurrencyBeSecret",
    "ShouldProfessionsBeSecret",
    "ShouldAchievementsBeSecret",
    "ShouldQuestsBeSecret",
    "ShouldReputationBeSecret",
    "ShouldPetBeSecret",
    "ShouldTalentsBeSecret",
}

-- Widget secret aspects
SecretsExplorer.WIDGET_ASPECTS = {
    "text",
    "texture",
    "position",
    "size",
    "alpha",
    "visibility",
    "color",
}

function SecretsExplorer:Initialize()
    -- Start periodic updates for predicates
    self:StartUpdates()

    -- Initial cache population
    self:RefreshPredicates()
    self:RefreshRestrictions()
end

--- Start periodic updates
function SecretsExplorer:StartUpdates()
    if self.updateTimer then
        self.updateTimer:Cancel()
    end

    self.updateTimer = C_Timer.NewTicker(self.updateInterval, function()
        local predicatesChanged = self:RefreshPredicates()
        local restrictionsChanged = self:RefreshRestrictions()

        if predicatesChanged and self.onPredicatesUpdated then
            self.onPredicatesUpdated(self.predicateCache)
        end

        if restrictionsChanged and self.onRestrictionChanged then
            self.onRestrictionChanged(self.restrictionCache)
        end
    end)
end

--- Stop updates
function SecretsExplorer:StopUpdates()
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
end

--- Refresh all predicate states
--- @return boolean True if any changed
function SecretsExplorer:RefreshPredicates()
    local changed = false

    for _, predicate in ipairs(self.PREDICATES) do
        local func = C_Secrets and C_Secrets[predicate]
        local value = false

        if func then
            local ok, result = pcall(func)
            if ok then
                value = result
            end
        end

        if self.predicateCache[predicate] ~= value then
            self.predicateCache[predicate] = value
            changed = true
        end
    end

    return changed
end

--- Refresh restriction states
--- @return boolean True if any changed
function SecretsExplorer:RefreshRestrictions()
    local changed = false
    local cache = self.restrictionCache

    -- CheckAllowProtectedFunctions
    local allowProtected = true
    if C_RestrictedActions and C_RestrictedActions.CheckAllowProtectedFunctions then
        local ok, result = pcall(C_RestrictedActions.CheckAllowProtectedFunctions)
        if ok then
            allowProtected = result
        end
    end
    if cache.allowProtectedFunctions ~= allowProtected then
        cache.allowProtectedFunctions = allowProtected
        changed = true
    end

    -- GetAddOnRestrictionState
    local restrictionState = "none"
    if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState then
        local ok, result = pcall(C_RestrictedActions.GetAddOnRestrictionState)
        if ok and result then
            restrictionState = result
        end
    end
    if cache.restrictionState ~= restrictionState then
        cache.restrictionState = restrictionState
        changed = true
    end

    -- IsAddOnRestrictionActive
    local restrictionActive = false
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive then
        local ok, result = pcall(C_RestrictedActions.IsAddOnRestrictionActive)
        if ok then
            restrictionActive = result
        end
    end
    if cache.restrictionActive ~= restrictionActive then
        cache.restrictionActive = restrictionActive
        changed = true
    end

    return changed
end

--- Get secret info for any value
--- @param value any The value to analyze
--- @return table Secret info
function SecretsExplorer:GetValueSecretInfo(value)
    local info = {
        isSecret = false,
        canAccess = true,
        valueType = type(value),
    }

    -- Check if issecretvalue exists (WoW 12.0.0+)
    if issecretvalue then
        local ok, result = pcall(issecretvalue, value)
        if ok then
            info.isSecret = result
        end
    end

    -- Check if canaccessvalue exists
    if canaccessvalue then
        local ok, result = pcall(canaccessvalue, value)
        if ok then
            info.canAccess = result
        end
    end

    -- For tables, check additional properties
    if type(value) == "table" then
        if issecrettable then
            local ok, result = pcall(issecrettable, value)
            if ok then
                info.isSecretTable = result
            end
        end

        if canaccesstable then
            local ok, result = pcall(canaccesstable, value)
            if ok then
                info.canAccessTable = result
            end
        end

        if hasanysecretvalues then
            local ok, result = pcall(hasanysecretvalues, value)
            if ok then
                info.hasSecretValues = result
            end
        end
    end

    return info
end

--- Get secret info for a widget
--- @param widget table The widget to analyze
--- @return table Widget secret info
function SecretsExplorer:GetWidgetSecretInfo(widget)
    if not widget then return nil end

    local info = {
        hasSecretValues = false,
        isAnchoringSecret = false,
        isPreventingSecretValues = false,
        secretAspects = {},
    }

    -- Check HasSecretValues
    if widget.HasSecretValues then
        local ok, result = pcall(widget.HasSecretValues, widget)
        if ok then
            info.hasSecretValues = result
        end
    end

    -- Check IsAnchoringSecret
    if widget.IsAnchoringSecret then
        local ok, result = pcall(widget.IsAnchoringSecret, widget)
        if ok then
            info.isAnchoringSecret = result
        end
    end

    -- Check IsPreventingSecretValues
    if widget.IsPreventingSecretValues then
        local ok, result = pcall(widget.IsPreventingSecretValues, widget)
        if ok then
            info.isPreventingSecretValues = result
        end
    end

    -- Check each aspect
    if widget.HasSecretAspect then
        for _, aspect in ipairs(self.WIDGET_ASPECTS) do
            local ok, result = pcall(widget.HasSecretAspect, widget, aspect)
            if ok and result then
                info.secretAspects[#info.secretAspects + 1] = aspect
            end
        end
    end

    return info
end

--- Get all predicate states
--- @return table Predicate states
function SecretsExplorer:GetAllPredicates()
    self:RefreshPredicates()
    return self.predicateCache
end

--- Get addon restriction info
--- @return table Restriction info
function SecretsExplorer:GetAddOnRestrictions()
    self:RefreshRestrictions()
    return self.restrictionCache
end

--- Get current context
--- @return table Current game context
function SecretsExplorer:GetCurrentContext()
    return {
        inCombat = InCombatLockdown and InCombatLockdown() or false,
        inMythicPlus = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() or false,
        inRaid = IsInRaid and IsInRaid() or false,
        inInstance = IsInInstance and IsInInstance() or false,
        instanceType = select(2, GetInstanceInfo()) or "none",
        inPvP = C_PvP and C_PvP.IsPVPMap and C_PvP.IsPVPMap() or false,
    }
end

--- Set simulation state
--- @param key string Restriction key (combat, mythicPlus, raid)
--- @param enabled boolean Whether to simulate
function SecretsExplorer:SetSimulation(key, enabled)
    if self.simulateRestrictions[key] ~= nil then
        self.simulateRestrictions[key] = enabled
    end
end

--- Get simulation state
--- @return table Simulation flags
function SecretsExplorer:GetSimulation()
    return self.simulateRestrictions
end

--- Check if any simulation is active
--- @return boolean
function SecretsExplorer:IsSimulating()
    return self.simulateRestrictions.combat or
           self.simulateRestrictions.mythicPlus or
           self.simulateRestrictions.raid
end

--- Search APIs by keyword
--- @param query string Search query
--- @return table Matching APIs with categories
function SecretsExplorer:SearchAPIs(query)
    if not query or query == "" then
        return {}
    end

    query = query:lower()
    local results = {}

    for _, category in ipairs(self.API_DATABASE) do
        local categoryMatch = category.category:lower():find(query, 1, true)
        local aliasMatch = false

        if category.aliases then
            for _, alias in ipairs(category.aliases) do
                if alias:lower():find(query, 1, true) then
                    aliasMatch = true
                    break
                end
            end
        end

        if categoryMatch or aliasMatch then
            -- Add all APIs from matching category
            for _, api in ipairs(category.apis) do
                results[#results + 1] = {
                    category = category.category,
                    api = api,
                }
            end
        else
            -- Check individual API names
            for _, api in ipairs(category.apis) do
                if api.name:lower():find(query, 1, true) or
                   api.desc:lower():find(query, 1, true) then
                    results[#results + 1] = {
                        category = category.category,
                        api = api,
                    }
                end
            end
        end
    end

    return results
end

--- Test an API with different units
--- @param apiName string API name
--- @param args table Base arguments
--- @param units table Units to test with
--- @return table Results per unit
function SecretsExplorer:TestAPI(apiName, args, units)
    units = units or {"player", "target", "party1", "raid1"}
    args = args or {}

    local results = {}

    for _, unit in ipairs(units) do
        local testArgs = {}
        for i, arg in ipairs(args) do
            if arg == "unit" then
                testArgs[i] = unit
            else
                testArgs[i] = arg
            end
        end

        results[unit] = self:TestAPICall(apiName, testArgs)
    end

    return results
end

--- Test a single API call
--- @param apiName string API name
--- @param args table Arguments
--- @return table Result info
function SecretsExplorer:TestAPICall(apiName, args)
    local result = {
        value = nil,
        valueStr = "???",
        isSecret = false,
        canAccess = true,
        error = nil,
        wouldBeSecret = false,
    }

    -- Find the function
    local func = _G[apiName]
    if not func then
        -- Try C_ namespace
        local namespace, method = apiName:match("^([^%.]+)%.(.+)$")
        if namespace and method and _G[namespace] then
            func = _G[namespace][method]
        end
    end

    if not func then
        result.error = "API not found"
        return result
    end

    -- Call the API
    local ok, ret1, ret2, ret3, ret4, ret5 = pcall(func, unpack(args))
    if not ok then
        result.error = ret1
        return result
    end

    result.value = ret1

    -- Check secret status
    if issecretvalue and ret1 ~= nil then
        local secretOk, isSecret = pcall(issecretvalue, ret1)
        if secretOk then
            result.isSecret = isSecret
        end
    end

    if canaccessvalue and ret1 ~= nil then
        local accessOk, canAccess = pcall(canaccessvalue, ret1)
        if accessOk then
            result.canAccess = canAccess
        end
    end

    -- Format value string
    if result.isSecret then
        result.valueStr = "???"
    elseif ret1 == nil then
        result.valueStr = "nil"
    elseif type(ret1) == "table" then
        result.valueStr = "{...}"
    elseif type(ret1) == "string" then
        result.valueStr = '"' .. tostring(ret1):sub(1, 30) .. '"'
    else
        result.valueStr = tostring(ret1)
    end

    -- Check simulation
    if self:IsSimulating() then
        -- For enemy/target units with simulated restrictions, assume would be secret
        local unit = args[1]
        if unit and type(unit) == "string" then
            local isEnemyUnit = (unit == "target" or unit:match("^arena") or
                                 unit:match("^enemy") or unit:match("^nameplate"))
            if isEnemyUnit then
                result.wouldBeSecret = true
            end
        end
    end

    return result
end

--- Test an API with simulation
--- @param apiName string API name
--- @param args table Base arguments
--- @param units table Units to test
--- @return table Results with simulation data
function SecretsExplorer:TestAPIWithSimulation(apiName, args, units)
    units = units or {"player", "target"}

    local results = {}

    for _, unit in ipairs(units) do
        local testArgs = {}
        for i, arg in ipairs(args) do
            if arg == "unit" then
                testArgs[i] = unit
            else
                testArgs[i] = arg
            end
        end

        local testResult = self:TestAPICall(apiName, testArgs)

        -- Determine simulation status
        if self:IsSimulating() then
            local isEnemyUnit = (unit == "target" or unit:match("^arena") or
                                 unit:match("^enemy") or unit:match("^nameplate"))

            if isEnemyUnit and not testResult.isSecret then
                testResult.wouldBeSecret = true
            end
        end

        results[unit] = testResult
    end

    return results
end

--- Format all secrets info for clipboard
--- @param frameInfo table Optional frame info to include
--- @return string Formatted text
function SecretsExplorer:FormatForCopy(frameInfo)
    local lines = {
        "=== MedaDebug Secrets Report ===",
        "Generated: " .. date("%Y-%m-%d %H:%M:%S"),
        "",
    }

    -- Context
    local context = self:GetCurrentContext()
    lines[#lines + 1] = "=== Current Context ==="
    lines[#lines + 1] = "In Combat: " .. (context.inCombat and "Yes" or "No")
    lines[#lines + 1] = "In M+: " .. (context.inMythicPlus and "Yes" or "No")
    lines[#lines + 1] = "In Raid: " .. (context.inRaid and "Yes" or "No")
    lines[#lines + 1] = "Instance Type: " .. context.instanceType
    lines[#lines + 1] = ""

    -- Predicates
    lines[#lines + 1] = "=== Global Predicates (C_Secrets) ==="
    local predicates = self:GetAllPredicates()
    for _, predicate in ipairs(self.PREDICATES) do
        local value = predicates[predicate]
        lines[#lines + 1] = predicate .. ": " .. (value and "true" or "false")
    end
    lines[#lines + 1] = ""

    -- Restrictions
    lines[#lines + 1] = "=== AddOn Restrictions ==="
    local restrictions = self:GetAddOnRestrictions()
    lines[#lines + 1] = "CheckAllowProtectedFunctions: " .. (restrictions.allowProtectedFunctions and "true" or "false")
    lines[#lines + 1] = "GetAddOnRestrictionState: \"" .. (restrictions.restrictionState or "none") .. "\""
    lines[#lines + 1] = "IsAddOnRestrictionActive: " .. (restrictions.restrictionActive and "true" or "false")
    lines[#lines + 1] = ""

    -- Frame info if provided
    if frameInfo then
        lines[#lines + 1] = "=== Inspected Frame ==="
        lines[#lines + 1] = "Frame: " .. (frameInfo.name or "(unnamed)") .. " (" .. (frameInfo.type or "?") .. ")"

        if frameInfo.secrets then
            local secrets = frameInfo.secrets
            lines[#lines + 1] = "HasSecretValues: " .. (secrets.hasSecretValues and "true" or "false")
            lines[#lines + 1] = "IsAnchoringSecret: " .. (secrets.isAnchoringSecret and "true" or "false")
            lines[#lines + 1] = "IsPreventingSecretValues: " .. (secrets.isPreventingSecretValues and "true" or "false")

            if secrets.secretAspects and #secrets.secretAspects > 0 then
                lines[#lines + 1] = "Secret Aspects: " .. table.concat(secrets.secretAspects, ", ")
            end
        end
    end

    lines[#lines + 1] = "==="

    return table.concat(lines, "\n")
end
