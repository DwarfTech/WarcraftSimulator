-- Skirmish engine: the remaining Warcraft III rules.
--  * Day and night: a full day is 8 minutes (a game hour every 20 seconds), starting at 8:00.
--    Night (18:00 - 6:00) shrinks most units' sight to their night sight; creeps fall asleep.
--  * Orc Burrows: up to 4 Peons climb in (Battle Stations) and throw spears; Back to Work lets them out.
--  * Repair: Peasants and Peons mend buildings and machines; full repair costs 35% of the building
--    and takes 1.5x its build time. Liquid Fire stops repairs.
--  * Call to Arms: Peasants run to the hall and turn into Militia there; Back to Work sends them back.
--  * Artillery splash (Mortar Teams, Demolishers) hurts your own units too.

local _, ns = ...
local E = ns.Engine
local D, M, S = E.Data, E.Map, E.Sim

local floor, abs, max, min, sqrt = math.floor, math.abs, math.max, math.min, math.sqrt
local function alive(e) return e and not e.dead and not e.removed end
local function dist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return sqrt(dx * dx + dy * dy) end
local function T(units) return units / 128 end
local ICON = "Interface\\Icons\\"
local EMPTY = {}

-- ------------------------------------------------------------------ day and night

D.DAY_LENGTH = 480          -- seconds for 24 game hours
D.DAY_START = 8             -- the game starts at 8:00

function S.timeOfDay(w)
    return (D.DAY_START + (w.time / D.DAY_LENGTH) * 24) % 24
end

function S.isNight(w)
    local h = S.timeOfDay(w)
    return h >= 18 or h < 6
end

-- how dark it is: 0 by day, 1 in the dead of night, with an hour of dusk and dawn
function S.darkness(w)
    local h = S.timeOfDay(w)
    if h >= 6 and h < 17 then return 0 end
    if h >= 17 and h < 18 then return (h - 17) * 0.6 end
    if h >= 18 or h < 5 then return 1 end
    return 1 - (h - 5)                      -- 5:00-6:00 dawn
end

-- sight for vision: night sight after dark
function S.sightOf(w, e)
    local def = e.def
    if e.kind == "building" and not e.built then return 4 end
    if w.night and not def.alwaysSight then
        return def.nightSight or (def.sight or 6) * 0.6
    end
    return def.sight or 6
end

for _, u in pairs(D.Units) do
    if u.hero then u.nightSight = 800 / 160 end
    if u.summon and not u.nightSight then u.nightSight = (u.sight or 8) * 0.7 end
end

local function stepDayNight(w)
    local night = S.isNight(w)
    if night ~= w.night then
        w.night = night
        S.event(w, { t = night and "nightfall" or "daybreak" })
        S.updateVision(w)
        -- creeps sleep at night and wake at dawn
        for _, u in ipairs(w.list) do
            if u.kind == "unit" and u.owner == 3 and alive(u) then
                if night and not u.order then u.sleeping = true elseif not night then u.sleeping = nil end
            end
        end
    end
end

-- a sleeping camp wakes up when any of its creeps is hurt
function S.wakeCamp(w, u)
    if not u.camp then u.sleeping = nil return end
    for _, f in ipairs(w.list) do
        if f.kind == "unit" and f.owner == 3 and f.camp and f.camp[1] == u.camp[1] and f.camp[2] == u.camp[2] then f.sleeping = nil end
    end
end

-- ------------------------------------------------------------------ Orc Burrows

do
    local b = D.Buildings.burrow
    b.attack = { dmin = 23, dmax = 27, cd = 4, range = T(700), atype = "pierce", hitsAir = true, hitsGround = true, hitsBuildings = true, missile = "spear", garrison = true }
    b.garrisonMax = 4
end

