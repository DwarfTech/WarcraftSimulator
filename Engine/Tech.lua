-- Skirmish engine: the Warcraft III tech tree on top of the simulation. Research levels and what
-- they do, hall and tower upgrades, which weapon can hit what (ground / air / buildings), splash,
-- Call to Arms, Defend, War Drums, upkeep, and the special effects of each research.

local _, ns = ...
local E = ns.Engine
local D, M, S = E.Data, E.Map, E.Sim

local floor, abs, max, min, sqrt, atan2 = math.floor, math.abs, math.max, math.min, math.sqrt, math.atan2
local EMPTY = {}

local function alive(e) return e and not e.dead and not e.removed end
local function dist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return sqrt(dx * dx + dy * dy) end

-- ------------------------------------------------------------------ research levels & bonuses

function S.level(w, p, rid)
    local pl = w.players[p]
    return pl and pl.research and pl.research[rid] or 0
end

-- Rebuild a player's per-unit bonuses from their research. Called whenever research finishes.
function S.recalc(w, p)
    local pl = w.players[p]
    pl.research = pl.research or {}
    pl.bonus = {}
    pl.masonry, pl.spikes, pl.lumberLv = 0, 0, 0
    pl.reinforced, pl.pillage = false, false
    for rid, lv in pairs(pl.research) do
        local r = D.Research[rid]
        local e = r.effect
        if e == "masonry" then pl.masonry = lv
        elseif e == "spikes" then pl.spikes = lv
        elseif e == "lumber" then pl.lumberLv = lv
        elseif e == "reinforced" then pl.reinforced = true
        elseif e == "pillage" then pl.pillage = true
        end
        for _, uid in ipairs(r.units or EMPTY) do
            local b = pl.bonus[uid]
            if not b then b = { dice = 0, armor = 0, hp = 0, dmg = 0, range = 0, regen = 0, flags = {} } pl.bonus[uid] = b end
            if e == "melee" or e == "ranged" then b.dice = b.dice + lv
            elseif e == "armor" then b.armor = b.armor + 2 * lv       -- UnitBalance defUp = 2 on every unit
            elseif e == "hp" then
                b.hp = b.hp + (rid == "animalWar" and 150 or 100)
                if rid == "berserkerStr" then b.dmg = b.dmg + 3 end
            elseif e == "range" then b.range = b.range + 200 / 128
            elseif e == "regen" then b.regen = b.regen + 0.8           -- Troll Regeneration (UpgradeData Rotr rhpr .8)
            elseif e == "caster" then
                local mana, regen, hp = S.casterBonus(rid, lv)
                b.mana, b.manaRegen, b.hp = (b.mana or 0) + mana, (b.manaRegen or 0) + regen, b.hp + hp
            else b.flags[e] = true end
        end
    end
end

function S.bonus(w, e)
    local pl = w.players[e.owner]
    return pl and pl.bonus and pl.bonus[e.def.id] or EMPTY
end

-- armour value and armour type, after upgrades
function S.armorOf(w, e)
    local def = e.def
    local pl = w.players[e.owner]
    if e.kind == "building" then
        local a = def.armor or 5
        if pl and pl.masonry then a = a + 1 * pl.masonry end    -- Masonry: building defUp is 1 per level
        local t = def.dtype or "fortified"
        if pl and pl.reinforced and (def.id == "watchTower" or def.id == "burrow") then t = "fortified" end
        return a, t
    end
    local b = S.bonus(w, e)
    local a = (def.armor or 0) + (b.armor or 0)
    if S.heroArmorBonus then a = a + S.heroArmorBonus(e) end
    return a, def.dtype or "medium"
end

function S.hpBonus(w, p, uid)
    local pl = w.players[p]
    local b = pl and pl.bonus and pl.bonus[uid]
    return b and b.hp or 0
end

-- ------------------------------------------------------------------ weapons

