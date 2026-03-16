--[[
    MedaDebug Lifecycle
    ADDON_LOADED, PLAYER_LOGIN, and PLAYER_LOGOUT ownership
]]

local addonName, MedaDebug = ...
local RuntimeRegistry = MedaDebug.RuntimeRegistry

local function WireOutputCallbacks()
    if not MedaDebug.OutputManager then
        return
    end

    MedaDebug.OutputManager.onNewMessage = function(entry, isUpdate)
        if MedaDebug.MainHost then
            MedaDebug.MainHost:HandleNewMessage(entry, isUpdate)
        end
    end
end

local function WireErrorCallbacks()
    if not MedaDebug.ErrorHandler then
        return
    end

    MedaDebug.ErrorHandler.onNewError = function(entry)
        if MedaDebug.ErrorNotification then
            local count = MedaDebug.ErrorHandler:GetVisibleErrorCount()
            MedaDebug.ErrorNotification:UpdateCount(count)
        end
        if MedaDebug.MainHost then
            MedaDebug.MainHost:HandleErrorChanged("new", entry)
        end
        MedaDebug:UpdateErrorBar()
    end

    MedaDebug.ErrorHandler.onErrorUpdated = function(entry)
        if MedaDebug.ErrorNotification then
            local count = MedaDebug.ErrorHandler:GetVisibleErrorCount()
            MedaDebug.ErrorNotification:UpdateCount(count)
        end
        if MedaDebug.MainHost then
            MedaDebug.MainHost:HandleErrorChanged("update", entry)
        end
        MedaDebug:UpdateErrorBar()
    end

    MedaDebug.ErrorHandler.onErrorsCleared = function()
        if MedaDebug.ErrorNotification then
            MedaDebug.ErrorNotification:UpdateCount(0)
        end
        if MedaDebug.MainHost then
            MedaDebug.MainHost:HandleErrorChanged("clear")
        end
        if MedaDebug.ErrorsTab and MedaDebug.ErrorsTab.RefreshData then
            MedaDebug.ErrorsTab:RefreshData()
        end
        MedaDebug:UpdateErrorBar()
    end

    MedaDebug.ErrorHandler.onSuppressChanged = function()
        if MedaDebug.ErrorNotification then
            local count = MedaDebug.ErrorHandler:GetVisibleErrorCount()
            MedaDebug.ErrorNotification:UpdateCount(count)
        end
        if MedaDebug.MainHost then
            MedaDebug.MainHost:HandleErrorChanged("suppress")
        end
        if MedaDebug.ErrorsTab and MedaDebug.ErrorsTab.RefreshData then
            MedaDebug.ErrorsTab:RefreshData()
        end
        MedaDebug:UpdateErrorBar()
    end
end

local function RestoreWorkspaceState()
    if not MedaDebug.MainHost or not MedaDebug.db then
        return
    end

    if MedaDebug.db.options.devMode or MedaDebug.db.frameState.isOpen then
        MedaDebug.MainHost:Show()
    end
end

local function InitializeUserInterface()
    if MedaDebug.MainHost then
        MedaDebug.MainHost:Initialize()
    end

    if MedaDebug.log.session.reloadCount > 1 then
        MedaDebug:LogInternal("MedaDebug", "--- Reload #" .. MedaDebug.log.session.reloadCount .. " ---", "INFO")
    end

    MedaDebug:InitializeMinimapButton()

    if MedaDebug.ErrorNotification and MedaDebug.ErrorNotification.Initialize then
        MedaDebug.ErrorNotification:Initialize()
    end

    WireOutputCallbacks()
    WireErrorCallbacks()
    RestoreWorkspaceState()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= addonName then
            return
        end

        MedaDebug:InitializeDB()

        local MedaUI = LibStub("MedaUI-2.0")
        if MedaDebug.db.options.muteSounds then
            MedaUI:SetSoundsEnabled(false)
        end

        MedaDebug.log.session.reloadCount = (MedaDebug.log.session.reloadCount or 0) + 1
        if MedaDebug.log.session.startTime == 0 then
            MedaDebug.log.session.startTime = time()
        end

        MedaDebug:InitializeSlashCommands()
        if RuntimeRegistry then
            RuntimeRegistry:InitializePhase("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        MedaDebug:TameBlizzardErrors()
        if RuntimeRegistry then
            RuntimeRegistry:InitializePhase("PLAYER_LOGIN")
        end
        C_Timer.After(0.1, InitializeUserInterface)
    elseif event == "PLAYER_LOGOUT" then
        if MedaDebug.MainHost and MedaDebug.MainHost.PersistState then
            MedaDebug.MainHost:PersistState()
        end
    end
end)
