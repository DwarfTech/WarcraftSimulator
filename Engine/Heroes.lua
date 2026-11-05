-- Skirmish engine: Warcraft III heroes.
-- Eight heroes with their real attributes (strength / agility / intelligence and growth per
-- level), levels 1-10 with skill points, and all 32 hero abilities using WC3's numbers.
-- Hit points = 100 + 25 x STR, mana = 15 x INT, armour = base + 0.3 x AGI, damage = main
-- attribute + dice, attack speed +2% per AGI. Distances converted at 128 game units a tile.

local _, ns = ...
local E = ns.Engine
local D, M, S = E.Data, E.Map, E.Sim

local floor, abs, max, min, sqrt, atan2, cos, sin, pi = math.floor, math.abs, math.max, math.min, math.sqrt, math.atan2, math.cos, math.sin, math.pi
local function alive(e) return e and not e.dead and not e.removed end
local function dist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return sqrt(dx * dx + dy * dy) end
local function T(units) return units / 128 end
local ICON = "Interface\\Icons\\"
local EMPTY = {}

-- ------------------------------------------------------------------ levels & experience (WC3)
D.HERO_XP = { 0, 200, 500, 900, 1400, 2000, 2700, 3500, 4400, 5400 }
D.HERO_MAX_LEVEL = 10
D.CREEP_XP_CAP = 5                       -- heroes stop learning from creeps at level 5
local UNIT_XP = { 25, 40, 60, 85, 115, 150, 190, 235, 285, 340 }
local HERO_KILL_XP = { 100, 120, 160, 220, 300, 400, 500, 600, 700, 800 }
local CREEP_XP_PCT = { 0.8, 0.7, 0.6, 0.5, 0 }

-- ------------------------------------------------------------------ the eight heroes
local function H(t)
    t.kind, t.role, t.hero = "unit", "hero", true
    t.supply, t.gold, t.lumber, t.time = 5, 425, 100, 55
    t.dtype, t.atype = "hero", "hero"
    t.vis = 0.45
    t.radius, t.spaced = t.vis * 1.2, true
    t.hp = 100 + 25 * t.str
    t.sight, t.nightSight, t.acquire = T(1800), T(800), max(4.2, (t.range or 0.5) + 0.5)
    t.hitsGround, t.hitsBuildings = true, true
    t.hitsAir = (t.range or 0) > 1 or nil
    t.dice = t.dice or 2
    t.armor = t.armor or 0
    t.base = 0
    t.missile = t.range and t.range > 1 and (t.missile or "arcane") or nil
    t.dmin = t.str + 2
    t.dmax = t.str + t.dice * t.sides
    D.Units[t.id] = t
end
D.defHero = H

H{ id = "paladin", faction = "alliance", name = "Paladin", primary = "str", str = 22, agi = 13, int = 17, strUp = 2.7, agiUp = 1.5, intUp = 1.8,
   armor = 2, sides = 6, cd = 2.0, dmgpt = 0.433, range = T(100), speed = T(290), display = { 5566 }, gear = { main = 2178, off = 143 },
   icon = ICON .. "Spell_Holy_HolyBolt", key = "P", abilities = { "holyLight", "divineShield", "devotionAura", "resurrection" },
   tip = "Warrior hero. Heals with Holy Light, shields himself with Divine Shield and steadies troops with Devotion Aura." }
H{ id = "archmage", faction = "alliance", name = "Archmage", primary = "int", str = 14, agi = 17, int = 19, strUp = 1.8, agiUp = 1.0, intUp = 3.2,
   armor = 0, sides = 4, cd = 2.13, dmgpt = 0.55, range = T(600), speed = T(320), display = { 3585 }, missile = "fire",
   icon = ICON .. "Spell_Frost_IceStorm", key = "A", abilities = { "blizzard", "waterElemental", "brillianceAura", "massTeleport" },
   tip = "Mystical hero. Rains Blizzard on the enemy, summons Water Elementals and speeds up friendly mana." }
H{ id = "mountainKing", faction = "alliance", name = "Mountain King", primary = "str", str = 24, agi = 11, int = 15, strUp = 3.0, agiUp = 1.5, intUp = 1.5,
   armor = 1, sides = 6, cd = 2.22, dmgpt = 0.35, range = T(100), speed = T(290), display = { 3597 }, gear = { main = 12883, off = 12883 },
   icon = ICON .. "Ability_ThunderBolt", key = "M", abilities = { "stormBolt", "thunderClap", "bash", "avatar" },
   tip = "Warrior hero. Storm Bolt stuns, Thunder Clap slows everything nearby and Bash stuns with his blows." }
H{ id = "bloodMage", faction = "alliance", name = "Blood Mage", primary = "int", str = 18, agi = 14, int = 19, strUp = 2.0, agiUp = 1.0, intUp = 3.0,
   armor = 0, sides = 4, cd = 1.64, dmgpt = 0.55, range = T(600), speed = T(300), display = { 10328 }, missile = "fire",
   icon = ICON .. "Spell_Fire_Fireball02", key = "B", abilities = { "flameStrike", "banish", "siphonMana", "phoenix" },
   tip = "Mystical hero. Flame Strike burns an area, Banish makes a unit ethereal and Siphon Mana drains spellcasters." }

H{ id = "blademaster", faction = "orcs", name = "Blademaster", primary = "agi", str = 18, agi = 24, int = 16, strUp = 2.0, agiUp = 1.75, intUp = 2.25,
   armor = 0, sides = 12, cd = 1.77, dmgpt = 0.33, range = T(100), speed = T(320), display = { 1619 }, gear = { main = 10612 },
   icon = ICON .. "Ability_Whirlwind", key = "B", abilities = { "windWalk", "mirrorImage", "criticalStrike", "bladestorm" },
   tip = "Cunning hero. Wind Walk turns him invisible, Mirror Image confuses the enemy and Critical Strike lands huge blows." }
H{ id = "farSeer", faction = "orcs", name = "Far Seer", primary = "int", str = 15, agi = 18, int = 19, strUp = 2.0, agiUp = 1.0, intUp = 3.0,
   armor = 0, sides = 4, cd = 2.28, dmgpt = 0.3, range = T(600), speed = T(320), display = { 4366 }, mount = { 10278 }, gear = { main = 5303 }, missile = "lightning",
   icon = ICON .. "Spell_Nature_ChainLightning", key = "F", abilities = { "chainLightning", "farSight", "feralSpirit", "earthquake" },
   tip = "Mystical hero on a wolf. Chain Lightning arcs between enemies and Feral Spirit summons wolves." }
H{ id = "taurenChieftain", faction = "orcs", name = "Tauren Chieftain", primary = "str", str = 25, agi = 10, int = 15, strUp = 3.2, agiUp = 1.5, intUp = 1.3,
   armor = 1, sides = 6, cd = 2.05, dmgpt = 0.36, range = T(128), speed = T(290), display = { 4307 }, gear = { main = 14084 },
   icon = ICON .. "Ability_Warrior_Sunder", key = "T", abilities = { "shockwave", "warStomp", "enduranceAura", "reincarnation" },
   tip = "Warrior hero. Shockwave and War Stomp break enemy lines; Endurance Aura speeds up his troops." }
H{ id = "shadowHunter", faction = "orcs", name = "Shadow Hunter", primary = "agi", str = 15, agi = 20, int = 17, strUp = 2.0, agiUp = 1.5, intUp = 2.5,
   armor = 0, sides = 4, cd = 2.28, dmgpt = 0.3, range = T(600), speed = T(320), display = { 9732 }, gear = { main = 10878, off = 12332 }, missile = "voodoo",
   icon = ICON .. "Spell_Shadow_ShadowWordDominate", key = "S", abilities = { "healingWave", "hex", "serpentWard", "bigBadVoodoo" },
   tip = "Cunning hero. Healing Wave heals several friends, Hex turns an enemy into a frog and Serpent Wards guard ground." }


-- summoned units
local function SU(t)
    t.kind, t.summon = "unit", true
    t.supply, t.gold, t.lumber, t.time, t.armor = 0, 0, 0, 0, t.armor or 0
    t.vis = t.vis or 0.45
    t.radius, t.spaced = t.vis * 1.2, true
    t.sight = t.sight or 8
    t.acquire = t.acquire or max(4, (t.range or 0.5) + 0.5)
    if t.hitsGround == nil then t.hitsGround, t.hitsBuildings = true, true end
    t.dice, t.base = 1, t.dmin - 1
    t.sides = t.dmax - t.dmin + 1
    D.Units[t.id] = t
end
D.defSummon = SU
for lv, s in ipairs({ { 525, 0, 18, 22 }, { 675, 1, 31, 39 }, { 900, 2, 41, 49 } }) do
    SU{ id = "waterElemental" .. lv, faction = "alliance", name = "Water Elemental", role = "ranged", hp = s[1], armor = s[2], dtype = "heavy", atype = "pierce",
        dmin = s[3], dmax = s[4], cd = 1.5, dmgpt = 0.4, range = T(300), speed = T(220), sight = T(1200), display = { 525 }, missile = "frost", hitsAir = true,
        icon = ICON .. "Spell_Frost_SummonWaterElemental", vis = 0.5 }
end
for lv, s in ipairs({ { 250, 11, 12, 320, 2 }, { 350, 16, 17, 350, 3 }, { 500, 21, 22, 350, 4 } }) do
    SU{ id = "spiritWolf" .. lv, faction = "orcs", name = "Spirit Wolf", role = "melee", hp = s[1], dtype = "heavy", sight = T(1200),
        crit = lv >= 2 and { 20, 2 } or nil, invisible = lv >= 3 or nil, atype = "normal",
        dmin = s[2], dmax = s[3], cd = 1.0, dmgpt = 0.4, range = T(90), speed = T(s[4]), level = s[5], display = { 1236 }, alpha = 0.85,
        icon = ICON .. "Spell_Nature_SpiritWolf", vis = 0.42 }
