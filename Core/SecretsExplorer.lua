--[[
    MedaDebug Secrets Explorer
    Analyze WoW 12.0.0+ secret values and widget restrictions
]]

local _, MedaDebug = ...

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
-- Findings annotated from empirical testing in WoW 12.0 (Midnight)
SecretsExplorer.API_DATABASE = {
    -- Power/Resource APIs
    {
        category = "mana",
        aliases = {"power", "resource", "energy", "rage", "focus"},
        apis = {
            {name = "UnitPower", args = {"unit", "0"}, desc = "Current mana (SECRET in instances)"},
            {name = "UnitPower", args = {"unit", "0", "true"}, desc = "Current mana unmodified (SECRET in instances)"},
            {name = "UnitPowerMax", args = {"unit", "0"}, desc = "Max mana"},
            {name = "UnitPowerMax", args = {"unit", "0", "true"}, desc = "Max mana unmodified (READABLE in instances!)"},
            {name = "UnitPowerType", args = {"unit"}, desc = "Power type (readable)"},
            {name = "UnitPowerDisplayMod", args = {"0"}, desc = "Power display modifier (readable, returns 1.0)"},
            {name = "GetUnitPowerBarInfo", args = {"unit"}, desc = "Power bar metadata (readable, may be nil)"},
            {name = "UnitPowerBarID", args = {"unit"}, desc = "Power bar ID (readable, returns 0)"},
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
        aliases = {"buff", "debuff", "auras", "drinking"},
        apis = {
            {name = "C_UnitAuras.GetAuraDataByIndex", args = {"unit", "1"}, desc = "Aura by index (fields may be tainted)"},
            {name = "C_UnitAuras.GetPlayerAuraBySpellID", args = {"spellID"}, desc = "Player aura by spell"},
            {name = "C_UnitAuras.GetAuraDataBySlot", args = {"unit", "slot"}, desc = "Aura by slot"},
            {name = "C_UnitAuras.GetBuffDataByIndex", args = {"unit", "1"}, desc = "Buff by index"},
            {name = "C_UnitAuras.GetDebuffDataByIndex", args = {"unit", "1"}, desc = "Debuff by index"},
            {name = "C_UnitAuras.GetAuraDataBySpellName", args = {"unit", "spellName"}, desc = "Aura by spell name"},
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
        aliases = {"player", "target", "party", "raid", "identity", "name", "role", "group"},
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
            {name = "UnitGroupRolesAssigned", args = {"unit"}, desc = "Assigned role (TANK/HEALER/DAMAGER)"},
            {name = "UnitExists", args = {"unit"}, desc = "Unit exists"},
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
        aliases = {"threat", "aggro", "combatlog"},
        apis = {
            {name = "UnitThreatSituation", args = {"unit"}, desc = "Threat situation"},
            {name = "UnitDetailedThreatSituation", args = {"unit", "target"}, desc = "Detailed threat"},
            {name = "UnitAffectingCombat", args = {"unit"}, desc = "In combat"},
        },
    },
    -- Widget / Frame APIs (reading and writing secret values via UI elements)
    {
        category = "widget",
        aliases = {"frame", "statusbar", "texture", "fontstring", "bar", "powerbar"},
        apis = {
            {name = "StatusBar:GetValue", args = {}, desc = "Bar value (SECRET when source value is secret)"},
            {name = "StatusBar:SetValue", args = {"value"}, desc = "ACCEPTS secret numbers -- bar renders correct fill visually"},
            {name = "StatusBar:GetMinMaxValues", args = {}, desc = "Bar min/max (may be secret)"},
            {name = "StatusBar:SetMinMaxValues", args = {"min", "max"}, desc = "Use with clean max from UnitPowerMax(u,t,true)"},
            {name = "StatusBar:GetStatusBarTexture", args = {}, desc = "Fill texture object (readable)"},
            {name = "Texture:GetWidth", args = {}, desc = "Texture width (SECRET if driven by secret value)"},
            {name = "Texture:GetTexCoord", args = {}, desc = "UV coordinates (SECRET if driven by secret value)"},
            {name = "FontString:GetText", args = {}, desc = "Text content (returns SECRET STRING if tainted)"},
            {name = "FontString:SetText", args = {"text"}, desc = "ACCEPTS tainted strings from format() -- displays real values"},
        },
    },
    -- Addon Communication
    {
        category = "addon_comm",
        aliases = {"communication", "message", "channel", "whisper", "party", "raid"},
        apis = {
            {name = "C_ChatInfo.RegisterAddonMessagePrefix", args = {"prefix"}, desc = "Register addon msg prefix"},
            {name = "C_ChatInfo.SendAddonMessage", args = {"prefix", "msg", "channel"}, desc = "BLOCKED in Midnight instances (was working pre-12.0)"},
        },
    },
    -- Instance/Context APIs
    {
        category = "instance",
        aliases = {"dungeon", "mythic", "m+", "challenge", "raid", "arena", "pvp", "battleground"},
        apis = {
            {name = "IsInInstance", args = {}, desc = "In an instance"},
            {name = "GetInstanceInfo", args = {}, desc = "Instance name, type, difficulty"},
            {name = "C_ChallengeMode.GetActiveChallengeMapID", args = {}, desc = "Active M+ map ID (nil if not M+)"},
            {name = "C_ChallengeMode.IsChallengeModeActive", args = {}, desc = "M+ active"},
            {name = "IsInRaid", args = {}, desc = "In raid group"},
            {name = "IsInGroup", args = {}, desc = "In any group"},
            {name = "GetNumGroupMembers", args = {}, desc = "Group size"},
        },
    },
}

-- ============================================================================
-- Taint Behavior Reference (empirically tested in WoW 12.0 Midnight)
-- ============================================================================
-- These rules were discovered through systematic testing in M+ and dungeons.
-- They document what operations succeed/fail on secret values, and how taint
-- propagates through different Lua operations.
--
-- CRITICAL FINDINGS:
--   UnitPower(unit, type)          -> SECRET NUMBER in instances
--   UnitPowerMax(unit, type, true) -> READABLE! Max values are not restricted
--   UnitPowerDisplayMod(type)      -> READABLE (returns 1.0)
--   UnitPowerBarID(unit)           -> READABLE (returns 0)
--   C_ChatInfo.SendAddonMessage    -> BLOCKED in Midnight (12.0) instances
--
-- VISUAL DISPLAY WORKAROUND (primary technique for secret values):
--   StatusBar:SetValue(secretNum)  -> WORKS! Bar renders correct fill from secret
--   StatusBar:SetMinMaxValues(0,N) -> WORKS with clean max from UnitPowerMax(u,t,true)
--   FontString:SetText(fmt)        -> WORKS! format("%d",secretNum) produces tainted
--                                     string that SetText accepts and displays correctly
--   This is the proven way to display secret mana/power values to the user.
--
-- SECRET NUMBER BEHAVIOR:
--   Arithmetic (+, -, *, /, %)     -> ERROR "attempt to perform arithmetic on secret"
--   Comparison (>, <, ==, ~=)      -> ERROR "attempt to compare secret"
--   tostring(secretNum)            -> SUCCEEDS but returns a SECRET STRING (taint propagates!)
--   string.format("%d", secretNum) -> SUCCEEDS but returns a SECRET STRING
--   type(secretNum)                -> Returns "number" (clean, not tainted)
--   math.floor(secretNum)          -> ERROR
--   Using as table key             -> ERROR "secret as table key"
--   issecretvalue(secretNum)       -> Returns true (clean boolean)
--
-- SECRET STRING BEHAVIOR (from tostring(secretNum)):
--   Concatenation ("x" .. secret)  -> SUCCEEDS but result is TAINTED
--   Comparison (secret == "foo")   -> ERROR "attempt to compare secret string"
--   string.find/match on secret    -> ERROR
--   #secretString (length)         -> ERROR
--   string.sub on secret           -> ERROR
--   Passing to SetText()           -> WORKS (Blizzard UI accepts tainted values for display)
--   Passing to print()             -> WORKS (output is tainted but displays)
--
-- TAINT PROPAGATION:
--   Secret numbers taint ALL derived values. If you concat a secret into a log
--   message, the entire message becomes tainted and will crash any code that
--   tries to compare or index it (like deduplication logic).
--
-- SAFE PATTERNS:
--   1. Check with issecretvalue() BEFORE any operation
--   2. Use pcall() for ALL operations on potentially secret values
--   3. After pcall succeeds, verify result is clean by forcing a comparison:
--        local ok = pcall(function() if result == "probe" then end end)
--   4. Never embed secret-derived values into strings used for logic
--   5. type() is safe and returns clean "number" for secret numbers
--   6. UnitPowerMax with unmodified=true bypasses restrictions (max only!)
--
-- WORKAROUNDS FOR DISPLAYING RESTRICTED VALUES:
--   1. Visual display: Feed secret values to addon-owned UI widgets via pcall:
--        pcall(bar.SetValue, bar, secretNum)
--        pcall(function() text:SetText(format("%d", secretNum)) end)
--   2. Max values: UnitPowerMax(unit, type, true) returns clean (non-secret) max
--   3. Drinking detection: Check for "Drinking" buff (may also be tainted in some contexts)
--   4. Comparisons are BLOCKED (secretVal > threshold errors), so binary search does NOT work
-- ============================================================================

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
        displayStr = self:SafeValueStr(value),
    }

    -- Check if issecretvalue exists (WoW 12.0.0+)
    if issecretvalue then
        local ok, result = pcall(issecretvalue, value)
        if ok then
            info.isSecret = result
        end
    end

    -- Fallback detection: try arithmetic on numbers
    if not issecretvalue and type(value) == "number" then
        local arithOk = pcall(function() return value + 0 end)
        if not arithOk then
            info.isSecret = true
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

    -- Probe taint behavior for secret values
    if info.isSecret then
        local tb = {}
        local vType = type(value)

        local tostrOk = pcall(function()
            local s = tostring(value)
            return s == "___PROBE___"
        end)
        tb.tostring = tostrOk and "clean" or "tainted"

        local cmpOk = pcall(function() return value == value end)
        tb.compare = cmpOk and "works" or "blocked"

        if vType == "number" then
            local mathOk = pcall(function() return value + 0 end)
            tb.arithmetic = mathOk and "works" or "blocked"
        end

        info.taintBehavior = tb
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

--- Safely convert a value to a clean display string.
--- Secret values taint through tostring() and concat, so we must verify
--- the result is clean by forcing a comparison (which errors on tainted strings).
--- @param value any
--- @return string Clean display string
function SecretsExplorer:SafeValueStr(value)
    if value == nil then return "nil" end

    local valType = type(value)

    if valType == "table" then
        local countOk, count = pcall(function()
            local n = 0
            for _ in pairs(value) do n = n + 1 end
            return n
        end)
        if countOk then
            return "{" .. count .. " fields}"
        end
        return "{...}"
    end

    if valType == "boolean" then
        local boolOk, boolStr = pcall(function()
            if value then return "true" else return "false" end
        end)
        if boolOk then return boolStr end
        return "???(tainted bool)"
    end

    -- For numbers and strings, tostring succeeds but may return a tainted string
    local strOk, str = pcall(tostring, value)
    if not strOk then return "???(tostring failed)" end

    -- Verify the result string is clean by forcing a comparison
    local cleanOk = pcall(function()
        return str == "___TAINT_PROBE___"
    end)
    if not cleanOk then
        return "???(tainted " .. valType .. ")"
    end

    if valType == "string" then
        if #str > 30 then str = str:sub(1, 30) .. ".." end
        return '"' .. str .. '"'
    end

    return str
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
        taintBehavior = nil,
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
        result.error = tostring(ret1 or "unknown error")
        return result
    end

    result.value = ret1

    -- Check secret status using WoW 12.0 APIs
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

    -- If issecretvalue isn't available, detect via pcall arithmetic
    if not issecretvalue and ret1 ~= nil and type(ret1) == "number" then
        local arithOk = pcall(function() return ret1 + 0 end)
        if not arithOk then
            result.isSecret = true
        end
    end

    -- Probe taint behavior for secret values
    if result.isSecret then
        local behavior = {}

        local tostrOk = pcall(function()
            local s = tostring(ret1)
            return s == "___PROBE___"
        end)
        behavior.tostring = tostrOk and "clean" or "tainted"

        local compareOk = pcall(function() return ret1 == ret1 end)
        behavior.compare = compareOk and "works" or "blocked"

        if type(ret1) == "number" then
            local arithOk = pcall(function() return ret1 + 0 end)
            behavior.arithmetic = arithOk and "works" or "blocked"

            local floorOk = pcall(function() return math.floor(ret1) end)
            behavior.mathOps = floorOk and "works" or "blocked"
        end

        result.taintBehavior = behavior
    end

    -- Format value string safely
    result.valueStr = self:SafeValueStr(ret1)

    -- Also format additional return values if they exist
    if ret2 ~= nil then
        result.valueStr = result.valueStr .. ", " .. self:SafeValueStr(ret2)
    end

    -- Check simulation
    if self:IsSimulating() then
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
    lines[#lines + 1] = "In Instance: " .. (context.inInstance and "Yes" or "No")
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

    -- Quick API probe on common power/health APIs
    lines[#lines + 1] = "=== API Probe (party1) ==="
    local probeAPIs = {
        {name = "UnitPower",    args = {"party1", 0},       label = "UnitPower(party1, MANA)"},
        {name = "UnitPower",    args = {"party1", 0, true},  label = "UnitPower(party1, MANA, true)"},
        {name = "UnitPowerMax", args = {"party1", 0},        label = "UnitPowerMax(party1, MANA)"},
        {name = "UnitPowerMax", args = {"party1", 0, true},  label = "UnitPowerMax(party1, MANA, true)"},
        {name = "UnitHealth",   args = {"party1"},           label = "UnitHealth(party1)"},
        {name = "UnitHealthMax", args = {"party1"},          label = "UnitHealthMax(party1)"},
    }
    for _, probe in ipairs(probeAPIs) do
        local testResult = self:TestAPICall(probe.name, probe.args)
        local status = testResult.isSecret and "SECRET" or (testResult.error and "ERROR" or "OK")
        local valStr = testResult.valueStr or "?"
        lines[#lines + 1] = probe.label .. ": " .. status .. " = " .. valStr

        if testResult.taintBehavior then
            local tb = testResult.taintBehavior
            local parts = {}
            for k, v in pairs(tb) do
                parts[#parts + 1] = k .. "=" .. v
            end
            if #parts > 0 then
                lines[#lines + 1] = "  taint: " .. table.concat(parts, ", ")
            end
        end
    end
    lines[#lines + 1] = ""

    -- Taint behavior quick reference
    lines[#lines + 1] = "=== Taint Behavior (WoW 12.0) ==="
    lines[#lines + 1] = "Secret numbers: arithmetic=BLOCKED, compare=BLOCKED, tostring=TAINTED_STRING"
    lines[#lines + 1] = "Secret strings: concat=PROPAGATES, compare=BLOCKED, find/match/sub=BLOCKED"
    lines[#lines + 1] = "Safe operations: type()=clean, issecretvalue()=clean, SetText()=works"
    lines[#lines + 1] = "Key finding: UnitPowerMax(unit,type,true) is READABLE when UnitPower is SECRET"
    lines[#lines + 1] = "Key finding: C_ChatInfo.SendAddonMessage WORKS in instances (party channel)"
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
