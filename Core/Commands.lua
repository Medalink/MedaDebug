--[[
    MedaDebug Commands
    Shared command handlers and shell-level runtime helpers
]]

local _, MedaDebug = ...

function MedaDebug:ShowMainPage(pageId)
    if not self.MainHost then
        return
    end

    if pageId and self.WorkspaceRegistry and not self.WorkspaceRegistry:GetPage(pageId) then
        pageId = nil
    end

    self.MainHost:Initialize()
    self.MainHost:Show()
    if pageId then
        self.MainHost:SetActiveTab(pageId)
    end
end

function MedaDebug:HandleSlashCommand(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "toggle" then
        if self.MainHost then
            self.MainHost:Toggle()
        end
    elseif cmd == "settings" or cmd == "config" then
        if self.ToggleSettings then
            self:ToggleSettings()
        end
    elseif cmd == "dev" then
        self.db.options.devMode = not self.db.options.devMode
        print("|cff00ff00[MedaDebug]|r Development mode: " .. (self.db.options.devMode and "ON" or "OFF"))
    elseif cmd == "msgs" or cmd == "messages" then
        self:ShowMainPage("messages")
    elseif cmd == "errors" then
        self:ShowMainPage("errors")
    elseif cmd == "events" then
        self:ShowMainPage("events")
    elseif cmd == "console" then
        self:ShowMainPage("console")
    elseif cmd == "inspect" then
        self:ShowMainPage("inspector")
        if self.FrameInspector then
            self.FrameInspector:StartInspectMode()
        end
    elseif cmd == "watch" then
        if rest and rest ~= "" and self.VariableWatch then
            self.VariableWatch:AddWatch(rest)
        end
        self:ShowMainPage("watch")
    elseif cmd == "timers" then
        self:ShowMainPage("timers")
    elseif cmd == "system" or cmd == "sys" then
        self:ShowMainPage("system")
    elseif cmd == "secrets" then
        self:ShowMainPage("secrets")
    elseif cmd == "perf" or cmd == "profiler" then
        self:ShowMainPage("perf")
    elseif cmd == "clear" then
        if rest == "all" then
            if self.OutputManager then
                self.OutputManager:ClearAll()
            end
        elseif self.MainHost then
            self.MainHost:ClearCurrentPage()
        end
    elseif cmd == "run" then
        if rest and rest ~= "" and self.Console then
            self.Console:Execute(rest)
        end
    elseif cmd == "var" then
        if rest and rest ~= "" and self.VariableWatch then
            self.VariableWatch:AddWatch(rest)
        end
    elseif cmd == "unvar" then
        if rest and rest ~= "" and self.VariableWatch then
            self.VariableWatch:RemoveWatch(rest)
        end
    elseif cmd == "snapshot" then
        if self.SVDiff then
            self.SVDiff:TakeSnapshot()
            print("|cff00ff00[MedaDebug]|r SavedVariables snapshot taken")
        end
    elseif cmd == "diff" then
        if self.SVDiff then
            self.SVDiff:ShowDiff()
        end
    elseif cmd == "export" then
        if self.OutputManager then
            self.OutputManager:ExportSession()
        end
    elseif cmd == "help" then
        print("|cff00ff00[MedaDebug]|r Commands:")
        print("  /mdebug - Toggle main workspace")
        print("  /mdebug settings - Open settings")
        print("  /mdebug dev - Toggle development mode")
        print("  /mdebug msgs|errors|events|console|inspect|watch|timers|system|secrets|perf - Open page")
        print("  /mdebug clear [all] - Clear active view or all messages")
        print("  /mdebug run <code> - Execute Lua code")
        print("  /mdebug var <path> - Watch variable")
        print("  /mdebug snapshot - Take SV snapshot")
        print("  /mdebug diff - Show SV diff")
    else
        print("|cff00ff00[MedaDebug]|r Unknown command. Type /mdebug help for commands.")
    end
end

function MedaDebug:InitializeSlashCommands()
    SLASH_MEDADEBUG1 = "/mdebug"
    SLASH_MEDADEBUG2 = "/medadebug"
    SlashCmdList["MEDADEBUG"] = function(msg)
        MedaDebug:HandleSlashCommand(msg)
    end
end

function MedaDebug:InitializeMinimapButton()
    local MedaUI = LibStub("MedaUI-2.0", true)
    if not MedaUI then
        return
    end

    self.minimapButton = MedaUI:CreateMinimapButton(
        "MedaDebug",
        "Interface\\AddOns\\MedaDebug\\Media\\debug",
        function()
            if self.MainHost then
                self.MainHost:Toggle()
            end
        end,
        function()
            if self.ToggleSettings then
                self:ToggleSettings()
            end
        end,
        self.db
    )

    if self.minimapButton then
        local LDB = LibStub("LibDataBroker-1.1", true)
        if LDB then
            self.minimapButton.OnTooltipShow = function(tooltip)
                local theme = MedaUI:GetTheme()
                tooltip:AddLine("MedaDebug", unpack(theme.gold))
                tooltip:AddLine(" ")
                tooltip:AddLine("Left-click to toggle debug workspace", unpack(theme.text))
                tooltip:AddLine("Right-click for settings", unpack(theme.text))
                tooltip:AddLine("Drag to move", unpack(theme.textDim))

                if self.ErrorHandler then
                    local errorCount = self.ErrorHandler:GetErrorCount()
                    if errorCount > 0 then
                        tooltip:AddLine(" ")
                        tooltip:AddLine(errorCount .. " error(s) captured", 1, 0.3, 0.3)
                    end
                end
            end
        end
    end
end

function MedaDebug:TameBlizzardErrors()
    if not self.db.options.tameBlizzardErrors then
        return
    end

    local blizzFrame = _G.ScriptErrorsFrame or _G.BasicScriptErrors
    if blizzFrame then
        blizzFrame:SetScript("OnShow", nil)
        blizzFrame:SetScript("OnEvent", nil)
        blizzFrame:UnregisterAllEvents()
        blizzFrame:Hide()
        blizzFrame.Show = function() end
    end

    if StaticPopupDialogs then
        for _, key in ipairs({
            "TOO_MANY_LUA_ERRORS",
            "ADDON_ACTION_FORBIDDEN",
        }) do
            StaticPopupDialogs[key] = {
                button1 = "",
                button2 = "",
                OnShow = function(popup)
                    popup:Hide()
                end,
            }
            pcall(StaticPopup_Hide, key)
        end
    end

    if self.errorBar then
        return
    end

    local notice = CreateFrame("Button", "MedaDebugErrorBar", UIParent)
    notice:SetHeight(20)
    notice:SetPoint("TOP", UIParent, "TOP", 0, -4)
    notice:SetFrameStrata("HIGH")
    notice:Hide()

    notice.text = notice:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notice.text:SetPoint("CENTER")
    notice.text:SetTextColor(0.7, 0.7, 0.7)
    notice.text:SetShadowOffset(1, -1)
    notice.text:SetShadowColor(0, 0, 0, 0.8)
    notice:SetWidth(400)

    notice:SetScript("OnClick", function()
        MedaDebug:ShowMainPage("errors")
    end)
    notice:SetScript("OnEnter", function(noticeFrame)
        noticeFrame.text:SetTextColor(1, 0.8, 0.5)
    end)
    notice:SetScript("OnLeave", function(noticeFrame)
        noticeFrame.text:SetTextColor(0.7, 0.7, 0.7)
    end)

    self.errorBar = notice
end

function MedaDebug:UpdateErrorBar()
    if not self.errorBar or not self.db.options.tameBlizzardErrors then
        return
    end
    if not self.ErrorHandler then
        return
    end

    local count = self.ErrorHandler:GetVisibleErrorCount()
    if count > 0 then
        self.errorBar.text:SetText(count .. " addon error(s) thrown - click or /mdebug errors to inspect")
        self.errorBar:Show()

        if self.errorBarTimer then
            self.errorBarTimer:Cancel()
        end
        self.errorBarTimer = C_Timer.NewTimer(5, function()
            if self.errorBar then
                self.errorBar:Hide()
            end
        end)
    else
        self.errorBar:Hide()
    end
end

function MedaDebug:SetMinimapButtonShown(show)
    if not self.minimapButton then
        return
    end

    if show then
        self.minimapButton:ShowButton()
        self.db.minimapButton.hide = false
    else
        self.minimapButton:HideButton()
        self.db.minimapButton.hide = true
    end
end
