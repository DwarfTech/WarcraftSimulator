-- Skirmish: drawing the map. Ground and fog are flat textures; trees, units, buildings, the gold
-- mines and spell effects are real WoW models seen from above (UI.Figures).

local ADDON, ns = ...
local E = ns.Engine
local D, M, S = E.Data, E.Map, E.Sim
local UI = ns.UI
local Dr = {}
UI.Draw = Dr

local floor, min, max, abs, sqrt, pi, atan2 = math.floor, math.min, math.max, math.abs, math.sqrt, math.pi, math.atan2

local ANIM = { stand = 0, walk = 4, run = 5, death = 1, dead = 6, stun = 14, attack = 17, ready = 26, cast = 53, work = 17, spin = 52, roar = 55 }
local GRASS, GRASS2, FOREST_FLOOR, DIRT = 186818, 187126, 187130, 186820
-- ground textures for each WC3 tileset: base, second grass, dirt, rock (cliffs), tint for the base colour
local TILESETS = {
    L = { 186818, 187126, 186820, 186822, { 0.22, 0.32, 0.14 } },      -- Lordaeron Summer
    F = { 186818, 187126, 186820, 186822, { 0.30, 0.28, 0.14 } },      -- Lordaeron Fall
    V = { 186818, 187126, 186820, 186822, { 0.22, 0.32, 0.14 } },      -- Village
    Q = { 188954, 188956, 188950, 188952, { 0.26, 0.26, 0.15 } },      -- Village Fall (Tirisfal)
    Y = { 186818, 187126, 186820, 186822, { 0.22, 0.32, 0.14 } },      -- Cityscape
    X = { 186818, 187126, 186820, 186822, { 0.22, 0.32, 0.14 } },      -- Dalaran
    W = { 189053, 189051, 189029, 189049, { 0.75, 0.78, 0.82 } },      -- Lordaeron Winter
    N = { 189053, 189051, 189029, 189049, { 0.75, 0.78, 0.82 } },      -- Northrend
    I = { 189053, 189051, 189035, 189049, { 0.70, 0.75, 0.82 } },      -- Icecrown
    B = { 186904, 186906, 186899, 186919, { 0.38, 0.30, 0.18 } },      -- Barrens
    D = { 186904, 186899, 186902, 186915, { 0.32, 0.26, 0.18 } },      -- Underground
    A = { 186832, 186836, 186828, 186840, { 0.16, 0.26, 0.18 } },      -- Ashenvale
    C = { 188474, 188469, 188467, 186840, { 0.18, 0.24, 0.14 } },      -- Felwood
    Z = { 186832, 186836, 186848, 186844, { 0.18, 0.28, 0.20 } },      -- Sunken Ruins
}
function Dr.tileset(w) return TILESETS[w and w.tileset or "L"] or TILESETS.L end
local MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- tree density: "all" (a model on every tree), "dense" (edges plus every other tree inside a
-- forest), "light" (edges only), "flat" (no tree models)
Dr.treeMode = "dense"

local function T(x) return x * UI.TILE end

-- ------------------------------------------------------------------ pools

