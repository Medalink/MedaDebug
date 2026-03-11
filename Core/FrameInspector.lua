--[[
    MedaDebug Frame Inspector
    Click-to-inspect tool for debugging UI frames
    Enhanced with techniques from MedaBinds ConfigMode
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local FrameInspector = {}
MedaDebug.FrameInspector = FrameInspector

-- Inspector state
FrameInspector.isInspecting = false
FrameInspector.inspectedFrame = nil
FrameInspector.highlightFrame = nil
FrameInspector.previewFrame = nil  -- Currently previewed frame (while hovering)
FrameInspector.cursorFrame = nil   -- Frame directly under cursor
FrameInspector.navigatedFrame = nil -- Frame after user navigation (+/- keys)
FrameInspector.helpOverlay = nil   -- Center screen help message
FrameInspector.statusOverlay = nil -- Status message overlay

-- Callbacks
FrameInspector.onFrameInspected = nil
FrameInspector.onFramePreview = nil  -- Called during hover for live preview

-- Pulsing animation state
local pulseTime = 0

-- Throttling for frame detection
local lastUpdateTime = 0
local UPDATE_INTERVAL = 0.05  -- 50ms between updates

-- Default frames to ignore during inspection (full-screen overlays, etc.)
local DEFAULT_IGNORED_FRAMES = {
    -- Model scenes (full-screen effect overlays)
    ["GlobalFXDialogModelScene"] = true,
    ["GlobalFXMediumModelScene"] = true,
    ["GlobalFXBackgroundModelScene"] = true,
    ["CinematicFrameModelScene"] = true,
    -- Fullscreen UI elements
    ["FullScreenBlackFrame"] = true,
    ["FullScreenBlackFrameHigh"] = true,
    ["UIParentFullScreen"] = true,
    ["LowHealthFrame"] = true,
    ["TimerTracker"] = true,
    -- Dropdown/menu backdrop frames
    ["DropDownList1Backdrop"] = true,
    ["DropDownList2Backdrop"] = true,
}

--- Check if a frame name or path should be ignored
--- @param name string Frame name or path to check
--- @return boolean True if frame should be ignored
function FrameInspector:IsFrameIgnored(name)
    if not name or name == "" then return false end
    -- Check defaults
    if DEFAULT_IGNORED_FRAMES[name] then return true end
    -- Check user list (includes both names and paths)
    if MedaDebug.db and MedaDebug.db.inspector and MedaDebug.db.inspector.ignoredFrames then
        if MedaDebug.db.inspector.ignoredFrames[name] then return true end
    end
    return false
end

--- Add a frame to the user ignore list
--- @param name string Frame name to ignore
function FrameInspector:AddIgnoredFrame(name)
    if not name or name == "" then return end
    if not MedaDebug.db then return end

    -- Initialize storage if needed
    if not MedaDebug.db.inspector then
        MedaDebug.db.inspector = {}
    end
    if not MedaDebug.db.inspector.ignoredFrames then
        MedaDebug.db.inspector.ignoredFrames = {}
    end

    MedaDebug.db.inspector.ignoredFrames[name] = true
    MedaDebug:LogInternal("MedaDebug", "Added to ignore list: " .. name, "INFO")
end

--- Remove a frame from the user ignore list
--- @param name string Frame name to remove
function FrameInspector:RemoveIgnoredFrame(name)
    if not name or name == "" then return end
    if MedaDebug.db and MedaDebug.db.inspector and MedaDebug.db.inspector.ignoredFrames then
        MedaDebug.db.inspector.ignoredFrames[name] = nil
        MedaDebug:LogInternal("MedaDebug", "Removed from ignore list: " .. name, "INFO")
    end
end

--- Clear all user ignored frames
function FrameInspector:ClearIgnoredFrames()
    if MedaDebug.db and MedaDebug.db.inspector then
        MedaDebug.db.inspector.ignoredFrames = {}
        MedaDebug:LogInternal("MedaDebug", "Cleared user ignore list", "INFO")
    end
end

--- Get all ignored frames (defaults + user)
--- @return table Two tables: defaults, userIgnored
function FrameInspector:GetIgnoredFrames()
    local userIgnored = {}
    if MedaDebug.db and MedaDebug.db.inspector and MedaDebug.db.inspector.ignoredFrames then
        for name in pairs(MedaDebug.db.inspector.ignoredFrames) do
            userIgnored[#userIgnored + 1] = name
        end
        table.sort(userIgnored)
    end

    local defaults = {}
    for name in pairs(DEFAULT_IGNORED_FRAMES) do
        defaults[#defaults + 1] = name
    end
    table.sort(defaults)

    return defaults, userIgnored
end

function FrameInspector:Initialize()
    -- Create highlight overlay with pulsing animation
    self.highlightFrame = CreateFrame("Frame", "MedaDebugInspectorHighlight", UIParent)
    self.highlightFrame:SetFrameStrata("TOOLTIP")
    self.highlightFrame:EnableMouse(false)
    self.highlightFrame:Hide()

    -- Background glow
    local bg = self.highlightFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 0.85, 0, 0.25)
    self.highlightFrame.bg = bg

    -- Border
    local border = CreateFrame("Frame", nil, self.highlightFrame, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop(MedaUI:CreateBackdrop(true))
    border:SetBackdropColor(0, 0, 0, 0)
    border:SetBackdropBorderColor(1, 0.85, 0, 1)
    self.highlightFrame.border = border

    -- Pulsing animation
    self.highlightFrame:SetScript("OnUpdate", function(_, elapsed)
        pulseTime = pulseTime + elapsed
        local alpha = 0.15 + 0.15 * math.sin(pulseTime * 4)
        bg:SetColorTexture(1, 0.85, 0, alpha)
        local borderAlpha = 0.8 + 0.2 * math.sin(pulseTime * 4)
        border:SetBackdropBorderColor(1, 0.85, 0, borderAlpha)
    end)

    -- Name label
    local label = self.highlightFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", self.highlightFrame, "TOPLEFT", 0, 2)
    label:SetTextColor(1, 0.85, 0)
    self.highlightFrame.label = label

    -- Source label (shows addon that owns the frame)
    local sourceLabel = self.highlightFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sourceLabel:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, 0)
    sourceLabel:SetTextColor(0.7, 0.7, 0.7)
    self.highlightFrame.sourceLabel = sourceLabel

    -- Create top screen help overlay
    self.helpOverlay = CreateFrame("Frame", "MedaDebugInspectorHelp", UIParent)
    self.helpOverlay:SetFrameStrata("TOOLTIP")
    self.helpOverlay:SetSize(320, 120)
    self.helpOverlay:SetPoint("TOP", UIParent, "TOP", 0, -20)
    self.helpOverlay:EnableMouse(false)
    self.helpOverlay:Hide()

    -- Help overlay background
    local helpBg = self.helpOverlay:CreateTexture(nil, "BACKGROUND")
    helpBg:SetAllPoints()
    helpBg:SetColorTexture(0, 0, 0, 0.85)

    -- Help overlay border
    local helpBorder = CreateFrame("Frame", nil, self.helpOverlay, "BackdropTemplate")
    helpBorder:SetAllPoints()
    helpBorder:SetBackdrop(MedaUI:CreateBackdrop(true))
    helpBorder:SetBackdropColor(0, 0, 0, 0)
    helpBorder:SetBackdropBorderColor(1, 0.85, 0, 0.8)

    -- Help title
    local helpTitle = self.helpOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    helpTitle:SetPoint("TOP", self.helpOverlay, "TOP", 0, -10)
    helpTitle:SetTextColor(1, 0.85, 0)
    helpTitle:SetText("Inspection Mode")

    -- Help text
    local helpText = self.helpOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    helpText:SetPoint("TOP", helpTitle, "BOTTOM", 0, -8)
    helpText:SetTextColor(0.9, 0.9, 0.9)
    helpText:SetJustifyH("LEFT")
    helpText:SetSpacing(3)
    helpText:SetText(
        "|cffFFD700Click|r - Select frame\n" ..
        "|cffFFD700+|r / |cffFFD700-|r - Navigate parent/child frames\n" ..
        "|cffFFD700I|r - Add frame to ignore list\n" ..
        "|cffFFD700ESC|r - Exit inspection mode"
    )
    self.helpOverlay.text = helpText

    -- Create status overlay for feedback messages
    self.statusOverlay = CreateFrame("Frame", "MedaDebugInspectorStatus", UIParent)
    self.statusOverlay:SetFrameStrata("TOOLTIP")
    self.statusOverlay:SetSize(300, 40)
    self.statusOverlay:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    self.statusOverlay:EnableMouse(false)
    self.statusOverlay:Hide()

    -- Status background
    local statusBg = self.statusOverlay:CreateTexture(nil, "BACKGROUND")
    statusBg:SetAllPoints()
    statusBg:SetColorTexture(0, 0.4, 0, 0.9)
    self.statusOverlay.bg = statusBg

    -- Status border
    local statusBorder = CreateFrame("Frame", nil, self.statusOverlay, "BackdropTemplate")
    statusBorder:SetAllPoints()
    statusBorder:SetBackdrop(MedaUI:CreateBackdrop(true))
    statusBorder:SetBackdropColor(0, 0, 0, 0)
    statusBorder:SetBackdropBorderColor(0.3, 1, 0.3, 1)
    self.statusOverlay.border = statusBorder

    -- Status text
    local statusText = self.statusOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("CENTER")
    statusText:SetTextColor(1, 1, 1)
    self.statusOverlay.text = statusText
end

--- Show a temporary status message
--- @param message string The message to show
--- @param isSuccess boolean True for green (success), false for red (error)
function FrameInspector:ShowStatus(message, isSuccess)
    if not self.statusOverlay then return end

    self.statusOverlay.text:SetText(message)

    if isSuccess then
        self.statusOverlay.bg:SetColorTexture(0, 0.4, 0, 0.9)
        self.statusOverlay.border:SetBackdropBorderColor(0.3, 1, 0.3, 1)
    else
        self.statusOverlay.bg:SetColorTexture(0.5, 0, 0, 0.9)
        self.statusOverlay.border:SetBackdropBorderColor(1, 0.3, 0.3, 1)
    end

    self.statusOverlay:Show()

    -- Auto-hide after 1.5 seconds
    C_Timer.After(1.5, function()
        if self.statusOverlay then
            self.statusOverlay:Hide()
        end
    end)
end

--- Check if cursor is over a frame (manual hit-test for frames with EnableMouse(false))
--- @param frame Frame The frame to check
--- @return boolean True if cursor is over the frame
function FrameInspector:IsCursorOverFrame(frame)
    if not frame then return false end

    -- Get frame position - use pcall directly on method to capture all return values
    local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
    if not ok or not left or not width or width <= 0 or height <= 0 then return false end

    -- Get cursor position and scale
    local cx, cy = GetCursorPosition()
    local ok2, scale = pcall(frame.GetEffectiveScale, frame)
    if not ok2 or not scale or scale <= 0 then return false end

    cx, cy = cx / scale, cy / scale

    local right = left + width
    local top = bottom + height

    return cx >= left and cx <= right and cy >= bottom and cy <= top
end

--- Get frame source (addon name or "Blizzard") using generic prefix detection
--- @param frame Frame The frame to check
--- @return string Source name
function FrameInspector:GetFrameSource(frame)
    if not frame then return "Unknown" end

    -- Walk up parent chain looking for named frames
    local current = frame
    local depth = 0
    while current and depth < 15 do
        local ok, name = pcall(function() return current:GetName() end)
        if ok and name then
            -- Check for Blizzard UI patterns first
            if name:match("^UI") or name:match("^Interface") or name:match("^Blizzard") then
                return "Blizzard"
            end
            if name:match("^Action") or name:match("^Spell") or name:match("^Buff") or name:match("^Debuff") then
                return "Blizzard"
            end
            if name:match("^Player") or name:match("^Target") or name:match("^Focus") or name:match("^Party") then
                return "Blizzard"
            end
            if name:match("^Minimap") or name:match("^Chat") or name:match("^Game") then
                return "Blizzard"
            end

            -- Generic addon prefix extraction
            local prefix = name:match("^([A-Z][a-z]+[A-Z]?[a-z]*)")  -- CamelCase prefix
                        or name:match("^([A-Z]+)_")                   -- CAPS_prefix
                        or name:match("^([A-Za-z]+)%d")               -- prefix before number
                        or name:match("^([A-Za-z]+)Frame")            -- prefixFrame
                        or name:match("^([A-Za-z]+)Button")           -- prefixButton
                        or name:match("^([A-Za-z]+)Icon")             -- prefixIcon
                        or name:match("^([A-Za-z]+)Bar")              -- prefixBar

            if prefix and #prefix >= 3 then
                return prefix
            end
        end
        local ok2, parent = pcall(function() return current:GetParent() end)
        current = ok2 and parent or nil
        depth = depth + 1
    end
    return "Unknown"
end

--- Start inspect mode
function FrameInspector:StartInspectMode()
    if self.isInspecting then return end

    self.isInspecting = true
    self.cursorFrame = nil
    self.navigatedFrame = nil

    -- Create click interceptor
    if not self.clickFrame then
        self.clickFrame = CreateFrame("Button", "MedaDebugInspectorClick", UIParent)
        self.clickFrame:SetAllPoints()
        self.clickFrame:SetFrameStrata("TOOLTIP")
        self.clickFrame:EnableMouse(true)
        self.clickFrame:EnableKeyboard(true)
        self.clickFrame:SetPropagateKeyboardInput(false)

        self.clickFrame:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then
                -- Use navigated frame, or the currently previewed frame from hover
                local frame = self.navigatedFrame or self.previewFrame
                if frame then
                    self:InspectFrame(frame)
                end
            end
            self:StopInspectMode()
        end)

        self.clickFrame:SetScript("OnUpdate", function(_, elapsed)
            lastUpdateTime = lastUpdateTime + elapsed
            if lastUpdateTime >= UPDATE_INTERVAL then
                lastUpdateTime = 0
                self:UpdateHighlight()
            end
        end)

        self.clickFrame:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then
                self:StopInspectMode()
            elseif key == "I" then
                -- Ignore currently previewed frame
                local targetFrame = self.navigatedFrame or self.previewFrame
                if targetFrame then
                    local ok, name = pcall(targetFrame.GetName, targetFrame)
                    if ok and name and name ~= "" then
                        self:AddIgnoredFrame(name)
                        self:ShowStatus("Ignored: " .. name, true)
                        -- Reset navigation since frame is now ignored
                        self.navigatedFrame = nil
                        self.previewFrame = nil
                    else
                        -- Unnamed frames cannot be reliably ignored
                        local ok2, objType = pcall(targetFrame.GetObjectType, targetFrame)
                        objType = (ok2 and objType) or "Frame"
                        self:ShowStatus("Cannot ignore unnamed " .. objType, false)
                    end
                end
            elseif key == "-" or key == "MINUS" or key == "NUMPADMINUS" then
                -- Navigate to parent frame
                local currentFrame = self.navigatedFrame or self.previewFrame or self.cursorFrame
                if currentFrame then
                    local ok, parent = pcall(currentFrame.GetParent, currentFrame)
                    if ok and parent and parent ~= UIParent and parent ~= WorldFrame then
                        self.navigatedFrame = parent
                        self:UpdateHighlightForFrame(parent)
                    else
                        self:ShowStatus("No more parent frames", false)
                    end
                end
            elseif key == "=" or key == "NUMPADPLUS" then
                -- Navigate to first child frame (+ key is "=" without shift)
                local currentFrame = self.navigatedFrame or self.previewFrame or self.cursorFrame
                if currentFrame and currentFrame.GetChildren then
                    local ok, children = pcall(function() return {currentFrame:GetChildren()} end)
                    if ok and children and #children > 0 then
                        -- Find first visible child
                        for _, child in ipairs(children) do
                            local okVis, isVis = pcall(child.IsVisible, child)
                            if okVis and isVis then
                                self.navigatedFrame = child
                                self:UpdateHighlightForFrame(child)
                                return
                            end
                        end
                        -- No visible children, use first child anyway
                        self.navigatedFrame = children[1]
                        self:UpdateHighlightForFrame(children[1])
                    else
                        self:ShowStatus("No child frames", false)
                    end
                else
                    self:ShowStatus("No child frames", false)
                end
            end
        end)
    end

    self.clickFrame:Show()
    SetCursor("CAST_CURSOR")

    -- Show help overlay
    if self.helpOverlay then
        self.helpOverlay:Show()
    end

    MedaDebug:LogInternal("MedaDebug", "Inspect mode: Click a frame or press ESC to cancel", "INFO")
end

--- Stop inspect mode
function FrameInspector:StopInspectMode()
    self.isInspecting = false
    self.cursorFrame = nil
    self.navigatedFrame = nil

    if self.clickFrame then
        self.clickFrame:Hide()
    end

    if self.highlightFrame then
        self.highlightFrame:Hide()
    end

    if self.helpOverlay then
        self.helpOverlay:Hide()
    end

    if self.statusOverlay then
        self.statusOverlay:Hide()
    end

    ResetCursor()
end

--- Get frame under cursor
--- Uses both IsMouseOver and position-based detection for EnableMouse(false) frames
--- @return Frame|nil
function FrameInspector:GetFrameUnderCursor()
    -- Hide our frames temporarily so they don't interfere
    local clickWasShown = self.clickFrame and self.clickFrame:IsShown()
    local highlightWasShown = self.highlightFrame and self.highlightFrame:IsShown()

    if self.clickFrame then self.clickFrame:Hide() end
    if self.highlightFrame then self.highlightFrame:Hide() end

    local strataOrder = {
        BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
        DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8
    }

    -- First pass: use IsMouseOver (fast, works for EnableMouse(true) frames)
    local bestFrame = nil
    local bestLevel = -1
    local bestStrata = -1
    local positionCandidates = {}  -- Collect visible frames for position check fallback

    local frame = EnumerateFrames()
    while frame do
        local visible = false
        local ok1, result1 = pcall(frame.IsVisible, frame)
        if ok1 then
            if issecretvalue and issecretvalue(result1) then
                -- Skip secret values
            elseif result1 then
                visible = true
            end
        end

        if visible then
            local ok2, result2 = pcall(frame.IsMouseOver, frame)
            local isOver = false
            if ok2 then
                if issecretvalue and issecretvalue(result2) then
                    -- Skip secret values
                elseif result2 then
                    isOver = true
                end
            end

            if isOver then
                local ok3, name = pcall(frame.GetName, frame)
                name = (ok3 and name) or ""

                -- Skip our frames, WorldFrame, UIParent, and ignored frames
                if not name:match("^MedaDebug") and
                   frame ~= WorldFrame and
                   frame ~= UIParent and
                   not self:IsFrameIgnored(name) then

                    -- Skip near-fullscreen frames (likely overlays)
                    local ok6, w = pcall(frame.GetWidth, frame)
                    local ok7, h = pcall(frame.GetHeight, frame)
                    local screenW, screenH = GetScreenWidth(), GetScreenHeight()
                    local isFullscreen = false
                    if ok6 and ok7 and w and h and screenW and screenH then
                        local wSecret = issecretvalue and issecretvalue(w)
                        local hSecret = issecretvalue and issecretvalue(h)
                        if not wSecret and not hSecret then
                            -- Skip if frame covers more than 80% of screen
                            if w > screenW * 0.8 and h > screenH * 0.8 then
                                isFullscreen = true
                            end
                        end
                    end

                    if not isFullscreen then
                        local ok4, strata = pcall(frame.GetFrameStrata, frame)
                        local ok5, level = pcall(frame.GetFrameLevel, frame)
                        strata = ok4 and strata or "MEDIUM"
                        level = ok5 and level or 0
                        local strataNum = strataOrder[strata] or 0

                        if strataNum > bestStrata or (strataNum == bestStrata and level > bestLevel) then
                            bestStrata = strataNum
                            bestLevel = level
                            bestFrame = frame
                        end
                    end
                end
            else
                -- Store for potential position-based check (limit to reasonable frames)
                if #positionCandidates < 500 then  -- Limit to prevent memory issues
                    local ok3, name = pcall(frame.GetName, frame)
                    name = (ok3 and name) or ""
                    if not name:match("^MedaDebug") and
                       frame ~= WorldFrame and
                       frame ~= UIParent and
                       not self:IsFrameIgnored(name) then
                        -- Only store frames with reasonable size (potential UI elements)
                        local ok6, w = pcall(frame.GetWidth, frame)
                        local ok7, h = pcall(frame.GetHeight, frame)
                        -- Check for secret values before comparing
                        if ok6 and ok7 and w and h then
                            local wSecret = issecretvalue and issecretvalue(w)
                            local hSecret = issecretvalue and issecretvalue(h)
                            if not wSecret and not hSecret and w >= 5 and h >= 5 and w <= 2000 and h <= 2000 then
                                positionCandidates[#positionCandidates + 1] = frame
                            end
                        end
                    end
                end
            end
        end
        frame = EnumerateFrames(frame)
    end

    -- Second pass: if no frame found via IsMouseOver, try position-based detection
    -- This catches EnableMouse(false) frames like status bars
    if not bestFrame and #positionCandidates > 0 then
        for _, candidate in ipairs(positionCandidates) do
            if self:IsCursorOverFrame(candidate) then
                local ok4, strata = pcall(candidate.GetFrameStrata, candidate)
                local ok5, level = pcall(candidate.GetFrameLevel, candidate)
                strata = ok4 and strata or "MEDIUM"
                level = ok5 and level or 0
                local strataNum = strataOrder[strata] or 0

                if strataNum > bestStrata or (strataNum == bestStrata and level > bestLevel) then
                    bestStrata = strataNum
                    bestLevel = level
                    bestFrame = candidate
                end
            end
        end
    end

    -- Restore our frames
    if clickWasShown and self.clickFrame then self.clickFrame:Show() end
    if highlightWasShown and self.highlightFrame then self.highlightFrame:Show() end

    return bestFrame
end

--- Update highlight for a specific frame (used when navigating with +/-)
--- @param frame Frame The frame to highlight
function FrameInspector:UpdateHighlightForFrame(frame)
    if not frame or not self.highlightFrame then return end

    self.highlightFrame:ClearAllPoints()
    self.highlightFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    self.highlightFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    local ok1, name = pcall(function() return frame:GetName() end)
    name = (ok1 and name) or tostring(frame):match("table: (.+)") or "unnamed"
    local ok2, objType = pcall(function() return frame:GetObjectType() end)
    objType = (ok2 and objType) or "Frame"
    self.highlightFrame.label:SetText(name .. " (" .. objType .. ")")

    -- Show frame source (addon that owns it)
    local source = self:GetFrameSource(frame)
    self.highlightFrame.sourceLabel:SetText("Source: " .. source)

    self.highlightFrame:Show()

    -- Live preview: update inspector tab
    if frame ~= self.previewFrame then
        self.previewFrame = frame
        if self.onFramePreview then
            local info = self:GetFrameInfo(frame)
            self.onFramePreview(frame, info, true)  -- true = preview mode
        end
    end
end

--- Update highlight position
function FrameInspector:UpdateHighlight()
    if not self.isInspecting or not self.highlightFrame then return end

    -- Get frame under cursor
    local cursorFrame = self:GetFrameUnderCursor()

    -- If cursor moved to a different frame, reset navigation
    if cursorFrame ~= self.cursorFrame then
        self.cursorFrame = cursorFrame
        self.navigatedFrame = nil  -- Reset navigation when cursor moves to new frame
    end

    -- Use navigated frame if set, otherwise use cursor frame
    local frame = self.navigatedFrame or cursorFrame

    if frame and frame ~= self.clickFrame and frame ~= self.highlightFrame then
        self.highlightFrame:ClearAllPoints()
        self.highlightFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        self.highlightFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

        local ok1, name = pcall(function() return frame:GetName() end)
        name = (ok1 and name) or tostring(frame):match("table: (.+)") or "unnamed"
        local ok2, objType = pcall(function() return frame:GetObjectType() end)
        objType = (ok2 and objType) or "Frame"
        self.highlightFrame.label:SetText(name .. " (" .. objType .. ")")

        -- Show frame source (addon that owns it)
        local source = self:GetFrameSource(frame)
        self.highlightFrame.sourceLabel:SetText("Source: " .. source)

        self.highlightFrame:Show()

        -- Live preview: update inspector tab if frame changed
        if frame ~= self.previewFrame then
            self.previewFrame = frame
            if self.onFramePreview then
                local info = self:GetFrameInfo(frame)
                self.onFramePreview(frame, info, true)  -- true = preview mode
            end
        end
    else
        self.highlightFrame:Hide()
        self.previewFrame = nil
    end
end

--- Inspect a frame
--- @param frame Frame The frame to inspect
function FrameInspector:InspectFrame(frame)
    self.inspectedFrame = frame
    
    -- Store in global for console access
    _G.INSPECTED = frame
    
    -- Gather frame info
    local info = self:GetFrameInfo(frame)
    
    -- Notify UI
    if self.onFrameInspected then
        self.onFrameInspected(frame, info)
    end
    
    return info
end

--- Get detailed frame information
--- @param frame Frame The frame to inspect
--- @return table Frame information
function FrameInspector:GetFrameInfo(frame)
    if not frame then return nil end

    local objType = frame:GetObjectType()

    local info = {
        -- Identity
        name = frame:GetName() or "(unnamed)",
        type = objType,
        parent = frame:GetParent() and (frame:GetParent():GetName() or "(unnamed parent)") or "nil",
        source = self:GetFrameSource(frame),

        -- Geometry
        width = frame:GetWidth(),
        height = frame:GetHeight(),
        effectiveScale = frame:GetEffectiveScale(),
        points = {},

        -- State
        isShown = frame:IsShown(),
        isVisible = frame:IsVisible(),
        alpha = frame:GetAlpha(),
        frameLevel = frame.GetFrameLevel and frame:GetFrameLevel() or "N/A",
        frameStrata = frame.GetFrameStrata and frame:GetFrameStrata() or "N/A",

        -- Scripts
        scripts = {},

        -- Children
        children = {},

        -- Regions
        regions = {},

        -- Widget-specific values
        widgetValues = {},
    }

    -- Helper to safely get values that might be secrets
    local function safeValue(val)
        if val == nil then return nil end
        if issecretvalue and issecretvalue(val) then
            return "(secret)"
        end
        return val
    end

    local function safeNumber(val)
        if val == nil then return 0 end
        if issecretvalue and issecretvalue(val) then
            return nil  -- Return nil so we know it's secret
        end
        return val
    end

    -- Collect widget-specific values based on type
    if objType == "StatusBar" then
        local ok, min, max, value = pcall(function()
            local mn, mx = frame:GetMinMaxValues()
            local v = frame:GetValue()
            return mn, mx, v
        end)

        if ok then
            local minNum = safeNumber(min)
            local maxNum = safeNumber(max)
            local valueNum = safeNumber(value)

            local percent = "(secret)"
            if minNum and maxNum and valueNum and maxNum > minNum then
                percent = string.format("%.1f", (valueNum - minNum) / (maxNum - minNum) * 100)
            end

            info.widgetValues.statusBar = {
                min = safeValue(min),
                max = safeValue(max),
                value = safeValue(value),
                percent = percent,
                fillStyle = frame.GetFillStyle and safeValue(frame:GetFillStyle()) or "N/A",
                orientation = frame.GetOrientation and safeValue(frame:GetOrientation()) or "N/A",
            }

            -- Get status bar texture
            local texture = frame:GetStatusBarTexture()
            if texture then
                local texturePath = safeValue(texture:GetTexture())
                info.widgetValues.statusBar.texture = texturePath or "(none)"
                local ok2, r, g, b, a = pcall(texture.GetVertexColor, texture)
                if ok2 then
                    info.widgetValues.statusBar.color = string.format("%.2f, %.2f, %.2f, %.2f",
                        safeNumber(r) or 1, safeNumber(g) or 1, safeNumber(b) or 1, safeNumber(a) or 1)
                end
            end
        end
    elseif objType == "Button" then
        local ok, text, enabled = pcall(function()
            return frame.GetText and frame:GetText() or nil, frame:IsEnabled()
        end)
        if ok then
            info.widgetValues.button = {
                text = safeValue(text),
                enabled = safeValue(enabled),
            }
            if frame.GetNormalTexture then
                local tex = frame:GetNormalTexture()
                info.widgetValues.button.normalTexture = tex and safeValue(tex:GetTexture()) or nil
            end
        end
    elseif objType == "Slider" then
        local ok, min, max, value, step, orientation = pcall(function()
            local mn, mx = frame:GetMinMaxValues()
            return mn, mx, frame:GetValue(), frame:GetValueStep(), frame:GetOrientation()
        end)
        if ok then
            info.widgetValues.slider = {
                min = safeValue(min),
                max = safeValue(max),
                value = safeValue(value),
                step = safeValue(step),
                orientation = safeValue(orientation),
            }
        end
    elseif objType == "EditBox" then
        local ok, text, maxLetters, isMulti, isNum = pcall(function()
            return frame:GetText(), frame:GetMaxLetters(), frame:IsMultiLine(), frame:IsNumeric()
        end)
        if ok then
            info.widgetValues.editBox = {
                text = safeValue(text),
                maxLetters = safeValue(maxLetters),
                isMultiLine = safeValue(isMulti),
                isNumeric = safeValue(isNum),
            }
        end
    elseif objType == "CheckButton" then
        local ok, checked, text = pcall(function()
            return frame:GetChecked(), frame.GetText and frame:GetText() or nil
        end)
        if ok then
            info.widgetValues.checkButton = {
                checked = safeValue(checked),
                text = safeValue(text),
            }
        end
    elseif objType == "Cooldown" then
        local ok, start, duration, enabled = pcall(function()
            return frame:GetCooldownTimes()
        end)
        if ok then
            local startNum = safeNumber(start)
            local durationNum = safeNumber(duration)
            info.widgetValues.cooldown = {
                start = startNum and (startNum / 1000) or "(secret)",
                duration = durationNum and (durationNum / 1000) or "(secret)",
                enabled = safeValue(enabled),
            }
        end
    end
    
    -- Get anchor points
    for i = 1, frame:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
        info.points[i] = {
            point = point,
            relativeTo = relativeTo and (relativeTo:GetName() or "(unnamed)") or "nil",
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end
    
    -- Get scripts
    local scriptNames = {
        "OnShow", "OnHide", "OnEvent", "OnUpdate", "OnClick", 
        "OnEnter", "OnLeave", "OnDragStart", "OnDragStop",
        "OnMouseDown", "OnMouseUp", "OnKeyDown", "OnKeyUp"
    }
    for _, scriptName in ipairs(scriptNames) do
        if frame:HasScript(scriptName) and frame:GetScript(scriptName) then
            info.scripts[#info.scripts + 1] = scriptName
        end
    end
    
    -- Get children
    if frame.GetChildren then
        local children = {frame:GetChildren()}
        for _, child in ipairs(children) do
            info.children[#info.children + 1] = {
                name = child:GetName() or "(unnamed)",
                type = child:GetObjectType(),
            }
        end
    end
    
    -- Get regions with detailed info
    if frame.GetRegions then
        local ok, regions = pcall(function() return {frame:GetRegions()} end)
        if ok and regions then
            for _, region in ipairs(regions) do
                local regionType = region:GetObjectType()
                local regionInfo = {
                    name = region:GetName() or "(unnamed)",
                    type = regionType,
                }

                if regionType == "FontString" then
                    local ok2, text = pcall(region.GetText, region)
                    regionInfo.text = ok2 and safeValue(text) or nil

                    local ok3, font, fontSize = pcall(function()
                        return select(1, region:GetFont()), select(2, region:GetFont())
                    end)
                    regionInfo.font = ok3 and safeValue(font) or "N/A"
                    regionInfo.fontSize = ok3 and safeValue(fontSize) or 0

                    local ok4, r, g, b, a = pcall(region.GetTextColor, region)
                    if ok4 then
                        local rn, gn, bn, an = safeNumber(r), safeNumber(g), safeNumber(b), safeNumber(a)
                        if rn and gn and bn then
                            regionInfo.textColor = string.format("%.2f, %.2f, %.2f, %.2f", rn, gn, bn, an or 1)
                        else
                            regionInfo.textColor = "(secret)"
                        end
                    end
                elseif regionType == "Texture" or regionType == "MaskTexture" then
                    local ok2, texturePath = pcall(region.GetTexture, region)
                    regionInfo.texture = ok2 and safeValue(texturePath) or "(none)"

                    if region.GetTexCoord then
                        local ok3, left, right, top, bottom = pcall(region.GetTexCoord, region)
                        if ok3 and left then
                            local ln, rn, tn, bn = safeNumber(left), safeNumber(right), safeNumber(top), safeNumber(bottom)
                            if ln and rn and tn and bn then
                                regionInfo.texCoord = string.format("%.2f, %.2f, %.2f, %.2f", ln, rn, tn, bn)
                            else
                                regionInfo.texCoord = "(secret)"
                            end
                        end
                    end
                    if region.GetVertexColor then
                        local ok3, r, g, b, a = pcall(region.GetVertexColor, region)
                        if ok3 then
                            local rn, gn, bn, an = safeNumber(r), safeNumber(g), safeNumber(b), safeNumber(a)
                            if rn and gn and bn then
                                regionInfo.vertexColor = string.format("%.2f, %.2f, %.2f, %.2f", rn, gn, bn, an or 1)
                            else
                                regionInfo.vertexColor = "(secret)"
                            end
                        end
                    end
                    if region.GetBlendMode then
                        local ok3, blendMode = pcall(region.GetBlendMode, region)
                        regionInfo.blendMode = ok3 and safeValue(blendMode) or nil
                    end
                end

                info.regions[#info.regions + 1] = regionInfo
            end
        end
    end

    -- Get secrets info (WoW 12.0.0+)
    if MedaDebug.SecretsExplorer then
        info.secrets = MedaDebug.SecretsExplorer:GetWidgetSecretInfo(frame)
    end

    return info
end

--- Get frame path for copying
--- @param frame Frame The frame
--- @return string Lua path to access frame
function FrameInspector:GetFramePath(frame)
    local name = frame:GetName()
    if name then
        return name
    end
    
    -- Try to build path through parents
    local path = {}
    local current = frame
    local unnamed = false
    
    while current do
        local parentName = current:GetName()
        if parentName then
            table.insert(path, 1, parentName)
            break
        else
            -- Find index in parent's children
            local parent = current:GetParent()
            if parent and parent.GetChildren then
                local children = {parent:GetChildren()}
                for i, child in ipairs(children) do
                    if child == current then
                        table.insert(path, 1, ":GetChildren()[" .. i .. "]")
                        break
                    end
                end
            end
            unnamed = true
        end
        current = current:GetParent()
    end
    
    if #path > 0 then
        if unnamed then
            return path[1] .. table.concat(path, "", 2)
        else
            return path[1]
        end
    end
    
    return "-- Unable to determine path"
end

--- Show anchor lines for a frame
--- @param frame Frame The frame
function FrameInspector:ShowAnchors(frame)
    -- TODO: Draw lines from frame to its anchor points
    -- This would require creating line textures
end

--- Get currently inspected frame
--- @return Frame|nil
function FrameInspector:GetInspectedFrame()
    return self.inspectedFrame
end