end
for lv, s in ipairs({ { 14, 16, 90 }, { 27, 30, 165 }, { 48, 52, 200 } }) do
    SU{ id = "serpentWard" .. lv, faction = "orcs", name = "Serpent Ward", role = "ranged", hp = s[3], dtype = "heavy", spellImmune = true, sight = T(1200), atype = "pierce",
        dmin = s[1], dmax = s[2], cd = 1.5, dmgpt = 0.3, range = T(600), speed = 0, display = { 2418 }, missile = "voodoo", hitsAir = true,
        icon = ICON .. "Spell_Nature_NullWard", vis = 0.3, ward = true }
end
SU{ id = "phoenix", faction = "alliance", name = "Phoenix", role = "air", air = true, hp = 1250, armor = 1, dtype = "light", atype = "magic",
    dmin = 61, dmax = 75, cd = 1.4, dmgpt = 0.43, range = T(600), splash = T(66), spellImmune = true, sight = T(1600), speed = T(320), display = { 1405 }, missile = "fire", hitsAir = true,
    icon = ICON .. "Spell_Fire_Immolation", vis = 0.6, burnAura = 10, selfBurn = 25 }
-- when the Phoenix dies it becomes an egg; unless the egg is destroyed, a new Phoenix hatches
SU{ id = "phoenixEgg", faction = "alliance", name = "Phoenix Egg", role = "ward", hp = 200, armor = 0, dtype = "heavy", atype = "normal",
    dmin = 1, dmax = 1, cd = 99, range = 0.1, speed = 0, display = { 1405 }, vis = 0.25, alpha = 0.8, ward = true, noAttack = true,
    icon = ICON .. "Spell_Fire_Immolation", sight = T(600) }
D.Units.phoenixEgg.dmin = nil

-- ------------------------------------------------------------------ the 32 abilities
-- target: enemy / ally / unit (either) / point / self / none (around the hero) / passive / aura
-- dur: duration on normal units; heroDur on heroes. Numbers per level.
D.Abilities = {}
local function A(t)
    t.maxLevel = t.maxLevel or (t.ult and 1 or 3)
    D.Abilities[t.id] = t
end
D.defAbility = A
-- Paladin
A{ id = "holyLight", noMech = true, name = "Holy Light", key = "Q", target = "ally", noSelf = true, mana = { 65, 65, 65 }, cd = { 5, 5, 5 }, range = T(800),
   heal = { 200, 400, 600 }, effect = 166328, icon = ICON .. "Spell_Holy_HolyBolt", tip = "Heals a friendly unit for %d hit points." }
A{ id = "divineShield", name = "Divine Shield", key = "W", target = "self", mana = { 25, 25, 25 }, cd = { 35, 50, 65 }, dur = { 15, 25, 35 },
   effect = 166342, icon = ICON .. "Spell_Holy_DivineIntervention", tip = "The Paladin can't be harmed for %d seconds." }
A{ id = "devotionAura", name = "Devotion Aura", key = "E", target = "aura", radius = T(900), armor = { 1.5, 3, 4.5 },
   icon = ICON .. "Spell_Holy_DevotionAura", tip = "Nearby friendly units get %s extra armour." }
A{ id = "resurrection", name = "Resurrection", key = "R", ult = true, target = "none", mana = { 200 }, cd = { 240 }, radius = T(900), count = { 6 },
   effect = 166324, icon = ICON .. "Spell_Holy_Resurrection", tip = "Brings up to %d dead friendly units back to life." }
-- Archmage
A{ id = "blizzard", name = "Blizzard", key = "Q", target = "point", mana = { 75, 75, 75 }, cd = { 6, 6, 6 }, range = T(800), radius = T(200),
   waves = { 6, 8, 10 }, dmg = { 30, 40, 50 }, effect = 165716, channel = true, icon = ICON .. "Spell_Frost_IceStorm", tip = "Waves of ice shards; %d damage a wave." }
A{ id = "waterElemental", name = "Summon Water Elemental", key = "W", target = "none", mana = { 125, 125, 125 }, cd = { 20, 20, 20 }, dur = { 60, 60, 60 },
   summon = "waterElemental", effect = 165594, icon = ICON .. "Spell_Frost_SummonWaterElemental", tip = "Summons a Water Elemental for 60 seconds." }
A{ id = "brillianceAura", name = "Brilliance Aura", key = "E", target = "aura", radius = T(900), manaRegen = { 0.75, 1.5, 2.25 },
   icon = ICON .. "Spell_Holy_MagicalSentry", tip = "Nearby friends regain %s extra mana a second." }
A{ id = "massTeleport", name = "Mass Teleport", key = "R", ult = true, target = "friend", mana = { 100 }, cd = { 20 }, radius = T(700), count = { 24 }, delay = 3,
   effect = 165921, icon = ICON .. "Spell_Arcane_PortalStormwind", tip = "Teleports the Archmage and up to %d nearby units to a friendly unit or building." }
-- Mountain King
A{ id = "stormBolt", noMech = true, name = "Storm Bolt", key = "Q", target = "enemy", mana = { 75, 75, 75 }, cd = { 9, 9, 9 }, range = T(600),
   dmg = { 100, 210, 325 }, dur = { 5, 5, 5 }, heroDur = { 3, 3, 3 }, missile = 166497, impact = 166496,
   icon = ICON .. "Ability_ThunderBolt", tip = "Throws a hammer for %d damage, stunning the target." }
A{ id = "thunderClap", noMech = true, name = "Thunder Clap", key = "W", target = "none", mana = { 90, 90, 90 }, cd = { 6, 6, 6 },
   dmg = { 65, 125, 175 }, radiusL = { T(300), T(350), T(400) }, dur = { 5, 5, 5 }, heroDur = { 3, 3, 3 }, slow = 0.5, effect = 167120,
   icon = ICON .. "Spell_Nature_ThunderClap", tip = "Slams the ground for %d damage and slows nearby enemies." }
A{ id = "bash", name = "Bash", key = "E", target = "passive", chance = { 20, 30, 40 }, bonus = { 25, 25, 25 }, dur = { 2, 2, 2 }, heroDur = { 1, 1, 1 },
   icon = ICON .. "Ability_Rogue_KidneyShot", tip = "%d%% of attacks stun and deal bonus damage." }
A{ id = "avatar", name = "Avatar", key = "R", ult = true, target = "self", mana = { 150 }, cd = { 180 }, dur = { 60 }, armor = 5, hp = 500, dmg = 20, effect = 166465,
   icon = ICON .. "Spell_Nature_Strength", tip = "Grows huge for 60 seconds: +5 armour, +500 hit points, +20 damage and immune to spells." }
-- Blood Mage
A{ id = "flameStrike", name = "Flame Strike", key = "Q", target = "point", mana = { 135, 135, 135 }, cd = { 10, 10, 10 }, range = T(800), radius = T(200),
   burst = { 90, 160, 220 }, burn = { 4, 6, 8 }, delay = 1.33, effect = 166187, icon = ICON .. "Spell_Fire_SelfDestruct",
   tip = "Calls down a pillar of flame: %d damage, then the ground keeps burning." }
A{ id = "banish", noMech = true, name = "Banish", key = "W", target = "unit", mana = { 75, 60, 50 }, cd = { 0, 0, 0 }, range = T(800), dur = { 12, 15, 18 }, heroDur = { 4, 5, 6 },
   effect = 165652, icon = ICON .. "Spell_Shadow_Cripple", tip = "Makes a unit ethereal for %d seconds: it can't attack and is slowed, but weapons pass through it." }
A{ id = "siphonMana", noMech = true, name = "Siphon Mana", key = "E", target = "unit", mana = { 10, 10, 10 }, cd = { 6, 6, 6 }, range = T(600), dur = { 6, 6, 6 },
   drain = { 15, 30, 45 }, effect = 166536, channel = true, icon = ICON .. "Spell_Shadow_SiphonMana", tip = "Drains %d mana a second from a unit." }
A{ id = "phoenix", name = "Phoenix", key = "R", ult = true, target = "none", mana = { 175 }, cd = { 180 }, summon = "phoenix", effect = 166147,
   icon = ICON .. "Spell_Fire_Immolation", tip = "Summons a burning Phoenix that scorches nearby enemies." }
-- Blademaster
A{ id = "windWalk", name = "Wind Walk", key = "Q", target = "self", mana = { 75, 75, 75 }, cd = { 5, 5, 5 }, dur = { 20, 35, 50 }, speed = { 0.1, 0.4, 0.7 },
   backstab = { 40, 70, 100 }, effect = 166430, icon = ICON .. "Ability_Stealth", tip = "Turns invisible and fast; the first blow deals %d extra damage." }
A{ id = "mirrorImage", name = "Mirror Image", key = "W", target = "self", mana = { 100, 100, 100 }, cd = { 3, 3, 3 }, dur = { 60, 60, 60 }, count = { 1, 2, 3 },
   effect = 166430, icon = ICON .. "Spell_Magic_LesserInvisibilty", tip = "Creates %d illusions of the Blademaster. Illusions deal no damage and take double." }
A{ id = "criticalStrike", name = "Critical Strike", key = "E", target = "passive", chance = { 15, 15, 15 }, mult = { 2, 3, 4 },
   icon = ICON .. "Ability_CriticalStrike", tip = "15%% of attacks deal %dx damage." }
A{ id = "bladestorm", name = "Bladestorm", key = "R", ult = true, target = "self", mana = { 200 }, cd = { 180 }, dur = { 5 }, dps = { 110 }, radius = T(200),
   effect = 167199, icon = ICON .. "Ability_Whirlwind", tip = "Whirls for 5 seconds, cutting everything nearby for %d damage a second; immune to spells." }
