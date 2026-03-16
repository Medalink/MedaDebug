--[[
    MedaDebug Timer Tracker
    Track active C_Timer timers and scheduled callbacks
]]

local _, MedaDebug = ...
local MedaUI = LibStub("MedaUI-2.0")

local TimerTracker = {}
MedaDebug.TimerTracker = TimerTracker

-- Tracked timers
TimerTracker.timers = {}
TimerTracker.timerCount = 0
TimerTracker.isEnabled = false
TimerTracker.isHooked = false

-- Callbacks
TimerTracker.onTimerAdded = nil
TimerTracker.onTimerUpdated = nil
TimerTracker.onTimerRemoved = nil

-- Original functions (saved before hooking)
local originalAfter
local originalNewTimer
local originalNewTicker

local function RunInternalAfter(seconds, callback)
    local afterFunc = originalAfter or (C_Timer and C_Timer.After)
    if afterFunc then
        return afterFunc(seconds, callback)
    end

    callback()
    return nil
end

function TimerTracker:Initialize()
    if self.isEnabled then return end
    self.isEnabled = true
    
    -- Hook C_Timer functions (only once, hooks are permanent)
    if not self.isHooked then
        self:HookTimerFunctions()
        self.isHooked = true
    end
    
    -- Start update loop
    self:StartUpdates()
end

--- Enable timer tracking at runtime
function TimerTracker:Enable()
    if self.isEnabled then return end
    self:Initialize()
    MedaDebug:LogInternal("MedaDebug", "Timer tracking enabled", "INFO")
end

--- Disable timer tracking at runtime
function TimerTracker:Disable()
    if not self.isEnabled then return end
    self.isEnabled = false
    
    -- Stop the update frame
    if self.updateFrame then
        self.updateFrame:SetScript("OnUpdate", nil)
    end
    
    -- Clear tracked timers
    wipe(self.timers)
    
    MedaDebug:LogInternal("MedaDebug", "Timer tracking disabled", "INFO")
end

--- Check if enabled
function TimerTracker:IsEnabled()
    return self.isEnabled
end

--- Hook C_Timer functions to track timers
function TimerTracker:HookTimerFunctions()
    local tracker = self
    
    -- Hook C_Timer.After
    if C_Timer and C_Timer.After then
        originalAfter = C_Timer.After
        C_Timer.After = function(seconds, callback)
            if tracker.isEnabled then
                local timerId = tracker.timerCount + 1
                local wrappedCallback = function()
                    tracker:OnTimerFired(timerId, "after")
                    callback()
                end
                local timer = originalAfter(seconds, wrappedCallback)
                tracker:RegisterTimer(timerId, "after", seconds, callback, nil, timer, wrappedCallback)
                return timer
            else
                return originalAfter(seconds, callback)
            end
        end
    end
    
    -- Hook C_Timer.NewTimer
    if C_Timer and C_Timer.NewTimer then
        originalNewTimer = C_Timer.NewTimer
        C_Timer.NewTimer = function(seconds, callback)
            if tracker.isEnabled then
                local timerId = tracker.timerCount + 1
                local wrappedCallback = function()
                    tracker:OnTimerFired(timerId, "timer")
                    callback()
                end
                local timer = originalNewTimer(seconds, wrappedCallback)
                tracker:RegisterTimer(timerId, "timer", seconds, callback, nil, timer, wrappedCallback)
                return timer
            else
                return originalNewTimer(seconds, callback)
            end
        end
    end
    
    -- Hook C_Timer.NewTicker
    if C_Timer and C_Timer.NewTicker then
        originalNewTicker = C_Timer.NewTicker
        C_Timer.NewTicker = function(seconds, callback, iterations)
            if tracker.isEnabled then
                local timerId = tracker.timerCount + 1
                local tickCount = 0
                local wrappedCallback = function()
                    tickCount = tickCount + 1
                    tracker:OnTickerTick(timerId, tickCount, iterations)
                    callback()
                end
                local timer = originalNewTicker(seconds, wrappedCallback, iterations)
                tracker:RegisterTimer(timerId, "ticker", seconds, callback, iterations, timer, wrappedCallback)
                return timer
            else
                return originalNewTicker(seconds, callback, iterations)
            end
        end
    end