local function mainWeapon(def)
    if def.weapon1 then return def.weapon1 end
    local base, dice, sides = def.base, def.dice, def.sides
    if not base then base, dice, sides = def.dmin - 1, 1, (def.dmax - def.dmin + 1) end
    def.weapon1 = { atype = def.atype or "normal", base = base, dice = dice or 1, sides = sides or 1, cd = def.cd, range = def.range,
        splash = def.splash, splashF = def.splashF, splashQ = def.splashQ, splashH = def.splashH, splashQf = def.splashQf,
        splashBuildings = def.splashBuildings, minRange = def.minRange, friendlyFire = def.friendlyFire, missile = def.missile, hitsGround = def.hitsGround, hitsAir = def.hitsAir, hitsBuildings = def.hitsBuildings,
        dmgpt = def.dmgpt or 0.4 }
    return def.weapon1
end

local function secondWeapon(def)
    if def.weapon2w then return def.weapon2w end
    local w2 = def.weapon2
    if not w2 then return nil end
    def.weapon2w = { atype = w2.atype, base = w2.dmin - 1, dice = 1, sides = w2.dmax - w2.dmin + 1, cd = w2.cd, range = w2.range,
        hitsGround = w2.hitsGround, hitsAir = w2.hitsAir, hitsBuildings = w2.hitsBuildings, missile = def.missile or "bullet",
        dmgpt = w2.dmgpt or def.dmgpt or 0.4 }
    return def.weapon2w
end

local function covers(wp, tgt)
    if tgt.kind == "building" then return wp.hitsBuildings end
    if tgt.def.air and not (tgt.buffs and tgt.buffs.ensnare) then return wp.hitsAir end
    return wp.hitsGround
end

-- the weapon a unit would use on a target, or nil if it can't attack it at all
function S.weaponFor(w, u, tgt)
    local def = u.def
    if not def.dmin then return nil end
    local w1 = mainWeapon(def)
    if covers(w1, tgt) then return w1 end
    local w2 = secondWeapon(def)
    if w2 and (def.weapon2On or (S.bonus(w, u).flags and S.bonus(w, u).flags.weapon2)) and covers(w2, tgt) then return w2 end
    return nil
end

function S.canHit(w, u, tgt) return S.weaponFor(w, u, tgt) ~= nil end

function S.rangeOf(w, u, wp)
    wp = wp or mainWeapon(u.def)
    return wp.range + (S.bonus(w, u).range or 0)
end

-- roll the damage of one attack
function S.roll(w, u, wp)
    local b = S.bonus(w, u)
    local dice = (wp.dice or 1) + (wp == u.def.weapon1 and (b.dice or 0) or 0)
    local d = wp.base + (wp == u.def.weapon1 and (b.dmg or 0) or 0)
    for _ = 1, dice do d = d + 1 + w.rng.next() % max(1, wp.sides) end
    if u.def.hero then
        local _, _, _, main = S.heroStats(u)
        d = d + main
        if S.hasBuff(u, "avatar") then d = d + 20 end
    end
    if u.illusion then return 0 end
    if u.buffs and u.buffs.innerFire then d = d * 1.1 end
    if u.ib then d = d + u.ib.dmg end
    if u.aura and u.aura.dmg then d = d * (1 + u.aura.dmg) end
    if S.rollExtra then d = S.rollExtra(w, u, d) end
    -- War Drums: a friendly Kodo Beast nearby adds 10% (20% upgraded)
    local drums = S.drumsBonus(w, u)
    if drums > 0 then d = d * (1 + drums) end
    return floor(d + 0.5)
end

function S.drumsBonus(w, u)
    local pl = w.players[u.owner]
    if not pl or not pl.kodos or #pl.kodos == 0 then return 0 end
    for _, k in ipairs(pl.kodos) do
        if alive(k) and dist(k.x, k.y, u.x, u.y) <= 7 then
            return (S.bonus(w, k).flags and S.bonus(w, k).flags.drums) and 0.2 or 0.1
        end
    end
    return 0
end

-- ------------------------------------------------------------------ what happens when an attack lands

