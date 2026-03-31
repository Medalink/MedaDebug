local _, MedaDebug = ...

local MedaUI = LibStub("MedaUI-2.0")
local SettingsRegistry = MedaDebug.SettingsRegistry

local function SafeGetLogPolicy(addonInfo)
    if not addonInfo or type(addonInfo.getLogPolicy) ~= "function" then
        return nil
    end

    local ok, policy = pcall(addonInfo.getLogPolicy)
    if ok then
        return policy
    end

    return nil
end

local function SafeSetLogPolicy(addonInfo, policy)
    if not addonInfo or type(addonInfo.setLogPolicy) ~= "function" then
        return
    end

    local ok = pcall(addonInfo.setLogPolicy, policy)
    if not ok then
        return
    end
end

local function CreateNote(parent, text, yOff, color)
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPLEFT", 0, yOff)
    note:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(true)
    note:SetText(text)
    note:SetTextColor(unpack(color or MedaUI.Theme.textDim or { 0.7, 0.7, 0.7, 1 }))
    return note, yOff - note:GetStringHeight() - 12
end

local function CreateCard(parent, addonName, addonInfo, yOff)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetPoint("TOPLEFT", 0, yOff)
    card:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    card:SetBackdrop(MedaUI:CreateBackdrop(true))
    card:SetBackdropColor(unpack(MedaUI.Theme.backgroundLight or { 0.12, 0.12, 0.14, 0.92 }))
    card:SetBackdropBorderColor(unpack(MedaUI.Theme.border or { 0.25, 0.25, 0.25, 1 }))

    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText(addonName)
    title:SetTextColor(unpack(addonInfo.color or MedaUI.Theme.gold or { 0.9, 0.7, 0.15, 1 }))

    local subtitle = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetWordWrap(true)
    subtitle:SetText("Sender-owned logging policy. Changes write back into the addon's own SavedVariables.")
    subtitle:SetTextColor(unpack(MedaUI.Theme.textDim or { 0.7, 0.7, 0.7, 1 }))

    local controls = MedaUI:BuildLogPolicyControls(card, function()
        return SafeGetLogPolicy(addonInfo)
    end, function(policy)
        SafeSetLogPolicy(addonInfo, policy)
    end, {
        width = 270,
        includeChatFallback = true,
    })
    controls:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
    controls:Refresh()

    local cardHeight = 44 + subtitle:GetStringHeight() + controls:GetHeight()
    card:SetHeight(cardHeight + 18)

    return yOff - card:GetHeight() - 12
end

local function BuildAddonLoggingPage(parent)
    local yOff = 0

    local header = MedaUI:CreateSectionHeader(parent, "Addon Logging", 520)
    header:SetPoint("TOPLEFT", 0, yOff)
    yOff = yOff - 40

    local intro
    intro, yOff = CreateNote(
        parent,
        "These controls edit sender-owned logging policies through addon registration callbacks. MedaDebug only reflects and forwards the settings.",
        yOff
    )

    local addonNames = MedaDebug:GetRegisteredAddons()
    local editableCount = 0
    local skippedCount = 0

    for _, addonName in ipairs(addonNames) do
        local addonInfo = MedaDebug:GetAddonInfo(addonName)
        if addonInfo and type(addonInfo.getLogPolicy) == "function" and type(addonInfo.setLogPolicy) == "function" then
            editableCount = editableCount + 1
            yOff = CreateCard(parent, addonName, addonInfo, yOff)
        else
            skippedCount = skippedCount + 1
        end
    end

    if editableCount == 0 then
        local emptyLabel
        emptyLabel, yOff = CreateNote(
            parent,
            "No registered addons currently expose logging-policy callbacks.",
            yOff,
            MedaUI.Theme.warning or { 1, 0.75, 0.2, 1 }
        )
    elseif skippedCount > 0 then
        local skippedLabel
        skippedLabel, yOff = CreateNote(
            parent,
            string.format("%d registered addon(s) were omitted because they do not expose editable logging policies.", skippedCount),
            yOff
        )
    end

    return math.abs(yOff) + 40
end

SettingsRegistry:RegisterModule("addon-logging", {
    title = "Addon Logging",
    description = "Unified editor for sender-owned logging policies exposed by MedaDebug-integrated addons.",
    sidebarGroup = "Settings",
    sidebarOrder = 40,
    entryType = "nav",
    pages = {
        { id = "addon-logging", label = "Addon Logging" },
    },
    buildPage = function(_, parent)
        return BuildAddonLoggingPage(parent)
    end,
})
