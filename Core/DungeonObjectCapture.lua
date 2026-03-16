--[[
    MedaDebug Dungeon Object Capture
    Correlates world-object and NPC tooltip interactions with buffs, loot, and spell outcomes.
]]

local _, MedaDebug = ...
local MedaUI = LibStub("MedaUI-2.0")

local DungeonObjectCapture = {}
MedaDebug.DungeonObjectCapture = DungeonObjectCapture

DungeonObjectCapture.captures = nil
DungeonObjectCapture.recentContexts = {}
DungeonObjectCapture.unitAuraState = {}
DungeonObjectCapture.isEnabled = false
DungeonObjectCapture.isInitialized = false
DungeonObjectCapture.onDataChanged = nil

local eventFrame = CreateFrame("Frame")

local OBJECT_TOOLTIP_TYPE = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object or 4
local UNIT_TOOLTIP_TYPE = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit or 2
local CORPSE_TOOLTIP_TYPE = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Corpse or 3

local function GetOptions()
    return MedaDebug.db and MedaDebug.db.options or nil
end

local function SafeToString(value)
    if value == nil then
        return nil
    end

    local ok, text = pcall(tostring, value)
    if ok and text ~= "" then
        return text
    end

    return nil
end

local function Trim(text)
    if type(text) ~= "string" then
        return nil
    end

    local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        return nil
    end

    return trimmed
end

