--[[
    MedaDebug Profiler Lite
    Lightweight counters and timings for MedaDebug/UI hot paths
]]

local _, MedaDebug = ...

local ProfilerLite = {}
MedaDebug.ProfilerLite = ProfilerLite

ProfilerLite.entries = {}
ProfilerLite.enabled = true
ProfilerLite.pendingNotify = false

local function NowMs()
    return GetTime() * 1000
end

function ProfilerLite:Initialize()
    self.enabled = true
end

function ProfilerLite:IsEnabled()
    return self.enabled
end

function ProfilerLite:SetEnabled(enabled)
    self.enabled = enabled and true or false
    self:ScheduleNotify()
end

function ProfilerLite:ScheduleNotify()
    if self.pendingNotify then
        return
    end

    self.pendingNotify = true
    C_Timer.After(0.1, function()
        self.pendingNotify = false
        if self.onUpdated then
            self.onUpdated()
        end
    end)
end

function ProfilerLite:BeginSample(name, category, source)
    if not self.enabled then
        return nil
    end

    return {
        name = name,
        category = category or "misc",
        source = source,
        startMs = NowMs(),
    }
end

function ProfilerLite:EndSample(token, source)
    if not token or not self.enabled then
        return nil
    end

    return self:RecordSample(token.name, token.category, NowMs() - token.startMs, source or token.source)
end

function ProfilerLite:RecordSample(name, category, durationMs, source)
    if not self.enabled then
        return nil
    end

    category = category or "misc"
    local key = category .. ":" .. name
    local entry = self.entries[key]

    if not entry then
        entry = {
            key = key,
            name = name,
            category = category,
            source = source or "",
            count = 0,
            totalMs = 0,
            maxMs = 0,
            lastMs = 0,
            updatedAt = GetTime(),
        }
        self.entries[key] = entry
    end

    entry.count = entry.count + 1
    entry.lastMs = durationMs or 0
    entry.totalMs = entry.totalMs + entry.lastMs
    entry.maxMs = math.max(entry.maxMs, entry.lastMs)
    entry.avgMs = entry.totalMs / math.max(entry.count, 1)
    entry.updatedAt = GetTime()
    if source and source ~= "" then
        entry.source = source
    end

    self:ScheduleNotify()
    return entry
end

function ProfilerLite:GetStats(category)
    local rows = {}

    for _, entry in pairs(self.entries) do
        if not category or category == "all" or entry.category == category then
            rows[#rows + 1] = entry
        end
    end

    table.sort(rows, function(a, b)
        if a.totalMs == b.totalMs then
            return a.count > b.count
        end
        return a.totalMs > b.totalMs
    end)

    return rows
end

function ProfilerLite:GetSummary()
    local count = 0
    local totalMs = 0

    for _, entry in pairs(self.entries) do
        count = count + 1
        totalMs = totalMs + (entry.totalMs or 0)
    end

    return {
        entries = count,
        totalMs = totalMs,
    }
end

function ProfilerLite:Clear()
    wipe(self.entries)
    self:ScheduleNotify()
end

if MedaDebug.RuntimeRegistry then
    MedaDebug.RuntimeRegistry:RegisterModule("ProfilerLite", {
        order = 30,
    })
end
