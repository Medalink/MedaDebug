--[[
    MedaDebug Frame Inspector
    Click-to-inspect tool for debugging UI frames
]]

local addonName, MedaDebug = ...

local FrameInspector = {}
MedaDebug.FrameInspector = FrameInspector

-- Inspector state
FrameInspector.isInspecting = false
FrameInspector.inspectedFrame = nil
FrameInspector.highlightFrame = nil

-- Callbacks
FrameInspector.onFrameInspected = nil

function FrameInspector:Initialize()
    -- Create highlight overlay
    self.highlightFrame = CreateFrame("Frame", "MedaDebugInspectorHighlight", UIParent)
    self.highlightFrame:SetFrameStrata("TOOLTIP")
    self.highlightFrame:EnableMouse(false)
    self.highlightFrame:Hide()
    
    local bg = self.highlightFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 0, 0.3)
    self.highlightFrame.bg = bg
    
    -- Border
    local border = CreateFrame("Frame", nil, self.highlightFrame, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    border:SetBackdropBorderColor(1, 1, 0, 1)
    
    -- Name label
    local label = self.highlightFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOMLEFT", self.highlightFrame, "TOPLEFT", 0, 2)
    label:SetTextColor(1, 1, 0)
    self.highlightFrame.label = label
end

--- Start inspect mode
function FrameInspector:StartInspectMode()
    if self.isInspecting then return end
    
    self.isInspecting = true
    
    -- Create click interceptor
    if not self.clickFrame then
        self.clickFrame = CreateFrame("Button", "MedaDebugInspectorClick", UIParent)
        self.clickFrame:SetAllPoints()
        self.clickFrame:SetFrameStrata("TOOLTIP")
        self.clickFrame:EnableMouse(true)
        self.clickFrame:RegisterForClicks("AnyUp")
        
        self.clickFrame:SetScript("OnClick", function(_, button)
            if button == "LeftButton" then
                local frame = self:GetFrameUnderCursor()
                if frame then
                    self:InspectFrame(frame)
                end
            end
            self:StopInspectMode()
        end)
        
        self.clickFrame:SetScript("OnUpdate", function()
            self:UpdateHighlight()
        end)
        
        self.clickFrame:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then
                self:StopInspectMode()
            end
        end)
    end
    
    self.clickFrame:Show()
    SetCursor("CAST_CURSOR")
    
    MedaDebug:Log("MedaDebug", "Inspect mode: Click a frame or press ESC to cancel", "INFO")
end

--- Stop inspect mode
function FrameInspector:StopInspectMode()
    self.isInspecting = false
    
    if self.clickFrame then
        self.clickFrame:Hide()
    end
    
    if self.highlightFrame then
        self.highlightFrame:Hide()
    end
    
    ResetCursor()
end

--- Get frame under cursor
--- @return Frame|nil
function FrameInspector:GetFrameUnderCursor()
    -- Get all frames under cursor
    local frames = GetMouseFoci()
    if not frames or #frames == 0 then return nil end
    
    -- Filter out our own frames
    for _, frame in ipairs(frames) do
        local name = frame:GetName() or ""
        if not name:match("^MedaDebug") and frame ~= self.clickFrame and frame ~= self.highlightFrame then
            return frame
        end
    end
    
    return frames[1]
end

--- Update highlight position
function FrameInspector:UpdateHighlight()
    if not self.isInspecting then return end
    
    local frame = self:GetFrameUnderCursor()
    if frame and frame ~= self.clickFrame and frame ~= self.highlightFrame then
        self.highlightFrame:ClearAllPoints()
        self.highlightFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        self.highlightFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        
        local name = frame:GetName() or tostring(frame):match("table: (.+)") or "unnamed"
        local objType = frame:GetObjectType()
        self.highlightFrame.label:SetText(name .. " (" .. objType .. ")")
        
        self.highlightFrame:Show()
    else
        self.highlightFrame:Hide()
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
    
    local info = {
        -- Identity
        name = frame:GetName() or "(unnamed)",
        type = frame:GetObjectType(),
        parent = frame:GetParent() and (frame:GetParent():GetName() or "(unnamed parent)") or "nil",
        
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
    }
    
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
    
    -- Get regions
    if frame.GetRegions then
        local regions = {frame:GetRegions()}
        for _, region in ipairs(regions) do
            local regionInfo = {
                name = region:GetName() or "(unnamed)",
                type = region:GetObjectType(),
            }
            
            if region:GetObjectType() == "FontString" then
                regionInfo.text = region:GetText()
            end
            
            info.regions[#info.regions + 1] = regionInfo
        end
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