local function circlePool(parent, layer, sub)
    local p = { items = {}, n = 0 }
    function p:get()
        self.n = self.n + 1
        local t = self.items[self.n]
        if not t then
            t = parent:CreateTexture(nil, layer, nil, sub or 0)
            t:SetTexture(UI.WHITE)
            local ok, mask = pcall(parent.CreateMaskTexture, parent)
            if ok and mask then
                pcall(mask.SetTexture, mask, MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(t)
                pcall(t.AddMaskTexture, t, mask)
            end
            self.items[self.n] = t
        end
        t:Show()
        return t
    end
    function p:reset() self.n = 0 end
    function p:finish() for i = self.n + 1, #self.items do self.items[i]:Hide() end end
    return p
end

local function textPool(parent)
    local p = { items = {}, n = 0 }
    function p:get()
        self.n = self.n + 1
        local t = self.items[self.n]
        if not t then
            t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            t:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
            self.items[self.n] = t
        end
        t:Show()
        return t
    end
    function p:reset() self.n = 0 end
    function p:finish() for i = self.n + 1, #self.items do self.items[i]:Hide() end end
    return p
end

local function rect(t, x, y, w, h, r, g, b, a)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", UI.board, "TOPLEFT", x, -y)
    t:SetSize(max(1, w), max(1, h))
    t:SetVertexColor(r, g, b, a or 1)
end

local function setGround(t, file)
    if t.file ~= file then
        local ok = pcall(t.SetTexture, t, file, "REPEAT", "REPEAT")
        if not ok then t:SetTexture(file) end
        t.file = file
    end
end

-- ------------------------------------------------------------------ setup

function Dr.build()
    local g = UI.groundLayer
    Dr.base = g:CreateTexture(nil, "BACKGROUND", nil, -8)
    Dr.base:SetAllPoints(UI.board)
    Dr.base:SetTexture(UI.WHITE)
    Dr.base:SetVertexColor(0.22, 0.32, 0.14, 1)
    Dr.grass = g:CreateTexture(nil, "BACKGROUND", nil, -7)
    Dr.grass:SetAllPoints(UI.board)
    setGround(Dr.grass, GRASS)
    Dr.grass:SetTexCoord(0, D.MAP_W / 4, 0, D.MAP_H / 4)
    Dr.patches = UI.pool(g, "BACKGROUND", -6)
    Dr.blight = UI.pool(g, "BACKGROUND", -1)
    Dr.blightTint = UI.pool(g, "BACKGROUND", 0)
    Dr.floor = UI.pool(g, "BORDER", 0)

    Dr.plates = UI.pool(UI.decalLayer, "BACKGROUND", 0)
    Dr.circles = circlePool(UI.decalLayer, "ARTWORK", 0)
    Dr.rings = UI.pool(UI.decalLayer, "ARTWORK", 2)
    Dr.bars = UI.pool(UI.barLayer, "ARTWORK", 0)
    Dr.shots = UI.pool(UI.barLayer, "OVERLAY", 0)
    Dr.fog = UI.pool(UI.fogLayer, "ARTWORK", 0)
    -- night: a deep blue wash over the whole map (WC3 lighting goes blue and dark after 18:00)
    Dr.night = UI.fogLayer:CreateTexture(nil, "BACKGROUND", nil, -8)
    Dr.night:SetTexture(UI.WHITE)
    Dr.night:SetAllPoints(UI.board)
    Dr.night:SetVertexColor(0.02, 0.05, 0.2, 0)
    Dr.over = UI.pool(UI.overLayer, "ARTWORK", 0)
    Dr.overCircles = circlePool(UI.overLayer, "ARTWORK", 1)
    Dr.texts = textPool(UI.overLayer)
    Dr.floats = {}
    Dr.effects = {}
    Dr.markers = {}
    if UI.Fx then UI.Fx.build() end
end

-- Undead blight: a purple, dead-looking ground, one texture per run of blighted tiles in a row
function Dr.refreshBlight(w)
    Dr.blightVer = w.blightVer
    Dr.blight:reset()
    Dr.blightTint:reset()
    local bl = w.blight
    if bl then
        local W = w.w
        for y = 1, w.h do
            local start
            for x = 1, W + 1 do
                local on = x <= W and bl[(y - 1) * W + x]
                if on and not start then start = x
                elseif not on and start then
                    -- the tileset's dirt, stained a dark violet (WC3 blight)
                    local t = Dr.blight:get()
                    setGround(t, Dr.tileset(w)[3])
                    t:SetTexCoord((start - 1) / 4, x / 4 - 0.25, (y - 1) / 4, y / 4)
                    rect(t, T(start - 1), T(y - 1), T(x - start), T(1), 0.6, 0.5, 0.75, 1)
                    local v = Dr.blightTint:get()
                    v:SetTexture(UI.WHITE)
                    v.file = nil
                    v:SetTexCoord(0, 1, 0, 1)
                    rect(v, T(start - 1), T(y - 1), T(x - start), T(1), 0.3, 0.08, 0.45, 0.5)
                    start = nil
                end
            end
        end
    end
    Dr.blight:finish()
    Dr.blightTint:finish()
end

function Dr.reset()
    Dr.floats, Dr.effects, Dr.markers = {}, {}, {}
    Dr.blightVer = -1
    if UI.Fx then UI.Fx.reset() end
    Dr.lastCam = nil
    -- a few lighter and darker patches so the grass isn't one flat sheet
    local w = UI.w
    local ts = Dr.tileset(w)
    GRASS, GRASS2, DIRT = ts[1], ts[2], ts[3]
    setGround(Dr.grass, GRASS)
    Dr.base:SetVertexColor(ts[5][1], ts[5][2], ts[5][3], 1)
    Dr.patches:reset()
    local r = M.rng((w.seed or 1) * 31 + 7)
    for _ = 1, 70 do
        local x, y = r.int(0, w.w), r.int(0, w.h)
        local s = r.int(4, 9)
        local t = Dr.patches:get()
        setGround(t, r.float() < 0.6 and GRASS2 or DIRT)
        t:SetTexCoord(0, s / 4, 0, s / 4)
        rect(t, T(x - s / 2), T(y - s / 2), T(s), T(s), 1, 1, 1, 0.35)
    end
    -- dirt roads, then water (with a sandy shore), one texture per run of tiles in a row
    local W = w.w
    local function runs(test, fn)
        for y = 1, w.h do
            local start
            for x = 1, W + 1 do
                local on = x <= W and test((y - 1) * W + x)
                if on and not start then start = x
                elseif not on and start then fn(start, x - 1, y) start = nil end
            end
        end
    end
    if w.road then
        runs(function(i) return w.road[i] and not (w.water and w.water[i]) end, function(x1, x2, y)
            local t = Dr.patches:get()
            setGround(t, DIRT)
            t:SetTexCoord(0, (x2 - x1 + 1) / 4, 0, 0.25)
            rect(t, T(x1 - 1), T(y - 1), T(x2 - x1 + 1), T(1), 0.95, 0.85, 0.7, 0.55)
        end)
    end
    if w.water then
        runs(function(i) return w.water[i] end, function(x1, x2, y)
            local shore = Dr.patches:get()
            setGround(shore, DIRT)
            shore:SetTexCoord(0, (x2 - x1 + 2) / 4, 0, 0.3)
            rect(shore, T(x1 - 1.3), T(y - 1.15), T(x2 - x1 + 1.6), T(1.3), 0.9, 0.85, 0.6, 0.8)
        end)
        runs(function(i) return w.water[i] end, function(x1, x2, y)
            local t = Dr.patches:get()
            t:SetTexture(UI.WHITE)
            t.file = nil
            t:SetTexCoord(0, 1, 0, 1)
            rect(t, T(x1 - 1), T(y - 1), T(x2 - x1 + 1), T(1), 0.1, 0.27, 0.42, 1)
        end)
    end
    -- WC3 maps: high ground a shade lighter, low ground darker (the cliff levels)
    if w.layer then
        local base = w.layer[floor(w.h / 2) * W + floor(W / 2)] or 2
        for _, want in ipairs({ -2, -1, 1, 2, 3 }) do
            runs(function(i) return w.layer[i] and (w.layer[i] - base == want or (want == 3 and w.layer[i] - base > 3) or (want == -2 and w.layer[i] - base < -2)) end, function(x1, x2, y)
                local t = Dr.patches:get()
                t:SetTexture(UI.WHITE)
                t.file = nil
                t:SetTexCoord(0, 1, 0, 1)
                if want > 0 then rect(t, T(x1 - 1), T(y - 1), T(x2 - x1 + 1), T(1), 1, 0.95, 0.8, 0.07 * want)
                else rect(t, T(x1 - 1), T(y - 1), T(x2 - x1 + 1), T(1), 0, 0, 0, -0.12 * want) end
            end)
        end
    end
    -- cliffs and walls: bare rock
    if w.cliff then
        runs(function(i) return w.cliff[i] end, function(x1, x2, y)
            local t = Dr.patches:get()
            setGround(t, ts[4])
            t:SetTexCoord(0, (x2 - x1 + 1) / 4, 0, 0.25)
            rect(t, T(x1 - 1), T(y - 1), T(x2 - x1 + 1), T(1), 0.75, 0.72, 0.68, 1)
        end)
    end
    -- shallow water (troops can wade through it, nothing can be built there)
    if w.shallow then
        runs(function(i) return w.shallow[i] end, function(x1, x2, y)
            local t = Dr.patches:get()
            t:SetTexture(UI.WHITE)
            t.file = nil
            t:SetTexCoord(0, 1, 0, 1)
            rect(t, T(x1 - 1), T(y - 1), T(x2 - x1 + 1), T(1), 0.2, 0.45, 0.6, 0.55)
        end)
    end
    -- worn ground around the halls and mines
    for _, e in ipairs(w.list) do
        if e.kind == "mine" or (e.kind == "building" and e.def.hall) then
            local s = e.size + 4
            local t = Dr.patches:get()
            setGround(t, DIRT)
            t:SetTexCoord(0, s / 4, 0, s / 4)
            rect(t, T(e.x - s / 2), T(e.y - s / 2), T(s), T(s), 1, 0.95, 0.85, 0.55)
        end
    end
    Dr.patches:finish()
end

-- ------------------------------------------------------------------ the static layer: trees and fog

local function fogState(w, pl, i)
    if w.noFog then return 0 end
    if pl.visible[i] then return 0 end
    if pl.explored[i] then return 1 end
    return 2
end

function Dr.refreshStatic(w)
    local pl = w.players[UI.me]
    local x1, y1, x2, y2 = UI.viewRect(1)
    x1, y1 = max(1, floor(x1)), max(1, floor(y1))
    x2, y2 = min(w.w, floor(x2) + 1), min(w.h, floor(y2) + 1)
    local W = w.w
    local F = UI.Figures

    -- forest floor (one texture per run of trees in a row) and tree models
    Dr.floor:reset()
    F.begin("trees")
    local mode = Dr.treeMode
    for y = y1, y2 do
        local runStart
        for x = x1, x2 + 1 do
            local i = (y - 1) * W + x
            local tree = x <= x2 and w.block[i] == "tree"
            if tree and not runStart then runStart = x end
            if not tree and runStart then
                local t = Dr.floor:get()
                setGround(t, FOREST_FLOOR)
                t:SetTexCoord((runStart - 1) / 4, x / 4 - 0.25, (y - 1) / 4, y / 4)
                rect(t, T(runStart - 1), T(y - 1), T(x - runStart), T(1), 0.75, 0.85, 0.7, 1)
                runStart = nil
            end
            if tree and mode ~= "flat" then
                local edge = not M.isTree(w, x - 1, y) or not M.isTree(w, x + 1, y) or not M.isTree(w, x, y - 1) or not M.isTree(w, x, y + 1)
                local show = mode == "all" or edge or (mode == "dense" and (x + y) % 2 == 0)
                if show and fogState(w, pl, i) < 2 then
                    local kind = w.treeKind[i] or 1
                    local hash = (x * 7349 + y * 1931) % 1000
                    F.place("trees", i, UI.modelLayer, { file = D.TREES[kind] }, T(x - 0.5), T(y - 0.5),
                        T(edge and 2.7 or 3.0), 0.9, 10, hash / 1000 * 2 * pi, floor(y * 2), 0, 1)
                end
            end
        end
    end
    F.finish("trees")
    Dr.floor:finish()
    Dr.refreshFog(w)
end

function Dr.refreshFog(w)
    local pl = w.players[UI.me]
    local x1, y1, x2, y2 = UI.viewRect(1)
    x1, y1 = max(1, floor(x1)), max(1, floor(y1))
    x2, y2 = min(w.w, floor(x2) + 1), min(w.h, floor(y2) + 1)
    local W = w.w
    Dr.fog:reset()
    if not w.noFog then
        for y = y1, y2 do
            local runStart, runState
            for x = x1, x2 + 1 do
                local st = x <= x2 and fogState(w, pl, (y - 1) * W + x) or -1
                if st ~= runState then
                    if runState and runState > 0 then
                        local t = Dr.fog:get()
                        t:SetTexture(UI.WHITE)
                        rect(t, T(runStart - 1), T(y - 1), T(x - runStart), T(1), 0, 0, 0, runState == 2 and 1 or 0.5)
                    end
                    runStart, runState = x, st
                end
            end
        end
    end
    Dr.fog:finish()
end

-- ------------------------------------------------------------------ effects, floating text, markers

function Dr.effect(ev)
    Dr.effects[#Dr.effects + 1] = { x = ev.x, y = ev.y, model = ev.model, size = ev.size or 2, life = ev.life or 1.2,
        t = -(ev.delay or 0), follow = ev.follow, id = (Dr.fxId or 0) + 1 }
    Dr.fxId = (Dr.fxId or 0) + 1
end

function Dr.float(x, y, text, color)
    Dr.floats[#Dr.floats + 1] = { x = x, y = y, text = text, c = color, t = 0 }
end

function Dr.marker(x, y, r, g, b)
    Dr.markers[#Dr.markers + 1] = { x = x, y = y, c = { r, g, b }, t = 0 }
end

-- ------------------------------------------------------------------ per-frame drawing

-- colour and size of round missiles
local MISSILE = {
    shell = { 0.15, 0.13, 0.1, 7 }, boulder = { 0.35, 0.3, 0.25, 9 }, holy = { 1, 0.95, 0.6, 5 }, arcane = { 0.75, 0.45, 1, 5 },
    lightning = { 0.5, 0.75, 1, 5 }, frost = { 0.55, 0.85, 1, 6 }, shadow = { 0.55, 1, 0.45, 6 }, fire = { 1, 0.5, 0.1, 6 }, voodoo = { 0.4, 1, 0.4, 5 }, hammer = { 0.6, 0.85, 1, 6 },
}

-- models shown on a unit while a buff lasts: file, size (x the unit), alpha
local BUFF_FX = {
    lightningShield = { 166500, 1.2 }, ensnare = { 166616, 1.0 }, invuln = { 166342, 1.1, 0.8 }, slowSpell = { 165857, 0.7, 0.35 },
    voodoo = { 166342, 0.9, 0.5 }, frostArmor = { 166378, 0.9, 0.45 }, ams = { 166342, 1.1, 0.5 }, plague = { 166492, 0.7, 0.3 },
}
local BLIGHT = 188710     -- (unused: this Plaguelands texture draws pale yellow in Classic; blight is tinted dirt)
local CORPSE = 189894     -- a skeleton lying on the ground (Elwynn battleglade doodad)

local function barColor(f)
    if f > 0.6 then return 0.1, 0.9, 0.1 elseif f > 0.3 then return 0.95, 0.85, 0.1 end
    return 0.95, 0.15, 0.1
end

local function drawBar(cx, top, width, frac, r, g, b)
    local bg = Dr.bars:get()
    bg:SetTexture(UI.WHITE)
    rect(bg, cx - width / 2 - 1, top - 1, width + 2, 6, 0, 0, 0, 0.85)
    local fg = Dr.bars:get()
    fg:SetTexture(UI.WHITE)
    if not r then r, g, b = barColor(frac) end
    rect(fg, cx - width / 2, top, max(1, width * frac), 4, r, g, b, 1)
end

-- WC3 selection colours: green for yours, yellow for neutrals and creeps, red for enemies
local function selColor(owner, me, w)
    if owner == me then return 0.25, 1, 0.25 end
    if owner == 0 or owner == 3 then return 1, 0.85, 0.2 end
    return 1, 0.22, 0.18
end

-- a selection ring (a thin circle, flattened a little like WC3's on the ground)
local RING = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Ring"
local function ring(cx, cy, d, r, g, b, a)
    local t = Dr.rings:get()
    if t.file ~= RING then t:SetTexture(RING) t.file = RING end
    pcall(t.SetBlendMode, t, "BLEND")
    rect(t, cx - d / 2, cy - d * 0.42, d, d * 0.84, r, g, b, a)
end

-- the unit-size setting: how much bigger than WC3 scale units are drawn (top-down hides their height)
local UNIT_SCALE = { 2.2, 2.7, 3.2 }
function Dr.unitScale()
    return UNIT_SCALE[SkirmishDB.unitSize or 2] or 2.7
end
Dr.UNIT_SCALE = UNIT_SCALE

-- how far above its feet a unit's model reaches on screen (in tiles), given its drawn size
function Dr.bodyUp(target)
    if UI.Figures.pitch() < 1.5 then return target * 0.62 + 0.3 end
    return target * 0.5 + 0.4
end

-- the drawn size of a unit, in tiles
function Dr.unitTarget(def)
    local wc = D.WC3SIZE[def.id]
    return (wc and wc[1] / 128 or (def.vis or def.radius) * 2.3) * Dr.unitScale()
end

-- selection circle diameter in tiles, from WC3's selection scale
function Dr.selDiameter(def, wc)
    if wc then return wc[2] * 0.95 end
    return (def.vis or def.radius) * 2.9
end

local function teamColor(owner, w)
    if owner == 3 then return 0.95, 0.75, 0.2 end
    if owner == 0 then return 0.9, 0.8, 0.3 end
    local c = D.Factions[w.players[owner].faction].color
    return c[1], c[2], c[3]
end

-- The walk cycle is played at a speed that matches how fast the unit really covers ground, so feet
-- don't slide. (WoW's run animation is made for ~7 yards a second; units here cover about 2.)
-- Short flickers between walking and standing are smoothed over so the cycle never restarts.
local function unitAnim(u, elapsed)
    local a = u.anim
    if u.dead then return (u.deadT or 0) < 1.4 and ANIM.death or ANIM.dead end
    if a == "walk" then
        u.walkHold = 0.25
    elseif u.walkHold and u.walkHold > 0 and (a == "stand" or a == nil) then
        u.walkHold = u.walkHold - elapsed
        a = "walk"
    end
    if a == "walk" then return ANIM.walk, u.def.walkSpeed or max(0.6, min(1.5, u.def.speed * 0.95 / 2.3)) end
    -- building and chopping: keep swinging (the attack animation plays once, so restart it each second)
    if a == "work" then return ANIM.work, 1, floor((UI.w and UI.w.time or 0) / 1.0) end
    if a == "attack" then
        if u.animT then return (u.def.attackAnim and u.def.attackAnim[1]) or ANIM.attack end
        return u.def.readyAnim or ANIM.ready
    end
    return ANIM[a] or ANIM.stand
end

function Dr.frame(alpha, elapsed)
    local w = UI.w
    local F = UI.Figures
    local me = UI.me
    local TILE = UI.TILE

    -- refresh trees and fog when the camera moves, and fog a few times a second anyway
    local camKey = floor(UI.camX / TILE) .. ":" .. floor(UI.camY / TILE) .. ":" .. UI.zoom
    Dr.fogT = (Dr.fogT or 0) - elapsed
    if UI.dirtyStatic or camKey ~= Dr.lastCam then
        Dr.lastCam = camKey
        UI.dirtyStatic = false
        Dr.refreshStatic(w)
        Dr.fogT = 0.4
    elseif Dr.fogT <= 0 then
        Dr.fogT = 0.4
        Dr.refreshFog(w)
        Dr.fogRefreshes = (Dr.fogRefreshes or 0) + 1
        if Dr.fogRefreshes % 5 == 0 then Dr.refreshStatic(w) end   -- trees revealed by exploring
    end

    if (w.blightVer or 0) ~= Dr.blightVer then Dr.refreshBlight(w) end

    local selected = {}
    for _, id in ipairs(UI.sel or {}) do selected[id] = true end
    local hover = UI.Input.hoverId
    local alt = IsAltKeyDown()
    local x1, y1, x2, y2 = UI.viewRect(2.5)

    F.begin("units")
    Dr.plates:reset()
    Dr.circles:reset()
    Dr.rings:reset()
    Dr.bars:reset()
    Dr.shots:reset()
    Dr.over:reset()
    Dr.overCircles:reset()
    Dr.texts:reset()

    for _, e in ipairs(w.list) do
        if not e.removed and e.x > x1 and e.x < x2 and e.y > y1 and e.y < y2 and S.visibleTo(w, me, e) then
            if e.kind == "unit" then
                if not e.hidden then
                    local def = e.def
                    local x = e.px + (e.x - e.px) * alpha
                    local y = e.py + (e.y - e.py) * alpha
                    local r = def.vis or def.radius
                    -- turn smoothly towards the way the unit is facing (Warcraft III units turn, they don't snap)
                    local want = e.facing or 0
                    local cur = e.dispFacing or want
                    local diff = (want - cur + pi) % (2 * pi) - pi
                    local turn = 9 * elapsed
                    if abs(diff) <= turn then cur = want else cur = cur + (diff > 0 and turn or -turn) end
                    e.dispFacing = cur
                    local custom = SkirmishDB.models and SkirmishDB.models[def.id]
                    local disp = custom or (def.display and def.display[((e.variant or 1) - 1) % #def.display + 1])
                    if def.carryWood and e.carry and e.carry.res == "lumber" and not (SkirmishDB.models and SkirmishDB.models[def.id]) then disp = def.carryWood end
                    local anim, animSpeed, animCycle = unitAnim(e, elapsed)
                    local fade = def.alpha or 1
                    if e.dead then fade = fade * max(0, min(1, (6 - (e.deadT or 0)) / 2)) end
                    -- flyers are drawn up in the air, above everything on the ground, with a shadow below
                    local lift = def.air and not e.dead and not S.hasBuff(e, "ensnare") and 1.0 or 0
                    if lift > 0 then
                        local sh = Dr.circles:get()
                        local ss = T(r * 2.2)
                        rect(sh, T(x) - ss / 2, T(y) - ss * 0.3, ss, ss * 0.6, 0, 0, 0, 0.35)
                    end
                    -- drawn at its Warcraft III size (Engine/Sizes.lua), scaled up by the unit-size setting
                    -- because seen from straight above a unit shows only its shoulders, not its height
                    local wc = D.WC3SIZE[def.id]
                    local target = (wc and wc[1] / 128 or r * 2.3) * Dr.unitScale()
                    local size = T(target) * 1.5
                    local barUp = max(r + 0.9, Dr.bodyUp(target))   -- health bar just above the model
                    local fill = 1 / 1.5
                    local model = { display = disp, file = (not custom) and def.modelFile or nil, mount = def.mount and def.mount[((e.variant or 1) - 1) % #def.mount + 1] or nil, gear = (not (SkirmishDB.models and SkirmishDB.models[def.id]) and SkirmishDB.weapons ~= false) and def.gear or nil }
                    if model.file then model.display = nil end
                    model.fitHeight = wc and (wc[3] and "long" or "h") or true
                    model.capRatio = wc and wc[4] and 1.3 * wc[4] / wc[1] or nil
                    -- spell states: hexed units are frogs, Avatar makes the Mountain King huge,
                    -- Wind Walk and Banish fade the unit, your own illusions look ghostly
                    if S.hasBuff(e, "hex") then model = { display = 901 } end
                    if e.buffs and e.buffs.robo then model = { display = 5926, fitHeight = model.fitHeight } end
                    if S.hasBuff(e, "poly") then model = { display = 856 } end
                    if S.hasBuff(e, "avatar") then size = size * 1.4 end
                    if S.hasBuff(e, "bloodlust") then size = size * 1.15 end
                    if S.isInvisible(e) then fade = fade * 0.4 end
                    if S.hasBuff(e, "ethereal") then fade = fade * 0.5 end
                    if e.illusion and e.owner == me then fade = fade * 0.7 end
                    -- a padded frame (same model size) so heads, weapons and mounts aren't cut off at its edge
                    model.pad = 1.6
                    F.place("units", e.id, UI.modelLayer, model, T(x), T(y - lift), size * 1.6, fill, 1.3,
                        F.yawFor(cur), floor(y * 2) + 2 + (lift > 0 and 140 or 0), anim, fade, animSpeed, animCycle)
                    -- lasting spell visuals that follow the unit while the buff is on
                    if e.buffs and not e.dead then
                        for bid, m in pairs(BUFF_FX) do
                            if S.hasBuff(e, bid) then
                                F.place("units", e.id .. ":b:" .. bid, UI.modelLayer, { file = m[1] }, T(x), T(y - lift), size * m[2], 0.9, 2,
                                    0, floor(y * 2) + 3 + (lift > 0 and 140 or 0), 0, m[3] or 1)
                            end
                        end
                    end
                    y = y - lift
                    if not e.dead then
                        -- team colour under every unit; a brighter ring when selected
                        -- WC3's selection circle, sized by the unit's selection scale; a faint team-coloured
                        -- disc inside it so you can tell whose units are whose from above
                        local sel = Dr.selDiameter(def, wc)
                        local tr, tg, tb = teamColor(e.owner, w)
                        local c = Dr.circles:get()
                        local cs = T(sel * 0.8)
                        rect(c, T(x) - cs / 2, T(y) - cs * 0.4 + T(0.08), cs, cs * 0.8, tr, tg, tb, 0.3)
                        if selected[e.id] or hover == e.id then
                            local sr, sg, sb = selColor(e.owner, me, w)
                            ring(T(x), T(y) + T(0.08), T(sel), sr, sg, sb, selected[e.id] and 0.95 or 0.45)
                        end
                        if selected[e.id] or hover == e.id or alt or e.hp < e.maxhp then
                            local bw = T(max(0.9, r * 2.4))
                            drawBar(T(x), T(y - barUp), bw, e.hp / e.maxhp)
                            if def.hero then
                                local mb = Dr.bars:get()
                                mb:SetTexture(UI.WHITE)
                                rect(mb, T(x) - bw / 2, T(y - barUp) + 5, max(1, bw * e.mana / e.maxMana), 3, 0.25, 0.45, 1, 1)
                            end
                        end
                        if e.lineup then
                            local st = Dr.texts:get()
                            st:SetText(def.name)
                            st:SetTextColor(1, 0.9, 0.6)
                            st:ClearAllPoints()
                            st:SetPoint("CENTER", UI.board, "TOPLEFT", T(x), -T(y + (UI.Figures.pitch() < 1.5 and 0.55 or target * 0.45 + 0.3)))
                        end
                        if e.stun > 0 then
                            local st = Dr.texts:get()
                            st:SetText("*")
                            st:SetTextColor(1, 1, 0.3)
                            st:ClearAllPoints()
                            st:SetPoint("CENTER", UI.board, "TOPLEFT", T(x), -T(y - barUp - 0.35))
                        end
                        if e.sleeping then
                            local st = Dr.texts:get()
                            st:SetText("z Z")
                            st:SetTextColor(0.7, 0.8, 1)
                            st:ClearAllPoints()
                            st:SetPoint("CENTER", UI.board, "TOPLEFT", T(x) + 8, -T(y - barUp - 0.15 - 0.15 * math.sin(w.time * 2)))
                        end
                    end
                end
            elseif e.kind == "item" then
                -- an item lying on the ground: its icon on a glowing disc
                local glow = Dr.circles:get()
                local pulse = 0.35 + 0.15 * math.sin((w.time + e.id) * 3)
                rect(glow, T(e.x) - T(0.42), T(e.y) - T(0.34), T(0.84), T(0.68), 1, 0.85, 0.3, pulse)
                local ic = Dr.over:get()
                ic:SetTexture(e.def.icon)
                ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                rect(ic, T(e.x) - T(0.26), T(e.y) - T(0.5), T(0.52), T(0.52), 1, 1, 1, 0.95)
                if hover == e.id then
                    local st = Dr.texts:get()
                    st:SetText(e.def.name)
                    st:SetTextColor(1, 0.85, 0.3)
                    st:ClearAllPoints()
                    st:SetPoint("CENTER", UI.board, "TOPLEFT", T(e.x), -T(e.y - 0.9))
                end
            else
                -- buildings and gold mines
                local def = e.def
                local px, py, sz = T(e.tx - 1), T(e.ty - 1), T(e.size)
                -- the patch of bare, trodden earth every WC3 building stands on, with a thin edge in the
                -- owner's colour so you can tell whose it is from above
                local plate = Dr.plates:get()
                setGround(plate, Dr.tileset(w)[3])
                local u0, v0 = (e.tx - 1) / 4, (e.ty - 1) / 4
                plate:SetTexCoord(u0, u0 + e.size / 4, v0, v0 + e.size / 4)
                rect(plate, px, py, sz, sz, 0.8, 0.74, 0.66, 0.95)
                if e.kind == "building" and e.owner ~= 0 then
                    local tr, tg, tb = teamColor(e.owner, w)
                    for _, side in ipairs({ { 0, 0, sz, 2 }, { 0, sz - 2, sz, 2 }, { 0, 0, 2, sz }, { sz - 2, 0, 2, sz } }) do
                        local t = Dr.plates:get()
                        setGround(t, UI.WHITE)
                        t:SetTexCoord(0, 1, 0, 1)
                        rect(t, px + side[1], py + side[2], side[3], side[4], tr, tg, tb, 0.45)
                    end
                end
                local a = (e.kind == "building" and not e.built) and (0.35 + 0.5 * e.progress) or 1
                local bottom = e.ty - 1 + e.size
                local wcB = D.WC3SIZE[def.id] or (e.kind == "mine" and D.WC3SIZE.goldMine)
                local tilted = UI.Figures.pitch() < 1.5
                for k, m in ipairs(def.models) do
                    -- the frame is padded (bigger, camera pulled back to match) so roofs and corners that
                    -- stick out aren't clipped, while the building stays exactly the same size
                    -- the main part may be no taller than 1.5x the WC3 building (in tiles)
                    local capHU = (k == 1 and wcB and tilted) and (wcB[1] / 128 * 1.5) / m.size or nil
                    F.place("units", e.id .. ":" .. k, UI.modelLayer, { file = m.file, display = m.display, pad = 1.6, capHU = capHU },
                        T(e.x + (m.dx or 0)), T(e.y + (m.dy or 0)), T(m.size) * 1.6, m.fill, m.guess,
                        F.yawFor(m.yaw or (pi * 0.5)), floor(bottom * 2) - 3 + k, 0, a)
                end
                if e.lineup then
                    local st = Dr.texts:get()
                    st:SetText(def.name)
                    st:SetTextColor(1, 0.9, 0.6)
                    st:ClearAllPoints()
                    st:SetPoint("CENTER", UI.board, "TOPLEFT", T(e.x), -T(e.ty - 1 + e.size + 0.35))
                end
                if selected[e.id] or hover == e.id then
                    local sr, sg, sb = selColor(e.owner, me, w)
                    if e.kind == "mine" then sr, sg, sb = 1, 0.85, 0.2 end
                    -- buildings get a circle too in WC3, sized by their selection scale
                    local wc = D.WC3SIZE[def.id] or (e.kind == "mine" and D.WC3SIZE.goldMine)
                    local d = wc and wc[2] * 80 / 128 or e.size * 0.95
                    ring(T(e.x), T(e.y), T(max(d, e.size * 0.85)), sr, sg, sb, selected[e.id] and 0.95 or 0.45)
                end
                if e.kind == "building" and (selected[e.id] or hover == e.id or alt or e.hp < e.maxhp or not e.built) then
                    drawBar(T(e.x), py - 8, sz * 0.7, e.hp / e.maxhp)
                    if not e.built then
                        drawBar(T(e.x), py - 2, sz * 0.7, e.progress, 0.9, 0.75, 0.2)
                    elseif e.queue[1] then
                        local info = e.qinfo and e.qinfo[1]
                        local _, def1 = S.queueItem(e.queue[1])
                        drawBar(T(e.x), py - 2, sz * 0.7, min(1, e.trainT / ((info and info.time) or (def1 and def1.time) or 30)), 0.3, 0.6, 1)
                    end
                end
                -- rally point of a selected building
                if selected[e.id] and e.owner == me and e.rally then
                    local fl = Dr.over:get()
                    fl:SetTexture("Interface\\Icons\\INV_Banner_02")
                    fl:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    -- rallied onto a unit: the flag rides above it
                    local rt = e.rally.target and w.ents[e.rally.target]
                    local rx, ry = e.rally.x, e.rally.y
                    if rt and rt.kind == "unit" and S.alive(rt) then rx, ry = rt.x, rt.y - 0.9 end
                    rect(fl, T(rx) - 8, T(ry) - 20, 16, 16, 1, 1, 1, 0.95)
                end
            end
        end
    end

    -- corpses (Raise Dead, Cannibalize and the Meat Wagon use them): bones on the ground
    local pl = w.players[me]
    for _, c in ipairs(w.corpses or {}) do
        local age = w.time - c.t
        if c.cid and (age > 5 or c.made) and age < (D.CORPSE_LIFE or 90) and c.x > x1 and c.x < x2 and c.y > y1 and c.y < y2 then
            local tx, ty = M.tileOf(c.x, c.y)
            if w.noFog or pl.visible[(ty - 1) * w.w + tx] then
                F.place("units", "corpse" .. c.cid, UI.modelLayer, { file = CORPSE, pad = 1.6 }, T(c.x), T(c.y), T(1.0) * 1.6, 0.9, 2,
                    F.yawFor((c.cid * 1.7) % (2 * pi)), floor(c.y * 2) + 1, 0, min(1, (D.CORPSE_LIFE or 90) - age) * 0.9)
            end
        end
    end

    -- Burning Oil: patches of burning ground
    for _, f in ipairs(w.fires or {}) do
        if f.x > x1 and f.x < x2 and f.y > y1 and f.y < y2 then
            local c = Dr.circles:get()
            local s0 = T(f.r * 2) * (0.9 + 0.1 * math.sin(w.time * 9 + f.x))
            rect(c, T(f.x) - s0 / 2, T(f.y) - s0 * 0.4, s0, s0 * 0.8, 1, 0.45, 0.1, min(0.45, f.t * 0.2))
        end
    end

    -- missiles
    for _, m in ipairs(w.missiles) do
        if m.x > x1 and m.x < x2 and m.y > y1 and m.y < y2 then
            local tx, ty = M.tileOf(m.x, m.y)
            local vis = w.noFog or w.players[me].visible[(ty - 1) * w.w + tx]
            if vis then
                if m.kind == "stormBolt" then
                    F.place("units", "mis" .. tostring(m), UI.modelLayer, { file = m.model or 166497 }, T(m.x), T(m.y), T(1.6), 0.8, 1,
                        F.yawFor(m.angle or 0), 380, 0, 1)
                elseif MISSILE[m.kind] then
                    -- balls of artillery and magic
                    local ms = MISSILE[m.kind]
                    local t = Dr.shots:get()
                    t:SetTexture(UI.WHITE)
                    t:ClearAllPoints()
                    t:SetPoint("CENTER", UI.board, "TOPLEFT", T(m.x), -T(m.y - 0.6))
                    t:SetSize(ms[4], ms[4])
                    t:SetVertexColor(ms[1], ms[2], ms[3], 1)
                    pcall(t.SetRotation, t, 0)
                else
                    local t = Dr.shots:get()
                    t:SetTexture(UI.WHITE)
                    local len = m.kind == "bullet" and 14 or 12
                    local thick = m.kind == "bullet" and 2 or 2
                    t:ClearAllPoints()
                    t:SetPoint("CENTER", UI.board, "TOPLEFT", T(m.x), -T(m.y - 0.5))
                    t:SetSize(len, thick)
                    if m.kind == "bullet" then t:SetVertexColor(1, 0.95, 0.5, 1) else t:SetVertexColor(0.45, 0.32, 0.18, 1) end
                    pcall(t.SetRotation, t, -(m.angle or 0))
                end
            end
        end
    end

    -- spell effects
    local keep = {}
    for _, fx in ipairs(Dr.effects) do
        fx.t = fx.t + elapsed
        if fx.t < fx.life then
            keep[#keep + 1] = fx
            if fx.t >= 0 then
                local x, y = fx.x, fx.y
                if fx.follow then
                    local u = w.ents[fx.follow]
                    if u then x, y = u.x, u.y end
                end
                if x > x1 and x < x2 and y > y1 and y < y2 then
                    F.place("units", "fx" .. fx.id, UI.modelLayer, { file = fx.model }, T(x), T(y), T(fx.size), 0.9, 2,
                        0, 390, 0, min(1, (fx.life - fx.t) * 2))
                end
            end
        end
    end
    Dr.effects = keep
    if UI.Fx then UI.Fx.step(elapsed) end
    if Dr.night and S.darkness then Dr.night:SetVertexColor(0.02, 0.05, 0.2, 0.38 * S.darkness(w)) end
    F.finish("units")

    -- move / attack markers
    keep = {}
    for _, mk in ipairs(Dr.markers) do
        mk.t = mk.t + elapsed
        if mk.t < 0.5 then
            keep[#keep + 1] = mk
            local c = Dr.overCircles:get()
            local s = T(0.9) * (1 - mk.t)
            rect(c, T(mk.x) - s / 2, T(mk.y) - s / 2 * 0.8, s, s * 0.8, mk.c[1], mk.c[2], mk.c[3], 0.8 * (1 - mk.t * 2))
        end
    end
    Dr.markers = keep

    -- floating "+10"
    keep = {}
    for _, fl in ipairs(Dr.floats) do
        fl.t = fl.t + elapsed
        if fl.t < 1.4 then
            keep[#keep + 1] = fl
            local t = Dr.texts:get()
            t:SetText(fl.text)
            t:SetTextColor(fl.c[1], fl.c[2], fl.c[3], min(1, (1.4 - fl.t) * 2))
            t:ClearAllPoints()
            t:SetPoint("CENTER", UI.board, "TOPLEFT", T(fl.x), -T(fl.y - fl.t * 0.8))
        end
    end
    Dr.floats = keep

    UI.Input.drawOverlay(Dr.over, rect)

    Dr.plates:finish()
    Dr.circles:finish()
    Dr.rings:finish()
    Dr.bars:finish()
    Dr.shots:finish()
    Dr.over:finish()
    Dr.overCircles:finish()
    Dr.texts:finish()
    F.tick()
end

Dr.rect = rect
