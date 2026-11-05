-- Skirmish engine: the Tavern and its eight neutral heroes (Warcraft III: The Frozen Throne).
-- Dark Ranger, Beastmaster, Pandaren Brewmaster, Naga Sea Witch, Pit Lord, Goblin Tinker,
-- Goblin Alchemist and Firelord, with their 32 abilities. Numbers are from War3.mpq
-- (UnitBalance / UnitWeapons / AbilityData). WoW has no WC3 models, so each hero uses the
-- closest WoW creature: a Timbermaw Ursa for the Brewmaster, a Doomguard Commander for the Pit Lord...
-- Tavern heroes cost 425 gold and 135 lumber, need one of your units next to the Tavern, and each
-- can be hired by only one player. The usual hero rules apply (3 at most, tier 2 / 3 for the
-- second and third, the first is free); a fallen tavern hero is revived at your Altar.

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

-- ------------------------------------------------------------------ the heroes

local function TH(t)
    H(t)
    t.faction, t.tavern = "neutral", true
    t.gold, t.lumber = 425, 135
end

TH{ id = "darkRanger", name = "Dark Ranger", primary = "agi", str = 18, agi = 21, int = 15, strUp = 1.9, agiUp = 1.5, intUp = 2.6,
    armor = 0, sides = 6, cd = 2.42, dmgpt = 0.7, range = T(600), speed = T(320), display = { 1679 }, missile = "arrow",
    icon = ICON .. "INV_Weapon_Bow_02", key = "D", abilities = { "silence", "blackArrow", "lifeDrain", "charm" },
    tip = "Cunning ranged hero. Silence stops enemy spells, Black Arrow raises the dead she kills, Charm steals a unit." }
TH{ id = "beastmaster", name = "Beastmaster", primary = "str", str = 22, agi = 14, int = 15, strUp = 2.9, agiUp = 1.3, intUp = 1.8,
    armor = 0, sides = 6, cd = 2.2, dmgpt = 0.3, range = T(128), speed = T(320), display = { 4624 },
    icon = ICON .. "Ability_Hunter_BeastCall", key = "B", abilities = { "summonBear", "summonQuilbeast", "summonHawk", "stampede" },
    tip = "Warrior hero who calls up a bear, a quilbeast and a hawk, and sends a Stampede through the enemy." }
TH{ id = "brewmaster", name = "Pandaren Brewmaster", primary = "str", str = 22, agi = 14, int = 15, strUp = 3, agiUp = 1.5, intUp = 1.5,
    armor = 1, sides = 6, cd = 2.22, dmgpt = 0.35, range = T(100), speed = T(290), display = { 6746 },
    icon = ICON .. "INV_Drink_04", key = "P", abilities = { "breathOfFire", "drunkenHaze", "drunkenBrawler", "stormEarthFire" },
    tip = "Warrior hero. Drunken Haze makes enemies miss, Breath of Fire sets hazed enemies alight, and he dodges blows." }
TH{ id = "seaWitch", name = "Naga Sea Witch", primary = "int", str = 15, agi = 16, int = 22, strUp = 2, agiUp = 1, intUp = 3,
    armor = 0, sides = 6, cd = 1.9, dmgpt = 0.73, range = T(600), speed = T(290), display = { 11263 }, missile = "frost",
    icon = ICON .. "Spell_Frost_FrostBolt02", key = "N", abilities = { "forkedLightning", "frostArrows", "manaShield", "tornado" },
    tip = "Mystical ranged hero. Frost Arrows slow, Forked Lightning hits three enemies, Mana Shield soaks up damage." }
TH{ id = "pitLord", name = "Pit Lord", primary = "str", str = 26, agi = 14, int = 14, strUp = 3.2, agiUp = 1.3, intUp = 1.5,
    armor = 0, sides = 6, cd = 2.05, dmgpt = 0.8, range = T(100), speed = T(300), display = { 4426 },
    icon = ICON .. "Spell_Shadow_SummonInfernal", key = "L", abilities = { "rainOfFire", "howlOfTerror", "cleavingAttack", "doom" },
    tip = "Warrior hero. Cleaving Attack hits everything around his target; Rain of Fire burns an area; Doom makes a demon of a unit." }
TH{ id = "tinker", name = "Goblin Tinker", primary = "int", str = 20, agi = 15, int = 20, strUp = 2.4, agiUp = 1, intUp = 2.6,
    armor = 2, sides = 4, cd = 2, dmgpt = 0.35, range = T(128), speed = T(290), display = { 7109 },
    icon = ICON .. "INV_Gizmo_01", key = "T", abilities = { "pocketFactory", "clusterRockets", "engineeringUpgrade", "roboGoblin" },
    tip = "Mystical hero. Pocket Factories churn out exploding goblins; Robo-Goblin turns him into a building-wrecking machine." }
TH{ id = "alchemist", name = "Goblin Alchemist", primary = "str", str = 25, agi = 10, int = 18, strUp = 3.3, agiUp = 1, intUp = 2,
    armor = 0, sides = 10, dice = 3, cd = 2.5, dmgpt = 0.35, range = T(100), speed = T(290), display = { 14402 },
    icon = ICON .. "Trade_Alchemy", key = "A", abilities = { "healingSpray", "acidBomb", "chemicalRage", "transmute" },
    tip = "Warrior hero on an ogre. Healing Spray heals an area, Acid Bomb strips armour, Transmute turns a unit into gold." }
TH{ id = "firelord", name = "Firelord", primary = "agi", str = 15, agi = 20, int = 18, strUp = 2, agiUp = 1.6, intUp = 2.5,
    armor = 0, sides = 4, cd = 1.8, dmgpt = 0.5, range = T(550), speed = T(320), display = { 12231 }, missile = "fire",
    icon = ICON .. "Spell_Fire_Fire", key = "F", abilities = { "soulBurn", "lavaSpawn", "incinerate", "volcano" },
    tip = "Cunning ranged hero of fire. Soul Burn silences, Lava Spawn multiply as they fight, Incinerate makes the dead explode." }

D.TAVERN_HEROES = { "darkRanger", "beastmaster", "brewmaster", "seaWitch", "pitLord", "tinker", "alchemist", "firelord" }

-- ------------------------------------------------------------------ summoned units

-- WC3 damage is base + dice x sides; SU wants the lowest and highest roll
local function dmg(base, dice, sides) return base + dice, base + dice * sides end

for lv, s in ipairs({ { 215, 270, 8, 1, 2 }, { 290, 300, 14, 1, 3 }, { 405, 330, 15, 1, 4 } }) do
    local lo, hi = dmg(s[3], s[4], s[5])
    SU{ id = "darkMinion" .. lv, faction = "neutral", name = "Dark Minion", role = "melee", hp = s[1], dtype = "heavy", atype = "normal",
        dmin = lo, dmax = hi, cd = 2, dmgpt = 0.5, range = T(90), speed = T(s[2]), display = { 200 }, icon = ICON .. "Spell_Shadow_RaiseDead", vis = 0.38, level = lv + 1 }
end
for lv, s in ipairs({ { 600, 0, 18, 320 }, { 900, 1, 27, 320 }, { 1200, 2, 37, 350 } }) do
    local lo, hi = dmg(s[3], 1, 3)
    SU{ id = "bear" .. lv, faction = "neutral", name = "Bear", role = "melee", hp = s[1], armor = s[2], dtype = "heavy", atype = "normal",
        dmin = lo, dmax = hi, cd = 1.5, dmgpt = 0.5, range = T(128), speed = T(s[4]), display = { lv < 3 and 719 or 820 },
        bash = lv >= 2 and { 25, 25, 2, 1 } or nil, icon = ICON .. "Ability_Racial_BearForm", vis = 0.5, level = lv + 3 }
