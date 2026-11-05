-- Skirmish UI: procedural spell visuals drawn with textures (on top of the WoW spell models).
-- Rings that sweep outwards, glowing discs on the ground, light pillars, jagged lightning,
-- falling ice shards, travelling shockwaves, bursts of sparks, and halos on units while a
-- spell lasts (Divine Shield, Avatar, Bladestorm, auras, channels). Everything is in map tiles.

local ADDON, ns = ...
local E = ns.Engine
local D, S = E.Data, E.Sim
local UI = ns.UI
local Fx = {}
UI.Fx = Fx

local floor, min, max, abs, sqrt, sin, cos, atan2, pi = math.floor, math.min, math.max, math.abs, math.sqrt, math.sin, math.cos, math.atan2, math.pi
local MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local COLORS = {
    holy = { 1, 0.88, 0.45 }, frost = { 0.55, 0.85, 1 }, fire = { 1, 0.5, 0.12 }, nature = { 0.45, 1, 0.4 }, lightning = { 0.7, 0.85, 1 },
    shadow = { 0.7, 0.35, 1 }, arcane = { 0.8, 0.55, 1 }, earth = { 0.75, 0.6, 0.4 }, blood = { 1, 0.2, 0.15 }, white = { 1, 1, 1 },
    gold = { 1, 0.8, 0.2 }, mana = { 0.35, 0.55, 1 },
}
Fx.COLORS = COLORS

local list = {}

local function T(x) return x * UI.TILE end

