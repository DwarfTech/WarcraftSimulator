-- Skirmish engine: the Undead Scourge (Warcraft III).
-- Acolytes summon buildings that build themselves and mine Haunted Gold Mines without carrying
-- the gold home; Ghouls cut the lumber. Every building but the Necropolis and the Haunted Gold
-- Mine needs blighted ground, and Undead units heal only on blight. Graveyards make corpses for
-- Necromancers, Meat Wagons carry them, and Acolytes can be sacrificed for Shades.
-- Four heroes (Death Knight, Lich, Dreadlord, Crypt Lord) with their 16 abilities, and the unit
-- spells. Numbers are from War3.mpq (UnitBalance / UnitWeapons / AbilityData).

local _, ns = ...
local E = ns.Engine
local D, M, S = E.Data, E.Map, E.Sim

local floor, abs, max, min, sqrt, atan2, cos, sin, pi = math.floor, math.abs, math.max, math.min, math.sqrt, math.atan2, math.cos, math.sin, math.pi
local function alive(e) return e and not e.dead and not e.removed end
local function dist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return sqrt(dx * dx + dy * dy) end
local function T(units) return units / 128 end
local ICON = "Interface\\Icons\\"
local EMPTY = {}
local H, SU, A = D.defHero, D.defSummon, D.defAbility