end
for lv, s in ipairs({ { 425, 12, 1 }, { 515, 24, 2 }, { 600, 36, 3 } }) do
    local lo, hi = dmg(s[2], s[3], 3)
    SU{ id = "quilbeast" .. lv, faction = "neutral", name = "Quilbeast", role = "ranged", hp = s[1], dtype = "medium", atype = "pierce",
        dmin = lo, dmax = hi, cd = 1.5, dmgpt = 0.5, range = T(550), speed = T(300), display = { lv < 3 and 381 or 744 }, missile = "arrow", hitsAir = true,
        icon = ICON .. "Ability_Hunter_Pet_Boar", vis = 0.45, level = lv + 2 }
end
for lv, s in ipairs({ { 300, 0, 0, 0 }, { 450, 3, 20, 5 }, { 650, 5, 45, 12 } }) do
    SU{ id = "hawk" .. lv, faction = "neutral", name = "Hawk", role = "air", air = true, hp = s[1], armor = s[2], dtype = "light", atype = "magic",
        dmin = max(1, s[3] + 1), dmax = max(1, s[3] + s[4]), cd = 1.5, dmgpt = 0.4, range = T(300), speed = T(350), display = { 6299 }, missile = "lightning",
        hitsAir = true, detector = T(900), invisible = lv >= 3 or nil, icon = ICON .. "Ability_Hunter_Pet_Owl", vis = 0.45, level = lv + 1 }
end
D.Units.hawk1.dmin, D.Units.hawk1.noAttack = nil, true
-- Storm, Earth and Fire
SU{ id = "pandaFire", faction = "neutral", name = "Fire", role = "melee", hp = 1100, armor = 2, dtype = "heavy", atype = "normal",
    dmin = 68, dmax = 82, cd = 1.35, dmgpt = 0.5, range = T(128), speed = T(300), display = { 1204 }, burnAura = 10, selfBurn = 0,
    icon = ICON .. "Spell_Fire_Fire", vis = 0.5, level = 6 }
SU{ id = "pandaStorm", faction = "neutral", name = "Storm", role = "ranged", hp = 1200, armor = 2, dtype = "heavy", atype = "pierce",
    dmin = 49, dmax = 57, cd = 1.5, dmgpt = 0.5, range = T(500), speed = T(300), display = { 14253 }, missile = "lightning", hitsAir = true,
    icon = ICON .. "Spell_Nature_Cyclone", vis = 0.5, level = 6 }
SU{ id = "pandaEarth", faction = "neutral", name = "Earth", role = "melee", hp = 1700, armor = 5, dtype = "heavy", atype = "normal",
    dmin = 49, dmax = 57, cd = 1.35, dmgpt = 0.5, range = T(128), speed = T(300), display = { 14511 }, spellImmune = true,
    pulverize = { 20, 40, T(250) }, onHit = true, icon = ICON .. "Spell_Nature_EarthShock", vis = 0.55, level = 6 }
SU{ id = "tornadoSummon", faction = "neutral", name = "Tornado", role = "ward", hp = 500, dtype = "heavy", atype = "normal",
    dmin = 1, dmax = 1, cd = 99, range = 0.1, speed = T(75), display = { 5327 }, spellImmune = true, tornado = true, noAttack = true,
    icon = ICON .. "Spell_Nature_Cyclone", vis = 0.6 }
D.Units.tornadoSummon.dmin = nil
SU{ id = "doomGuard", faction = "neutral", name = "Doom Guard", role = "melee", hp = 1600, armor = 3, dtype = "heavy", atype = "chaos",
    dmin = 41, dmax = 48, cd = 1.8, dmgpt = 0.5, range = T(100), speed = T(270), display = { 1912 }, icon = ICON .. "Spell_Shadow_SummonFelGuard", vis = 0.6, level = 8 }
for lv, hp in ipairs({ 300, 450, 600 }) do
    SU{ id = "pocketFactory" .. lv, faction = "neutral", name = "Pocket Factory", role = "ward", hp = hp, dtype = "medium", atype = "normal",
        dmin = 1, dmax = 1, cd = 99, range = 0.1, speed = 0, modelFile = 197767, mech = true, factory = lv, noAttack = true,
        icon = ICON .. "INV_Gizmo_02", vis = 0.6, ward = true }
    D.Units["pocketFactory" .. lv].dmin = nil
end
for lv, boom in ipairs({ 12, 22, 30 }) do
    SU{ id = "clockwerk" .. lv, faction = "neutral", name = "Clockwerk Goblin", role = "melee", hp = 80, armor = 1, dtype = "heavy", atype = "normal",
        dmin = 12, dmax = 14, cd = 1, dmgpt = 0.4, range = T(60), speed = T(270), display = { 7204 }, mech = true, selfDestruct = boom,
        icon = ICON .. "INV_Gizmo_01", vis = 0.32 }
end
for lv, s in ipairs({ { 425, 0, 7, 4 }, { 550, 1, 15, 6 }, { 700, 2, 26, 6 } }) do
    local lo, hi = dmg(s[3], s[4], 5)
    SU{ id = "lavaSpawn" .. lv, faction = "neutral", name = "Lava Spawn", role = "ranged", hp = s[1], armor = s[2], dtype = "heavy", atype = "pierce",
        dmin = lo, dmax = hi, cd = 1.5, dmgpt = 0.5, range = T(300), speed = T(300), display = { 2172 }, missile = "fire", hitsAir = true,
        splitAfter = 12, onHit = true, icon = ICON .. "Spell_Fire_Volcano", vis = 0.45, level = lv + 3 }
end

-- ------------------------------------------------------------------ the abilities

local function durFor(ab, lv, e)
    local d = ab.dur and lvOf(ab.dur, lv)
    if e and e.def.hero and ab.heroDur then return lvOf(ab.heroDur, lv) end
    return d
end

-- Dark Ranger
A{ id = "silence", name = "Silence", key = "Q", target = "point", mana = { 75, 75, 75 }, cd = { 15, 15, 15 }, range = T(900),
   radiusL = { T(200), T(275), T(350) }, dur = { 16, 20, 24 }, heroDur = { 8, 10, 12 }, school = "shadow",
   icon = ICON .. "Spell_Shadow_ImpPhaseShift", tip = "Enemies in an area can't cast spells for %d seconds.",
   cast = function(w, u, o, tgt, lv)
       local ab = D.Abilities.silence
       local r = lvOf(ab.radiusL, lv)
       fx(w, o.x, o.y, 166808, r * 2.4, 1.2)
       for _, e in ipairs(enemies(w, u, o.x, o.y, r, true)) do
           if canHurt(e) then S.buff(w, e, "silence", durFor(ab, lv, e)) e.channel = nil end
       end
   end,
   ai = function(w, h, en, ctx)
       local c, n = ctx.cluster(en, 2)
       local casters = 0
       for _, e in ipairs(en) do if (e.maxMana or 0) > 0 and (e.mana or 0) > 50 then casters = casters + 1 end end
       if c and casters >= 2 then return { x = c.x, y = c.y } end
   end }
A{ id = "blackArrow", name = "Black Arrow", key = "W", target = "passive", autocast = true, mana = { 6, 6, 6 }, bonus = { 2, 10, 20 },
   icon = ICON .. "Ability_TheBlackArrow", tip = "Her arrows deal %d extra damage (6 mana each). A unit killed while hit by one rises as a Dark Minion for 80 seconds. Right-click to switch on or off." }
