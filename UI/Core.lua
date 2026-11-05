-- Skirmish: the game window, camera and game loop.
-- You are always player 1 (starting bottom-left); the computer is player 2 (top-right).

local ADDON, ns = ...
local E = ns.Engine
local D, M, S, AI = E.Data, E.Map, E.Sim, E.AI

local UI = ns.UI or {}
ns.UI = UI

SkirmishDB = SkirmishDB or {}

local floor, min, max, abs = math.floor, math.min, math.max, math.abs

UI.TILE = 32
UI.WIN_W, UI.WIN_H = 1240, 846
UI.VIEW_X, UI.VIEW_Y, UI.VIEW_W, UI.VIEW_H = 12, 40, 1216, 566
UI.WHITE = "Interface\\Buttons\\WHITE8X8"
UI.me = 1

function UI.say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffd9a54cWarcraft Simulator|r: " .. msg) end

-- ------------------------------------------------------------------ small helpers used everywhere

function UI.pool(parent, layer, sub)
    local p = { items = {}, n = 0 }
    function p:get()
        self.n = self.n + 1
        local t = self.items[self.n]
        if not t then
            t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0)
            self.items[self.n] = t
        end
        t:Show()
        return t
    end
    function p:reset() self.n = 0 end
    function p:finish() for i = self.n + 1, #self.items do self.items[i]:Hide() end end
    return p
end