-- peons near the burrow (or the hall) climb into the nearest burrow with room
function S.battleStations(w, p, bId)
    local b = w.ents[bId]
    if not alive(b) or b.owner ~= p then return false end
    local burrows = {}
    for _, e in ipairs(w.list) do
        if e.kind == "building" and e.owner == p and alive(e) and e.built and e.def.garrisonMax and dist(e.x, e.y, b.x, b.y) < 16 then
            burrows[#burrows + 1] = e
        end
    end
    if #burrows == 0 then return false, "You need a finished Orc Burrow." end
    local n = 0
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and u.owner == p and alive(u) and u.def.id == "peon" and not u.hidden and dist(u.x, u.y, b.x, b.y) < 16 then
            local best, bd
            for _, bu in ipairs(burrows) do
                local room = bu.def.garrisonMax - #(bu.garrison or EMPTY) - (bu.incoming or 0)
                local d = dist(u.x, u.y, bu.x, bu.y)
                if room > 0 and (not bd or d < bd) then best, bd = bu, d end
            end
            if best then
                u.beforeBurrow = u.order and u.order.type == "gather" and { type = "gather", res = u.order.res, mine = u.order.mine, tree = u.order.tree } or nil
                S.issue(w, u, { type = "garrison", b = best.id })
                best.incoming = (best.incoming or 0) + 1
                n = n + 1
            end
        end
    end
    for _, bu in ipairs(burrows) do bu.incoming = nil end
    if n == 0 then return false, "No Peons nearby, or the burrows are full." end
    return true
end

function S.stepGarrison(w, u, dt, o, stepMove)
    local b = w.ents[o.b or 0]
    if not alive(b) then return false end
    if S.gap(u, b) > 0.5 then stepMove(w, u, dt, nil, nil, b, 0.4) return true end
    b.garrison = b.garrison or {}
    if #b.garrison >= b.def.garrisonMax then return false end
    b.garrison[#b.garrison + 1] = u.id
    u.inBurrow = b.id
    u.hidden = true
    u.carry = nil
    S.updateSupply(w)
    return false
end

-- everybody out
function S.unloadBurrow(w, b)
    if not b.garrison then return end
    for i, id in ipairs(b.garrison) do
        local u = w.ents[id]
        if u then
            u.hidden, u.inBurrow = false, nil
            local tx, ty = M.nearestOpen(w, b.tx + b.size, b.ty + b.size - 1 + (i % 2), 4)
            if tx then u.x, u.y = tx - 0.5, ty - 0.5 u.px, u.py = u.x, u.y end
            u.order = nil
            if u.beforeBurrow then S.issue(w, u, u.beforeBurrow) u.beforeBurrow = nil end
        end
    end
    b.garrison = {}
end

function S.backToWorkAll(w, p, bId)
    local b = w.ents[bId]
    if not alive(b) or b.owner ~= p then return false end
    local n = 0
    for _, e in ipairs(w.list) do
        if e.kind == "building" and e.owner == p and alive(e) and e.garrison and #e.garrison > 0 and dist(e.x, e.y, b.x, b.y) < 16 then
            n = n + #e.garrison
            S.unloadBurrow(w, e)
        end
    end
    if b.def.hall then
        -- militia near the hall go back to work too
        for _, u in ipairs(w.list) do
            if u.kind == "unit" and u.owner == p and alive(u) and u.militia and dist(u.x, u.y, b.x, b.y) < 16 then S.backToWork(w, u) n = n + 1 end
        end
    end
    return n > 0
end

-- ------------------------------------------------------------------ Call to Arms: walk to the hall first

local becomeMilitia
function S.callToArms(w, p, hallId)
    local hall = w.ents[hallId]
    if not alive(hall) or hall.owner ~= p or not hall.def.hall or w.players[p].faction ~= "alliance" then return false end
    local n = 0
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and u.owner == p and alive(u) and u.def.id == "peasant" and not u.hidden and dist(u.x, u.y, hall.x, hall.y) < 20 then
            u.beforeArms = u.order and u.order.type == "gather" and { type = "gather", res = u.order.res, mine = u.order.mine, tree = u.order.tree } or nil
            S.issue(w, u, { type = "toArms", hall = hall.id })
            n = n + 1
        end
    end
    if n == 0 then return false, "No Peasants nearby." end
    S.event(w, { t = "callToArms", owner = p, count = n })
    return true
end

function becomeMilitia(w, u)
    local p = u.owner
    u.militia = { order = u.beforeArms }
    u.beforeArms = nil
    u.order = nil
    u.def = D.Units.militia
    u.militiaT = 45
    local frac = u.hp / u.maxhp
    u.maxhp = u.def.hp + S.hpBonus(w, p, "militia")
    u.hp = floor(u.maxhp * frac)
    u.carry = nil
    S.event(w, { t = "effect", x = u.x, y = u.y, model = 166464, size = 1.4, life = 0.8 })
end

function S.stepToArms(w, u, dt, o, stepMove)
    local hall = w.ents[o.hall or 0]
    if not alive(hall) then
        -- the hall is gone: the nearest one will do
        for _, e in ipairs(w.list) do if e.kind == "building" and e.owner == u.owner and alive(e) and e.def.hall then hall = e break end end
        if not hall then return false end
        o.hall = hall.id
    end
    if S.gap(u, hall) > 0.7 then stepMove(w, u, dt, nil, nil, hall, 0.6) return true end
    becomeMilitia(w, u)
    return false
end

-- Back to Work: militia walk to the hall to put their tools back on
local oldBackToWork = S.backToWork
function S.backToWork(w, u)
    if not u.militia then return end
    local hall
    for _, e in ipairs(w.list) do
        if e.kind == "building" and e.owner == u.owner and alive(e) and e.def.hall and e.built then
            if not hall or dist(e.x, e.y, u.x, u.y) < dist(hall.x, hall.y, u.x, u.y) then hall = e end
        end
    end
    if hall and S.gap(u, hall) > 0.8 and not u.militiaExpired then
        S.issue(w, u, { type = "toWork", hall = hall.id })
        return
    end
    oldBackToWork(w, u)
end

function S.stepToWork(w, u, dt, o, stepMove)
    local hall = w.ents[o.hall or 0]
    if not alive(hall) or not u.militia then return false end
    if S.gap(u, hall) > 0.8 then stepMove(w, u, dt, nil, nil, hall, 0.6) return true end
    u.order = nil
    oldBackToWork(w, u)
    return true
end

-- the 45 seconds run out: they turn back where they stand
function S.stepMilitia(w, u, dt)
    if u.militiaT then
        u.militiaT = u.militiaT - dt
        if u.militiaT <= 0 then u.militiaExpired = true oldBackToWork(w, u) u.militiaExpired = nil end
    end
end

-- ------------------------------------------------------------------ repair

-- can this worker repair that?
function S.canRepair(u, t)
    if not u.def.worker or u.def.lumberOnly then return false end
    if not alive(t) or t.owner ~= u.owner then return false end
    if t.kind == "building" then return t.built and t.hp < t.maxhp end
    return t.kind == "unit" and t.def.mech and t.hp < t.maxhp
end

function S.stepRepair(w, u, dt, o, stepMove)
    local t = w.ents[o.target or 0]
    if not S.canRepair(u, t) then return false end
    if S.gap(u, t) > 0.6 then stepMove(w, u, dt, nil, nil, t, 0.5) return true end
    if t.liquid and t.liquid > 0 then
        u.anim = "stand"
        if not o.warned then o.warned = true S.event(w, { t = "error", owner = u.owner, text = "Liquid Fire: it can't be repaired while it burns." }) end
        return true
    end
    local def = t.def
    local time = (def.time or 30) * 1.5
    local amount = t.maxhp / time * dt
    -- each worker after the first adds a bit less (several Peasants repair faster together)
    if t.repairTick == w.time then amount = amount * 0.6 end
    t.repairTick = w.time
    amount = min(amount, t.maxhp - t.hp)
    -- cost: 35% of the building's price for a full repair
    local pl = w.players[u.owner]
    local g = (def.gold or 0) * 0.35 * amount / t.maxhp
    local l = (def.lumber or 0) * 0.35 * amount / t.maxhp
    o.owedG, o.owedL = (o.owedG or 0) + g, (o.owedL or 0) + l
    if o.owedG >= 1 or o.owedL >= 1 then
        local pg, plu = floor(o.owedG), floor(o.owedL)
        if pl.gold < pg or pl.lumber < plu then
            S.event(w, { t = "error", owner = u.owner, text = "Not enough resources to keep repairing." })
            return false
        end
        pl.gold, pl.lumber = pl.gold - pg, pl.lumber - plu
        o.owedG, o.owedL = o.owedG - pg, o.owedL - plu
    end
    t.hp = min(t.maxhp, t.hp + amount)
    u.anim = "work"
    u.facing = math.atan2(t.y - u.y, t.x - u.x)
    return t.hp < t.maxhp
end

-- ------------------------------------------------------------------ per tick

function S.stepRules(w, dt)
    stepDayNight(w)
    for _, e in ipairs(w.list) do
        -- Liquid Fire burning on buildings
        if e.kind == "building" and alive(e) and e.liquid and e.liquid > 0 then
            e.liquid = e.liquid - dt
            e.liquidAcc = (e.liquidAcc or 0) + 8 * dt
            if e.liquidAcc >= 1 then
                local n = floor(e.liquidAcc)
                e.liquidAcc = e.liquidAcc - n
                S.damage(w, w.ents[e.liquidSrc or 0], e, n, "magic", true)
            end
        end
        -- a burrow empties when it's destroyed
        if e.kind == "building" and e.dead and e.garrison and #e.garrison > 0 then S.unloadBurrow(w, e) end
    end
end

-- the burrow throws one spear per Peon inside; Liquid Fire slows a building's attacks
function S.buildingAttackCd(w, b, atk)
    local cd = atk.cd
    if atk.garrison then cd = cd / max(1, #(b.garrison or EMPTY)) end
    if b.liquid and b.liquid > 0 then cd = cd / 0.2 end
    return cd
end

D.Units.mortarTeam.friendlyFire = true
D.Units.demolisher.friendlyFire = true

-- ------------------------------------------------------------------ Fountain of Health
-- WC3's fountains heal every unit standing around them (any player's), fast.
D.Buildings.fountain = { id = "fountain", kind = "building", faction = "neutral", name = "Fountain of Health", size = 2, hp = 1000, armor = 10,
    dtype = "fortified", gold = 0, lumber = 0, time = 1, supplyGiven = 0, sight = 5, nightSight = 5, noBuild = true, fountain = true,
    icon = ICON .. "INV_Potion_51", models = { { file = 190915, size = 2.6, fill = 0.92, guess = 6 } },
    tip = "Units standing next to the fountain regain hit points quickly." }

local stepRulesBase = S.stepRules
function S.stepRules(w, dt)
    stepRulesBase(w, dt)
    w.fountainT = (w.fountainT or 0) - dt
    if w.fountainT > 0 then return end
    w.fountainT = 0.5
    for _, f in ipairs(w.list) do
        if f.kind == "building" and f.def.fountain and alive(f) then
            for _, u in ipairs(w.list) do
                if u.kind == "unit" and alive(u) and u.owner ~= 3 and not u.def.mech and u.hp < u.maxhp and S.edgeDist(u.x, u.y, f) <= 500 / 128 then   -- ACnr: 1% a second within 500
                    u.hp = min(u.maxhp, u.hp + u.maxhp * 0.005)
                end
            end
        end
    end
end

-- ------------------------------------------------------------------ spacing
-- Every unit keeps its own patch of ground: the collision circle is as wide as the model is
-- drawn, so armies spread out the way they do in WC3 instead of piling into one heap.
-- (Workers stay slimmer, and walk through each other while gathering.)
S.formationGap = 1.15
for _, u in pairs(D.Units) do
    if u.vis then
        if u.worker then u.radius = max(0.3, u.vis * 1.15)
        elseif u.ward then u.radius = 0.2
        else u.radius = u.vis * 1.55 end
    end
end

-- ------------------------------------------------------------------ high ground
-- WC3: an attack from lower ground at a target up on higher ground misses 25% of the time
-- (ranged attacks: melee can only reach across a ramp), and a unit shooting down from high ground
-- is seen for a moment by the side it hits. Flyers fly above it all.
S.HIGH_GROUND_MISS = 25
local prevMissHG = S.missExtra
function S.missExtra(w, src, tgt)
    if prevMissHG and prevMissHG(w, src, tgt) then return true end
    if src and src.kind == "unit" and tgt and not src.def.air and not (tgt.def and tgt.def.air) and w.layer and next(w.layer)
       and (src.def.range or 0) > 1.5 and M.levelAt(w, src.x, src.y) < M.levelAt(w, tgt.x, tgt.y) then
        return w.rng.next() % 100 < S.HIGH_GROUND_MISS
    end
    return false
end

local prevLand = S.land
function S.land(w, src, tgt, dmg, wp, owner)
    if src and alive(src) and tgt and tgt.owner ~= src.owner and tgt.owner >= 1 and tgt.owner <= 2 and w.layer and next(w.layer)
       and not src.def.air and M.levelAt(w, src.x, src.y) > M.levelAt(w, tgt.x, tgt.y) then
        w.reveals = w.reveals or {}
        w.reveals[#w.reveals + 1] = { owner = tgt.owner, x = src.x, y = src.y, r = 1, t = 1.5 }
    end
    return prevLand(w, src, tgt, dmg, wp, owner)
end