-- Far Seer
A{ id = "chainLightning", name = "Chain Lightning", key = "Q", target = "enemy", mana = { 120, 120, 120 }, cd = { 9, 9, 9 }, range = T(700),
   dmg = { 85, 125, 180 }, jumps = { 4, 6, 8 }, jumpRange = T(500), decay = 0.1, effect = 165780,
   icon = ICON .. "Spell_Nature_ChainLightning", tip = "Lightning that jumps between enemies, starting at %d damage." }
A{ id = "farSight", name = "Far Sight", key = "W", target = "anywhere", mana = { 0, 0, 0 }, cd = { 0, 0, 0 }, dur = { 8, 8, 8 },
   radiusL = { T(600), T(1800), T(4000) }, effect = 165940, icon = ICON .. "Spell_Nature_FarSight", tip = "Reveals part of the map for 8 seconds." }
A{ id = "feralSpirit", name = "Feral Spirit", key = "E", target = "none", mana = { 75, 75, 75 }, cd = { 30, 30, 30 }, dur = { 60, 60, 60 }, count = { 2, 2, 2 },
   summon = "spiritWolf", effect = 165619, icon = ICON .. "Spell_Nature_SpiritWolf", tip = "Summons %d Spirit Wolves for 60 seconds." }
A{ id = "earthquake", name = "Earthquake", key = "R", ult = true, target = "point", mana = { 150 }, cd = { 90 }, range = T(1000), radius = T(250), dur = { 25 },
   buildingDps = { 50 }, slow = 0.75, effect = 165976, icon = ICON .. "Spell_Nature_Earthquake", tip = "Shakes an area for 25 seconds: units are slowed and buildings take %d damage a second." }
-- Tauren Chieftain
A{ id = "shockwave", name = "Shockwave", key = "Q", target = "point", mana = { 100, 100, 100 }, cd = { 8, 8, 8 }, range = T(700), length = T(800), width = T(250),
   dmg = { 75, 130, 200 }, effect = 165976, icon = ICON .. "Ability_Warrior_Sunder", tip = "A wave of force deals %d damage to everything in a line." }
A{ id = "warStomp", noMech = true, name = "War Stomp", key = "W", target = "none", mana = { 90, 90, 90 }, cd = { 6, 6, 6 }, dmg = { 30, 60, 90 },
   radiusL = { T(250), T(300), T(350) }, dur = { 3, 4, 5 }, heroDur = { 2, 3, 4 }, effect = 165977,
   icon = ICON .. "Ability_WarStomp", tip = "Stomps for %d damage, stunning nearby enemies." }
A{ id = "enduranceAura", name = "Endurance Aura", key = "E", target = "aura", radius = T(900), moveBonus = { 0.1, 0.2, 0.3 }, attackBonus = { 0.05, 0.1, 0.15 },
   icon = ICON .. "Spell_Nature_UnyeildingStamina", tip = "Nearby friends move %d%% faster and attack faster." }
A{ id = "reincarnation", name = "Reincarnation", key = "R", ult = true, target = "passive", cd = { 240 }, delay = 5, effect = 166464,
   icon = ICON .. "Spell_Nature_Reincarnation", tip = "When killed, the Chieftain comes back to life after 5 seconds (every 4 minutes)." }
-- Shadow Hunter
A{ id = "healingWave", noMech = true, name = "Healing Wave", key = "Q", target = "ally", mana = { 90, 90, 90 }, cd = { 9, 9, 9 }, range = T(700),
   heal = { 130, 215, 300 }, jumps = { 3, 4, 5 }, jumpRange = T(500), decay = 0.25, effect = 166324,
   icon = ICON .. "Spell_Nature_HealingWaveGreater", tip = "A wave of healing that bounces between friends, starting at %d." }
A{ id = "hex", noMech = true, name = "Hex", key = "W", target = "enemy", mana = { 70, 70, 70 }, cd = { 7, 7, 7 }, range = T(800), dur = { 15, 30, 45 }, heroDur = { 4, 5, 6 },
   effect = 166430, icon = ICON .. "Spell_Shadow_AntiShadow", tip = "Turns an enemy into a frog for %d seconds." }
A{ id = "serpentWard", name = "Serpent Ward", key = "E", target = "point", mana = { 30, 30, 30 }, cd = { 6.5, 6.5, 6.5 }, range = T(500), dur = { 40, 40, 40 },
   summon = "serpentWard", effect = 165594, icon = ICON .. "Spell_Nature_NullWard", tip = "Plants a ward that attacks enemies for 40 seconds." }
A{ id = "bigBadVoodoo", name = "Big Bad Voodoo", key = "R", ult = true, target = "self", mana = { 200 }, cd = { 180 }, dur = { 30 }, radius = T(800), channel = true,
   effect = 166347, icon = ICON .. "Spell_Shadow_UnholyFrenzy", tip = "While channelling (up to 30 seconds), nearby friendly units can't be harmed." }

-- the main attribute for a hero at its level
function S.heroStats(u)
    local d, lv = u.def, (u.level or 1) - 1
    local str = floor(d.str + d.strUp * lv + (u.bonusStr or 0))
    local agi = floor(d.agi + d.agiUp * lv + (u.bonusAgi or 0))
    local int = floor(d.int + d.intUp * lv + (u.bonusInt or 0))
    local main = d.primary == "str" and str or (d.primary == "agi" and agi or int)
    return str, agi, int, main
end

-- recompute a hero's hit points, mana and so on from its attributes (keeps current fractions)
function S.refreshHero(u)
    local str, agi, int = S.heroStats(u)
    local hpFrac = u.maxhp and u.maxhp > 0 and u.hp / u.maxhp or 1
    local mpFrac = u.maxMana and u.maxMana > 0 and u.mana / u.maxMana or 1
    local ib = u.ib or EMPTY
    u.maxhp = 100 + 25 * str + (u.buffs and u.buffs.avatar and 500 or 0) + (ib.hp or 0)
    u.maxMana = 15 * int + (ib.mana or 0)
    u.hp = max(1, u.maxhp * hpFrac)
    u.mana = u.maxMana * mpFrac
    u.hpRegen = 0.25 + 0.05 * str
    u.manaRegen = (0.01 + 0.05 * int) * (1 + (ib.manaPct or 0))
end

