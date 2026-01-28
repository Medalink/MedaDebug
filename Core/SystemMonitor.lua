--[[
    MedaDebug System Monitor
    Tracks FPS, memory, latency, and other system info
]]

local addonName, MedaDebug = ...

local SystemMonitor = {}
MedaDebug.SystemMonitor = SystemMonitor

-- Current stats
SystemMonitor.stats = {
    fps = 0,
    memory = 0,
    latencyHome = 0,
    latencyWorld = 0,
    addonCount = 0,
    inCombat = false,
    sessionUptime = 0,
}

-- Memory per addon
SystemMonitor.addonMemory = {}

-- Update timers
SystemMonitor.updateTimer = nil
SystemMonitor.updateInterval = 1  -- Fast stats (FPS, latency)
SystemMonitor.memoryUpdateInterval = 10  -- Slow stats (memory) - expensive!
SystemMonitor.lastMemoryUpdate = 0
SystemMonitor.isEnabled = false

-- Callbacks
SystemMonitor.onStatsUpdated = nil

--- Enable system monitoring at runtime
function SystemMonitor:Enable()
    if self.isEnabled then return end
    self:Initialize()
    MedaDebug:Log("MedaDebug", "System monitoring enabled", "INFO")
end

--- Disable system monitoring at runtime
function SystemMonitor:Disable()
    if not self.isEnabled then return end
    self.isEnabled = false
    self:StopUpdates()
    MedaDebug:Log("MedaDebug", "System monitoring disabled", "INFO")
end

--- Check if enabled
function SystemMonitor:IsEnabled()
    return self.isEnabled
end

function SystemMonitor:Initialize()
    if self.isEnabled then return end
    self.isEnabled = true
    
    -- Load settings
    if MedaDebug.db then
        self.updateInterval = MedaDebug.db.options.systemUpdateInterval or 1
        self.memoryUpdateInterval = MedaDebug.db.options.memoryUpdateInterval or 10
    end
    
    -- Get WoW version info
    local version, build, date, tocversion = GetBuildInfo()
    self.wowVersion = {
        version = version,
        build = build,
        date = date,
        tocversion = tocversion,
    }
    
    -- Count addons (C_AddOns API for WoW 11.0+)
    self.stats.addonCount = C_AddOns.GetNumAddOns()
    
    -- Start update timer
    self:StartUpdates()
    
    -- Register combat events
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            self.stats.inCombat = true
        else
            self.stats.inCombat = false
        end
    end)
end

--- Start periodic updates
function SystemMonitor:StartUpdates()
    if self.updateTimer then
        self.updateTimer:Cancel()
    end
    
    self.updateTimer = C_Timer.NewTicker(self.updateInterval, function()
        self:Update()
    end)
    
    -- Initial update
    self:Update()
end

--- Stop updates
function SystemMonitor:StopUpdates()
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
end

--- Update fast stats (FPS, latency) - called frequently
function SystemMonitor:Update()
    -- FPS
    self.stats.fps = GetFramerate()
    
    -- Latency
    local _, _, latencyHome, latencyWorld = GetNetStats()
    self.stats.latencyHome = latencyHome
    self.stats.latencyWorld = latencyWorld
    
    -- Session uptime
    if MedaDebug.log and MedaDebug.log.session then
        local startTime = MedaDebug.log.session.startTime or time()
        self.stats.sessionUptime = time() - startTime
    end
    
    -- Memory update (expensive!) - only every memoryUpdateInterval seconds
    local now = GetTime()
    if now - self.lastMemoryUpdate >= self.memoryUpdateInterval then
        self:UpdateMemory()
        self.lastMemoryUpdate = now
    end
    
    -- Notify UI
    if self.onStatsUpdated then
        self.onStatsUpdated(self.stats)
    end
end

--- Update memory stats (expensive - causes brief stutter)
--- Call sparingly or on-demand
function SystemMonitor:UpdateMemory()
    -- This call is expensive! It forces a memory scan of all addons
    UpdateAddOnMemoryUsage()
    
    local totalMemory = 0
    wipe(self.addonMemory)
    
    for i = 1, C_AddOns.GetNumAddOns() do
        local mem = GetAddOnMemoryUsage(i)
        totalMemory = totalMemory + mem
        
        local name = C_AddOns.GetAddOnInfo(i)
        self.addonMemory[name] = mem
    end
    
    self.stats.memory = totalMemory
    self.lastMemoryUpdate = GetTime()
end

--- Force a memory refresh (for manual refresh button)
function SystemMonitor:RefreshMemory()
    self:UpdateMemory()
    if self.onStatsUpdated then
        self.onStatsUpdated(self.stats)
    end
end

--- Get current stats
--- @return table Current system stats
function SystemMonitor:GetStats()
    return self.stats
end

--- Get WoW version info
--- @return table WoW version information
function SystemMonitor:GetWoWVersion()
    return self.wowVersion
end

--- Get addon memory breakdown
--- @param sorted boolean Whether to return sorted by memory usage
--- @return table Addon memory data
function SystemMonitor:GetAddonMemory(sorted)
    if not sorted then
        return self.addonMemory
    end
    
    -- Convert to sorted array
    local result = {}
    for name, mem in pairs(self.addonMemory) do
        result[#result + 1] = {name = name, memory = mem}
    end
    
    table.sort(result, function(a, b) return a.memory > b.memory end)
    return result
end

--- Format memory for display
--- @param kb number Memory in KB
--- @return string Formatted memory string
function SystemMonitor:FormatMemory(kb)
    if kb >= 1024 then
        return string.format("%.1f MB", kb / 1024)
    else
        return string.format("%.0f KB", kb)
    end
end

--- Format uptime for display
--- @param seconds number Uptime in seconds
--- @return string Formatted uptime string
function SystemMonitor:FormatUptime(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    
    if hours > 0 then
        return string.format("%dh %dm %ds", hours, mins, secs)
    elseif mins > 0 then
        return string.format("%dm %ds", mins, secs)
    else
        return string.format("%ds", secs)
    end
end

--- Set update interval
--- @param interval number Update interval in seconds
function SystemMonitor:SetUpdateInterval(interval)
    self.updateInterval = interval
    if self.updateTimer then
        self:StartUpdates()
    end
end
