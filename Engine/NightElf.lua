-- Skirmish engine: the Night Elf Sentinels (Warcraft III).
-- Wisps become the buildings they make, harvest lumber without felling trees, and mine an
-- Entangled Gold Mine (a Tree wraps the mine in roots). Moon Wells give food and pour their
-- mana into the health and mana of nearby troops. Archers, Huntresses and Dryads melt into
-- the shadows at night. Druids change shape, Archers ride Hippogryphs.
-- Four heroes (Demon Hunter, Keeper of the Grove, Priestess of the Moon, Warden) and their 16
-- abilities. Numbers are from War3.mpq (UnitBalance / UnitWeapons / AbilityData).
-- The Trees and Ancients Uproot and walk, Root again, and Eat Trees; Huntresses post Sentinels;
-- Faerie Dragons channel Mana Flare.

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

-- ------------------------------------------------------------------ unit data

D.Units.druidClaw.mana0, D.Units.druidClaw.manaRegen = 100, 0.667
D.Units.druidClawBear.mana0, D.Units.druidClawBear.manaRegen = 100, 0.667
D.Units.druidTalon.mana0, D.Units.druidTalon.manaRegen = 100, 0.667
D.Units.druidTalonCrow.mana0, D.Units.druidTalonCrow.manaRegen = 100, 0.667
D.Units.dryad.mana0, D.Units.dryad.manaRegen = 200, 0.667
D.Units.faerieDragon.mana0, D.Units.faerieDragon.manaRegen = 200, 0.667
D.Units.glaiveThrower.mech = true
D.Units.hippogryphRider.time, D.Units.hippogryphRider.gold, D.Units.hippogryphRider.lumber = 1, 290, 30
D.Units.dryad.slowPoison = true
D.Units.mountainGiant.resistantSkin = true
D.Units.huntress.bounce = true
D.Units.druidClawBear.formOf, D.Units.druidTalonCrow.formOf = "druidClaw", "druidTalon"
D.Units.treant.summon = true
for _, id in ipairs({ "archer", "huntress", "dryad" }) do D.Units[id].shadowmeld = true end
-- Night Elf buildings are made by a Wisp, which turns into the building
for _, b in pairs(D.Buildings) do
    if b.faction == "nightelf" then b.summoned, b.consumeBuilder = true, true end
end
D.Buildings.entangledMine.time = 10             -- Entangle Gold Mine (Aent)
D.Buildings.moonWell.wellMana = 300             -- emow manaN 300

local SPELLS = {
    wisp = { "detonate" },
    druidClaw = { "roar", "rejuvenationDruid", "bearForm" },
    druidClawBear = { "roar", "rejuvenationDruid", "humanForm" },
    druidTalon = { "faerieFireDruid", "crowForm", "cyclone" },
    druidTalonCrow = { "faerieFireDruid", "talonForm" },
    dryad = { "dryadAbolish" },
    hippogryph = { "pickUpArcher" },
    hippogryphRider = { "dismount" },
    mountainGiant = { "taunt", "warClub" },
    faerieDragon = { "phaseShift", "manaFlare" },
    huntress = { "sentinel" },
}
for id, list in pairs(SPELLS) do D.Units[id].spells = list end

-- ------------------------------------------------------------------ the heroes

local function NH(t)
    H(t)
    t.faction = "nightelf"
end
NH{ id = "demonHunter", name = "Demon Hunter", primary = "agi", str = 19, agi = 22, int = 16, strUp = 2.4, agiUp = 1.5, intUp = 2.1,
    armor = 0, sides = 12, cd = 1.7, dmgpt = 0.3, range = T(100), speed = T(320), display = { 4161 },
    icon = ICON .. "Spell_Shadow_ManaBurn", key = "D", abilities = { "manaBurn", "immolation", "evasion", "metamorphosis" },
    tip = "Cunning warrior hero. Mana Burn drains casters, Immolation burns everything near him, and he dodges blows." }
NH{ id = "keeper", name = "Keeper of the Grove", primary = "int", str = 16, agi = 15, int = 19, strUp = 1.8, agiUp = 1.5, intUp = 2.7,
    armor = 0, sides = 4, cd = 2.18, dmgpt = 0.4, range = T(600), speed = T(320), display = { 11906 }, missile = "voodoo",
    icon = ICON .. "Spell_Nature_StrangleVines", key = "K", abilities = { "entanglingRoots", "forceOfNature", "thornsAura", "tranquility" },
    tip = "Mystical hero. Entangling Roots holds an enemy, Force of Nature turns trees into Treants, Tranquility heals the army." }
NH{ id = "priestess", name = "Priestess of the Moon", primary = "agi", str = 18, agi = 19, int = 15, strUp = 1.9, agiUp = 1.5, intUp = 2.6,
    armor = 0, sides = 6, cd = 2.33, dmgpt = 0.3, range = T(600), speed = T(320), display = { 7274 }, mount = { 9695 }, missile = "arrow",
    icon = ICON .. "Spell_Nature_StarFall", key = "P", abilities = { "scout", "searingArrows", "trueshotAura", "starfall" },
    tip = "Cunning ranged hero on a white tiger. Searing Arrows burn, Trueshot Aura sharpens ranged troops, Starfall rains stars." }
NH{ id = "warden", name = "Warden", primary = "agi", str = 18, agi = 20, int = 15, strUp = 2.4, agiUp = 1.6, intUp = 2,
    armor = 0, sides = 11, cd = 2.05, dmgpt = 0.3, range = T(100), speed = T(320), display = { 11774 },
    icon = ICON .. "Ability_Warrior_Riposte", key = "W", abilities = { "fanOfKnives", "blink", "shadowStrike", "vengeance" },
    tip = "Cunning hero. Blink jumps across the field, Fan of Knives cuts everything around her, Shadow Strike poisons a target." }

D.NIGHTELF_HEROES = { "demonHunter", "keeper", "priestess", "warden" }

-- ------------------------------------------------------------------ summoned units

SU{ id = "owl", faction = "nightelf", name = "Owl Scout", role = "air", air = true, hp = 40, armor = 0, dtype = "light", atype = "normal",
    dmin = 1, dmax = 1, cd = 99, range = 0.1, speed = T(300), display = { 4615 }, noAttack = true, invisible = true, sight = T(1400),
    icon = ICON .. "Ability_Hunter_Pet_Owl", vis = 0.35 }
D.Units.owl.dmin = nil
-- the Huntress's Sentinel: an owl that sits in a tree and watches (it can't be hurt; it goes when the tree does)
SU{ id = "sentinelOwl", faction = "nightelf", name = "Sentinel", role = "ward", air = true, hp = 100, armor = 0, dtype = "light", atype = "normal",
    dmin = 1, dmax = 1, cd = 99, range = 0.1, speed = 0, display = { 4615 }, noAttack = true, ward = true, sight = T(900), nightSight = T(900),
    icon = ICON .. "Ability_Hunter_Pet_Owl", vis = 0.3 }
D.Units.sentinelOwl.dmin = nil
SU{ id = "avatarVengeance", faction = "nightelf", name = "Avatar of Vengeance", role = "ranged", hp = 1200, armor = 2, dtype = "heavy", atype = "normal",
    dmin = 25, dmax = 36, cd = 1.35, dmgpt = 0.33, range = T(450), speed = T(320), display = { 11774 }, alpha = 0.55, missile = "arcane", hitsAir = true,
    icon = ICON .. "Spell_Shadow_Twilight", vis = 0.55, level = 6 }
SU{ id = "spiritVengeance", faction = "nightelf", name = "Spirit of Vengeance", role = "ranged", hp = 500, armor = 5, dtype = "heavy", atype = "pierce",
    dmin = 17, dmax = 21, cd = 1.35, dmgpt = 0.33, range = T(450), speed = T(270), display = { 11774 }, alpha = 0.4, missile = "arcane", hitsAir = true,
    invulnerableSummon = true, icon = ICON .. "Spell_Shadow_Twilight", vis = 0.42, level = 3 }

