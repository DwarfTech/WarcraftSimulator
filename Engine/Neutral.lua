-- Skirmish engine: neutral creeps, items, shops and mercenaries (Warcraft III).
-- Creep camps guard the map and drop items; heroes carry six items; the Arcane Vault, Voodoo
-- Lounge and Goblin Merchant sell them; the Mercenary Camp and Goblin Laboratory hire units.
-- Item numbers are from WC3's ItemData and item abilities; creep stats from UnitBalance/UnitWeapons.

local _, ns = ...
local E = ns.Engine
local D, M, S = E.Data, E.Map, E.Sim

local floor, abs, max, min, sqrt, cos, sin, pi = math.floor, math.abs, math.max, math.min, math.sqrt, math.cos, math.sin, math.pi
local function alive(e) return e and not e.dead and not e.removed end
local function dist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by return sqrt(dx * dx + dy * dy) end
local function T(units) return units / 128 end
local ICON = "Interface\\Icons\\"
local EMPTY = {}
local NEUTRAL = 3

local function fx(w, x, y, model, size, life, follow)
    S.event(w, { t = "effect", x = x, y = y, model = model, size = size or 2, life = life or 1.2, follow = follow })
end

-- ------------------------------------------------------------------ creep and mercenary touches

local FAMILY_ICON = {
    kobold = "INV_Misc_Head_Kobold_01", gnoll = "INV_Misc_Head_Gnoll_01", troll = "INV_Misc_Head_Troll_01", ogre = "INV_Misc_Head_Ogre_01",
    wolf = "Ability_Mount_WhiteDireWolf", murloc = "INV_Misc_Head_Murloc_01", harpy = "INV_Feather_04", golem = "INV_Stone_15",
    satyr = "Spell_Shadow_SummonFelHunter", furbolg = "INV_Misc_Pelt_Bear_01", bandit = "INV_Misc_Bandana_03", rogue = "Ability_Stealth",
    goblin = "INV_Misc_Head_Gnome_01",
}
for id, u in pairs(D.Units) do
    if u.faction == "neutral" and u.wc3 then
        for fam, icon in pairs(FAMILY_ICON) do
            if id:lower():find(fam:lower()) then u.icon = ICON .. icon break end
        end
        u.acquire = 3.9               -- creeps wake up when something comes within 500
        if u.mana and not u.mana0 then u.mana0 = u.mana end
    end
end
D.Units.timberWolf.icon, D.Units.giantWolf.icon = ICON .. "Ability_Mount_WhiteDireWolf", ICON .. "Ability_Mount_WhiteDireWolf"
D.Units.mudGolem.icon, D.Units.rockGolem.icon = ICON .. "INV_Stone_15", ICON .. "INV_Stone_15"
D.Units.bandit.icon = ICON .. "INV_Misc_Bandana_03"
D.Units.dragonhawk.radius, D.Units.dragonhawk.vis = 0.48, 0.62
-- the Goblin Shredder cuts lumber: 10 a swing, 200 a trip, and nothing else
do
    local s = D.Units.goblinShredder
    s.worker, s.lumberOnly, s.noBuild, s.chop, s.chopTime, s.lumberTrip = true, true, true, 10, 1.35, 200
end
D.Units.spellBreaker.spells = { "spellSteal", "controlMagic", "feedback" }
D.Units.dragonhawk.spells = { "aerialShackles", "cloud" }

-- extra abilities creeps and the new units use
local function A(t)
    t.unit, t.maxLevel = true, 1
    for _, f in ipairs({ "mana", "cd", "dur", "heroDur" }) do if type(t[f]) == "number" then t[f] = { t[f] } end end
    D.Abilities[t.id] = t
end
A{ id = "lesserHeal", name = "Heal", key = "E", target = "ally", mana = 5, cd = 1, range = T(250), autocast = true, castPoint = 0.3, noMech = true, school = "holy",
   icon = ICON .. "Spell_Holy_Heal02", tip = "Heals a wounded friendly unit for 12 hit points.",
   check = function(w, u, t) if t.hp >= t.maxhp then return false, "Already at full health." end return true end,
   cast = function(w, u, o, t) t.hp = min(t.maxhp, t.hp + 12) fx(w, t.x, t.y, 166696, 1.4, 0.8, t.id) end }
A{ id = "faerieFire", name = "Faerie Fire", key = "F", target = "enemy", mana = 45, cd = 8, range = T(700), dur = 30, heroDur = 15, school = "nature",
   icon = ICON .. "Spell_Nature_FaerieFire", tip = "Lowers an enemy's armour by 4 and shows it to you for 30 seconds.",
   cast = function(w, u, o, t, lv, durFor) S.buff(w, t, "faerie", durFor(t)) fx(w, t.x, t.y, 166061, 1.4, 1.0, t.id) end }
A{ id = "kaboom", name = "Kaboom!", key = "K", target = "unit", mana = 0, cd = 1, range = 0.7, precast = false, castPoint = 0.1, anyTarget = true,
   icon = ICON .. "INV_Misc_Bomb_08", tip = "The Sapper blows itself up: 250 damage to units nearby, and three times that to buildings.",
   check = function(w, u, t) return true end,
   cast = function(w, u, o, t)
       local x, y = (t and t.x) or u.x, (t and t.y) or u.y
       fx(w, x, y, 165744, 3.2, 1.4)
       S.event(w, { t = "vfx", kind = "impact", x = x, y = y, c = "fire", n = 24, r = 2, ring = 2 })
       for _, e in ipairs(w.list) do
           if alive(e) and e.kind ~= "mine" and e.kind ~= "item" and S.isEnemy(u, e) and not (e.def and e.def.air) then
               local d = e.kind == "building" and S.edgeDist(x, y, e) or dist(e.x, e.y, x, y)
               if d <= T(250) then S.damage(w, u, e, e.kind == "building" and 750 or 250, "siege", true) end
           end
       end
       S.kill(w, u, nil)
   end }
-- the Spell Breaker
A{ id = "feedback", name = "Feedback", target = "passive", icon = ICON .. "Spell_Shadow_ManaBurn",
   tip = "Each attack burns 20 mana; the mana burned is dealt as extra damage." }
A{ id = "spellSteal", name = "Spell Steal", key = "T", target = "unit", mana = 75, cd = 3, range = T(700), autocast = true, castPoint = 0.3, school = "arcane",
   icon = ICON .. "Spell_Arcane_Arcane02", tip = "Takes a helpful spell off an enemy and gives it to a friend nearby, or a harmful one off a friend and puts it on an enemy.",
   cast = function(w, u, o, t) S.stealSpell(w, u, t) end }
A{ id = "controlMagic", name = "Control Magic", key = "C", target = "enemy", mana = 25, cd = 5, range = T(700), research = { "controlMagic", 1 }, school = "arcane",
   icon = ICON .. "Spell_Shadow_Charm", tip = "Takes control of an enemy summoned unit (costs extra mana for its hit points).",
   check = function(w, u, t)
       if not t.def.summon then return false, "Must target a summoned unit." end
       if (u.mana or 0) < 25 + t.hp * 0.45 then return false, "Not enough mana." end
       return true
   end,
   cast = function(w, u, o, t)
       u.mana = max(0, u.mana - t.hp * 0.45)
       t.owner = u.owner
       t.order, t.swing, t.channel = nil, nil, nil
       fx(w, t.x, t.y, 166430, 1.8, 1.0)
       S.updateSupply(w)
   end }
