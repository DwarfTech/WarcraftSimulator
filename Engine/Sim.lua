-- Skirmish engine: the real-time simulation. Runs in fixed 0.1 second ticks so the game plays the
-- same however fast the client draws. Nothing here touches the WoW API, so the whole game can be
-- played out offline (see Debug.lua / the test harness).

local _, ns = ...
local E = ns.Engine
local D, M = E.Data, E.Map
local S = {}
E.Sim = S

local floor, abs, max, min, sqrt, atan2, cos, sin, pi =
    math.floor, math.abs, math.max, math.min, math.sqrt, math.atan2, math.cos, math.sin, math.pi

local NEUTRAL_HOSTILE = 3

-- ------------------------------------------------------------------ helpers

local function dist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return sqrt(dx * dx + dy * dy) end
S.dist = dist

-- distance from a point to an entity's edge (rectangle for buildings/mines, circle for units)
local function edgeDist(px, py, e)
    if e.kind == "unit" then return dist(px, py, e.x, e.y) - e.def.radius end
    local x1, y1 = e.tx - 1, e.ty - 1
    local x2, y2 = x1 + e.size, y1 + e.size
    local dx = px < x1 and x1 - px or (px > x2 and px - x2 or 0)
    local dy = py < y1 and y1 - py or (py > y2 and py - y2 or 0)
    return sqrt(dx * dx + dy * dy)
end
S.edgeDist = edgeDist

local function gap(a, b) return edgeDist(a.x, a.y, b) - (a.def.radius or 0) end
S.gap = gap

function S.isEnemy(a, b)
    if not a or not b or a.owner == b.owner then return false end
    if a.owner == 0 or b.owner == 0 then return false end
    return true
end

local function alive(e) return e and not e.dead and not e.removed end
S.alive = alive