local function lvOf(t, lv) return t[min(lv, #t)] end
local function fx(w, x, y, model, size, life, follow, delay) S.fxAt(w, x, y, model, size, life, follow, delay) end
local function enemies(w, u, x, y, r, air) return S.enemiesAround2(w, u, x, y, r, air) end
local function canHurt(e) return not S.spellImmune(e) end
local function event(w, t) S.event(w, t) end

-- is this one of the living dead? (Death Coil heals them, disease doesn't touch them)
function S.isUndead(e)
    return e and e.def and (e.def.faction == "undead" or e.def.undead) or false
end
local function living(e) return e.kind == "unit" and not S.isUndead(e) and not e.def.mech and not e.def.ward end

-- ------------------------------------------------------------------ unit data

D.CORPSE_LIFE = 90                      -- seconds a corpse can be raised (WC3 corpses decay after about 90 s)
for _, id in ipairs({ "meatWagon", "obsidianStatue" }) do D.Units[id].mech = true end
D.Units.destroyer.spellImmune = true
D.Units.destroyer.orbAnnihilation = true
D.Units.destroyer.onHit = true
D.Units.destroyer.manaRegen, D.Units.destroyer.mana0 = 0, 0
D.Units.necromancer.mana0, D.Units.necromancer.manaRegen = 75, 0.667
D.Units.banshee.mana0, D.Units.banshee.manaRegen = 75, 0.667
D.Units.obsidianStatue.mana0, D.Units.obsidianStatue.manaRegen = 400, 1.5
D.Units.frostWyrm.frostAttack = true
D.Units.shade.detector = T(900)          -- Atru: true sight 900
D.Units.shade.noTrain, D.Units.shade.sacrifice = nil, true
D.Units.meatWagon.cargoMax = 8
for _, id in ipairs({ "skeletonWarrior", "skeletalMage" }) do
    local u = D.Units[id]
    u.summon, u.supply, u.gold, u.lumber = true, 0, 0, 0
end

local SPELLS = {
    necromancer = { "raiseDead", "unholyFrenzy", "cripple" },
    banshee = { "bansheeCurse", "antiMagicShell", "possession" },
    cryptFiend = { "web", "burrow" },
    gargoyle = { "stoneForm" },
    ghoul = { "cannibalize" },
    abomination = { "cannibalizeAbom" },
    meatWagon = { "loadCorpses", "dropCorpses" },
    obsidianStatue = { "essenceOfBlight", "spiritTouch", "destroyerMorph" },
    destroyer = { "devourMagic", "absorbMana" },
}
for id, list in pairs(SPELLS) do D.Units[id].spells = list end

-- the Gargoyle in Stone Form: a statue on the ground that can't attack but heals fast
do
    local g = D.Units.gargoyle
    local s = {}
    for k, v in pairs(g) do s[k] = v end
    s.id, s.name, s.air, s.role = "gargoyleStone", "Gargoyle (Stone Form)", nil, "melee"
    s.armor, s.speed, s.spellImmune, s.noAttack = 15, 0, true, true      -- WC3 ugrm: 15 armour, magic immune
    s.dmin, s.dmax, s.base, s.weapon1, s.weapon2, s.weapon2w = nil, nil, nil, nil, nil, nil
    s.hitsAir, s.hitsGround = nil, nil
    s.stoneOf, s.noTrain = "gargoyle", true
    D.Units.gargoyleStone = s
    if D.WC3SIZE then D.WC3SIZE.gargoyleStone = D.WC3SIZE.gargoyle end
end

-- ------------------------------------------------------------------ the heroes

local function UH(t)
    H(t)
    t.faction, t.blightRegen = "undead", 2
end
UH{ id = "deathKnight", name = "Death Knight", primary = "str", str = 23, agi = 12, int = 17, strUp = 2.7, agiUp = 1.5, intUp = 1.8,
    armor = 1, sides = 6, cd = 2.33, dmgpt = 0.56, range = T(100), speed = T(320), display = { 14591 }, mount = { 10718 },
    icon = ICON .. "Spell_Shadow_DeathCoil", key = "D", abilities = { "deathCoil", "deathPact", "unholyAura", "animateDead" },
    tip = "Warrior hero on a skeletal horse. Death Coil hurts the living and heals the dead; Unholy Aura speeds up his troops." }
UH{ id = "lich", name = "Lich", primary = "int", str = 15, agi = 14, int = 20, strUp = 2, agiUp = 1, intUp = 3.4,
    armor = 0, sides = 4, cd = 1.9, dmgpt = 0.46, range = T(600), speed = T(290), display = { 7919 }, missile = "frost",
    icon = ICON .. "Spell_Frost_FrostNova", key = "L", abilities = { "frostNova", "frostArmor", "darkRitual", "deathAndDecay" },
    tip = "Mystical hero. Frost Nova blasts and slows enemies, Frost Armor protects friends, Dark Ritual turns a unit into mana." }
UH{ id = "dreadlord", name = "Dreadlord", primary = "str", str = 20, agi = 16, int = 18, strUp = 2.5, agiUp = 1, intUp = 2.5,
    armor = 0, sides = 6, cd = 1.8, dmgpt = 0.55, range = T(100), speed = T(290), display = { 10543 },
    icon = ICON .. "Spell_Shadow_CarrionSwarm", key = "E", abilities = { "carrionSwarm", "dreadSleep", "vampiricAura", "inferno" },
    tip = "Cunning hero. Carrion Swarm sends bats through the enemy, Sleep takes a unit out, Vampiric Aura heals his fighters." }
UH{ id = "cryptLord", name = "Crypt Lord", primary = "str", str = 26, agi = 14, int = 14, strUp = 3.2, agiUp = 1.2, intUp = 1.6,
    armor = 0, sides = 4, cd = 1.9, dmgpt = 0.46, range = T(128), speed = T(290), display = { 15931 },
    icon = ICON .. "Ability_Hunter_Pet_Scorpid", key = "C", abilities = { "impale", "spikedCarapace", "carrionScarabs", "locustSwarm" },
    tip = "Warrior hero. Impale throws enemies into the air, Spiked Carapace hurts his attackers, Carrion Scarabs rise from corpses." }

D.UNDEAD_HEROES = { "deathKnight", "lich", "dreadlord", "cryptLord" }

-- ------------------------------------------------------------------ summoned units

local function dmg(base, dice, sides) return base + dice, base + dice * sides end
for lv, s in ipairs({ { 170, 7, 2 }, { 330, 14, 4 }, { 490, 21, 6 } }) do
    local lo, hi = dmg(s[2], 1, s[3])
    SU{ id = "carrionScarab" .. lv, faction = "undead", name = "Carrion Scarab", role = "melee", hp = s[1], armor = 2, dtype = "heavy", atype = "normal",
        dmin = lo, dmax = hi, cd = 1.5, dmgpt = 0.33, range = T(90), speed = T(290), display = { 10031 }, icon = ICON .. "Ability_Hunter_Pet_Crab",
        vis = 0.32, level = lv, undead = true, burrowLv = lv >= 2 or nil }
end
SU{ id = "infernal", faction = "undead", name = "Infernal", role = "melee", hp = 1500, armor = 6, dtype = "heavy", atype = "chaos",
    dmin = 49, dmax = 60, cd = 1.35, dmgpt = 0.26, range = T(100), speed = T(320), display = { 169 }, spellImmune = true,
    icon = ICON .. "Spell_Shadow_SummonInfernal", vis = 0.55, level = 8, undead = true }

-- ------------------------------------------------------------------ blight

-- WC3 blight: each Undead building spreads a disc of it (960 for the Necropolis and Haunted Gold
-- Mine, 768 for the rest), growing outwards. It stays after the building is gone.
local BLIGHT_R = { large = T(960), small = T(768) }

function S.addBlight(w, x, y, r, instant)
    w.blight = w.blight or {}
    w.blightSrc = w.blightSrc or {}
    local s = { x = x, y = y, r = instant and r or 0.5, max = r }
    w.blightSrc[#w.blightSrc + 1] = s
    S.paintBlight(w, s)
end

function S.paintBlight(w, s)
    local r = s.r
    local x1, x2 = max(1, floor(s.x - r)), min(w.w, floor(s.x + r) + 1)
    local y1, y2 = max(1, floor(s.y - r)), min(w.h, floor(s.y + r) + 1)
    local changed = false
    for ty = y1, y2 do
        for tx = x1, x2 do
            local i = (ty - 1) * w.w + tx
            if not w.blight[i] and dist(tx - 0.5, ty - 0.5, s.x, s.y) <= r and not (w.water and w.water[i]) and not (w.cliff and w.cliff[i]) then
                w.blight[i] = true
                changed = true
            end
        end
    end
    if changed then w.blightVer = (w.blightVer or 0) + 1 end
end

function S.blightAt(w, tx, ty)
    return w.blight and w.blight[(ty - 1) * w.w + tx] or false
end

-- is the whole footprint blighted?
function S.blighted(w, tx, ty, size)
    if not w.blight then return false end
    for yy = ty, ty + size - 1 do
        for xx = tx, tx + size - 1 do
            if not w.blight[(yy - 1) * w.w + xx] then return false end
        end
    end
    return true
end

function S.onBlight(w, u)
    if not w.blight then return false end
    local tx, ty = M.tileOf(u.x, u.y)
    return w.blight[(ty - 1) * w.w + tx] or false
end

-- ------------------------------------------------------------------ placing buildings

function S.mineAt(w, tx, ty)
    for _, e in ipairs(w.list) do
        if e.kind == "mine" and alive(e) and e.tx == tx and e.ty == ty then return e end
    end
end

-- a gold mine under (or next to) a point, for placing a Haunted Gold Mine
function S.mineNear(w, x, y)
    local best, bd
    for _, e in ipairs(w.list) do
        if e.kind == "mine" and alive(e) then
            local d = dist(e.x, e.y, x, y)
            if d < 2.2 and (not bd or d < bd) then best, bd = e, d end
        end
    end
    return best
end

-- can player p put building bid with its top-left tile at (tx, ty)?
function S.canPlaceFor(w, p, bid, tx, ty)
    local def = D.Buildings[bid]
    if def.onMine then
        local m = S.mineAt(w, tx, ty)
        if not m then return false, "Must be built on a gold mine." end
        if m.haunted and alive(w.ents[m.haunted]) then return false, "That gold mine is already haunted." end
        return true
    end
    if not M.canPlace(w, tx, ty, def.size) then return false, "Can't build there." end
    if def.needsBlight and not S.blighted(w, tx, ty, def.size) then return false, "Must be built on blight." end
    return true
end

for _, b in pairs(D.Buildings) do
    if b.faction == "undead" then
        b.summoned = true
        if not b.hall and not b.onMine then b.needsBlight = true end
    end
end

-- an Acolyte has placed a building: it summons itself; the Acolyte is free at once
function S.startSummoning(w, b)
    b.selfBuild = true
    if b.def.onMine then
        local m = S.mineAt(w, b.tx, b.ty)
        if m then m.haunted, b.mine = b.id, m.id end
    end
    if b.def.blight then S.addBlight(w, b.x, b.y, BLIGHT_R[b.def.blight] or BLIGHT_R.small) end
end

-- a summoned building builds itself, at the normal build time
function S.stepSummoning(w, b, dt)
    local inc = dt / b.def.time * (w.players[b.owner].buildSpeed or 1)
    b.progress = min(1, b.progress + inc)
    b.hp = min(b.maxhp, b.hp + b.maxhp * 0.9 * inc)
    b.lastBuilt = w.time
    if b.progress >= 1 then
        b.built = true
        b.hp = max(b.hp, floor(b.maxhp * 0.98))
        w.players[b.owner].stats.built = w.players[b.owner].stats.built + 1
        event(w, { t = "built", unit = b.id, owner = b.owner })
        S.updateSupply(w)
    end
end

-- ------------------------------------------------------------------ Haunted Gold Mine

function S.nearestHaunted(w, p, x, y, maxD)
    local best, bd
    for _, e in ipairs(w.list) do
        if e.kind == "mine" and alive(e) and e.gold > 0 and e.haunted then
            local b = w.ents[e.haunted]
            if alive(b) and b.owner == p and b.built then
                local d = dist(x, y, e.x, e.y)
                if (not maxD or d <= maxD) and (not bd or d < bd) then best, bd = e, d end
            end
        end
    end
    return best
end

-- five spots in a ring all the way round the mine (WC3's Acolytes stand round the Haunted Gold Mine)
local function slotPos(w, m, i, owner)
    m.slotXY = m.slotXY or {}
    if m.slotXY[i] then return m.slotXY[i][1], m.slotXY[i][2] end
    local hall = S.nearestDropoff and S.nearestDropoff(w, { owner = owner, x = m.x, y = m.y, def = { radius = 0 } })
    local base = hall and atan2(hall.y - m.y, hall.x - m.x) or 0
    local a = base + (i - 1) * 2 * pi / 5
    local x, y = m.x + cos(a) * 2.2, m.y + sin(a) * 2.2
    local tx, ty = M.tileOf(x, y)
    if not M.walkable(w, tx, ty) then
        local nx, ny = M.nearestOpen(w, tx, ty, 3)
        if nx then x, y = nx - 0.5, ny - 0.5 end
    end
    m.slotXY[i] = { x, y }
    return x, y
end

-- the "gather gold" order for an Acolyte: stand at the mine and channel 10 gold every 5 seconds
function S.stepHaunt(w, u, dt, o, stepMove)
    local m = w.ents[o.mine or 0]
    if m and m.kind == "building" and m.mine then m = w.ents[m.mine] o.mine = m and m.id end
    local b = m and m.haunted and w.ents[m.haunted]
    if not (alive(m) and m.gold > 0 and alive(b) and b.owner == u.owner and b.built) then
        m = S.nearestHaunted(w, u.owner, u.x, u.y, 40)
        if not m then
            if not o.warned and u.owner >= 1 and u.owner <= 2 then
                o.warned = true
                local F = D.Factions[w.players[u.owner].faction]
                local mb = F and F.mineBuilding and D.Buildings[F.mineBuilding]
                event(w, { t = "error", owner = u.owner, text = u.def.name .. "s mine only from " .. (mb and ("an " .. mb.name):gsub("^an H", "a H") or "a gold mine") .. " of yours." })
            end
            u.order = nil
            u.anim = "stand"
            return
        end
        o.mine, o.slot, o.state = m.id, nil, nil
    end
    u.lastMine = m.id
    m.slots = m.slots or {}
    if not (o.slot and m.slots[o.slot] == u.id) then
        o.slot = nil
        for i = 1, 5 do
            local a = w.ents[m.slots[i] or 0]
            if m.slots[i] and not (alive(a) and a.order and a.order.type == "gather" and a.order.mine == m.id and a.order.slot == i) then m.slots[i] = nil end
        end
        for i = 1, 5 do if not m.slots[i] then o.slot = i break end end
        if not o.slot then
            -- all five spots are taken: wait by the mine
            if S.gap(u, m) > 1.2 then stepMove(w, u, dt, nil, nil, m, 1.0) else u.anim = "stand" end
            return
        end
        m.slots[o.slot] = u.id
        o.state = "toSlot"
    end
    local sx, sy = slotPos(w, m, o.slot, u.owner)
    if o.state ~= "haunt" then
        local there = stepMove(w, u, dt, sx, sy, nil, 0.2)
        if there or dist(u.x, u.y, sx, sy) < 0.45 or ((u.blockedT or 0) > 1 and S.gap(u, m) < 1.5) or u.stuck then
            o.state = "haunt"
            u.hauntT = 0
            u.path = nil
        end
        return
    end
    u.facing = atan2(m.y - u.y, m.x - u.x)
    u.anim = "work"
    u.hauntT = (u.hauntT or 0) + dt
    if u.hauntT >= 5 then
        u.hauntT = u.hauntT - 5
        local amt = min(10, m.gold)
        m.gold = m.gold - amt
        local pl = w.players[u.owner]
        local got = floor(amt * S.upkeep(w, u.owner) + 0.5)
        pl.gold = pl.gold + got
        pl.stats.gold = pl.stats.gold + got
        pl.stats.upkeepLost = (pl.stats.upkeepLost or 0) + (amt - got)
        event(w, { t = "deposit", unit = u.id, res = "gold", amt = got, owner = u.owner, x = u.x, y = u.y })
        if m.gold <= 0 then
            event(w, { t = "mineEmpty", x = m.x, y = m.y })
            if alive(b) then S.kill(w, b, nil, true) end
            S.kill(w, m)
        end
    end
end

-- ------------------------------------------------------------------ corpses

local function corpseAlive(w, c) return w.time - c.t < D.CORPSE_LIFE end

-- the corpses within r of a point (oldest first)
function S.corpsesNear(w, x, y, r)
    local out = {}
    for _, c in ipairs(w.corpses or EMPTY) do
        if corpseAlive(w, c) and abs(c.x - x) <= r and abs(c.y - y) <= r and dist(c.x, c.y, x, y) <= r then out[#out + 1] = c end
    end
    return out
end

function S.takeCorpse(w, c)
    for i, k in ipairs(w.corpses or EMPTY) do
        if k == c then table.remove(w.corpses, i) break end
    end
    if c.ent then c.ent.removed = true end
end

function S.addCorpse(w, x, y, owner, id)
    w.corpses = w.corpses or {}
    w.corpseId = (w.corpseId or 0) + 1
    w.corpses[#w.corpses + 1] = { id = id or "ghoul", owner = owner, x = x, y = y, t = w.time, cid = w.corpseId, made = true }
    if #w.corpses > 80 then table.remove(w.corpses, 1) end
end

-- corpses carried by a friendly Meat Wagon near a point count too (Necromancers raise from the cart)
local function wagonNear(w, owner, x, y, r)
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and e.owner == owner and (e.cargo or 0) > 0 and dist(e.x, e.y, x, y) <= r then return e end
    end
end

-- take n corpses near (x, y) for a spell: returns their positions
local function useCorpses(w, owner, x, y, r, n)
    local got = {}
    for _, c in ipairs(S.corpsesNear(w, x, y, r)) do
        if #got >= n then break end
        got[#got + 1] = { c.x, c.y }
        S.takeCorpse(w, c)
    end
    while #got < n do
        local wg = wagonNear(w, owner, x, y, r)
        if not wg then break end
        wg.cargo = wg.cargo - 1
        got[#got + 1] = { wg.x + 0.5, wg.y + 0.3 }
    end
    return got
end
local function corpseCount(w, owner, x, y, r)
    local n = #S.corpsesNear(w, x, y, r)
    local wg = wagonNear(w, owner, x, y, r)
    return n + (wg and wg.cargo or 0)
end

-- ------------------------------------------------------------------ unit spells

local function UA(t)
    t.unit, t.maxLevel = true, 1
    for _, f in ipairs({ "mana", "cd", "dur", "heroDur" }) do if type(t[f]) == "number" then t[f] = { t[f] } end end
    D.Abilities[t.id] = t
end

-- Necromancer
UA{ id = "raiseDead", name = "Raise Dead", key = "R", target = "none", mana = 75, cd = 8, range = T(600), autocast = true, school = "shadow", castPoint = 0.4,
    icon = ICON .. "Spell_Shadow_RaiseDead", tip = "Raises two Skeleton Warriors from a corpse for 40 seconds. Right-click for autocast.",
    ready = function(w, u) if corpseCount(w, u.owner, u.x, u.y, T(600) + 1) < 1 then return false, "There are no corpses nearby." end return true end,
    cast = function(w, u)
        local got = useCorpses(w, u.owner, u.x, u.y, T(600) + 1, 1)
        local c = got[1]
        if not c then return end
        local life = 40 + (S.level(w, u.owner, "skeletalLongevity") > 0 and 15 or 0)
        local mastery = S.level(w, u.owner, "skeletalMastery") > 0
        for i = 1, 2 do
            local id = (mastery and i == 2) and "skeletalMage" or "skeletonWarrior"
            local s = S.summonUnit(w, u.owner, id, c[1] + (i - 1.5) * 0.6, c[2], life)
            if u.order and u.order.type == "amove" then S.issue(w, s, { type = "amove", x = u.order.x, y = u.order.y }) end
        end
        fx(w, c[1], c[2], 166808, 1.8, 1.2)
        S.updateSupply(w)
    end }
UA{ id = "unholyFrenzy", name = "Unholy Frenzy", key = "U", target = "ally", mana = 50, cd = 1, range = T(500), dur = 45, research = { "necroTraining", 1 }, noMech = true,
    school = "shadow", aiAuto = true, icon = ICON .. "Spell_Shadow_UnholyFrenzy",
    tip = "A friendly unit attacks 75% faster for 45 seconds, but loses 4 hit points a second.",
    cast = function(w, u, o, t) S.buff(w, t, "frenzy", 45) fx(w, t.x, t.y, 166808, 1.4, 1.0, t.id) end }
UA{ id = "cripple", name = "Cripple", key = "C", target = "enemy", mana = 175, cd = 10, range = T(600), dur = 60, heroDur = 10, research = { "necroTraining", 2 }, noMech = true,
    school = "shadow", aiAuto = true, icon = ICON .. "Spell_Shadow_Cripple",
    tip = "An enemy moves 75% slower, attacks 50% slower and deals 50% less damage for 60 seconds (10 on heroes).",
    cast = function(w, u, o, t, lv, durFor) S.buff(w, t, "cripple", durFor(t)) fx(w, t.x, t.y, 166808, 1.4, 1.0, t.id) end }
-- Banshee
UA{ id = "bansheeCurse", name = "Curse", key = "C", target = "enemy", mana = 40, cd = 1, range = T(700), dur = 120, heroDur = 60, autocast = true, noMech = true, school = "shadow",
    castPoint = 0.3, icon = ICON .. "Spell_Shadow_CurseOfTounges", tip = "The target misses 33% of its attacks for 2 minutes (1 on heroes). Right-click for autocast.",
    check = function(w, u, t) if S.hasBuff(t, "curse") then return false, "Already cursed." end return true end,
    cast = function(w, u, o, t, lv, durFor) S.buff(w, t, "curse", durFor(t)) fx(w, t.x, t.y, 166808, 1.4, 1.0, t.id) end }
UA{ id = "antiMagicShell", name = "Anti-magic Shell", key = "N", target = "ally", mana = 75, cd = 1, range = T(500), dur = 90, research = { "bansheeTraining", 1 }, school = "shadow",
    aiAuto = true, icon = ICON .. "Spell_Shadow_AntiMagicShell", tip = "Shields a friendly unit from spells for 90 seconds, or until it has soaked up 300 spell damage.",
    cast = function(w, u, o, t) S.buff(w, t, "ams", 90, { left = 300 }) fx(w, t.x, t.y, 166808, 1.6, 1.0, t.id) end }
UA{ id = "possession", name = "Possession", key = "O", target = "enemy", mana = 250, cd = 1, range = T(350), research = { "bansheeTraining", 2 }, noHero = true, noMech = true,
    school = "shadow", aiAuto = true, icon = ICON .. "Spell_Shadow_Possession",
    tip = "The Banshee spends 3 seconds entering an enemy unit and takes control of it for good. The Banshee is lost. Not heroes.",
    check = function(w, u, t) if t.def.summon then return false, "Can't possess summoned units." end return true end,
    cast = function(w, u, o, t)
        u.channel = { ability = "possession", target = t.id, t = 3 }
        fx(w, t.x, t.y, 166808, 1.8, 3, t.id)
    end,
    tick = function(w, u, dt, ch)
        local t = w.ents[ch.target or 0]
        ch.t = ch.t - dt
        if not alive(t) or S.spellImmune(t) or dist(t.x, t.y, u.x, u.y) > T(700) then return false end
        if ch.t > 0 then return end
        t.owner, t.order, t.camp, t.sleeping, t.swing, t.autocast = u.owner, nil, nil, nil, nil, nil
        u.channel = nil
        u.noCorpse = true
        S.kill(w, u, nil, true)
        u.removed = true
        S.updateSupply(w)
        return false
    end }
-- Crypt Fiend
UA{ id = "web", name = "Web", key = "W", target = "enemy", mana = 0, cd = 12, range = T(400), dur = 12, heroDur = 7, research = { "webUp", 1 }, airOnly = true, autocast = true,
    precast = false, castPoint = 0.3, icon = ICON .. "Spell_Nature_Web", tip = "Webs a flying unit to the ground for 12 seconds (7 on heroes), where ground troops can hit it. Right-click for autocast.",
    cast = function(w, u, o, t, lv, durFor) S.buff(w, t, "ensnare", durFor(t)) fx(w, t.x, t.y, 166492, 1.4, 1.0, t.id) end }
UA{ id = "burrow", name = "Burrow", key = "B", target = "self", mana = 0, cd = 1, research = { "burrowUp", 1 }, precast = false, castPoint = 0.5,
    icon = ICON .. "Ability_Rogue_FeignDeath", tip = "Burrows into the ground: unseen by the enemy and healing faster, but can't move or attack. Again to come up.",
    cast = function(w, u)
        if u.buffs and u.buffs.burrowed then u.buffs.burrowed = nil else S.buff(w, u, "burrowed", 1e9) u.order, u.path, u.swing = nil, nil, nil end
        fx(w, u.x, u.y, 165976, 1.4, 0.8)
    end }
-- Gargoyle
UA{ id = "stoneForm", name = "Stone Form", key = "F", target = "self", mana = 0, cd = 1, research = { "stoneFormUp", 1 }, precast = false, castPoint = 0.5,
    icon = ICON .. "Spell_Nature_StoneSkinTotem", tip = "Turns to stone on the ground: 15 armour, immune to magic and healing quickly, but can't attack or move. Again to fly.",
    cast = function(w, u)
        local frac = u.hp / u.maxhp
        if u.def.stoneOf then u.def = D.Units[u.def.stoneOf] else u.def = D.Units.gargoyleStone u.order, u.path, u.swing = nil, nil, nil end
        u.hp = max(1, u.maxhp * frac)
        fx(w, u.x, u.y, 165976, 1.6, 0.8)
    end }
D.Units.gargoyleStone.spells = { "stoneForm" }
-- Ghoul and Abomination
local function cannibal(id, rate, research)
    UA{ id = id, name = "Cannibalize", key = "C", target = "none", mana = 0, cd = 1, range = T(150), research = research, precast = false, castPoint = 0.3,
        icon = ICON .. "Ability_Racial_Cannibalize", tip = "Eats a corpse next to it, healing " .. rate .. " hit points a second until full (up to 33 seconds).",
        ready = function(w, u)
            if u.hp >= u.maxhp then return false, "Already at full health." end
            if #S.corpsesNear(w, u.x, u.y, 2.2) == 0 then return false, "There are no corpses nearby." end
            return true
        end,
        cast = function(w, u)
            local c = S.corpsesNear(w, u.x, u.y, 2.2)[1]
            if not c then return end
            S.takeCorpse(w, c)
            u.facing = atan2(c.y - u.y, c.x - u.x)
            u.channel = { ability = id, t = 33, rate = rate }
        end,
        tick = function(w, u, dt, ch)
            ch.t = ch.t - dt
            u.anim = "work"
            u.hp = min(u.maxhp, u.hp + ch.rate * dt)
            if ch.t <= 0 or u.hp >= u.maxhp or (w.time - (u.hitT or -99)) < 0.15 then return false end
        end }
end
cannibal("cannibalize", 10, { "cannibalizeUp", 1 })
cannibal("cannibalizeAbom", 15, nil)
-- Meat Wagon
UA{ id = "loadCorpses", name = "Get Corpse", key = "G", target = "none", mana = 0, cd = 1, range = T(600), autocast = true, precast = false, castPoint = 0.2,
    icon = ICON .. "INV_Misc_Bone_Skull_01", tip = "Loads the corpses lying near the Meat Wagon (up to 8). Right-click for autocast.",
    ready = function(w, u)
        if (u.cargo or 0) >= 8 then return false, "The Meat Wagon is full." end
        if #S.corpsesNear(w, u.x, u.y, T(600)) == 0 then return false, "There are no corpses nearby." end
        return true
    end,
    cast = function(w, u)
        for _, c in ipairs(S.corpsesNear(w, u.x, u.y, T(600))) do
            if (u.cargo or 0) >= 8 then break end
            S.takeCorpse(w, c)
            u.cargo = (u.cargo or 0) + 1
        end
    end }
UA{ id = "dropCorpses", name = "Drop All Corpses", key = "D", target = "none", mana = 0, cd = 1, precast = false, castPoint = 0.2,
    icon = ICON .. "Spell_Shadow_AnimateDead", tip = "Drops every corpse the Meat Wagon is carrying on the ground beside it.",
    ready = function(w, u) if (u.cargo or 0) < 1 then return false, "The Meat Wagon is empty." end return true end,
    cast = function(w, u)
        for i = 1, u.cargo or 0 do
            local a = i * 0.8
            S.addCorpse(w, u.x + cos(a) * 0.8, u.y + sin(a) * 0.8, u.owner)
        end
        u.cargo = 0
    end }
-- Obsidian Statue
UA{ id = "essenceOfBlight", name = "Essence of Blight", key = "B", target = "none", mana = 2, cd = 1, range = T(700), autocast = true, precast = false, castPoint = 0.1,
    icon = ICON .. "Spell_Shadow_DemonicFortitude", tip = "Heals up to 5 wounded friendly units nearby for 10 hit points (2 mana). Right-click for autocast.",
    cast = function(w, u)
        local n = 0
        for _, e in ipairs(w.list) do
            if n < 5 and e.kind == "unit" and alive(e) and e.owner == u.owner and not e.def.mech and e.hp < e.maxhp and dist(e.x, e.y, u.x, u.y) <= T(700) then
                e.hp = min(e.maxhp, e.hp + 10)
                n = n + 1
            end
        end
    end }
UA{ id = "spiritTouch", name = "Spirit Touch", key = "T", target = "none", mana = 2, cd = 1, range = T(700), autocast = true, precast = false, castPoint = 0.1,
    icon = ICON .. "Spell_Shadow_Twilight", tip = "Gives up to 5 friendly units nearby 3 mana (2 mana). Right-click for autocast.",
    cast = function(w, u)
        local n = 0
        for _, e in ipairs(w.list) do
            if n < 5 and e ~= u and e.kind == "unit" and alive(e) and e.owner == u.owner and (e.maxMana or 0) > 0 and e.def.id ~= "obsidianStatue"
               and (e.mana or 0) < e.maxMana and dist(e.x, e.y, u.x, u.y) <= T(700) then
                e.mana = min(e.maxMana, e.mana + 3)
                n = n + 1
            end
        end
    end }
UA{ id = "destroyerMorph", name = "Destroyer Form", key = "F", target = "self", mana = 0, cd = 1, research = { "destroyerForm", 1 }, precast = false, castPoint = 1.1,
    icon = ICON .. "Spell_Shadow_Shadowfiend", tip = "Turns into a Destroyer: a flying, spell-immune unit that eats magic. It can't turn back.",
    ready = function(w, u)
        local pl = w.players[u.owner]
        if pl.used - u.def.supply + D.Units.destroyer.supply > pl.cap then return false, "Not enough food." end
        return true
    end,
    cast = function(w, u)
        local frac = u.hp / u.maxhp
        u.def = D.Units.destroyer
        u.maxhp = u.def.hp + S.hpBonus(w, u.owner, "destroyer")
        u.hp = max(1, floor(u.maxhp * frac))
        u.maxMana, u.mana = u.def.mana, 0
        u.order, u.path, u.swing = nil, nil, nil
        fx(w, u.x, u.y, 166808, 2.4, 1.4)
        S.updateSupply(w)
    end }
-- Destroyer
UA{ id = "devourMagic", name = "Devour Magic", key = "D", target = "point", mana = 0, cd = 7, range = T(600), radius = T(200), precast = false, castPoint = 0.3,
    aiAuto = true, icon = ICON .. "Spell_Shadow_ManaBurn",
    tip = "Eats all magic on units in an area. For each effect removed it gains 50 hit points and 75 mana; summoned units take 180 damage.",
    cast = function(w, u, o)
        local n = 0
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and alive(e) and e ~= u and dist(e.x, e.y, o.x, o.y) <= T(200) + e.def.radius then
                if e.def.summon and S.isEnemy(u, e) then S.damage(w, u, e, 180, "magic", true) n = n + 1 end
                if e.buffs then
                    for id, b in pairs(e.buffs) do
                        if b.t and b.t < 1e8 and id ~= "invuln" then e.buffs[id] = nil n = n + 1 end
                    end
                end
            end
        end
        u.hp = min(u.maxhp, u.hp + 50 * n)
        u.mana = min(u.maxMana or 0, (u.mana or 0) + 75 * n)
        fx(w, o.x, o.y, 165955, T(200) * 2.4, 1.0)
    end }
UA{ id = "absorbMana", name = "Absorb Mana", key = "A", target = "ally", mana = 0, cd = 1, range = T(900), precast = false, castPoint = 0.3,
    icon = ICON .. "Spell_Shadow_SiphonMana", tip = "Takes all the mana of a friendly unit.",
    check = function(w, u, t) if (t.mana or 0) < 1 or t == u then return false, "That unit has no mana to give." end return true end,
    cast = function(w, u, o, t)
        u.mana = min(u.maxMana or 0, (u.mana or 0) + (t.mana or 0))
        t.mana = 0
        S.event(w, { t = "vfx", kind = "bounce", x1 = t.x, y1 = t.y, x2 = u.x, y2 = u.y })
    end }

-- autocast and computer-player casting for these spells
local AUTO = S.AUTO
local function anyEnemyNear(w, u, r)
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.hidden and abs(e.x - u.x) < r and abs(e.y - u.y) < r then return e end
    end
end
AUTO.raiseDead = function(w, u, ab)
    if corpseCount(w, u.owner, u.x, u.y, T(600) + 1) > 0 then return u end
end
AUTO.bansheeCurse = function(w, u, ab)
    local best, bs
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.hidden and not e.def.mech and not e.def.ward and e.def.dmin and not S.hasBuff(e, "curse")
           and not S.spellImmune(e) and S.targetable(w, u, e) and abs(e.x - u.x) <= ab.range + 1 and abs(e.y - u.y) <= ab.range + 1 and S.gap(u, e) <= ab.range then
            local s = (e.def.hero and 50 or 0) + (e.def.supply or 1) + (e.def.dmax or 0) / 20
            if not bs or s > bs then best, bs = e, s end
        end
    end
    return best
end
AUTO.web = function(w, u, ab)
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and e.def.air and S.isEnemy(u, e) and not e.hidden and not S.hasBuff(e, "ensnare") and not S.spellImmune(e)
           and S.targetable(w, u, e) and S.gap(u, e) <= ab.range then return e end
    end
end
AUTO.loadCorpses = function(w, u, ab)
    if (u.cargo or 0) < 8 and #S.corpsesNear(w, u.x, u.y, 2.5) > 0 then return u end
end
AUTO.essenceOfBlight = function(w, u, ab)
    local n = 0
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and e.owner == u.owner and not e.def.mech and e.maxhp - e.hp >= 10 and abs(e.x - u.x) < 6 and abs(e.y - u.y) < 6
           and dist(e.x, e.y, u.x, u.y) <= T(700) then n = n + 1 if n >= 1 then return u end end
    end
end
AUTO.spiritTouch = function(w, u, ab)
    for _, e in ipairs(w.list) do
        if e ~= u and e.kind == "unit" and alive(e) and e.owner == u.owner and (e.maxMana or 0) > 0 and e.def.id ~= "obsidianStatue" and e.maxMana - (e.mana or 0) >= 3
           and abs(e.x - u.x) < 6 and abs(e.y - u.y) < 6 and dist(e.x, e.y, u.x, u.y) <= T(700) then return u end
    end
end
-- for the computer player only
AUTO.unholyFrenzy = function(w, u, ab)
    if not anyEnemyNear(w, u, 6) then return end
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and e.owner == u.owner and e.def.dmin and not e.def.mech and not e.def.worker and not e.def.summon and e.hp > 250
           and (e.def.range or 0) < 1.5 and not S.hasBuff(e, "frenzy") and e.order and (e.order.type == "attack" or e.order.target) and S.gap(u, e) <= ab.range then return e end
    end
end
AUTO.cripple = function(w, u, ab)
    local best, bs
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.hidden and not e.def.mech and not S.hasBuff(e, "cripple") and not S.spellImmune(e)
           and S.targetable(w, u, e) and S.gap(u, e) <= ab.range and (e.def.hero or (e.def.supply or 1) >= 3) then
            local s = (e.def.hero and 100 or 0) + (e.def.supply or 1)
            if not bs or s > bs then best, bs = e, s end
        end
    end
    return best
end
AUTO.antiMagicShell = function(w, u, ab)
    if not anyEnemyNear(w, u, 8) then return end
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and e.owner == u.owner and (e.def.hero or (e.def.supply or 1) >= 4) and not S.hasBuff(e, "ams") and S.gap(u, e) <= ab.range then return e end
    end
end
AUTO.possession = function(w, u, ab)
    local best, bs
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.hidden and not e.def.hero and not e.def.summon and not e.def.mech and not S.spellImmune(e)
           and (e.def.supply or 1) >= 4 and S.targetable(w, u, e) and S.gap(u, e) <= ab.range + 2 then
            local s = (e.def.supply or 1) * 100 + e.hp
            if not bs or s > bs then best, bs = e, s end
        end
    end
    return best
end
AUTO.devourMagic = function(w, u, ab)
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and S.gap(u, e) <= ab.range and ((S.isEnemy(u, e) and (e.def.summon or S.hasBuff(e, "bloodlust") or S.hasBuff(e, "innerFire")))
           or (not S.isEnemy(u, e) and (S.hasBuff(e, "slowSpell") or S.hasBuff(e, "curse") or S.hasBuff(e, "cripple")))) then
            return { id = e.id, x = e.x, y = e.y }
        end
    end
end

-- ------------------------------------------------------------------ hero abilities

local function durFor(ab, lv, e)
    local d = ab.dur and lvOf(ab.dur, lv)
    if e and e.def.hero and ab.heroDur then return lvOf(ab.heroDur, lv) end
    return d
end

-- Death Knight
A{ id = "deathCoil", name = "Death Coil", key = "C", target = "unit", mana = { 75, 75, 75 }, cd = { 6, 6, 6 }, range = T(800), heal = { 200, 400, 600 }, noSelf = true,
   noMech = true, school = "shadow", icon = ICON .. "Spell_Shadow_DeathCoil",
   tip = "A coil of death that heals a friendly Undead unit for %d, or hurts a living enemy for half that.",
   check = function(w, u, t)
       if S.isEnemy(u, t) then if S.isUndead(t) then return false, "Can't hurt Undead units." end
       elseif not S.isUndead(t) then return false, "Can only heal Undead units." end
       return true
   end,
   cast = function(w, u, o, t, lv)
       local amt = lvOf(D.Abilities.deathCoil.heal, lv)
       S.event(w, { t = "vfx", kind = "bounce", x1 = u.x, y1 = u.y, x2 = t.x, y2 = t.y })
       fx(w, t.x, t.y, 166808, 1.6, 1.0)
       if S.isEnemy(u, t) then S.damage(w, u, t, amt / 2, "magic", true) else t.hp = min(t.maxhp, t.hp + amt) end
   end,
   ai = function(w, h, en, ctx)
       for _, f in ipairs(ctx.friends) do
           if f ~= h and S.isUndead(f) and f.maxhp - f.hp >= 180 and not f.def.mech and S.dist(f.x, f.y, h.x, h.y) < 6 then return { target = f.id } end
       end
       local t = ctx.juiciest(en)
       if t and t.def.hero and not S.isUndead(t) and t.hp < 350 then return { target = t.id } end
   end }
A{ id = "deathPact", name = "Death Pact", key = "E", target = "ally", mana = { 50, 50, 50 }, cd = { 15, 15, 15 }, range = T(800), pct = { 1, 2, 3 }, noHero = true, noSelf = true,
   school = "shadow", icon = ICON .. "Spell_Shadow_DeathPact",
   tip = "Kills one of your units; the Death Knight heals for 100% of its hit points (200% at level 2, 300% at level 3).",
   check = function(w, u, t) if t.owner ~= u.owner then return false, "Must target one of your units." end return true end,
   cast = function(w, u, o, t, lv)
       local heal = t.hp * lvOf(D.Abilities.deathPact.pct, lv)
       fx(w, t.x, t.y, 166808, 1.6, 1.0)
       S.kill(w, t, u)
       u.hp = min(u.maxhp, u.hp + heal)
   end,
   ai = function(w, h, en, ctx)
       if h.hp > h.maxhp * 0.35 or not ctx.fight then return end
       local best
       for _, f in ipairs(ctx.friends) do
           if f ~= h and not f.def.hero and (f.def.summon or f.def.worker) and S.dist(f.x, f.y, h.x, h.y) < 6 and (not best or f.hp > best.hp) then best = f end
       end
       if best then return { target = best.id } end
   end }
A{ id = "unholyAura", name = "Unholy Aura", key = "U", target = "aura", radius = T(900), moveBonus = { 0.1, 0.2, 0.3 }, attackBonus = { 0, 0, 0 }, regenBonus = { 0.5, 1, 1.5 },
   icon = ICON .. "Spell_Shadow_UnholyStrength", tip = "Friendly units nearby move %d%% faster and regenerate hit points faster." }
A{ id = "animateDead", name = "Animate Dead", key = "A", ult = true, target = "none", mana = { 175 }, cd = { 180 }, range = T(400), dur = { 40 }, school = "shadow",
   icon = ICON .. "Spell_Shadow_AnimateDead", tip = "Raises up to 6 dead units nearby as invulnerable fighters for 40 seconds.",
   ready = function(w, u) if #S.corpsesNear(w, u.x, u.y, T(900)) < 1 then return false, "There are no corpses nearby." end return true end,
   cast = function(w, u)
       local n = 0
       for _, c in ipairs(S.corpsesNear(w, u.x, u.y, T(900))) do
           if n >= 6 then break end
           local def = D.Units[c.id]
           if def and not def.hero and not def.mech then
               n = n + 1
               S.takeCorpse(w, c)
               local r = S.summonUnit(w, u.owner, c.id, c.x, c.y, 40)
               r.animated, r.camp, r.sleeping = true, nil, nil
               S.buff(w, r, "invuln", 40)
               fx(w, c.x, c.y, 166808, 1.8, 1.2)
           end
       end
       S.updateSupply(w)
   end,
   ai = function(w, h, en, ctx) if #en >= 4 and #S.corpsesNear(w, h.x, h.y, T(900)) >= 4 then return {} end end }
-- Lich
A{ id = "frostNova", name = "Frost Nova", key = "N", target = "enemy", mana = { 125, 125, 125 }, cd = { 8, 8, 8 }, range = T(800), dmg = { 50, 100, 150 },
   dur = { 4, 6, 8 }, heroDur = { 2, 3, 4 }, school = "frost", icon = ICON .. "Spell_Frost_FrostNova",
   tip = "Blasts enemies around the target with frost: 100 damage to the target and %d to everything near it, and slows them.",
   cast = function(w, u, o, t, lv)
       local ab = D.Abilities.frostNova
       fx(w, t.x, t.y, 166378, T(200) * 2.6, 1.2)
       S.damage(w, u, t, 100, "magic", true)
       for _, e in ipairs(enemies(w, u, t.x, t.y, T(200), true)) do
           if canHurt(e) then
               S.damage(w, u, e, lvOf(ab.dmg, lv), "magic", true)
               e.slow, e.slowFactor, e.slowAttack = durFor(ab, lv, e), 0.5, 0.25
           end
       end
   end,
   ai = function(w, h, en, ctx)
       local c, n = ctx.cluster(en, 1.6)
       if c and (n >= 2 or c.def.hero) then return { target = c.id } end
   end }
A{ id = "frostArmor", name = "Frost Armor", key = "F", target = "ally", mana = { 40, 40, 40 }, cd = { 2, 2, 2 }, range = T(800), armor = { 3, 5, 7 }, dur = { 45, 45, 45 },
   autocast = true, school = "frost", icon = ICON .. "Spell_Frost_FrostArmor02",
   tip = "Gives a friendly unit %d armour for 45 seconds; melee attackers are slowed. Right-click for autocast.",
   check = function(w, u, t) if S.hasBuff(t, "frostArmor") then return false, "Already has Frost Armor." end return true end,
   cast = function(w, u, o, t, lv) S.buff(w, t, "frostArmor", 45, { armor = lvOf(D.Abilities.frostArmor.armor, lv) }) fx(w, t.x, t.y, 166378, 1.4, 1.0, t.id) end,
   ai = function(w, h, en, ctx)
       for _, f in ipairs(ctx.friends) do
           if not f.def.ward and not S.hasBuff(f, "frostArmor") and f.def.dmin and (f.def.hero or (f.def.supply or 1) >= 2) and S.dist(f.x, f.y, h.x, h.y) < 6 then return { target = f.id } end
       end
   end }
A{ id = "darkRitual", name = "Dark Ritual", key = "R", target = "ally", mana = { 25, 25, 25 }, cd = { 15, 15, 15 }, range = T(800), pct = { 0.33, 0.66, 1 }, noHero = true, noSelf = true,
   school = "shadow", icon = ICON .. "Spell_Shadow_DarkRitual",
   tip = "Kills one of your units and turns its hit points into mana for the Lich.",
   check = function(w, u, t) if t.owner ~= u.owner then return false, "Must target one of your units." end return true end,
   cast = function(w, u, o, t, lv)
       local gain = t.hp * lvOf(D.Abilities.darkRitual.pct, lv)
       fx(w, t.x, t.y, 166808, 1.6, 1.0)
       S.kill(w, t, u)
       u.mana = min(u.maxMana, u.mana + gain)
   end,
   ai = function(w, h, en, ctx)
       if h.mana > h.maxMana * 0.3 then return end
       for _, f in ipairs(ctx.friends) do
           if f ~= h and f.def.summon and not f.def.hero and S.dist(f.x, f.y, h.x, h.y) < 6 then return { target = f.id } end
       end
   end }
A{ id = "deathAndDecay", name = "Death and Decay", key = "D", ult = true, target = "point", mana = { 250 }, cd = { 150 }, range = T(1000), dur = { 35 }, channel = true,
   school = "shadow", icon = ICON .. "Spell_Shadow_DeathAndDecay",
   tip = "While the Lich channels (up to 35 seconds) everything in an area, units and buildings, loses 4% of its hit points a second.",
   cast = function(w, u, o)
       u.channel = { ability = "deathAndDecay", x = o.x, y = o.y, t = 35, acc = 0 }
       fx(w, o.x, o.y, 166808, T(300) * 2.4, 35)
   end,
   tick = function(w, u, dt, ch)
       ch.t = ch.t - dt
       if ch.t <= 0 then return false end
       ch.acc = ch.acc + dt
       if ch.acc < 1 then return end
       ch.acc = ch.acc - 1
       for _, e in ipairs(w.list) do
           if alive(e) and (e.kind == "unit" or e.kind == "building") and not e.hidden and e.owner ~= 0 then
               local d = e.kind == "unit" and dist(e.x, e.y, ch.x, ch.y) or S.edgeDist(ch.x, ch.y, e)
               if d <= T(300) and (e.kind == "building" or canHurt(e)) and e ~= u then S.damage(w, u, e, max(1, e.maxhp * 0.04), "magic", true) end
           end
       end
   end,
   ai = function(w, h, en, ctx)
       local c, n = ctx.cluster(en, 2.2)
       if c and n >= 5 then return { x = c.x, y = c.y } end
   end }
-- Dreadlord
A{ id = "carrionSwarm", name = "Carrion Swarm", key = "C", target = "point", mana = { 100, 100, 100 }, cd = { 10, 10, 10 }, range = T(700), dmg = { 75, 125, 200 },
   cap = { 400, 700, 1200 }, school = "shadow", icon = ICON .. "Spell_Shadow_CarrionSwarm",
   tip = "Sends a swarm of bats through the enemy line: %d damage to each unit it passes.",
   cast = function(w, u, o, t, lv)
       local ab = D.Abilities.carrionSwarm
       local dx, dy = (o.x or u.x) - u.x, (o.y or u.y) - u.y
       local d = max(0.1, sqrt(dx * dx + dy * dy))
       dx, dy = dx / d, dy / d
       u.facing = atan2(dy, dx)
       local len = T(800)
       for s = 0.8, len, 1.2 do fx(w, u.x + dx * s, u.y + dy * s, 166808, 1.2 + s * 0.25, 0.8, nil, s / 16) end
       local left = lvOf(ab.cap, lv)
       local each = lvOf(ab.dmg, lv)
       for _, e in ipairs(w.list) do
           if left <= 0 then break end
           if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.hidden and canHurt(e) then
               local rx, ry = e.x - u.x, e.y - u.y
               local along = rx * dx + ry * dy
               local width = T(100) + (T(300) - T(100)) * max(0, along) / len
               if along > 0 and along <= len and abs(rx * dy - ry * dx) <= width / 2 + e.def.radius then
                   S.damage(w, u, e, min(each, left), "magic", true)
                   left = left - each
               end
           end
       end
   end,
   ai = function(w, h, en, ctx)
       if ctx.closest and ctx.cd < 5 and ctx.countNear(en, ctx.closest.x, ctx.closest.y, 2.2) >= 3 then return { x = ctx.closest.x, y = ctx.closest.y } end
   end }
A{ id = "dreadSleep", name = "Sleep", key = "S", target = "enemy", mana = { 80, 65, 50 }, cd = { 4, 4, 4 }, range = T(800), dur = { 15, 35, 55 }, heroDur = { 4, 8, 12 },
   noMech = true, school = "shadow", icon = ICON .. "Spell_Nature_Sleep",
   tip = "Puts an enemy to sleep for %d seconds (less on heroes). Damage wakes it.",
   cast = function(w, u, o, t, lv)
       local d = durFor(D.Abilities.dreadSleep, lv, t)
       S.buff(w, t, "sleep", d)
       S.stunUnit(w, t, d)
       t.order = nil
       fx(w, t.x, t.y, 166808, 1.4, 1.0, t.id)
   end,
   ai = function(w, h, en, ctx)
       local t = ctx.juiciest(en)
       if t and (t.def.hero or (t.def.supply or 1) >= 3) and not S.hasBuff(t, "sleep") and t ~= ctx.closest then return { target = t.id } end
   end }
A{ id = "vampiricAura", name = "Vampiric Aura", key = "V", target = "aura", radius = T(900), lifesteal = { 0.2, 0.35, 0.5 },
   icon = ICON .. "Spell_Shadow_LifeDrain", tip = "Friendly melee units nearby heal themselves with every blow (part of the damage they deal)." }
A{ id = "inferno", name = "Inferno", key = "I", ult = true, target = "point", mana = { 175 }, cd = { 180 }, range = T(900), dmg = { 50 }, school = "fire",
   icon = ICON .. "Spell_Shadow_SummonInfernal", tip = "Calls an Infernal down from the sky: %d damage and a stun to enemies where it lands. It fights for 3 minutes.",
   cast = function(w, u, o)
       fx(w, o.x, o.y, 166187, 3.2, 1.4)
       for _, e in ipairs(enemies(w, u, o.x, o.y, T(250), false)) do
           if canHurt(e) then S.damage(w, u, e, 50, "magic", true) S.stunUnit(w, e, e.def.hero and 2 or 4) end
       end
       S.summonUnit(w, u.owner, "infernal", o.x, o.y, 180)
       S.updateSupply(w)
   end,
   ai = function(w, h, en, ctx)
       local c, n = ctx.cluster(en, 2)
       if c and n >= 3 then return { x = c.x, y = c.y } end
   end }
-- Crypt Lord
A{ id = "impale", name = "Impale", key = "E", target = "point", mana = { 100, 100, 100 }, cd = { 9, 9, 9 }, range = T(700), dmg = { 75, 120, 165 },
   dur = { 2, 3, 4 }, heroDur = { 1, 2, 3 }, school = "nature", icon = ICON .. "Ability_Rogue_Ambush",
   tip = "Spikes burst from the ground in a line, throwing enemies into the air: %d damage and a stun.",
   cast = function(w, u, o, t, lv)
       local ab = D.Abilities.impale
       local dx, dy = (o.x or u.x) - u.x, (o.y or u.y) - u.y
       local d = max(0.1, sqrt(dx * dx + dy * dy))
       dx, dy = dx / d, dy / d
       u.facing = atan2(dy, dx)
       local len = T(700)
       for s = 0.8, len, 1.0 do fx(w, u.x + dx * s, u.y + dy * s, 165976, 1.6, 0.9, nil, s / 18) end
       for _, e in ipairs(w.list) do
           if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.hidden and not e.def.air and canHurt(e) then
               local rx, ry = e.x - u.x, e.y - u.y
               local along = rx * dx + ry * dy
               if along > 0 and along <= len and abs(rx * dy - ry * dx) <= T(250) / 2 + e.def.radius then
                   S.damage(w, u, e, lvOf(ab.dmg, lv), "magic", true)
                   if alive(e) then S.stunUnit(w, e, durFor(ab, lv, e)) end
               end
           end
       end
   end,
   ai = function(w, h, en, ctx)
       if ctx.closest and ctx.cd < 5 and ctx.countNear(en, ctx.closest.x, ctx.closest.y, 2) >= 2 then return { x = ctx.closest.x, y = ctx.closest.y } end
   end }
A{ id = "spikedCarapace", name = "Spiked Carapace", key = "C", target = "passive", armor = { 3, 5, 7 }, reflect = { 0.15, 0.25, 0.35 },
   icon = ICON .. "Spell_Nature_Thorns", tip = "+%d armour, and melee attackers take part of the damage they deal back." }
A{ id = "carrionScarabs", name = "Carrion Scarabs", key = "S", target = "none", mana = { 30, 30, 30 }, cd = { 6, 6, 6 }, range = T(900), autocast = true,
   school = "nature", icon = ICON .. "Ability_Hunter_Pet_Crab",
   tip = "Raises a Carrion Scarab from a corpse (5 at most). They live until killed. Right-click for autocast.",
   ready = function(w, u)
       if #S.corpsesNear(w, u.x, u.y, T(900)) < 1 then return false, "There are no corpses nearby." end
       local n = 0
       for _, e in ipairs(w.list) do if e.kind == "unit" and alive(e) and e.scarabOf == u.id then n = n + 1 end end
       if n >= 5 then return false, "You have 5 Carrion Scarabs already." end
       return true
   end,
   cast = function(w, u, o, t, lv)
       local c = S.corpsesNear(w, u.x, u.y, T(900))[1]
       if not c then return end
       S.takeCorpse(w, c)
       local s = S.summonUnit(w, u.owner, "carrionScarab" .. lv, c.x, c.y, nil)
       s.scarabOf = u.id
       fx(w, c.x, c.y, 165976, 1.2, 0.8)
       S.updateSupply(w)
   end,
   heroAuto = function(w, u) return true end,
   ai = function(w, h, en, ctx) return {} end }
A{ id = "locustSwarm", name = "Locust Swarm", key = "L", ult = true, target = "none", mana = { 150 }, cd = { 180 }, dur = { 30 }, school = "nature",
   icon = ICON .. "Spell_Nature_InsectSwarm", tip = "For 30 seconds a swarm of locusts bites enemies around the Crypt Lord; what they eat heals him.",
   cast = function(w, u) S.buff(w, u, "locusts", 30) fx(w, u.x, u.y, 166492, 3.5, 30, u.id) end,
   ai = function(w, h, en, ctx) if #en >= 4 then return {} end end }

-- ------------------------------------------------------------------ hooks into the combat code

local prevSpellImmune = S.spellImmune
function S.spellImmune(u)
    if S.hasBuff(u, "ams") then return true end
    return prevSpellImmune(u)
end

local prevInvisible = S.isInvisible
function S.isInvisible(u)
    if u.kind == "unit" and u.buffs and u.buffs.burrowed then return true end
    return prevInvisible(u)
end

local prevCanAct = S.canAct
function S.canAct(u)
    if u.buffs and u.buffs.burrowed then return false end
    return prevCanAct(u)
end

local prevArmor = S.armorExtra
function S.armorExtra(u)
    local a = prevArmor and prevArmor(u) or 0
    local b = u.buffs
    if b and b.frostArmor and b.frostArmor.t > 0 then a = a + b.frostArmor.armor end
    local sc = u.skills and u.skills.spikedCarapace
    if sc and sc > 0 then a = a + lvOf(D.Abilities.spikedCarapace.armor, sc) end
    return a
end

local prevAttack = S.attackExtra
function S.attackExtra(u, m)
    m = prevAttack and prevAttack(u, m) or m
    local b = u.buffs
    if b then
        if b.frenzy and b.frenzy.t > 0 then m = m + 0.75 end
        if b.cripple and b.cripple.t > 0 then m = m * 0.5 end
    end
    if u.def.id == "ghoul" then
        local w = S.currentWorld
        local fl = w and S.bonus(w, u).flags
        if fl and fl.frenzy then m = m + 0.25 end
    end
    return m
end

local prevMove = S.moveExtra
function S.moveExtra(u, m)
    m = prevMove and prevMove(u, m) or m
    local b = u.buffs
    if b then
        if b.cripple and b.cripple.t > 0 then m = m * 0.25 end
        if b.burrowed then m = 0 end
    end
    if u.def.id == "ghoul" and (u.def.speed or 0) > 0 then
        local w = S.currentWorld
        local fl = w and S.bonus(w, u).flags
        if fl and fl.frenzy then m = m + T(80) / u.def.speed end
    end
    return m
end

local prevRoll = S.rollExtra
function S.rollExtra(w, u, d)
    d = prevRoll and prevRoll(w, u, d) or d
    local b = u.buffs
    if b and b.cripple and b.cripple.t > 0 then d = d * 0.5 end
    return d
end

-- on every blow a Destroyer (Orb of Annihilation) lands
local prevOnHit = S.onHitExtra
function S.onHitExtra(w, src, tgt, d)
    d = prevOnHit and prevOnHit(w, src, tgt, d) or d
    if src.def.orbAnnihilation then
        d = d + 20
        if tgt.kind == "unit" then
            for _, e in ipairs(enemies(w, src, tgt.x, tgt.y, T(150), tgt.def.air and true or false)) do
                if e ~= tgt then S.damage(w, src, e, (d + 20) * 0.45, "magic") end
            end
        end
    end
    -- Orb of Corruption (item)
    if src.ib and src.ib.orb == "corruption" and tgt.kind == "unit" then S.buff(w, tgt, "corrupted", tgt.def.hero and 3 or 10) end
    return d
end

-- after an attack lands: frost slows, Freezing Breath, Disease Cloud, Vampiric Aura, Spiked Carapace, Frost Armor
function S.landExtra(w, src, tgt, dmg, wp)
    if not src or not alive(tgt) then
        if src and src.kind == "unit" and src.aura and src.aura.lifesteal and (src.def.range or 0) < 1.5 then src.hp = min(src.maxhp, src.hp + dmg * src.aura.lifesteal) end
        return
    end
    local def = src.def
    if tgt.kind == "unit" then
        local frost = def.frostAttack or (src.kind == "building" and def.attack and def.attack.frost)
        if frost and not S.spellImmune(tgt) and not tgt.def.mech then
            tgt.slow, tgt.slowFactor, tgt.slowAttack = tgt.def.hero and 2 or 5, 0.25, 0.25
        end
    elseif tgt.kind == "building" and def.id == "frostWyrm" then
        local fl = S.bonus(w, src).flags
        if fl and fl.freezingBreath then tgt.frozenT = w.time + 5 fx(w, tgt.x, tgt.y, 166378, tgt.size * 1.4, 1.0) end
    end
    if src.kind ~= "unit" then return end
    -- Meat Wagon shots leave a disease cloud (Disease Cloud research)
    if def.id == "meatWagon" then
        local fl = S.bonus(w, src).flags
        if fl and fl.disease then
            w.areas = w.areas or {}
            local owner, sid = src.owner, src.id
            w.areas[#w.areas + 1] = { kind = "plagueCloud", x = tgt.x, y = tgt.y, r = T(200), t = 10, owner = owner, src = sid,
                tick = function(w, a, dt, s, fake)
                    a.acc = (a.acc or 0) + dt
                    if a.acc < 1 then return end
                    a.acc = 0
                    for _, e in ipairs(enemies(w, fake, a.x, a.y, a.r, false)) do if living(e) then S.buff(w, e, "plague", 30, { src = a.src }) end end
                end }
            fx(w, tgt.x, tgt.y, 166492, 2.4, 10)
        end
    end
    -- Vampiric Aura: melee blows heal the attacker
    if src.aura and src.aura.lifesteal and (def.range or 0) < 1.5 then src.hp = min(src.maxhp, src.hp + dmg * src.aura.lifesteal) end
    -- Spiked Carapace hurts melee attackers
    local sc = tgt.skills and tgt.skills.spikedCarapace
    if sc and sc > 0 and (def.range or 0) < 1.5 and alive(src) then
        S.damage(w, tgt, src, dmg * lvOf(D.Abilities.spikedCarapace.reflect, sc), "normal", true)
    end
    -- Frost Armor slows melee attackers
    if tgt.buffs and tgt.buffs.frostArmor and (def.range or 0) < 1.5 and alive(src) and not S.spellImmune(src) then
        src.slow, src.slowFactor, src.slowAttack = src.def.hero and 2 or 5, 0.3, 0.25
    end
end

-- per unit per tick
local prevStep = S.stepExtra
function S.stepExtra(w, u, dt)
    if prevStep and prevStep(w, u, dt) then return true end
    -- channelled unit spells (Possession, Cannibalize); heroes channel in stepHero
    local ch = u.channel
    if ch and not u.def.hero then
        local ab = D.Abilities[ch.ability]
        if (u.stun or 0) > 0 or (u.order and u.order.type ~= "cast") or not (ab and ab.tick) then
            u.channel = nil
        elseif ab.tick(w, u, dt, ch) == false then
            u.channel = nil
        end
        if not alive(u) then return true end
    end
    local b = u.buffs
    if b then
        -- Unholy Frenzy costs 4 hit points a second; disease (Disease Cloud) 1 a second
        if b.frenzy then
            b.frenzy.acc = (b.frenzy.acc or 0) + 4 * dt
            if b.frenzy.acc >= 4 then
                local n = floor(b.frenzy.acc)
                b.frenzy.acc = b.frenzy.acc - n
                u.hp = u.hp - n
                if u.hp <= 0 then u.hp = 1 end
            end
        end
        if b.plague then
            b.plague.acc = (b.plague.acc or 0) + dt
            if b.plague.acc >= 1 then
                b.plague.acc = b.plague.acc - 1
                S.damage(w, w.ents[b.plague.src or 0], u, 1, "magic", true)
                if not alive(u) then return true end
            end
        end
        -- Locust Swarm: bites enemies all around the Crypt Lord and heals him
        if b.locusts then
            b.locusts.acc = (b.locusts.acc or 0) + dt
            while b.locusts.acc >= 0.1 do
                b.locusts.acc = b.locusts.acc - 0.1
                local list = enemies(w, u, u.x, u.y, T(800), true)
                if #list == 0 then break end
                local e = list[w.rng.next() % #list + 1]
                if canHurt(e) then
                    local before = e.hp
                    S.damage(w, u, e, 14, "magic", true)
                    u.hp = min(u.maxhp, u.hp + max(0, before - max(0, e.hp)) * 0.75)
                end
            end
        end
        if b.burrowed then
            u.hp = min(u.maxhp, u.hp + 2 * dt)
            u.anim = "stand"
        end
    end
    local def = u.def
    -- Gargoyle in Stone Form heals fast
    if def.stoneOf then u.hp = min(u.maxhp, u.hp + 10 * dt) u.anim = "stand" end
    -- Abominations with Disease Cloud
    if def.id == "abomination" then
        u.cloudT = (u.cloudT or 0) - dt
        if u.cloudT <= 0 then
            u.cloudT = 1
            local fl = S.bonus(w, u).flags
            if fl and fl.disease then
                for _, e in ipairs(enemies(w, u, u.x, u.y, T(176), false)) do if living(e) then S.buff(w, e, "plague", 120, { src = u.id }) end end
            end
        end
    end
    -- Exhume Corpses: a Meat Wagon makes a corpse every 15 seconds
    if def.id == "meatWagon" then
        local fl = S.bonus(w, u).flags
        if fl and fl.exhume and (u.cargo or 0) < 8 then
            u.exhumeT = (u.exhumeT or 15) - dt
            if u.exhumeT <= 0 then u.exhumeT = 15 u.cargo = (u.cargo or 0) + 1 end
        end
    end
    -- hero autocast (Frost Armor, Carrion Scarabs) for anyone's heroes
    if def.hero and def.faction == "undead" and u.skills then
        u.heroAutoT = (u.heroAutoT or 0) - dt
        if u.heroAutoT <= 0 then
            u.heroAutoT = 0.5
            local o = u.order
            if not (o and (o.type == "cast" or o.type == "move")) and not u.channel and not S.isInvisible(u) then
                if (u.skills.frostArmor or 0) > 0 and S.autocastOn(u, "frostArmor") and S.canCast(w, u, "frostArmor") then
                    for _, e in ipairs(w.list) do
                        if e.kind == "unit" and alive(e) and e.owner == u.owner and not e.def.ward and not S.hasBuff(e, "frostArmor") and e.def.dmin
                           and (w.time - (e.hitT or -99)) < 3 and S.gap(u, e) <= D.Abilities.frostArmor.range then
                            S.doCast(w, u, { ability = "frostArmor", target = e.id })
                            break
                        end
                    end
                end
                if (u.skills.carrionScarabs or 0) > 0 and S.autocastOn(u, "carrionScarabs") and S.canCast(w, u, "carrionScarabs") then
                    S.doCast(w, u, { ability = "carrionScarabs" })
                end
            end
        end
    end
    return false
end

-- deaths: corpses for the dead (creeps too), haunted mines go back to plain mines
local prevDeath = S.deathExtra
function S.deathExtra(w, e)
    if prevDeath then prevDeath(w, e) end
    if (e.cargo or 0) > 0 then
        for i = 1, e.cargo do S.addCorpse(w, e.x + cos(i) * 0.7, e.y + sin(i) * 0.7, e.owner) end
        e.cargo = 0
    end
    -- creeps leave corpses too (the players' own are added in Heroes' onDeath)
    if e.owner > 2 and not e.def.summon and not e.def.air and not e.def.mech and not e.illusion then
        w.corpses = w.corpses or {}
        w.corpses[#w.corpses + 1] = { id = e.def.id, owner = e.owner, x = e.x, y = e.y, t = w.time, ent = e }
    end
end

-- the dead don't leave corpses of machines; give every corpse an id for drawing
local prevOnDeath = S.onDeath
function S.onDeath(w, e)
    local n = #(w.corpses or EMPTY)
    prevOnDeath(w, e)
    local list = w.corpses or EMPTY
    for i = n + 1, #list do
        local c = list[i]
        if c and not c.cid then w.corpseId = (w.corpseId or 0) + 1 c.cid = w.corpseId end
    end
    if (e.def.mech or e.noCorpse or e.animated) and list[#list] and list[#list].ent == e then table.remove(list) end
end

-- a building being destroyed: a haunted mine leaves the gold mine behind
function S.buildingGone(w, b)
    if b.mine then
        local m = w.ents[b.mine]
        if m and m.haunted == b.id then m.haunted, m.slots = nil, nil end
    end
end

-- ------------------------------------------------------------------ the Sacrificial Pit

-- the pit's "Shade" button: the nearest Acolyte walks into the pit and a Shade comes out
local prevTrain = S.train
function S.train(w, p, bId, uid)
    local def = D.Units[uid]
    if not def or not def.sacrifice then return prevTrain(w, p, bId, uid) end
    local b = w.ents[bId]
    if not alive(b) or b.owner ~= p or not b.built then return false end
    local best, bd
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and e.owner == p and e.def.id == "acolyte" and not e.hidden then
            local d = dist(e.x, e.y, b.x, b.y)
            if not bd or d < bd then best, bd = e, d end
        end
    end
    if not best then return false, "You need an Acolyte to sacrifice." end
    if #b.queue >= 7 then return false, "The queue is full." end
    best.noCorpse = true
    S.kill(w, best, nil, true)
    best.removed = true
    fx(w, b.x, b.y, 166808, 2.2, 1.2)
    S.updateSupply(w)
    return prevTrain(w, p, bId, uid)
end

-- ------------------------------------------------------------------ items from the Tomb of Relics

do
    local function I(t) t.icon = ICON .. t.icon D.Items[t.id] = t end
    I{ id = "rnec", name = "Rod of Necromancy", icon = "INV_Wand_07", class = "charged", level = 2, gold = 150, uses = 3, cd = 2, stock = { 1, 120 },
       tip = "Raises two Skeleton Warriors from a corpse near the hero, for 40 seconds. 3 charges.",
       use = function(w, u)
           local got = useCorpses(w, u.owner, u.x, u.y, T(600), 1)
           if not got[1] then return false, "There are no corpses nearby." end
           for i = 1, 2 do S.summonUnit(w, u.owner, "skeletonWarrior", got[1][1] + (i - 1.5) * 0.6, got[1][2], 40) end
           S.updateSupply(w)
           return true
       end }
    I{ id = "skul", name = "Sacrificial Skull", icon = "INV_Misc_Bone_HumanSkull_01", class = "charged", level = 1, gold = 50, uses = 1, target = "point", range = T(300), stock = { 1, 60 },
       tip = "Spreads blight on the ground where it's used.",
       use = function(w, u, t, x, y)
           S.addBlight(w, x, y, T(400))
           return true
       end }
    I{ id = "ocor", name = "Orb of Corruption", icon = "INV_Misc_Orb_02", class = "permanent", level = 3, gold = 375, dmg = 5, orb = "corruption", corrupt = true, stock = { 1, 120 },
       tip = "+5 damage; attacks take 5 armour from the target for a while." }
end

local prevArmor2 = S.armorExtra
function S.armorExtra(u)
    local a = prevArmor2(u)
    if u.buffs and u.buffs.corrupted and u.buffs.corrupted.t > 0 then a = a - 5 end
    return a
end

-- ------------------------------------------------------------------ the world tick

-- ------------------------------------------------------------------ Unsummon

-- WC3's Acolytes can unsummon an Undead building: it loses 50 hit points a second and, once it's
-- gone, half of what it cost (the upgrades included) comes back. Here the order is given on the
-- building itself, and it needs one of your Acolytes alive to do it.
function S.canUnsummon(w, p, b)
    if not alive(b) or b.owner ~= p or b.kind ~= "building" or b.def.faction ~= "undead" then return false end
    if not b.built then return false, "It isn't finished." end
    if b.unsummoning then return false, "It is already being unsummoned." end
    if b.upgrading or (b.queue and #b.queue > 0) then return false, "Empty its queue first." end
    for _, u in ipairs(w.list) do
        if u.owner == p and u.kind == "unit" and alive(u) and u.def.haunt and u.def.faction == "undead" then return true end
    end
    return false, "You need an Acolyte to unsummon it."
end

function S.unsummon(w, p, bId)
    local b = w.ents[bId]
    local ok, why = S.canUnsummon(w, p, b)
    if not ok then return false, why end
    b.unsummoning = true
    fx(w, b.x, b.y, 166808, b.size * 0.8, 2)
    return true
end

local function stepUnsummon(w, dt)
    for _, b in ipairs(w.list) do
        if b.unsummoning and alive(b) then
            b.hp = b.hp - 50 * dt
            if b.hp <= 0 then
                S.refund(w, b.owner, b.def, 0.5)
                event(w, { t = "unsummoned", x = b.x, y = b.y, owner = b.owner })
                S.kill(w, b, nil, true)
            end
        end
    end
end

function S.stepUndead(w, dt)
    stepUnsummon(w, dt)
    -- blight grows outwards from its sources
    if w.blightSrc then
        w.blightT = (w.blightT or 0) + dt
        if w.blightT >= 0.5 then
            local step = w.blightT * 2
            w.blightT = 0
            local keep = {}
            for _, s in ipairs(w.blightSrc) do
                if s.r < s.max then
                    s.r = min(s.max, s.r + step)
                    S.paintBlight(w, s)
                end
                if s.r < s.max then keep[#keep + 1] = s end
            end
            w.blightSrc = keep
        end
    end
    -- Graveyards make a corpse every 15 seconds, up to 5 lying around each
    w.graveT = (w.graveT or 0) + dt
    if w.graveT >= 1 then
        w.graveT = 0
        for _, b in ipairs(w.list) do
            if b.kind == "building" and alive(b) and b.built and b.def.graveyard then
                b.graveT = (b.graveT or 0) + 1
                if b.graveT >= 15 then
                    b.graveT = 0
                    if #S.corpsesNear(w, b.x, b.y, 2.6) < 5 then
                        local a = w.rng.float() * 2 * pi
                        local x, y = b.x + cos(a) * 2.2, b.y + sin(a) * 2.2
                        local tx, ty = M.tileOf(x, y)
                        if M.walkable(w, tx, ty) then S.addCorpse(w, x, y, b.owner, "ghoul") end
                    end
                end
            end
        end
        -- old corpses rot away
        if w.corpses and #w.corpses > 0 and w.corpses[1].t < w.time - D.CORPSE_LIFE then
            local keep = {}
            for _, c in ipairs(w.corpses) do if corpseAlive(w, c) then keep[#keep + 1] = c end end
            w.corpses = keep
        end
    end
end

-- ------------------------------------------------------------------ the start of a game

-- Undead start with a Necropolis, a Haunted Gold Mine, 3 Acolytes and a Ghoul, on blight
function S.undeadStart(w, p, hall, mine, autoGather)
    local hm = S.addBuilding(w, p, "hauntedMine", mine.tx, mine.ty, true)
    mine.haunted, hm.mine = hm.id, mine.id
    S.addBlight(w, hall.x, hall.y, BLIGHT_R.large, true)
    S.addBlight(w, mine.x, mine.y, BLIGHT_R.large, true)
    local tx, ty = M.nearestOpen(w, floor((hall.x + mine.x) / 2), floor((hall.y + mine.y) / 2) + 2, 6)
    local g = S.addUnit(w, p, "ghoul", (tx or floor(hall.x)) - 0.5, (ty or floor(hall.y + 3)) - 0.5)
    local tree = M.nearestTree(w, hall.x, hall.y, 16)
    if tree and autoGather ~= false then S.issue(w, g, { type = "gather", res = "lumber", tree = tree }) end
end