end

--- Detect source addon from stack
--- @return string, string Addon name and source line
local function DetectSource()
    local stack = debugstack(4, 5, 0)
    local addon = stack:match("Interface/AddOns/([^/]+)/") or "Unknown"
    local sourceLine = stack:match("([^/\\]+%.lua:%d+)") or "unknown"
    return addon, sourceLine
end

--- Register a new timer
function TimerTracker:RegisterTimer(timerId, timerType, duration, callback, iterations, timerObj, wrappedCallback)
    local sourceAddon, sourceLine = DetectSource()
    if MedaDebug.ProfilerLite then
        MedaDebug.ProfilerLite:RecordSample("TimerRegistered:" .. timerType, "timer", 0, sourceAddon)
    end

    self.timerCount = math.max(self.timerCount, timerId)
    local now = GetTime()
    
    local entry = {
        id = timerId,
        type = timerType,
        duration = duration,
        callback = callback,
        wrappedCallback = wrappedCallback,
        timerObj = timerObj,
        sourceAddon = sourceAddon,
        sourceLine = sourceLine,
        createdAt = now,
        iterations = iterations,
        iterationsRemaining = iterations,
        currentIteration = 0,
        nextFireAt = now + duration,
        status = "active",
        isHighFrequency = duration < 0.1,
    }
    
    self.timers[timerId] = entry
    
    -- Notify UI
    if self.onTimerAdded then
        self.onTimerAdded(entry)
    end
    
    return entry
end

--- Handle timer fired
function TimerTracker:OnTimerFired(timerId, timerType)
    if MedaDebug.ProfilerLite then
        MedaDebug.ProfilerLite:RecordSample("TimerFired:" .. timerType, "timer", 0)
    end

    local timer = self.timers[timerId]
    if not timer or timer.type ~= timerType or timer.status ~= "active" then
        return
    end

    timer.status = "fired"
    timer.firedAt = GetTime()

    if self.onTimerRemoved then
        self.onTimerRemoved(timer)
    end

    -- Remove after a delay for UI display using the original, untracked timer API.
    RunInternalAfter(2, function()
        self.timers[timerId] = nil
    end)
end

--- Handle ticker tick
function TimerTracker:OnTickerTick(timerId, tickCount, maxIterations)
    if MedaDebug.ProfilerLite then
        MedaDebug.ProfilerLite:RecordSample("TickerTick", "timer", 0)
    end

    local timer = self.timers[timerId]
    if not timer or timer.type ~= "ticker" then
        return
    end

    timer.currentIteration = tickCount
    timer.nextFireAt = GetTime() + timer.duration
    
    if maxIterations then
        timer.iterationsRemaining = maxIterations - tickCount
        if timer.iterationsRemaining <= 0 then
            timer.status = "completed"
            if self.onTimerRemoved then
                self.onTimerRemoved(timer)
            end
            RunInternalAfter(2, function()
                self.timers[timerId] = nil
            end)
        end
    end

    if self.onTimerUpdated then
        self.onTimerUpdated(timer)
    end
end

--- Start update loop for countdown display
function TimerTracker:StartUpdates()
    -- Use OnUpdate for smooth countdown display
    if not self.updateFrame then
        self.updateFrame = CreateFrame("Frame")
    end

    self.updateFrame:SetScript("OnUpdate", function(_, elapsed)
        self:UpdateCountdowns()
    end)
end

--- Update timer countdowns
function TimerTracker:UpdateCountdowns()
    local now = GetTime()
    
    for id, timer in pairs(self.timers) do
        if timer.status == "active" then
            timer.timeRemaining = timer.nextFireAt - now
            
            -- Check for expired timers that didn't fire (shouldn't happen normally)
            if timer.timeRemaining < -5 then
                timer.status = "expired"
            end
        end
    end
end