local function event(w, t)
    w.events[#w.events + 1] = t
end
S.event = event

local function rand(w, a, b) return a + w.rng.next() % (b - a + 1) end

-- ------------------------------------------------------------------ world setup

function S.newWorld(opts)
    opts = opts or {}
    local w = { time = 0, nextId = 1, ents = {}, list = {}, missiles = {}, events = {}, seed = opts.seed or 1 }
    w.rng = M.rng((opts.seed or 1) * 7 + 3)
    S.currentWorld = w
    M.generate(w, opts.seed or 1, opts.map)
    w.players = {}
    local factions = opts.factions or { "alliance", "orcs" }
    for p = 1, 2 do
        w.players[p] = {
            id = p, faction = factions[p], gold = D.START_GOLD, lumber = D.START_LUMBER,
            used = 0, cap = 0, explored = {}, visible = {}, ai = opts.ai and opts.ai[p],
            stats = S.newStats(),
            research = {}, researching = {}, kodos = {},
        }
        S.recalc(w, p)
    end
    w.players[0] = { id = 0, faction = "neutral", gold = 0, lumber = 0, used = 0, cap = 0,
        explored = {}, visible = {}, stats = S.newStats() }
    w.players[NEUTRAL_HOSTILE] = { id = NEUTRAL_HOSTILE, faction = "neutral", gold = 0, lumber = 0, used = 0, cap = 0,
        explored = {}, visible = {}, stats = S.newStats() }

    for p = 1, 2 do
        local st = w.starts[p]
        local F = D.Factions[w.players[p].faction]
        local hall = S.addBuilding(w, p, F.hall, st.hall[1], st.hall[2], true)
        local mine = S.addMine(w, st.mine[1], st.mine[2])
        w.players[p].home = { hall.x, hall.y }
        -- workers between the hall and the mine
        for i = 1, F.startWorkers or 5 do
            local ax, ay = (hall.x + mine.x) / 2, (hall.y + mine.y) / 2
            local tx, ty = M.nearestOpen(w, floor(ax) + (i % 3) - 1, floor(ay) + floor(i / 3), 6)
            local u = S.addUnit(w, p, F.worker, tx - 0.5, ty - 0.5)
            if opts.autoGather ~= false then S.issue(w, u, { type = "gather", res = "gold", mine = mine.id }) end
        end
        if F.mineBuilding == "hauntedMine" and S.undeadStart then S.undeadStart(w, p, hall, mine, opts.autoGather)
        elseif F.mineBuilding == "entangledMine" and S.nightElfStart then S.nightElfStart(w, p, hall, mine, opts.autoGather) end
    end
    for _, e in ipairs(w.expansions) do local m = S.addMine(w, e[1], e[2]) if e.gold then m.gold = e.gold end end

    -- neutral creep camps and the neutral shops (Goblin Merchant, Mercenary Camp, Goblin Laboratory)
    if opts.creeps ~= false then S.placeNeutral(w) end
    S.updateSupply(w)
    S.updateVision(w)
    return w
end

D.applyFeel()

-- Spacing: units keep apart by about the width of their model, like Warcraft III, instead of
-- squeezing models together. (Workers stay a little slimmer so they don't jam around the base.)
for _, u in pairs(D.Units) do
    if u.vis and not u.spaced then
        u.spaced = true
        u.radius = u.worker and max(u.radius, 0.3) or max(u.radius, u.vis * 1.2)
    end
end

-- what the score screen shows at the end (the same tallies as Warcraft III's)
function S.newStats()
    return { trained = 0, killed = 0, lost = 0, built = 0, razed = 0, gold = 0, lumber = 0,
             creeps = 0, largest = 0, heroKills = 0, items = 0, hired = 0, xp = 0, upkeepLost = 0,
             spent = 0, hist = {} }
end

local function newEnt(w, t)
    t.id = w.nextId
    w.nextId = w.nextId + 1
    w.ents[t.id] = t
    w.list[#w.list + 1] = t
    return t
end

function S.addUnit(w, owner, id, x, y)
    local def = D.Units[id]
    local u = newEnt(w, { kind = "unit", owner = owner, def = def, x = x, y = y, px = x, py = y,
        hp = def.hp, maxhp = def.hp, facing = (owner == 1) and -pi / 4 or (3 * pi / 4), cd = 0, stun = 0, slow = 0,
        anim = "stand", variant = 1 + (w.nextId % (def.display and #def.display or 1)), born = w.time })
    if owner <= 2 and not def.hero and S.hpBonus then
        u.maxhp = def.hp + S.hpBonus(w, owner, id)
        u.hp = u.maxhp
    end
    if def.hero then S.initHero(w, u, w.reviveRec)
    elseif def.mana then
        local b = S.bonus(w, u)
        u.maxMana = def.mana + (b.mana or 0)
        u.mana = min(u.maxMana, def.mana0 or u.maxMana)
        u.abilityCd = {}
    end
    if def.spells then u.abilityCd = u.abilityCd or {} u.mana = u.mana or 0 end
    return u
end

function S.addBuilding(w, owner, id, tx, ty, done)
    local def = D.Buildings[id]
    local b = newEnt(w, { kind = "building", owner = owner, def = def, tx = tx, ty = ty, size = def.size,
        x = tx - 1 + def.size / 2, y = ty - 1 + def.size / 2,
        hp = floor((done and def.hp or def.hp * 0.1) * (1 + 0.1 * (w.players[owner].masonry or 0))),
        maxhp = floor(def.hp * (1 + 0.1 * (w.players[owner].masonry or 0))),
        built = done and true or false, progress = done and 1 or 0, queue = {}, trainT = 0, cd = 0 })
    if not def.onMine then M.setRect(w, tx, ty, def.size, b) end
    if done then w.players[owner].stats.built = w.players[owner].stats.built end
    S.pushOut(w, b)
    return b
end

function S.addMine(w, tx, ty)
    local m = newEnt(w, { kind = "mine", owner = 0, def = D.GoldMine, tx = tx, ty = ty, size = 3,
        x = tx - 1 + 1.5, y = ty - 1 + 1.5, gold = D.MINE_GOLD, hp = 1, maxhp = 1 })
    M.setRect(w, tx, ty, 3, m)
    return m
end

-- move any units standing inside a new footprint out to open ground
function S.pushOut(w, b)
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and alive(u) and not u.hidden then
            local tx, ty = M.tileOf(u.x, u.y)
            if not M.walkable(w, tx, ty) then
                local nx, ny = M.nearestOpen(w, tx, ty, 8)
                if nx then u.x, u.y = nx - 0.5, ny - 0.5 u.px, u.py = u.x, u.y end
                u.path = nil
            end
        end
    end
end

-- ------------------------------------------------------------------ supply & resources

function S.updateSupply(w)
    for p = 1, 2 do
        local pl = w.players[p]
        pl.used, pl.cap, pl.army = 0, 0, 0
        pl.heroAlive, pl.heroQueued = false, false
        pl.has = {}
        pl.researching = {}
        pl.kodos = {}
    end
    for _, e in ipairs(w.list) do
        local pl = w.players[e.owner]
        if pl and e.owner >= 1 and e.owner <= 2 and alive(e) then
            if e.kind == "unit" then
                pl.used = pl.used + e.def.supply
                pl.army = (pl.army or 0) + e.def.supply
                if e.def.hero then pl.heroAlive = true end
                if e.def.aura == "warDrums" then pl.kodos[#pl.kodos + 1] = e end
                -- an uprooted Tree or Ancient still counts as its building (food, tech)
                if e.def.rootsTo then
                    local bd = D.Buildings[e.def.rootsTo]
                    pl.cap = pl.cap + (bd.supplyGiven or 0)
                    pl.has[bd.id] = true
                end
            elseif e.kind == "building" then
                if e.built then
                    pl.cap = pl.cap + e.def.supplyGiven
                    pl.has[e.def.id] = true
                end
                for _, q in ipairs(e.queue) do
                    local kind, qd, qid = S.queueItem(q)
                    if kind == "unit" then
                        pl.used = pl.used + qd.supply
                        if qd.hero then pl.heroQueued = true end
                    elseif kind == "research" then
                        pl.researching[qid] = true
                    end
                end
            end
        end
    end
    for p = 1, 2 do
        local pl = w.players[p]
        pl.cap = min(pl.cap, D.MAX_SUPPLY)
        if pl.stats and pl.army > (pl.stats.largest or 0) then pl.stats.largest = pl.army end
    end
end

function S.canAfford(w, p, def, mult)
    local pl = w.players[p]
    mult = mult or 1
    if pl.gold < floor((def.gold or 0) * mult) then return false, "Not enough gold." end
    if pl.lumber < floor((def.lumber or 0) * mult) then return false, "Not enough lumber." end
    return true
end

local function pay(w, p, def, mult)
    local pl = w.players[p]
    mult = mult or 1
    pl.gold = pl.gold - floor((def.gold or 0) * mult)
    pl.lumber = pl.lumber - floor((def.lumber or 0) * mult)
end

local function refund(w, p, def, mult)
    local pl = w.players[p]
    mult = mult or 1
    pl.gold = pl.gold + floor((def.gold or 0) * mult)
    pl.lumber = pl.lumber + floor((def.lumber or 0) * mult)
end
S.refund = refund

-- ------------------------------------------------------------------ orders

local function clearOrder(w, u)
    local o = u.order
    if o and o.type == "build" and o.paid and not o.placed then refund(w, u.owner, D.Buildings[o.bid]) end
    -- shift-queued buildings that were never started give their money back
    if u.queue then
        for _, q in ipairs(u.queue) do
            if q.type == "build" and q.paid and not q.placed then refund(w, u.owner, D.Buildings[q.bid]) end
        end
        u.queue = nil
    end
    if o and o.mine then
        local m = w.ents[o.mine]
        if m and m.inside == u.id then m.inside = nil u.hidden = false end
    end
    -- a new order breaks off a channelled spell
    if u.channel then
        if u.channel.ability == "aerialShackles" then
            local t = w.ents[u.channel.target or 0]
            if t and t.buffs then t.buffs.shackled = nil end
        end
        u.channel = nil
    end
    u.order, u.path, u.target = nil, nil, nil
end

-- give a unit a new order (replacing whatever it was doing)
function S.issue(w, u, o)
    if not alive(u) or u.kind ~= "unit" or u.inBurrow then return end
    if u.order and u.order.type == "gather" and o.type == "gather" and u.order.state == "inMine" then
        -- let it finish inside the mine
        u.nextOrder = o
        return
    end
    -- Shift: line the order up after what the unit is already doing (WC3 shift-queue)
    if w.queueing and u.order and o.type ~= "stop" and o.type ~= "hold" then
        u.queue = u.queue or {}
        if #u.queue < 12 then u.queue[#u.queue + 1] = o end
        return
    end
    clearOrder(w, u)
    u.order = o
    u.repath = 0
    u.stuck, u.partial, u.blockedT = nil, nil, 0
end

local function formation(n)
    local cols = math.ceil(sqrt(n))
    local out = {}
    for i = 0, n - 1 do
        local c, r = i % cols, floor(i / cols)
        out[#out + 1] = { (c - (cols - 1) / 2) * (S.formationGap or 1.1), (r - (math.ceil(n / cols) - 1) / 2) * (S.formationGap or 1.1) }
    end
    return out
end

-- the player's way in: a command for a group of units. Returns false, reason on failure.
local commandNow
function S.command(w, p, ids, cmd)
    w.queueing = cmd.queue and true or nil
    local ok, why = commandNow(w, p, ids, cmd)
    w.queueing = nil
    return ok, why
end
function commandNow(w, p, ids, cmd)
    local units = {}
    for _, id in ipairs(ids) do
        local u = w.ents[id]
        if alive(u) and u.owner == p and u.kind == "unit" then units[#units + 1] = u end
    end
    if #units == 0 then return false end
    local t = cmd.type
    if t == "move" or t == "amove" then
        local offs = formation(#units)
        -- a group walks at the pace of its slowest member, as in Warcraft III
        local gs
        if #units > 1 then
            gs = 99
            for _, u in ipairs(units) do gs = min(gs, u.def.speed) end
        end
        -- keep the group's left/right order so units don't cross over each other
        table.sort(units, function(a, b) if abs(a.y - b.y) > 0.6 then return a.y < b.y end return a.x < b.x end)
        for i, u in ipairs(units) do
            local dx, dy = offs[i][1], offs[i][2]
            if #units == 1 then dx, dy = 0, 0 end
            S.issue(w, u, { type = t, x = cmd.x + dx, y = cmd.y + dy, gs = gs })
        end
    elseif t == "attack" then
        local tgt = w.ents[cmd.target]
        if not alive(tgt) then return false end
        for _, u in ipairs(units) do S.issue(w, u, { type = "attack", target = tgt.id }) end
    elseif t == "stop" then
        for _, u in ipairs(units) do S.issue(w, u, { type = "stop" }) u.order = nil end
    elseif t == "defend" then
        -- Footmen with the Defend research raise their shields (or lower them)
        local on = cmd.on
        for _, u in ipairs(units) do
            if u.def.id == "footman" and S.bonus(w, u).flags and S.bonus(w, u).flags.defend then
                if on == nil then on = not u.defend end
                u.defend = on
            end
        end
    elseif t == "repair" then
        local tgt = w.ents[cmd.target or 0]
        local any = false
        for _, u in ipairs(units) do if S.canRepair(u, tgt) then S.issue(w, u, { type = "repair", target = tgt.id }) any = true end end
        if not any then return false, "Must target a damaged building or machine of yours." end
    elseif t == "backToWork" then
        for _, u in ipairs(units) do if u.militia then S.backToWork(w, u) end end
    elseif t == "hold" then
        for _, u in ipairs(units) do S.issue(w, u, { type = "hold" }) end
    elseif t == "gather" then
        local any = false
        for _, u in ipairs(units) do
            if u.def.worker or u.def.gatherer then
                any = true
                if cmd.mine then S.issue(w, u, { type = "gather", res = "gold", mine = cmd.mine })
                else S.issue(w, u, { type = "gather", res = "lumber", tree = cmd.tree }) end
            end
        end
        if not any then return false, "Only workers can gather." end
    elseif t == "return" then
        for _, u in ipairs(units) do
            if (u.def.worker or u.def.gatherer) and u.carry then
                S.issue(w, u, { type = "gather", res = u.carry.res, state = "return",
                    mine = u.lastMine, tree = u.lastTree })
            end
        end
    elseif t == "smart" then
        -- right-click: attack enemies, gather resources, otherwise move
        local tgt = cmd.target and w.ents[cmd.target]
        if tgt and alive(tgt) and S.isEnemy(units[1], tgt) then
            return commandNow(w, p, ids, { type = "attack", target = tgt.id })
        end
        -- an item on the ground: the first hero goes to pick it up
        if tgt and tgt.kind == "item" and alive(tgt) then
            for _, u in ipairs(units) do
                if u.def.hero and not u.illusion then S.issue(w, u, { type = "pickup", item = tgt.id }) return true end
            end
            return commandNow(w, p, ids, { type = "move", x = cmd.x, y = cmd.y })
        end
        -- a Haunted Gold Mine of yours: Acolytes go and mine it
        if tgt and alive(tgt) and tgt.kind == "building" and tgt.def.onMine and tgt.owner == p and tgt.built and tgt.mine then
            local workers, others = {}, {}
            for _, u in ipairs(units) do
                if u.def.haunt then workers[#workers + 1] = u.id else others[#others + 1] = u.id end
            end
            if #workers > 0 then
                commandNow(w, p, workers, { type = "gather", mine = tgt.mine })
                if #others > 0 then commandNow(w, p, others, { type = "move", x = cmd.x, y = cmd.y }) end
                return true
            end
        end
        if tgt and tgt.kind == "mine" or cmd.tree then
            local workers, others = {}, {}
            for _, u in ipairs(units) do
                if u.def.worker or (u.def.gatherer and cmd.tree) then workers[#workers + 1] = u.id else others[#others + 1] = u.id end
            end
            if #workers > 0 then
                commandNow(w, p, workers, { type = "gather", mine = tgt and tgt.kind == "mine" and tgt.id or nil, tree = cmd.tree })
            end
            if #others > 0 then commandNow(w, p, others, { type = "move", x = cmd.x, y = cmd.y }) end
            return true
        end
        -- workers right-clicking a damaged building or machine of yours repair it
        if tgt and alive(tgt) and tgt.owner == p and (tgt.kind == "building" and tgt.built or tgt.kind == "unit") then
            local fixers, rest = {}, {}
            for _, u in ipairs(units) do
                if S.canRepair(u, tgt) and not (u.carry and tgt.def.dropoff) then fixers[#fixers + 1] = u else rest[#rest + 1] = u.id end
            end
            if #fixers > 0 then
                for _, u in ipairs(fixers) do S.issue(w, u, { type = "repair", target = tgt.id }) end
                if #rest > 0 then commandNow(w, p, rest, { type = "smart", target = cmd.target, x = cmd.x, y = cmd.y }) end
                return true
            end
        end
        if tgt and tgt.kind == "building" and tgt.owner == p then
            local workers, others = {}, {}
            for _, u in ipairs(units) do
                if u.def.worker and (not tgt.built) and not tgt.selfBuild then workers[#workers + 1] = u
                elseif (u.def.worker or u.def.gatherer) and u.carry and tgt.def.dropoff and tgt.built then workers[#workers + 1] = u
                else others[#others + 1] = u.id end
            end
            for _, u in ipairs(workers) do
                if not tgt.built then S.issue(w, u, { type = "construct", b = tgt.id })
                else S.issue(w, u, { type = "gather", res = u.carry.res, state = "return", mine = u.lastMine, tree = u.lastTree }) end
            end
            if #others > 0 then commandNow(w, p, others, { type = "move", x = cmd.x, y = cmd.y }) end
            return true
        end
        -- right-click on one of your own (or an allied) units: follow it
        if tgt and alive(tgt) and tgt.kind == "unit" and not tgt.hidden then
            local any = false
            for _, u in ipairs(units) do
                if u.id ~= tgt.id then S.issue(w, u, { type = "follow", target = tgt.id }) any = true end
            end
            if any then return true end
        end
        return commandNow(w, p, ids, { type = "move", x = cmd.x, y = cmd.y })
    elseif t == "patrol" then
        -- walk round the patrol points, fighting anything met on the way (Shift adds a point)
        local offs = formation(#units)
        for i, u in ipairs(units) do
            local dx, dy = offs[i][1], offs[i][2]
            if #units == 1 then dx, dy = 0, 0 end
            local px, py = cmd.x + dx, cmd.y + dy
            local cur = u.order
            if w.queueing and cur and cur.type == "patrol" and #cur.pts < 8 then
                cur.pts[#cur.pts + 1] = { px, py }
            else
                local qx, qy = u.x, u.y
                if w.queueing and u.queue and #u.queue > 0 and u.queue[#u.queue].x then qx, qy = u.queue[#u.queue].x, u.queue[#u.queue].y
                elseif w.queueing and cur and cur.x then qx, qy = cur.x, cur.y end
                S.issue(w, u, { type = "patrol", pts = { { qx, qy }, { px, py } }, i = 2, x = px, y = py })
            end
        end
    elseif t == "follow" then
        local tgt = w.ents[cmd.target or 0]
        if not alive(tgt) or tgt.kind ~= "unit" then return false end
        for _, u in ipairs(units) do if u.id ~= tgt.id then S.issue(w, u, { type = "follow", target = tgt.id }) end end
    elseif t == "cast" then
        local caster = units[1]
        for _, u in ipairs(units) do
            if S.skillLevel(u, cmd.ability) > 0 and S.canCast(w, u, cmd.ability) then caster = u break end
        end
        return S.castCommand(w, caster, cmd)
    end
    return true
end

-- ------------------------------------------------------------------ buildings & training

-- is a spot already promised to a building one of this player's workers is on the way to build?
function S.siteReserved(w, p, tx, ty, size)
    local function hits(o)
        if not o or o.type ~= "build" or o.placed then return false end
        local s2 = D.Buildings[o.bid].size
        return tx < o.tx + s2 and o.tx < tx + size and ty < o.ty + s2 and o.ty < ty + size
    end
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and u.owner == p and alive(u) and u.def.worker then
            if hits(u.order) then return true end
            for _, q in ipairs(u.queue or {}) do if hits(q) then return true end end
        end
    end
    return false
end

-- queue = true (shift-click): the worker builds it after the buildings it already has lined up
function S.build(w, p, workerId, bid, tx, ty, queue)
    local u = w.ents[workerId]
    local def = D.Buildings[bid]
    if not alive(u) or not u.def.worker or u.owner ~= p then return false end
    local ok, need = S.requirementMet(w, p, bid)
    if not ok then return false, S.needText(need) end
    if def.noBuild then return false end
    local afford, why = S.canAfford(w, p, def)
    if not afford then return false, why end
    local okPlace, whyPlace = S.canPlaceFor(w, p, bid, tx, ty)
    if not okPlace then return false, whyPlace end
    if S.siteReserved(w, p, tx, ty, def.size) then return false, "Another building is already planned there." end
    pay(w, p, def)
    local o = { type = "build", bid = bid, tx = tx, ty = ty, paid = true }
    local busy = u.order and (u.order.type == "build" or u.order.type == "construct")
    if queue and (busy or (u.queue and #u.queue > 0)) then
        u.queue = u.queue or {}
        -- whatever the worker goes back to afterwards (gathering) moves to the end of the line
        local last = u.queue[#u.queue] or u.order
        o.after, last.after = last.after, nil
        u.queue[#u.queue + 1] = o
        return true
    end
    S.issue(w, u, o)
    return true
end

function S.cancelBuilding(w, p, bId)
    local b = w.ents[bId]
    if not alive(b) or b.owner ~= p or b.built then return false end
    refund(w, p, b.def, 0.75)
    S.kill(w, b, nil, true)
    return true
end

function S.setRally(w, p, bId, x, y, target)
    local b = w.ents[bId]
    if not alive(b) or b.owner ~= p then return end
    b.rally = { x = x, y = y, target = target }
end

local function spawnFrom(w, b, uid)
    -- the open tile around the building closest to its rally point
    local rx, ry = b.rally and b.rally.x or (b.x + 2), b.rally and b.rally.y or (b.y + 2)
    local best, bd
    for yy = b.ty - 1, b.ty + b.size do
        for xx = b.tx - 1, b.tx + b.size do
            if M.walkable(w, xx, yy) then
                local d = dist(xx - 0.5, yy - 0.5, rx, ry)
                if not bd or d < bd then best, bd = { xx, yy }, d end
            end
        end
    end
    if not best then
        local nx, ny = M.nearestOpen(w, b.tx, b.ty, 10)
        if not nx then return end
        best = { nx, ny }
    end
    local u = S.addUnit(w, b.owner, uid, best[1] - 0.5, best[2] - 0.5)
    u.facing = atan2(ry - u.y, rx - u.x)
    w.players[b.owner].stats.trained = w.players[b.owner].stats.trained + 1
    event(w, { t = "trained", unit = u.id, owner = b.owner })
    if b.rally then
        local tgt = b.rally.target and w.ents[b.rally.target]
        if u.def.worker and tgt and tgt.kind == "mine" then
            S.issue(w, u, { type = "gather", res = "gold", mine = tgt.id })
        elseif tgt and tgt.kind == "unit" and alive(tgt) and tgt.owner == b.owner then
            -- rallied onto one of your units: the new unit follows it, as in Warcraft III
            S.issue(w, u, { type = "follow", target = tgt.id })
        elseif (u.def.worker or u.def.gatherer) and b.rally.tree then
            S.issue(w, u, { type = "gather", res = "lumber", tree = b.rally.tree })
        else
            S.issue(w, u, { type = "move", x = b.rally.x, y = b.rally.y })
        end
    end
    return u
end

S.spawnFrom = spawnFrom

-- ------------------------------------------------------------------ damage & death

local function armorMult(a)
    if a >= 0 then return 1 - (0.06 * a) / (1 + 0.06 * a) end
    return 2 - 0.94 ^ (-a)
end
S.armorMult = armorMult

function S.damage(w, src, tgt, amount, atype, spell, noLink)
    if not alive(tgt) or tgt.kind == "mine" or tgt.kind == "item" or tgt.invulnerable then return end
    local mult = 1
    if not spell then
        local armor, dtype = S.armorOf(w, tgt)
        mult = (D.ATTACK_VS[atype or "normal"] or D.ATTACK_VS.normal)[dtype or "medium"] or 1
        mult = mult * armorMult(armor)
        -- Defend: footmen take half damage from piercing attacks
        if tgt.defend and atype == "pierce" then mult = mult * 0.5 end
    elseif tgt.kind == "unit" and tgt.def.hero then
        -- WC3: Hero armour takes 70% damage from spells (since patch 1.15)
        mult = 0.7
    elseif tgt.kind == "unit" and tgt.def.resistantSkin and tgt.owner >= 1 and tgt.owner <= 2 and S.level(w, tgt.owner, "resistantSkin") > 0 then
        -- Resistant Skin: Mountain Giants take spells like heroes do
        mult = 0.7
    end
    local taken = S.damageTaken(w, tgt, src, atype, spell)
    if taken <= 0 or amount <= 0 then return end
    mult = mult * taken
    local dmg = max(1, floor(amount * mult + 0.5))
    if not noLink and tgt.kind == "unit" and tgt.buffs and tgt.buffs.link then dmg = max(1, floor(S.linkShare(w, tgt, src, dmg) + 0.5)) end
    -- Mana Shield: damage comes off mana first
    if tgt.buffs and tgt.buffs.manaShield and S.absorbExtra then
        dmg = S.absorbExtra(w, tgt, dmg)
        if dmg <= 0 then return end
    end
    tgt.hp = tgt.hp - dmg
    tgt.hitT = w.time
    -- damage wakes a sleeping unit
    if tgt.buffs and tgt.buffs.sleep then tgt.buffs.sleep = nil tgt.stun = 0 end
    if src then tgt.lastAttacker = src.id end
    if tgt.sleeping then S.wakeCamp(w, tgt) end
    event(w, { t = "hit", unit = tgt.id, dmg = dmg, spell = spell })
    if tgt.hp <= 0 then
        S.kill(w, tgt, src)
        return
    end
    -- react: idle units fight back, and nearby idle friends come to help
    if src and alive(src) and tgt.kind == "unit" then
        local o = tgt.order
        if (not o or (o.auto and not alive(w.ents[o.target or 0]))) and not tgt.def.worker and tgt.def.dmin and not tgt.channel then
            tgt.order = { type = "attack", target = src.id, auto = true, home = { tgt.x, tgt.y } }
        end
    end
    if src and alive(src) and tgt.owner ~= NEUTRAL_HOSTILE then
        for _, f in ipairs(w.list) do
            if f.kind == "unit" and f.owner == tgt.owner and alive(f) and not f.order and not f.def.worker and f.def.dmin and not f.hidden and not f.channel
               and abs(f.x - tgt.x) < 6 and abs(f.y - tgt.y) < 6 then
                f.order = { type = "attack", target = src.id, auto = true, home = { f.x, f.y } }
            end
        end
    elseif src and alive(src) and tgt.owner == NEUTRAL_HOSTILE then
        for _, f in ipairs(w.list) do
            if f.owner == NEUTRAL_HOSTILE and alive(f) and f.camp and tgt.camp and f.camp[1] == tgt.camp[1] and f.camp[2] == tgt.camp[2] and not f.order then
                f.order = { type = "attack", target = src.id, auto = true }
            end
        end
    end
end

local function giveXp(w, killer, victim) S.giveXp(w, killer, victim) end

function S.kill(w, e, killer, quiet)
    if e.dead then return end
    if e.kind == "unit" and not quiet and S.tryReincarnate(w, e) then return end
    e.dead = true
    e.hp = 0
    e.deadT = 0
    local pl = w.players[e.owner]
    if e.kind == "unit" then
        clearOrder(w, e)
        e.anim = "death"
        if e.hidden then e.hidden = false end
        S.creepDied(w, e, killer)
        if pl and pl.stats then pl.stats.lost = pl.stats.lost + 1 end
        local kp = killer and w.players[killer.owner]
        if kp and kp.stats and killer.owner ~= e.owner then
            kp.stats.killed = kp.stats.killed + 1
            if e.owner > 2 or e.owner == 0 then kp.stats.creeps = kp.stats.creeps + 1 end
            if e.def.hero and not e.illusion then kp.stats.heroKills = kp.stats.heroKills + 1 end
        end
        if not e.illusion then giveXp(w, killer, e) end
        e.channel, e.teleport = nil, nil
        S.onDeath(w, e)
        if e.def.hero and pl and not e.illusion then
            event(w, { t = "heroDied", unit = e.id, owner = e.owner })
        end
        -- illusions and summons vanish
        if e.illusion or e.def.summon then e.removed = true end
    else
        if not (e.def and e.def.onMine) then M.setRect(w, e.tx, e.ty, e.size, nil) end
        e.removed = true
        if e.kind == "building" then
            if S.buildingGone then S.buildingGone(w, e) end
            -- a hero being revived at a destroyed altar goes back to the dead list
            for _, info in ipairs(e.qinfo or {}) do
                if info.rec and pl then pl.deadHeroes = pl.deadHeroes or {} table.insert(pl.deadHeroes, info.rec) end
            end
            if killer and w.players[killer.owner] then w.players[killer.owner].stats.razed = w.players[killer.owner].stats.razed + 1 end
            -- a worker building it stops
            for _, u in ipairs(w.list) do
                if u.kind == "unit" and u.order and u.order.b == e.id then u.order = nil end
            end
            if not quiet then event(w, { t = "destroyed", x = e.x, y = e.y, size = e.size, owner = e.owner }) end
        end
    end
    event(w, { t = "died", unit = e.id, owner = e.owner, kind = e.kind })
    S.updateSupply(w)
end

-- ------------------------------------------------------------------ movement

-- Walk toward a goal. goal is either a point { x, y } or an entity (walk until next to it).
-- Returns true when there.
local function stepMove(w, u, dt, gx, gy, ent, within)
    within = within or 0.15
    if ent then
        if gap(u, ent) <= within then u.path = nil return true end
    else
        if dist(u.x, u.y, gx, gy) <= within + 0.1 then u.path = nil return true end
    end
    u.repath = (u.repath or 0) - dt
    local key = ent and ("e" .. ent.id) or (floor(gx * 2) .. ":" .. floor(gy * 2))
    if u.def.air then
        -- flyers go straight over trees and buildings
        u.path = { { ent and ent.x or gx, ent and ent.y or gy } }
        u.pi, u.pathKey, u.stuck, u.partial = 1, key, nil, nil
    end
    -- (a budget of path searches per tick keeps a big army's re-route from freezing a frame;
    -- units over budget keep their old path, or wait a tick)
    local wantPath = not u.def.air and (not u.path or u.pathKey ~= key or u.repath <= 0 or u.pathVer ~= w.blockVersion and u.repath < 0.6)
    if wantPath and ((w.pathBudget or 99) <= 0 or (w.nodeBudget or 9999) <= 300) then
        wantPath = false
        u.repath = 0
        if not u.path then return false end
    end
    if wantPath then
        w.pathBudget = (w.pathBudget or 99) - 1
        local sx, sy = M.tileOf(u.x, u.y)
        local goal
        if ent then
            if ent.kind == "unit" then
                local ex, ey = M.tileOf(ent.x, ent.y)
                goal = { ex, ey }
            else
                goal = { ent.tx, ent.ty, ent.tx + ent.size - 1, ent.ty + ent.size - 1 }
            end
        else
            local ex, ey = M.tileOf(gx, gy)
            goal = { ex, ey }
        end
        -- units of a group heading the same way share one search (WC3 moves groups the same way)
        local ck = floor(sx / 3) .. ":" .. floor(sy / 3) .. ">" .. floor(goal[1] / 3) .. ":" .. floor(goal[2] / 3) .. (goal[3] and ("r" .. goal[3]) or "")
        w.pathCache = w.pathCache or {}
        local c = w.pathCache[ck]
        local path, found
        if c and c.ver == w.blockVersion and w.time - c.t < 1.5 then
            if c.path then path = {} for i, pt in ipairs(c.path) do path[i] = { pt[1], pt[2] } end end
            found = c.found
            w.pathBudget = w.pathBudget + 1     -- a shared path costs nothing
        else
            path, found = M.findPath(w, sx, sy, goal, min(2500, w.nodeBudget or 2500))
            local copy
            if path then copy = {} for i, pt in ipairs(path) do copy[i] = { pt[1], pt[2] } end end
            w.pathCache[ck] = { path = copy, found = found, t = w.time, ver = w.blockVersion }
        end
        u.path, u.pi, u.pathKey, u.pathVer = path, 1, key, w.blockVersion
        u.partial = path and not found
        u.stuck = path == nil
        u.repath = ent and ent.kind == "unit" and 0.8 or 3
        if path and #path > 0 then
            -- finish on the exact point when walking to open ground
            if not ent then
                local last = path[#path]
                if dist(last[1], last[2], gx, gy) < 1.2 and M.walkable(w, M.tileOf(gx, gy)) then
                    path[#path] = { gx, gy }
                end
            elseif ent.kind == "unit" then
                path[#path] = { ent.x, ent.y }
            end
        end
    end
    local path = u.path
    if u.stuck then
        -- no way there at all: stand still rather than run on the spot
        u.anim = "stand"
        return false
    end
    if not path or #path == 0 then
        -- already next to it: step in the last bit
        path = { { ent and ent.x or gx, ent and ent.y or gy } }
        u.path, u.pi = path, 1
    end
    local wp = path[u.pi]
    if not wp then u.path = nil return true end
    local speed = u.def.speed
    local o = u.order
    if o and o.gs and (o.type == "move" or (o.type == "amove" and not o.target)) then speed = min(speed, o.gs) end
    if u.defend then speed = speed * 0.7 end
    speed = speed * S.moveSpeedMult(w, u)
    speed = speed * (u.slow > 0 and (1 - (u.slowFactor or 0.5)) or 1)
    local dx, dy = wp[1] - u.x, wp[2] - u.y
    local d = sqrt(dx * dx + dy * dy)
    -- turn to face the way it's going first (no running sideways or backwards)
    if d > 0.01 then
        local want = atan2(dy, dx)
        local diff = (want - (u.facing or want) + pi) % (2 * pi) - pi
        local turn = 11 * dt
        if abs(diff) <= turn then u.facing = want diff = 0
        else u.facing = (u.facing or 0) + (diff > 0 and turn or -turn) diff = diff - (diff > 0 and turn or -turn) end
        local align = cos(diff)
        -- turn on the spot for sharp turns, otherwise ease into it while walking
        if align < 0 then speed = 0 else speed = speed * max(0.35, align) end
    end
    local step = speed * dt
    if d <= step then
        u.x, u.y = wp[1], wp[2]
        u.pi = u.pi + 1
        if u.pi > #path then
            u.path = nil
            if u.partial then u.stuck = true u.anim = "stand" return false end
            if not ent then return dist(u.x, u.y, gx, gy) <= within + 0.4 end
        end
    elseif step > 0 then
        u.x, u.y = u.x + dx / d * step, u.y + dy / d * step
    end
    u.anim = "walk"
    u.moved = true
    return false
end

-- ------------------------------------------------------------------ targeting

local function canAttack(u) return u.def.dmin ~= nil end
local function reach(w, u, tgt)
    local wp = S.weaponFor(w, u, tgt)
    return wp and S.rangeOf(w, u, wp) or nil, wp
end

-- best enemy near a unit (units before buildings, closest first)
function S.findTarget(w, u, range)
    local best, bs
    for _, e in ipairs(w.list) do
        if alive(e) and S.isEnemy(u, e) and not e.hidden and e.kind ~= "mine" and S.targetable(w, u, e)
           and (u.owner < 1 or u.owner > 2 or S.visibleTo(w, u.owner, e)) then    -- WC3: only what you can see
            if abs(e.x - u.x) < range + 3 and abs(e.y - u.y) < range + 3 and S.canHit(w, u, e) then
                local d = gap(u, e)
                if d <= range and not (u.def.minRange and d < u.def.minRange) then
                    local score = d
                    if e.kind == "building" then score = score + 6
                    elseif e.def.worker then score = score + 2 end
                    if e.kind == "unit" and not canAttack(e) then score = score + 3 end
                    if not bs or score < bs then best, bs = e, score end
                end
            end
        end
    end
    return best
end

local function startAttack(w, u, tgt, wp)
    u.facing = atan2(tgt.y - u.y, tgt.x - u.x)
    if u.cd > 0 then
        if not u.swing then u.anim = "ready" end
        return
    end
    if not S.canAct(u) then u.anim = "stand" return end
    if u.buffs and u.buffs.invis then u.buffs.invis = nil end
    u.cd = (wp.cd or u.def.cd) / S.attackSpeed(w, u)
    u.swing = { t = max(0.15, min(0.8, wp.dmgpt or 0.4)), target = tgt.id, wp = wp }
    u.anim = "attack"
    u.animT = 0.7
end

local function finishSwing(w, u, dt)
    if not u.swing then return end
    u.swing.t = u.swing.t - dt
    if u.swing.t > 0 then return end
    local tgt = w.ents[u.swing.target]
    local wp = u.swing.wp
    u.swing = nil
    if not alive(tgt) or not wp then return end
    local dmg = S.roll(w, u, wp)
    if wp.missile then
        local slow = (wp.missile == "shell" or wp.missile == "boulder")
        w.missiles[#w.missiles + 1] = { x = u.x, y = u.y, target = tgt.id, src = u.id, dmg = dmg, atype = wp.atype,
            speed = slow and 9 or 16, kind = wp.missile, wp = wp, owner = u.owner }
    else
        S.land(w, u, tgt, dmg, wp, u.owner)
    end
end

-- attack a target: chase it, then swing. Returns false once the target is gone.
local function stepAttack(w, u, dt, tgt)
    if not alive(tgt) or tgt.hidden then return false end
    local range, wp = reach(w, u, tgt)
    if not range then return false end
    -- Mortar Teams and Demolishers can't hit anything closer than 250
    if wp and wp.minRange and gap(u, tgt) < wp.minRange and not u.swing then return false end
    -- once swinging, a little slack so being nudged doesn't break off the fight
    local slack = (u.engaged == tgt.id) and 0.3 or 0.05
    if gap(u, tgt) <= range + slack then
        u.path = nil
        u.engaged = tgt.id
        startAttack(w, u, tgt, wp)
        return true
    end
    u.engaged = nil
    if u.order and u.order.type == "hold" then return false end
    if u.swing then return true end
    -- stuck behind friends while chasing: hit whatever enemy is already within reach instead
    if (u.blockedT or 0) > 0.6 and range < 1 then
        local near = S.findTarget(w, u, range + 0.35)
        if near and near ~= tgt then
            u.blockedT = 0
            if u.order then u.order.target = near.id end
            return stepAttack(w, u, dt, near)
        end
        if (u.blockedT or 0) > 1.5 then
            local other = S.findTarget(w, u, u.def.acquire)
            u.blockedT = 0
            if other and other ~= tgt and u.order then u.order.target = other.id return true end
        end
    end
    stepMove(w, u, dt, nil, nil, tgt, range)
    return true
end

-- ------------------------------------------------------------------ abilities

-- hero abilities live in Heroes.lua

-- ------------------------------------------------------------------ gathering

local function nearestDropoff(w, u)
    local best, bd
    for _, e in ipairs(w.list) do
        if e.kind == "building" and e.owner == u.owner and alive(e) and e.built and e.def.dropoff then
            local d = edgeDist(u.x, u.y, e)
            if not bd or d < bd then best, bd = e, d end
        end
    end
    return best
end
S.nearestDropoff = nearestDropoff

local function nearestMine(w, x, y, maxD, owner)
    local best, bd
    for _, e in ipairs(w.list) do
        local hb = e.kind == "mine" and e.haunted and w.ents[e.haunted]
        if hb and not alive(hb) then e.haunted, hb = nil, nil end
        if e.kind == "mine" and alive(e) and e.gold > 0 and (not hb or (owner and hb.owner == owner)) then
            local d = dist(x, y, e.x, e.y)
            if (not maxD or d <= maxD) and (not bd or d < bd) then best, bd = e, d end
        end
    end
    return best
end
S.nearestMine = nearestMine

local function treeRect(w, i)
    local x, y = (i - 1) % w.w + 1, floor((i - 1) / w.w) + 1
    return { kind = "tree", tx = x, ty = y, size = 1, x = x - 0.5, y = y - 0.5, id = -i }
end

local function stepGather(w, u, dt, o)
    local st = o.state
    if not st then
        if u.carry and u.carry.res ~= o.res then st = "return"
        elseif u.carry and u.carry.amt >= S.tripSize(w, u, o.res) then st = "return"
        else st = o.res == "gold" and "toMine" or "toTree" end
        o.state = st
    end
    if st == "toMine" and u.def.lumberOnly then o.res, o.state = "lumber", "toTree" return end
    if u.def.haunt then
        if o.res ~= "gold" and u.def.wispHarvest then return S.stepWispWood(w, u, dt, o, stepMove) end
        if o.res ~= "gold" then
            event(w, { t = "error", owner = u.owner, text = "Acolytes can't harvest lumber. Ghouls do that." })
            u.order = nil
            return
        end
        return S.stepHaunt(w, u, dt, o, stepMove)
    end
    if st == "toMine" then
        local m = w.ents[o.mine or 0]
        if m and m.kind == "building" and m.mine then m = w.ents[m.mine] end
        if not alive(m) or m.gold <= 0 or m.haunted then
            m = nearestMine(w, u.x, u.y, 20, u.owner)
            if not m then u.order = nil return end
            o.mine = m.id
        end
        u.lastMine = m.id
        if stepMove(w, u, dt, nil, nil, m, 0.35) then
            if not m.inside then
                m.inside = u.id
                u.hidden = true
                u.insideT = D.MINE_TIME
                o.state = "inMine"
                u.path = nil
            else
                u.anim = "stand"
            end
        end
    elseif st == "inMine" then
        local m = w.ents[o.mine or 0]
        u.insideT = u.insideT - dt
        if not alive(m) then u.hidden = false o.state = nil return end
        if u.insideT <= 0 then
            local amt = min(D.GOLD_TRIP, m.gold)
            m.gold = m.gold - amt
            m.inside = nil
            u.hidden = false
            u.carry = { res = "gold", amt = amt }
            -- step out on the side facing home
            local hall = nearestDropoff(w, u)
            if hall then
                local bestT, bd
                for yy = m.ty - 1, m.ty + m.size do
                    for xx = m.tx - 1, m.tx + m.size do
                        if M.walkable(w, xx, yy) then
                            local d = dist(xx - 0.5, yy - 0.5, hall.x, hall.y)
                            if not bd or d < bd then bestT, bd = { xx, yy }, d end
                        end
                    end
                end
                if bestT then u.x, u.y = bestT[1] - 0.5, bestT[2] - 0.5 u.px, u.py = u.x, u.y end
            end
            o.state = "return"
            if m.gold <= 0 then
                event(w, { t = "mineEmpty", x = m.x, y = m.y })
                S.kill(w, m)
            end
            if u.nextOrder then local n = u.nextOrder u.nextOrder = nil S.issue(w, u, n) end
        end
    elseif st == "toTree" then
        if not o.tree or not w.trees[o.tree] then
            o.tree = M.nearestTree(w, u.x, u.y, 14)
            if not o.tree then if u.carry then o.state = "return" else u.order = nil end return end
        end
        u.lastTree = o.tree
        local tr = treeRect(w, o.tree)
        if stepMove(w, u, dt, nil, nil, tr, 0.4) then
            o.state = "chop"
            u.chopT = 0
            u.facing = atan2(tr.y - u.y, tr.x - u.x)
        elseif u.path == nil and u.moved == false then
            -- couldn't get there: try another tree
            o.tree = nil
        end
    elseif st == "chop" then
        if not w.trees[o.tree or 0] then
            o.state = "toTree"
            o.tree = M.nearestTree(w, u.x, u.y, 8)
            return
        end
        u.anim = "work"
        u.chopT = (u.chopT or 0) + dt
        local chopTime = u.def.chopTime or D.CHOP_TIME
        if u.chopT >= chopTime then
            u.chopT = u.chopT - chopTime
            u.carry = u.carry or { res = "lumber", amt = 0 }
            local take = min(u.def.chop or 1, w.trees[o.tree])
            u.carry.amt = u.carry.amt + take
            w.trees[o.tree] = w.trees[o.tree] - take
            if w.trees[o.tree] <= 0 then
                M.removeTree(w, o.tree)
                event(w, { t = "treeFell", tree = o.tree })
            end
            if u.carry.amt >= S.tripSize(w, u, "lumber") then o.state = "return" end
        end
    elseif st == "return" then
        if not u.carry then o.state = nil return end
        local hall = S.dropoffFor(w, u, u.carry.res)
        if not hall then u.anim = "stand" return end
        if stepMove(w, u, dt, nil, nil, hall, 0.35) then
            local pl = w.players[u.owner]
            local res, amt = u.carry.res, u.carry.amt
            -- upkeep: a big army means less of each gold trip reaches the treasury
            if res == "gold" then
                local full = amt
                amt = floor(amt * S.upkeep(w, u.owner) + 0.5)
                pl.stats.upkeepLost = (pl.stats.upkeepLost or 0) + (full - amt)
            end
            pl[res] = pl[res] + amt
            pl.stats[res] = pl.stats[res] + amt
            u.carry = nil
            event(w, { t = "deposit", unit = u.id, res = res, amt = amt, owner = u.owner, x = hall.x, y = hall.y })
            o.state = o.res == "gold" and "toMine" or "toTree"
            if o.res ~= res then o.state = nil end
        end
    end
end

-- ------------------------------------------------------------------ building

local function stepBuild(w, u, dt, o)
    local def = D.Buildings[o.bid]
    local site = { kind = "building", tx = o.tx, ty = o.ty, size = def.size, x = o.tx - 1 + def.size / 2, y = o.ty - 1 + def.size / 2, id = -1 }
    -- a worker that can't get to the spot for half a minute gives up (and the money comes back)
    o.startT = o.startT or w.time
    if w.time - o.startT > 30 or u.stuck then
        refund(w, u.owner, def)
        o.paid = false
        u.order = o.after
        event(w, { t = "error", owner = u.owner, text = "The worker can't reach the building site." })
        return
    end
    if stepMove(w, u, dt, nil, nil, site, def.onMine and 1.0 or 0.6) then
        local okPlace, whyPlace = S.canPlaceFor(w, u.owner, o.bid, o.tx, o.ty)
        if not okPlace then
            refund(w, u.owner, def)
            o.paid = false
            u.order = nil
            event(w, { t = "error", owner = u.owner, text = whyPlace == "Can't build there." and "Can't build there - something is in the way." or whyPlace })
            return
        end
        local b = S.addBuilding(w, u.owner, o.bid, o.tx, o.ty, false)
        o.placed = true
        event(w, { t = "placed", unit = b.id, owner = u.owner })
        if def.summoned then
            -- Undead: the Acolyte summons it and walks away; it builds itself.
            -- Night Elves: the Wisp turns into the building.
            S.startSummoning(w, b)
            if def.consumeBuilder and S.consumeBuilder then S.consumeBuilder(w, u, b) return end
            u.order = o.after
            u.anim, u.animT = "cast", 0.8
            return
        end
        b.builder = u.id
        u.order = { type = "construct", b = b.id, after = o.after }
    end
end

local function stepConstruct(w, u, dt, o)
    local b = w.ents[o.b]
    if not alive(b) or b.built or b.selfBuild then u.order = o.after return end
    if gap(u, b) > 0.7 then stepMove(w, u, dt, nil, nil, b, 0.6) return end
    u.facing = atan2(b.y - u.y, b.x - u.x)
    u.anim = "work"
    b.builder = u.id
    local inc = dt / b.def.time * (w.players[u.owner].buildSpeed or 1)   -- buildSpeed: testing option
    -- WC3 power-building: extra Peasants on the same site speed it up (Orcs build with one Peon)
    if b.buildTick == w.time then
        if w.players[u.owner].faction ~= "alliance" then return end
        inc = inc * 0.6
    end
    b.buildTick = w.time
    b.progress = min(1, b.progress + inc)
    b.hp = min(b.maxhp, b.hp + b.maxhp * 0.9 * inc)
    b.lastBuilt = w.time
    if b.progress >= 1 then
        b.built = true
        b.hp = max(b.hp, floor(b.maxhp * 0.98))
        w.players[b.owner].stats.built = w.players[b.owner].stats.built + 1
        event(w, { t = "built", unit = b.id, owner = b.owner })
        S.updateSupply(w)
        u.order = o.after
    end
end

-- ------------------------------------------------------------------ the unit tick

local function stepUnit(w, u, dt)
    u.moved = false
    if not u.order and u.queue then
        u.order = table.remove(u.queue, 1)
        if #u.queue == 0 then u.queue = nil end
        u.repath = 0
    end
    if u.cd > 0 then u.cd = u.cd - dt end
    if u.animT then u.animT = u.animT - dt if u.animT <= 0 then u.animT = nil end end
    if u.slow > 0 then u.slow = u.slow - dt end
    if S.stepReincarnate(w, u, dt) then return end
    S.stepHero(w, u, dt)
    if not alive(u) then return end
    if S.stepCaster(w, u, dt) then return end
    if not alive(u) then return end
    if u.channel then return end
    -- everything alive regenerates slowly (trolls much faster with Troll Regeneration)
    -- (machines don't: WC3 regenType "none" for Flying Machines, Siege Engines and Demolishers)
    if not u.def.hero and not u.def.summon and not u.def.noRegen and u.hp < u.maxhp and u.owner <= 2 then
        -- Undead heal only on blight (WC3 regenType "blight"), and quickly there
        if u.def.blightRegen then
            if S.onBlight(w, u) then u.hp = min(u.maxhp, u.hp + u.def.blightRegen * dt) end
        else
            u.hp = min(u.maxhp, u.hp + (D.REGEN + (S.bonus(w, u).regen or 0)) * dt)
        end
    elseif u.def.hero and u.def.blightRegen and u.hp < u.maxhp and S.onBlight(w, u) then
        u.hp = min(u.maxhp, u.hp + u.def.blightRegen * dt)
    end
    S.stepMilitia(w, u, dt)
    -- wounded units patch themselves up at home once out of the fight
    if u.hp < u.maxhp and u.owner >= 1 and u.owner <= 2 and (w.time - (u.hitT or -99)) > 5 then
        local home = w.players[u.owner].home
        if home and abs(u.x - home[1]) < 9 and abs(u.y - home[2]) < 9 then
            u.hp = min(u.maxhp, u.hp + u.maxhp * 0.02 * dt)
        end
    end
    if u.stun > 0 then
        u.stun = u.stun - dt
        u.anim = "stun"
        u.swing = nil
        return
    end
    finishSwing(w, u, dt)
    local o = u.order

    -- neutral creeps never wander far from their camp
    if u.camp then
        local d = dist(u.x, u.y, u.camp[1], u.camp[2])
        if (o and o.type == "leash") or d > 8 then
            if not o or o.type ~= "leash" then u.order = { type = "leash" } o = u.order end
            u.hp = min(u.maxhp, u.hp + u.maxhp * 0.08 * dt)
            if stepMove(w, u, dt, u.camp[1], u.camp[2], nil, 1) then u.order = nil end
            return
        end
    end

    if not o or o.type == "hold" then
        if not u.animT then u.anim = "stand" end
        if canAttack(u) and not u.def.worker and not u.sleeping and not u.channel then
            -- look around for something to fight
            u.scanT = (u.scanT or 0) - dt
            if u.scanT <= 0 then
                u.scanT = 0.3 + (u.id % 3) * 0.1
                local rng = S.rangeOf(w, u)
                local range = (o and o.type == "hold") and rng or u.def.acquire
                if rng > range then range = rng end
                local tgt = S.findTarget(w, u, range)
                if tgt then
                    if o and o.type == "hold" then
                        o.target = tgt.id
                    else
                        u.order = { type = "attack", target = tgt.id, auto = true, home = { u.x, u.y } }
                    end
                end
            end
            if o and o.type == "hold" and o.target then
                if not stepAttack(w, u, dt, w.ents[o.target]) then o.target = nil end
            end
        end
        return
    end

    local t = o.type
    -- wards and other units without a weapon can't attack-move or attack
    if (t == "amove" or t == "attack") and not canAttack(u) then
        if t == "amove" and u.def.speed and u.def.speed > 0 then o.type, t = "move", "move" else u.order = nil return end
    end
    if t == "move" then
        if stepMove(w, u, dt, o.x, o.y, nil, 0.15) then u.order = nil end
        -- the spot is crowded: close enough is good enough
        if u.order and (u.blockedT or 0) > 0.5 and dist(u.x, u.y, o.x, o.y) < 1.6 then u.order = nil end
        -- can't get there, or boxed in for a while: stop where we are
        if u.order and (u.stuck or (u.blockedT or 0) > 2.5) then u.order = nil u.anim = "stand" end
    elseif t == "amove" then
        if o.target then
            local tgt = w.ents[o.target]
            if not stepAttack(w, u, dt, tgt) then o.target = nil end
            -- something closer may come along
        else
            u.scanT = (u.scanT or 0) - dt
            if u.scanT <= 0 then
                u.scanT = 0.3
                local tgt = S.findTarget(w, u, max(u.def.acquire, S.rangeOf(w, u)))
                if tgt then o.target = tgt.id end
            end
            if not o.target and stepMove(w, u, dt, o.x, o.y, nil, 0.5) then u.order = nil end
            if u.order and not o.target and (u.blockedT or 0) > 0.5 and dist(u.x, u.y, o.x, o.y) < 1.8 then u.order = nil end
            if u.order and not o.target and (u.stuck or (u.blockedT or 0) > 2.5) then u.order = nil u.anim = "stand" end
        end
    elseif t == "patrol" then
        if o.target then
            if not stepAttack(w, u, dt, w.ents[o.target]) then o.target = nil u.repath = 0 end
        else
            u.scanT = (u.scanT or 0) - dt
            if u.scanT <= 0 and canAttack(u) then
                u.scanT = 0.3
                local tgt = S.findTarget(w, u, max(u.def.acquire, S.rangeOf(w, u)))
                if tgt then o.target = tgt.id end
            end
            if not o.target then
                local arrived = stepMove(w, u, dt, o.x, o.y, nil, 0.5)
                if not arrived and dist(u.x, u.y, o.x, o.y) < 1.8 and (u.blockedT or 0) > 0.5 then arrived = true end
                if arrived or u.stuck then
                    o.i = o.i % #o.pts + 1
                    o.x, o.y = o.pts[o.i][1], o.pts[o.i][2]
                    u.path, u.stuck, u.blockedT, u.repath = nil, nil, 0, 0
                end
            end
        end
    elseif t == "follow" then
        local tgt = w.ents[o.target or 0]
        if not alive(tgt) or tgt.hidden or (tgt.owner ~= u.owner and not S.visibleTo(w, u.owner, tgt)) then
            u.order = nil
            u.anim = "stand"
        else
            if gap(u, tgt) > 0.9 then
                stepMove(w, u, dt, nil, nil, tgt, 0.6)
                u.stuck = nil
            else
                u.path = nil
                if not u.animT then u.anim = "stand" end
            end
        end
    elseif t == "attack" then
        local tgt = w.ents[o.target or 0]
        if o.auto then
            -- auto-acquired targets: switch to something closer now and then, and don't chase forever
            if o.home and dist(u.x, u.y, o.home[1], o.home[2]) > 14 then u.order = nil return end
            u.scanT = (u.scanT or 0) - dt
            if u.scanT <= 0 and alive(tgt) and gap(u, tgt) > S.rangeOf(w, u) + 0.5 then
                u.scanT = 0.5
                local near = S.findTarget(w, u, u.def.acquire)
                if near and near.kind == "unit" then o.target = near.id tgt = near end
            end
        end
        if not stepAttack(w, u, dt, tgt) then
            u.order = nil
            u.scanT = 0
        end
        -- an auto-picked target we can't reach isn't worth running at
        if u.order and o.auto and u.stuck then u.order = nil u.anim = "stand" end
    elseif t == "gather" then
        stepGather(w, u, dt, o)
    elseif t == "build" then
        stepBuild(w, u, dt, o)
    elseif t == "garrison" then
        if not S.stepGarrison(w, u, dt, o, stepMove) then if u.order == o then u.order = nil end end
    elseif t == "toArms" then
        if not S.stepToArms(w, u, dt, o, stepMove) then if u.order == o then u.order = nil end end
    elseif t == "toWork" then
        if not S.stepToWork(w, u, dt, o, stepMove) then if u.order == o then u.order = nil end end
    elseif t == "repair" then
        if not S.stepRepair(w, u, dt, o, stepMove) then u.order = nil end
    elseif t == "pickup" then
        if not S.stepPickup(w, u, dt, o, stepMove) then u.order = nil end
    elseif t == "construct" then
        stepConstruct(w, u, dt, o)
    elseif t == "cast" then
        if not S.stepCast(w, u, dt, o, stepMove) then u.order = nil end
    elseif t == "stop" then
        u.order = nil
    end
end

-- keep units from standing inside each other or inside blocked tiles
local function separate(w)
    local cell = {}
    local units = {}
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and not u.dead and not u.hidden then
            units[#units + 1] = u
            local k = floor(u.x / 2) * 100 + floor(u.y / 2)
            local c = cell[k]
            if not c then c = {} cell[k] = c end
            c[#c + 1] = u
        end
    end
    -- Like Warcraft III: a unit that is standing still (fighting, working, waiting) is planted and
    -- hardly moves; units walking past slide around it instead of shoving it out of the way.
    for _, u in ipairs(units) do
        local cx, cy = floor(u.x / 2), floor(u.y / 2)
        for ox = -1, 1 do
            for oy = -1, 1 do
                local c = cell[(cx + ox) * 100 + cy + oy]
                if c then
                    for _, v in ipairs(c) do
                        -- workers walk through each other, as in Warcraft III (no jams at the mine);
                        -- flyers only bump into other flyers
                        -- (a Wind Walking Blademaster passes through units)
                        if v.id > u.id and (u.def.air and true or false) == (v.def.air and true or false)
                           and not (u.buffs and u.buffs.windWalk) and not (v.buffs and v.buffs.windWalk)
                           and not (u.def.worker and v.def.worker and u.order and v.order
                                    and u.order.type == "gather" and v.order.type == "gather") then
                            local dx, dy = v.x - u.x, v.y - u.y
                            local d = sqrt(dx * dx + dy * dy)
                            local want = u.def.radius + v.def.radius
                            if d < want then
                                if d < 0.01 then dx, dy, d = (u.id % 2 == 0) and 0.05 or -0.05, 0.03, 0.06 end
                                local nx, ny = dx / d, dy / d
                                local push = want - d
                                local wu = u.moved and 1 or 0.06
                                local wv = v.moved and 1 or 0.06
                                if not u.moved and not v.moved then wu, wv = 0.25, 0.25 end
                                local tot = wu + wv
                                local pu, pv = push * wu / tot, push * wv / tot
                                u.x, u.y = u.x - nx * pu, u.y - ny * pu
                                v.x, v.y = v.x + nx * pv, v.y + ny * pv
                                -- a walker bumping into something planted steps sideways around it
                                if u.moved ~= v.moved then
                                    local mover = u.moved and u or v
                                    local sgn = u.moved and -1 or 1      -- direction from the planted unit to the mover
                                    local ax, ay = nx * sgn, ny * sgn
                                    local tx, ty = -ay, ax
                                    local fx, fy = cos(mover.facing or 0), sin(mover.facing or 0)
                                    if tx * fx + ty * fy < 0 then tx, ty = -tx, -ty end
                                    -- only when it's actually walking into the other unit
                                    local into = -(ax * fx + ay * fy)
                                    local slide = into > 0.2 and push * 0.5 * into or 0
                                    mover.x, mover.y = mover.x + tx * slide, mover.y + ty * slide
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- out of walls
    for _, u in ipairs(units) do
        local tx, ty = M.tileOf(u.x, u.y)
        if not u.def.air and not M.walkable(w, tx, ty) then
            local nx, ny = M.nearestOpen(w, tx, ty, 3)
            if nx then
                local gx, gy = nx - 0.5, ny - 0.5
                local dx, dy = gx - u.x, gy - u.y
                local d = sqrt(dx * dx + dy * dy)
                local s = min(d, 0.25)
                if d > 0 then u.x, u.y = u.x + dx / d * s, u.y + dy / d * s end
            end
        end
        u.x = max(0.3, min(w.w - 0.3, u.x))
        u.y = max(0.3, min(w.h - 0.3, u.y))
    end
end

local function stepBuilding(w, b, dt)
    if not b.built then
        if b.selfBuild then S.stepSummoning(w, b, dt) end
        return
    end
    -- frozen by a Frost Wyrm's Freezing Breath: no training, research or attacking
    if b.frozenT and b.frozenT > w.time then return end
    if b.queue[1] then
        local info = b.qinfo and b.qinfo[1]
        local _, qd = S.queueItem(b.queue[1])
        b.trainT = b.trainT + dt * ((w.players[b.owner] and w.players[b.owner].buildSpeed) or 1)
        if b.trainT >= ((info and info.time) or (qd and qd.time) or 20) then
            S.finishQueueItem(w, b)
        end
    end
    local atk = b.def.attack
    if atk and not S.clouded(w, b) and not (atk.garrison and #(b.garrison or {}) == 0) then
        if b.cd > 0 then b.cd = b.cd - dt end
        if b.cd <= 0 then
            local best, bd
            for _, e in ipairs(w.list) do
                if e.kind == "unit" and alive(e) and S.isEnemy(b, e) and not e.hidden and S.targetable(w, b, e) and (e.def.air and atk.hitsAir or (not e.def.air and atk.hitsGround)) then
                    local d = edgeDist(e.x, e.y, b)
                    if d <= atk.range and (not bd or d < bd) then best, bd = e, d end
                end
            end
            -- Guard, Arcane and Watch Towers (and manned Burrows) shoot buildings when no unit is in range
            if not best and atk.hitsBuildings then
                for _, e in ipairs(w.list) do
                    if e.kind == "building" and alive(e) and S.isEnemy(b, e) and e.owner >= 1 and e.owner <= 2 then
                        local d = S.edgeDist(b.x, b.y, e) - b.size / 2
                        if d <= atk.range and (not bd or d < bd) then best, bd = e, d end
                    end
                end
            end
            if best then
                b.cd = S.buildingAttackCd(w, b, atk)
                local slow = atk.missile == "shell"
                w.missiles[#w.missiles + 1] = { x = b.x, y = b.y - 0.8, target = best.id, src = b.id, dmg = rand(w, atk.dmin, atk.dmax),
                    atype = atk.atype, speed = slow and 10 or 16, kind = atk.missile, owner = b.owner,
                    wp = { atype = atk.atype, splash = atk.splash, splashF = atk.splashF, splashQ = atk.splashQ, splashH = atk.splashH,
                           splashQf = atk.splashQf, splashBuildings = atk.splashBuildings, friendlyFire = atk.friendlyFire } }
            end
        end
    end
end

local function stepMissiles(w, dt)
    local keep = {}
    for _, m in ipairs(w.missiles) do
        local tgt = w.ents[m.target]
        if alive(tgt) then
            local dx, dy = tgt.x - m.x, tgt.y - m.y
            local d = sqrt(dx * dx + dy * dy)
            local step = m.speed * dt
            if d <= step + (tgt.kind == "unit" and 0.2 or tgt.size / 2) then
                local src = w.ents[m.src]
                if m.stun and tgt.kind == "unit" then S.stunUnit(w, tgt, m.stun) end
                if m.impact then
                    event(w, { t = "effect", x = tgt.x, y = tgt.y, model = m.impact, size = 1.6, life = 0.8 })
                    event(w, { t = "vfx", kind = "impact", x = tgt.x, y = tgt.y, c = "lightning", n = 16, r = 1.1, ring = 1.2 })
                end
                if m.spell or not m.wp then
                    S.damage(w, alive(src) and src or nil, tgt, m.dmg, m.atype, m.spell)
                else
                    S.land(w, alive(src) and src or nil, tgt, m.dmg, m.wp, m.owner)
                end
            else
                m.x, m.y = m.x + dx / d * step, m.y + dy / d * step
                m.angle = atan2(dy, dx)
                keep[#keep + 1] = m
            end
        end
    end
    w.missiles = keep
end

-- ------------------------------------------------------------------ vision

local circles = {}
local function circle(r)
    r = floor(r)
    if circles[r] then return circles[r] end
    local out = {}
    for y = -r, r do for x = -r, r do if x * x + y * y <= r * r + r then out[#out + 1] = { x, y } end end end
    circles[r] = out
    return out
end

function S.updateVision(w)
    local W, H = w.w, w.h
    for p = 1, 2 do w.players[p].visible = {} end
    for _, e in ipairs(w.list) do
        if alive(e) and e.owner >= 1 and e.owner <= 2 and not e.hidden then
            local pl = w.players[e.owner]
            local vis, exp = pl.visible, pl.explored
            local cx, cy = M.tileOf(e.x, e.y)
            local sight = S.sightOf(w, e)
            -- WC3 high ground: from the ground you can't see up onto higher cliffs (flyers can)
            local L = w.layer
            local lim = L and next(L) and not e.def.air and (L[(cy - 1) * W + cx] or 0) or nil
            for _, o in ipairs(circle(sight)) do
                local x, y = cx + o[1], cy + o[2]
                if x >= 1 and y >= 1 and x <= W and y <= H then
                    local i = (y - 1) * W + x
                    if not lim or (L[i] or 0) <= lim then
                        vis[i] = true
                        exp[i] = true
                    end
                end
            end
        end
    end
    for _, r in ipairs(w.reveals or {}) do
        local pl = w.players[r.owner]
        if pl then
            local cx, cy = M.tileOf(r.x, r.y)
            for _, o in ipairs(circle(r.r)) do
                local x, y = cx + o[1], cy + o[2]
                if x >= 1 and y >= 1 and x <= W and y <= H then
                    local i = (y - 1) * W + x
                    pl.visible[i] = true
                    pl.explored[i] = true
                end
            end
        end
    end    S.updateDetection(w)
end

function S.visibleTo(w, p, e)
    if not e then return false end
    if e.owner == p then return true end
    local pl = w.players[p]
    if e.kind == "unit" and (e.devouredBy or (S.isInvisible(e) and not S.detected(w, p, e))) then return false end
    if w.noFog then return true end
    if e.kind == "unit" or e.kind == "item" then
        local tx, ty = M.tileOf(e.x, e.y)
        return pl.visible[(ty - 1) * w.w + tx] == true
    end
    -- buildings and mines: seen once explored
    for yy = e.ty, e.ty + e.size - 1 do
        for xx = e.tx, e.tx + e.size - 1 do
            if pl.explored[(yy - 1) * w.w + xx] then return true end
        end
    end
    return false
end

-- ------------------------------------------------------------------ the main tick

function S.step(w, dt)
    dt = dt or D.TICK
    if w.over then return end
    w.time = w.time + dt
    w.pathBudget, w.nodeBudget = 10, 2500
    if w.time % 5 < dt then w.pathCache = nil end
    for _, e in ipairs(w.list) do
        e.px, e.py = e.x, e.y
    end
    -- the score screen's graph: army size every 15 seconds
    if w.time >= (w.histT or 0) then
        w.histT = (w.histT or 0) + 15
        for p = 1, 2 do
            local st = w.players[p].stats
            if st and st.hist then st.hist[#st.hist + 1] = { w.time, w.players[p].army or 0, st.gold + st.lumber } end
        end
    end
    local n = #w.list
    for i = 1, n do
        local e = w.list[i]
        if not e.removed then
            if e.dead then
                if e.kind == "unit" then
                    e.deadT = e.deadT + dt
                    if e.deadT > 6 then e.removed = true end
                end
            elseif e.kind == "unit" then
                stepUnit(w, e, dt)
            elseif e.kind == "building" then
                stepBuilding(w, e, dt)
            end
        end
    end
    -- several passes, so a crowd is fully pushed apart every tick: no unit stands inside another
    separate(w)
    separate(w)
    separate(w)
    -- how far each unit really got this tick (for noticing when it is stuck behind others)
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and not u.dead then
            if u.moved then
                local want = u.def.speed * dt
                local got = dist(u.x, u.y, u.px, u.py)
                if got < want * 0.3 then
                    u.blockedT = (u.blockedT or 0) + dt
                    -- shuffling on the spot looks wrong: stand while blocked
                    if u.blockedT > 0.4 then u.anim = "stand" end
                    if u.blockedT > 1.0 and u.blockedT - dt <= 1.0 then u.path = nil end   -- look for another way
                else
                    u.blockedT = 0
                end
            else
                u.blockedT = 0
            end
        end
    end
    stepMissiles(w, dt)
    S.stepDots(w, dt)
    S.stepAreas(w, dt)
    S.stepNeutral(w, dt)
    S.stepRules(w, dt)
    if S.stepUndead then S.stepUndead(w, dt) end

    -- tidy up removed entities now and then
    w.tidyT = (w.tidyT or 0) + dt
    if w.tidyT > 2 then
        w.tidyT = 0
        local keep = {}
        for _, e in ipairs(w.list) do
            if e.removed then w.ents[e.id] = nil else keep[#keep + 1] = e end
        end
        w.list = keep
    end

    w.visT = (w.visT or 0) - dt
    if w.visT <= 0 then
        w.visT = 0.4
        S.updateVision(w)
    end

    -- victory: a side with no buildings left loses
    w.winT = (w.winT or 0) - dt
    if w.winT <= 0 then
        w.winT = 1
        local count = { 0, 0 }
        for _, e in ipairs(w.list) do
            if (e.kind == "building" or e.def.rootsTo) and alive(e) and e.owner >= 1 and e.owner <= 2 then count[e.owner] = count[e.owner] + 1 end
        end
        if count[1] == 0 or count[2] == 0 then
            w.over = true
            w.winner = count[1] == 0 and (count[2] == 0 and 0 or 2) or 1
            event(w, { t = "gameOver", winner = w.winner })
        end
    end
end

-- debug: a pile of units fighting in the middle (performance test)
function S.stress(w, n)
    local F1, F2 = D.Factions[w.players[1].faction], D.Factions[w.players[2].faction]
    local melee1 = w.players[1].faction == "alliance" and "footman" or "grunt"
    local ranged1 = w.players[1].faction == "alliance" and "rifleman" or "headhunter"
    local melee2 = w.players[2].faction == "alliance" and "footman" or "grunt"
    local ranged2 = w.players[2].faction == "alliance" and "rifleman" or "headhunter"
    local made = {}
    for i = 1, n do
        local row, col = floor((i - 1) / 8), (i - 1) % 8
        local a = S.addUnit(w, 1, i % 3 == 0 and ranged1 or melee1, 26 + col * 0.9, 38 + row * 0.9)
        local b = S.addUnit(w, 2, i % 3 == 0 and ranged2 or melee2, 30 + col * 0.9, 26 - row * 0.9)
        made[#made + 1] = a
        S.issue(w, b, { type = "amove", x = 30, y = 40 })
    end
    S.updateSupply(w)
    return made
end
