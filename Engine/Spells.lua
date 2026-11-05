-- Skirmish engine: spellcasters and unit abilities (Warcraft III).
-- Priest, Sorceress, Shaman, Witch Doctor and Spirit Walker spells (with Adept / Master Training
-- unlocking the second and third), plus Raider Ensnare, Kodo Devour, Batrider Unstable Concoction,
-- Mortar Flare and Berserker Berserk. Autocast for Heal, Inner Fire, Slow and Bloodlust.
-- Invisibility and detection (Flying Machines and Sentry Wards see invisible units).

local _, ns = ...
local E = ns.Engine
local D, M, S = E.Data, E.Map, E.Sim

local floor, abs, max, min, sqrt, atan2, cos, sin = math.floor, math.abs, math.max, math.min, math.sqrt, math.atan2, math.cos, math.sin
local function alive(e) return e and not e.dead and not e.removed end
local function dist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return sqrt(dx * dx + dy * dy) end
local function T(units) return units / 128 end
local ICON = "Interface\\Icons\\"
local EMPTY = {}

local function fx(w, x, y, model, size, life, follow, delay)
    S.event(w, { t = "effect", x = x, y = y, model = model, size = size or 2, life = life or 1.2, follow = follow, delay = delay })
end

-- ------------------------------------------------------------------ unit data

-- WC3 casters: starting mana and mana regeneration (UnitBalance)
for id, m in pairs({ priest = { 75, 0.667 }, sorceress = { 75, 0.667 }, shaman = { 75, 0.667 }, witchDoctor = { 75, 0.667 }, spiritWalker = { 100, 1 } }) do
    local u = D.Units[id]
    if u then u.mana0, u.manaRegen = m[1], m[2] end
end
for _, id in ipairs({ "flyingMachine", "siegeEngine", "demolisher" }) do if D.Units[id] then D.Units[id].mech = true end end
-- Flying Machines have True Sight
D.Units.flyingMachine.detector = T(900)       -- Agyv true sight 900

local SPELLS = {
    priest = { "heal", "dispelMagic", "innerFire" },
    sorceress = { "slow", "invisibility", "polymorph" },
    shaman = { "purge", "lightningShield", "bloodlust" },
    witchDoctor = { "sentryWard", "stasisTrap", "healingWard" },
    spiritWalker = { "spiritLink", "disenchant", "ancestralSpirit", "etherealForm" },
    raider = { "ensnare" },
    kodoBeast = { "devour" },
    batrider = { "unstableConcoction" },
    mortarTeam = { "flare" },
    berserker = { "berserk" },
}
for id, list in pairs(SPELLS) do if D.Units[id] then D.Units[id].spells = list end end

-- wards and traps the Witch Doctor plants
local function WARD(t)
    t.kind, t.summon, t.ward = "unit", true, true
    t.supply, t.gold, t.lumber, t.time, t.armor = 0, 0, 0, 0, 0
    t.dtype, t.speed = "medium", 0
    t.vis = t.vis or 0.3
    t.radius, t.spaced = 0.2, true
    t.sight = t.sight or 6
    t.acquire = 0
    D.Units[t.id] = t
end
WARD{ id = "sentryWard", faction = "orcs", name = "Sentry Ward", role = "ward", hp = 200, sight = T(1600), invisible = true, detector = T(900),
      display = { 4590 }, icon = ICON .. "Spell_Nature_RemoveCurse" }
WARD{ id = "stasisTrap", faction = "orcs", name = "Stasis Trap", role = "ward", hp = 100, sight = T(600), invisible = true, display = { 4589 }, alpha = 0.6,
      icon = ICON .. "Spell_Nature_Slow" }
WARD{ id = "healingWard", faction = "orcs", name = "Healing Ward", role = "ward", hp = 5, sight = T(600), display = { 2030 }, icon = ICON .. "Spell_Holy_LayOnHands" }