-- ------------------------------------------------------------------ Entangle Gold Mine, Wisp harvesting

-- the Tree's "Entangle Gold Mine": wrap the nearest free mine in roots
function S.entangleTarget(w, p, tree)
    local best, bd
    for _, e in ipairs(w.list) do
        if e.kind == "mine" and alive(e) and e.gold > 0 and not (e.haunted and alive(w.ents[e.haunted])) then
            local d = dist(e.x, e.y, tree.x, tree.y)
            if d < 10 and (not bd or d < bd) then best, bd = e, d end
        end
    end
    return best
end

function S.entangle(w, p, treeId)
    local tree = w.ents[treeId]
    if not alive(tree) or tree.owner ~= p or not tree.built or not tree.def.entangle then return false end
    local m = S.entangleTarget(w, p, tree)
    if not m then return false, "There is no free gold mine near the Tree." end
    local b = S.addBuilding(w, p, "entangledMine", m.tx, m.ty, false)
    S.startSummoning(w, b)
    event(w, { t = "placed", unit = b.id, owner = p })
    return true
end

-- a Wisp at a tree: 5 lumber every 8 seconds, straight to the stockpile; the tree isn't cut down
function S.stepWispWood(w, u, dt, o, stepMove)
    if not o.tree or not w.trees[o.tree] then
        o.tree = M.nearestTree(w, u.x, u.y, 14)
        if not o.tree then u.order = nil return end
        o.state = nil
    end
    local x, y = (o.tree - 1) % w.w + 1, floor((o.tree - 1) / w.w) + 1
    local tr = { kind = "tree", tx = x, ty = y, size = 1, x = x - 0.5, y = y - 0.5, id = -o.tree }
    u.lastTree = o.tree
    if o.state ~= "wisp" then
        if stepMove(w, u, dt, nil, nil, tr, 0.45) then
            o.state, u.wispT = "wisp", 0
            u.facing = atan2(tr.y - u.y, tr.x - u.x)
        elseif u.path == nil and u.moved == false then
            o.tree = nil
        end
        return
    end
    u.anim = "work"
    u.wispT = (u.wispT or 0) + dt
    if u.wispT >= 8 then
        u.wispT = u.wispT - 8
        local pl = w.players[u.owner]
        pl.lumber = pl.lumber + 5
        pl.stats.lumber = pl.stats.lumber + 5
        event(w, { t = "deposit", unit = u.id, res = "lumber", amt = 5, owner = u.owner, x = u.x, y = u.y })
    end
end

-- ------------------------------------------------------------------ unit spells

local function UA(t)
    t.unit, t.maxLevel = true, 1
    for _, f in ipairs({ "mana", "cd", "dur", "heroDur" }) do if type(t[f]) == "number" then t[f] = { t[f] } end end
    D.Abilities[t.id] = t
end

-- change a unit into another form (druids), keeping how hurt it is and its mana
local function morph(w, u, to)
    local frac = u.hp / u.maxhp
    u.def = D.Units[to]
    u.maxhp = u.def.hp + S.hpBonus(w, u.owner, to)
    u.hp = max(1, floor(u.maxhp * frac))
    if u.def.mana then u.maxMana = u.def.mana + (S.bonus(w, u).mana or 0) u.mana = min(u.mana or 0, u.maxMana) end
    u.order, u.path, u.swing = nil, nil, nil
    u.abilityCd = u.abilityCd or {}
    fx(w, u.x, u.y, 166492, 1.8, 0.8)
    S.updateSupply(w)
end

UA{ id = "detonate", name = "Detonate", key = "D", target = "self", mana = 0, cd = 0, precast = false, castPoint = 0.1,
    icon = ICON .. "Spell_Nature_WispSplode", tip = "The Wisp explodes: it removes magic around it, burns 50 mana from each unit and does 225 damage to summoned units.",
    cast = function(w, u)
        fx(w, u.x, u.y, 165955, 2.4, 1.0)
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and alive(e) and e ~= u and dist(e.x, e.y, u.x, u.y) <= T(300) then
                if e.buffs then for id, b in pairs(e.buffs) do if b.t and b.t < 1e8 and id ~= "invuln" then e.buffs[id] = nil end end end
                if (e.mana or 0) > 0 then e.mana = max(0, e.mana - 50) end
                if e.def.summon and S.isEnemy(u, e) then S.damage(w, u, e, 225, "magic", true) end
            end
        end
        u.noCorpse = true
        S.kill(w, u, nil, true)
        u.removed = true
    end }
UA{ id = "roar", name = "Roar", key = "R", target = "none", mana = 100, cd = 1, dur = 45, school = "nature", castAnim = "roar", aiAuto = true,
    icon = ICON .. "Ability_Druid_DemoralizingRoar", tip = "Friendly units nearby deal 25% more damage for 45 seconds.",
    cast = function(w, u)
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and alive(e) and e.owner == u.owner and dist(e.x, e.y, u.x, u.y) <= T(500) then S.buff(w, e, "roar", 45) end
        end
        fx(w, u.x, u.y, 165726, 2.4, 1.0)
    end }
UA{ id = "rejuvenationDruid", name = "Rejuvenation", key = "E", target = "ally", mana = 125, cd = 1, range = T(400), dur = 12, research = { "clawTraining", 1 },
    noMech = true, school = "nature", aiAuto = true, icon = ICON .. "Spell_Nature_Rejuvenation",
    tip = "Heals a friendly unit for 400 hit points over 12 seconds.",
    check = function(w, u, t) if t.hp > t.maxhp - 100 then return false, "Not hurt enough." end return true end,
    cast = function(w, u, o, t) S.buff(w, t, "rejuv", 12, { hps = 400 / 12 }) fx(w, t.x, t.y, 166492, 1.4, 1.0, t.id) end }
UA{ id = "bearForm", name = "Bear Form", key = "F", target = "self", mana = 25, cd = 1, research = { "clawTraining", 2 }, precast = false, castPoint = 1.45,
    icon = ICON .. "Ability_Racial_BearForm", tip = "Turns into a great bear: much tougher and harder-hitting. Again to change back.",
    cast = function(w, u) morph(w, u, "druidClawBear") end }
UA{ id = "humanForm", name = "Night Elf Form", key = "F", target = "self", mana = 0, cd = 1, precast = false, castPoint = 1.0,
    icon = ICON .. "Ability_Druid_Bash", tip = "Changes back into a Night Elf.", cast = function(w, u) morph(w, u, u.def.formOf) end }
UA{ id = "faerieFireDruid", name = "Faerie Fire", key = "F", target = "enemy", mana = 45, cd = 1, range = T(700), dur = 90, heroDur = 60, autocast = true,
    school = "nature", castPoint = 0.3, icon = ICON .. "Spell_Nature_FaerieFire", tip = "An enemy loses 4 armour and can be seen for 90 seconds (60 on heroes). Right-click for autocast.",
    check = function(w, u, t) if S.hasBuff(t, "faerie") then return false, "Already has Faerie Fire." end return true end,
    cast = function(w, u, o, t, lv, durFor) S.buff(w, t, "faerie", durFor(t)) fx(w, t.x, t.y, 166492, 1.4, 1.0, t.id) end }
UA{ id = "crowForm", name = "Storm Crow Form", key = "C", target = "self", mana = 0, cd = 1, research = { "talonTraining", 1 }, precast = false, castPoint = 1.05,
    icon = ICON .. "Ability_Druid_TravelForm", tip = "Turns into a storm crow: it flies and can attack air units. Again to change back.",
    cast = function(w, u) morph(w, u, "druidTalonCrow") end }
