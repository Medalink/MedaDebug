--[[
    MedaDebug Console Tab
    Lua REPL with output capture
]]

local addonName, MedaDebug = ...
local MedaUI = LibStub("MedaUI-1.0")

local ConsoleTab = {}
MedaDebug.ConsoleTab = ConsoleTab
MedaDebug.Console = ConsoleTab -- Alias

ConsoleTab.frame = nil
ConsoleTab.history = {}
ConsoleTab.historyIndex = 0
ConsoleTab.output = {}

function ConsoleTab:Initialize(parent)
    self.frame = parent
    local Theme = MedaUI:GetTheme()
    
    -- Load history from saved variables
    if MedaDebug.db and MedaDebug.db.consoleHistory then
        self.history = MedaDebug.db.consoleHistory
    end
    
    -- Output area (code block)
    self.outputBlock = MedaUI:CreateCodeBlock(parent, parent:GetWidth(), parent:GetHeight() - 35, {
        showLineNumbers = false,
    })
    self.outputBlock:SetPoint("TOPLEFT", 0, 0)
    self.outputBlock:SetPoint("BOTTOMRIGHT", 0, 32)
    
    -- Input area
    self.inputFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self.inputFrame:SetHeight(28)
    self.inputFrame:SetPoint("BOTTOMLEFT", 0, 0)
    self.inputFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    self.inputFrame:SetBackdrop(MedaUI:CreateBackdrop(true))
    self.inputFrame:SetBackdropColor(unpack(Theme.input))
    self.inputFrame:SetBackdropBorderColor(unpack(Theme.border))
    
    -- Prompt
    self.prompt = self.inputFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.prompt:SetPoint("LEFT", 8, 0)
    self.prompt:SetText(">")
    self.prompt:SetTextColor(unpack(Theme.gold))
    
    -- Input edit box
    self.inputBox = CreateFrame("EditBox", nil, self.inputFrame)
    self.inputBox:SetPoint("LEFT", self.prompt, "RIGHT", 4, 0)
    self.inputBox:SetPoint("RIGHT", -8, 0)
    self.inputBox:SetHeight(24)
    self.inputBox:SetFontObject(GameFontNormal)
    self.inputBox:SetTextColor(unpack(Theme.text))
    self.inputBox:SetAutoFocus(false)
    
    self.inputBox:SetScript("OnEnterPressed", function(self)
        ConsoleTab:ExecuteInput()
    end)
    
    self.inputBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    
    -- History navigation
    self.inputBox:SetScript("OnKeyDown", function(editBox, key)
        if key == "UP" then
            ConsoleTab:HistoryPrevious()
        elseif key == "DOWN" then
            ConsoleTab:HistoryNext()
        end
    end)
    
    -- Focus on click
    self.inputFrame:SetScript("OnMouseDown", function()
        self.inputBox:SetFocus()
    end)
    
    -- Show welcome message
    self:AddOutput("-- MedaDebug Console")
    self:AddOutput("-- Type Lua code and press Enter to execute")
    self:AddOutput("-- Use _G.INSPECTED for last inspected frame")
    self:AddOutput("")
end

function ConsoleTab:ExecuteInput()
    local input = self.inputBox:GetText()
    if not input or input == "" then return end
    
    -- Add to history
    table.insert(self.history, input)
    if #self.history > 100 then
        table.remove(self.history, 1)
    end
    self.historyIndex = #self.history + 1
    
    -- Save history
    if MedaDebug.db then
        MedaDebug.db.consoleHistory = self.history
    end
    
    -- Show input
    self:AddOutput("> " .. input)
    
    -- Execute
    self:Execute(input)
    
    -- Clear input
    self.inputBox:SetText("")
end

function ConsoleTab:Execute(code)
    -- Capture print output
    local oldPrint = print
    local printOutput = {}
    print = function(...)
        local args = {...}
        local str = ""
        for i, v in ipairs(args) do
            str = str .. (i > 1 and "\t" or "") .. tostring(v)
        end
        table.insert(printOutput, str)
    end
    
    -- Try to execute as expression first (for return values)
    local func, err = load("return " .. code)
    if not func then
        func, err = load(code)
    end
    
    local success, result
    if func then
        success, result = pcall(func)
    else
        success = false
        result = err
    end
    
    -- Restore print
    print = oldPrint
    
    -- Output print captures
    for _, line in ipairs(printOutput) do
        self:AddOutput(line)
    end
    
    -- Output result
    if success then
        if result ~= nil then
            local output = self:FormatValue(result)
            self:AddOutput(output)
            _G.LAST = result
        end
    else
        self:AddOutput("|cffff4444Error:|r " .. tostring(result))
    end
end

function ConsoleTab:FormatValue(value, depth)
    depth = depth or 0
    local maxDepth = MedaDebug.db and MedaDebug.db.options.consoleMaxTableDepth or 4
    
    if depth > maxDepth then return "..." end
    
    local t = type(value)
    if t == "nil" then
        return "nil"
    elseif t == "boolean" then
        return value and "true" or "false"
    elseif t == "number" then
        return tostring(value)
    elseif t == "string" then
        return '"' .. value:gsub("\n", "\\n"):sub(1, 200) .. '"'
    elseif t == "function" then
        return "<function>"
    elseif t == "userdata" then
        return "<userdata>"
    elseif t == "table" then
        local indent = string.rep("  ", depth)
        local lines = {"{"}
        local count = 0
        for k, v in pairs(value) do
            count = count + 1
            if count > 20 then
                lines[#lines + 1] = indent .. "  ... (more entries)"
                break
            end
            local keyStr = type(k) == "string" and k or ("[" .. tostring(k) .. "]")
            local valStr = self:FormatValue(v, depth + 1)
            lines[#lines + 1] = indent .. "  " .. keyStr .. " = " .. valStr .. ","
        end
        lines[#lines + 1] = indent .. "}"
        return table.concat(lines, "\n")
    else
        return tostring(value)
    end
end

function ConsoleTab:AddOutput(text)
    self.output[#self.output + 1] = text
    
    -- Limit output
    while #self.output > 500 do
        table.remove(self.output, 1)
    end
    
    -- Update display
    self.outputBlock:SetText(table.concat(self.output, "\n"))
    
    -- Scroll to bottom
    -- TODO: CodeBlock scroll to bottom
end

function ConsoleTab:HistoryPrevious()
    if self.historyIndex > 1 then
        self.historyIndex = self.historyIndex - 1
        self.inputBox:SetText(self.history[self.historyIndex] or "")
    end
end

function ConsoleTab:HistoryNext()
    if self.historyIndex < #self.history then
        self.historyIndex = self.historyIndex + 1
        self.inputBox:SetText(self.history[self.historyIndex] or "")
    else
        self.historyIndex = #self.history + 1
        self.inputBox:SetText("")
    end
end

function ConsoleTab:Clear()
    wipe(self.output)
    self.outputBlock:SetText("")
end

function ConsoleTab:OnShow()
    -- Focus input
    C_Timer.After(0.1, function()
        if self.inputBox then
            self.inputBox:SetFocus()
        end
    end)
end