A{ id = "lifeDrain", name = "Life Drain", key = "E", target = "enemy", mana = { 50, 50, 50 }, cd = { 8, 8, 8 }, range = T(500), dur = { 8, 8, 8 },
   drain = { 30, 45, 60 }, channel = true, school = "shadow", noMech = true,
   icon = ICON .. "Spell_Shadow_LifeDrain02", tip = "Drains %d hit points a second from an enemy into the Dark Ranger, for up to 8 seconds.",
   cast = function(w, u, o, tgt, lv)
       u.channel = { ability = "lifeDrain", target = tgt.id, t = 8, drain = lvOf(D.Abilities.lifeDrain.drain, lv) }
       fx(w, tgt.x, tgt.y, 166536, 1.4, 8, tgt.id)
   end,
   tick = function(w, u, dt, ch)
       local tgt = w.ents[ch.target or 0]
       ch.t = ch.t - dt
       if not alive(tgt) or dist(tgt.x, tgt.y, u.x, u.y) > T(800) or ch.t <= 0 or S.spellImmune(tgt) then return false end
       ch.acc = (ch.acc or 0) + ch.drain * dt
       if ch.acc >= 5 then
           local n = floor(ch.acc)
           ch.acc = ch.acc - n
           S.damage(w, u, tgt, n, "magic", true)
           u.hp = min(u.maxhp, u.hp + n)
       end
   end,
   ai = function(w, h, en, ctx)
       if h.hp < h.maxhp * 0.6 then local t = ctx.juiciest(en) if t and S.dist(t.x, t.y, h.x, h.y) < 5 then return { target = t.id } end end
   end }
A{ id = "charm", name = "Charm", key = "R", ult = true, target = "enemy", mana = { 150 }, cd = { 45 }, range = T(700), noHero = true, school = "shadow",
   icon = ICON .. "Spell_Shadow_Charm", tip = "Takes permanent control of an enemy unit (not a hero; level 5 or lower).",
   check = function(w, u, tgt) if (tgt.def.level or 1) > 5 then return false, "That unit is too powerful." end return true end,
   cast = function(w, u, o, tgt)
       tgt.owner, tgt.order, tgt.camp, tgt.sleeping, tgt.swing = u.owner, nil, nil, nil, nil
       if tgt.buffs then tgt.buffs.sleep = nil end
       fx(w, tgt.x, tgt.y, 166808, 1.8, 1.5, tgt.id)
       S.updateSupply(w)
   end,
   ai = function(w, h, en, ctx)
       local best
       for _, e in ipairs(en) do
           if not e.def.hero and (e.def.level or 1) <= 5 and not e.def.summon and not S.spellImmune(e) and (not best or (e.def.level or 1) > (best.def.level or 1)) then best = e end
       end
       if best and (best.def.level or 1) >= 3 then return { target = best.id } end
   end }

-- Beastmaster
local function summoner(id, unit, mana, cd, icon, name, tip)
    A{ id = id, name = name, key = ({ summonBear = "Q", summonQuilbeast = "W", summonHawk = "E" })[id], target = "none", mana = { mana, mana, mana },
       cd = { cd, cd, cd }, dur = { 70, 70, 70 }, school = "nature", icon = icon, tip = tip,
       cast = function(w, u, o, tgt, lv)
           S.summonUnit(w, u.owner, unit .. lv, u.x + cos(u.facing) * 1.2, u.y + sin(u.facing) * 1.2, 70)
           S.updateSupply(w)
       end,
       ai = function(w, h, en, ctx) if ctx.fight or id == "summonHawk" then return {} end end }