UA{ id = "talonForm", name = "Night Elf Form", key = "C", target = "self", mana = 0, cd = 1, precast = false, castPoint = 0.6,
    icon = ICON .. "Spell_Nature_FaerieFire", tip = "Lands and changes back into a Night Elf.", cast = function(w, u) morph(w, u, u.def.formOf) end }
UA{ id = "cyclone", name = "Cyclone", key = "Y", target = "enemy", mana = 150, cd = 5, range = T(600), dur = 20, heroDur = 6, research = { "talonTraining", 2 },
    noMech = true, school = "nature", aiAuto = true, icon = ICON .. "Spell_Nature_Cyclone",
    tip = "Lifts an enemy into a cyclone for 20 seconds (6 on heroes): it can't act, and can't be hurt.",
    cast = function(w, u, o, t, lv, durFor)
        local d = durFor(t)
        S.buff(w, t, "cyclone", d)
        S.buff(w, t, "invuln", d)
        S.stunUnit(w, t, d)
        t.order = nil
        fx(w, t.x, t.y, 165976, 1.8, d, t.id)
    end }
UA{ id = "dryadAbolish", name = "Abolish Magic", key = "B", target = "unit", mana = 50, cd = 1, range = T(500), research = { "abolishUp", 1 }, autocast = true,
    school = "nature", castPoint = 0.2, icon = ICON .. "Spell_Nature_NullifyDisease",
    tip = "Removes enemy spells from a friend, or friendly spells from an enemy. Summoned units take 300 damage. Right-click for autocast.",
    cast = function(w, u, o, t)
        fx(w, t.x, t.y, 165955, 1.6, 1.0, t.id)
        if S.isEnemy(u, t) then
            if t.def.summon then S.damage(w, u, t, 300, "magic", true) return end
            for _, id in ipairs({ "innerFire", "bloodlust", "invis", "lightningShield", "haste", "frenzy", "roar", "ams", "frostArmor", "rejuv" }) do if t.buffs then t.buffs[id] = nil end end
        else
            for _, id in ipairs({ "slowSpell", "faerie", "curse", "purged", "ensnare", "rooted", "cripple", "plague", "entangled" }) do if t.buffs then t.buffs[id] = nil end end
        end
    end }
UA{ id = "pickUpArcher", name = "Pick up Archer", key = "A", target = "self", mana = 0, cd = 1, research = { "hippogryphTaming", 1 }, precast = false, castPoint = 0.3,
    icon = ICON .. "Ability_Mount_JungleTiger", tip = "Picks up the nearest Archer: together they become a Hippogryph Rider.",
    ready = function(w, u)
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and alive(e) and e.owner == u.owner and e.def.id == "archer" and dist(e.x, e.y, u.x, u.y) <= 4 then return true end
        end
        return false, "There is no Archer nearby."
    end,
    cast = function(w, u)
        local best, bd
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and alive(e) and e.owner == u.owner and e.def.id == "archer" then
                local d = dist(e.x, e.y, u.x, u.y)
                if d <= 4 and (not bd or d < bd) then best, bd = e, d end
            end
        end
        if not best then return end
        local frac = (u.hp / u.maxhp + best.hp / best.maxhp) / 2
        best.noCorpse = true
        S.kill(w, best, nil, true) best.removed = true
        morph(w, u, "hippogryphRider")
        u.hp = max(1, floor(u.maxhp * frac))
    end }
UA{ id = "dismount", name = "Dismount", key = "D", target = "self", mana = 0, cd = 1, precast = false, castPoint = 0.3,
    icon = ICON .. "Ability_Hunter_Pet_Owl", tip = "The Archer jumps off: an Archer and a Hippogryph again.",
    cast = function(w, u)
        local frac = u.hp / u.maxhp
        local a = S.addUnit(w, u.owner, "archer", u.x + 0.5, u.y + 0.3)
        a.hp = max(1, floor(a.maxhp * frac))
        morph(w, u, "hippogryph")
    end }
UA{ id = "taunt", name = "Taunt", key = "T", target = "none", mana = 0, cd = 15, precast = false, castPoint = 0.3, castAnim = "roar", aiAuto = true,
    icon = ICON .. "Ability_Warrior_Challange", tip = "Makes enemies nearby attack the Mountain Giant.",
    cast = function(w, u)
        for _, e in ipairs(enemies(w, u, u.x, u.y, T(450), false)) do
            if not e.def.hero and e.def.dmin and not e.def.worker then e.order = { type = "attack", target = u.id, auto = true, home = { e.x, e.y } } end
        end
        fx(w, u.x, u.y, 165726, 2.4, 1.0)
    end }
UA{ id = "phaseShift", name = "Phase Shift", key = "P", target = "self", mana = 20, cd = 6.5, autocast = true, precast = false, castPoint = 0,
    icon = ICON .. "Spell_Arcane_Blink", tip = "When hit, the Faerie Dragon shifts out of this world for a moment and can't be hurt (20 mana). Right-click for autocast.",
    cast = function(w, u) S.buff(w, u, "invuln", 1.5) S.buff(w, u, "phased", 1.5) end }

-- Sentinel (WC3 Aesn): the Huntress sends an owl to a tree within 800; it watches 900 around it
-- for as long as the tree stands.
UA{ id = "sentinel", name = "Sentinel", key = "N", target = "point", mana = 0, cd = 60, range = T(800), research = { "sentinelUp", 1 }, precast = false, castPoint = 0.2,
    icon = ICON .. "Ability_Hunter_Pet_Owl", tip = "Sends an owl to a tree: it can't be hurt and watches the area around the tree until the tree is cut down.",
    cast = function(w, u, o)
        local i = M.nearestTree(w, o.x, o.y, 2)
        if not i then
            u.abilityCd.sentinel = 0
            event(w, { t = "error", owner = u.owner, text = "Target a tree." })
            return
        end
        local tx, ty = (i - 1) % w.w + 1, floor((i - 1) / w.w) + 1
        local owl = S.addUnit(w, u.owner, "sentinelOwl", tx - 0.5, ty - 0.5)
        owl.sentinelTree = { tx, ty }
        S.buff(w, owl, "invuln", 1e9)
        fx(w, owl.x, owl.y, 166492, 1.2, 0.8)
        S.updateSupply(w)
    end }

-- War Club (WC3 Agra, Grab Tree): the Mountain Giant tears up a tree and swings it for 15 attacks,
-- with a longer reach and 2.5x damage against buildings.
UA{ id = "warClub", name = "War Club", key = "W", target = "point", mana = 0, cd = 5, range = 1.2, precast = false, castPoint = 0.5,
    icon = ICON .. "INV_Misc_Bone_01", tip = "Tears up a tree to use as a club: 15 attacks with longer reach that do 2.5 times the damage to buildings.",
    cast = function(w, u, o)
        local i = M.nearestTree(w, o.x, o.y, 2)
        if not i then u.abilityCd.warClub = 0 event(w, { t = "error", owner = u.owner, text = "Target a tree." }) return end
        local tx, ty = (i - 1) % w.w + 1, floor((i - 1) / w.w) + 1
        if dist(tx - 0.5, ty - 0.5, u.x, u.y) > 3 then u.abilityCd.warClub = 0 event(w, { t = "error", owner = u.owner, text = "Too far from the tree." }) return end
        M.removeTree(w, i)
        S.buff(w, u, "warClub", 1e9, { hits = 15 })
        fx(w, tx - 0.5, ty - 0.5, 166492, 1.6, 1.0)
    end }