local function enemiesAround(w, src, x, y, r, air)
    local out = {}
    for _, e in ipairs(w.list) do
        if alive(e) and e.kind == "unit" and not e.hidden and S.isEnemy(src, e) and (air == nil or (e.def.air and true or false) == air) then
            if dist(e.x, e.y, x, y) <= r + e.def.radius then out[#out + 1] = e end
        end
    end
    return out
end

-- An attack (melee swing or missile) arriving at its target. hit = { dmg, atype, wp, src (entity or nil), owner }
function S.land(w, src, tgt, dmg, wp, owner)
    if not alive(tgt) then return end
    local atype = wp and wp.atype or "normal"
    local flags = src and src.kind == "unit" and S.bonus(w, src).flags or EMPTY
    local fake = src or { owner = owner }
    -- Fragmentation Shards: mortars hurt lightly armoured troops more
    if flags.frag and tgt.kind == "unit" and (tgt.def.dtype == "unarmored" or tgt.def.dtype == "medium") then dmg = dmg * 1.35 end
    -- Liquid Fire (Batriders): the building burns, can't be repaired and attacks slower
    if flags.liquidFire and tgt.kind == "building" then tgt.liquid, tgt.liquidSrc = 3, src and src.id end
    -- hero passives: Critical Strike, Bash, Wind Walk's backstab
    if src and src.kind == "unit" and alive(src) and (src.def.hero or src.def.bash or src.def.crit or src.def.onHit or src.def.id == "spellBreaker" or (src.ib and src.ib.orb)) then
        dmg = S.heroOnHit(w, src, tgt, dmg)
    end
    if src and src.illusion then dmg = 0 end
    -- Curse: a third of attacks miss
    if src and ((src.buffs and src.buffs.curse and w.rng.next() % 100 < 33)
            or (tgt.def and tgt.def.evasion and w.rng.next() % 100 < tgt.def.evasion)
            or (S.missExtra and S.missExtra(w, src, tgt))) then    -- Curse, creep Evasion, Drunken Haze / Brawler
        S.event(w, { t = "float", x = tgt.x, y = tgt.y - 1, text = "miss", color = { 1, 1, 1 } })
        return
    end
    S.damage(w, src, tgt, dmg, atype)
    if S.landExtra then S.landExtra(w, src, tgt, dmg, wp) end
    -- creep poison (Murloc Nightcrawler's Envenomed Weapons)
    if src and src.def and src.def.poisonHit and tgt.kind == "unit" and alive(tgt) and not tgt.def.mech then
        local ph = src.def.poisonHit
        tgt.poisonT, tgt.poisonOwner, tgt.poisonDps = tgt.def.hero and ph[3] or ph[2], src.id, ph[1]
    end
    local x, y = tgt.x, tgt.y
    -- WC3 splash: full damage inside the small ring, Hfact inside the middle ring, Qfact out to the
    -- edge; artillery hurts buildings too, and doesn't care whose units are standing there
    local splash = wp and wp.splash
    if splash and splash > 0 then
        local outer = max(splash, wp.splashQ or 0)
        local inner = wp.splashF or splash * 0.3
        local hFact, qFact = wp.splashH or 0.5, wp.splashQf or 0
        local function share(d)
            if d <= inner then return 1 elseif d <= splash then return hFact elseif d <= outer then return qFact end
            return 0
        end
        local air = tgt.def.air and true or false
        for _, e in ipairs(w.list) do
            if e ~= tgt and alive(e) and not e.hidden and e ~= src then
                local ok
                if e.kind == "unit" then
                    ok = (e.def.air and true or false) == air and (S.isEnemy(fake, e) or (wp.friendlyFire and e.owner == fake.owner))
                elseif e.kind == "building" then
                    ok = wp.splashBuildings and S.isEnemy(fake, e)
                end
                if ok then
                    local d = e.kind == "unit" and dist(e.x, e.y, x, y) or S.edgeDist(x, y, e)
                    local f = share(d)
                    if f > 0 then S.damage(w, src, e, dmg * f, atype) end
                end
            end
        end
    end
    -- Storm Hammers: the hammer carries on through the target, hurting enemies up to 200 behind it
    -- (within 50 of its path) for 80% damage
    if flags.splash and src and tgt.kind == "unit" then
        local dx, dy = x - src.x, y - src.y
        local d0 = max(0.01, sqrt(dx * dx + dy * dy))
        dx, dy = dx / d0, dy / d0
        for _, e in ipairs(enemiesAround(w, fake, x, y, 2, false)) do
            if e ~= tgt then
                local rx, ry = e.x - x, e.y - y
                local along = rx * dx + ry * dy
                if along > 0 and along <= 200 / 128 and abs(rx * dy - ry * dx) <= 50 / 128 + e.def.radius then
                    S.damage(w, src, e, dmg * 0.8, atype)
                end
            end
        end
    end
    -- Flak Cannons: flying machines hit every air unit near an air target
    if flags.airSplash and tgt.def.air then
        for _, e in ipairs(enemiesAround(w, fake, x, y, 1.3, true)) do
            if e ~= tgt then S.damage(w, src, e, dmg * 0.5, atype) end
        end
    end
    -- Pulverize: a Tauren blow sometimes hits everything around the target
    if flags.pulverize and w.rng.next() % 100 < 25 then
        S.event(w, { t = "effect", x = x, y = y, model = 165977, size = 2.2, life = 0.7 })
        for _, e in ipairs(enemiesAround(w, fake, x, y, 2.0, false)) do
            if e ~= tgt then S.damage(w, src, e, 60, "normal") end
        end
    end
    -- Envenomed Spears: poison
    -- (WC3 Aven: 4 dps for 25 s, 1 s on heroes, living targets only)
    if flags.poison and tgt.kind == "unit" and alive(tgt) and not tgt.def.mech then tgt.poisonT, tgt.poisonOwner, tgt.poisonDps = tgt.def.hero and 1 or 25, src and src.id, 4 end
    -- Burning Oil: the ground where a boulder lands burns for a while
    if flags.burn then
        w.fires = w.fires or {}
        w.fires[#w.fires + 1] = { x = x, y = y, r = 1.2, t = 5, owner = owner, src = src and src.id }
        -- (drawn as a burning patch on the ground; a looping fire model here flickered constantly)
    end
    -- Spiked Barricades: melee attackers of an Orc building get hurt
    if tgt.kind == "building" and src and src.kind == "unit" and alive(src) and src.def.range < 1 then
        local tp = w.players[tgt.owner]
        if tp and tp.spikes and tp.spikes > 0 then
            S.damage(w, nil, src, ({ 4, 10, 16 })[tp.spikes], "normal", true)
        end
    end
    -- Pillage: Orc peons, grunts and raiders take gold from the buildings they hit
    if tgt.kind == "building" and src and src.kind == "unit" then
        local sp = w.players[src.owner]
        if sp and sp.pillage and (src.def.id == "peon" or src.def.id == "grunt" or src.def.id == "raider") then
            local g = floor(dmg * 0.5)        -- AbilityData Asal DataA .5
            sp.gold = sp.gold + g
        end
    end
end

-- damage over time (poison, fire) each tick
function S.stepDots(w, dt)
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and alive(u) and u.poisonT and u.poisonT > 0 then
            u.poisonT = u.poisonT - dt
            u.poisonAcc = (u.poisonAcc or 0) + (u.poisonDps or 4) * dt
            if u.poisonAcc >= 1 then
                local n = floor(u.poisonAcc)
                u.poisonAcc = u.poisonAcc - n
                S.damage(w, w.ents[u.poisonOwner or 0], u, n, "normal", true)
            end
        end
    end
    if w.fires and #w.fires > 0 then
        local keep = {}
        for _, f in ipairs(w.fires) do
            f.t = f.t - dt
            if f.t > 0 then
                keep[#keep + 1] = f
                f.acc = (f.acc or 0) + 15 * dt
                if f.acc >= 1 then
                    local n = floor(f.acc)
                    f.acc = f.acc - n
                    for _, e in ipairs(enemiesAround(w, { owner = f.owner }, f.x, f.y, f.r, false)) do
                        S.damage(w, w.ents[f.src or 0], e, n, "normal", true)
                    end
                end
            end
        end
        w.fires = keep
    end
end

-- ------------------------------------------------------------------ requirements

-- does the player have this building (or a hall tier above it)?
function S.has(w, p, id)
    local has = w.players[p].has or EMPTY
    if has[id] then return true end
    for _, up in ipairs(D.Counts[id] or EMPTY) do if has[up] then return true end end
    return false
end

-- requirements of a unit, building or research level. Returns ok, the first thing missing.
function S.requirementMet(w, p, id, level)
    local def = D.def(id)
    if not def then return true end
    local req = def.requires
    if def.kind == "research" then req = def.requires[level or (S.level(w, p, id) + 1)] end
    if def.hero then
        -- WC3: the first hero is free to summon; the second needs tier 2, the third tier 3
        req = nil
    end
    for _, need in ipairs(req or EMPTY) do
        if not S.has(w, p, need) then return false, need end
    end
    return true
end

function S.needText(need)
    local d = D.def(need)
    return "Requires " .. (d and d.name or need) .. "."
end

-- ------------------------------------------------------------------ the training / research / upgrade queue
-- b.queue holds ids: a unit id, "r:<research>" or "u:<building to upgrade into>"; b.qinfo the costs.

function S.queueItem(q)
    local kind, id = q:match("^(%a):(.+)$")
    if kind == "r" then return "research", D.Research[id], id end
    if kind == "u" then return "upgrade", D.Buildings[id], id end
    return "unit", D.Units[q], q
end

-- the unit actually trained for a button (Berserkers replace Headhunters after the upgrade)
function S.trainId(w, p, uid)
    if uid == "headhunter" and S.level(w, p, "berserkerUp") > 0 then return "berserker" end
    return uid
end

local function payCost(w, p, g, l)
    local pl = w.players[p]
    if pl.gold < g then return false, "Not enough gold." end
    if pl.lumber < l then return false, "Not enough lumber." end
    pl.gold, pl.lumber = pl.gold - g, pl.lumber - l
    return true
end

function S.train(w, p, bId, uid)
    local b = w.ents[bId]
    if not alive(b) or b.owner ~= p or not b.built then return false end
    if b.upgrading then return false, "The building is being upgraded." end
    if b.unsummoning then return false, "It is being unsummoned." end
    if b.uprootT then return false, "It is uprooting." end
    uid = S.trainId(w, p, uid)
    local def = D.Units[uid]
    if #b.queue >= 7 then return false, "The queue is full." end
    local pl = w.players[p]
    local mult = 1
    local rec, time
    if def.hero then
        local allowed, why = S.heroAllowed(w, p, uid)
        if not allowed then return false, why end
        local ri
        rec, ri = S.deadHero(w, p, uid)
        if rec then
            local g, l, t = S.reviveCost(rec)
            mult, time = g / def.gold, t
        elseif S.heroCount(w, p) == 0 then
            mult = 0               -- WC3 (TFT): your first hero is free
        end
    end
    local ok, need = S.requirementMet(w, p, uid)
    if not ok then return false, S.needText(need) end
    if pl.used + def.supply > pl.cap then
        if pl.cap >= D.MAX_SUPPLY then return false, "Food is at its limit." end
        return false, "Not enough food. Build more " .. D.Buildings[D.Factions[pl.faction].farm].name .. "s."
    end
    local g, l = floor(def.gold * mult), floor((def.lumber or 0) * mult)
    if rec then l = 0 end
    local paid, why = payCost(w, p, g, l)
    if not paid then return false, why end
    b.queue[#b.queue + 1] = uid
    b.qinfo = b.qinfo or {}
    b.qinfo[#b.queue] = { gold = g, lumber = l, time = time or def.time, rec = rec }
    if rec then
        local _, ri = S.deadHero(w, p, uid)
        table.remove(pl.deadHeroes, ri)
    end
    S.updateSupply(w)
    return true
end

-- the cost of the next level of a research
function S.researchCost(w, p, rid)
    local r = D.Research[rid]
    local lv = S.level(w, p, rid) + 1
    if lv > r.levels then return nil end
    return r.gold[lv], r.lumber[lv], r.time[lv], lv
end

function S.research(w, p, bId, rid)
    local b = w.ents[bId]
    local r = D.Research[rid]
    if not alive(b) or b.owner ~= p or not b.built or not r then return false end
    if b.upgrading then return false, "The building is being upgraded." end
    if b.unsummoning then return false, "It is being unsummoned." end
    if b.uprootT then return false, "It is uprooting." end
    local pl = w.players[p]
    if pl.researching and pl.researching[rid] then return false, "Already being researched." end
    local g, l, t, lv = S.researchCost(w, p, rid)
    if not g then return false, "Already fully researched." end
    local ok, need = S.requirementMet(w, p, rid, lv)
    if not ok then return false, S.needText(need) end
    if #b.queue >= 7 then return false, "The queue is full." end
    local paid, why = payCost(w, p, g, l)
    if not paid then return false, why end
    b.queue[#b.queue + 1] = "r:" .. rid
    b.qinfo = b.qinfo or {}
    b.qinfo[#b.queue] = { gold = g, lumber = l, time = t, level = lv }
    S.updateSupply(w)
    return true
end

-- upgrade a building in place (hall tiers, scout tower into a guard/cannon/arcane tower)
function S.upgradeBuilding(w, p, bId, toId)
    local b = w.ents[bId]
    local to = D.Buildings[toId]
    if not alive(b) or b.owner ~= p or not b.built or not to then return false end
    if b.upgrading then return false, "Already upgrading." end
    if b.unsummoning then return false, "It is being unsummoned." end
    if b.uprootT then return false, "It is uprooting." end
    if #b.queue > 0 then return false, "Finish or cancel the queue first." end
    local ok, need = S.requirementMet(w, p, toId)
    if not ok then return false, S.needText(need) end
    local g, l = max(0, to.gold - b.def.gold), max(0, to.lumber - b.def.lumber)
    local paid, why = payCost(w, p, g, l)
    if not paid then return false, why end
    b.queue[1] = "u:" .. toId
    b.qinfo = { { gold = g, lumber = l, time = to.time } }
    b.upgrading = toId
    return true
end

function S.upgradeCost(b, toId)
    local to = D.Buildings[toId]
    return max(0, to.gold - b.def.gold), max(0, to.lumber - b.def.lumber), to.time
end

function S.cancelTrain(w, p, bId, i)
    local b = w.ents[bId]
    if not alive(b) or b.owner ~= p or not b.queue[i] then return false end
    local q = table.remove(b.queue, i)
    local info = b.qinfo and table.remove(b.qinfo, i) or {}
    local pl = w.players[p]
    pl.gold, pl.lumber = pl.gold + (info.gold or 0), pl.lumber + (info.lumber or 0)
    if q:sub(1, 2) == "u:" then b.upgrading = nil end
    if info.rec then table.insert(pl.deadHeroes, info.rec) end
    if i == 1 then b.trainT = 0 end
    S.updateSupply(w)
    return true
end

-- the item at the front of a building's queue has finished
function S.finishQueueItem(w, b)
    local q = table.remove(b.queue, 1)
    local info = b.qinfo and table.remove(b.qinfo, 1) or {}
    b.trainT = 0
    local kind, def, id = S.queueItem(q)
    local pl = w.players[b.owner]
    if kind == "unit" then
        w.reviveRec = info.rec
        S.spawnFrom(w, b, id)
        w.reviveRec = nil
    elseif kind == "research" then
        pl.research[id] = info.level or (S.level(w, b.owner, id) + 1)
        S.applyResearch(w, b.owner, id)
        S.event(w, { t = "researched", owner = b.owner, research = id, level = pl.research[id] })
    elseif kind == "upgrade" then
        S.transformBuilding(w, b, id)
        b.upgrading = nil
        S.event(w, { t = "upgraded", owner = b.owner, unit = b.id })
    end
    S.updateSupply(w)
end

function S.transformBuilding(w, b, toId)
    local frac = b.hp / b.maxhp
    b.def = D.Buildings[toId]
    local pl = w.players[b.owner]
    b.maxhp = floor(b.def.hp * (1 + 0.1 * (pl.masonry or 0)))
    b.hp = max(1, floor(b.maxhp * frac))
    b.cd = 0
end

-- effects that change things already on the map when a research finishes
function S.applyResearch(w, p, rid)
    local before = {}
    for _, e in ipairs(w.list) do if e.owner == p and alive(e) then before[e] = e.maxhp end end
    S.recalc(w, p)
    local r = D.Research[rid]
    local pl = w.players[p]
    for _, e in ipairs(w.list) do
        if e.owner == p and alive(e) then
            if e.kind == "unit" then
                if rid == "berserkerUp" and e.def.id == "headhunter" then
                    local frac = e.hp / e.maxhp
                    e.def = D.Units.berserker
                    e.maxhp = e.def.hp + S.hpBonus(w, p, "berserker")
                    e.hp = floor(e.maxhp * frac)
                else
                    local want = e.def.hp + S.hpBonus(w, p, e.def.id)
                    if not e.def.hero and want ~= e.maxhp then
                        e.hp = e.hp + (want - e.maxhp)
                        e.maxhp = want
                    end
                    if not e.def.hero and e.def.mana then
                        local wantMana = e.def.mana + (S.bonus(w, e).mana or 0)
                        if wantMana ~= e.maxMana then e.mana = (e.mana or 0) + (wantMana - (e.maxMana or 0)) e.maxMana = wantMana end
                    end
                end
            elseif e.kind == "building" and r.effect == "masonry" then
                local want = floor(e.def.hp * (1 + 0.1 * pl.masonry))
                e.hp = e.hp + (want - e.maxhp)
                e.maxhp = want
            end
        end
    end
end

-- ------------------------------------------------------------------ Call to Arms, Defend

function S.callToArms(w, p, hallId)
    local hall = w.ents[hallId]
    if not alive(hall) or hall.owner ~= p or not hall.def.hall or w.players[p].faction ~= "alliance" then return false end
    local n = 0
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and u.owner == p and alive(u) and u.def.id == "peasant" and not u.hidden and dist(u.x, u.y, hall.x, hall.y) < 14 then
            u.militia = { order = u.order and u.order.type == "gather" and { type = "gather", res = u.order.res, mine = u.order.mine, tree = u.order.tree } or nil }
            S.issue(w, u, { type = "stop" })
            u.order = nil
            u.def = D.Units.militia
            u.militiaT = 45
            local frac = u.hp / u.maxhp
            u.maxhp = u.def.hp + S.hpBonus(w, p, "militia")
            u.hp = floor(u.maxhp * frac)
            u.carry = nil
            n = n + 1
        end
    end
    if n == 0 then return false, "No Peasants nearby." end
    S.event(w, { t = "callToArms", owner = p, count = n })
    return true
end

function S.backToWork(w, u)
    if not u.militia then return end
    local frac = u.hp / u.maxhp
    u.def = D.Units.peasant
    u.maxhp = u.def.hp
    u.hp = max(1, floor(u.maxhp * frac))
    local o = u.militia.order
    u.militia, u.militiaT = nil, nil
    u.order = nil
    if o then S.issue(w, u, o) end
end

function S.stepMilitia(w, u, dt)
    if u.militiaT then
        u.militiaT = u.militiaT - dt
        if u.militiaT <= 0 then S.backToWork(w, u) end
    end
end

-- ------------------------------------------------------------------ economy

-- WC3 upkeep: the more food you use, the less of each gold trip you keep
function S.upkeep(w, p)
    local used = w.players[p].used
    for _, u in ipairs(D.UPKEEP) do
        if used <= u[1] then return u[2] end
    end
    return D.UPKEEP[#D.UPKEEP][2]
end

function S.tripSize(w, u, res)
    if res == "gold" then return D.GOLD_TRIP end
    if u.def.lumberTrip then return u.def.lumberTrip end
    local pl = w.players[u.owner]
    if u.def.id == "peasant" then return D.LUMBER_TRIP + 10 * (pl.lumberLv or 0) end
    return D.LUMBER_TRIP
end

-- the nearest building this worker can drop this resource at
function S.dropoffFor(w, u, res)
    local best, bd
    for _, e in ipairs(w.list) do
        if e.kind == "building" and e.owner == u.owner and alive(e) and e.built then
            local d0 = e.def.dropoff
            if d0 == true or (res and d0 == res) then
                local d = S.edgeDist(u.x, u.y, e)
                if not bd or d < bd then best, bd = e, d end
            end
        end
    end
    return best
end