end
summoner("summonBear", "bear", 125, 40, ICON .. "Ability_Racial_BearForm", "Summon Bear", "Summons a Bear for 70 seconds (it can Bash from level 2).")
summoner("summonQuilbeast", "quilbeast", 75, 25, ICON .. "Ability_Hunter_Pet_Boar", "Summon Quilbeast", "Summons a Quilbeast that throws quills, for 70 seconds.")
summoner("summonHawk", "hawk", 50, 70, ICON .. "Ability_Hunter_Pet_Owl", "Summon Hawk", "Summons a Hawk that scouts and sees invisible units, for 70 seconds (it attacks from level 2, is invisible at 3).")
A{ id = "stampede", name = "Stampede", key = "R", ult = true, target = "point", mana = { 150 }, cd = { 180 }, range = T(300), dur = { 30 },
   channel = true, dmg = { 55 }, school = "nature", icon = ICON .. "Ability_Hunter_BeastCall02",
   tip = "While he channels (up to 30 seconds), beasts charge through the area in front of him, %d damage each.",
   cast = function(w, u, o, tgt, lv)
       local dx, dy = (o.x or u.x) - u.x, (o.y or u.y) - u.y
       local d = max(0.1, sqrt(dx * dx + dy * dy))
       u.channel = { ability = "stampede", t = 30, dx = dx / d, dy = dy / d, every = 0.2, n = 0 }
   end,
   tick = function(w, u, dt, ch)
       ch.t = ch.t - dt
       ch.n = ch.n - dt
       if ch.t <= 0 then return false end
       if ch.n > 0 then return end
       ch.n = ch.every
       -- a beast runs through a random spot of the area ahead
       local along, side = 1 + w.rng.float() * T(1000) * 0.8, (w.rng.float() - 0.5) * T(1000)
       local x, y = u.x + ch.dx * along - ch.dy * side, u.y + ch.dy * along + ch.dx * side
       fx(w, x, y, 165976, 1.4, 0.6)
       for _, e in ipairs(enemies(w, u, x, y, T(60) + 0.4, false)) do S.damage(w, u, e, 55, "magic", true) end
       for _, b in ipairs(w.list) do
           if b.kind == "building" and alive(b) and S.isEnemy(u, b) and S.edgeDist(x, y, b) <= 0.4 then S.damage(w, u, b, 55, "magic", true) end
       end
   end,
   ai = function(w, h, en, ctx) if #en >= 5 and ctx.closest then return { x = ctx.closest.x, y = ctx.closest.y } end end }

-- Pandaren Brewmaster
A{ id = "breathOfFire", name = "Breath of Fire", key = "Q", target = "point", mana = { 70, 70, 70 }, cd = { 10, 10, 10 }, range = T(375),
   dmg = { 65, 125, 170 }, burn = { 7, 14, 21 }, school = "fire", icon = ICON .. "Spell_Fire_Fireball02",
   tip = "Breathes a cone of fire: %d damage; enemies in Drunken Haze catch fire and keep burning.",
   cast = function(w, u, o, tgt, lv)
       local ab = D.Abilities.breathOfFire
       local dx, dy = (o.x or u.x) - u.x, (o.y or u.y) - u.y
       local d = max(0.1, sqrt(dx * dx + dy * dy))
       dx, dy = dx / d, dy / d
       u.facing = atan2(dy, dx)
       local len = T(375) + T(300)
       for s = 0.8, len, 1.1 do fx(w, u.x + dx * s, u.y + dy * s, 166187, 1.2 + s * 0.35, 0.8, nil, s / 20) end
       for _, e in ipairs(w.list) do
           if alive(e) and (e.kind == "unit" or e.kind == "building") and S.isEnemy(u, e) and not e.hidden then
               local rx, ry = e.x - u.x, e.y - u.y
               local along = rx * dx + ry * dy
               local width = T(125) + (T(300) - T(125)) * max(0, along) / len
               if along > 0 and along <= len + (e.size or 0) / 2 and abs(rx * dy - ry * dx) <= width / 2 + (e.size or 0) / 2 + 0.3 then
                   if e.kind == "building" or canHurt(e) then
                       S.damage(w, u, e, lvOf(ab.dmg, lv), "magic", true)
                       if e.kind == "unit" and S.hasBuff(e, "haze") and alive(e) then
                           e.poisonT, e.poisonOwner, e.poisonDps = 5, u.id, lvOf(ab.burn, lv)
                       end
                   end
               end
           end
       end
   end,
   ai = function(w, h, en, ctx)
       if ctx.closest and ctx.cd < 3 and ctx.countNear(en, ctx.closest.x, ctx.closest.y, 2) >= 2 then return { x = ctx.closest.x, y = ctx.closest.y } end
   end }
A{ id = "drunkenHaze", name = "Drunken Haze", key = "W", target = "enemy", mana = { 70, 70, 70 }, cd = { 12, 12, 12 }, range = T(550),
   miss = { 0.45, 0.65, 0.8 }, slowL = { 0.15, 0.3, 0.5 }, dur = { 12, 12, 12 }, heroDur = { 5, 5, 5 }, noMech = true, school = "nature",
   icon = ICON .. "INV_Drink_05", tip = "Drenches enemies in an area with alcohol: they move slower and miss many of their attacks.",
   cast = function(w, u, o, tgt, lv)
       local ab = D.Abilities.drunkenHaze
       fx(w, tgt.x, tgt.y, 166492, 2.4, 1.2)
       for _, e in ipairs(enemies(w, u, tgt.x, tgt.y, T(200), true)) do
           if canHurt(e) and not e.def.mech then
               S.buff(w, e, "haze", durFor(ab, lv, e), { miss = lvOf(ab.miss, lv), slow = lvOf(ab.slowL, lv) })
           end
       end
   end,
   ai = function(w, h, en, ctx)
       local c, n = ctx.cluster(en, 1.6)
       if c and (n >= 2 or c.def.hero) and not S.hasBuff(c, "haze") then return { target = c.id } end
   end }
A{ id = "drunkenBrawler", name = "Drunken Brawler", key = "E", target = "passive", evade = { 7, 14, 21 }, mult = { 2, 3, 4 },
   icon = ICON .. "Ability_Rogue_Feint", tip = "Dodges %d%% of attacks against him, and 10% of his blows deal extra damage." }
A{ id = "stormEarthFire", name = "Storm, Earth and Fire", key = "R", ult = true, target = "self", mana = { 150 }, cd = { 180 }, dur = { 45 },
   school = "nature", icon = ICON .. "Spell_Nature_EarthShock",
   tip = "Splits into three spirits - Storm, Earth and Fire - for 45 seconds; he comes back when they are gone.",
   cast = function(w, u, o, tgt, lv)
       local ids = {}
       for i, id in ipairs({ "pandaStorm", "pandaEarth", "pandaFire" }) do
           local a = u.facing + (i - 2) * 1.6
           local p = S.summonUnit(w, u.owner, id, u.x + cos(a) * 1.1, u.y + sin(a) * 1.1, 45)
           ids[#ids + 1] = p.id
       end
       u.sef = { t = 45, ids = ids }
       u.hidden, u.order, u.path, u.swing = true, nil, nil, nil
       S.buff(w, u, "invuln", 46)
       S.updateSupply(w)
   end,
   ai = function(w, h, en, ctx) if #en >= 4 then return {} end end }

-- Naga Sea Witch
A{ id = "forkedLightning", name = "Forked Lightning", key = "Q", target = "enemy", mana = { 110, 110, 110 }, cd = { 11, 11, 11 }, range = T(600),
   dmg = { 85, 160, 250 }, school = "nature", icon = ICON .. "Spell_Nature_ChainLightning",
   tip = "Lightning forks into up to three enemies in front of her, %d damage each.",
   cast = function(w, u, o, tgt, lv)
       local d0 = lvOf(D.Abilities.forkedLightning.dmg, lv)
       local hit = { tgt }
       local dx, dy = tgt.x - u.x, tgt.y - u.y
       local dl = max(0.1, sqrt(dx * dx + dy * dy))
       for _, e in ipairs(enemies(w, u, tgt.x, tgt.y, T(300), true)) do
           if #hit >= 3 then break end
           local ex, ey = e.x - u.x, e.y - u.y
           if e ~= tgt and canHurt(e) and (ex * dx + ey * dy) / dl > 0 then hit[#hit + 1] = e end
       end
       for _, e in ipairs(hit) do
           S.event(w, { t = "vfx", kind = "bounce", x1 = u.x, y1 = u.y, x2 = e.x, y2 = e.y })
           S.damage(w, u, e, d0, "magic", true)
       end
   end,
   ai = function(w, h, en, ctx) local t = ctx.juiciest(en) if t and #en >= 2 then return { target = t.id } end end }
A{ id = "frostArrows", name = "Frost Arrows", key = "W", target = "passive", autocast = true, mana = { 10, 10, 10 }, bonus = { 5, 10, 15 },
   slowL = { 0.3, 0.5, 0.7 }, atkSlow = { 0.3, 0.5, 0.7 }, icon = ICON .. "Spell_Frost_ChillingBlast",
   tip = "Her arrows deal %d extra cold damage and slow the target (10 mana each). Right-click to switch on or off." }
A{ id = "manaShield", name = "Mana Shield", key = "E", target = "self", mana = { 25, 25, 25 }, cd = { 10, 10, 10 }, ratio = { 1, 1.5, 2 }, school = "arcane",
   icon = ICON .. "Spell_Shadow_DetectLesserInvisibility", tip = "Damage she takes drains mana instead (%s damage per point of mana). Cast again to turn it off.",
   cast = function(w, u, o, tgt, lv)
       if S.hasBuff(u, "manaShield") then u.buffs.manaShield = nil u.abilityCd.manaShield = 0 u.mana = u.mana + 25 return end
       S.buff(w, u, "manaShield", 1e9, { ratio = lvOf(D.Abilities.manaShield.ratio, lv) })
       fx(w, u.x, u.y, 166526, 2, 1.5, u.id)
   end,
   ai = function(w, h, en, ctx) if ctx.fight and not S.hasBuff(h, "manaShield") and h.hp < h.maxhp * 0.7 and h.mana > 150 then return {} end end }
A{ id = "tornado", name = "Tornado", key = "R", ult = true, target = "point", mana = { 200 }, cd = { 120 }, range = T(700), dur = { 40 },
   school = "nature", icon = ICON .. "Spell_Nature_Cyclone", tip = "Summons a Tornado for 40 seconds that slows and damages enemies around it and tears at buildings.",
   cast = function(w, u, o, tgt, lv)
       local t = S.summonUnit(w, u.owner, "tornadoSummon", o.x, o.y, 40)
       t.home = { o.x, o.y }
       S.updateSupply(w)
   end,
   ai = function(w, h, en, ctx) local c, n = ctx.cluster(en, 3) if c and n >= 4 then return { x = c.x, y = c.y } end end }

-- Pit Lord
A{ id = "rainOfFire", name = "Rain of Fire", key = "Q", target = "point", mana = { 85, 85, 85 }, cd = { 8, 8, 8 }, range = T(800), radius = T(200),
   waves = { 6, 8, 10 }, dmg = { 25, 30, 35 }, burn = { 5, 10, 15 }, channel = true, school = "fire", icon = ICON .. "Spell_Shadow_RainOfFire",
   tip = "Fire rains on an area while he channels: %d damage a wave, and the ground keeps burning.",
   cast = function(w, u, o, tgt, lv)
       local ab = D.Abilities.rainOfFire
       u.channel = { ability = "rainOfFire", x = o.x, y = o.y, waves = lvOf(ab.waves, lv), dmg = lvOf(ab.dmg, lv), burn = lvOf(ab.burn, lv), t = 0.1 }
   end,
   tick = function(w, u, dt, ch)
       ch.t = ch.t - dt
       if ch.t > 0 then return end
       ch.t = 1
       ch.waves = ch.waves - 1
       local r = T(200)
       fx(w, ch.x, ch.y, 166187, r * 2.4, 1.2)
       for _, e in ipairs(w.list) do
           if alive(e) and (e.kind == "unit" or e.kind == "building") and S.isEnemy(u, e) and not e.hidden and dist(e.x, e.y, ch.x, ch.y) <= r + (e.size or 0) / 2 then
               if e.kind == "building" or canHurt(e) then
                   S.damage(w, u, e, ch.dmg * (e.kind == "building" and 0.5 or 1), "magic", true)
                   if e.kind == "unit" and alive(e) then e.poisonT, e.poisonOwner, e.poisonDps = 3, u.id, ch.burn end
               end
           end
       end
       if ch.waves <= 0 then return false end
   end,
   ai = function(w, h, en, ctx) local c, n = ctx.cluster(en, 1.6) if c and n >= 3 then return { x = c.x, y = c.y } end end }
A{ id = "howlOfTerror", name = "Howl of Terror", key = "W", target = "none", mana = { 75, 75, 75 }, cd = { 12, 12, 12 }, pct = { 0.3, 0.4, 0.5 },
   dur = { 15, 15, 15 }, school = "shadow", icon = ICON .. "Spell_Shadow_DeathScream",
   tip = "Enemies nearby are terrified and deal less damage for 15 seconds.",
   cast = function(w, u, o, tgt, lv)
       fx(w, u.x, u.y, 166808, T(500) * 2, 1.4)
       for _, e in ipairs(enemies(w, u, u.x, u.y, T(500), true)) do
           if canHurt(e) then S.buff(w, e, "howl", 15, { pct = lvOf(D.Abilities.howlOfTerror.pct, lv) }) end
       end
   end,
   ai = function(w, h, en, ctx) if ctx.countNear(en, h.x, h.y, T(500)) >= 4 then return {} end end }
A{ id = "cleavingAttack", name = "Cleaving Attack", key = "E", target = "passive", pct = { 0.3, 0.55, 0.8 }, icon = ICON .. "Ability_Warrior_Cleave",
   tip = "His blows also hit enemies around the target for part of the damage." }
A{ id = "doom", name = "Doom", key = "R", ult = true, target = "enemy", mana = { 150 }, cd = { 120 }, range = T(650), noHero = true, noMech = true,
   school = "shadow", icon = ICON .. "Spell_Shadow_AntiShadow", tip = "Dooms a unit: it can't cast spells and takes 40 damage a second until it dies, then a Doom Guard rises from it.",
   cast = function(w, u, o, tgt) S.buff(w, tgt, "doom", 1e9, { owner = u.owner, src = u.id }) fx(w, tgt.x, tgt.y, 166808, 1.8, 2, tgt.id) end,
   ai = function(w, h, en, ctx)
       local best
       for _, e in ipairs(en) do if not e.def.hero and not S.spellImmune(e) and not e.def.mech and e.hp > 400 and (not best or e.hp > best.hp) then best = e end end
       if best then return { target = best.id } end
   end }

-- Goblin Tinker
local function engLevel(u) return S.skillLevel(u, "engineeringUpgrade") end
A{ id = "pocketFactory", name = "Pocket Factory", key = "Q", target = "point", mana = { 125, 125, 125 }, cd = { 35, 35, 35 }, range = T(500), dur = { 40, 40, 40 },
   school = "arcane", icon = ICON .. "INV_Gizmo_02", tip = "Builds a factory for 40 seconds that turns out Clockwerk Goblins, which explode when they die.",
   cast = function(w, u, o, tgt, lv)
       local f = S.summonUnit(w, u.owner, "pocketFactory" .. lv, o.x, o.y, 40)
       f.makeT, f.every = 1, ({ 5, 4, 3.2, 2.56 })[engLevel(u) + 1]
       S.updateSupply(w)
   end,
   ai = function(w, h, en, ctx) if ctx.fight and ctx.closest then return { x = (h.x + ctx.closest.x) / 2, y = (h.y + ctx.closest.y) / 2 } end end }
A{ id = "clusterRockets", name = "Cluster Rockets", key = "W", target = "point", mana = { 70, 70, 70 }, cd = { 6, 6, 6 }, range = T(800),
   dmg = { 105, 195, 300 }, school = "fire", icon = ICON .. "INV_Misc_Bomb_04",
   tip = "Fires rockets into an area: %d damage over a second, stunning enemies for a moment.",
   cast = function(w, u, o, tgt, lv)
       local r = ({ T(200), T(230), T(260), T(290) })[engLevel(u) + 1]
       local total = lvOf(D.Abilities.clusterRockets.dmg, lv)
       w.areas = w.areas or {}
       w.areas[#w.areas + 1] = { kind = "rockets", x = o.x, y = o.y, r = r, t = 1.01, owner = u.owner, src = u.id, hits = 3, per = total / 3, next = 0,
           tick = function(w2, a, dt, src, fake)
               a.next = a.next - dt
               if a.next > 0 or a.hits <= 0 then return end
               a.next, a.hits = 0.33, a.hits - 1
               fx(w2, a.x + (w2.rng.float() - 0.5) * a.r, a.y + (w2.rng.float() - 0.5) * a.r, 166187, 1.6, 0.6)
               for _, e in ipairs(w2.list) do
                   if alive(e) and (e.kind == "unit" or e.kind == "building") and S.isEnemy(fake, e) and not e.hidden and dist(e.x, e.y, a.x, a.y) <= a.r + (e.size or 0) / 2 then
                       if e.kind == "building" or canHurt(e) then
                           S.damage(w2, src, e, a.per, "magic", true)
                           if e.kind == "unit" and alive(e) and a.hits == 2 then S.stunUnit(w2, e, 1) end
                       end
                   end
               end
           end }
   end,
   ai = function(w, h, en, ctx) local c, n = ctx.cluster(en, 1.8) if c and (n >= 3 or c.def.hero) then return { x = c.x, y = c.y } end end }
A{ id = "engineeringUpgrade", name = "Engineering Upgrade", key = "E", target = "passive", move = { 0.1, 0.2, 0.3 }, bonus = { 2, 4, 6 },
   icon = ICON .. "Trade_Engineering", tip = "He moves faster and hits harder, and his other abilities get better: faster factories, wider rockets, a tougher Robo-Goblin." }
A{ id = "roboGoblin", name = "Robo-Goblin", key = "R", ult = true, target = "self", mana = { 25 }, cd = { 1 }, school = "arcane", icon = ICON .. "INV_Gizmo_03",
   tip = "Turns into (or out of) a Robo-Goblin: tougher armour, mechanical, and wrecks buildings.",
   cast = function(w, u, o, tgt, lv)
       if S.hasBuff(u, "robo") then u.buffs.robo = nil
       else
           local el = engLevel(u)
           S.buff(w, u, "robo", 1e9, { armor = ({ 5, 7, 9, 11 })[el + 1], demolish = ({ 2, 2.5, 3, 3.5 })[el + 1] })
       end
       fx(w, u.x, u.y, 165594, 2.2, 1)
   end,
   ai = function(w, h, en, ctx)
       if not S.hasBuff(h, "robo") and ctx.fight then return {} end
   end }

-- Goblin Alchemist
A{ id = "healingSpray", name = "Healing Spray", key = "Q", target = "point", mana = { 75, 75, 75 }, cd = { 6, 6, 6 }, range = T(800), heal = { 40, 55, 70 },
   school = "nature", icon = ICON .. "INV_Potion_51", tip = "Sprays a healing mist: friends in the area regain %d hit points a second for 6 seconds.",
   cast = function(w, u, o, tgt, lv)
       local hps = lvOf(D.Abilities.healingSpray.heal, lv)
       w.areas = w.areas or {}
       w.areas[#w.areas + 1] = { kind = "spray", x = o.x, y = o.y, r = T(250), t = 6, owner = u.owner, src = u.id, acc = 0,
           tick = function(w2, a, dt)
               a.acc = a.acc + dt
               if a.acc < 1 then return end
               a.acc = a.acc - 1
               fx(w2, a.x, a.y, 166324, a.r * 2.2, 1)
               for _, e in ipairs(w2.list) do
                   if e.kind == "unit" and alive(e) and e.owner == a.owner and not e.def.mech and dist(e.x, e.y, a.x, a.y) <= a.r then e.hp = min(e.maxhp, e.hp + hps) end
               end
           end }
   end,
   ai = function(w, h, en, ctx)
       local hurt, x, y = 0, 0, 0
       for _, f in ipairs(ctx.friends) do if f.hp < f.maxhp * 0.7 and not f.def.mech then hurt, x, y = hurt + 1, x + f.x, y + f.y end end
       if hurt >= 3 then return { x = x / hurt, y = y / hurt } end
   end }
A{ id = "acidBomb", name = "Acid Bomb", key = "W", target = "enemy", mana = { 75, 75, 75 }, cd = { 12, 12, 12 }, range = T(700), armorL = { 3, 4, 5 },
   dps = { 8, 13, 18 }, splashDps = { 5, 8.5, 12 }, dur = { 15, 15, 15 }, school = "nature", icon = ICON .. "INV_Misc_Bomb_02",
   tip = "Hurls acid that strips armour from enemies in an area and burns them (%d damage a second on the main target).",
   cast = function(w, u, o, tgt, lv)
       local ab = D.Abilities.acidBomb
       fx(w, tgt.x, tgt.y, 166492, 2.4, 1.2)
       for _, e in ipairs(enemies(w, u, tgt.x, tgt.y, T(200), true)) do
           if canHurt(e) then
               S.buff(w, e, "acid", 15, { armor = lvOf(ab.armorL, lv) })
               e.poisonT, e.poisonOwner, e.poisonDps = 15, u.id, e == tgt and lvOf(ab.dps, lv) or lvOf(ab.splashDps, lv)
           end
       end
   end,
   ai = function(w, h, en, ctx) local t = ctx.juiciest(en) if t and not S.hasBuff(t, "acid") then return { target = t.id } end end }
A{ id = "chemicalRage", name = "Chemical Rage", key = "E", target = "self", mana = { 25, 25, 25 }, cd = { 30, 30, 30 }, dur = { 15, 15, 15 },
   atk = { 0.25, 0.75, 1.25 }, school = "nature", icon = ICON .. "Ability_Racial_BloodRage",
   tip = "For 15 seconds the ogre runs much faster and attacks faster.",
   cast = function(w, u, o, tgt, lv) S.buff(w, u, "rage", 15, { atk = lvOf(D.Abilities.chemicalRage.atk, lv) }) fx(w, u.x, u.y, 166121, 2, 1, u.id) end,
   ai = function(w, h, en, ctx) if ctx.fight and ctx.cd and ctx.cd < 4 then return {} end end }
A{ id = "transmute", name = "Transmute", key = "R", ult = true, target = "enemy", mana = { 150 }, cd = { 45 }, range = T(650), noHero = true, school = "arcane",
   icon = ICON .. "INV_Misc_Coin_02", tip = "Turns an enemy unit (level 5 or lower) into gold for you.",
   check = function(w, u, tgt) if (tgt.def.level or 1) > 5 then return false, "That unit is too powerful." end return true end,
   cast = function(w, u, o, tgt)
       local g = floor((tgt.def.gold and tgt.def.gold > 0 and tgt.def.gold or (tgt.def.level or 1) * 25) * 0.8)
       local pl = w.players[u.owner]
       if pl then pl.gold = pl.gold + g end
       S.event(w, { t = "float", x = tgt.x, y = tgt.y - 1, text = "+" .. g, color = { 1, 0.85, 0.2 } })
       fx(w, tgt.x, tgt.y, 166324, 1.8, 1.2)
       S.kill(w, tgt, u)
   end,
   ai = function(w, h, en, ctx)
       local best
       for _, e in ipairs(en) do if not e.def.hero and (e.def.level or 1) <= 5 and not S.spellImmune(e) and (not best or (e.def.gold or 0) > (best.def.gold or 0)) then best = e end end
       if best then return { target = best.id } end
   end }

-- Firelord
A{ id = "soulBurn", name = "Soul Burn", key = "Q", target = "enemy", mana = { 85, 85, 85 }, cd = { 12, 12, 12 }, range = T(700), dps = { 7.81, 15, 22.5 },
   dur = { 16, 18, 20 }, heroDur = { 7, 8, 9 }, school = "fire", icon = ICON .. "Spell_Fire_Immolation",
   tip = "Burns an enemy's soul: it can't cast spells, deals half damage and burns for %d damage a second.",
   cast = function(w, u, o, tgt, lv)
       local ab = D.Abilities.soulBurn
       local d = durFor(ab, lv, tgt)
       S.buff(w, tgt, "soulburn", d)
       tgt.poisonT, tgt.poisonOwner, tgt.poisonDps = d, u.id, lvOf(ab.dps, lv)
       tgt.channel = nil
       fx(w, tgt.x, tgt.y, 166121, 1.6, d, tgt.id)
   end,
   ai = function(w, h, en, ctx)
       for _, e in ipairs(en) do if e.def.hero and canHurt(e) and not S.hasBuff(e, "soulburn") then return { target = e.id } end end
       local t = ctx.juiciest(en) if t and (t.mana or 0) > 50 then return { target = t.id } end
   end }
A{ id = "lavaSpawn", name = "Summon Lava Spawn", key = "W", target = "none", mana = { 150, 150, 150 }, cd = { 32, 32, 32 }, dur = { 70, 70, 70 },
   school = "fire", icon = ICON .. "Spell_Fire_Volcano", tip = "Summons a Lava Spawn for 70 seconds; after 12 attacks it splits in two.",
   cast = function(w, u, o, tgt, lv)
       S.summonUnit(w, u.owner, "lavaSpawn" .. lv, u.x + cos(u.facing) * 1.2, u.y + sin(u.facing) * 1.2, 70)
       S.updateSupply(w)
   end,
   ai = function(w, h, en, ctx) if ctx.fight then return {} end end }
A{ id = "incinerate", name = "Incinerate", key = "E", target = "passive", autocast = true, mana = { 6, 6, 6 }, bonus = { 2, 3, 4 }, boom = { 30, 45, 60 },
   icon = ICON .. "Spell_Fire_SelfDestruct",
   tip = "Each blow on the same target burns hotter (+%d damage a hit, 6 mana each); a unit that dies burning explodes. Right-click to switch on or off." }
A{ id = "volcano", name = "Volcano", key = "R", ult = true, target = "point", mana = { 200 }, cd = { 180 }, range = T(800), dmg = { 100 },
   school = "fire", icon = ICON .. "Spell_Fire_Volcano", tip = "Raises a volcano for 24 seconds: waves of rocks deal %d damage, stun, and smash buildings.",
   cast = function(w, u, o, tgt, lv)
       w.areas = w.areas or {}
       w.areas[#w.areas + 1] = { kind = "volcano", x = o.x, y = o.y, r = T(500), t = 24, owner = u.owner, src = u.id, wave = 0.5,
           tick = function(w2, a, dt, src, fake)
               a.wave = a.wave - dt
               if a.wave > 0 then return end
               a.wave = 3
               fx(w2, a.x, a.y, 165976, 3, 1.5)
               for _ = 1, 5 do
                   local ang, rr = w2.rng.float() * 2 * pi, sqrt(w2.rng.float()) * a.r
                   local x, y = a.x + cos(ang) * rr, a.y + sin(ang) * rr
                   fx(w2, x, y, 166187, 1.6, 1, nil, w2.rng.float() * 0.5)
                   for _, e in ipairs(w2.list) do
                       if alive(e) and (e.kind == "unit" or e.kind == "building") and S.isEnemy(fake, e) and not e.hidden and dist(e.x, e.y, x, y) <= T(150) + (e.size or 0) / 2 then
                           if e.kind == "building" then S.damage(w2, src, e, 150, "magic", true)
                           elseif canHurt(e) and not e.def.air then
                               S.damage(w2, src, e, 100, "magic", true)
                               if alive(e) then S.stunUnit(w2, e, e.def.hero and 1 or 2) end
                           end
                       end
                   end
               end
           end }
   end,
   ai = function(w, h, en, ctx)
       local c, n = ctx.cluster(en, 3)
       if c and n >= 5 then return { x = c.x, y = c.y } end
   end }

local SCHOOLS = { silence = "shadow", lifeDrain = "shadow", charm = "shadow" }
for id, sc in pairs(SCHOOLS) do D.Abilities[id].school = D.Abilities[id].school or sc end
for _, id in ipairs({ "howlOfTerror", "stormEarthFire", "roboGoblin", "chemicalRage", "breathOfFire" }) do
    D.Abilities[id].precast, D.Abilities[id].castAnim, D.Abilities[id].castPoint = false, "roar", 0.3
end

-- ------------------------------------------------------------------ hooks into the combat code

-- on every blow a hero (or Earth / Lava Spawn) lands
function S.onHitExtra(w, src, tgt, d)
    local def = src.def
    if def.pulverize and tgt.kind == "unit" and w.rng.next() % 100 < def.pulverize[1] then
        fx(w, tgt.x, tgt.y, 165977, 2.2, 0.7)
        for _, e in ipairs(enemies(w, src, tgt.x, tgt.y, def.pulverize[3], false)) do if e ~= tgt then S.damage(w, src, e, def.pulverize[2], "normal") end end
    end
    if def.splitAfter and not src.split then
        src.hits = (src.hits or 0) + 1
        if src.hits >= def.splitAfter then
            src.split = true
            local c = S.summonUnit(w, src.owner, def.id, src.x + 0.6, src.y + 0.4, src.life)
            c.split = false
            S.updateSupply(w)
        end
    end
    if not def.hero or not src.skills then return d end
    local sk = src.skills
    -- orbs (autocast, cost mana per arrow)
    if (sk.blackArrow or 0) > 0 and S.autocastOn(src, "blackArrow") and (src.mana or 0) >= 6 and tgt.kind == "unit" and not tgt.def.hero then
        src.mana = src.mana - 6
        d = d + lvOf(D.Abilities.blackArrow.bonus, sk.blackArrow)
        tgt.blackArrow = { t = w.time + 2, lv = sk.blackArrow, owner = src.owner }
    end
    if (sk.frostArrows or 0) > 0 and S.autocastOn(src, "frostArrows") and (src.mana or 0) >= 10 and tgt.kind == "unit" and canHurt(tgt) then
        src.mana = src.mana - 10
        local ab, lv = D.Abilities.frostArrows, sk.frostArrows
        d = d + lvOf(ab.bonus, lv)
        tgt.slow, tgt.slowFactor, tgt.slowAttack = tgt.def.hero and 1.5 or 5, lvOf(ab.slowL, lv), lvOf(ab.atkSlow, lv) * 0.5
    end
    if (sk.incinerate or 0) > 0 and S.autocastOn(src, "incinerate") and (src.mana or 0) >= 6 and tgt.kind == "unit" then
        src.mana = src.mana - 6
        local inc = tgt.incin
        if not inc or inc.src ~= src.id or w.time > inc.untilT then inc = { src = src.id, stacks = 0, owner = src.owner } tgt.incin = inc end
        inc.stacks, inc.untilT, inc.lv = inc.stacks + 1, w.time + 4, sk.incinerate
        d = d + inc.stacks * lvOf(D.Abilities.incinerate.bonus, sk.incinerate)
    end
    -- Drunken Brawler: 10% critical blows
    if (sk.drunkenBrawler or 0) > 0 and w.rng.next() % 100 < 10 then
        d = d * lvOf(D.Abilities.drunkenBrawler.mult, sk.drunkenBrawler)
        S.event(w, { t = "float", x = tgt.x, y = tgt.y, text = floor(d) .. "!", color = { 1, 0.2, 0.2 } })
    end
    -- Robo-Goblin: Demolish
    local robo = src.buffs and src.buffs.robo
    if robo and tgt.kind == "building" then d = d * robo.demolish end
    -- Engineering Upgrade
    if (sk.engineeringUpgrade or 0) > 0 then d = d + lvOf(D.Abilities.engineeringUpgrade.bonus, sk.engineeringUpgrade) end
    -- Cleaving Attack: the blow carries on into everything around the target
    if (sk.cleavingAttack or 0) > 0 and tgt.kind == "unit" and not tgt.def.air then
        local pct = lvOf(D.Abilities.cleavingAttack.pct, sk.cleavingAttack)
        for _, e in ipairs(enemies(w, src, tgt.x, tgt.y, T(200), false)) do
            if e ~= tgt then S.damage(w, src, e, d * pct, "normal") end
        end
    end
    return d
end

-- attacks that miss: the attacker is in Drunken Haze, or the target is a Drunken Brawler
function S.missExtra(w, src, tgt)
    local hz = src.buffs and src.buffs.haze
    if hz and hz.t > 0 and w.rng.float() < hz.miss then return true end
    local bl = tgt.skills and tgt.skills.drunkenBrawler
    if bl and bl > 0 and w.rng.next() % 100 < lvOf(D.Abilities.drunkenBrawler.evade, bl) then return true end
    return false
end

function S.rollExtra(w, u, d)
    local b = u.buffs
    if not b then return d end
    if b.howl and b.howl.t > 0 then d = d * (1 - b.howl.pct) end
    if b.soulburn and b.soulburn.t > 0 then d = d * 0.5 end
    return d
end

function S.armorExtra(u)
    local b = u.buffs
    if not b then return 0 end
    local a = 0
    if b.acid and b.acid.t > 0 then a = a - b.acid.armor end
    if b.robo then a = a + b.robo.armor end
    return a
end

function S.attackExtra(u, m)
    local r = u.buffs and u.buffs.rage
    if r and r.t > 0 then m = m + r.atk end
    return m
end

function S.moveExtra(u, m)
    local b = u.buffs
    if b then
        if b.haze and b.haze.t > 0 then m = m * (1 - b.haze.slow) end
        if b.rage and b.rage.t > 0 and (u.def.speed or 0) > 0 then m = max(m, (405 / 128) / u.def.speed) end
        if b.tornadoSlow and b.tornadoSlow.t > 0 then m = m * 0.4 end
    end
    local eg = u.skills and u.skills.engineeringUpgrade
    if eg and eg > 0 then m = m + lvOf(D.Abilities.engineeringUpgrade.move, eg) end
    return m
end

-- Mana Shield soaks damage with mana
function S.absorbExtra(w, tgt, dmg)
    local ms = tgt.buffs.manaShield
    if not ms or ms.t <= 0 then return dmg end
    local cost = dmg / ms.ratio
    if (tgt.mana or 0) >= cost then tgt.mana = tgt.mana - cost return 0 end
    local soaked = (tgt.mana or 0) * ms.ratio
    tgt.mana = 0
    tgt.buffs.manaShield = nil
    return max(0, floor(dmg - soaked + 0.5))
end

-- per unit per tick: Doom, factories, tornadoes, Storm Earth and Fire. true = skip the rest.
function S.stepExtra(w, u, dt)
    local b = u.buffs
    local doom = b and b.doom
    if doom then
        doom.acc = (doom.acc or 0) + 40 * dt
        if doom.acc >= 10 then
            local n = floor(doom.acc)
            doom.acc = doom.acc - n
            S.damage(w, w.ents[doom.src or 0], u, n, "magic", true)
            if not alive(u) then return true end
        end
    end
    local def = u.def
    if def.factory then
        u.makeT = (u.makeT or 1) - dt
        if u.makeT <= 0 then
            u.makeT = u.every or 5
            local a = w.rng.float() * 2 * pi
            local g = S.summonUnit(w, u.owner, "clockwerk" .. def.factory, u.x + cos(a) * 0.9, u.y + sin(a) * 0.9, 12)
            S.updateSupply(w)
        end
    end
    if def.tornado then
        -- it slows everything around it, hurts units and tears at buildings, and wanders about
        u.tAcc = (u.tAcc or 0) + dt
        if u.tAcc >= 1 then
            u.tAcc = u.tAcc - 1
            for _, e in ipairs(enemies(w, u, u.x, u.y, T(600), false)) do
                S.buff(w, e, "tornadoSlow", 1.2)
                if dist(e.x, e.y, u.x, u.y) <= T(275) then S.damage(w, u, e, 7, "magic", true) end
            end
            for _, bb in ipairs(w.list) do
                if bb.kind == "building" and alive(bb) and S.isEnemy(u, bb) and S.edgeDist(u.x, u.y, bb) <= T(275) then S.damage(w, u, bb, 25, "magic", true) end
            end
            fx(w, u.x, u.y, 165976, 1.6, 0.8)
        end
        u.wanderT = (u.wanderT or 0) - dt
        if u.wanderT <= 0 then
            u.wanderT = 2
            local hx, hy = (u.home or { u.x, u.y })[1], (u.home or { u.x, u.y })[2]
            local a, r = w.rng.float() * 2 * pi, w.rng.float() * 4
            S.issue(w, u, { type = "move", x = hx + cos(a) * r, y = hy + sin(a) * r })
        end
    end
    if u.sef then
        u.sef.t = u.sef.t - dt
        local any, spot
        for _, id in ipairs(u.sef.ids) do local p = w.ents[id] if alive(p) then any, spot = true, p end end
        if u.sef.t <= 0 or not any then
            if spot then u.x, u.y = spot.x, spot.y u.px, u.py = u.x, u.y end
            for _, id in ipairs(u.sef.ids) do local p = w.ents[id] if alive(p) then S.kill(w, p, nil, true) p.removed = true end end
            u.sef, u.hidden = nil, nil
            if u.buffs then u.buffs.invuln = nil end
            fx(w, u.x, u.y, 165594, 2, 1)
            S.updateSupply(w)
        else
            if spot then u.x, u.y = spot.x, spot.y end
        end
    end
    return false
end

-- deaths: Black Arrow raises a Dark Minion, Incinerate explodes, Doom brings a Doom Guard, goblins blow up
function S.deathExtra(w, e)
    local ba = e.blackArrow
    if ba and w.time <= ba.t and not e.def.hero and not e.def.summon and ba.owner ~= e.owner then
        S.summonUnit(w, ba.owner, "darkMinion" .. ba.lv, e.x, e.y, 80)
        S.updateSupply(w)
    end
    local inc = e.incin
    if inc and w.time <= inc.untilT then
        fx(w, e.x, e.y, 166187, 2.2, 1)
        local full = lvOf(D.Abilities.incinerate.boom, inc.lv or 1)
        for _, o in ipairs(enemies(w, { owner = inc.owner }, e.x, e.y, T(240), true)) do
            if o ~= e and canHurt(o) then S.damage(w, w.ents[inc.src or 0], o, dist(o.x, o.y, e.x, e.y) <= T(120) and full or full * 0.5, "magic", true) end
        end
    end
    local doom = e.buffs and e.buffs.doom
    if doom then
        S.summonUnit(w, doom.owner, "doomGuard", e.x, e.y, 120)
        S.updateSupply(w)
    end
    if e.def.selfDestruct then
        fx(w, e.x, e.y, 166187, 1.6, 0.8)
        for _, o in ipairs(enemies(w, e, e.x, e.y, T(250), false)) do S.damage(w, e, o, e.def.selfDestruct, "magic", true) end
        for _, bb in ipairs(w.list) do
            if bb.kind == "building" and alive(bb) and S.isEnemy(e, bb) and S.edgeDist(e.x, e.y, bb) <= T(250) then S.damage(w, e, bb, e.def.selfDestruct, "magic", true) end
        end
    end
end

-- ------------------------------------------------------------------ the Tavern

-- hire a tavern hero: one of your units next to it, the usual hero limits, and each hero only once a game
function S.hireHero(w, p, shopId, uid)
    local shop = w.ents[shopId]
    local def = D.Units[uid]
    if not alive(shop) or not def or not def.tavern then return false end
    if not S.shopUnit(w, p, shop) then return false, "One of your units must be next to the Tavern." end
    w.tavernTaken = w.tavernTaken or {}
    if w.tavernTaken[uid] and w.tavernTaken[uid] ~= p then return false, "Another player has hired this hero." end
    if w.tavernTaken[uid] then return false, "You already have this hero." end
    local ok, why = S.heroAllowed(w, p, uid)
    if not ok then return false, why end
    local pl = w.players[p]
    local free = S.heroCount(w, p) == 0
    local g, l = free and 0 or def.gold, free and 0 or def.lumber
    if pl.gold < g then return false, "Not enough gold." end
    if pl.lumber < l then return false, "Not enough lumber." end
    if pl.used + def.supply > pl.cap then return false, "Not enough food." end
    pl.gold, pl.lumber = pl.gold - g, pl.lumber - l
    w.tavernTaken[uid] = p
    local owner, rally = shop.owner, shop.rally
    shop.owner, shop.rally = p, nil
    local u = S.spawnFrom(w, shop, uid)
    shop.owner, shop.rally = owner, rally
    S.updateSupply(w)
    if pl.stats then pl.stats.hired = (pl.stats.hired or 0) + 1 end
    return u ~= nil
end

-- why a tavern hero can't be hired by p right now (nil = it can)
function S.tavernWhy(w, p, shop, uid)
    local def = D.Units[uid]
    local taken = w.tavernTaken and w.tavernTaken[uid]
    if taken then return taken == p and "You already have this hero." or "Another player has hired this hero." end
    local ok, why = S.heroAllowed(w, p, uid)
    if not ok then return why end
    if not S.shopUnit(w, p, shop) then return "One of your units must be next to the Tavern." end
    return nil
end