-- Mana Flare (WC3 Amfl): the Faerie Dragon stops and channels for 30 seconds; every enemy that
-- casts a spell within 750 takes 3x the spell's mana cost (at most 90), heroes 1x (at most 50).
UA{ id = "manaFlare", name = "Mana Flare", key = "F", target = "none", mana = 50, cd = 20, dur = 30, precast = false, castPoint = 0.75, aiAuto = true,
    radius = T(750), unitMul = 3, heroMul = 1, unitMax = 90, heroMax = 50,
    icon = ICON .. "Spell_Nature_Lightning", tip = "The Faerie Dragon stops and channels for 30 seconds. Enemies casting spells within 750 take damage for the mana they spend. Any order ends it.",
    cast = function(w, u)
        u.channel = { ability = "manaFlare", t = 30 }
        S.buff(w, u, "manaFlare", 30)
    end,
    tick = function(w, u, dt, ch)
        ch.t = ch.t - dt
        u.anim = "cast"
        if ch.t <= 0 then if u.buffs then u.buffs.manaFlare = nil end return false end
    end }
local prevCastExtra = S.castExtra
function S.castExtra(w, c, abId, cost)
    if prevCastExtra then prevCastExtra(w, c, abId, cost) end
    if not alive(c) then return end
    local ab = D.Abilities.manaFlare
    for _, f in ipairs(w.list) do
        if f.channel and f.channel.ability == "manaFlare" and alive(f) and S.isEnemy(f, c) and not S.spellImmune(c)
           and dist(f.x, f.y, c.x, c.y) <= ab.radius then
            local d = c.def.hero and min(ab.heroMax, cost * ab.heroMul) or min(ab.unitMax, cost * ab.unitMul)
            fx(w, c.x, c.y, 165955, 1.4, 0.6, c.id)
            S.damage(w, f, c, d, "magic", true)
            if not alive(c) then return end
        end
    end
end

-- autocast and computer-player casting
local AUTO = S.AUTO
AUTO.manaFlare = function(w, u, ab)
    local n = 0
    for _, e in ipairs(enemies(w, u, u.x, u.y, T(750), true)) do
        if (e.maxMana or 0) > 0 then n = n + (e.def.hero and 3 or 1) end
    end
    if n >= 3 then return u end
end
AUTO.faerieFireDruid = function(w, u, ab)
    local best, bs
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.hidden and not e.def.ward and not S.hasBuff(e, "faerie") and not S.spellImmune(e)
           and S.targetable(w, u, e) and abs(e.x - u.x) <= ab.range + 1 and abs(e.y - u.y) <= ab.range + 1 and S.gap(u, e) <= ab.range then
            local s = (e.def.hero and 50 or 0) + (e.def.supply or 1) + (e.def.armor or 0)
            if not bs or s > bs then best, bs = e, s end
        end
    end
    return best
end
AUTO.dryadAbolish = function(w, u, ab)
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and not e.hidden and S.gap(u, e) <= ab.range then
            if S.isEnemy(u, e) and (e.def.summon and not e.def.hero or S.hasBuff(e, "bloodlust") or S.hasBuff(e, "innerFire") or S.hasBuff(e, "frenzy")) and not S.spellImmune(e) then return e end
            if not S.isEnemy(u, e) and (S.hasBuff(e, "slowSpell") or S.hasBuff(e, "curse") or S.hasBuff(e, "cripple") or S.hasBuff(e, "faerie")) then return e end
        end
    end
end
AUTO.roar = function(w, u, ab)
    local n = 0
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and e.owner == u.owner and e.def.dmin and not S.hasBuff(e, "roar") and (w.time - (e.hitT or -99)) < 3
           and dist(e.x, e.y, u.x, u.y) <= T(500) then n = n + 1 end
    end
    if n >= 3 then return u end
end
AUTO.rejuvenationDruid = function(w, u, ab)
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and e.owner == u.owner and not e.def.mech and not e.def.ward and e.maxhp - e.hp >= 250 and not S.hasBuff(e, "rejuv")
           and S.gap(u, e) <= ab.range then return e end
    end
end
AUTO.cyclone = function(w, u, ab)
    local best, bs
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and alive(e) and S.isEnemy(u, e) and not e.hidden and not e.def.mech and not S.hasBuff(e, "cyclone") and not S.spellImmune(e)
           and S.targetable(w, u, e) and S.gap(u, e) <= ab.range and (e.def.hero or (e.def.supply or 1) >= 4) then
            local s = (e.def.hero and 100 or 0) + (e.def.supply or 1)
            if not bs or s > bs then best, bs = e, s end
        end
    end
    return best
end
AUTO.taunt = function(w, u, ab)
    if u.hp > u.maxhp * 0.5 and #enemies(w, u, u.x, u.y, T(450), false) >= 3 then return u end
end

-- ------------------------------------------------------------------ hero abilities

local function durFor(ab, lv, e)
    local d = ab.dur and lvOf(ab.dur, lv)
    if e and e.def.hero and ab.heroDur then return lvOf(ab.heroDur, lv) end
    return d
end

-- Demon Hunter
A{ id = "manaBurn", name = "Mana Burn", key = "B", target = "enemy", mana = { 60, 60, 60 }, cd = { 7, 6, 5 }, range = T(300), burn = { 50, 100, 150 }, school = "shadow",
   icon = ICON .. "Spell_Shadow_ManaBurn", tip = "Burns up to %d mana from an enemy; it takes that much damage.",
   check = function(w, u, t) if (t.mana or 0) < 1 then return false, "That unit has no mana." end return true end,
   cast = function(w, u, o, t, lv)
       local n = min(t.mana or 0, lvOf(D.Abilities.manaBurn.burn, lv))
       t.mana = (t.mana or 0) - n
       S.event(w, { t = "vfx", kind = "bounce", x1 = u.x, y1 = u.y, x2 = t.x, y2 = t.y })
       S.damage(w, u, t, n, "magic", true)
   end,
   ai = function(w, h, en, ctx)
       local best
       for _, e in ipairs(en) do if (e.mana or 0) >= 60 and (not best or (e.def.hero and not best.def.hero) or e.mana > best.mana) then best = e end end
       if best then return { target = best.id } end
   end }
A{ id = "immolation", name = "Immolation", key = "I", target = "self", mana = { 25, 25, 25 }, cd = { 1, 1, 1 }, dmg = { 10, 15, 20 }, school = "fire",
   icon = ICON .. "Spell_Fire_Immolation", tip = "Flames burn enemies next to him for %d damage a second, using 7 mana a second. Again to put them out.",
   cast = function(w, u, o, t, lv)
       if S.hasBuff(u, "immolation") then u.buffs.immolation = nil return end
       S.buff(w, u, "immolation", 1e9, { dps = lvOf(D.Abilities.immolation.dmg, lv) })
   end,
   ai = function(w, h, en, ctx)
       local on = S.hasBuff(h, "immolation")
       local near = ctx.countNear(en, h.x, h.y, 2)
       if (not on and near >= 2 and h.mana > 60) or (on and near == 0) then return {} end
   end }
A{ id = "evasion", name = "Evasion", key = "E", target = "passive", evade = { 10, 20, 30 },
   icon = ICON .. "Spell_Shadow_ShadowWard", tip = "Dodges %d%% of attacks against him." }