--- Get all active timers
--- @return table Array of timers
function TimerTracker:GetTimers()
    local result = {}
    for _, timer in pairs(self.timers) do
        if timer.status == "active" then
            result[#result + 1] = timer
        end
    end
    
    -- Sort by next fire time
    table.sort(result, function(a, b)
        return (a.nextFireAt or 0) < (b.nextFireAt or 0)
    end)
    
    return result
end

--- Get timers filtered by addon
--- @param addonName string|nil Addon name or nil for all
--- @return table Filtered timers
function TimerTracker:GetFilteredTimers(addonName)
    if not addonName or addonName == "all" then
        return self:GetTimers()
    end
    
    local result = {}
    for _, timer in pairs(self.timers) do
        if timer.status == "active" and timer.sourceAddon == addonName then
            result[#result + 1] = timer
        end
    end
    
    table.sort(result, function(a, b)
        return (a.nextFireAt or 0) < (b.nextFireAt or 0)
    end)
    
    return result
end

--- Get active timer count
--- @return number
function TimerTracker:GetActiveCount()
    local count = 0
    for _, timer in pairs(self.timers) do
        if timer.status == "active" then
            count = count + 1
        end
    end
    return count
end

--- Format time remaining
--- @param seconds number Time in seconds
--- @return string Formatted time
function TimerTracker:FormatTimeRemaining(seconds)
    if seconds <= 0 then
        return "now"
    elseif seconds < 1 then
        return string.format("%.2fs", seconds)
    elseif seconds < 60 then
        return string.format("%.1fs", seconds)
    else
        local mins = math.floor(seconds / 60)
        local secs = seconds % 60
        return string.format("%dm %.0fs", mins, secs)
    end
end

--- Cancel a timer (if possible)
--- @param timerId number Timer ID
--- @return boolean Success
function TimerTracker:CancelTimer(timerId)
    local timer = self.timers[timerId]
    if not timer or timer.status ~= "active" then
        return false
    end
    
    if timer.timerObj and timer.timerObj.Cancel then
        timer.timerObj:Cancel()
        timer.status = "cancelled"
        
        if self.onTimerRemoved then
            self.onTimerRemoved(timer)
        end

        RunInternalAfter(2, function()
            self.timers[timerId] = nil
        end)
        
        return true
    end
    
    return false
end

--- Get unique addons with active timers
--- @return table Array of addon names
function TimerTracker:GetAddonsWithTimers()
    local addons = {}
    local seen = {}
    
    for _, timer in pairs(self.timers) do
        if timer.status == "active" and not seen[timer.sourceAddon] then
            seen[timer.sourceAddon] = true
            addons[#addons + 1] = timer.sourceAddon
        end
    end
    
    table.sort(addons)
    return addons
end

if MedaDebug.RuntimeRegistry then
    MedaDebug.RuntimeRegistry:RegisterModule("TimerTracker", {
        order = 100,
        optionKey = "enableTimerTracking",
    })
end

if MedaDebug.SettingsRegistry then
    MedaDebug.SettingsRegistry:RegisterModule("timer-tracker", {
        title = "Timer Tracker",
        description = "Controls for `C_Timer` instrumentation and retained timer display.",
        sidebarGroup = "Settings",
        sidebarOrder = 50,
        sidebarLabel = "Timer Tracker",
        entryType = "module",
        getEnabled = function()
            return MedaDebug.db and MedaDebug.db.options.enableTimerTracking or false
        end,
        setEnabled = function(enabled)
            MedaDebug.db.options.enableTimerTracking = enabled
            if enabled then
                TimerTracker:Enable()
            else
                TimerTracker:Disable()
            end
        end,
        pages = {
            { id = "timer-tracker", label = "Timer Tracker" },
        },
        pageHeights = {
            ["timer-tracker"] = 180,
        },
        buildPage = function(_, parent)
            local yOff = 0

            local header = MedaUI:CreateSectionHeader(parent, "Timer Tracker", 470)
            header:SetPoint("TOPLEFT", 0, yOff)
            yOff = yOff - 38

            local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", 12, yOff)
            label:SetPoint("RIGHT", parent, "RIGHT", -24, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(true)
            label:SetText("Hooks `C_Timer.After`, `C_Timer.NewTimer`, and `C_Timer.NewTicker`. Keep this disabled unless you are actively inspecting timer churn.")
            label:SetTextColor(unpack(MedaUI.Theme.warning))

            return 180
        end,
    })
end
