-- Skirmish: slash commands.
--   /skirmish                 open or close the game
--   /skirmish stress [n]      n units a side brawl in the middle of the map (frame-rate test)
--   /skirmish model <unit> <displayID>   use a different creature model for a unit type
--                             (e.g. /skirmish model peasant 87). "/skirmish model <unit>" resets it.
--   /skirmish units           list unit ids for the model command
--   /skirmish face            units walking backwards/sideways? cycles the four ways of turning models
--   /skirmish reset           reset the window size and zoom
--   /skirmish minimap         hide or show the minimap button
--   /skirmish cheat           unlimited gold and lumber for testing (again to turn it off)
--   /skirmish lineup [alliance|orcs|undead|creeps|buildings [race]]   one of every unit in rows by the camera, to compare models
--   /skirmish gallery [page|undead [auto]] every building-sized prop (or the Undead candidates), 24 to a page
--   /skirmish studio          the building studio: change the models that make up each building
--   /skirmish sound           turn unit voices and warnings on or off
--   /skirmish instant | fast  instant / 10x faster building, training and research for testing
--   /skirmish weapons         turn the units' weapons on or off

local ADDON, ns = ...
local E = ns.Engine
local UI = ns.UI

local function say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffd9a54cWarcraft Simulator|r: " .. msg) end

SLASH_SKIRMISH1 = "/skirmish"
SLASH_SKIRMISH2 = "/sk"
SLASH_SKIRMISH3 = "/warsim"
SLASH_SKIRMISH4 = "/ws"
SlashCmdList.SKIRMISH = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "stress" then
        if not UI.built then UI.Toggle() end
        if not UI.frame:IsShown() then UI.frame:Show() end
        UI.stressTest(math.max(4, math.min(80, tonumber(rest) or 40)))
        UI.Hud.hideMenu()
    elseif cmd == "gallery" then
        if not UI.built then UI.Toggle() end
        if not UI.frame:IsShown() then UI.frame:Show() end
        UI.Hud.hideMenu()
        UI.Studio.gallery(rest)
    elseif cmd == "flip" then
        SkirmishDB.viewFlip = not UI.Figures.flipped() and true or false
        if SkirmishDB.viewFlip then SkirmishDB.viewFlip = nil end
        if UI.Figures then
            for _, g in pairs(UI.Figures.groups) do for _, sc in pairs(g) do sc.yaw = nil end end
        end
        UI.dirtyStatic = true
        say("model view " .. (UI.Figures.flipped() and "unmirrored (new)" or "mirrored (old)") .. ". Use this if models look inside out.")
    elseif cmd == "lineup" then
        if not UI.built then UI.Toggle() end
        if not UI.frame:IsShown() then UI.frame:Show() end
        UI.Hud.hideMenu()
        UI.lineup(rest ~= "" and rest:lower() or nil)
    elseif cmd == "model" then
        local unit, id = rest:match("^(%S+)%s*(%d*)$")
        if not unit or not E.Data.Units[unit] then say("unknown unit. /skirmish units lists them.") return end
        SkirmishDB.models = SkirmishDB.models or {}
        SkirmishDB.models[unit] = tonumber(id)
        UI.Hud.portraitKey = nil
        say(unit .. (tonumber(id) and (" now uses display " .. id) or " uses its normal model again"))
    elseif cmd == "units" then
        local ids = {}
        for id in pairs(E.Data.Units) do ids[#ids + 1] = id end
        table.sort(ids)
        say(table.concat(ids, ", "))
    elseif cmd == "turn" or cmd == "face" then
        local n, name = UI.Figures.cycleFacing()
        UI.dirtyStatic = true
        say("model facing " .. n .. " of 8 (" .. name .. "). Repeat until units face the way they walk.")
    elseif cmd == "weapons" then
        SkirmishDB.weapons = SkirmishDB.weapons == false
        if UI.Figures then
            for _, g in pairs(UI.Figures.groups) do for _, sc in pairs(g) do sc.modelKey = nil end end
        end
        say(SkirmishDB.weapons ~= false and "weapons on" or "weapons off")
    elseif cmd == "instant" or cmd == "fast" then
        local v = cmd == "instant" and 1000 or 10
        SkirmishDB.buildSpeed = (SkirmishDB.buildSpeed ~= v) and v or nil
        say(SkirmishDB.buildSpeed and ("testing mode: " .. (v == 1000 and "instant" or "10x faster") .. " building, training and research") or "normal build speed")
    elseif cmd == "sound" or cmd == "sounds" then
        SkirmishDB.sound = SkirmishDB.sound == false
        say("sound " .. (SkirmishDB.sound and "on" or "off"))
    elseif cmd == "cheat" or cmd == "dev" then
        SkirmishDB.cheat = not SkirmishDB.cheat or nil
        say(SkirmishDB.cheat and "testing mode: unlimited gold and lumber" or "testing mode off")
    elseif cmd == "studio" or cmd == "buildings" then
        if not UI.built then UI.Toggle() end
        if not UI.frame:IsShown() then UI.frame:Show() end
        if UI.Studio then UI.Studio.toggle() end
    elseif cmd == "minimap" then
        local shown = UI.MinimapButton.toggle()
        say(shown and "minimap button shown" or "minimap button hidden (/skirmish minimap brings it back)")
    elseif cmd == "reset" then
        SkirmishDB.scale, SkirmishDB.zoom = nil, nil
        if UI.frame then
            UI.frame:SetScale(0.85)
            UI.frame:ClearAllPoints()
            UI.frame:SetPoint("CENTER")
            UI.setZoom(1)
        end
        say("window reset")
    else
        UI.Toggle()
    end
end
