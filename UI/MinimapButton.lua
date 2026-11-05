-- Skirmish: a button on the minimap. Left-click opens or closes the game, right-click opens the
-- game menu, drag moves it around the minimap edge. /skirmish minimap hides or shows it.

local ADDON, ns = ...
local UI = ns.UI
local MB = {}
UI.MinimapButton = MB

local RADIUS = 80

local function place(b)
    local a = math.rad(SkirmishDB.minimapAngle or 205)
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * RADIUS, math.sin(a) * RADIUS)
end

local function create()
    if MB.button or not Minimap then return end
    local b = CreateFrame("Button", "SkirmishMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Banner_03")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon = icon
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if not UI.built or not UI.frame:IsShown() then UI.Toggle() end
            if UI.frame and UI.frame:IsShown() then UI.Hud.showMenu() end
        else
            UI.Toggle()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            SkirmishDB.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            place(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Warcraft Simulator")
        GameTooltip:AddLine("Left-click: open / close the game", 1, 1, 1)
        GameTooltip:AddLine("Right-click: game menu", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    MB.button = b
    place(b)
    b:SetShown(not SkirmishDB.minimapHidden)
end

function MB.toggle()
    SkirmishDB.minimapHidden = not SkirmishDB.minimapHidden
    if MB.button then MB.button:SetShown(not SkirmishDB.minimapHidden) end
    return not SkirmishDB.minimapHidden
end

-- saved variables are only ready once the addon has finished loading
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    SkirmishDB = SkirmishDB or {}
    create()
end)