function UI.button(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetText(text)
    return b
end

function UI.backdrop(f, dark)
    if not f.SetBackdrop then Mixin(f, BackdropTemplateMixin) end
    f:SetBackdrop({ bgFile = dark and "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" or "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 } })
end

-- map position (tiles) -> board position (board units)
function UI.toBoard(x, y) return x * UI.TILE, y * UI.TILE end

-- cursor -> map position, or nil when the cursor isn't over the view
function UI.cursorMap()
    local v = UI.view
    if not v or not v:IsMouseOver() then return nil end
    local cx, cy = GetCursorPosition()
    local s = v:GetEffectiveScale()
    local x, y = cx / s - v:GetLeft(), v:GetTop() - cy / s
    return (UI.camX + x / UI.zoom) / UI.TILE, (UI.camY + y / UI.zoom) / UI.TILE, x, y
end

-- ------------------------------------------------------------------ camera

function UI.clampCamera()
    local w = UI.w
    local mapW, mapH = (w and w.w or 64) * UI.TILE, (w and w.h or 64) * UI.TILE
    local vw, vh = UI.VIEW_W / UI.zoom, UI.VIEW_H / UI.zoom
    UI.camX = max(0, min(mapW - vw, UI.camX))
    UI.camY = max(0, min(mapH - vh, UI.camY))
    if UI.board then
        UI.board:ClearAllPoints()
        UI.board:SetPoint("TOPLEFT", UI.view, "TOPLEFT", -UI.camX, UI.camY)
    end
end

-- centre the camera on a map position (tiles)
function UI.lookAt(x, y)
    UI.camX = x * UI.TILE - UI.VIEW_W / UI.zoom / 2
    UI.camY = y * UI.TILE - UI.VIEW_H / UI.zoom / 2
    UI.clampCamera()
    UI.dirtyStatic = true
end

function UI.setZoom(z, ax, ay)
    z = max(0.6, min(2.6, z))
    if z == UI.zoom then return end
    -- keep the point under the cursor (or the centre) where it is
    ax = ax or UI.VIEW_W / 2
    ay = ay or UI.VIEW_H / 2
    local mx, my = UI.camX + ax / UI.zoom, UI.camY + ay / UI.zoom
    UI.zoom = z
    UI.board:SetScale(z)
    UI.camX, UI.camY = mx - ax / z, my - ay / z
    UI.clampCamera()
    UI.dirtyStatic = true
    SkirmishDB.zoom = z
end

-- the visible map area in tiles
function UI.viewRect(margin)
    margin = margin or 0
    local T = UI.TILE
    return UI.camX / T - margin, UI.camY / T - margin,
           (UI.camX + UI.VIEW_W / UI.zoom) / T + margin, (UI.camY + UI.VIEW_H / UI.zoom) / T + margin
end

-- ------------------------------------------------------------------ the window

local function build()
    local f = CreateFrame("Frame", "SkirmishFrame", UIParent, "BackdropTemplate")
    f:SetSize(UI.WIN_W, UI.WIN_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not UI.view:IsMouseOver() then self:StartMoving() end end)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    f:SetScale(SkirmishDB.scale or 0.85)
    f:SetToplevel(true)
    UI.frame = f

    -- the window onto the map; the map itself (UI.board) slides and zooms inside it
    local view = CreateFrame("Frame", nil, f)
    view:SetSize(UI.VIEW_W, UI.VIEW_H)
    view:SetPoint("TOPLEFT", UI.VIEW_X, -UI.VIEW_Y)
    pcall(view.SetClipsChildren, view, true)
    view:EnableMouse(true)
    view:EnableMouseWheel(true)
    UI.view = view
    local edge = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    edge:SetTexture(UI.WHITE)
    edge:SetPoint("TOPLEFT", view, "TOPLEFT", -3, 3)
    edge:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 3, -3)
    edge:SetVertexColor(0.05, 0.04, 0.03, 1)

    local board = CreateFrame("Frame", nil, view)
    board:SetSize(D.MAP_W * UI.TILE, D.MAP_H * UI.TILE)
    board:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
    UI.board = board
    UI.zoom = SkirmishDB.zoom or 1.7
    board:SetScale(UI.zoom)
    UI.camX, UI.camY = 0, 0

    -- layers, bottom to top: ground, decals, models, bars, fog, overlay
    local lv = board:GetFrameLevel()
    local function layer(n)
        local l = CreateFrame("Frame", nil, board)
        l:SetAllPoints()
        l:SetFrameLevel(lv + n)
        return l
    end
    UI.groundLayer = layer(1)
    UI.decalLayer = layer(3)
    UI.modelLayer = layer(5)        -- models use levels modelLayer + 1 .. + 400
    UI.barLayer = layer(420)
    UI.fogLayer = layer(440)
    UI.overLayer = layer(460)

    UI.Draw.build()
    UI.Hud.build(f)
    UI.Mini.build(f)
    UI.Input.build(f, view)
    if UI.Studio then UI.Studio.apply() UI.Studio.build() end

    f:SetScript("OnUpdate", function(_, elapsed) UI.onUpdate(elapsed) end)
    f:Hide()
    UI.built = true
end

function UI.Toggle()
    if not UI.built then
        if not UI.Figures.available() then
            UI.say("this client can't draw 3D models in the UI (no ModelScene), so the game can't run here.")
            return
        end
        build()
    end
    if UI.frame:IsShown() then UI.frame:Hide() return end
    UI.frame:Show()
    if not UI.w then UI.Hud.showMenu() end
end

function UI.rescale(d)
    local s = max(0.5, min(1.3, (SkirmishDB.scale or 0.85) + d))
    SkirmishDB.scale = s
    UI.frame:SetScale(s)
end

-- ------------------------------------------------------------------ starting a game

function UI.newGame(opts)
    opts = opts or {}
    -- starting a new game leaves a multiplayer one (as a loss)
    if not opts.net and UI.Net and UI.Net.session then UI.Net.leave() end
    UI.me = opts.me or 1
    local mine = opts.faction or SkirmishDB.faction or "alliance"
    local seed = opts.seed or (floor(GetTime() * 1000) % 100000 + 1)
    -- the enemy's race: chosen in the menu, or one of the other races at random
    local other = opts.enemy or SkirmishDB.enemy
    if not other or not D.Factions[other] then
        local pick = {}
        for _, f in ipairs(D.FactionOrder) do if f ~= mine then pick[#pick + 1] = f end end
        other = pick[seed % #pick + 1]
    end
    local factions = opts.factions or { mine, other }
    local w = S.newWorld({ seed = seed, factions = factions, creeps = true, map = opts.map or SkirmishDB.map or "classic" })
    UI.board:SetSize(w.w * UI.TILE, w.h * UI.TILE)
    if UI.Draw.grass then UI.Draw.grass:SetTexCoord(0, w.w / 4, 0, w.h / 4) end
    if not opts.net then AI.new(w, 2, opts.level or SkirmishDB.level or "normal") end
    if opts.net then w.noFog = opts.fog == false
    else w.noFog = (opts.fog == false) or (SkirmishDB.fog == false) end
    w.net = opts.net
    UI.w = w
    UI.sel = {}
    UI.groups = {}
    UI.mode = nil
    UI.acc = 0
    UI.paused = false
    UI.gameOver = nil
    UI.lastAttackWarn = -99
    UI.Figures.clear("units")
    UI.Figures.clear("trees")
    UI.Figures.clear("fx")
    UI.Draw.reset()
    local home = w.players[UI.me].home
    UI.lookAt(home[1] + 2, home[2] - 1)
    UI.Hud.hideMenu()
    UI.Hud.hideEnd()
    UI.dirtyStatic = true
    UI.Mini.dirtyTerrain = true
    UI.Hud.dirty = true
    -- start with the town hall selected, like the real thing
    for _, e in ipairs(w.list) do
        if e.owner == UI.me and e.kind == "building" then UI.sel = { e.id } break end
    end
    if not opts.net then
        UI.say(string.format("new game: %s vs %s (%s). Seed %d.", D.Factions[mine].name, D.Factions[other].name,
            opts.level or SkirmishDB.level or "normal", seed))
    end
end

-- debug: a big fight in the middle of the map to see how the frame rate holds up
function UI.stressTest(n)
    if not UI.w then UI.newGame() end
    local w = UI.w
    w.noFog = true
    local made = S.stress(w, n or 30)
    UI.lookAt(29, 33)
    UI.sel = {}
    for i = 1, min(24, #made) do UI.sel[#UI.sel + 1] = made[i].id end
    UI.Hud.dirty = true
    UI.say(string.format("stress test: %d units a side fighting in the middle. FPS is shown top right.", n or 30))
end

-- One of every unit, standing in rows by the camera, to compare models and sizes.
-- which: "alliance", "orcs", "creeps" or nil for both armies (heroes included).
function UI.lineup(which)
    UI.newGame({})
    local w = UI.w
    w.noFog = true
    if which and which:sub(1, 9) == "buildings" then
        -- every building (or one race's), finished, in rows (plus a gold mine)
        local fac = which:match("^buildings%s+(%a+)")
        local ids = {}
        for id, b in pairs(D.Buildings) do if b.models and (not fac or b.faction == fac) then ids[#ids + 1] = id end end
        table.sort(ids, function(a, b)
            local A, B = D.Buildings[a], D.Buildings[b]
            if A.faction ~= B.faction then return A.faction < B.faction end
            if A.size ~= B.size then return A.size > B.size end
            return A.name < B.name
        end)
        local x0, y0 = floor((w.w or 64) / 2) - 16, floor((w.h or 64) / 2) - 12
        local x, y, rowH = x0, y0, 0
        for _, id in ipairs(ids) do
            local b = D.Buildings[id]
            if x + b.size > x0 + 34 then x, y, rowH = x0, y + rowH + 2, 0 end
            local e = S.addBuilding(w, D.Buildings[id].faction == "neutral" and 0 or UI.me, id, x, y, true)
            if e then e.lineup = true end
            x, rowH = x + b.size + 1, max(rowH, b.size)
        end
        S.addMine(w, x, y)
        S.updateSupply(w)
        UI.lookAt(x0 + 16, y0 + 8)
        UI.paused = true
        UI.dirtyStatic = true
        UI.say(string.format("lineup: %d buildings (paused).", #ids))
        return
    end
    local ids = {}
    for id, def in pairs(D.Units) do
        local f = def.faction
        local want
        if which == "creeps" then want = f == "neutral" and def.level and not def.summon
        elseif which then want = f == which
        else want = f == "alliance" or f == "orcs" end
        if want and not def.ward and id ~= "critter" then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local A, B = D.Units[a], D.Units[b]
        if A.faction ~= B.faction then return A.faction < B.faction end
        if (A.hero and 1 or 0) ~= (B.hero and 1 or 0) then return not A.hero end
        local wa, wb = D.WC3SIZE[a], D.WC3SIZE[b]
        return (wa and wa[1] or 0) < (wb and wb[1] or 0)
    end)
    -- rows across the middle of the map, each unit given room for its own size; the game is paused
    -- so they stand still (models keep animating)
    local x0, y0 = (w.w or 64) / 2 - 14, (w.h or 64) / 2 - 10
    local x, y, rowH = x0, y0, 0
    UI.sel = {}
    for _, id in ipairs(ids) do
        local wc = D.WC3SIZE[id]
        local sz = max(1.8, (wc and wc[1] / 128 or 0.8) * UI.Draw.unitScale() * 1.15)
        if x + sz > x0 + 28 then x, y, rowH = x0, y + rowH + 1.2, 0 end
        local u = S.addUnit(w, UI.me, id, x + sz / 2, y + sz / 2)
        u.facing = math.pi / 2
        u.lineup = true
        x, rowH = x + sz, max(rowH, sz)
    end
    S.updateSupply(w)
    UI.lookAt(x0 + 14, y0 + 8)
    UI.paused = true
    UI.Hud.dirty = true
    UI.say(string.format("lineup: %d units (paused). Esc and Start new game to play again.", #ids))
end

-- ------------------------------------------------------------------ events from the simulation

local function handleEvents(w)
    local me = UI.me
    for _, ev in ipairs(w.events) do
        local t = ev.t
        if UI.Sound then UI.Sound.event(w, ev) end
        if t == "deposit" and ev.owner == me then
            UI.Draw.float(ev.x, ev.y - 1.2, "+" .. ev.amt, ev.res == "gold" and { 1, 0.85, 0.2 } or { 0.4, 0.9, 0.4 })
        elseif t == "error" and ev.owner == me then
            UI.Hud.error(ev.text)
        elseif t == "cast" then
            if UI.Fx and S.visibleTo(w, me, w.ents[ev.unit]) then UI.Fx.onCast(w, ev) end
        elseif t == "bounty" and ev.owner == me then
            UI.Draw.float(ev.x, ev.y - 1.2, "+" .. ev.amt, { 1, 0.85, 0.2 })
        elseif t == "item" and ev.owner == me then
            UI.Hud.dirty = true
        elseif t == "float" then
            UI.Draw.float(ev.x, ev.y, ev.text, ev.color)
        elseif t == "morphed" then
            -- an Ancient uprooted or rooted: it is a new entity, keep it selected
            for i, id in ipairs(UI.sel or {}) do if id == ev.from then UI.sel[i] = ev.to UI.Hud.dirty = true end end
            UI.Mini.dirtyTerrain = true
        elseif t == "unsummoned" then
            UI.Draw.effect({ x = ev.x, y = ev.y, model = 166808, size = 3, life = 1.4 })
            UI.Mini.dirtyTerrain = true
            if ev.owner == me then UI.Hud.dirty = true end
        elseif t == "nightfall" then
            UI.Hud.message("Night falls. Sight is shorter and the creeps are asleep.")
        elseif t == "daybreak" then
            UI.Hud.message("The sun rises.")
        elseif t == "vfx" then
            if UI.Fx then UI.Fx.onEvent(w, ev) end
        elseif t == "effect" then
            UI.Draw.effect(ev)
        elseif t == "levelup" then
            local u = w.ents[ev.unit]
            if u then
                UI.Draw.effect({ x = u.x, y = u.y, model = 166464, size = 2.5, life = 2.0, follow = u.id })
                if u.owner == me then UI.Hud.message(u.def.name .. " reached level " .. ev.level .. "!  A new skill point: open Hero Abilities (O).") UI.Hud.dirty = true end
            end
        elseif t == "destroyed" then
            UI.Draw.effect({ x = ev.x, y = ev.y, model = 165744, size = ev.size * 1.6, life = 1.6 })
            UI.Mini.dirtyTerrain = true
        elseif t == "heroDied" and ev.owner == me then
            local u = w.ents[ev.unit]
            UI.Hud.message("Your " .. (u and u.def.name or "hero") .. " has fallen. Revive them at your altar.", true)
            UI.Hud.dirty = true
        elseif t == "built" and ev.owner == me then
            local b = w.ents[ev.unit]
            if b then UI.Hud.message(b.def.name .. " complete.") end
            UI.Hud.dirty = true
        elseif t == "trained" and ev.owner == me then
            UI.Hud.dirty = true
        elseif t == "treeFell" then
            UI.dirtyStatic = true
            UI.Mini.dirtyTerrain = true
        elseif t == "mineEmpty" then
            UI.Hud.message("A gold mine has collapsed.")
            UI.Mini.dirtyTerrain = true
        elseif t == "hit" then
            local u = w.ents[ev.unit]
            if u and u.owner == me and w.time - (UI.lastAttackWarn or -99) > 12 then
                local x1, y1, x2, y2 = UI.viewRect()
                if u.x < x1 or u.x > x2 or u.y < y1 or u.y > y2 then
                    UI.lastAttackWarn = w.time
                    UI.Hud.message(u.kind == "building" and "Your base is under attack!" or "Your troops are under attack!", true)
                    UI.Mini.ping(u.x, u.y)
                    UI.attackAt = { u.x, u.y }
                    if UI.Sound then UI.Sound.underAttack(w) end
                end
            end
        elseif t == "died" then
            UI.Hud.dirty = true
        elseif t == "gameOver" then
            UI.gameOver = ev.winner
            UI.Hud.showEnd(ev.winner == me)
        end
    end
    w.events = {}
end
UI.handleEvents = handleEvents

-- ------------------------------------------------------------------ the loop

UI.speed = 1
function UI.onUpdate(elapsed)
    local w = UI.w
    if elapsed > 0.25 then elapsed = 0.25 end
    UI.Input.update(elapsed)
    if not w then return end
    local running = not UI.paused and UI.frame:IsShown() and not UI.menuPause and not w.over
    -- a multiplayer game is moved on by UI/Net.lua (in step with the other player, and never paused)
    if w.net then running = false end
    if w.net and not w.over then
        -- (the drawing still interpolates between ticks)
    elseif running then
        UI.acc = UI.acc + elapsed * UI.speed
        local steps = 0
        local cost = debugprofilestop()
        while UI.acc >= D.TICK and steps < 4 do
            AI.step(w, D.TICK)
            S.step(w, D.TICK)
            handleEvents(w)
            UI.acc = UI.acc - D.TICK
            steps = steps + 1
        end
        if steps > 0 then UI.simMs = (UI.simMs or 0) * 0.9 + (debugprofilestop() - cost) / steps * 0.1 end
        if UI.acc > D.TICK * 4 then UI.acc = 0 end
    elseif w.over then
        handleEvents(w)
    end
    local alpha = (running or (w.net and not w.over)) and min(1, UI.acc / D.TICK) or 1
    -- drop dead or unseen things from the selection
    if UI.sel and #UI.sel > 0 then
        local keep = {}
        for _, id in ipairs(UI.sel) do
            local e = w.ents[id]
            if S.alive(e) and not (e.owner ~= UI.me and not S.visibleTo(w, UI.me, e)) then keep[#keep + 1] = id end
        end
        if #keep ~= #UI.sel then UI.sel = keep UI.Hud.dirty = true end
    end
    UI.Draw.frame(alpha, elapsed)
    UI.Mini.update(elapsed)
    UI.Hud.update(elapsed)
end