A{ id = "metamorphosis", name = "Metamorphosis", key = "M", ult = true, target = "self", mana = { 150 }, cd = { 180 }, dur = { 60 }, school = "shadow",
   icon = ICON .. "Spell_Shadow_Metamorphosis", tip = "Becomes a demon for 60 seconds: 500 more hit points and a long-range chaos attack.",
   cast = function(w, u)
       S.buff(w, u, "meta", 60)
       u.hp = u.hp + 500
       fx(w, u.x, u.y, 166808, 3, 1.5, u.id)
   end,
   ai = function(w, h, en, ctx) if #en >= 4 then return {} end end }
-- Keeper of the Grove
A{ id = "entanglingRoots", name = "Entangling Roots", key = "E", target = "enemy", mana = { 75, 75, 75 }, cd = { 8, 8, 8 }, range = T(800), dps = { 15, 20, 30 },
   dur = { 9, 18, 30 }, heroDur = { 3, 5, 7 }, groundOnly = true, school = "nature", icon = ICON .. "Spell_Nature_StrangleVines",
   tip = "Roots burst out and hold an enemy in place, %d damage a second.",
   cast = function(w, u, o, t, lv)
       local d = durFor(D.Abilities.entanglingRoots, lv, t)
       S.buff(w, t, "entangled", d, { dps = lvOf(D.Abilities.entanglingRoots.dps, lv), src = u.id })
       S.buff(w, t, "rooted", d)
       t.swing = nil
       fx(w, t.x, t.y, 166492, 1.6, d, t.id)
   end,
   ai = function(w, h, en, ctx)
       local t = ctx.juiciest(en)
       if t and not t.def.air and not S.hasBuff(t, "entangled") then return { target = t.id } end
   end }
A{ id = "forceOfNature", name = "Force of Nature", key = "F", target = "point", mana = { 125, 125, 125 }, cd = { 20, 20, 20 }, range = T(800), count = { 2, 3, 4 },
   dur = { 60, 60, 60 }, school = "nature", icon = ICON .. "Ability_Druid_ForceofNature",
   tip = "Turns trees into %d Treants that fight for 60 seconds.",
   ready = function(w, u) if not M.nearestTree(w, u.x, u.y, 8) then return false, "There are no trees nearby." end return true end,
   cast = function(w, u, o, t, lv)
       local n = lvOf(D.Abilities.forceOfNature.count, lv)
       for i = 1, n do
           local tree = M.nearestTree(w, o.x or u.x, o.y or u.y, 8)
           if not tree then break end
           local x, y = (tree - 1) % w.w + 1, floor((tree - 1) / w.w) + 1
           M.removeTree(w, tree)
           event(w, { t = "treeFell", tree = tree })
           S.summonUnit(w, u.owner, "treant", x - 0.5, y - 0.5, 60)
       end
       S.updateSupply(w)
   end,
   ai = function(w, h, en, ctx)
       local tree = M.nearestTree(w, h.x, h.y, 7)
       if tree then
           local x, y = (tree - 1) % w.w + 1, floor((tree - 1) / w.w) + 1
           return { x = x - 0.5, y = y - 0.5 }
       end
   end }
A{ id = "thornsAura", name = "Thorns Aura", key = "T", target = "aura", radius = T(900), thorns = { 0.1, 0.2, 0.3 },
   icon = ICON .. "Spell_Nature_Thorns", tip = "Melee attackers of friendly units nearby take part of the damage they deal back." }
A{ id = "tranquility", name = "Tranquility", key = "R", ult = true, target = "none", mana = { 125 }, cd = { 60 }, dur = { 30 }, channel = true, school = "nature",
   icon = ICON .. "Spell_Nature_Tranquility", tip = "While the Keeper channels (up to 30 seconds), friendly units near him heal 40 hit points a second.",
   cast = function(w, u)
       u.channel = { ability = "tranquility", t = 30 }
       fx(w, u.x, u.y, 166492, T(900) * 1.2, 30, u.id)
   end,
   tick = function(w, u, dt, ch)
       ch.t = ch.t - dt
       if ch.t <= 0 then return false end
       for _, e in ipairs(w.list) do
           if e.kind == "unit" and alive(e) and e.owner == u.owner and not e.def.mech and abs(e.x - u.x) <= T(900) and abs(e.y - u.y) <= T(900)
              and dist(e.x, e.y, u.x, u.y) <= T(900) then e.hp = min(e.maxhp, e.hp + 40 * dt) end
       end
   end,
   ai = function(w, h, en, ctx)
       local hurt = 0
       for _, f in ipairs(ctx.friends) do if f.maxhp - f.hp > 200 then hurt = hurt + 1 end end
       if hurt >= 5 then return {} end
   end }
-- Priestess of the Moon
A{ id = "scout", name = "Scout", key = "C", target = "point", mana = { 50, 50, 50 }, cd = { 20, 20, 20 }, range = 99, dur = { 60, 90, 120 }, school = "nature",
   icon = ICON .. "Ability_Hunter_Pet_Owl", tip = "Sends out an owl that flies where you point, unseen, for %d seconds.",
   cast = function(w, u, o, t, lv)
       local owl = S.summonUnit(w, u.owner, "owl", u.x, u.y, lvOf(D.Abilities.scout.dur, lv))
       S.issue(w, owl, { type = "move", x = o.x, y = o.y })
       S.updateSupply(w)
   end }
A{ id = "searingArrows", name = "Searing Arrows", key = "R", target = "passive", autocast = true, mana = { 8, 8, 8 }, bonus = { 10, 20, 30 },
   icon = ICON .. "Spell_Fire_Flare", tip = "Her arrows deal %d extra fire damage (8 mana each). Right-click to switch on or off." }
A{ id = "trueshotAura", name = "Trueshot Aura", key = "T", target = "aura", radius = T(900), rangedBonus = { 0.1, 0.2, 0.3 },
   icon = ICON .. "Ability_TrueShot", tip = "Friendly ranged units nearby deal more damage." }
A{ id = "starfall", name = "Starfall", key = "F", ult = true, target = "none", mana = { 200 }, cd = { 180 }, dur = { 30 }, channel = true, school = "arcane",
   icon = ICON .. "Spell_Nature_StarFall", tip = "While she channels (up to 30 seconds), stars fall on enemies around her, 50 damage each wave.",
   cast = function(w, u) u.channel = { ability = "starfall", t = 30, acc = 0 } end,
   tick = function(w, u, dt, ch)
       ch.t = ch.t - dt
       if ch.t <= 0 then return false end
       ch.acc = ch.acc + dt
       if ch.acc < 1.5 then return end
       ch.acc = ch.acc - 1.5
       for _, e in ipairs(enemies(w, u, u.x, u.y, T(1000), true)) do
           if canHurt(e) then S.damage(w, u, e, 50, "magic", true) fx(w, e.x, e.y, 166526, 1.2, 0.8) end
       end
       for _, b in ipairs(w.list) do
           if b.kind == "building" and alive(b) and S.isEnemy(u, b) and S.edgeDist(u.x, u.y, b) <= T(1000) then S.damage(w, u, b, 50 * 0.35, "magic", true) end
       end
   end,
   ai = function(w, h, en, ctx) if #en >= 5 then return {} end end }
-- Warden
A{ id = "fanOfKnives", name = "Fan of Knives", key = "F", target = "none", mana = { 100, 100, 100 }, cd = { 9, 9, 9 }, dmg = { 75, 125, 190 },
   radiusL = { T(400), T(450), T(475) }, school = "shadow", icon = ICON .. "Ability_Rogue_FanofKnives",
   tip = "Throws knives all around her: %d damage to every enemy nearby.",
   cast = function(w, u, o, t, lv)
       local ab = D.Abilities.fanOfKnives
       local r = lvOf(ab.radiusL, lv)
       fx(w, u.x, u.y, 166808, r * 2.2, 1.0)
       for _, e in ipairs(enemies(w, u, u.x, u.y, r, true)) do if canHurt(e) then S.damage(w, u, e, lvOf(ab.dmg, lv), "magic", true) end end
   end,
   ai = function(w, h, en, ctx) if ctx.countNear(en, h.x, h.y, 3.3) >= 3 then return {} end end }
A{ id = "blink", name = "Blink", key = "B", target = "point", mana = { 50, 10, 10 }, cd = { 10, 7, 4 }, range = 99, reach = { T(1000), T(1075), T(1150) },
   school = "arcane", precast = false, castPoint = 0.1, icon = ICON .. "Spell_Arcane_Blink",
   tip = "Teleports a short distance in the direction you point.",
   cast = function(w, u, o, t, lv)
       local dx, dy = (o.x or u.x) - u.x, (o.y or u.y) - u.y
       local d = sqrt(dx * dx + dy * dy)
       local r = lvOf(D.Abilities.blink.reach, lv)
       if d > r then dx, dy = dx / d * r, dy / d * r end
       local tx, ty = M.tileOf(u.x + dx, u.y + dy)
       local nx, ny = M.nearestOpen(w, tx, ty, 4)
       if not nx then return end
       fx(w, u.x, u.y, 166526, 1.6, 0.6)
       u.x, u.y = nx - 0.5, ny - 0.5
       u.px, u.py, u.path = u.x, u.y, nil
       fx(w, u.x, u.y, 166526, 1.6, 0.6)
   end,
   ai = function(w, h, en, ctx)
       if h.hp < h.maxhp * 0.3 and ctx.fight then
           local home = w.players[h.owner].home
           if home then return { x = home[1], y = home[2] } end
       end
   end }
A{ id = "shadowStrike", name = "Shadow Strike", key = "S", target = "enemy", mana = { 75, 75, 75 }, cd = { 8, 8, 8 }, range = T(300), dmg = { 75, 150, 225 },
   dps = { 10, 30, 45 }, school = "shadow", icon = ICON .. "Spell_Shadow_ShadowWordPain",
   tip = "A poisoned dagger: %d damage, then more damage over 15 seconds while the target is slowed.",
   cast = function(w, u, o, t, lv)
       local ab = D.Abilities.shadowStrike
       S.damage(w, u, t, lvOf(ab.dmg, lv), "magic", true)
       if alive(t) then
           t.poisonT, t.poisonOwner, t.poisonDps = 15, u.id, lvOf(ab.dps, lv) / 3
           t.slow, t.slowFactor, t.slowAttack = 15, 0.5, 0.25
       end
       S.event(w, { t = "vfx", kind = "bounce", x1 = u.x, y1 = u.y, x2 = t.x, y2 = t.y })
   end,
   ai = function(w, h, en, ctx) local t = ctx.juiciest(en) if t then return { target = t.id } end end }
A{ id = "vengeance", name = "Spirit of Vengeance", key = "V", ult = true, target = "none", mana = { 150 }, cd = { 180 }, dur = { 180 }, school = "shadow",
   icon = ICON .. "Spell_Shadow_Twilight", tip = "Calls up an Avatar of Vengeance for 3 minutes; it raises Spirits of Vengeance from the dead.",
   cast = function(w, u)
       local a = S.summonUnit(w, u.owner, "avatarVengeance", u.x + 1, u.y, 180)
       a.raiseT = 2
       S.updateSupply(w)
   end,
   ai = function(w, h, en, ctx) if #en >= 4 then return {} end end }

-- ------------------------------------------------------------------ hooks into the combat code

local prevInvisible = S.isInvisible
function S.isInvisible(u)
    if u.kind == "unit" and u.buffs and u.buffs.meld then return true end
    return prevInvisible(u)
end

local prevSight = S.sightOf
function S.sightOf(w, e)
    if w.night and e.kind == "unit" and e.def.faction == "nightelf" and S.level(w, e.owner, "ultravision") > 0 then return e.def.sight or 6 end
    return prevSight(w, e)
end

local prevAttack = S.attackExtra
function S.attackExtra(u, m)
    m = prevAttack and prevAttack(u, m) or m
    local b = u.buffs
    if b and b.cyclone then m = 0 end
    return m
end

local prevMove = S.moveExtra
function S.moveExtra(u, m)
    m = prevMove and prevMove(u, m) or m
    local w = S.currentWorld
    if w and (u.def.speed or 0) > 0 and (u.def.id == "treant" or u.def.id == "druidClaw" or u.def.id == "druidClawBear") then
        local fl = S.bonus(w, u).flags
        if fl and fl.blessing then m = m + T(40) / u.def.speed end
    end
    return m
end

local prevRoll = S.rollExtra
function S.rollExtra(w, u, d)
    d = prevRoll and prevRoll(w, u, d) or d
    local b = u.buffs
    if b and b.roar and b.roar.t > 0 then d = d * 1.25 end
    local fl = S.bonus(w, u).flags
    if fl and fl.marksman then d = d + 3 end
    -- Trueshot Aura
    if u.aura and u.aura.rangedBonus and (u.def.range or 0) > 1.5 then d = d * (1 + u.aura.rangedBonus) end
    -- Metamorphosis: a long-range chaos attack
    return d
end

local prevMiss = S.missExtra
function S.missExtra(w, src, tgt)
    if prevMiss and prevMiss(w, src, tgt) then return true end
    local ev = tgt.skills and tgt.skills.evasion
    if ev and ev > 0 and w.rng.next() % 100 < lvOf(D.Abilities.evasion.evade, ev) then return true end
    return false
end

local prevOnHit = S.onHitExtra
function S.onHitExtra(w, src, tgt, d)
    d = prevOnHit and prevOnHit(w, src, tgt, d) or d
    local sk = src.skills
    if sk and (sk.searingArrows or 0) > 0 and S.autocastOn(src, "searingArrows") and (src.mana or 0) >= 8 then
        src.mana = src.mana - 8
        d = d + lvOf(D.Abilities.searingArrows.bonus, sk.searingArrows)
    end
    return d
end

local prevLandWC = S.landExtra
function S.landExtra(w, src, tgt, dmg, wp)
    if prevLandWC then prevLandWC(w, src, tgt, dmg, wp) end
    local wc = src and src.buffs and src.buffs.warClub
    if wc and wc.t > 0 and alive(src) then
        if tgt and tgt.kind == "building" and alive(tgt) then S.damage(w, src, tgt, dmg * 1.5, "siege") end
        wc.hits = wc.hits - 1
        if wc.hits <= 0 then src.buffs.warClub = nil end
    end
end
local prevLand = S.landExtra
function S.landExtra(w, src, tgt, dmg, wp)
    if prevLand then prevLand(w, src, tgt, dmg, wp) end
    if not src or src.kind ~= "unit" or not alive(tgt) then return end
    local def = src.def
    -- Huntress: the moon glaive bounces on to another enemy (two more with the upgrade)
    if def.bounce and tgt.kind == "unit" then
        local fl = S.bonus(w, src).flags
        local n = (fl and fl.glaive) and 2 or 1
        local from, hit, amt = tgt, { [tgt.id] = true }, dmg
        for _ = 1, n do
            amt = amt * 0.8
            local best, bd
            for _, e in ipairs(enemies(w, src, from.x, from.y, T(250), false)) do
                if not hit[e.id] then local dd = dist(e.x, e.y, from.x, from.y) if not bd or dd < bd then best, bd = e, dd end end
            end
            if not best then break end
            hit[best.id] = true
            S.event(w, { t = "vfx", kind = "bounce", x1 = from.x, y1 = from.y, x2 = best.x, y2 = best.y })
            S.damage(w, src, best, amt, wp and wp.atype or "normal")
            from = best
        end
    end
    -- Vorpal Blades: the glaive carries on through every enemy in a line behind the target
    if def.id == "glaiveThrower" and tgt.kind == "unit" then
        local fl = S.bonus(w, src).flags
        if fl and fl.vorpal then
            local dx, dy = tgt.x - src.x, tgt.y - src.y
            local d0 = max(0.01, sqrt(dx * dx + dy * dy))
            dx, dy = dx / d0, dy / d0
            for _, e in ipairs(enemies(w, src, tgt.x, tgt.y, T(300), false)) do
                if e ~= tgt then
                    local rx, ry = e.x - tgt.x, e.y - tgt.y
                    local along = rx * dx + ry * dy
                    if along > 0 and abs(rx * dy - ry * dx) <= T(60) + e.def.radius then S.damage(w, src, e, dmg * 0.75, "siege") end
                end
            end
        end
    end
    -- Dryad: Slow Poison
    if def.slowPoison and tgt.kind == "unit" and not tgt.def.mech and not S.spellImmune(tgt) then
        tgt.poisonT, tgt.poisonOwner, tgt.poisonDps = tgt.def.hero and 1 or 5, src.id, 4
        tgt.slow, tgt.slowFactor, tgt.slowAttack = tgt.def.hero and 1 or 5, 0.5, 0.25
    end
    -- Chimaera: Corrosive Breath eats buildings
    if def.id == "chimaera" and tgt.kind == "building" then
        local fl = S.bonus(w, src).flags
        if fl and fl.corrosive then S.damage(w, src, tgt, dmg * 0.5, "siege", true) end
    end
    -- Thorns Aura: melee attackers of a friend near the Keeper get hurt
    if tgt.kind == "unit" and tgt.aura and tgt.aura.thorns and (def.range or 0) < 1.5 and alive(src) then
        S.damage(w, tgt, src, dmg * tgt.aura.thorns, "normal", true)
    end
    -- Faerie Dragon: Phase Shift when hit
    if tgt.kind == "unit" and tgt.def.id == "faerieDragon" and alive(tgt) and S.autocastOn(tgt, "phaseShift") and S.canCast(w, tgt, "phaseShift") then
        S.doCast(w, tgt, { ability = "phaseShift", target = tgt.id })
    end
    -- Hardened Skin (Mountain Giant research): each blow 12 less, at least 3
    if tgt.kind == "unit" and tgt.def.id == "mountainGiant" and alive(tgt) then
        local fl = S.bonus(w, tgt).flags
        if fl and fl.hardenedSkin then tgt.hp = min(tgt.maxhp, tgt.hp + min(12, max(0, dmg - 3))) end
    end
end

-- per unit per tick: Immolation, Entangling Roots, Shadowmeld, the Avatar raising spirits
local prevStep = S.stepExtra
function S.stepExtra(w, u, dt)
    if prevStep and prevStep(w, u, dt) then return true end
    local b = u.buffs
    if b then
        local im = b.immolation
        if im then
            u.mana = (u.mana or 0) - 7 * dt
            if u.mana <= 0 then u.mana = 0 b.immolation = nil
            else
                im.acc = (im.acc or 0) + dt
                if im.acc >= 1 then
                    im.acc = im.acc - 1
                    for _, e in ipairs(enemies(w, u, u.x, u.y, T(160) + 0.3, false)) do if canHurt(e) and not e.def.mech then S.damage(w, u, e, im.dps, "magic", true) end end
                end
            end
        end
        local en = b.entangled
        if en then
            en.acc = (en.acc or 0) + en.dps * dt
            if en.acc >= 5 then
                local n = floor(en.acc)
                en.acc = en.acc - n
                S.damage(w, w.ents[en.src or 0], u, n, "magic", true)
                if not alive(u) then return true end
            end
        end
        if b.meld and (u.order or u.swing or not w.night) then b.meld = nil end
    end
    local def = u.def
    -- Shadowmeld: standing still at night for 1.5 seconds, they fade into the shadows
    if def.shadowmeld and w.night and not u.order and not u.swing then
        u.stillT = (u.stillT or 0) + dt
        if u.stillT >= 1.5 and not (b and b.meld) then S.buff(w, u, "meld", 1e9) end
    else
        u.stillT = 0
    end
    -- the Avatar of Vengeance raises a Spirit of Vengeance from a corpse every few seconds (6 at most)
    if def.id == "avatarVengeance" then
        u.raiseT = (u.raiseT or 2) - dt
        if u.raiseT <= 0 then
            u.raiseT = 4
            local n = 0
            for _, e in ipairs(w.list) do if e.kind == "unit" and alive(e) and e.spiritOf == u.id then n = n + 1 end end
            local c = S.corpsesNear and S.corpsesNear(w, u.x, u.y, T(900))[1]
            if n < 6 and c then
                S.takeCorpse(w, c)
                local s = S.summonUnit(w, u.owner, "spiritVengeance", c.x, c.y, 50)
                s.spiritOf = u.id
                S.buff(w, s, "invuln", 50)
                S.updateSupply(w)
            end
        end
    end
    return false
end

-- Metamorphosis: a longer reach while it lasts
local prevRange = S.rangeOf
function S.rangeOf(w, u, wp)
    local r = prevRange(w, u, wp)
    if u.buffs and u.buffs.meta and u.buffs.meta.t > 0 then return max(r, T(450)) end
    if u.buffs and u.buffs.warClub and u.buffs.warClub.t > 0 then return r + 0.6 end
    return r
end

-- Trueshot and Thorns auras ride on the hero aura code
local prevAuras = S.stepAuras
function S.stepAuras(w)
    prevAuras(w)
    for _, h in ipairs(w.list) do
        if h.kind == "unit" and h.def.hero and alive(h) and not h.illusion and h.skills then
            local ts, th = h.skills.trueshotAura or 0, h.skills.thornsAura or 0
            if ts > 0 or th > 0 then
                local r = T(900)
                for _, u in ipairs(w.list) do
                    if u.kind == "unit" and alive(u) and u.owner == h.owner and abs(u.x - h.x) <= r and abs(u.y - h.y) <= r and dist(u.x, u.y, h.x, h.y) <= r then
                        u.aura = u.aura or {}
                        if ts > 0 then u.aura.rangedBonus = max(u.aura.rangedBonus or 0, lvOf(D.Abilities.trueshotAura.rangedBonus, ts)) end
                        if th > 0 then u.aura.thorns = max(u.aura.thorns or 0, lvOf(D.Abilities.thornsAura.thorns, th)) end
                    end
                end
            end
        end
    end
end

-- ------------------------------------------------------------------ building a Night Elf building uses up the Wisp

function S.consumeBuilder(w, u, b)
    u.noCorpse = true
    u.order, u.queue = nil, nil
    S.kill(w, u, nil, true)
    u.removed = true
    S.updateSupply(w)
end

-- ------------------------------------------------------------------ Moon Wells

local prevWorld = S.stepUndead
function S.stepUndead(w, dt)
    if prevWorld then prevWorld(w, dt) end
    w.wellT = (w.wellT or 0) + dt
    if w.wellT < 0.5 then return end
    local step = w.wellT
    w.wellT = 0
    -- a Sentinel goes when its tree is cut down
    for _, e in ipairs(w.list) do
        if e.sentinelTree and alive(e) and not M.isTree(w, e.sentinelTree[1], e.sentinelTree[2]) then
            e.buffs.invuln = nil
            S.kill(w, e, nil, true)
        end
    end
    for _, b in ipairs(w.list) do
        if b.kind == "building" and alive(b) and b.built and b.def.moonWell then
            local spring = S.level(w, b.owner, "wellSpring") > 0
            local cap = b.def.wellMana + (spring and 125 or 0)
            b.wellMax = cap
            if b.wellMana == nil then b.wellMana = b.def.wellMana * 0.5 end
            -- refills 1.25 mana a second (WC3 emow), faster at night and with Well Spring
            b.wellMana = min(cap, b.wellMana + (1.25 + (w.night and 1.25 or 0)) * (spring and 1.5 or 1) * step)
            -- Replenish: up to 10 mana a second goes to the wounded and the drained nearby
            local budget = 10 * step
            for _, e in ipairs(w.list) do
                if budget <= 0 or b.wellMana < 1 then break end
                if e.kind == "unit" and alive(e) and e.owner == b.owner and not e.def.mech and dist(e.x, e.y, b.x, b.y) <= T(400) + 1 then
                    if e.hp < e.maxhp - 5 then
                        local use = min(budget, b.wellMana, (e.maxhp - e.hp) / 2)
                        e.hp = min(e.maxhp, e.hp + use * 2)
                        b.wellMana, budget = b.wellMana - use, budget - use
                    end
                    if (e.maxMana or 0) > 0 and (e.mana or 0) < e.maxMana - 3 and budget > 0 then
                        local use = min(budget, b.wellMana, e.maxMana - e.mana)
                        e.mana = e.mana + use
                        b.wellMana, budget = b.wellMana - use, budget - use
                    end
                end
            end
        end
    end
end

-- ------------------------------------------------------------------ the start of a game

-- Night Elves start with a Tree of Life with an Entangled Gold Mine, and 5 Wisps
function S.nightElfStart(w, p, hall, mine, autoGather)
    local em = S.addBuilding(w, p, "entangledMine", mine.tx, mine.ty, true)
    mine.haunted, em.mine = em.id, mine.id
    if autoGather ~= false then
        local n = 0
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and e.owner == p and e.def.id == "wisp" then
                n = n + 1
                if n > 4 then
                    local tree = M.nearestTree(w, hall.x, hall.y, 16)
                    if tree then S.issue(w, e, { type = "gather", res = "lumber", tree = tree }) end
                end
            end
        end
    end
end

-- ------------------------------------------------------------------ Ancients uproot and walk

-- WC3: the Trees and Ancients Uproot (2.5 s) and walk, with Heavy armour and a melee attack, and
-- Root (2.5 s) again where there is room; rooted they are Fortified buildings that can train.
-- Uprooted they can Eat Tree (500 hit points over 30 seconds). The Ancient Protector throws
-- boulders only while rooted and hits with its branches when it walks. Weapons from UnitWeapons.
local UPROOT = {
    treeOfLife = { 41, 50, 2.5 }, treeOfAges = { 49, 60, 2.5 }, treeOfEternity = { 60, 74, 2.5 },
    ancientWar = { 45, 55, 2.5 }, ancientLore = { 41, 50, 2.5 }, ancientWind = { 38, 46, 2.5 }, ancientProtector = { 26, 33, 1.5 },
    ancientWonders = { 21, 25, 2.5 },
}
for bid, a in pairs(UPROOT) do
    local b = D.Buildings[bid]
    local m = b.models[1]
    local id = bid .. "Walk"
    D.Units[id] = { id = id, kind = "unit", faction = "nightelf", name = b.name .. " (Uprooted)", role = "melee",
        hp = b.hp, armor = b.armor, dtype = "heavy", atype = "normal", base = a[1] - 1, dice = 1, sides = a[2] - a[1] + 1, dmin = a[1], dmax = a[2],
        cd = a[3], dmgpt = 0.4, range = 1, speed = T(150), acquire = T(500), sight = b.sight, nightSight = b.nightSight,
        gold = 0, lumber = 0, supply = 0, time = 0, level = 5, hitsGround = true, hitsBuildings = true, radius = 0.9, vis = 1.1,
        display = m.display and { m.display } or nil, modelFile = m.file, icon = b.icon, rootsTo = bid, ancient = true,
        spells = { "root", "eatTree" }, tip = "Uprooted: it walks and fights, and can Root again where there is room." }
    b.uproot = id
    if D.WC3SIZE then D.WC3SIZE[id] = D.WC3SIZE[bid] end
end

function S.canUproot(w, p, b)
    if not alive(b) or b.owner ~= p or b.kind ~= "building" or not b.def.uproot then return false end
    if not b.built then return false, "It isn't finished." end
    if b.uprootT then return false, "It is already uprooting." end
    if b.upgrading or (b.queue and #b.queue > 0) then return false, "Empty its queue first." end
    return true
end

function S.uproot(w, p, bId)
    local b = w.ents[bId]
    local ok, why = S.canUproot(w, p, b)
    if not ok then return false, why end
    b.uprootT = 2.5
    fx(w, b.x, b.y, 166492, b.size * 0.8, 2.5)
    return true
end

local function toUnit(w, b)
    local frac = b.hp / b.maxhp
    local u = S.addUnit(w, b.owner, b.def.uproot, b.x, b.y)
    u.hp = max(1, floor(u.maxhp * frac))
    u.facing = -pi / 2
    u.rally = b.rally
    M.setRect(w, b.tx, b.ty, b.size, nil)
    b.dead, b.removed, b.hp = true, true, 0
    event(w, { t = "morphed", from = b.id, to = u.id, owner = b.owner })
    S.updateSupply(w)
    return u
end

local function toBuilding(w, u, tx, ty)
    local bid = u.def.rootsTo
    local frac = u.hp / u.maxhp
    local b = S.addBuilding(w, u.owner, bid, tx, ty, true)
    b.hp = max(1, floor(b.maxhp * frac))
    b.rally = u.rally
    u.dead, u.removed, u.hp = true, true, 0
    u.order, u.channel = nil, nil
    event(w, { t = "morphed", from = u.id, to = b.id, owner = u.owner })
    S.updateSupply(w)
    return b
end
S.ancientToUnit, S.ancientToBuilding = toUnit, toBuilding

-- the top-left tile of a footprint centred on (x, y)
local function footAt(def, x, y)
    return floor(x - def.size / 2 + 0.5) + 1, floor(y - def.size / 2 + 0.5) + 1
end
S.ancientFoot = footAt

UA{ id = "root", name = "Root", key = "R", target = "point", mana = 0, cd = 1, range = 0.6, precast = false, castPoint = 0,
    icon = ICON .. "Ability_Druid_Ancient", tip = "Walks to the spot and roots there (2.5 seconds), becoming a building again. Needs open ground the size of the building.",
    cast = function(w, u, o)
        local def = D.Buildings[u.def.rootsTo]
        local tx, ty = footAt(def, o.x, o.y)
        if not M.canPlace(w, tx, ty, def.size) then
            -- it may be standing in the way of itself only; otherwise there's no room
            event(w, { t = "error", owner = u.owner, text = "Can't root there." })
            return
        end
        u.channel = { ability = "root", t = 2.5, tx = tx, ty = ty }
        fx(w, u.x, u.y, 166492, def.size * 0.8, 2.5)
    end,
    tick = function(w, u, dt, ch)
        ch.t = ch.t - dt
        u.anim = "stand"
        if ch.t <= 0 then
            local def = D.Buildings[u.def.rootsTo]
            if M.canPlace(w, ch.tx, ch.ty, def.size) then toBuilding(w, u, ch.tx, ch.ty)
            else event(w, { t = "error", owner = u.owner, text = "Can't root there." }) end
            return false
        end
    end }

UA{ id = "eatTree", name = "Eat Tree", key = "E", target = "point", mana = 0, cd = 1, range = 1.2, precast = false, castPoint = 0.5,
    icon = ICON .. "Spell_Nature_ResistNature", tip = "Eats a tree next to it and regains 500 hit points over 30 seconds.",
    cast = function(w, u, o)
        local i = M.nearestTree(w, o.x, o.y, 2)
        if not i then event(w, { t = "error", owner = u.owner, text = "Target a tree." }) return end
        local tx, ty = (i - 1) % w.w + 1, floor((i - 1) / w.w) + 1
        if dist(tx - 0.5, ty - 0.5, u.x, u.y) > 3 then event(w, { t = "error", owner = u.owner, text = "Too far from the tree." }) return end
        M.removeTree(w, i)
        S.buff(w, u, "eatTree", 30, { hps = 500 / 30 })
        fx(w, tx - 0.5, ty - 0.5, 166492, 1.6, 1.0)
    end }

-- uprooting buildings, and the Eat Tree heal
local prevWorld2 = S.stepUndead
function S.stepUndead(w, dt)
    if prevWorld2 then prevWorld2(w, dt) end
    for _, b in ipairs(w.list) do
        if b.uprootT and alive(b) then
            b.uprootT = b.uprootT - dt
            if b.uprootT <= 0 then b.uprootT = nil toUnit(w, b) end
        elseif b.kind == "unit" and b.buffs and b.buffs.eatTree and alive(b) then
            b.hp = min(b.maxhp, b.hp + (b.buffs.eatTree.hps or 0) * dt)
        end
    end
end