local function BuildLower(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local ok, lowered = pcall(string.lower, text)
    if ok then
        return lowered
    end

    return nil
end

local function FormatTimestamp(seconds)
    local millis = math.floor(((seconds or 0) % 1) * 1000 + 0.5)
    return date("%H:%M:%S") .. string.format(".%03d", millis)
end

local function TableContains(list, value)
    for i = 1, #list do
        if list[i] == value then
            return true
        end
    end

    return false
end

local function ParseGuidInfo(guid)
    if type(guid) ~= "string" then
        return nil, nil
    end

    local guidType, _, _, _, entryId = strsplit("-", guid)
    return guidType, tonumber(entryId)
end

local function BuildMonitoredUnits(trackParty)
    local units = { "player" }

    if not trackParty then
        return units
    end

    if IsInRaid() then
        local count = GetNumGroupMembers() or 0
        for index = 1, count do
            units[#units + 1] = "raid" .. index
        end
    elseif IsInGroup() then
        local count = GetNumSubgroupMembers() or 0
        for index = 1, count do
            units[#units + 1] = "party" .. index
        end
    end

    return units
end

local function SafeRegisterEvent(frame, eventName)
    local ok, err = pcall(frame.RegisterEvent, frame, eventName)
    if ok then
        return true
    end

    MedaDebug:LogInternal("MedaDebug", string.format("Dungeon object capture could not register event %s: %s", tostring(eventName), tostring(err)), "WARN")
    return false
end

local function GetInstanceContext()
    local instanceName, instanceType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID, instanceGroupSize = GetInstanceInfo()
    local mapID = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
    local positionX, positionY

    if mapID and C_Map.GetPlayerMapPosition then
        local position = C_Map.GetPlayerMapPosition(mapID, "player")
        if position then
            positionX = position.x
            positionY = position.y
        end
    end

    return {
        instanceName = instanceName,
        instanceType = instanceType,
        difficultyID = difficultyID,
        difficultyName = difficultyName,
        maxPlayers = maxPlayers,
        dynamicDifficulty = dynamicDifficulty,
        isDynamic = isDynamic,
        instanceID = instanceID,
        instanceGroupSize = instanceGroupSize,
        mapID = mapID,
        positionX = positionX,
        positionY = positionY,
    }
end

local function IsDungeonInstanceContext(context)
    return context
        and context.instanceType == "party"
        and context.instanceID
        and context.instanceID > 0
end

local function BuildPositionText(context)
    if not context or not context.positionX or not context.positionY then
        return nil
    end

    return string.format("%.1f, %.1f", context.positionX * 100, context.positionY * 100)
end

local function ExtractTooltipLineText(line, output)
    if type(line) ~= "table" then
        local text = Trim(SafeToString(line))
        if text then
            output[#output + 1] = text
        end
        return
    end

    local textFields = {
        "leftText",
        "rightText",
        "text",
        "formattedText",
        "tooltipText",
        "header",
        "body",
    }

    for i = 1, #textFields do
        local value = Trim(SafeToString(line[textFields[i]]))
        if value then
            output[#output + 1] = value
        end
    end

    if type(line.args) == "table" then
        for i = 1, #line.args do
            local arg = line.args[i]
            if type(arg) == "table" then
                local stringVal = Trim(arg.stringVal)
                if stringVal then
                    output[#output + 1] = stringVal
                end
            end
        end
    end

    if type(line.lines) == "table" then
        for i = 1, #line.lines do
            ExtractTooltipLineText(line.lines[i], output)
        end
    end
end

local function ExtractTooltipLines(data)
    local lines = {}
    if type(data) ~= "table" or type(data.lines) ~= "table" then
        return lines
    end

    for i = 1, #data.lines do
        ExtractTooltipLineText(data.lines[i], lines)
    end

    return lines
end

local function SerializeValue(value, depth, visited)
    depth = depth or 0
    if depth > 3 then
        return "..."
    end

    local valueType = type(value)
    if valueType == "nil" or valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end

    if valueType == "string" then
        return string.format("%q", value)
    end

    if valueType ~= "table" then
        return string.format("<%s>", valueType)
    end

    visited = visited or {}
    if visited[value] then
        return "<cycle>"
    end
    visited[value] = true

    local parts = { "{" }
    local count = 0
    for key, entry in pairs(value) do
        count = count + 1
        if count > 25 then
            parts[#parts + 1] = "\n" .. string.rep("  ", depth + 1) .. "..."
            break
        end

        parts[#parts + 1] = string.format(
            "\n%s[%s] = %s,",
            string.rep("  ", depth + 1),
            SerializeValue(key, depth + 1, visited),
            SerializeValue(entry, depth + 1, visited)
        )
    end

    parts[#parts + 1] = "\n" .. string.rep("  ", depth) .. "}"
    visited[value] = nil
    return table.concat(parts)
end

local function CopyPlainTable(source)
    if type(source) ~= "table" then
        return source
    end

    local target = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            target[key] = CopyPlainTable(value)
        elseif type(value) ~= "function" and type(value) ~= "userdata" and type(value) ~= "thread" then
            target[key] = value
        end
    end
    return target
end

function DungeonObjectCapture:GetStorage()
    MedaDebug.log.session.dungeonObjectCapture = MedaDebug.log.session.dungeonObjectCapture or {
        records = {},
        nextCaptureId = 0,
    }
    return MedaDebug.log.session.dungeonObjectCapture
end

function DungeonObjectCapture:LoadOptions()
    local options = GetOptions()
    if not options then
        return
    end

    self.correlationWindow = math.max(1, options.dungeonCaptureWindow or 5)
    self.maxEntries = math.max(20, options.dungeonCaptureMaxEntries or 200)
    self.trackPartyAuras = options.dungeonCaptureTrackPartyAuras ~= false
    self.includeCombatLog = false
end

function DungeonObjectCapture:EnsureInitialized()
    if self.isInitialized then
        return
    end

    self.isInitialized = true
    self:LoadOptions()
    self.captures = self:GetStorage().records

    eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "WORLD_CURSOR_TOOLTIP_UPDATE" then
            self:HandleWorldCursorTooltipUpdate(...)
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            self:HandleMouseoverUnit()
        elseif event == "UNIT_AURA" then
            self:HandleUnitAura(...)
        elseif event == "CHAT_MSG_LOOT" then
            self:HandleLootMessage(...)
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            self:PrimeAuraState()
            self:ExpireOldCaptures(GetTime())
            if event == "PLAYER_ENTERING_WORLD" then
                local instance = GetInstanceContext()
                if not IsDungeonInstanceContext(instance) then
                    self:ResetRecentContext()
                end
            end
        end
    end)
end

function DungeonObjectCapture:RegisterEvents()
    SafeRegisterEvent(eventFrame, "WORLD_CURSOR_TOOLTIP_UPDATE")
    SafeRegisterEvent(eventFrame, "UPDATE_MOUSEOVER_UNIT")
    SafeRegisterEvent(eventFrame, "UNIT_AURA")
    SafeRegisterEvent(eventFrame, "CHAT_MSG_LOOT")
    SafeRegisterEvent(eventFrame, "GROUP_ROSTER_UPDATE")
    SafeRegisterEvent(eventFrame, "PLAYER_ENTERING_WORLD")
end

function DungeonObjectCapture:Enable()
    self:EnsureInitialized()
    self:LoadOptions()
    self:RegisterEvents()
    self.isEnabled = true
    self:PrimeAuraState()
    MedaDebug:LogInternal("MedaDebug", "Dungeon object capture enabled", "INFO")
    self:NotifyChanged("refresh")
end

function DungeonObjectCapture:Disable()
    if not self.isInitialized then
        return
    end

    eventFrame:UnregisterAllEvents()
    self.isEnabled = false
    wipe(self.recentContexts)
    wipe(self.unitAuraState)
    MedaDebug:LogInternal("MedaDebug", "Dungeon object capture disabled", "INFO")
    self:NotifyChanged("refresh")
end

function DungeonObjectCapture:IsEnabled()
    return self.isEnabled
end

function DungeonObjectCapture:Initialize()
    self:Enable()
end

function DungeonObjectCapture:NotifyChanged(kind, payload)
    if self.onDataChanged then
        self.onDataChanged(kind, payload)
    end
end

function DungeonObjectCapture:GetCaptures()
    self:EnsureInitialized()
    return self.captures
end

function DungeonObjectCapture:Clear()
    self:EnsureInitialized()
    wipe(self.captures)
    wipe(self.recentContexts)
    wipe(self.unitAuraState)
    self:GetStorage().nextCaptureId = 0
    self:PrimeAuraState()
    self:NotifyChanged("refresh")
end

function DungeonObjectCapture:GetNextCaptureId()
    local storage = self:GetStorage()
    storage.nextCaptureId = (storage.nextCaptureId or 0) + 1
    return storage.nextCaptureId
end

function DungeonObjectCapture:TrimCaptures()
    while #self.captures > self.maxEntries do
        table.remove(self.captures)
    end
end

function DungeonObjectCapture:PrimeAuraState()
    wipe(self.unitAuraState)
    local units = BuildMonitoredUnits(self.trackPartyAuras)
    for i = 1, #units do
        local unit = units[i]
        if UnitExists(unit) then
            self.unitAuraState[unit] = self:SnapshotHelpfulAuras(unit)
        end
    end
end

function DungeonObjectCapture:ResetRecentContext()
    wipe(self.recentContexts)
end

function DungeonObjectCapture:SnapshotHelpfulAuras(unit)
    local snapshot = {}
    if not UnitExists(unit) or not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
        return snapshot
    end

    local index = 1
    while true do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
        if not aura then
            break
        end

        if aura.spellId then
            snapshot[aura.spellId] = {
                spellId = aura.spellId,
                name = aura.name,
                icon = aura.icon,
                applications = aura.applications,
                auraInstanceID = aura.auraInstanceID,
                duration = aura.duration,
                expirationTime = aura.expirationTime,
                sourceUnit = aura.sourceUnit,
            }
        end

        index = index + 1
    end

    return snapshot
end

function DungeonObjectCapture:IsGroupGuid(guid)
    if not guid then
        return false
    end

    local units = BuildMonitoredUnits(self.trackPartyAuras)
    for i = 1, #units do
        if UnitExists(units[i]) and UnitGUID(units[i]) == guid then
            return true
        end
    end

    return false
end

function DungeonObjectCapture:ExpireOldCaptures(now)
    now = now or GetTime()
    for i = 1, #self.captures do
        local capture = self.captures[i]
        if capture and capture.status == "pending" and now - (capture.context.timestamp or now) > self.correlationWindow then
            capture.status = "no_outcome"
            capture.summary = capture.summary or "No correlated outcome"
        end
    end

    for index = #self.recentContexts, 1, -1 do
        local capture = self.recentContexts[index]
        if not capture or now - (capture.context.timestamp or now) > self.correlationWindow then
            table.remove(self.recentContexts, index)
        end
    end
end

function DungeonObjectCapture:BuildTooltipContext(source, data, extra)
    if type(data) ~= "table" then
        return nil
    end

    local tooltipType = data.type
    if tooltipType ~= OBJECT_TOOLTIP_TYPE and tooltipType ~= UNIT_TOOLTIP_TYPE and tooltipType ~= CORPSE_TOOLTIP_TYPE then
        return nil
    end

    local lines = ExtractTooltipLines(data)
    local name = Trim(data.name) or lines[1] or Trim(data.hyperlink)
    if not name then
        return nil
    end

    local guid = data.guid or data.objectGUID or data.unitGUID
    local guidType, entryID = ParseGuidInfo(guid)
    local instance = GetInstanceContext()
    if not IsDungeonInstanceContext(instance) then
        return nil
    end

    return {
        timestamp = GetTime(),
        datetime = FormatTimestamp(GetTime()),
        source = source,
        tooltipType = tooltipType,
        tooltipTypeLabel = tooltipType == OBJECT_TOOLTIP_TYPE and "object"
            or tooltipType == UNIT_TOOLTIP_TYPE and "unit"
            or tooltipType == CORPSE_TOOLTIP_TYPE and "corpse"
            or tostring(tooltipType),
        name = name,
        guid = guid,
        guidType = guidType,
        entryID = entryID,
        dataID = data.id,
        displayID = data.displayID,
        hyperlink = data.hyperlink,
        lines = lines,
        rawData = CopyPlainTable(data),
        instance = instance,
        positionText = BuildPositionText(instance),
        sourceExtra = extra and CopyPlainTable(extra) or nil,
    }
end

function DungeonObjectCapture:FindLatestCaptureBySignature(signature, now)
    if not signature then
        return nil
    end

    now = now or GetTime()
    local latest = self.captures[1]
    if not latest or not latest.context or latest.signature ~= signature then
        return nil
    end

    if now - (latest.context.timestamp or now) <= 0.75 then
        return latest
    end

    return nil
end

function DungeonObjectCapture:AddContextCapture(context)
    if not context then
        return nil
    end

    self:EnsureInitialized()
    self:ExpireOldCaptures(context.timestamp)

    local signature = table.concat({
        context.source or "?",
        context.tooltipTypeLabel or "?",
        context.guid or "",
        tostring(context.entryID or ""),
        context.name or "",
    }, ":")

    local existing = self:FindLatestCaptureBySignature(signature, context.timestamp)
    if existing then
        existing.context = context
        existing.summary = existing.summary or context.name
        existing.searchText = BuildLower((context.name or "") .. " " .. table.concat(context.lines or {}, " "))
        self:NotifyChanged("update", existing)
        return existing
    end

    local capture = {
        id = self:GetNextCaptureId(),
        signature = signature,
        createdAt = context.timestamp,
        context = context,
        outcomes = {},
        status = "pending",
        confidence = "low",
        summary = context.name,
        searchText = BuildLower((context.name or "") .. " " .. table.concat(context.lines or {}, " ")),
    }

    table.insert(self.captures, 1, capture)
    table.insert(self.recentContexts, 1, capture)
    self:TrimCaptures()
    self:NotifyChanged("new", capture)
    return capture
end

function DungeonObjectCapture:FindTargetCapture(now)
    self:ExpireOldCaptures(now)
    return self.recentContexts[1]
end

function DungeonObjectCapture:UpdateCaptureSummary(capture)
    local contextName = capture.context and capture.context.name or "Unknown"
    if not capture.outcomes or #capture.outcomes == 0 then
        capture.summary = contextName
        capture.status = capture.status == "no_outcome" and "no_outcome" or "pending"
        capture.confidence = "low"
        return
    end

    local outcome = capture.outcomes[1]
    local label = outcome.label or outcome.name or outcome.kind or "outcome"
    capture.summary = string.format("%s -> %s", contextName, label)
    capture.status = "matched"
    if #capture.outcomes == 1 then
        capture.confidence = outcome.kind == "aura" and "high" or "medium"
    else
        capture.confidence = "medium"
    end
end

function DungeonObjectCapture:AddOutcome(kind, payload, outcomeTime)
    outcomeTime = outcomeTime or GetTime()
    local capture = self:FindTargetCapture(outcomeTime)
    if not capture then
        return
    end

    local outcome = CopyPlainTable(payload or {})
    outcome.kind = kind
    outcome.timestamp = outcomeTime
    outcome.delta = outcomeTime - (capture.context and capture.context.timestamp or outcomeTime)
    outcome.label = outcome.label or outcome.name or outcome.message or kind

    capture.outcomes[#capture.outcomes + 1] = outcome
    capture.status = "matched"
    self:UpdateCaptureSummary(capture)
    capture.searchText = BuildLower(table.concat({
        capture.context and capture.context.name or "",
        table.concat(capture.context and capture.context.lines or {}, " "),
        outcome.label or "",
        outcome.name or "",
        outcome.message or "",
    }, " "))

    self:NotifyChanged("update", capture)
end

function DungeonObjectCapture:HandleWorldCursorTooltipUpdate(anchorType)
    if not self.isEnabled or not C_TooltipInfo or not C_TooltipInfo.GetWorldCursor then
        return
    end

    local data = C_TooltipInfo.GetWorldCursor()
    if not data then
        return
    end

    local context = self:BuildTooltipContext("world_cursor", data, {
        anchorType = anchorType,
    })
    if context then
        self:AddContextCapture(context)
    end
end

function DungeonObjectCapture:HandleMouseoverUnit()
    if not self.isEnabled or not UnitExists("mouseover") then
        return
    end

    local tooltipData = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit("mouseover") or nil
    local context = self:BuildTooltipContext("mouseover_unit", tooltipData or {
        type = UNIT_TOOLTIP_TYPE,
        name = UnitName("mouseover"),
        unitGUID = UnitGUID("mouseover"),
    }, {
        unitToken = "mouseover",
        unitGUID = UnitGUID("mouseover"),
        reaction = UnitReaction("mouseover", "player"),
    })

    if context then
        self:AddContextCapture(context)
    end
end

function DungeonObjectCapture:HandleUnitAura(unit)
    if not self.isEnabled or not unit then
        return
    end

    local monitored = BuildMonitoredUnits(self.trackPartyAuras)
    if not TableContains(monitored, unit) then
        return
    end

    local previous = self.unitAuraState[unit] or {}
    local current = self:SnapshotHelpfulAuras(unit)
    self.unitAuraState[unit] = current

    for spellId, aura in pairs(current) do
        if not previous[spellId] then
            self:AddOutcome("aura", {
                label = string.format("%s gained %s", UnitName(unit) or unit, aura.name or ("Spell " .. spellId)),
                unit = unit,
                unitName = UnitName(unit),
                spellId = spellId,
                name = aura.name,
                icon = aura.icon,
                applications = aura.applications,
                sourceUnit = aura.sourceUnit,
                duration = aura.duration,
            })
        end
    end
end

function DungeonObjectCapture:HandleLootMessage(message)
    if not self.isEnabled or type(message) ~= "string" then
        return
    end

    local itemId = message:match("|Hitem:(%d+)")
    local spellId = message:match("|Hspell:(%d+)")
    self:AddOutcome("loot", {
        label = message,
        message = message,
        itemId = itemId and tonumber(itemId) or nil,
        spellId = spellId and tonumber(spellId) or nil,
    })
end

function DungeonObjectCapture:BuildCaptureReport(capture)
    if not capture then
        return "No capture selected."
    end

    local context = capture.context or {}
    local instance = context.instance or {}
    local lines = {
        "=== MedaDebug Dungeon Object Capture ===",
        "Capture ID: " .. tostring(capture.id),
        "Status: " .. tostring(capture.status),
        "Confidence: " .. tostring(capture.confidence),
        "Context: " .. tostring(context.name or "?"),
        "Tooltip Type: " .. tostring(context.tooltipTypeLabel or "?"),
        "Source: " .. tostring(context.source or "?"),
        "Timestamp: " .. tostring(context.datetime or "?"),
        "Instance: " .. tostring(instance.instanceName or "?") .. " (" .. tostring(instance.instanceID or "?") .. ")",
    }

    if context.positionText then
        lines[#lines + 1] = "Position: " .. context.positionText
    end
    if context.guid then
        lines[#lines + 1] = "GUID: " .. context.guid
    end
    if context.entryID then
        lines[#lines + 1] = "Entry ID: " .. tostring(context.entryID)
    end
    if context.dataID then
        lines[#lines + 1] = "Tooltip Data ID: " .. tostring(context.dataID)
    end
    if context.hyperlink then
        lines[#lines + 1] = "Hyperlink: " .. tostring(context.hyperlink)
    end

    if context.lines and #context.lines > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "=== Tooltip Lines ==="
        for i = 1, #context.lines do
            lines[#lines + 1] = "- " .. context.lines[i]
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "=== Outcomes ==="
    if capture.outcomes and #capture.outcomes > 0 then
        for index = 1, #capture.outcomes do
            local outcome = capture.outcomes[index]
            lines[#lines + 1] = string.format(
                "%d. [%s] %s (%.2fs)",
                index,
                tostring(outcome.kind or "?"),
                tostring(outcome.label or outcome.name or "?"),
                outcome.delta or 0
            )
            if outcome.spellId then
                lines[#lines + 1] = "   spellID: " .. tostring(outcome.spellId)
            end
            if outcome.itemId then
                lines[#lines + 1] = "   itemID: " .. tostring(outcome.itemId)
            end
            if outcome.unitName then
                lines[#lines + 1] = "   unit: " .. tostring(outcome.unitName)
            end
        end
    else
        lines[#lines + 1] = "(no correlated outcomes)"
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "=== Raw Tooltip Data ==="
    lines[#lines + 1] = SerializeValue(context.rawData)

    return table.concat(lines, "\n")
end

function DungeonObjectCapture:BuildCopyText(captures)
    captures = captures or self:GetCaptures()
    if #captures == 0 then
        return "No captures recorded."
    end

    local chunks = {}
    for index = 1, #captures do
        chunks[#chunks + 1] = self:BuildCaptureReport(captures[index])
    end
    return table.concat(chunks, "\n\n")
end

if MedaDebug.RuntimeRegistry then
    MedaDebug.RuntimeRegistry:RegisterModule("DungeonObjectCapture", {
        order = 95,
        phase = "PLAYER_LOGIN",
        optionKey = "enableDungeonObjectCapture",
    })
end

if MedaDebug.SettingsRegistry then
    MedaDebug.SettingsRegistry:RegisterModule("dungeon-object-capture", {
        title = "Object Capture",
        description = "Correlate world objects and NPC interactions to buffs, loot, and spell outcomes.",
        sidebarGroup = "Settings",
        sidebarOrder = 50,
        sidebarLabel = "Object Capture",
        entryType = "module",
        getEnabled = function()
            return MedaDebug.db and MedaDebug.db.options.enableDungeonObjectCapture or false
        end,
        setEnabled = function(enabled)
            MedaDebug.db.options.enableDungeonObjectCapture = enabled
            if enabled then
                DungeonObjectCapture:Enable()
            else
                DungeonObjectCapture:Disable()
            end
        end,
        pages = {
            { id = "dungeon-object-capture", label = "Object Capture" },
        },
        pageHeights = {
            ["dungeon-object-capture"] = 360,
        },
        buildPage = function(_, parent)
            local options = GetOptions() or {}
            local yOff = 0

            local header = MedaUI:CreateSectionHeader(parent, "Dungeon Object Capture", 470)
            header:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 38

            local infoLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            infoLabel:SetPoint("TOPLEFT", 12, yOff)
            infoLabel:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
            infoLabel:SetJustifyH("LEFT")
            infoLabel:SetWordWrap(true)
            infoLabel:SetText("Developer-only correlation logger. Hover or interact with dungeon objects or NPCs, then use the workspace Copy button to export the captured evidence.")
            infoLabel:SetTextColor(unpack(MedaUI.Theme.textDim))
            yOff = yOff - infoLabel:GetStringHeight() - 18

            local windowSlider = MedaUI:CreateLabeledSlider(parent, "Correlation Window (sec)", 220, 1, 10, 0.5)
            windowSlider:SetPoint("TOPLEFT", 12, yOff)
            windowSlider:SetValue(options.dungeonCaptureWindow or 5)
            windowSlider.OnValueChanged = function(_, value)
                options.dungeonCaptureWindow = value
                DungeonObjectCapture.correlationWindow = value
            end
            yOff = yOff - 62

            local entriesSlider = MedaUI:CreateLabeledSlider(parent, "Retained Captures", 220, 20, 500, 10)
            entriesSlider:SetPoint("TOPLEFT", 12, yOff)
            entriesSlider:SetValue(options.dungeonCaptureMaxEntries or 200)
            entriesSlider.OnValueChanged = function(_, value)
                options.dungeonCaptureMaxEntries = value
                DungeonObjectCapture.maxEntries = value
                DungeonObjectCapture:TrimCaptures()
                DungeonObjectCapture:NotifyChanged("refresh")
            end
            yOff = yOff - 62

            local groupCheckbox = MedaUI:CreateCheckbox(parent, "Track helpful auras on party members")
            groupCheckbox:SetPoint("TOPLEFT", 12, yOff)
            groupCheckbox:SetChecked(options.dungeonCaptureTrackPartyAuras ~= false)
            groupCheckbox.OnValueChanged = function(_, checked)
                options.dungeonCaptureTrackPartyAuras = checked
                DungeonObjectCapture.trackPartyAuras = checked
                DungeonObjectCapture:PrimeAuraState()
            end
            yOff = yOff - 28

            local combatNote = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            combatNote:SetPoint("TOPLEFT", 12, yOff)
            combatNote:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
            combatNote:SetJustifyH("LEFT")
            combatNote:SetWordWrap(true)
            combatNote:SetText("Combat-log correlation is disabled for now because this client throws a Blizzard popup when `COMBAT_LOG_EVENT_UNFILTERED` is registered from this module.")
            combatNote:SetTextColor(unpack(MedaUI.Theme.warning))

            return 360
        end,
    })
end