-- the Dragonhawk Rider
A{ id = "aerialShackles", noMech = true, name = "Aerial Shackles", key = "A", target = "enemy", mana = 75, cd = 30, range = T(550), dur = 40, heroDur = 10, airOnly = true, school = "arcane",
   icon = ICON .. "Spell_Nature_StrangleVines", tip = "Holds a flying unit helpless for up to 40 seconds (10 on heroes), dealing 30 damage a second. The Dragonhawk must keep channelling.",
   cast = function(w, u, o, t, lv, durFor)
       u.channel = { ability = "aerialShackles", target = t.id, t = durFor(t), range = T(550) + 2 }
       S.buff(w, t, "shackled", durFor(t))
       t.swing = nil
   end }
A{ id = "cloud", name = "Cloud", key = "C", target = "point", mana = 100, cd = 20, range = T(1000), radius = T(300), dur = 30, research = { "cloud", 1 }, school = "frost",
   icon = ICON .. "Spell_Frost_FrostNova", tip = "Covers an area in cloud for 30 seconds: towers and other buildings inside can't attack.",
   cast = function(w, u, o)
       w.areas = w.areas or {}
       w.areas[#w.areas + 1] = { kind = "cloud", x = o.x, y = o.y, r = T(300), t = 30, owner = u.owner, src = u.id }
   end }

-- ---------------------------------------------------------- creep spells
-- Creeps use WC3's creep versions of spells (ACxx in AbilityData), with their own mana, cooldowns
-- and durations. A creep spell copies the player spell's behaviour and changes the numbers.
local function creepSpell(id, base, t)
    local b = D.Abilities[base]
    local c = {}
    for k, v in pairs(b) do c[k] = v end
    for k, v in pairs(t) do c[k] = v end
    for _, f in ipairs({ "mana", "cd", "dur", "heroDur", "dmg" }) do if type(c[f]) == "number" then c[f] = { c[f] } end end
    c.id, c.base, c.maxLevel, c.research = id, base, 1, nil
    D.Abilities[id] = c
    return c
end
creepSpell("creepSlow", "slow", { mana = 50, cd = 8, range = T(600), dur = 20, heroDur = 10 })                       -- ACsw
creepSpell("creepPurge", "purge", { mana = 75, cd = 5, range = T(700), recover = 5, recoverHero = 5, root = nil })    -- ACpu
creepSpell("creepInnerFire", "innerFire", { mana = 75, cd = 5, range = T(500) })                                     -- ACif
creepSpell("creepBloodlust", "bloodlust", { mana = 75, cd = 8, range = T(600), dur = 40, heroDur = 40 })             -- ACbl
creepSpell("creepEnsnare", "ensnare", { mana = 0, cd = 10, range = T(500), dur = 10, heroDur = 5, noHero = true })  -- ACen
creepSpell("creepShockwave", "shockwave", { mana = 100, cd = 8, range = T(700), width = T(150) * 2, dmg = 75 })      -- ACsh
creepSpell("hurlBoulder", "stormBolt", { name = "Hurl Boulder", mana = 75, cd = 8, range = T(800), dmg = 100, dur = 2, heroDur = 2 })  -- ACtb
A{ id = "abolishMagic", name = "Abolish Magic", key = "D", target = "unit", mana = 75, cd = 0, range = T(500), school = "holy",   -- ACdm / ACd2
   icon = ICON .. "Spell_Holy_DispelMagic", tip = "Removes helpful magic from an enemy or harmful magic from a friend. Summoned units take 300 damage.",
   check = function(w, u, t)
       if S.isEnemy(u, t) then
           if t.def.summon then return true end
           for id in pairs(t.buffs or EMPTY) do if id == "innerFire" or id == "bloodlust" or id == "invis" or id == "lightningShield" or id == "haste" then return true end end
           return false, "Nothing to remove."
       end
       for id in pairs(t.buffs or EMPTY) do if id == "slowSpell" or id == "faerie" or id == "curse" or id == "purged" or id == "ensnare" then return true end end
       return false, "Nothing to remove."
   end,
   cast = function(w, u, o, t)
       fx(w, t.x, t.y, 165955, 1.6, 1.0, t.id)
       if S.isEnemy(u, t) then
           if t.def.summon then S.damage(w, u, t, 300, "magic", true) return end
           for _, id in ipairs({ "innerFire", "bloodlust", "invis", "lightningShield", "haste" }) do if t.buffs then t.buffs[id] = nil end end
       else
           for _, id in ipairs({ "slowSpell", "faerie", "curse", "purged", "ensnare", "rooted" }) do if t.buffs then t.buffs[id] = nil end end
       end
   end }
A{ id = "curse", name = "Curse", key = "C", target = "enemy", mana = 40, cd = 8, range = T(700), dur = 30, heroDur = 15, noMech = true, school = "shadow",  -- ACcs
   icon = ICON .. "Spell_Shadow_CurseOfTounges", tip = "The target misses 33% of its attacks for 30 seconds (15 on heroes).",
   check = function(w, u, t) if S.hasBuff(t, "curse") then return false, "Already cursed." end return true end,
   cast = function(w, u, o, t, lv, durFor) S.buff(w, t, "curse", durFor(t)) fx(w, t.x, t.y, 166808, 1.4, 1.0, t.id) end }
A{ id = "sleep", name = "Sleep", key = "S", target = "enemy", mana = 125, cd = 6, range = T(800), dur = 10, heroDur = 5, noMech = true, school = "shadow",  -- ACsl
   icon = ICON .. "Spell_Nature_Sleep", tip = "Puts an enemy to sleep for 10 seconds (5 on heroes). Damage wakes it.",
   cast = function(w, u, o, t, lv, durFor)
       local d = durFor(t)
       S.buff(w, t, "sleep", d)
       S.stunUnit(w, t, d)
       fx(w, t.x, t.y, 166808, 1.4, 1.0, t.id)
   end }
A{ id = "rejuvenation", name = "Rejuvenation", key = "R", target = "ally", mana = 150, cd = 1, range = T(400), dur = 12, noMech = true, school = "nature",   -- ACr2
   icon = ICON .. "Spell_Nature_Rejuvenation", tip = "Heals a friendly unit for 400 hit points over 12 seconds.",
   check = function(w, u, t) if t.hp > t.maxhp - 150 then return false, "Not hurt enough." end return true end,
   cast = function(w, u, o, t) S.buff(w, t, "rejuv", 12, { hps = 400 / 12 }) fx(w, t.x, t.y, 166492, 1.4, 1.0, t.id) end }

-- each creep's spells, from WC3's UnitAbilities
local CREEP_SPELLS = {
    koboldGeomancer = { "creepSlow", "abolishMagic" }, gnollWarden = { "creepPurge" }, trollShadowPriest = { "lesserHeal", "abolishMagic" },
    trollHighPriest = { "heal", "creepInnerFire", "abolishMagic" }, ogreLord = { "creepShockwave" }, murlocHuntsman = { "creepEnsnare" },
    harpyHag = { "curse", "sleep" }, mudGolem = { "creepSlow" }, rockGolem = { "hurlBoulder" }, satyrTrickster = { "creepPurge" },
    satyrHellcaller = { "creepBloodlust" }, furbolgShaman = { "rejuvenation" },
}
-- creeps from Blizzard's maps get their abilities from the game's UnitAbilities list
local CREEP_ABIL = { ACsw = "creepSlow", ACdm = "abolishMagic", ACd2 = "abolishMagic", ACpu = "creepPurge", ACif = "creepInnerFire",
    ACsh = "creepShockwave", ACen = "creepEnsnare", Aenw = "creepEnsnare", ACtb = "hurlBoulder", ACbl = "creepBloodlust", ACbb = "creepBloodlust",
    ACcs = "curse", ACsl = "sleep", Aslp = "sleep", ACr2 = "rejuvenation", ACrj = "rejuvenation", Anh1 = "lesserHeal", Anh2 = "heal",
    ACff = "faerieFire", ACls = "lightningShield" }
for id, u in pairs(D.Units) do
    if u.wc3abil and u.faction == "neutral" then
        local spells = {}
        for code in u.wc3abil:gmatch("[^,]+") do
            if CREEP_ABIL[code] and D.Abilities[CREEP_ABIL[code]] then spells[#spells + 1] = CREEP_ABIL[code]
            elseif code == "ACbh" then u.bash = { 15, 25, 2, 2 }
            elseif code == "ACct" then u.crit = { 20, 2 }
            elseif code == "ACmi" then u.spellImmune = true
            elseif code == "ACav" then u.creepAura = { armor = 3 }
            elseif code == "ACac" then u.creepAura = { dmg = 0.1 }
            elseif code == "ACat" then u.creepAura = { rangedDmg = 0.1 }
            elseif code == "ACua" then u.creepAura = { move = 0.1, regen = 0.5 }
            elseif code == "ACvs" then u.poisonHit = { 2, 20, 10 }
            elseif code == "ACev" then u.evasion = 15 end
        end
        if #spells > 0 then u.spells = spells end
    end
end
for id, list in pairs(CREEP_SPELLS) do if D.Units[id] then D.Units[id].spells = list end end
-- creep auras and on-hit effects
D.Units.trollWarlord.creepAura = { rangedDmg = 0.1 }                 -- ACat Trueshot Aura: +10% ranged damage
D.Units.satyrHellcaller.creepAura = { move = 0.1, regen = 0.5 }      -- ACua Unholy Aura
D.Units.murlocNightcrawler.poisonHit = { 2, 20, 10 }                 -- ACvs Envenomed Weapons: 2 dps, 20 s (10 on heroes)
for _, id in ipairs({ "koboldTaskmaster", "koboldLeader" }) do D.Units[id].bash = { 15, 25, 2, 2 } end   -- ACbh: 2 s on heroes too

-- creep auto-casting: offensive spells go on the creep's current target
local CREEP_CAST = { slow = true, purge = true, ensnare = true, faerieFire = true, stormBolt = true, shockwave = true,
    creepSlow = true, creepPurge = true, creepEnsnare = true, creepShockwave = true, hurlBoulder = true, curse = true, sleep = true, abolishMagic = true }

function S.creepThink(w, u)
    local o = u.order
    local tgt = o and w.ents[o.target or 0]
    if not alive(tgt) or tgt.kind ~= "unit" then return end
    for _, abId in ipairs(u.def.spells) do
        local ab = D.Abilities[abId]
        local tg = tgt
        -- Sleep goes on someone other than the creep's own target, so the others can keep hitting theirs
        if abId == "sleep" and S.hasBuff(tgt, "sleep") then tg = nil end
        if CREEP_CAST[abId] and tg and S.canCast(w, u, abId) and not ((abId == "slow" or abId == "creepSlow") and S.hasBuff(tgt, "slowSpell")) and not (abId == "faerieFire" and S.hasBuff(tgt, "faerie"))
           and not (abId == "abolishMagic" and not (D.Abilities.abolishMagic.check(w, u, tgt)))
           and not S.spellImmune(tgt) and S.dist(u.x, u.y, tgt.x, tgt.y) <= (ab.range or 6) + 1 then
            if ab.target == "point" then S.castCommand(w, u, { ability = abId, x = tgt.x, y = tgt.y })
            else S.castCommand(w, u, { ability = abId, target = tgt.id }) end
            return
        end
    end
end

-- ------------------------------------------------------------------ items

-- id = { name, icon, class, level, gold, effect fields... }
D.Items = {}
local function I(t)
    t.icon = ICON .. t.icon
    D.Items[t.id] = t
end
-- consumables (Purchasable / Charged)
I{ id = "phea", name = "Potion of Healing", icon = "INV_Potion_51", class = "charged", level = 1, gold = 150, uses = 1, heal = 250, cd = 20, stock = { 3, 120 }, tip = "Heals 250 hit points." }
I{ id = "pman", name = "Potion of Mana", icon = "INV_Potion_76", class = "charged", level = 1, gold = 200, uses = 1, mana = 150, cd = 20, stock = { 2, 120 }, tip = "Restores 150 mana." }
I{ id = "pghe", name = "Potion of Greater Healing", icon = "INV_Potion_54", class = "charged", level = 3, gold = 400, uses = 1, heal = 500, cd = 40, tip = "Heals 500 hit points." }
I{ id = "pgma", name = "Potion of Greater Mana", icon = "INV_Potion_73", class = "charged", level = 3, gold = 400, uses = 1, mana = 300, cd = 40, tip = "Restores 300 mana." }
I{ id = "pres", name = "Potion of Restoration", icon = "INV_Potion_28", class = "charged", level = 5, gold = 550, uses = 1, heal = 500, mana = 200, cd = 40, tip = "Restores 500 hit points and 200 mana." }
I{ id = "hslv", name = "Healing Salve", icon = "INV_Potion_08", class = "charged", level = 1, gold = 100, uses = 3, regen = { 400, 45 }, cd = 0, target = "ally", range = T(500), stock = { 2, 60 },
   tip = "Heals 400 hit points over 45 seconds. Wears off if the unit is hurt. 3 charges." }
I{ id = "plcl", name = "Lesser Clarity Potion", icon = "INV_Potion_02", class = "charged", level = 1, gold = 70, uses = 1, manaRegen = { 100, 30 }, stock = { 2, 30 },
   tip = "Restores 100 mana over 30 seconds. Wears off if the hero is hurt." }
I{ id = "shea", name = "Scroll of Healing", icon = "INV_Scroll_08", class = "charged", level = 2, gold = 250, uses = 1, areaHeal = 150, radius = T(600), cd = 25, stock = { 2, 120 },
   tip = "Heals your units around the hero for 150." }
I{ id = "spro", name = "Scroll of Protection", icon = "INV_Scroll_07", class = "charged", level = 1, gold = 150, uses = 1, areaArmor = 2, radius = T(600), dur = 30, stock = { 2, 120 },
   tip = "Your units around the hero get 2 armour for 30 seconds." }
I{ id = "sreg", name = "Scroll of Regeneration", icon = "INV_Scroll_06", class = "charged", level = 1, gold = 100, uses = 1, areaRegen = { 225, 45 }, radius = T(600), stock = { 2, 90 },
   tip = "Your units around the hero regain 225 hit points over 45 seconds (stops if they're hurt)." }
I{ id = "shas", name = "Scroll of Speed", icon = "INV_Scroll_05", class = "charged", level = 1, gold = 50, uses = 1, areaSpeed = 10, radius = T(600), cd = 60, stock = { 1, 60 },
   tip = "Your units around the hero run at top speed for 10 seconds." }
I{ id = "stwp", name = "Scroll of Town Portal", icon = "INV_Scroll_02", class = "charged", level = 2, gold = 350, uses = 1, townPortal = true, radius = T(1100), stock = { 2, 120 },
   tip = "After 5 seconds, takes the hero and nearby units home to your town hall." }
I{ id = "pinv", name = "Potion of Invisibility", icon = "INV_Potion_25", class = "charged", level = 1, gold = 100, uses = 1, invis = 120, stock = { 1, 120 }, tip = "The hero turns invisible for 2 minutes." }
I{ id = "pnvl", name = "Potion of Lesser Invulnerability", icon = "INV_Potion_62", class = "charged", level = 2, gold = 150, uses = 1, invuln = 7, cd = 45, stock = { 1, 120 },
   tip = "The hero can't be harmed for 7 seconds." }
I{ id = "dust", name = "Dust of Appearance", icon = "INV_Misc_Dust_02", class = "charged", level = 1, gold = 75, uses = 2, reveal = 20, radius = T(1000), cd = 20, stock = { 1, 60 },
   tip = "Shows invisible units around the hero for 20 seconds. 2 charges." }
I{ id = "wneg", name = "Wand of Negation", icon = "INV_Wand_04", class = "charged", level = 2, gold = 200, uses = 3, dispel = 200, radius = T(200), target = "point", range = T(500), stock = { 2, 90 },
   tip = "Removes magic in an area; summoned units take 200 damage. 3 charges." }
I{ id = "tret", name = "Tome of Retraining", icon = "INV_Misc_Book_11", class = "charged", level = 3, gold = 300, uses = 1, retrain = true, stock = { 1, 120 },
   tip = "The hero forgets its abilities, getting the skill points back to spend again." }
I{ id = "stel", name = "Staff of Teleportation", icon = "INV_Staff_14", class = "permanent", level = 2, gold = 150, teleport = true, target = "friend", cd = 90, stock = { 1, 120 },
   tip = "Teleports the hero to one of your units or buildings after 3 seconds." }
I{ id = "ssan", name = "Staff of Sanctuary", icon = "INV_Staff_19", class = "permanent", level = 3, gold = 250, sanctuary = true, target = "ally", range = T(700), cd = 45, stock = { 1, 120 },
   tip = "Sends a friendly unit home to your town hall and heals it." }
I{ id = "tsct", name = "Ivory Tower", icon = "INV_Misc_Statue_04", class = "charged", level = 1, gold = 40, lumber = 20, uses = 1, tower = "scoutTower", target = "point", range = T(300), stock = { 3, 30 },
   tip = "Builds a Scout Tower in an instant." }
I{ id = "tgrh", name = "Tiny Great Hall", icon = "INV_Misc_Statue_02", class = "charged", level = 3, gold = 600, lumber = 185, uses = 1, tower = "greatHall", target = "point", range = T(300), stock = { 1, 120 },
   tip = "Builds a Great Hall in an instant." }
I{ id = "mcri", name = "Mechanical Critter", icon = "INV_Misc_Gear_03", class = "charged", level = 1, gold = 50, uses = 1, critter = true, stock = { 2, 60 }, tip = "A wind-up scout that wanders where you send it." }
-- tomes and runes: used up as soon as they're picked up
I{ id = "tstr", name = "Tome of Strength", icon = "INV_Misc_Book_08", class = "powerup", level = 1, gold = 150, tomeStr = 1, tip = "Strength +1, for good." }
I{ id = "tagi", name = "Tome of Agility", icon = "INV_Misc_Book_07", class = "powerup", level = 1, gold = 150, tomeAgi = 1, tip = "Agility +1, for good." }
I{ id = "tint", name = "Tome of Intelligence", icon = "INV_Misc_Book_06", class = "powerup", level = 1, gold = 150, tomeInt = 1, tip = "Intelligence +1, for good." }
I{ id = "texp", name = "Tome of Experience", icon = "INV_Misc_Book_09", class = "powerup", level = 2, gold = 500, xp = 100, tip = "Gives the hero 100 experience." }
I{ id = "rhe1", name = "Rune of Lesser Healing", icon = "INV_Misc_Rune_06", class = "powerup", level = 1, gold = 100, areaHeal = 125, radius = T(800), tip = "Heals your units nearby for 125." }
I{ id = "rhe2", name = "Rune of Healing", icon = "INV_Misc_Rune_06", class = "powerup", level = 3, gold = 200, areaHeal = 250, radius = T(800), tip = "Heals your units nearby for 250." }
I{ id = "rhe3", name = "Rune of Greater Healing", icon = "INV_Misc_Rune_06", class = "powerup", level = 5, gold = 300, areaHeal = 400, radius = T(800), tip = "Heals your units nearby for 400." }
I{ id = "rma2", name = "Rune of Greater Mana", icon = "INV_Misc_Rune_05", class = "powerup", level = 4, gold = 300, areaMana = 300, radius = T(1200), tip = "Restores 300 mana to your units nearby." }
I{ id = "rres", name = "Rune of Restoration", icon = "INV_Misc_Rune_04", class = "powerup", level = 5, gold = 250, areaHeal = 300, areaMana = 150, radius = T(1200), tip = "300 hit points and 150 mana to your units nearby." }
I{ id = "gold", name = "Gold Coins", icon = "INV_Misc_Coin_02", class = "powerup", level = 1, gold = 150, giveGold = 250, tip = "250 gold." }
-- permanent items
I{ id = "rag1", name = "Slippers of Agility +3", icon = "INV_Boots_05", class = "permanent", level = 1, gold = 100, agi = 3 }
I{ id = "rin1", name = "Mantle of Intelligence +3", icon = "INV_Misc_Cape_06", class = "permanent", level = 1, gold = 100, int = 3 }
I{ id = "rst1", name = "Gauntlets of Ogre Strength +3", icon = "INV_Gauntlets_10", class = "permanent", level = 1, gold = 100, str = 3 }
I{ id = "cnob", name = "Circlet of Nobility", icon = "INV_Crown_01", class = "permanent", level = 2, gold = 175, str = 2, agi = 2, int = 2, stock = { 1, 120 } }
I{ id = "rat6", name = "Claws of Attack +6", icon = "INV_Misc_MonsterClaw_04", class = "permanent", level = 2, gold = 125, dmg = 6 }
I{ id = "rde1", name = "Ring of Protection +2", icon = "INV_Jewelry_Ring_03", class = "permanent", level = 2, gold = 125, armor = 2 }
I{ id = "gcel", name = "Gloves of Haste", icon = "INV_Gauntlets_05", class = "permanent", level = 2, gold = 125, atk = 0.15 }
I{ id = "rat9", name = "Claws of Attack +9", icon = "INV_Misc_MonsterClaw_04", class = "permanent", level = 3, gold = 300, dmg = 9 }
I{ id = "rde2", name = "Ring of Protection +3", icon = "INV_Jewelry_Ring_03", class = "permanent", level = 3, gold = 300, armor = 3 }
I{ id = "bspd", name = "Boots of Speed", icon = "INV_Boots_02", class = "permanent", level = 3, gold = 250, move = T(60), stock = { 1, 60 } }
I{ id = "rlif", name = "Ring of Regeneration", icon = "INV_Jewelry_Ring_15", class = "permanent", level = 3, gold = 300, hpRegen = 2 }
I{ id = "prvt", name = "Periapt of Vitality", icon = "INV_Jewelry_Necklace_03", class = "permanent", level = 3, gold = 350, hp = 150, stock = { 1, 120 } }
I{ id = "penr", name = "Pendant of Energy", icon = "INV_Jewelry_Necklace_04", class = "permanent", level = 3, gold = 300, mana = 150 }
I{ id = "ofir", name = "Orb of Fire", icon = "INV_Misc_Orb_05", class = "permanent", level = 3, gold = 275, dmg = 5, orb = "fire", stock = { 1, 120 }, tip = "+5 damage; attacks splash fire on enemies next to the target." }
I{ id = "oli2", name = "Orb of Lightning", icon = "INV_Misc_Orb_01", class = "permanent", level = 3, gold = 375, dmg = 5, orb = "lightning", stock = { 1, 120 }, tip = "+5 damage; attacks sometimes purge the target." }
I{ id = "bgst", name = "Belt of Giant Strength +6", icon = "INV_Belt_13", class = "permanent", level = 4, gold = 400, str = 6 }
I{ id = "belv", name = "Boots of Quel'Thalas +6", icon = "INV_Boots_07", class = "permanent", level = 4, gold = 400, agi = 6 }
I{ id = "ciri", name = "Robe of the Magi +6", icon = "INV_Chest_Cloth_25", class = "permanent", level = 4, gold = 400, int = 6 }
I{ id = "rwiz", name = "Sobi Mask", icon = "INV_Misc_Head_Troll_01", class = "permanent", level = 4, gold = 400, manaPct = 0.5 }
I{ id = "lhst", name = "Lion's Ring", icon = "INV_Jewelry_Ring_10", class = "permanent", level = 4, gold = 400, aura = { armor = 1 }, tip = "Devotion aura: nearby friends +1 armour." }
I{ id = "ratc", name = "Claws of Attack +12", icon = "INV_Misc_MonsterClaw_04", class = "permanent", level = 5, gold = 500, dmg = 12 }
I{ id = "hval", name = "Helm of Valor", icon = "INV_Helmet_08", class = "permanent", level = 5, gold = 500, str = 4, agi = 4 }
I{ id = "hcun", name = "Hood of Cunning", icon = "INV_Helmet_28", class = "permanent", level = 5, gold = 500, agi = 4, int = 4 }
I{ id = "mcou", name = "Medallion of Courage", icon = "INV_Jewelry_Talisman_04", class = "permanent", level = 5, gold = 500, str = 4, int = 4 }
I{ id = "ajen", name = "Ancient Janggo of Endurance", icon = "INV_Misc_Drum_01", class = "permanent", level = 5, gold = 500, aura = { move = 0.1, attack = 0.05 }, tip = "Endurance aura: nearby friends move 10% and attack 5% faster." }
I{ id = "kpin", name = "Khadgar's Pipe of Insight", icon = "INV_Misc_Pipe_01", class = "permanent", level = 5, gold = 500, aura = { mana = 0.75 }, tip = "Brilliance aura: nearby friends regain mana faster." }
I{ id = "clfm", name = "Cloak of Flames", icon = "INV_Misc_Cape_18", class = "permanent", level = 5, gold = 500, immolation = 10, tip = "Burns enemies next to the hero for 10 damage a second." }
I{ id = "rde3", name = "Ring of Protection +4", icon = "INV_Jewelry_Ring_03", class = "permanent", level = 6, gold = 600, armor = 4 }
I{ id = "rat9b", name = "Claws of Attack +15", icon = "INV_Misc_MonsterClaw_04", class = "permanent", level = 7, gold = 800, dmg = 15 }
I{ id = "rde4", name = "Ring of Protection +5", icon = "INV_Jewelry_Ring_03", class = "permanent", level = 7, gold = 800, armor = 5 }
I{ id = "ckng", name = "Crown of Kings +5", icon = "INV_Crown_02", class = "permanent", level = 8, gold = 1000, str = 5, agi = 5, int = 5 }

-- items creeps can drop, by level (WC3's random-item tables: permanent, charged and power-up items)
D.ItemsByLevel = {}
-- (shop-only items and orbs aren't in WC3's random tables: ItemData class Purchasable / Miscellaneous)
local NOT_RANDOM = { shea = true, stwp = true, pnvl = true, wneg = true, tret = true, ofir = true, oli2 = true }
for id, it in pairs(D.Items) do
    if it.level and (it.class ~= "charged" or it.level >= 2) and not it.tower and not it.critter and not NOT_RANDOM[id] then
        local l = it.level
        D.ItemsByLevel[l] = D.ItemsByLevel[l] or {}
        table.insert(D.ItemsByLevel[l], id)
    end
end
for _, l in pairs(D.ItemsByLevel) do table.sort(l) end

local function itemTip(it)
    local parts = {}
    for _, k in ipairs({ "str", "agi", "int" }) do if it[k] then parts[#parts + 1] = string.format("+%d %s", it[k], ({ str = "Strength", agi = "Agility", int = "Intelligence" })[k]) end end
    if it.dmg then parts[#parts + 1] = "+" .. it.dmg .. " damage" end
    if it.armor then parts[#parts + 1] = "+" .. it.armor .. " armour" end
    if it.atk then parts[#parts + 1] = string.format("+%d%% attack speed", it.atk * 100) end
    if it.move then parts[#parts + 1] = "+60 movement speed" end
    if it.hp then parts[#parts + 1] = "+" .. it.hp .. " hit points" end
    if it.mana and it.class == "permanent" then parts[#parts + 1] = "+" .. it.mana .. " mana" end
    if it.hpRegen then parts[#parts + 1] = "+" .. it.hpRegen .. " hit points a second" end
    if it.manaPct then parts[#parts + 1] = string.format("+%d%% mana regeneration", it.manaPct * 100) end
    return #parts > 0 and table.concat(parts, ", ") .. "." or ""
end
for _, it in pairs(D.Items) do if not it.tip then it.tip = itemTip(it) end end

-- ------------------------------------------------------------------ inventory

-- what a hero's items add up to
function S.refreshItems(w, u)
    local ib = { str = 0, agi = 0, int = 0, dmg = 0, armor = 0, atk = 0, move = 0, hp = 0, mana = 0, hpRegen = 0, manaPct = 0 }
    for i = 1, 6 do
        local slot = u.inv and u.inv[i]
        local it = slot and D.Items[slot.id]
        if it and it.class == "permanent" then
            for k in pairs(ib) do if type(it[k]) == "number" then ib[k] = ib[k] + it[k] end end
            if it.aura then ib.aura = it.aura end
            if it.immolation then ib.immolation = it.immolation end
            if it.orb then ib.orb = it.orb end
        end
    end
    u.ib = ib
    u.bonusStr = (u.tomeStr or 0) + ib.str
    u.bonusAgi = (u.tomeAgi or 0) + ib.agi
    u.bonusInt = (u.tomeInt or 0) + ib.int
    if u.def.hero then S.refreshHero(u) end
end

function S.freeSlot(u)
    for i = 1, 6 do if not (u.inv and u.inv[i]) then return i end end
end

local function powerUp(w, u, it)
    if it.tomeStr then u.tomeStr = (u.tomeStr or 0) + it.tomeStr end
    if it.tomeAgi then u.tomeAgi = (u.tomeAgi or 0) + it.tomeAgi end
    if it.tomeInt then u.tomeInt = (u.tomeInt or 0) + it.tomeInt end
    if it.xp and u.def.hero then S.addXp(w, u, it.xp) end
    if it.giveGold then local pl = w.players[u.owner] pl.gold = pl.gold + it.giveGold end
    if it.areaHeal or it.areaMana then
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and e.owner == u.owner and alive(e) and dist(e.x, e.y, u.x, u.y) <= it.radius then
                if it.areaHeal then e.hp = min(e.maxhp, e.hp + it.areaHeal) end
                if it.areaMana and e.maxMana then e.mana = min(e.maxMana, (e.mana or 0) + it.areaMana) end
            end
        end
        S.event(w, { t = "vfx", kind = "impact", x = u.x, y = u.y, c = it.areaMana and not it.areaHeal and "mana" or "nature", n = 20, r = 1.5, ring = it.radius })
    end
    S.refreshItems(w, u)
end

-- give an item to a hero: power-ups are used at once; others need a free slot
function S.giveItem(w, u, id, charges)
    local it = D.Items[id]
    if not it or not u.def.hero then return false, "Only heroes can carry items." end
    if not u.illusion and S.freeSlot(u) or it.class == "powerup" then
        local st = w.players[u.owner] and w.players[u.owner].stats
        if st then st.items = (st.items or 0) + 1 end
    end
    if it.class == "powerup" then
        powerUp(w, u, it)
        S.event(w, { t = "item", unit = u.id, item = id, owner = u.owner, used = true })
        return true
    end
    local i = S.freeSlot(u)
    if not i then return false, "Inventory is full." end
    u.inv = u.inv or {}
    u.inv[i] = { id = id, charges = charges or it.uses, cd = 0 }
    S.refreshItems(w, u)
    S.event(w, { t = "item", unit = u.id, item = id, owner = u.owner })
    return true
end

-- items on the ground
function S.spawnItem(w, id, x, y, charges)
    local it = D.Items[id]
    if not it then return end
    local e = { kind = "item", owner = 0, def = { id = id, name = it.name, icon = it.icon, radius = 0.25, item = true }, item = id, charges = charges,
                x = x, y = y, px = x, py = y, hp = 1, maxhp = 1, born = w.time }
    e.id = w.nextId
    w.nextId = w.nextId + 1
    w.ents[e.id] = e
    w.list[#w.list + 1] = e
    return e
end

function S.dropItem(w, u, slot)
    local s = u.inv and u.inv[slot]
    if not s then return false end
    u.inv[slot] = nil
    local a = (u.id * 1.7) % (2 * pi)
    S.spawnItem(w, s.id, u.x + cos(a) * 0.6, u.y + sin(a) * 0.6, s.charges)
    S.refreshItems(w, u)
    return true
end

function S.pickUp(w, u, e)
    if not alive(e) or e.kind ~= "item" then return false end
    local ok, why = S.giveItem(w, u, e.item, e.charges)
    if ok then e.removed = true end
    return ok, why
end

-- the "pickup" order: walk to the item, then take it
function S.stepPickup(w, u, dt, o, stepMove)
    local e = w.ents[o.item or 0]
    if not alive(e) then return false end
    if dist(u.x, u.y, e.x, e.y) > 0.9 then stepMove(w, u, dt, e.x, e.y, nil, 0.5) return true end
    local ok, why = S.pickUp(w, u, e)
    if not ok and why then S.event(w, { t = "error", owner = u.owner, text = why }) end
    return false
end

-- ------------------------------------------------------------------ using items

local function homeHall(w, p)
    local best
    for _, e in ipairs(w.list) do if e.kind == "building" and e.owner == p and alive(e) and e.def.hall and e.built then best = best or e end end
    return best
end
S.homeHall = homeHall

local function moveNear(w, e, x, y, k)
    local tx, ty = M.tileOf(x + cos(k * 2.4) * (0.8 + 0.2 * k), y + sin(k * 2.4) * (0.8 + 0.2 * k))
    local nx, ny = M.nearestOpen(w, tx, ty, 8)
    if nx then e.x, e.y = nx - 0.5, ny - 0.5 e.px, e.py = e.x, e.y e.path = nil e.order = nil end
end

function S.canUseItem(w, u, slot)
    local s = u.inv and u.inv[slot]
    if not s then return false end
    local it = D.Items[s.id]
    if it.class == "permanent" and not (it.teleport or it.sanctuary) then return false, it.name .. " works on its own." end
    if (s.cd or 0) > 0 then return false, it.name .. " isn't ready yet." end
    if it.heal and not it.mana and u.hp >= u.maxhp then return false, "Already at full health." end
    if it.mana and not it.heal and (u.maxMana or 0) - (u.mana or 0) < 1 then return false, "Already at full mana." end
    if (u.stun or 0) > 0 then return false end
    return true
end

function S.useItem(w, u, slot, target, x, y)
    local ok, why = S.canUseItem(w, u, slot)
    if not ok then return false, why end
    local s = u.inv[slot]
    local it = D.Items[s.id]
    local tgt = w.ents[target or 0]
    if it.target == "ally" or it.target == "friend" then
        if not alive(tgt) or tgt.owner ~= u.owner then return false, "Must target one of your units." end
        if it.range and dist(tgt.x, tgt.y, u.x, u.y) > it.range + 1 then return false, "Target is too far away." end
    elseif it.target == "point" then
        if not x then return false end
        if it.range and dist(x, y, u.x, u.y) > it.range + 1 then return false, "Too far away." end
    end
    tgt = tgt or u
    -- effects
    if it.heal then u.hp = min(u.maxhp, u.hp + it.heal) end
    if it.mana and it.class ~= "permanent" then u.mana = min(u.maxMana or 0, (u.mana or 0) + it.mana) end
    if it.heal or (it.mana and it.class ~= "permanent") then S.event(w, { t = "vfx", kind = "impact", x = u.x, y = u.y, c = it.heal and "nature" or "mana", n = 14, r = 0.9 }) end
    if it.regen then S.buff(w, tgt, "salve", it.regen[2], { amount = it.regen[1] / it.regen[2] }) end
    if it.manaRegen then S.buff(w, tgt, "clarity", it.manaRegen[2], { amount = it.manaRegen[1] / it.manaRegen[2] }) end
    if it.areaHeal or it.areaArmor or it.areaRegen or it.areaSpeed then
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and e.owner == u.owner and alive(e) and dist(e.x, e.y, u.x, u.y) <= it.radius then
                if it.areaHeal then e.hp = min(e.maxhp, e.hp + it.areaHeal) end
                if it.areaArmor then S.buff(w, e, "protection", it.dur) end
                if it.areaRegen then S.buff(w, e, "salve", it.areaRegen[2], { amount = it.areaRegen[1] / it.areaRegen[2] }) end
                if it.areaSpeed then S.buff(w, e, "haste", it.areaSpeed) end
            end
        end
        S.event(w, { t = "vfx", kind = "impact", x = u.x, y = u.y, c = "holy", n = 20, r = 1.6, ring = it.radius })
    end
    if it.townPortal then
        local hall = homeHall(w, u.owner)
        if not hall then return false, "You have no town hall." end
        u.teleport = { t = 5, target = hall.id, radius = it.radius, count = 99 }
    end
    if it.invis then S.buff(w, u, "invis", it.invis) end
    if it.invuln then S.buff(w, u, "invuln", it.invuln) end
    if it.reveal then
        w.reveals = w.reveals or {}
        w.reveals[#w.reveals + 1] = { owner = u.owner, x = u.x, y = u.y, r = it.radius, t = it.reveal, detect = true }
        S.updateVision(w)
    end
    if it.dispel then S.event(w, { t = "vfx", kind = "impact", x = x, y = y, c = "white", n = 12, r = 1, ring = it.radius }) S.dispelArea(w, u, x, y, it.radius, it.dispel) end
    if it.retrain then
        local n = 0
        for _, v in pairs(u.skills or EMPTY) do n = n + v end
        u.skills, u.points = {}, (u.points or 0) + n
    end
    if it.teleport then u.teleport = { t = 3, target = tgt.id, count = 0 } end
    if it.sanctuary then
        local hall = homeHall(w, u.owner)
        if hall then moveNear(w, tgt, hall.x, hall.y + hall.size / 2 + 0.5, 1) tgt.hp = min(tgt.maxhp, tgt.hp + 500) S.updateVision(w) end
    end
    if it.tower then
        local b = D.Buildings[it.tower]
        local tx, ty = floor(x - b.size / 2 + 0.5) + 1, floor(y - b.size / 2 + 0.5) + 1
        if not M.canPlace(w, tx, ty, b.size) then return false, "Can't build there." end
        S.addBuilding(w, u.owner, it.tower, tx, ty, true)
        S.updateSupply(w)
    end
    if it.critter then S.addUnit(w, u.owner, "critter", u.x + 0.6, u.y) S.updateSupply(w) end
    if it.use then
        local ok2, why2 = it.use(w, u, tgt, x, y)
        if ok2 == false then return false, why2 end
    end
    -- charges and cooldown
    s.cd = it.cd or 0
    if it.uses then
        s.charges = (s.charges or it.uses) - 1
        if s.charges <= 0 then u.inv[slot] = nil end
    end
    S.refreshItems(w, u)
    S.event(w, { t = "item", unit = u.id, item = it.id, owner = u.owner, used = true })
    return true
end

-- a wind-up critter for the Mechanical Critter item
D.Units.critter = { id = "critter", kind = "unit", faction = "neutral", name = "Mechanical Critter", role = "scout", hp = 50, armor = 0, dtype = "light",
    speed = T(400), sight = 7, supply = 0, gold = 0, lumber = 0, radius = 0.15, vis = 0.25, spaced = true, display = { 1206 }, icon = ICON .. "INV_Misc_Gear_03", summon = true }

-- ------------------------------------------------------------------ shops and mercenaries

local SHOP_RANGE = T(600) + 1

-- the hero of yours nearest a shop (within range)
function S.shopHero(w, p, shop)
    local best, bd
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and e.owner == p and alive(e) and e.def.hero and not e.illusion then
            local d = S.edgeDist(e.x, e.y, shop)
            if d <= SHOP_RANGE and (not bd or d < bd) then best, bd = e, d end
        end
    end
    return best
end

function S.shopUnit(w, p, shop)
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and e.owner == p and alive(e) and not e.def.ward and S.edgeDist(e.x, e.y, shop) <= SHOP_RANGE then return e end
    end
end

-- per player stock of each item / mercenary at each shop
-- seconds into the game before an item or mercenary is first in stock (ItemData / UnitBalance stockStart)
local STOCK_START = { phea = 440, pman = 440, pres = 440, shea = 440, spro = 440, stwp = 440, pinv = 440, pnvl = 440, tret = 440,
    stel = 220, bspd = 220, nftb = 220, nfsp = 120, nogm = 440, ngrk = 440, ngsp = 440, ngir = 300 }
local function stockOf(w, p, shop, id, def)
    local pl = w.players[p]
    pl.stock = pl.stock or {}
    local key = shop.id .. ":" .. id
    local st = pl.stock[key]
    local maxN, regen = (def.stock and def.stock[1]) or 1, (def.stock and def.stock[2]) or 120
    if not st then
        -- WC3 stockStart: some goods only appear a while into the game
        local start = STOCK_START[def.wc3 or id] or 0
        local waiting = start > 0 and w.time < start
        st = { n = waiting and 0 or maxN, t = 0, max = maxN, regen = regen, startAt = waiting and start or nil }
        pl.stock[key] = st
    end
    return st
end
S.stockOf = stockOf

function S.stepStock(w, dt)
    for p = 1, 2 do
        for _, st in pairs(w.players[p].stock or EMPTY) do
            if st.startAt then
                if w.time >= st.startAt then st.startAt = nil st.n = 1 st.t = 0 end
            elseif st.n < st.max then
                st.t = st.t + dt
                if st.t >= st.regen then st.t = 0 st.n = st.n + 1 end
            end
        end
    end
end

function S.buyItem(w, p, shopId, id)
    local shop = w.ents[shopId]
    local it = D.Items[id]
    if not alive(shop) or not it then return false end
    if shop.owner ~= p and shop.owner ~= 0 then return false end
    local hero = S.shopHero(w, p, shop)
    if not hero then return false, "A hero must be next to the shop." end
    if it.class ~= "powerup" and not S.freeSlot(hero) then return false, "Inventory is full." end
    local st = stockOf(w, p, shop, id, it)
    if st.n < 1 then return false, "Out of stock." end
    local pl = w.players[p]
    if pl.gold < it.gold then return false, "Not enough gold." end
    if pl.lumber < (it.lumber or 0) then return false, "Not enough lumber." end
    pl.gold, pl.lumber = pl.gold - it.gold, pl.lumber - (it.lumber or 0)
    st.n = st.n - 1
    S.giveItem(w, hero, id)
    return true
end

-- Alt-click on an item: sell it at a shop next to the hero, or else drop it on the ground
function S.sellOrDrop(w, p, heroId, slot)
    if S.sellItem(w, p, heroId, slot) then return true end
    local h = w.ents[heroId]
    if h and h.owner == p then return S.dropItem(w, h, slot) end
    return false
end

function S.sellItem(w, p, heroId, slot)
    local u = w.ents[heroId]
    if not alive(u) or u.owner ~= p then return false end
    local s = u.inv and u.inv[slot]
    if not s then return false end
    local shop
    for _, e in ipairs(w.list) do
        if e.kind == "building" and alive(e) and (e.def.shop or e.def.neutralShop) and (e.owner == p or e.owner == 0) and S.edgeDist(u.x, u.y, e) <= SHOP_RANGE then shop = e break end
    end
    if not shop then return false, "Bring the hero to a shop to sell items." end
    local it = D.Items[s.id]
    local value = floor(it.gold * 0.5 * ((s.charges and it.uses) and (s.charges / it.uses) or 1))
    w.players[p].gold = w.players[p].gold + value
    u.inv[slot] = nil
    S.refreshItems(w, u)
    S.event(w, { t = "float", x = u.x, y = u.y - 1, text = "+" .. value, color = { 1, 0.85, 0.2 } })
    return true
end

function S.hire(w, p, shopId, uid)
    local shop = w.ents[shopId]
    local def = D.Units[uid]
    if not alive(shop) or not def then return false end
    if not S.shopUnit(w, p, shop) then return false, "One of your units must be next to it." end
    local st = stockOf(w, p, shop, uid, def)
    if st.n < 1 then return false, "None available right now." end
    local pl = w.players[p]
    if pl.gold < def.gold then return false, "Not enough gold." end
    if pl.lumber < (def.lumber or 0) then return false, "Not enough lumber." end
    if pl.used + def.supply > pl.cap then return false, "Not enough food." end
    pl.gold, pl.lumber = pl.gold - def.gold, pl.lumber - (def.lumber or 0)
    st.n = st.n - 1
    local u = S.spawnFrom(w, shop, uid)
    if u then u.owner = p S.updateSupply(w) end
    if pl.stats then pl.stats.hired = (pl.stats.hired or 0) + 1 end
    return true
end

-- ------------------------------------------------------------------ creep camps

-- camps, by strength. Each list: creeps, then the level of the item the strongest creep drops.
D.CAMPS = {
    green = { { "kobold", "kobold", "koboldGeomancer", drop = 1 }, { "gnoll", "gnollPoacher", "gnoll", drop = 1 }, { "timberWolf", "timberWolf", drop = 1 },
              { "murloc", "murloc", "murlocHuntsman", drop = 1 }, { "satyr", "satyrTrickster", "satyr", drop = 1 } },
    orange = { { "ogre", "forestTroll", "trollShadowPriest", drop = 2 }, { "gnollBrute", "gnollWarden", "gnollBrute", drop = 2 },
               { "koboldTaskmaster", "koboldGeomancer", "koboldTaskmaster", drop = 2 }, { "giantWolf", "timberWolf", "timberWolf", drop = 3 },
               { "harpyWitch", "harpy", "harpy", drop = 2 }, { "mudGolem", "mudGolem", "bandit", drop = 2 } },
    red = { { "ogreMauler", "trollBerserker", "trollHighPriest", "forestTroll", drop = 4 }, { "furbolgTracker", "furbolg", "furbolgShaman", drop = 5 },
            { "ogreLord", "ogreMauler", "ogre", drop = 5 }, { "rockGolem", "mudGolem", "mudGolem", drop = 4 }, { "harpyHag", "harpyWitch", "harpyWitch", drop = 4 } },
}

function S.spawnCamp(w, x, y, list)
    local units = {}
    local n = #list
    for i, id in ipairs(list) do
        local a = (i / n) * 2 * pi
        local r = n > 1 and 0.9 or 0
        local u = S.addUnit(w, NEUTRAL, id, x + cos(a) * r, y + sin(a) * r)
        u.camp = { x, y }
        u.facing = math.atan2(32 - y, 32 - x)
        units[#units + 1] = u
    end
    -- the strongest creep carries the camp's item
    local best
    for _, u in ipairs(units) do if not best or (u.def.level or 1) > (best.def.level or 1) then best = u end end
    if best and list.drop then best.dropLevel = list.drop end
    return units
end

-- a creep that dies pays its bounty and maybe drops its item
function S.creepDied(w, e, killer)
    if e.owner ~= NEUTRAL or e.kind ~= "unit" then return end
    if killer and killer.owner >= 1 and killer.owner <= 2 and e.def.bounty then
        local b = e.def.bounty
        local g = b[1]
        for _ = 1, b[2] or 0 do g = g + 1 + w.rng.next() % max(1, b[3] or 1) end
        local pl = w.players[killer.owner]
        pl.gold = pl.gold + g
        S.event(w, { t = "bounty", x = e.x, y = e.y, amt = g, owner = killer.owner })
    end
    if e.dropLevel then
        local pool = D.ItemsByLevel[e.dropLevel] or D.ItemsByLevel[1]
        local id = pool[w.rng.next() % #pool + 1]
        S.spawnItem(w, id, e.x, e.y)
    end
    -- WC3 map drops: "i2" = a random permanent item of level 2 (j charged, k power-up, l artifact, y any)
    for k, code in ipairs(e.drops or EMPTY) do
        local cls, lvl = code:sub(1, 1), tonumber(code:sub(2)) or 1
        local want = ({ i = "permanent", j = "charged", k = "powerup", l = "artifact" })[cls]
        local pool = {}
        for _, id in ipairs(D.ItemsByLevel[lvl] or EMPTY) do
            if not want or D.Items[id].class == want then pool[#pool + 1] = id end
        end
        if #pool == 0 then pool = D.ItemsByLevel[lvl] or D.ItemsByLevel[1] end
        if pool and #pool > 0 then
            local id = pool[w.rng.next() % #pool + 1]
            S.spawnItem(w, id, e.x + (k - 1) * 0.4, e.y)
        end
    end
end

-- ------------------------------------------------------------------ neutral buildings on the map

function S.placeNeutral(w)
    for _, n in ipairs(w.neutralSpots or EMPTY) do
        local b = S.addBuilding(w, 0, n.id, n.x, n.y, true)
        b.invulnerable = true
    end
    for _, c in ipairs(w.campSpots or EMPTY) do
        if c.units then
            -- a camp from a Blizzard map: each creep where the map maker put it, with its own drops
            for _, cu in ipairs(c.units) do
                if D.Units[cu[1]] then
                    local u = S.addUnit(w, NEUTRAL, cu[1], cu[2], cu[3])
                    u.camp = { c.x, c.y }
                    u.facing = math.atan2(w.h / 2 - cu[3], w.w / 2 - cu[2])
                    u.drops = cu.drops
                end
            end
        else
            local opts = D.CAMPS[c.kind]
            local list = opts[(c.pick or 0) % #opts + 1]
            S.spawnCamp(w, c.x, c.y, list)
        end
    end
end

-- ------------------------------------------------------------------ the Spell Breaker's Spell Steal

local GOOD = { innerFire = true, bloodlust = true, invis = true, lightningShield = false, link = false, berserk = true, haste = true, protection = true }
local BAD = { slowSpell = true, faerie = true, ensnare = true, purged = true, poly = false, hex = false }

function S.stealSpell(w, u, t)
    if not alive(t) then return end
    local takeGood = S.isEnemy(u, t)
    for id, b in pairs(t.buffs or EMPTY) do
        if (takeGood and GOOD[id]) or (not takeGood and BAD[id]) then
            local data = b
            t.buffs[id] = nil
            -- hand it to the nearest suitable unit
            local best, bd
            for _, e in ipairs(w.list) do
                if e.kind == "unit" and alive(e) and e ~= t and (takeGood and e.owner == u.owner or (not takeGood and S.isEnemy(u, e))) and not S.spellImmune(e) then
                    local d = dist(e.x, e.y, t.x, t.y)
                    if d <= T(700) and (not bd or d < bd) then best, bd = e, d end
                end
            end
            if best then
                S.buff(w, best, id, data.t)
                S.event(w, { t = "vfx", kind = "bounce", x1 = t.x, y1 = t.y, x2 = best.x, y2 = best.y, heal = takeGood })
            end
            return true
        end
    end
end

-- autocast: Spell Steal looks for something worth stealing
function S.autoSpellSteal(w, u, ab)
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and e.buffs and S.gap(u, e) <= ab.range and not S.spellImmune(e) then
            local enemy = S.isEnemy(u, e)
            for id, b in pairs(e.buffs) do
                if b.t > 0 and ((enemy and GOOD[id]) or (not enemy and e.owner == u.owner and BAD[id])) then return e end
            end
        end
    end
end

-- ------------------------------------------------------------------ per tick

function S.stepNeutral(w, dt)
    S.stepStock(w, dt)
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and alive(u) then
            -- item cooldowns
            if u.inv then for i = 1, 6 do local s = u.inv[i] if s and (s.cd or 0) > 0 then s.cd = s.cd - dt end end end
            -- healing salve / clarity: wear off when the unit gets hurt
            local b = u.buffs
            if b and b.rejuv then u.hp = min(u.maxhp, u.hp + (b.rejuv.hps or 0) * dt) end
            if u.aura and u.aura.regen then u.hp = min(u.maxhp, u.hp + u.aura.regen * dt) end
            if b then
                if b.salve then
                    if (w.time - (u.hitT or -99)) < 0.2 and b.salve.t < 44 then b.salve = nil
                    else u.hp = min(u.maxhp, u.hp + b.salve.amount * dt) end
                end
                if b.clarity then
                    if (w.time - (u.hitT or -99)) < 0.2 and b.clarity.t < 29 then b.clarity = nil
                    elseif u.maxMana then u.mana = min(u.maxMana, (u.mana or 0) + b.clarity.amount * dt) end
                end
            end
            -- items: regeneration and Cloak of Flames
            local ib = u.ib
            if ib then
                if ib.hpRegen > 0 then u.hp = min(u.maxhp, u.hp + ib.hpRegen * dt) end
                if ib.immolation then
                    u.immoT = (u.immoT or 0) + dt
                    if u.immoT >= 1 then
                        u.immoT = u.immoT - 1
                        for _, e in ipairs(S.enemiesAround2(w, u, u.x, u.y, T(160) + 0.5, false)) do S.damage(w, u, e, ib.immolation, "magic", true) end
                    end
                end
            end
            -- Aerial Shackles: the Dragonhawk channels
            local ch = u.channel
            if ch and ch.ability == "aerialShackles" then
                local t = w.ents[ch.target or 0]
                ch.t = ch.t - dt
                ch.acc = (ch.acc or 0) + 30 * dt
                if not alive(t) or ch.t <= 0 or dist(t.x, t.y, u.x, u.y) > ch.range or (u.stun or 0) > 0 then
                    u.channel = nil
                    if t and t.buffs then t.buffs.shackled = nil end
                elseif ch.acc >= 5 then
                    local n = floor(ch.acc)
                    ch.acc = ch.acc - n
                    S.damage(w, u, t, n, "magic", true)
                end
            end
            -- creeps fight back with spells
            if u.owner == NEUTRAL and u.def.spells then
                u.creepT = (u.creepT or u.id % 7 * 0.1) - dt
                if u.creepT <= 0 then u.creepT = 0.7 S.creepThink(w, u) end
            end
        end
    end
end

-- buildings under Cloud can't attack
function S.clouded(w, b)
    for _, a in ipairs(w.areas or EMPTY) do
        if a.kind == "cloud" and S.isEnemy({ owner = a.owner }, b) and dist(a.x, a.y, b.x, b.y) <= a.r + b.size / 2 then return true end
    end
    return false
end