local function pool(parent, layer, sub, masked)
    local p = { items = {}, n = 0 }
    function p:get()
        self.n = self.n + 1
        local t = self.items[self.n]
        if not t then
            t = parent:CreateTexture(nil, layer, nil, sub or 0)
            t:SetTexture(UI.WHITE)
            if masked then
                local ok, mask = pcall(parent.CreateMaskTexture, parent)
                if ok and mask then
                    pcall(mask.SetTexture, mask, MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    mask:SetAllPoints(t)
                    pcall(t.AddMaskTexture, t, mask)
                end
            end
            pcall(t.SetBlendMode, t, "ADD")
            self.items[self.n] = t
        end
        t:Show()
        return t
    end
    function p:reset() self.n = 0 end
    function p:finish() for i = self.n + 1, #self.items do self.items[i]:Hide() end end
    return p
end

function Fx.build()
    Fx.groundDiscs = pool(UI.decalLayer, "ARTWORK", 3, true)
    Fx.groundDots = pool(UI.decalLayer, "ARTWORK", 4, false)
    Fx.airDiscs = pool(UI.barLayer, "ARTWORK", -2, true)
    Fx.airRects = pool(UI.barLayer, "ARTWORK", -1, false)
end

function Fx.reset() list = {} end

local function place(t, cx, cy, w, h, c, a, rot)
    t:ClearAllPoints()
    t:SetPoint("CENTER", UI.board, "TOPLEFT", cx, -cy)
    t:SetSize(max(1, w), max(1, h))
    t:SetVertexColor(c[1], c[2], c[3], max(0, min(1, a)))
    pcall(t.SetRotation, t, rot or 0)
end

-- ------------------------------------------------------------------ primitives (in tiles)

local function disc(p, x, y, r, c, a) place(p:get(), T(x), T(y), T(r * 2), T(r * 2) * 0.8, c, a) end
local function dot(p, x, y, s, c, a) place(p:get(), T(x), T(y), s, s, c, a) end
local function ring(p, x, y, r, c, a, n, s, phase)
    n = n or max(18, floor(r * 18))
    for i = 1, n do
        local ang = (i / n) * 2 * pi + (phase or 0)
        dot(p, x + cos(ang) * r, y + sin(ang) * r * 0.8, s or 3, c, a)
    end
end
local function line(p, x1, y1, x2, y2, width, c, a)
    local dx, dy = T(x2 - x1), T(y2 - y1)
    local len = sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    place(p:get(), (T(x1) + T(x2)) / 2, (T(y1) + T(y2)) / 2, len, width, c, a, -atan2(dy, dx))
end
local function jagged(p, x1, y1, x2, y2, width, c, a, seed)
    local segs = 6
    local px, py = x1, y1
    local nx, ny = -(y2 - y1), x2 - x1
    local l = sqrt(nx * nx + ny * ny)
    if l < 0.01 then return end
    nx, ny = nx / l, ny / l
    for i = 1, segs do
        local f = i / segs
        local off = i < segs and (sin(seed * 12.9898 + i * 78.233) * 43758.5453 % 1 - 0.5) * 0.6 or 0
        local qx, qy = x1 + (x2 - x1) * f + nx * off, y1 + (y2 - y1) * f + ny * off
        line(p, px, py, qx, qy, width, c, a)
        line(p, px, py, qx, qy, width * 3, c, a * 0.25)
        px, py = qx, qy
    end
end

-- ------------------------------------------------------------------ effects

-- add an effect: kind and its fields (see the draw functions below)
function Fx.add(e)
    e.t = -(e.delay or 0)
    e.life = e.life or 1
    e.seed = e.seed or math.random() * 100
    list[#list + 1] = e
end

local function pos(w, e)
    if e.follow then
        local u = w.ents[e.follow]
        if u and not u.removed then e.x, e.y = u.x, u.y end
    end
    return e.x, e.y
end

local DRAW = {}

-- a ring sweeping out from r0 to r1, with a faint disc behind it
function DRAW.nova(w, e, f)
    local x, y = pos(w, e)
    local r = e.r0 + (e.r1 - e.r0) * (1 - (1 - f) ^ 2)
    local a = (1 - f)
    disc(Fx.groundDiscs, x, y, r, e.c, 0.28 * a)
    ring(Fx.groundDots, x, y, r, e.c, a, nil, 4)
    ring(Fx.groundDots, x, y, r * 0.85, e.c, a * 0.5, nil, 3, 0.2)
end

-- a glowing disc on the ground that pulses (Flame Strike's burning ground, Earthquake, auras)
function DRAW.pool(w, e, f)
    local x, y = pos(w, e)
    local pulse = 0.75 + 0.25 * sin((e.t + e.seed) * (e.speed or 6))
    local fade = min(1, (e.life - e.t) * 2, e.t * 4 + 0.2)
    disc(Fx.groundDiscs, x, y, e.r, e.c, (e.a or 0.35) * pulse * fade)
    if e.edge ~= false then ring(Fx.groundDots, x, y, e.r, e.c, 0.8 * fade, nil, 3, e.t * 0.6) end
    if e.embers then
        for i = 1, e.embers do
            local s = e.seed + i * 7.31
            local ang, rad = (s * 3.7) % (2 * pi), ((s * 1.3) % 1) * e.r
            local rise = ((e.t * 1.5 + s) % 1)
            dot(Fx.airRects, x + cos(ang) * rad, y + sin(ang) * rad * 0.8 - rise * 0.8, 3, e.c, (1 - rise) * fade)
        end
    end
end

-- a pillar of light standing on a spot (Holy Light, Flame Strike, Resurrection)
function DRAW.column(w, e, f)
    local x, y = pos(w, e)
    local a = f < 0.2 and f / 0.2 or (1 - f) / 0.8
    local wd, h = T(e.r or 0.5), T(e.h or 3)
    local t = Fx.airRects:get()
    place(t, T(x), T(y) - h / 2, wd, h, e.c, a * 0.7)
    pcall(t.SetGradient, t, "VERTICAL", CreateColor and CreateColor(e.c[1], e.c[2], e.c[3], a * 0.9) or nil,
        CreateColor and CreateColor(e.c[1], e.c[2], e.c[3], 0) or nil)
    local core = Fx.airRects:get()
    place(core, T(x), T(y) - h / 2, wd * 0.35, h, COLORS.white, a * 0.6)
    pcall(core.SetGradient, core, "VERTICAL", CreateColor and CreateColor(1, 1, 1, a * 0.8) or nil, CreateColor and CreateColor(1, 1, 1, 0) or nil)
    disc(Fx.groundDiscs, x, y, (e.r or 0.5) * 1.3, e.c, a * 0.5)
end

-- sparks thrown outwards from a point
function DRAW.burst(w, e, f)
    local x, y = pos(w, e)
    local n = e.n or 14
    for i = 1, n do
        local s = e.seed + i * 3.17
        local ang = (s * 2.39) % (2 * pi)
        local sp = 0.6 + (s * 0.71) % 0.8
        local d = (e.r or 1.2) * sp * (1 - (1 - f) ^ 2)
        dot(Fx.airRects, x + cos(ang) * d, y + sin(ang) * d * 0.8 - (e.lift or 0.4) * (1 - f), e.s or 4, e.c, (1 - f) * (e.a or 1))
    end
end

-- a beam between two points or units; jagged = lightning
function DRAW.beam(w, e, f)
    local a, b = w.ents[e.from or 0], w.ents[e.to or 0]
    local x1, y1 = a and a.x or e.x1, a and a.y or e.y1
    local x2, y2 = b and b.x or e.x2, b and b.y or e.y2
    if not x1 or not x2 then return end
    local alpha = (1 - f) * (e.a or 1)
    if e.jagged then
        local seed = e.seed + floor(e.t * 20)
        jagged(Fx.airRects, x1, y1 - 0.6, x2, y2 - 0.6, 2, e.c, alpha, seed)
    else
        line(Fx.airRects, x1, y1 - 0.6, x2, y2 - 0.6, 3, e.c, alpha)
        line(Fx.airRects, x1, y1 - 0.6, x2, y2 - 0.6, 8, e.c, alpha * 0.25)
    end
end

-- ice shards falling into an area (Blizzard)
function DRAW.shards(w, e, f)
    local n = e.n or 12
    for i = 1, n do
        local s = e.seed + i * 5.13
        local ang, rad = (s * 2.1) % (2 * pi), sqrt((s * 0.37) % 1) * e.r
        local tx, ty = e.x + cos(ang) * rad, e.y + sin(ang) * rad * 0.8
        local start = ((s * 0.53) % 1) * 0.5
        local g = (f - start) / 0.35
        if g > 0 and g < 1 then
            local fall = (1 - g) * 2.2
            line(Fx.airRects, tx - 0.25 * (1 - g), ty - fall - 0.6, tx, ty - fall, 3, e.c, 0.9)
        elseif g >= 1 and g < 1.8 then
            local k = (g - 1) / 0.8
            ring(Fx.groundDots, tx, ty, 0.15 + k * 0.35, e.c, 1 - k, 8, 3)
        end
    end
    disc(Fx.groundDiscs, e.x, e.y, e.r, e.c, 0.18 * (1 - f))
end

-- a wave rolling along the ground in a straight line (Shockwave)
function DRAW.wave(w, e, f)
    local d = e.len * f
    local x, y = e.x + e.dx * d, e.y + e.dy * d
    disc(Fx.groundDiscs, x, y, e.width / 2, e.c, 0.45 * (1 - f * 0.5))
    for k = 1, 4 do
        local back = d - k * 0.5
        if back > 0 then disc(Fx.groundDiscs, e.x + e.dx * back, e.y + e.dy * back, e.width / 2 * (1 - k * 0.15), e.c, 0.15 * (1 - f)) end
    end
    DRAW.burst(w, { x = x, y = y, seed = e.seed + floor(f * 10), c = e.c, n = 6, r = e.width / 2, s = 4 }, (f * 10) % 1)
end

function Fx.step(elapsed)
    local w = UI.w
    Fx.groundDiscs:reset() Fx.groundDots:reset() Fx.airDiscs:reset() Fx.airRects:reset()
    if w then
        local keep = {}
        for _, e in ipairs(list) do
            e.t = e.t + elapsed
            if e.t < e.life then
                keep[#keep + 1] = e
                if e.t >= 0 then
                    local x, y = e.x or 0, e.y or 0
                    if not e.follow or (w.ents[e.follow] and not w.ents[e.follow].removed) then
                        DRAW[e.kind](w, e, e.t / e.life)
                    end
                end
            end
        end
        list = keep
        Fx.halos(w, elapsed)
    end
    Fx.groundDiscs:finish() Fx.groundDots:finish() Fx.airDiscs:finish() Fx.airRects:finish()
end

-- ------------------------------------------------------------------ halos on units while a spell lasts

local HALO = {
    invuln = { COLORS.gold, 0.75, "shield" }, voodoo = { COLORS.shadow, 0.7, "shield" }, avatar = { COLORS.holy, 0.9, "glow" },
    ethereal = { COLORS.nature, 0.7, "glow" }, bladestorm = { COLORS.white, 1.3, "spin" }, lightningShield = { COLORS.lightning, 0.75, "spin" },
    innerFire = { COLORS.holy, 0.55, "glow" }, bloodlust = { COLORS.blood, 0.55, "glow" }, link = { COLORS.shadow, 0.5, "dots" },
    berserk = { COLORS.blood, 0.6, "glow" }, slowSpell = { { 0.45, 0.35, 0.6 }, 0.45, "faint" }, purged = { COLORS.nature, 0.5, "dots" },
}
local AURA = { devotionAura = COLORS.holy, brillianceAura = COLORS.mana, enduranceAura = COLORS.blood }

function Fx.halos(w, elapsed)
    local me = UI.me
    local now = w.time
    local x1, y1 = UI.camX / UI.TILE - 2, UI.camY / UI.TILE - 2
    local x2, y2 = x1 + UI.VIEW_W / UI.TILE / UI.zoom + 4, y1 + UI.VIEW_H / UI.TILE / UI.zoom + 4
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and not u.dead and not u.removed and not u.hidden and u.x > x1 and u.x < x2 and u.y > y1 and u.y < y2 and S.visibleTo(w, me, u) then
            local x, y = u.x, u.y
            if u.buffs then
                for id, b in pairs(u.buffs) do
                    local h = HALO[id]
                    if h and b.t > 0 then
                        local r = h[2] * max(0.8, (u.def.vis or 0.4) * 2)
                        if h[3] == "shield" then
                            local p = 0.8 + 0.2 * sin(now * 5)
                            disc(Fx.airDiscs, x, y - 0.5, r, h[1], 0.22 * p)
                            ring(Fx.airRects, x, y - 0.5, r, h[1], 0.7 * p, 22, 3, now)
                        elseif h[3] == "glow" then
                            disc(Fx.groundDiscs, x, y, r, h[1], 0.3 + 0.1 * sin(now * 4))
                        elseif h[3] == "spin" then
                            for k = 0, 2 do
                                local base = now * (id == "bladestorm" and 9 or 4) + k * 2 * pi / 3
                                for j = 0, 5 do
                                    local ang = base + j * 0.12
                                    dot(Fx.airRects, x + cos(ang) * r, y - 0.4 + sin(ang) * r * 0.8, 4 - j * 0.5, h[1], 1 - j * 0.15)
                                end
                            end
                        elseif h[3] == "faint" then
                            ring(Fx.groundDots, x, y, r, h[1], 0.25, 8, 2, now)
                        else
                            ring(Fx.groundDots, x, y, r, h[1], 0.6, 10, 3, now * 2)
                        end
                    end
                end
            end
            -- heroes' auras: a slow ring of light under the hero
            if u.def.hero and u.skills then
                for abId, lv in pairs(u.skills) do
                    local c = AURA[abId]
                    if c and lv > 0 then ring(Fx.groundDots, x, y, 0.9, c, 0.5, 14, 3, now * 0.8) end
                end
            end
            -- channelled spells: the caster glows while channelling
            if u.channel or u.teleport then
                local c = u.teleport and COLORS.arcane or (u.channel.ability == "blizzard" and COLORS.frost) or (u.channel.ability == "siphonMana" and COLORS.mana) or COLORS.shadow
                ring(Fx.groundDots, x, y, 0.7 + 0.1 * sin(now * 8), c, 0.9, 16, 3, -now * 3)
                if u.teleport then disc(Fx.groundDiscs, x, y, D.Abilities.massTeleport.radius, COLORS.arcane, 0.15 + 0.1 * sin(now * 6)) end
                if u.channel and u.channel.ability == "siphonMana" then
                    local t = w.ents[u.channel.target or 0]
                    if t then DRAW.beam(w, { from = t.id, to = u.id, c = COLORS.mana, seed = 1, t = now, a = 0.8 }, 0.2) end
                end
                if u.channel and u.channel.ability == "bigBadVoodoo" then
                    disc(Fx.groundDiscs, x, y, u.channel.r, COLORS.shadow, 0.12)
                    ring(Fx.groundDots, x, y, u.channel.r, COLORS.shadow, 0.7, nil, 3, now)
                end
            end
        end
    end
    -- lasting ground effects from the engine
    for _, a in ipairs(w.areas or {}) do
        if a.kind == "flame" then
            if a.delay then
                local k = 1 - a.delay / 1.33
                disc(Fx.groundDiscs, a.x, a.y, a.r * k, COLORS.fire, 0.25)
                ring(Fx.groundDots, a.x, a.y, a.r, COLORS.fire, 0.8, nil, 3, now)
            else
                DRAW.pool(w, { x = a.x, y = a.y, r = a.r, c = COLORS.fire, t = now, life = 99, seed = a.x, embers = 10, speed = 9, a = 0.45 }, 0.5)
            end
        elseif a.kind == "cloud" then
            DRAW.pool(w, { x = a.x, y = a.y, r = a.r, c = { 0.75, 0.8, 0.9 }, t = now, life = 99, seed = a.x, embers = 6, speed = 2, a = 0.35, edge = false }, 0.5)
        elseif a.kind == "quake" then
            DRAW.pool(w, { x = a.x + sin(now * 31) * 0.05, y = a.y, r = a.r, c = COLORS.earth, t = now, life = 99, seed = a.y, embers = 12, speed = 14, a = 0.35 }, 0.5)
        end
    end
end

-- ------------------------------------------------------------------ what each spell looks like

local C = COLORS
local SPELL = {}
Fx.SPELL = SPELL

local function unitOf(w, id) return w.ents[id or 0] end

SPELL.holyLight = function(w, u, t) Fx.add{ kind = "column", follow = t, c = C.holy, r = 0.6, h = 3.5, life = 1.0 } Fx.add{ kind = "burst", follow = t, c = C.holy, n = 16, r = 1, life = 0.8 } end
SPELL.divineShield = function(w, u) Fx.add{ kind = "nova", follow = u.id, c = C.gold, r0 = 0.2, r1 = 1.4, life = 0.6 } end
SPELL.resurrection = function(w, u) Fx.add{ kind = "nova", x = u.x, y = u.y, c = C.holy, r0 = 0.5, r1 = D.Abilities.resurrection.radius, life = 1.2 } end
SPELL.waterElemental = function(w, u) Fx.add{ kind = "nova", x = u.x + cos(u.facing) * 1.2, y = u.y + sin(u.facing) * 1.2, c = C.frost, r0 = 0.1, r1 = 1.2, life = 0.7 } end
SPELL.massTeleport = function(w, u) Fx.add{ kind = "nova", follow = u.id, c = C.arcane, r0 = 0.2, r1 = 2, life = 0.8 } end
SPELL.thunderClap = function(w, u, t, ab, lv) local r = ab.radiusL[lv] Fx.add{ kind = "nova", x = u.x, y = u.y, c = C.lightning, r0 = 0.3, r1 = r, life = 0.6 } Fx.add{ kind = "burst", x = u.x, y = u.y, c = C.white, n = 20, r = r, life = 0.6, lift = 0.2 } end
SPELL.warStomp = function(w, u, t, ab, lv) local r = ab.radiusL[lv] Fx.add{ kind = "nova", x = u.x, y = u.y, c = C.earth, r0 = 0.3, r1 = r, life = 0.6 } Fx.add{ kind = "burst", x = u.x, y = u.y, c = C.earth, n = 24, r = r, life = 0.7, lift = 0.3 } end
SPELL.avatar = function(w, u) Fx.add{ kind = "column", follow = u.id, c = C.holy, r = 1, h = 4, life = 1.2 } Fx.add{ kind = "nova", follow = u.id, c = C.gold, r0 = 0.3, r1 = 2, life = 0.8 } end
SPELL.flameStrike = function(w, u, t, ab, lv, o) Fx.add{ kind = "column", x = o.x, y = o.y, c = C.fire, r = ab.radius * 1.4, h = 4.5, life = 1.3, delay = ab.delay - 0.1 } end
SPELL.banish = function(w, u, t) Fx.add{ kind = "burst", follow = t, c = C.nature, n = 12, r = 0.8, life = 0.7 } end
SPELL.phoenix = function(w, u) Fx.add{ kind = "nova", x = u.x, y = u.y - 1, c = C.fire, r0 = 0.2, r1 = 1.6, life = 0.8 } end
SPELL.windWalk = function(w, u) Fx.add{ kind = "burst", x = u.x, y = u.y, c = C.white, n = 14, r = 0.9, life = 0.6 } end
SPELL.mirrorImage = function(w, u) Fx.add{ kind = "nova", x = u.x, y = u.y, c = C.arcane, r0 = 0.2, r1 = 1.6, life = 0.6 } Fx.add{ kind = "burst", x = u.x, y = u.y, c = C.arcane, n = 18, r = 1.4, life = 0.6 } end
SPELL.bladestorm = function(w, u) Fx.add{ kind = "nova", follow = u.id, c = C.white, r0 = 0.3, r1 = 1.6, life = 0.5 } end
SPELL.farSight = function(w, u, t, ab, lv, o) Fx.add{ kind = "nova", x = o.x, y = o.y, c = C.lightning, r0 = 0.3, r1 = ab.radiusL[lv], life = 1.4 } end
SPELL.feralSpirit = function(w, u) Fx.add{ kind = "nova", x = u.x, y = u.y, c = C.lightning, r0 = 0.2, r1 = 1.5, life = 0.7 } end
SPELL.earthquake = function(w, u, t, ab, lv, o) Fx.add{ kind = "nova", x = o.x, y = o.y, c = C.earth, r0 = 0.2, r1 = ab.radius, life = 0.8 } end
SPELL.shockwave = function(w, u, t, ab, lv, o)
    local dx, dy = (o.x or u.x) - u.x, (o.y or u.y) - u.y
    local d = sqrt(dx * dx + dy * dy)
    if d < 0.1 then dx, dy, d = cos(u.facing), sin(u.facing), 1 end
    Fx.add{ kind = "wave", x = u.x, y = u.y, dx = dx / d, dy = dy / d, len = ab.length, width = ab.width * 1.2, c = C.earth, life = 0.8 }
end
SPELL.hex = function(w, u, t) Fx.add{ kind = "burst", follow = t, c = C.nature, n = 16, r = 1, life = 0.6 } end
SPELL.serpentWard = function(w, u, t, ab, lv, o) Fx.add{ kind = "nova", x = o.x, y = o.y, c = C.nature, r0 = 0.1, r1 = 0.9, life = 0.5 } end
SPELL.bigBadVoodoo = function(w, u, t, ab) Fx.add{ kind = "nova", x = u.x, y = u.y, c = C.shadow, r0 = 0.3, r1 = ab.radius, life = 1 } end
SPELL.stormBolt = function(w, u, t) end   -- the hammer is a missile; its impact is below
-- unit spells
SPELL.heal = function(w, u, t) Fx.add{ kind = "column", follow = t, c = C.holy, r = 0.35, h = 2, life = 0.6 } end
SPELL.innerFire = function(w, u, t) Fx.add{ kind = "burst", follow = t, c = C.holy, n = 10, r = 0.7, life = 0.6 } end
SPELL.dispelMagic = function(w, u, t, ab, lv, o) Fx.add{ kind = "nova", x = o.x, y = o.y, c = C.white, r0 = 0.1, r1 = ab.radius, life = 0.6 } end
SPELL.disenchant = SPELL.dispelMagic
-- the Sorceress casts a lot (Slow is on autocast), so her spells are kept soft
SPELL.slow = function(w, u, t) Fx.add{ kind = "beam", from = u.id, to = t, c = { 0.55, 0.45, 0.75 }, life = 0.3, a = 0.35 } end
SPELL.polymorph = function(w, u, t) Fx.add{ kind = "burst", follow = t, c = { 0.7, 0.55, 0.85 }, n = 12, r = 0.9, life = 0.6, a = 0.5 } end
SPELL.invisibility = function(w, u, t) Fx.add{ kind = "burst", follow = t, c = { 0.75, 0.75, 0.8 }, n = 10, r = 0.7, life = 0.6, a = 0.45 } end
SPELL.purge = function(w, u, t) Fx.add{ kind = "beam", from = u.id, to = t, c = C.nature, jagged = true, life = 0.35 } Fx.add{ kind = "burst", follow = t, c = C.nature, n = 10, r = 0.8, life = 0.5 } end
SPELL.lightningShield = function(w, u, t) Fx.add{ kind = "beam", from = u.id, to = t, c = C.lightning, jagged = true, life = 0.3 } end
SPELL.bloodlust = function(w, u, t) Fx.add{ kind = "burst", follow = t, c = C.blood, n = 12, r = 0.8, life = 0.6 } end
SPELL.spiritLink = function(w, u, t) Fx.add{ kind = "nova", follow = t, c = C.shadow, r0 = 0.2, r1 = 1.5, life = 0.6 } end
SPELL.ensnare = function(w, u, t) Fx.add{ kind = "beam", from = u.id, to = t, c = C.earth, life = 0.3 } end
SPELL.berserk = function(w, u) Fx.add{ kind = "burst", follow = u.id, c = C.blood, n = 14, r = 0.9, life = 0.6 } end
SPELL.flare = function(w, u, t, ab, lv, o) Fx.add{ kind = "nova", x = o.x, y = o.y, c = C.fire, r0 = 0.5, r1 = ab.radius, life = 2 } end
SPELL.unstableConcoction = function(w, u, t) local e = unitOf(w, t) if e then Fx.add{ kind = "nova", x = e.x, y = e.y - 1, c = C.fire, r0 = 0.2, r1 = 2.2, life = 0.6 } end end

-- called from the event loop for each "cast" event
function Fx.onCast(w, ev, o)
    local u = w.ents[ev.unit]
    local fn = SPELL[ev.ability]
    if not u or not fn then return end
    local ab = D.Abilities[ev.ability]
    local lv = max(1, S.skillLevel(u, ev.ability))
    fn(w, u, ev.target, ab, lv, { x = ev.x or u.x, y = ev.y or u.y })
end

-- engine "vfx" events (bounces, impacts, Blizzard waves)
function Fx.onEvent(w, ev)
    local k = ev.kind
    if k == "bounce" then
        Fx.add{ kind = "beam", x1 = ev.x1, y1 = ev.y1, x2 = ev.x2, y2 = ev.y2, c = ev.heal and C.nature or C.lightning, jagged = not ev.heal, life = 0.45, delay = ev.delay }
        if ev.heal then Fx.add{ kind = "column", x = ev.x2, y = ev.y2, c = C.nature, r = 0.35, h = 1.8, life = 0.6, delay = ev.delay } end
    elseif k == "wave" then
        Fx.add{ kind = "shards", x = ev.x, y = ev.y, r = ev.r, c = C.frost, n = 14, life = 1.0 }
    elseif k == "impact" then
        Fx.add{ kind = "burst", x = ev.x, y = ev.y, c = C[ev.c or "white"] or C.white, n = ev.n or 12, r = ev.r or 0.9, life = 0.5 }
        if ev.ring then Fx.add{ kind = "nova", x = ev.x, y = ev.y, c = C[ev.c or "white"] or C.white, r0 = 0.1, r1 = ev.ring, life = 0.4 } end
    elseif k == "revive" then
        Fx.add{ kind = "column", x = ev.x, y = ev.y, c = C.holy, r = 0.5, h = 3, life = 1.2 }
    end
end