-- ------------------------------------------------------------------ invisibility & detection

function S.isInvisible(u)
    if u.kind ~= "unit" then return false end
    local ww = u.buffs and u.buffs.windWalk
    if ww and ww.fadeAt and S.currentWorld and S.currentWorld.time < ww.fadeAt then ww = nil end
    return u.def.invisible or (ww and true) or S.hasBuff(u, "invis")
end

-- detection circles are gathered with vision; Flares reveal invisible units too
function S.updateDetection(w)
    w.detect = { {}, {}, {} }
    for _, e in ipairs(w.list) do
        if alive(e) and e.owner >= 1 and e.owner <= 2 then
            local r = e.def.detector
            -- Magic Sentry: Human towers see invisible units
            if not r and e.kind == "building" and e.built and (e.def.attack or e.def.id == "scoutTower") then
                local b = S.bonus(w, e)
                if b.flags and b.flags.magicSentry then r = T(900) end   -- Adts 900
            end
            if r then
                local t = w.detect[e.owner]
                t[#t + 1] = { e.x, e.y, r }
            end
        end
    end
    for _, r in ipairs(w.reveals or EMPTY) do
        if r.detect and w.detect[r.owner] then local t = w.detect[r.owner] t[#t + 1] = { r.x, r.y, r.r } end
    end
end

function S.detected(w, p, u)
    local t = w.detect and w.detect[p]
    if not t then return false end
    for _, c in ipairs(t) do
        if abs(c[1] - u.x) <= c[3] and abs(c[2] - u.y) <= c[3] and dist(c[1], c[2], u.x, u.y) <= c[3] then return true end
    end
    return false
end

-- ------------------------------------------------------------------ dispelling

-- magic that Dispel Magic, Purge and Disenchant remove
local DISPELLABLE = { innerFire = true, bloodlust = true, slowSpell = true, invis = true, poly = true, hex = true, lightningShield = true,
                      link = true, ensnare = true, purged = true, berserk = true }

local function dispelUnit(w, src, e, summonDmg)
    if e.def.summon or e.illusion then
        if e.illusion then S.kill(w, e, src) return end
        S.damage(w, src, e, summonDmg, "magic", true)
        return
    end
    if e.buffs then
        for id in pairs(e.buffs) do if DISPELLABLE[id] then e.buffs[id] = nil end end
        local eth = e.buffs.ethereal
        if eth and not eth.form then e.buffs.ethereal = nil end
    end
    e.slow = 0
end

local function dispelArea(w, src, x, y, r, summonDmg, model)
    if model then fx(w, x, y, model, r * 2.4, 1.2) end
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and not e.hidden and dist(e.x, e.y, x, y) <= r + e.def.radius * 0.5 then
            dispelUnit(w, src, e, summonDmg)
        end
    end
end

S.dispelArea = function(w, src, x, y, r, summonDmg) return dispelArea(w, src, x, y, r, summonDmg) end

local function plant(w, owner, id, x, y, life)
    local tx, ty = M.tileOf(x, y)
    if not M.walkable(w, tx, ty) then
        local nx, ny = M.nearestOpen(w, tx, ty, 3)
        if nx then x, y = nx - 0.5, ny - 0.5 end
    end
    local u = S.addUnit(w, owner, id, x, y)
    u.life = life
    S.updateSupply(w)
    return u
end

-- ------------------------------------------------------------------ the abilities

local function A(t)
    t.unit, t.maxLevel = true, 1
    for _, f in ipairs({ "mana", "cd", "dur", "heroDur" }) do if type(t[f]) == "number" then t[f] = { t[f] } end end
    D.Abilities[t.id] = t
end

-- Priest
A{ id = "heal", name = "Heal", key = "E", target = "ally", mana = 5, cd = 1, range = T(250), heal = 25, autocast = true, castPoint = 0.3, noMech = true, school = "holy",
   icon = ICON .. "Spell_Holy_Heal", tip = "Heals a wounded friendly unit for 25 hit points. Right-click to turn autocast on or off.",
   check = function(w, u, t) if t.hp >= t.maxhp then return false, "Already at full health." end return true end,
   cast = function(w, u, o, t) t.hp = min(t.maxhp, t.hp + 25) fx(w, t.x, t.y, 166696, 1.6, 1.0, t.id) end }
A{ id = "dispelMagic", name = "Dispel Magic", key = "D", target = "point", mana = 75, cd = 0, range = T(500), radius = T(200), research = { "priestTraining", 1 }, school = "holy",
   icon = ICON .. "Spell_Holy_DispelMagic", tip = "Removes all magic from units in an area. Summoned units take 200 damage.",
   cast = function(w, u, o) dispelArea(w, u, o.x, o.y, T(200), 200, 165955) end }
A{ id = "innerFire", name = "Inner Fire", key = "F", target = "ally", mana = 35, cd = 1, range = T(500), dur = 60, research = { "priestTraining", 2 }, autocast = true, autoOff = true,
   castPoint = 0.3, school = "holy",
   icon = ICON .. "Spell_Holy_InnerFire", tip = "A friendly unit gets 10% more damage and 5 more armour for 60 seconds. Right-click for autocast.",
   cast = function(w, u, o, t) S.buff(w, t, "innerFire", 60) fx(w, t.x, t.y, 166417, 1.6, 1.0, t.id) end }
-- Sorceress
A{ id = "slow", name = "Slow", key = "W", target = "enemy", mana = 50, cd = 1, range = T(700), dur = 60, heroDur = 10, autocast = true, castPoint = 0.3, school = "arcane",
   icon = ICON .. "Spell_Nature_Slow", tip = "Slows an enemy's movement by 60% and its attacks by 25% (60 seconds, 10 on heroes). Right-click for autocast.",
   cast = function(w, u, o, t, lv, durFor) S.buff(w, t, "slowSpell", durFor(t)) fx(w, t.x, t.y, 165857, 1.4, 1.0, t.id) end }
A{ id = "invisibility", noMech = true, name = "Invisibility", key = "I", target = "ally", mana = 50, cd = 0, range = T(300), dur = 120, research = { "sorceressTraining", 1 }, school = "arcane",
   icon = ICON .. "Spell_Magic_LesserInvisibilty", tip = "Makes a friendly unit invisible for 2 minutes, or until it attacks or casts.",
   cast = function(w, u, o, t) S.buff(w, t, "invis", 120) fx(w, t.x, t.y, 166430, 1.6, 0.8) end }
A{ id = "polymorph", name = "Polymorph", key = "O", target = "enemy", mana = 220, cd = 3, range = T(500), dur = 60, research = { "sorceressTraining", 2 }, noHero = true,
   school = "arcane", icon = ICON .. "Spell_Nature_Polymorph", tip = "Turns an enemy into a sheep for 60 seconds. Doesn't work on heroes.",
   cast = function(w, u, o, t) S.buff(w, t, "poly", 60) t.swing = nil t.order = nil fx(w, t.x, t.y, 166649, 1.8, 0.8) end }
-- Shaman
A{ id = "purge", name = "Purge", key = "G", target = "unit", mana = 75, cd = 1, range = T(700), school = "nature", noWard = false, root = 3,
   icon = ICON .. "Spell_Nature_Purge", tip = "Removes all magic from a unit. An enemy is held in place for 3 seconds, then slows to a fifth of its speed and recovers over 15 seconds (5 on heroes); summoned units take 400 damage.",
   cast = function(w, u, o, t)
       fx(w, t.x, t.y, 166665, 1.6, 1.0)
       dispelUnit(w, u, t, 400)
       if alive(t) and S.isEnemy(u, t) and not t.def.summon then
           local ab = D.Abilities[o.ability] or {}
           local d = t.def.hero and (ab.recoverHero or 5) or (ab.recover or 15)
           S.buff(w, t, "purged", d, { dur = d })
           -- the Shaman's Purge (Apg2) also holds the target in place for 3 seconds
           if ab.root then S.buff(w, t, "rooted", ab.root) end
       end
   end }
A{ id = "lightningShield", groundOnly = true, name = "Lightning Shield", key = "L", target = "unit", mana = 100, cd = 3, range = T(600), dur = 20, research = { "shamanTraining", 1 }, school = "nature",
   icon = ICON .. "Spell_Nature_LightningShield", tip = "Wraps a unit in lightning for 20 seconds, dealing 20 damage a second to every unit next to it.",
   cast = function(w, u, o, t) S.buff(w, t, "lightningShield", 20, { src = u.id, owner = u.owner }) end }
A{ id = "bloodlust", name = "Bloodlust", key = "B", target = "ally", mana = 40, cd = 1, range = T(600), dur = 60, research = { "shamanTraining", 2 }, autocast = true,
   castPoint = 0.3, noMech = true, school = "nature",
   icon = ICON .. "Spell_Nature_BloodLust", tip = "A friendly unit attacks 40% faster and moves 25% faster for 60 seconds. Right-click for autocast.",
   cast = function(w, u, o, t, lv, durFor) S.buff(w, t, "bloodlust", durFor and durFor(t) or 60) fx(w, t.x, t.y, 165726, 1.6, 1.0, t.id) end }
-- Witch Doctor
A{ id = "sentryWard", name = "Sentry Ward", key = "W", target = "point", mana = 50, cd = 1, range = T(500), school = "nature",
   icon = ICON .. "Spell_Nature_RemoveCurse", tip = "Plants an invisible ward that watches the area for 10 minutes and sees invisible units.",
   cast = function(w, u, o) plant(w, u.owner, "sentryWard", o.x, o.y, 600) fx(w, o.x, o.y, 165940, 1.4, 1.0) end }
A{ id = "stasisTrap", name = "Stasis Trap", key = "T", target = "point", mana = 100, cd = 0, range = T(500), research = { "witchDoctorTraining", 1 }, school = "shadow",
   icon = ICON .. "Spell_Nature_Slow", tip = "Plants an invisible trap that lasts 150 seconds. When an enemy comes close it stuns every ground enemy nearby for 6 seconds.",
   cast = function(w, u, o) plant(w, u.owner, "stasisTrap", o.x, o.y, 150) end }
A{ id = "healingWard", name = "Healing Ward", key = "E", target = "point", mana = 200, cd = 0, range = T(500), dur = 30, research = { "witchDoctorTraining", 2 }, school = "nature",
   radius = T(500), icon = ICON .. "Spell_Holy_LayOnHands", tip = "Plants a ward that heals nearby friendly units by 2% of their health every second, for 30 seconds.",
   cast = function(w, u, o) plant(w, u.owner, "healingWard", o.x, o.y, 30) end }
-- Spirit Walker
A{ id = "spiritLink", name = "Spirit Link", key = "K", target = "ally", mana = 75, cd = 0, range = T(750), dur = 75, school = "shadow", noMech = true,
   icon = ICON .. "Spell_Shadow_UnholyFrenzy", tip = "Links up to 4 friendly units for 75 seconds; half of the damage any of them takes is shared among the others.",
   cast = function(w, u, o, t)
       w.linkId = (w.linkId or 0) + 1
       local n, list = 0, { t }
       for _, e in ipairs(w.list) do
           if #list < 4 and e ~= t and e.kind == "unit" and alive(e) and e.owner == u.owner and not e.def.ward and not e.def.mech and dist(e.x, e.y, t.x, t.y) <= T(500) then
               list[#list + 1] = e
           end
       end
       for _, e in ipairs(list) do S.buff(w, e, "link", 75, { group = w.linkId }) fx(w, e.x, e.y, 165589, 1.4, 1.0, e.id) end
   end }
A{ id = "disenchant", name = "Disenchant", key = "D", target = "point", mana = 100, cd = 0, range = T(650), radius = T(250), research = { "spiritWalkerTraining", 1 }, school = "nature",
   icon = ICON .. "Spell_Holy_DispelMagic", tip = "Removes all magic from units in an area. Summoned units take 250 damage.",
   cast = function(w, u, o) dispelArea(w, u, o.x, o.y, T(250), 250, 165955) end }
local function taurenCorpse(w, u)
    local best, bd
    for _, c in ipairs(w.corpses or EMPTY) do
        if c.owner == u.owner and c.id == "tauren" and w.time - c.t < 90 then
            local d = dist(c.x, c.y, u.x, u.y)
            if d <= T(350) + 1 and (not bd or d < bd) then best, bd = c, d end
        end
    end
    return best
end
A{ id = "ancestralSpirit", name = "Ancestral Spirit", key = "R", target = "none", mana = 250, cd = 30, research = { "spiritWalkerTraining", 2 }, school = "holy", range = T(350),
   icon = ICON .. "Spell_Nature_Reincarnation", tip = "Brings a fallen Tauren next to the Spirit Walker back to life at full health.",
   ready = function(w, u) if not taurenCorpse(w, u) then return false, "There is no fallen Tauren nearby." end return true end,
   cast = function(w, u)
       local c = taurenCorpse(w, u)
       if not c then return end
       for i, k in ipairs(w.corpses) do if k == c then table.remove(w.corpses, i) break end end
       if c.ent then c.ent.removed = true end
       S.addUnit(w, c.owner, c.id, c.x, c.y)
       fx(w, c.x, c.y, 166324, 2, 1.5)
       S.updateSupply(w)
   end }
A{ id = "etherealForm", name = "Ethereal Form", key = "E", target = "self", mana = 0, cd = 30, precast = false, castPoint = 0.7,
   icon = ICON .. "Spell_Shadow_Twilight", tip = "Turns ethereal: physical attacks pass through, but it can't attack and magic hurts more. Again to return to corporeal form.",
   cast = function(w, u)
       local eth = u.buffs and u.buffs.ethereal
       if eth and eth.form then u.buffs.ethereal = nil
       else S.buff(w, u, "ethereal", 1e9, { form = true }) end
       fx(w, u.x, u.y, 166237, 1.8, 0.8)
   end }
-- Raider, Kodo Beast, Batrider, Mortar Team, Berserker
A{ id = "ensnare", name = "Ensnare", key = "E", target = "enemy", mana = 0, cd = 16, range = T(500), dur = 12, heroDur = 3, research = { "ensnare", 1 }, precast = false,
   castPoint = 0.25, icon = ICON .. "Spell_Nature_StrangleVines", tip = "Throws a net that pins a unit for 12 seconds (3 on heroes). Netted flyers can be hit by ground troops.",
   cast = function(w, u, o, t, lv, durFor) S.buff(w, t, "ensnare", durFor(t)) end }
A{ id = "devour", name = "Devour", key = "D", target = "enemy", mana = 0, cd = 1, range = T(100), precast = false, castPoint = 0.3, noHero = true, groundOnly = true,
   noWard = true, icon = ICON .. "Ability_Racial_Cannibalize", tip = "Swallows an enemy unit whole and digests it (5 damage a second). If the Kodo dies, the unit gets out.",
   ready = function(w, u) if u.devouring and alive(w.ents[u.devouring]) then return false, "Still digesting." end return true end,
   check = function(w, u, t) if (t.def.level or 1) > 5 then return false, "That unit is too big to swallow." end return true end,
   cast = function(w, u, o, t)
       u.devouring = t.id
       t.devouredBy = u.id
       t.hidden = true
       t.order, t.swing, t.channel = nil, nil, nil
       S.updateSupply(w)
   end }
A{ id = "unstableConcoction", name = "Unstable Concoction", key = "C", target = "enemy", mana = 0, cd = 1, range = 0.6, airOnly = true, precast = false, castPoint = 0.1,
   icon = ICON .. "INV_Potion_24", tip = "The Batrider dives into a flying enemy and explodes: 600 damage to it and 140 to other flyers nearby.",
   cast = function(w, u, o, t)
       fx(w, t.x, t.y - 1, 165744, 3, 1.4)
       S.damage(w, u, t, 600, "magic", true)
       for _, e in ipairs(w.list) do
           if e ~= t and e.kind == "unit" and alive(e) and e.def.air and S.isEnemy(u, e) and dist(e.x, e.y, t.x, t.y) <= T(280) then S.damage(w, u, e, 140, "magic", true) end
       end
       S.kill(w, u, nil)
   end }
A{ id = "flare", name = "Flare", key = "F", target = "anywhere", mana = 0, cd = 120, range = 999, research = { "flare", 1 }, precast = false, castPoint = 0.4, radius = T(1800),
   icon = ICON .. "Spell_Fire_Flare", tip = "Fires a flare that lights up an area for 15 seconds, showing invisible units too.",
   cast = function(w, u, o)
       w.reveals = w.reveals or {}
       w.reveals[#w.reveals + 1] = { owner = u.owner, x = o.x, y = o.y, r = T(1800), t = 15, detect = true }
       fx(w, o.x, o.y, 166196, 2.5, 15)
       S.updateVision(w)
   end }
A{ id = "berserk", name = "Berserk", key = "B", target = "self", mana = 0, cd = 30, dur = 12, precast = false, castPoint = 0.1, castAnim = "roar",
   icon = ICON .. "Ability_Racial_BloodRage", tip = "For 12 seconds the Berserker attacks 50% faster and moves 20% faster, but takes 50% more damage.",
   cast = function(w, u) S.buff(w, u, "berserk", 12) fx(w, u.x, u.y, 165726, 1.6, 1.0, u.id) end }

-- ------------------------------------------------------------------ per tick for casters, wards, devouring

-- autocast: Heal, Inner Fire, Slow and Bloodlust go off on their own (WC3 behaviour), when the
-- caster isn't busy walking somewhere, gathering or building
local AUTO = {
    spellSteal = function(w, u, ab) return S.autoSpellSteal(w, u, ab) end,
    lesserHeal = function(w, u, ab)
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and e ~= u and e.owner == u.owner and alive(e) and not e.def.mech and e.maxhp - e.hp >= 12 and S.gap(u, e) <= ab.range then return e end
        end
    end,
    heal = function(w, u, ab)
        local best, bf
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and e ~= u and e.owner == u.owner and alive(e) and not e.def.mech and not e.def.ward and e.maxhp - e.hp >= 20 and not e.hidden then
                if abs(e.x - u.x) <= ab.range + 1 and abs(e.y - u.y) <= ab.range + 1 and S.gap(u, e) <= ab.range then
                    local f = e.hp / e.maxhp
                    if not bf or f < bf then best, bf = e, f end
                end
            end
        end
        return best
    end,
    innerFire = function(w, u, ab)
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and e.owner == u.owner and alive(e) and not e.def.mech and not e.def.worker and not e.def.ward and not S.hasBuff(e, "innerFire")
               and e.def.dmin and ((e.order and (e.order.type == "attack" or e.order.target)) or (w.time - (e.hitT or -99)) < 3) and S.gap(u, e) <= ab.range then
                return e
            end
        end
    end,
    bloodlust = function(w, u, ab)
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and e.owner == u.owner and alive(e) and not e.def.mech and not e.def.worker and not e.def.ward and not S.hasBuff(e, "bloodlust")
               and e.def.dmin and ((e.order and (e.order.type == "attack" or e.order.target)) or (w.time - (e.hitT or -99)) < 3) and S.gap(u, e) <= ab.range then
                return e
            end
        end
    end,
    slow = function(w, u, ab)
        local best, bs
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.hidden and not e.def.ward and not S.hasBuff(e, "slowSpell") and not S.spellImmune(e)
               and S.targetable(w, u, e) and abs(e.x - u.x) <= ab.range + 1 and abs(e.y - u.y) <= ab.range + 1 and S.gap(u, e) <= ab.range then
                local s = (e.def.hero and 50 or 0) + (e.def.supply or 1)
                if not bs or s > bs then best, bs = e, s end
            end
        end
        return best
    end,
}
-- creep versions autocast the same way
AUTO.creepInnerFire, AUTO.creepBloodlust, AUTO.creepSlow = AUTO.innerFire, AUTO.bloodlust, AUTO.slow
AUTO.rejuvenation = function(w, u, ab)
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and e.owner == u.owner and alive(e) and not e.def.mech and not e.def.ward and e.maxhp - e.hp >= 150
           and not S.hasBuff(e, "rejuv") and S.gap(u, e) <= ab.range then return e end
    end
end
S.AUTO = AUTO

function S.autocastOn(u, abId)
    if u.autocast and u.autocast[abId] ~= nil then return u.autocast[abId] end
    -- WC3 defaults: Heal, Slow and Bloodlust start switched on; Inner Fire starts off
    local ab = D.Abilities[abId]
    return ab.autocast == true and not ab.autoOff
end

function S.toggleAutocast(w, p, ids, abId)
    local on
    for _, id in ipairs(ids) do
        local u = w.ents[id]
        if u and u.owner == p and (u.def.spells or u.def.hero) then
            if on == nil then on = not S.autocastOn(u, abId) end
            u.autocast = u.autocast or {}
            u.autocast[abId] = on
        end
    end
    return on
end

-- returns true when the unit should skip the rest of its tick (swallowed by a Kodo)
function S.stepCaster(w, u, dt)
    -- swallowed: ride inside the Kodo
    if u.devouredBy then
        local k = w.ents[u.devouredBy]
        if not alive(k) then
            u.devouredBy, u.hidden = nil, false
            S.updateSupply(w)
        else
            u.x, u.y = k.x, k.y
            u.digest = (u.digest or 0) + 5 * dt
            if u.digest >= 1 then
                local n = floor(u.digest)
                u.digest = u.digest - n
                S.damage(w, k, u, n, "chaos", true)
            end
            return true
        end
    end
    if u.devouring and not alive(w.ents[u.devouring]) then u.devouring = nil end
    -- Lightning Shield burns everything standing next to the shielded unit
    local ls = u.buffs and u.buffs.lightningShield
    if ls then
        ls.acc = (ls.acc or 0) + 20 * dt
        if ls.acc >= 4 then
            local n = floor(ls.acc)
            ls.acc = ls.acc - n
            local src = w.ents[ls.src or 0]
            for _, e in ipairs(w.list) do
                if e ~= u and e.kind == "unit" and alive(e) and not e.hidden and abs(e.x - u.x) < 2 and abs(e.y - u.y) < 2 and dist(e.x, e.y, u.x, u.y) <= T(160) + e.def.radius + u.def.radius then
                    S.damage(w, src, e, n, "magic", true)
                end
            end
        end
    end
    local def = u.def
    -- wards
    if def.id == "healingWard" then
        u.healT = (u.healT or 0) + dt
        if u.healT >= 0.5 then
            u.healT = u.healT - 0.5
            for _, e in ipairs(w.list) do
                if e.kind == "unit" and e.owner == u.owner and alive(e) and not e.def.mech and not e.def.ward and e.hp < e.maxhp and dist(e.x, e.y, u.x, u.y) <= T(500) then
                    e.hp = min(e.maxhp, e.hp + e.maxhp * 0.01)
                end
            end
        end
        return
    elseif def.id == "stasisTrap" then
        if u.springT then
            u.springT = u.springT - dt
            if u.springT <= 0 then
                fx(w, u.x, u.y, 166988, 3, 1.2)
                for _, e in ipairs(w.list) do
                    if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.def.air and not e.hidden and dist(e.x, e.y, u.x, u.y) <= T(400) and not S.spellImmune(e) then
                        S.stunUnit(w, e, 6)
                    end
                end
                S.kill(w, u, nil, true)
                u.removed = true
            end
        else
            u.scanT = (u.scanT or 0) - dt
            if u.scanT <= 0 then
                u.scanT = 0.3
                for _, e in ipairs(w.list) do
                    if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.def.air and not e.hidden and not e.def.ward and dist(e.x, e.y, u.x, u.y) <= T(250) then
                        u.springT = 1
                        break
                    end
                end
            end
        end
        return
    end
    -- mana and cooldowns for casters (heroes do theirs in stepHero)
    if def.hero or not def.spells then return end
    if u.maxMana and u.maxMana > 0 then
        local regen = (def.manaRegen or 0.667) + (S.bonus(w, u).manaRegen or 0) + (u.aura and u.aura.mana or 0)
        u.mana = min(u.maxMana, (u.mana or 0) + regen * dt)
    end
    if u.abilityCd then for k, v in pairs(u.abilityCd) do if v > 0 then u.abilityCd[k] = v - dt end end end
    -- autocast
    u.autoT = (u.autoT or (u.id % 5) * 0.08) - dt
    if u.autoT > 0 then return end
    u.autoT = 0.4
    local o = u.order
    if o and (o.type == "move" or o.type == "gather" or o.type == "build" or o.type == "cast") then return end
    if (u.stun or 0) > 0 or u.swing or u.channel or S.isInvisible(u) then return end
    for _, abId in ipairs(def.spells) do
        local fn = AUTO[abId]
        local ab = D.Abilities[abId]
        local pl = w.players[u.owner]
        if fn and (S.autocastOn(u, abId) or u.owner == 3 or (ab.aiAuto and pl and type(pl.ai) == "table")) and S.canCast(w, u, abId) then
            local tgt = fn(w, u, ab)
            if tgt then
                u.facing = atan2(tgt.y - u.y, tgt.x - u.x)
                S.doCast(w, u, { ability = abId, target = tgt.id, x = tgt.x, y = tgt.y })
                return
            end
        end
    end
end

-- Spirit Link: half the damage a linked unit takes is spread over the others in its link
function S.linkShare(w, tgt, src, dmg)
    local l = tgt.buffs and tgt.buffs.link
    if not l or l.t <= 0 or dmg < 2 then return dmg end
    local others = {}
    for _, e in ipairs(w.list) do
        if e ~= tgt and e.kind == "unit" and alive(e) and e.buffs and e.buffs.link and e.buffs.link.group == l.group and e.buffs.link.t > 0 then
            others[#others + 1] = e
        end
    end
    if #others == 0 then return dmg end
    local share = dmg * 0.5
    local each = share / #others
    for _, e in ipairs(others) do
        e.hp = e.hp - each
        if e.hp <= 0 then S.kill(w, e, src) end
    end
    return dmg - share
end

-- a Kodo that dies lets its meal go
local onDeath = S.onDeath
function S.onDeath(w, e)
    if e.devouring then
        local v = w.ents[e.devouring]
        if v then v.devouredBy, v.hidden = nil, false v.x, v.y = e.x + 0.6, e.y end
        e.devouring = nil
    end
    if e.devouredBy then return end   -- digested: no corpse
    return onDeath(w, e)
end

-- caster training: extra mana and hit points (Adept and Master Training)
function S.casterBonus(rid, lv)
    local sw = rid == "spiritWalkerTraining"
    return (sw and 150 or 100) * lv, (sw and 0.42 or 0.325) * lv, (sw and 60 or 40) * lv
end