function S.initHero(w, u, rec)
    u.level, u.xp, u.points, u.skills = 1, 0, 1, {}
    u.abilityCd = {}
    u.buffs = u.buffs or {}
    if rec then
        u.level, u.xp, u.points, u.skills = rec.level, rec.xp, rec.points, rec.skills
        u.inv, u.tomeStr, u.tomeAgi, u.tomeInt = rec.inv, rec.tomeStr, rec.tomeAgi, rec.tomeInt
        if S.refreshItems then S.refreshItems(w, u) end
    end
    u.maxhp, u.maxMana = nil, nil
    u.hp, u.mana = 1, 0
    S.refreshHero(u)
    u.hp, u.mana = u.maxhp, u.maxMana
    local pl = w.players[u.owner]
    pl.heroes = pl.heroes or {}
    pl.heroes[#pl.heroes + 1] = u.id
end

-- ------------------------------------------------------------------ experience

local function levelUp(w, h)
    h.level = h.level + 1
    h.points = (h.points or 0) + 1
    S.refreshHero(h)
    h.hp = min(h.maxhp, h.hp + 25 * h.def.strUp)
    S.event(w, { t = "levelup", unit = h.id, level = h.level })
end

-- experience from a Tome of Experience and the like
function S.addXp(w, h, amount)
    if h.level >= D.HERO_MAX_LEVEL then return end
    h.xp = h.xp + floor(amount)
    local st = w.players[h.owner] and w.players[h.owner].stats
    if st then st.xp = (st.xp or 0) + floor(amount) end
    while h.level < D.HERO_MAX_LEVEL and h.xp >= D.HERO_XP[h.level + 1] do levelUp(w, h) end
end

function S.giveXp(w, killer, victim)
    if not killer or victim.kind ~= "unit" or victim.illusion or victim.def.ward then return end
    local owner = killer.owner
    if owner > 2 or victim.owner == owner then return end
    local lvl = victim.def.hero and victim.level or (victim.def.level or (victim.def.xp and 3) or 1)
    local xp = victim.def.hero and HERO_KILL_XP[min(10, lvl)] or (victim.def.xp or UNIT_XP[min(10, max(1, lvl))])
    -- summoned units are worth half (WC3's SummonedKillFactor)
    if victim.def.summon then xp = xp * 0.5 end
    local creep = victim.owner == 3
    local heroes = {}
    for _, h in ipairs(w.list) do
        if h.kind == "unit" and h.def.hero and h.owner == owner and alive(h) and not h.illusion and dist(h.x, h.y, victim.x, victim.y) <= T(1200) then
            heroes[#heroes + 1] = h
        end
    end
    if #heroes == 0 then return end
    local share = xp / #heroes
    for _, h in ipairs(heroes) do
        local gain = share
        if creep then gain = h.level <= #CREEP_XP_PCT and share * CREEP_XP_PCT[h.level] or 0 end
        if creep and h.level >= D.CREEP_XP_CAP then gain = 0 end
        if h.level < D.HERO_MAX_LEVEL and gain > 0 then
            h.xp = h.xp + floor(gain)
            local st = w.players[h.owner] and w.players[h.owner].stats
            if st then st.xp = (st.xp or 0) + floor(gain) end
            while h.level < D.HERO_MAX_LEVEL and h.xp >= D.HERO_XP[h.level + 1] do levelUp(w, h) end
        end
    end
end

-- ------------------------------------------------------------------ skills

function S.canLearn(u, abId)
    local ab = D.Abilities[abId]
    if not ab or not u.def.hero then return false end
    local cur = u.skills[abId] or 0
    if (u.points or 0) < 1 then return false, "No skill points." end
    if cur >= ab.maxLevel then return false, "Already at its highest level." end
    local need = ab.ult and 6 or (1 + 2 * cur)
    if u.level < need then return false, ab.name .. " needs hero level " .. need .. "." end
    return true
end

function S.learn(w, u, abId)
    local ok, why = S.canLearn(u, abId)
    if not ok then return false, why end
    u.skills[abId] = (u.skills[abId] or 0) + 1
    u.points = u.points - 1
    S.event(w, { t = "learned", unit = u.id, ability = abId })
    return true
end

-- heroes learn with skill points; other units get their spells from research (Adept / Master Training)
function S.skillLevel(u, abId)
    if u.def.hero then return u.skills and u.skills[abId] or 0 end
    if not u.def.spells then return 0 end
    for _, id in ipairs(u.def.spells) do
        if id == abId then
            local ab = D.Abilities[abId]
            if ab.research and u.owner <= 2 and S.level(u.world or S.currentWorld, u.owner, ab.research[1]) < ab.research[2] then return 0 end
            return 1
        end
    end
    return 0
end

-- ------------------------------------------------------------------ buffs

-- a timed effect on a unit: buffs.stun / slow / invuln / ethereal / hex / windwalk / avatar / bladestorm / ...
function S.buff(w, u, id, dur, data)
    u.buffs = u.buffs or {}
    local b = u.buffs[id]
    if b and b.t > dur and not data then return b end
    u.buffs[id] = data or {}
    u.buffs[id].t = max(dur, (b and not data) and b.t or 0)
    if id == "avatar" and u.def.hero then S.refreshHero(u) u.hp = u.hp + 500 end
    return u.buffs[id]
end

function S.hasBuff(u, id) return u.buffs and u.buffs[id] and u.buffs[id].t > 0 end

local function stun(w, u, dur, fromAttack)
    -- spell immunity stops spell stuns, but not Bash from an attack
    if not fromAttack and (S.hasBuff(u, "avatar") or S.hasBuff(u, "bladestorm")) then return end
    u.stun = max(u.stun or 0, dur)
    u.swing = nil
end
S.stunUnit = stun

-- spells can't touch spell-immune units (Avatar, Bladestorm) or the invulnerable
function S.spellImmune(u)
    if u.def and u.def.spellImmune then return true end
    return S.hasBuff(u, "avatar") or S.hasBuff(u, "bladestorm") or S.hasBuff(u, "invuln") or S.hasBuff(u, "voodoo")
end

-- damage multiplier a target takes (0 = immune)
function S.damageTaken(w, tgt, src, atype, spell)
    if tgt.kind ~= "unit" then return 1 end
    if S.hasBuff(tgt, "invuln") or S.hasBuff(tgt, "voodoo") then return 0 end
    if spell and (S.hasBuff(tgt, "avatar") or S.hasBuff(tgt, "bladestorm")) then return 0 end
    local m = 1
    if S.hasBuff(tgt, "ethereal") then
        if not spell and atype ~= "magic" then return 0 end
        m = m * 1.66
    end
    if tgt.illusion then m = m * 2 end
    if tgt.buffs and tgt.buffs.berserk then m = m * 1.5 end
    return m
end

-- ------------------------------------------------------------------ auras (recomputed a few times a second)

local function spreadAura(w, h, radius, a2)
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and alive(u) and u.owner == h.owner and abs(u.x - h.x) <= radius and abs(u.y - h.y) <= radius and dist(u.x, u.y, h.x, h.y) <= radius then
            u.aura = u.aura or {}
            local a = u.aura
            if a2.armor then a.armor = max(a.armor or 0, a2.armor) end
            if a2.mana then a.mana = max(a.mana or 0, a2.mana) end
            if a2.move then a.move = max(a.move or 0, a2.move) end
            if a2.attack then a.attack = max(a.attack or 0, a2.attack) end
            if a2.dmg then a.dmg = max(a.dmg or 0, a2.dmg) end
            if a2.rangedDmg and (u.def.range or 0) > 1.5 then a.dmg = max(a.dmg or 0, a2.rangedDmg) end
            if a2.regen then a.regen = max(a.regen or 0, a2.regen) end
        end
    end
end

function S.stepAuras(w)
    for _, u in ipairs(w.list) do
        if u.kind == "unit" then u.aura = nil end
    end
    -- item auras and creep auras
    for _, h in ipairs(w.list) do
        if h.kind == "unit" and alive(h) and not h.illusion then
            if h.ib and h.ib.aura then spreadAura(w, h, 900 / 128, h.ib.aura) end
            if h.def.creepAura then spreadAura(w, h, 900 / 128, h.def.creepAura) end
        end
    end
    for _, h in ipairs(w.list) do
        if h.kind == "unit" and h.def.hero and alive(h) and not h.illusion and h.skills then
            for abId, lv in pairs(h.skills) do
                local ab = D.Abilities[abId]
                if ab.target == "aura" and lv > 0 then
                    for _, u in ipairs(w.list) do
                        if u.kind == "unit" and alive(u) and u.owner == h.owner and abs(u.x - h.x) <= ab.radius and abs(u.y - h.y) <= ab.radius
                           and dist(u.x, u.y, h.x, h.y) <= ab.radius then
                            u.aura = u.aura or {}
                            local a = u.aura
                            if ab.armor then a.armor = max(a.armor or 0, ab.armor[lv]) end
                            if ab.manaRegen then a.mana = max(a.mana or 0, ab.manaRegen[lv]) end
                            if ab.moveBonus then a.move = max(a.move or 0, ab.moveBonus[lv]) a.attack = max(a.attack or 0, ab.attackBonus[lv]) end
                            if ab.regenBonus then a.regen = max(a.regen or 0, ab.regenBonus[lv]) end
                            if ab.lifesteal then a.lifesteal = max(a.lifesteal or 0, ab.lifesteal[lv]) end
                        end
                    end
                end
            end
        end
    end
end

-- extra armour from agility, auras and Avatar
function S.heroArmorBonus(u)
    local a = 0
    if u.def.hero then
        local _, agi = S.heroStats(u)
        -- MiscGame: AgiDefenseBonus 0.30 per point, AgiDefenseBase -2
        a = a + agi * 0.3 - 2
        if S.hasBuff(u, "avatar") then a = a + 5 end
    end
    if u.aura and u.aura.armor then a = a + u.aura.armor end
    if S.hasBuff(u, "innerFire") then a = a + 5 end
    if u.ib then a = a + u.ib.armor end
    if S.hasBuff(u, "protection") then a = a + 2 end
    if S.hasBuff(u, "faerie") then a = a - 4 end
    if S.armorExtra then a = a + S.armorExtra(u) end
    return a
end

-- how much faster this unit attacks (agility, Endurance Aura); slows make it slower
function S.attackSpeed(w, u)
    local m = 1
    if u.def.hero then local _, agi = S.heroStats(u) m = m + 0.02 * agi end
    if u.aura and u.aura.attack then m = m + u.aura.attack end
    if u.slow and u.slow > 0 and u.slowAttack then m = m * (1 - u.slowAttack) end
    if S.hasBuff(u, "bloodlust") then m = m + 0.4 end
    if S.hasBuff(u, "berserk") then m = m + 0.5 end
    if S.hasBuff(u, "slowSpell") then m = m * 0.75 end
    if u.ib then m = m + u.ib.atk end
    if S.attackExtra then m = S.attackExtra(u, m) end
    return m
end

function S.moveSpeedMult(w, u)
    local m = 1
    if u.aura and u.aura.move then m = m + u.aura.move end
    local ww = u.buffs and u.buffs.windWalk
    if ww and ww.t > 0 then m = m + (ww.speed or 0) end
    local eth = u.buffs and u.buffs.ethereal
    if eth and eth.t > 0 and not eth.form then m = m * 0.5 end
    if S.hasBuff(u, "quake") then m = m * 0.25 end
    if S.hasBuff(u, "bloodlust") then m = m + 0.25 end
    if S.hasBuff(u, "slowSpell") then m = m * 0.4 end
    local pg = u.buffs and u.buffs.purged
    if pg and pg.t > 0 then m = m * (0.2 + 0.8 * max(0, 1 - pg.t / (pg.dur or 15))) end
    if S.hasBuff(u, "berserk") then m = m + 0.2 end
    if S.hasBuff(u, "ensnare") or S.hasBuff(u, "shackled") or S.hasBuff(u, "rooted") or u.devouredBy then m = 0 end
    -- a sheep moves at the sheep's own speed (WC3 nshe: 100)
    if S.hasBuff(u, "poly") then m = min(m, (100 / 128) / max(0.1, u.def.speed or 1)) end
    if u.ib and u.ib.move > 0 and (u.def.speed or 0) > 0 then m = m + u.ib.move / u.def.speed end
    if S.hasBuff(u, "haste") and (u.def.speed or 0) > 0 and m > 0 then m = max(m, (522 / 128) / u.def.speed) end
    if S.moveExtra then m = S.moveExtra(u, m) end
    return m
end

-- may u pick e as a target? (no invisible, invulnerable, or - for weapons - ethereal units)
function S.targetable(w, u, e)
    if e.kind ~= "unit" then return true end
    if S.hasBuff(e, "invuln") or S.hasBuff(e, "voodoo") or e.devouredBy then return false end
    if S.isInvisible(e) and not S.detected(w, u.owner, e) then return false end
    if S.hasBuff(e, "ethereal") then
        local wp = S.weaponFor(w, u, e)
        return wp and wp.atype == "magic" or false
    end
    return true
end

-- can this unit attack right now?
function S.canAct(u)
    if S.hasBuff(u, "hex") or S.hasBuff(u, "poly") or S.hasBuff(u, "ethereal") or S.hasBuff(u, "bladestorm") or S.hasBuff(u, "shackled") or u.devouredBy then return false end
    if u.channel then return false end
    return true
end

-- ------------------------------------------------------------------ hero attacks: crit, bash, backstab

function S.heroOnHit(w, src, tgt, dmg)
    if src.illusion then return 0 end
    local def = src.def
    if S.onHitExtra then dmg = S.onHitExtra(w, src, tgt, dmg) end
    -- creep passives (Bash, Critical Strike), the Spell Breaker's Feedback and item orbs
    if def.bash and tgt.kind == "unit" and w.rng.next() % 100 < def.bash[1] then dmg = dmg + def.bash[2] stun(w, tgt, tgt.def.hero and (def.bash[4] or 1) or def.bash[3], true) end
    if def.crit and w.rng.next() % 100 < def.crit[1] then dmg = dmg * def.crit[2] end
    if def.id == "spellBreaker" and tgt.kind == "unit" and (tgt.mana or 0) > 0 and not tgt.def.spellImmune then
        local burn = min(tgt.def.hero and 4 or 20, tgt.mana)    -- Afbk: 20 mana a hit, 4 on heroes
        tgt.mana = tgt.mana - burn
        dmg = dmg + burn
    end
    if src.ib and src.ib.orb and tgt.kind == "unit" then
        if src.ib.orb == "fire" then
            for _, e in ipairs(S.enemiesAround2(w, src, tgt.x, tgt.y, 1.1, tgt.def.air and true or false)) do
                if e ~= tgt then S.damage(w, src, e, 5, "magic", true) end
            end
        elseif src.ib.orb == "lightning" and not S.spellImmune(tgt) then
            -- Orb of Lightning (AIll): purges 35% of the time on units and summons, 10% on heroes;
            -- the purge holds the target 3 s and it recovers over 15 s (5 on heroes); summons take 150
            local chance = tgt.def.hero and 10 or 35
            if w.rng.next() % 100 < chance and S.isEnemy(src, tgt) then
                if tgt.def.summon then S.damage(w, src, tgt, 150, "magic", true)
                else
                    local d = tgt.def.hero and 5 or 15
                    S.buff(w, tgt, "purged", d, { dur = d })
                    S.buff(w, tgt, "rooted", 3)
                end
            end
        end
    end
    if not def.hero then return dmg end
    local ww = src.buffs and src.buffs.windWalk
    if ww and ww.t > 0 then
        dmg = dmg + (ww.backstab or 0)
        src.buffs.windWalk = nil
        S.event(w, { t = "float", x = tgt.x, y = tgt.y, text = "Backstab!", color = { 1, 0.4, 0.1 } })
    end
    local cl = S.skillLevel(src, "criticalStrike")
    if cl > 0 and w.rng.next() % 100 < 15 then
        dmg = dmg * D.Abilities.criticalStrike.mult[cl]
        S.event(w, { t = "float", x = tgt.x, y = tgt.y, text = floor(dmg) .. "!", color = { 1, 0.2, 0.2 } })
    end
    local bl = S.skillLevel(src, "bash")
    if bl > 0 and tgt.kind == "unit" and w.rng.next() % 100 < D.Abilities.bash.chance[bl] then
        dmg = dmg + D.Abilities.bash.bonus[bl]
        stun(w, tgt, tgt.def.hero and 1 or 2, true)
    end
    return dmg
end

-- ------------------------------------------------------------------ summons

local function summon(w, owner, id, x, y, life)
    local tx, ty = M.tileOf(x, y)
    if not M.walkable(w, tx, ty) and not D.Units[id].air then
        local nx, ny = M.nearestOpen(w, tx, ty, 4)
        if nx then x, y = nx - 0.5, ny - 0.5 end
    end
    local u = S.addUnit(w, owner, id, x, y)
    u.life = life
    S.event(w, { t = "effect", x = x, y = y, model = 165594, size = 1.6, life = 1 })
    return u
end
S.summonUnit = summon

-- ------------------------------------------------------------------ casting

function S.abilityValue(ab, field, lv) local t = ab[field] return t and t[min(lv, #t)] or nil end

function S.canCast(w, u, abId)
    local ab = D.Abilities[abId]
    if not ab or not alive(u) or not (u.def.hero or u.def.spells) then return false end
    local lv = S.skillLevel(u, abId)
    if lv < 1 then
        if ab.research then return false, "Needs " .. D.Research[ab.research[1]].names[ab.research[2]] .. "." end
        return false, ab.name .. " hasn't been learned yet."
    end
    u.abilityCd = u.abilityCd or {}
    u.mana = u.mana or 0
    if ab.target == "passive" or ab.target == "aura" then return false end
    if (u.abilityCd[abId] or 0) > 0 then return false, ab.name .. " isn't ready yet." end
    local mana = S.abilityValue(ab, "mana", lv) or 0
    if u.mana < mana then return false, "Not enough mana." end
    if (u.stun or 0) > 0 or S.hasBuff(u, "hex") or S.hasBuff(u, "poly") or u.devouredBy then return false end
    if S.hasBuff(u, "silence") or S.hasBuff(u, "soulburn") or S.hasBuff(u, "doom") then return false, "Silenced." end
    if u.hidden then return false end
    if ab.ready then local ok, why = ab.ready(w, u) if not ok then return false, why end end
    return true
end

local function validTarget(w, u, ab, tgt)
    if ab.anyTarget and alive(tgt) and tgt.kind == "building" then
        if not S.isEnemy(u, tgt) then return false, "Must target an enemy." end
        return true
    end
    if not alive(tgt) or tgt.kind ~= "unit" then return false, "Must target a unit." end
    if ab.target == "enemy" and not S.isEnemy(u, tgt) then return false, "Must target an enemy." end
    if ab.target == "ally" and S.isEnemy(u, tgt) then return false, "Must target a friendly unit." end
    if ab.noSelf and tgt == u then return false, "Can't target yourself." end
    if S.spellImmune(tgt) and tgt ~= u then return false, "That unit is immune to spells." end
    if ab.id == "siphonMana" and (tgt.maxMana or 0) <= 0 and not tgt.def.mana then return false, "That unit has no mana." end
    if ab.id == "holyLight" and tgt.hp >= tgt.maxhp then return false, "Already at full health." end
    if ab.noHero and tgt.def.hero then return false, "Can't target heroes." end
    if ab.noMech and tgt.def.mech then return false, "Can't target mechanical units." end
    if ab.airOnly and not tgt.def.air then return false, "Must target a flying unit." end
    if ab.groundOnly and tgt.def.air and not S.hasBuff(tgt, "ensnare") then return false, "Must target a ground unit." end
    if ab.noWard and tgt.def.ward then return false, "Can't target wards." end
    if ab.check then local ok, why = ab.check(w, u, tgt) if not ok then return false, why end end
    return true
end

function S.castCommand(w, u, cmd)
    local ab = D.Abilities[cmd.ability]
    local ok, why = S.canCast(w, u, cmd.ability)
    if not ok then return false, why end
    if ab.target == "enemy" or ab.target == "ally" or ab.target == "unit" then
        local okT, whyT = validTarget(w, u, ab, w.ents[cmd.target])
        if not okT then return false, whyT end
    elseif ab.target == "friend" then
        local tgt = w.ents[cmd.target]
        if not alive(tgt) or tgt.owner ~= u.owner then return false, "Must target one of your units or buildings." end
    end
    S.issue(w, u, { type = "cast", ability = cmd.ability, target = cmd.target, x = cmd.x, y = cmd.y })
    return true
end

local function enemiesAround(w, u, x, y, r, includeAir)
    local out = {}
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.hidden and (includeAir ~= false or not e.def.air) then
            if abs(e.x - x) <= r + 1 and abs(e.y - y) <= r + 1 and dist(e.x, e.y, x, y) <= r + e.def.radius * 0.5 then out[#out + 1] = e end
        end
    end
    return out
end
S.enemiesAround2 = enemiesAround

local function fx(w, x, y, model, size, life, follow, delay)
    S.event(w, { t = "effect", x = x, y = y, model = model, size = size or 2, life = life or 1.2, follow = follow, delay = delay })
end
S.fxAt = fx

-- bounce spells (Chain Lightning, Healing Wave)
local function bounce(w, u, first, ab, lv, heal)
    local hit = {}
    local amount = heal and ab.heal[lv] or ab.dmg[lv]
    local cur = first
    local px, py = u.x, u.y
    for i = 1, ab.jumps[lv] do
        if not cur then break end
        hit[cur.id] = true
        S.event(w, { t = "vfx", kind = "bounce", x1 = px, y1 = py, x2 = cur.x, y2 = cur.y, heal = heal, delay = (i - 1) * 0.15 })
        px, py = cur.x, cur.y
        fx(w, cur.x, cur.y, ab.effect, 1.6, 0.8, nil, (i - 1) * 0.15)
        if heal then cur.hp = min(cur.maxhp, cur.hp + amount)
        else S.damage(w, u, cur, amount, "magic", true) end
        amount = amount * (1 - ab.decay)
        -- next: closest unhit target in range (wounded friends first for healing)
        local best, bd
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and alive(e) and not hit[e.id] and not e.hidden and dist(e.x, e.y, cur.x, cur.y) <= ab.jumpRange
               and (heal and not S.isEnemy(u, e) and e.hp < e.maxhp or (not heal and S.isEnemy(u, e))) and not S.spellImmune(e) and not (ab.noMech and e.def.mech) then
                local d = dist(e.x, e.y, cur.x, cur.y)
                if not bd or d < bd then best, bd = e, d end
            end
        end
        cur = best
    end
end

local function doCast(w, u, o)
    local abId = o.ability
    local ab = D.Abilities[abId]
    local lv = S.skillLevel(u, abId)
    local cost = S.abilityValue(ab, "mana", lv) or 0
    u.mana = (u.mana or 0) - cost
    u.abilityCd = u.abilityCd or {}
    u.abilityCd[abId] = S.abilityValue(ab, "cd", lv) or 0
    u.anim, u.animT = ab.castAnim or "cast", 0.6
    if abId ~= "windWalk" and u.buffs then u.buffs.windWalk = nil u.buffs.invis = nil end
    S.event(w, { t = "cast", unit = u.id, ability = abId, target = o.target, x = o.x, y = o.y })
    if S.castExtra and cost > 0 then S.castExtra(w, u, abId, cost) if not alive(u) then return end end
    local tgt = w.ents[o.target or 0]
    local dur = S.abilityValue(ab, "dur", lv)
    local function durFor(e) return e.def.hero and (S.abilityValue(ab, "heroDur", lv) or dur) or dur end
    if ab.cast then ab.cast(w, u, o, tgt, lv, durFor) return end

    if abId == "holyLight" then
        tgt.hp = min(tgt.maxhp, tgt.hp + ab.heal[lv])
        fx(w, tgt.x, tgt.y, ab.effect, 1.8, 1.2, tgt.id)
    elseif abId == "divineShield" then
        S.buff(w, u, "invuln", dur)
    elseif abId == "resurrection" then
        local n = 0
        local keep = {}
        for _, c in ipairs(w.corpses or EMPTY) do
            if n < ab.count[1] and c.owner == u.owner and dist(c.x, c.y, u.x, u.y) <= ab.radius and w.time - c.t < 60 then
                n = n + 1
                local r = S.addUnit(w, c.owner, c.id, c.x, c.y)
                fx(w, c.x, c.y, ab.effect, 1.8, 1.5)
                if c.ent then c.ent.removed = true end
            else
                keep[#keep + 1] = c
            end
        end
        w.corpses = keep
        S.updateSupply(w)
    elseif abId == "blizzard" then
        u.channel = { ability = abId, x = o.x, y = o.y, waves = ab.waves[lv], dmg = ab.dmg[lv], t = 0.1, every = 1.0 }
    elseif abId == "waterElemental" then
        summon(w, u.owner, "waterElemental" .. lv, u.x + cos(u.facing) * 1.2, u.y + sin(u.facing) * 1.2, 60)
        S.updateSupply(w)
    elseif abId == "massTeleport" then
        u.teleport = { t = ab.delay, target = o.target }
        fx(w, u.x, u.y, ab.effect, 3.5, ab.delay)
    elseif abId == "stormBolt" then
        w.missiles[#w.missiles + 1] = { x = u.x, y = u.y, target = tgt.id, src = u.id, dmg = ab.dmg[lv], spell = true,
            stun = durFor(tgt), speed = T(1000), kind = "stormBolt", model = ab.missile, impact = ab.impact, owner = u.owner }
    elseif abId == "thunderClap" then
        local r = ab.radiusL[lv]
        fx(w, u.x, u.y, ab.effect, r * 2.4, 1.4)
        for _, e in ipairs(enemiesAround(w, u, u.x, u.y, r, false)) do
            if not S.spellImmune(e) and not e.def.mech then
                e.slow, e.slowFactor, e.slowAttack = durFor(e), ab.slow, 0.5
                S.damage(w, u, e, ab.dmg[lv], "magic", true)
            end
        end
    elseif abId == "avatar" then
        S.buff(w, u, "avatar", dur)
        fx(w, u.x, u.y, ab.effect, 2.4, 2, u.id)
    elseif abId == "flameStrike" then
        w.areas = w.areas or {}
        w.areas[#w.areas + 1] = { kind = "flame", x = o.x, y = o.y, r = ab.radius, delay = ab.delay, burst = ab.burst[lv], burnDps = ab.burn[lv],
            t = ab.delay + 6.3, owner = u.owner, src = u.id }
        fx(w, o.x, o.y, ab.effect, ab.radius * 2.6, ab.delay + 2.5, nil, ab.delay * 0.5)
    elseif abId == "banish" then
        S.buff(w, tgt, "ethereal", durFor(tgt))
        fx(w, tgt.x, tgt.y, ab.effect, 1.6, durFor(tgt), tgt.id)
    elseif abId == "siphonMana" then
        u.channel = { ability = abId, target = tgt.id, t = ab.dur[lv], drain = ab.drain[lv], range = ab.range + 2 }
        fx(w, tgt.x, tgt.y, ab.effect, 1.4, ab.dur[lv], tgt.id)
    elseif abId == "phoenix" then
        local p = summon(w, u.owner, "phoenix", u.x, u.y - 1, nil)
        S.updateSupply(w)
    elseif abId == "windWalk" then
        -- 0.6 s to fade out, during which he can still be attacked
        S.buff(w, u, "windWalk", dur, { speed = ab.speed[lv], backstab = ab.backstab[lv], fadeAt = w.time + 0.6 })
        fx(w, u.x, u.y, ab.effect, 1.6, 0.8)
    elseif abId == "mirrorImage" then
        -- it also dispels every magic effect on the Blademaster
        if u.buffs then for id in pairs(u.buffs) do if id ~= "windWalk" then u.buffs[id] = nil end end end
        u.slow, u.stun = 0, 0
        -- the hero and its images swap places so the enemy can't tell which is real
        local spots = { { u.x, u.y } }
        for i = 1, ab.count[lv] do
            local a = (i / (ab.count[lv] + 1)) * 2 * pi
            spots[#spots + 1] = { u.x + cos(a) * 1.2, u.y + sin(a) * 1.2 }
        end
        for i = #spots, 2, -1 do local j = w.rng.next() % i + 1 spots[i], spots[j] = spots[j], spots[i] end
        u.x, u.y = spots[1][1], spots[1][2]
        u.px, u.py = u.x, u.y
        for i = 2, #spots do
            local img = S.addUnit(w, u.owner, u.def.id, spots[i][1], spots[i][2])
            img.illusion = true
            img.life = dur
            img.level, img.skills, img.points = u.level, {}, 0
            S.refreshHero(img)
            img.hp = img.maxhp * (u.hp / u.maxhp)
            img.facing = u.facing
            if img.def.hero then
                local pl = w.players[u.owner]
                for k = #pl.heroes, 1, -1 do if pl.heroes[k] == img.id then table.remove(pl.heroes, k) end end
            end
        end
        S.updateSupply(w)
        fx(w, u.x, u.y, ab.effect, 2.2, 0.8)
    elseif abId == "bladestorm" then
        S.buff(w, u, "bladestorm", dur, { dps = ab.dps[1], r = ab.radius })
        fx(w, u.x, u.y, ab.effect, 2.6, dur, u.id)
    elseif abId == "chainLightning" then
        bounce(w, u, tgt, ab, lv, false)
    elseif abId == "farSight" then
        w.reveals = w.reveals or {}
        w.reveals[#w.reveals + 1] = { owner = u.owner, x = o.x, y = o.y, r = ab.radiusL[lv], t = dur, detect = true }
        fx(w, o.x, o.y, ab.effect, 2.5, 1.5)
        S.updateVision(w)
    elseif abId == "feralSpirit" then
        for i = 1, ab.count[lv] do
            summon(w, u.owner, "spiritWolf" .. lv, u.x + cos(u.facing + (i - 1.5)) * 1.2, u.y + sin(u.facing + (i - 1.5)) * 1.2, 60)
        end
        S.updateSupply(w)
    elseif abId == "earthquake" then
        w.areas = w.areas or {}
        w.areas[#w.areas + 1] = { kind = "quake", x = o.x, y = o.y, r = ab.radius, t = dur, buildingDps = ab.buildingDps[1], owner = u.owner, src = u.id }
    elseif abId == "shockwave" then
        local dx, dy = (o.x or u.x) - u.x, (o.y or u.y) - u.y
        local d = sqrt(dx * dx + dy * dy)
        if d < 0.1 then dx, dy, d = cos(u.facing), sin(u.facing), 1 end
        dx, dy = dx / d, dy / d
        u.facing = atan2(dy, dx)
        for s = 1, ab.length, 1.4 do fx(w, u.x + dx * s, u.y + dy * s, ab.effect, 2.2, 1.0, nil, s / 14) end
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.hidden and not e.def.air and not S.spellImmune(e) then
                local rx, ry = e.x - u.x, e.y - u.y
                local along = rx * dx + ry * dy
                if along > 0 and along <= ab.length and abs(rx * dy - ry * dx) <= ab.width / 2 + e.def.radius then
                    S.damage(w, u, e, ab.dmg[lv], "magic", true)
                end
            elseif e.kind == "building" and alive(e) and S.isEnemy(u, e) then
                local rx, ry = e.x - u.x, e.y - u.y
                local along = rx * dx + ry * dy
                if along > 0 and along <= ab.length + e.size / 2 and abs(rx * dy - ry * dx) <= ab.width / 2 + e.size / 2 then
                    S.damage(w, u, e, ab.dmg[lv], "magic", true)
                end
            end
        end
    elseif abId == "warStomp" then
        local r = ab.radiusL[lv]
        fx(w, u.x, u.y, ab.effect, r * 2.4, 1.4)
        for _, e in ipairs(enemiesAround(w, u, u.x, u.y, r, false)) do
            if not S.spellImmune(e) and not e.def.mech then
                stun(w, e, durFor(e))
                S.damage(w, u, e, ab.dmg[lv], "magic", true)
            end
        end
    elseif abId == "healingWave" then
        bounce(w, u, tgt, ab, lv, true)
    elseif abId == "hex" then
        S.buff(w, tgt, "hex", durFor(tgt))
        tgt.swing = nil
        fx(w, tgt.x, tgt.y, ab.effect, 1.6, 0.8)
    elseif abId == "serpentWard" then
        summon(w, u.owner, "serpentWard" .. lv, o.x, o.y, dur)
        S.updateSupply(w)
    elseif abId == "bigBadVoodoo" then
        u.channel = { ability = abId, t = dur, r = ab.radius }
        fx(w, u.x, u.y, ab.effect, 3, dur, u.id)
    end
end

-- the "cast" order: walk into range, then cast
function S.stepCast(w, u, dt, o, stepMove)
    local ab = D.Abilities[o.ability]
    if not S.canCast(w, u, o.ability) then return false end
    local lv = S.skillLevel(u, o.ability)
    local range = ab.range or 0
    if ab.target == "enemy" or ab.target == "ally" or ab.target == "unit" then
        local tgt = w.ents[o.target or 0]
        if not validTarget(w, u, ab, tgt) then return false end
        if S.gap(u, tgt) > range then stepMove(w, u, dt, nil, nil, tgt, range) return true end
        u.facing = atan2(tgt.y - u.y, tgt.x - u.x)
    elseif ab.target == "point" then
        if dist(u.x, u.y, o.x, o.y) > range + 0.3 then stepMove(w, u, dt, o.x, o.y, nil, range) return true end
        u.facing = atan2(o.y - u.y, o.x - u.x)
    elseif ab.target == "friend" then
        local tgt = w.ents[o.target or 0]
        if not alive(tgt) then return false end
        o.x, o.y = tgt.x, tgt.y
    end
    -- the cast point: the caster plays its spell animation (and a glow gathers) before the spell goes off
    u.path = nil
    if not o.castT then
        o.castT = ab.castPoint or 0.45
        u.swing = nil
        if ab.precast ~= false then
            S.event(w, { t = "effect", x = u.x, y = u.y, model = S.precastModel(ab), size = (u.def.vis or 0.45) * 4, life = o.castT + 0.35, follow = u.id })
        end
    end
    o.castT = o.castT - dt
    u.anim, u.animT = ab.castAnim or "cast", 0.4
    if o.castT > 0 then return true end
    doCast(w, u, o)
    return false
end
S.doCast = doCast

-- the glow that gathers on a caster, by school of magic
local PRECAST = { holy = 166334, frost = 166378, fire = 166121, nature = 166492, shadow = 166808, arcane = 166526 }
local SCHOOL = {
    holyLight = "holy", divineShield = "holy", resurrection = "holy", blizzard = "frost", waterElemental = "frost", massTeleport = "arcane",
    stormBolt = "nature", flameStrike = "fire", banish = "shadow", siphonMana = "arcane", phoenix = "fire", chainLightning = "nature",
    farSight = "arcane", feralSpirit = "nature", earthquake = "nature", healingWave = "nature", hex = "shadow", serpentWard = "nature",
    bigBadVoodoo = "shadow",
}
-- warrior abilities use a battle roar instead of a spell glow
for _, id in ipairs({ "thunderClap", "warStomp", "shockwave", "avatar", "windWalk", "mirrorImage", "bladestorm", "divineShield" }) do
    local ab = D.Abilities[id]
    if ab then ab.precast = id == "divineShield" and nil or false ab.castAnim = (id ~= "windWalk" and id ~= "mirrorImage") and "roar" or nil ab.castPoint = 0.3 end
end
function S.precastModel(ab) return PRECAST[ab.school or SCHOOL[ab.id] or "arcane"] or PRECAST.arcane end

-- ------------------------------------------------------------------ per tick: buffs, channels, summons, areas

local function endChannel(u) u.channel = nil end

function S.stepHero(w, u, dt)
    -- buffs
    if u.buffs then
        for id, b in pairs(u.buffs) do
            b.t = b.t - dt
            if b.t <= 0 then
                u.buffs[id] = nil
                if id == "avatar" and u.def.hero then S.refreshHero(u) end
            end
        end
        local bs = u.buffs.bladestorm
        if bs then
            bs.acc = (bs.acc or 0) + bs.dps * dt
            if bs.acc >= 20 then
                local n = floor(bs.acc)
                bs.acc = bs.acc - n
                for _, e in ipairs(enemiesAround(w, u, u.x, u.y, bs.r, false)) do S.damage(w, u, e, n, "normal", true) end
                -- it cuts buildings too
                for _, b in ipairs(w.list) do
                    if b.kind == "building" and alive(b) and S.isEnemy(u, b) and S.edgeDist(u.x, u.y, b) <= bs.r then S.damage(w, u, b, n, "normal", true) end
                end
            end
            u.anim = "spin"
        end
    end
    -- summoned and illusion lifetimes
    if u.life then
        u.life = u.life - dt
        if u.life <= 0 then
            if u.def.id == "phoenixEgg" then
                local x, y, owner = u.x, u.y, u.owner
                S.kill(w, u, nil, true) u.removed = true
                summon(w, owner, "phoenix", x, y, nil)
                S.updateSupply(w)
                return
            end
            S.kill(w, u, nil, true) u.removed = true return
        end
    end
    -- the phoenix burns: itself, and enemies around it
    if u.def.burnAura then
        u.burnAcc = (u.burnAcc or 0) + dt
        if u.burnAcc >= 1 then
            u.burnAcc = u.burnAcc - 1
            for _, e in ipairs(enemiesAround(w, u, u.x, u.y, 1.4, true)) do S.damage(w, u, e, u.def.burnAura, "magic", true) end
            S.damage(w, nil, u, u.def.selfBurn, "chaos", true)
            if not alive(u) then return end
        end
    end
    if S.stepExtra and S.stepExtra(w, u, dt) then return end
    if not u.def.hero or u.illusion then return end
    -- regeneration from attributes (plus Brilliance Aura)
    u.hp = min(u.maxhp, u.hp + u.hpRegen * dt)
    u.mana = min(u.maxMana, u.mana + (u.manaRegen + (u.aura and u.aura.mana or 0)) * dt)
    for k, v in pairs(u.abilityCd) do if v > 0 then u.abilityCd[k] = v - dt end end
    -- Mass Teleport countdown
    if u.teleport then
        u.teleport.t = u.teleport.t - dt
        if u.teleport.t <= 0 then
            local dest = w.ents[u.teleport.target or 0]
            u.lastTeleport = u.teleport
            u.teleport = nil
            if alive(dest) then
                local ab = D.Abilities.massTeleport
                local tp = u.lastTeleport or {}
                local n = 0
                local movers = { u }
                local count, radius = tp.count or ab.count[1], tp.radius or ab.radius
                for _, e in ipairs(w.list) do
                    if e ~= u and e.kind == "unit" and alive(e) and e.owner == u.owner and not e.def.ward and n < count - 1
                       and dist(e.x, e.y, u.x, u.y) <= radius then
                        n = n + 1
                        movers[#movers + 1] = e
                    end
                end
                for i, e in ipairs(movers) do
                    local a = i * 2.4
                    local r = 0.8 + 0.25 * i
                    local tx, ty = M.tileOf(dest.x + cos(a) * r, dest.y + sin(a) * r + (dest.kind == "building" and dest.size / 2 + 0.5 or 0))
                    local nx, ny = M.nearestOpen(w, tx, ty, 6)
                    if nx then e.x, e.y = nx - 0.5, ny - 0.5 e.px, e.py = e.x, e.y e.path = nil e.order = nil end
                end
                fx(w, dest.x, dest.y, ab.effect, 3.5, 1.5)
                S.updateVision(w)
            end
        end
    end
    -- channelled spells
    local ch = u.channel
    if ch then
        if (u.stun or 0) > 0 or S.hasBuff(u, "hex") or (u.order and u.order.type ~= "cast" and u.order.type ~= "channel") then
            endChannel(u)
            return
        end
        u.anim = "cast"
        if ch.ability == "blizzard" then
            ch.t = ch.t - dt
            if ch.t <= 0 then
                ch.t = ch.every
                ch.waves = ch.waves - 1
                local ab = D.Abilities.blizzard
                fx(w, ch.x, ch.y, ab.effect, ab.radius * 2.6, 1.2)
                S.event(w, { t = "vfx", kind = "wave", x = ch.x, y = ch.y, r = ab.radius })
                for _, e in ipairs(w.list) do
                    if alive(e) and (e.kind == "unit" or (e.kind == "building" and S.isEnemy(u, e))) and e ~= u and not e.hidden and dist(e.x, e.y, ch.x, ch.y) <= ab.radius + (e.size or 0) / 2 then
                        if not S.spellImmune(e) then S.damage(w, u, e, ch.dmg * (e.kind == "building" and 0.5 or 1), "magic", true) end
                    end
                end
                if ch.waves <= 0 then endChannel(u) end
            end
        elseif ch.ability == "siphonMana" then
            local tgt = w.ents[ch.target or 0]
            ch.t = ch.t - dt
            if not alive(tgt) or dist(tgt.x, tgt.y, u.x, u.y) > ch.range or ch.t <= 0 then endChannel(u) return end
            if S.isEnemy(u, tgt) then
                local take = min(tgt.mana or 0, ch.drain * dt)
                tgt.mana = (tgt.mana or 0) - take
                u.mana = min(u.maxMana, u.mana + take)
            else
                -- on a friend it works the other way: the Blood Mage gives mana
                local give = min(u.mana, ch.drain * dt, max(0, (tgt.maxMana or 0) - (tgt.mana or 0)))
                u.mana = u.mana - give
                tgt.mana = (tgt.mana or 0) + give
            end
        elseif D.Abilities[ch.ability] and D.Abilities[ch.ability].tick then
            if D.Abilities[ch.ability].tick(w, u, dt, ch) == false then endChannel(u) end
        elseif ch.ability == "bigBadVoodoo" then
            ch.t = ch.t - dt
            for _, e in ipairs(w.list) do
                if e.kind == "unit" and alive(e) and e.owner == u.owner and e ~= u and dist(e.x, e.y, u.x, u.y) <= ch.r then
                    S.buff(w, e, "voodoo", 0.3)
                end
            end
            if ch.t <= 0 then endChannel(u) end
        end
    end
end

-- ground effects that last a while: Flame Strike, Earthquake, Far Sight
function S.stepAreas(w, dt)
    if w.areas and #w.areas > 0 then
        local keep = {}
        for _, a in ipairs(w.areas) do
            a.t = a.t - dt
            local src = w.ents[a.src or 0]
            local fake = src or { owner = a.owner }
            if a.kind == "flame" then
                if a.delay then
                    a.delay = a.delay - dt
                    if a.delay <= 0 then
                        a.delay = nil
                        for _, e in ipairs(w.list) do
                            if alive(e) and (e.kind == "unit" or (e.kind == "building" and S.isEnemy(fake, e))) and not e.hidden and not (e.def and e.def.air) and dist(e.x, e.y, a.x, a.y) <= a.r + (e.size or 0) / 2 then
                                if e.kind ~= "unit" or not S.spellImmune(e) then S.damage(w, src, e, a.burst * (e.kind == "building" and 0.75 or 1), "magic", true) end
                            end
                        end
                    end
                else
                    a.acc = (a.acc or 0) + dt
                    if a.acc >= 1 then
                        a.acc = a.acc - 1
                        for _, e in ipairs(w.list) do
                            if alive(e) and not e.hidden and not (e.def and e.def.air) and (e.kind == "unit" or (e.kind == "building" and S.isEnemy(fake, e)))
                               and dist(e.x, e.y, a.x, a.y) <= a.r + (e.size or 0) / 2 and (e.kind ~= "unit" or not S.spellImmune(e)) then
                                S.damage(w, src, e, a.burnDps * (e.kind == "building" and 0.75 or 1), "magic", true)
                            end
                        end
                    end
                end
            elseif a.tick then
                a.tick(w, a, dt, src, fake)
            elseif a.kind == "quake" then
                for _, e in ipairs(enemiesAround(w, fake, a.x, a.y, a.r, false)) do S.buff(w, e, "quake", 0.3) end
                a.acc = (a.acc or 0) + a.buildingDps * dt
                if a.acc >= 5 then
                    local n = floor(a.acc)
                    a.acc = a.acc - n
                    for _, b in ipairs(w.list) do
                        if b.kind == "building" and alive(b) and b.owner >= 1 and dist(b.x, b.y, a.x, a.y) <= a.r + b.size / 2 then
                            S.damage(w, src, b, n, "siege", true)
                        end
                    end
                end
                a.fxT = (a.fxT or 0) - dt
                if a.fxT <= 0 then a.fxT = 1.2 S.event(w, { t = "effect", x = a.x + (w.rng.float() - 0.5) * a.r, y = a.y + (w.rng.float() - 0.5) * a.r, model = 165976, size = 2.2, life = 1.2 }) end
            end
            if a.t > 0 then keep[#keep + 1] = a end
        end
        w.areas = keep
    end
    if w.reveals and #w.reveals > 0 then
        local keep = {}
        for _, r in ipairs(w.reveals) do
            r.t = r.t - dt
            if r.t > 0 then keep[#keep + 1] = r end
        end
        w.reveals = keep
    end
    w.auraT = (w.auraT or 0) - dt
    if w.auraT <= 0 then
        w.auraT = 0.3
        S.stepAuras(w)
    end
end

-- ------------------------------------------------------------------ death, reincarnation, revival

-- the Tauren Chieftain's Reincarnation: called as a hero would die. true = it came back instead.
function S.tryReincarnate(w, u)
    if not u.def.hero or u.illusion then return false end
    if S.skillLevel(u, "reincarnation") < 1 or (u.abilityCd.reincarnation or 0) > 0 then return false end
    u.abilityCd.reincarnation = D.Abilities.reincarnation.cd[1]
    u.hp = 1
    u.reviveT = D.Abilities.reincarnation.delay
    u.anim = "death"
    u.order = nil
    u.channel = nil
    S.buff(w, u, "invuln", u.reviveT)
    u.swing = nil
    fx(w, u.x, u.y, 166464, 2.5, u.reviveT + 1.5, u.id, u.reviveT - 0.5)
    return true
end

function S.stepReincarnate(w, u, dt)
    if u.reviveT then
        u.reviveT = u.reviveT - dt
        u.anim = "death"
        if u.reviveT <= 0 then
            u.reviveT = nil
            u.hp, u.mana = u.maxhp, u.maxMana
            u.anim = "stand"
            if u.buffs then u.buffs.invuln = nil end
        end
        return true
    end
end

-- remember a fallen hero so the altar can revive it, and leave corpses for Resurrection
function S.onDeath(w, e)
    if e.kind ~= "unit" then return end
    if S.deathExtra then S.deathExtra(w, e) end
    if e.def.id == "phoenix" and not e.illusion then
        local egg = summon(w, e.owner, "phoenixEgg", e.x, e.y, 7)
        S.updateSupply(w)
    end
    if e.def.hero and not e.illusion then
        local pl = w.players[e.owner]
        if pl and e.owner <= 2 then
            pl.deadHeroes = pl.deadHeroes or {}
            pl.deadHeroes[#pl.deadHeroes + 1] = { id = e.def.id, level = e.level, xp = e.xp, points = e.points, skills = e.skills,
                inv = e.inv, tomeStr = e.tomeStr, tomeAgi = e.tomeAgi, tomeInt = e.tomeInt }
            for k = #(pl.heroes or EMPTY), 1, -1 do if pl.heroes[k] == e.id then table.remove(pl.heroes, k) end end
        end
    elseif not e.def.summon and not e.illusion and e.owner <= 2 and not e.def.air then
        w.corpses = w.corpses or {}
        w.corpses[#w.corpses + 1] = { id = e.def.id, owner = e.owner, x = e.x, y = e.y, t = w.time, ent = e }
        if #w.corpses > 60 then table.remove(w.corpses, 1) end
    end
end

-- how many heroes a player has (alive, dead or being trained) and how many they may have now
function S.heroCount(w, p)
    local pl = w.players[p]
    local n = 0
    for _, id in ipairs(pl.heroes or EMPTY) do if alive(w.ents[id]) then n = n + 1 end end
    n = n + #(pl.deadHeroes or EMPTY)
    for _, e in ipairs(w.list) do
        if e.kind == "building" and e.owner == p and alive(e) then
            for _, q in ipairs(e.queue) do if D.Units[q] and D.Units[q].hero then n = n + 1 end end
        end
    end
    return n
end

function S.deadHero(w, p, id)
    for i, r in ipairs(w.players[p].deadHeroes or EMPTY) do if r.id == id then return r, i end end
end

function S.hasHeroType(w, p, id)
    for _, hid in ipairs(w.players[p].heroes or EMPTY) do local h = w.ents[hid] if alive(h) and h.def.id == id then return true end end
    if S.deadHero(w, p, id) then return true end
    for _, e in ipairs(w.list) do
        if e.kind == "building" and e.owner == p and alive(e) then for _, q in ipairs(e.queue) do if q == id then return true end end end
    end
    return false
end

-- WC3: the 2nd hero needs a tier-2 hall, the 3rd a tier-3 hall; at most 3
function S.heroAllowed(w, p, id)
    local F = D.Factions[w.players[p].faction]
    if S.deadHero(w, p, id) then return true end
    if S.hasHeroType(w, p, id) then return false, "You already have this hero." end
    local n = S.heroCount(w, p)
    if n >= 3 then return false, "You can have at most 3 heroes." end
    if n == 1 and not S.has(w, p, F.halls[2]) then return false, "A second hero needs a " .. D.Buildings[F.halls[2]].name .. "." end
    if n == 2 and not S.has(w, p, F.halls[3]) then return false, "A third hero needs a " .. D.Buildings[F.halls[3]].name .. "." end
    return true
end

-- WC3 revive cost grows with the hero's level
function S.reviveCost(rec)
    local g = min(700, floor(425 * (0.4 + 0.1 * rec.level)))
    -- time: 0.65 x the hero's 55 s build time per level, at most 2 x the build time (110 s)
    return g, 0, min(110, 55 * 0.65 * rec.level)
end

-- an ability's tooltip with the numbers for one level filled in
local TIP_FIELDS = { "heal", "dmg", "burst", "mult", "chance", "backstab", "drain", "dps", "buildingDps", "moveBonus", "manaRegen", "armor", "count", "dur" }
function S.abilityTip(ab, lv)
    local v
    for _, f in ipairs(TIP_FIELDS) do
        local t = ab[f]
        if type(t) == "table" then v = t[min(lv, #t)] if f == "moveBonus" then v = v * 100 end break end
    end
    local ok, text = pcall(string.format, ab.tip or "", v or 0)
    text = ok and text or (ab.tip or "")
    local mana, cd = S.abilityValue(ab, "mana", lv), S.abilityValue(ab, "cd", lv)
    local extra = {}
    if mana and mana > 0 then extra[#extra + 1] = mana .. " mana" end
    if cd and cd > 0 then extra[#extra + 1] = cd .. " s cooldown" end
    if ab.ult then extra[#extra + 1] = "ultimate, hero level 6" end
    if #extra > 0 then text = text .. "\n|cffaaaaaa" .. table.concat(extra, ", ") .. "|r" end
    return text
end
