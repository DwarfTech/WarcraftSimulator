-- Skirmish engine: the computer opponent. It thinks a few times a second and plays through the
-- same commands a player uses (S.command / S.build / S.train), so it can't do anything you can't.

local _, ns = ...
local E = ns.Engine
local D, M, S = E.Data, E.Map, E.Sim
local AI = {}
E.AI = AI

local abs = math.abs
local floor, abs, max, min, sqrt = math.floor, math.abs, math.max, math.min, math.sqrt

AI.LEVELS = {
    easy   = { tierTimes = { 520 }, research = false, lumber = 3, think = 1.4, workers = 9, wave = 16, waveGrow = 8, towers = 0, barracks = 1, mix = { 0.6, 0.4, 0.0 } },
    normal = { tierTimes = { 330, 700 }, research = true, lumber = 4, think = 0.7, workers = 11, wave = 12, waveGrow = 6, towers = 1, barracks = 2, mix = { 0.5, 0.35, 0.15 } },
    hard   = { tierTimes = { 270, 560 }, research = true, lumber = 5, think = 0.35, workers = 12, wave = 12, waveGrow = 6, towers = 1, barracks = 3, mix = { 0.45, 0.35, 0.2 } },
}

-- What each side builds, researches and trains, roughly in Warcraft III build order.
-- build entries: { building, how many, earliest time, tier = hall tier needed, gold = only when this rich }
AI.PLANS = {
    alliance = {
        build = { { "altarKings", 1 }, { "barracks", 1 }, { "blacksmith", 1, 100 }, { "lumberMill", 1, 140 },
                  { "scoutTower", 1, 200 }, { "arcaneSanctum", 1, 0, tier = 2 }, { "arcaneVault", 1, 0, tier = 2 }, { "workshop", 1, 0, tier = 2 },
                  { "barracks", 2, 300, gold = 400 }, { "gryphonAviary", 1, 0, tier = 3 } },
        research = { "defend", "swords", "gunpowder", "plating", "leather", "longRifles", "masonry", "animalWar",
                     "priestTraining", "sorceressTraining", "stormHammers", "fragShards", "lumberHarvest", "bombs", "barrage", "flak" },
        weights = { footman = 2, rifleman = 4, knight = 5, mortarTeam = 1.5, flyingMachine = 0.6, siegeEngine = 0.6, gryphonRider = 3,
                    priest = 2.5, sorceress = 2, spellBreaker = 1.5, dragonhawk = 1 },
        limit = { flyingMachine = 3, siegeEngine = 2, mortarTeam = 4, priest = 4, sorceress = 3, spellBreaker = 4, dragonhawk = 3 },
    },
    orcs = {
        build = { { "altarStorms", 1 }, { "orcBarracks", 1 }, { "warMill", 1, 100 }, { "watchTower", 1, 200 },
                  { "beastiary", 1, 0, tier = 2 }, { "spiritLodge", 1, 0, tier = 2 }, { "voodooLounge", 1, 0, tier = 2 }, { "orcBarracks", 2, 300, gold = 400 }, { "taurenTotem", 1, 0, tier = 3 } },
        research = { "orcMelee", "orcArmor", "orcRanged", "berserkerStr", "trollRegen", "pillage", "spikes", "berserkerUp",
                     "shamanTraining", "witchDoctorTraining", "pulverize", "ensnare", "spiritWalkerTraining", "envenomed", "warDrumsUp",
                     "burningOil", "liquidFire", "reinforced" },
        weights = { grunt = 5, headhunter = 3, berserker = 3, demolisher = 1, raider = 2.5, kodoBeast = 1, windRider = 2.5, batrider = 1, tauren = 5,
                    shaman = 1.5, witchDoctor = 1, spiritWalker = 1.5 },
        limit = { kodoBeast = 2, demolisher = 3, batrider = 4, shaman = 3, witchDoctor = 2, spiritWalker = 3 },
    },
    undead = {
        build = { { "altarDarkness", 1 }, { "crypt", 1 }, { "graveyard", 1, 90 },
                  { "temple", 1, 0, tier = 2 }, { "slaughterhouse", 1, 0, tier = 2 }, { "tombRelics", 1, 0, tier = 2 }, { "crypt", 2, 300, gold = 400 },
                  { "sacrificialPit", 1, 0, tier = 3 }, { "boneyard", 1, 0, tier = 3 } },
        research = { "unholyStrength", "creatureAttack", "unholyArmor", "creatureCarapace", "ghoulFrenzy", "webUp", "necroTraining", "cannibalizeUp",
                     "skeletalMastery", "bansheeTraining", "diseaseCloud", "skeletalLongevity", "destroyerForm", "freezingBreath", "exhume" },
        weights = { ghoul = 1.5, cryptFiend = 6, gargoyle = 1.5, necromancer = 2.5, banshee = 1, meatWagon = 1, abomination = 5, obsidianStatue = 1.2, frostWyrm = 3 },
        limit = { necromancer = 4, banshee = 2, meatWagon = 2, obsidianStatue = 2, gargoyle = 6, frostWyrm = 4 },
        lumberGhouls = { easy = 2, normal = 3, hard = 4 },
    },
    nightelf = {
        build = { { "altarElders", 1 }, { "ancientWar", 1 }, { "huntersHall", 1, 90 }, { "ancientProtector", 1, 200 },
                  { "ancientLore", 1, 0, tier = 2 }, { "ancientWind", 1, 0, tier = 2 }, { "ancientWonders", 1, 0, tier = 2 }, { "ancientWar", 2, 300, gold = 400 },
                  { "chimaeraRoost", 1, 0, tier = 3 } },
        research = { "strengthMoon", "moonArmor", "strengthWild", "reinforcedHides", "improvedBows", "clawTraining", "talonTraining", "abolishUp",
                     "moonGlaive", "marksmanship", "naturesBlessing", "hippogryphTaming", "vorpalBlades", "hardenedSkin", "ultravision", "wellSpring", "corrosiveBreath" },
        weights = { archer = 3, huntress = 6, glaiveThrower = 1, dryad = 3, druidClaw = 3, mountainGiant = 2, hippogryph = 1, druidTalon = 1.5,
                    faerieDragon = 1, chimaera = 3 },
        limit = { glaiveThrower = 3, druidTalon = 3, faerieDragon = 3, hippogryph = 4 },
    },
}

-- how each side likes to play: Humans hold with towers and tech up a little sooner
AI.STYLE = { alliance = { wave = 8, towers = 1, earlyTier = 60 }, undead = { wave = 6, earlyTier = 90 }, nightelf = { wave = 8 } }

function AI.new(w, p, level)
    local cfg = AI.LEVELS[level or "normal"] or AI.LEVELS.normal
    local ai = { p = p, cfg = cfg, t = 0, wave = cfg.wave, attacking = false, issueT = 0, level = level or "normal" }
    local style = AI.STYLE[w.players[p].faction]
    if style then ai.wave = ai.wave + (style.wave or 0) ai.style = style end
    w.players[p].ai = ai
    return ai
end

local function myStuff(w, p)
    local st = { units = {}, workers = {}, army = {}, buildings = {}, count = {}, armySupply = 0, pendingBuild = {}, halls = {} }
    for _, e in ipairs(w.list) do
        if e.owner == p and S.alive(e) then
            if e.kind == "unit" and e.def.ward then
                -- wards stay where they were planted
            elseif e.kind == "unit" and e.militia then
                -- Militia only defend the base, then go back to work
                st.units[#st.units + 1] = e
                st.militia = st.militia or {}
                st.militia[#st.militia + 1] = e
            elseif e.kind == "unit" then
                st.units[#st.units + 1] = e
                if e.aiLumber and e.def.gatherer then
                    st.lumberers = st.lumberers or {}
                    st.lumberers[#st.lumberers + 1] = e
                elseif e.def.worker then
                    st.workers[#st.workers + 1] = e
                    local o = e.order
                    if o and o.type == "build" then st.pendingBuild[o.bid] = (st.pendingBuild[o.bid] or 0) + 1 end
                else
                    st.army[#st.army + 1] = e
                    st.armySupply = st.armySupply + e.def.supply
                    if e.def.hero and not e.illusion then
                        st.heroes = st.heroes or {}
                        st.heroes[#st.heroes + 1] = e
                        st.hero = st.hero or e
                    end
                end
                st.count[e.def.id] = (st.count[e.def.id] or 0) + 1
            elseif e.kind == "building" then
                st.buildings[#st.buildings + 1] = e
                st.count[e.def.id] = (st.count[e.def.id] or 0) + 1
                if e.def.hall and e.built then
                    st.hall = st.hall or e
                    st.halls[#st.halls + 1] = e
                end
                if not e.built then st.pendingBuild[e.def.id] = (st.pendingBuild[e.def.id] or 0) + 1 end
                for _, q in ipairs(e.queue) do st.count[q] = (st.count[q] or 0) + 1 end
            end
        end
    end
    return st
end

local function have(st, id) return (st.count[id] or 0) + (st.pendingBuild[id] or 0) > 0 end
-- a tower upgraded to a Guard/Cannon/Arcane Tower still counts as the tower that was built
local TOWER_FAMILY = { scoutTower = { "guardTower", "cannonTower", "arcaneTower" } }
local function total(st, id)
    -- buildings counted once whether placed or still on the way to being placed
    local placed = st.count[id] or 0
    for _, up in ipairs(TOWER_FAMILY[id] or {}) do placed = placed + (st.count[up] or 0) end
    local walking = 0
    for _, u in ipairs(st.workers) do if u.order and u.order.type == "build" and u.order.bid == id then walking = walking + 1 end end
    return placed + walking
end

-- a building spot near home that doesn't block the path between the hall and its mine
local function findSpot(w, ai, st, size, nearX, nearY, mine, bid)
    local needBlight = bid and D.Buildings[bid].needsBlight
    local hall = st.hall
    local cx, cy = floor(nearX or hall.x), floor(nearY or hall.y)
    for r = 3, 14 do
        local tries = {}
        for y = cy - r, cy + r do
            for x = cx - r, cx + r do
                if abs(x - cx) == r or abs(y - cy) == r then tries[#tries + 1] = { x, y } end
            end
        end
        -- a little shuffle so bases don't grow in a straight line
        for i = #tries, 2, -1 do
            local j = w.rng.next() % i + 1
            tries[i], tries[j] = tries[j], tries[i]
        end
        for _, t in ipairs(tries) do
            local x, y = t[1], t[2]
            if M.canPlace(w, x - 1, y - 1, size + 2) and (not needBlight or S.blighted(w, x, y, size)) then
                local bx, by = x - 1 + size / 2, y - 1 + size / 2
                local ok = true
                if mine and hall then
                    -- distance from the building centre to the hall-mine line
                    local ax, ay, qx, qy = hall.x, hall.y, mine.x, mine.y
                    local dx, dy = qx - ax, qy - ay
                    local len2 = dx * dx + dy * dy
                    local tt = max(0, min(1, ((bx - ax) * dx + (by - ay) * dy) / len2))
                    local px, py = ax + dx * tt, ay + dy * tt
                    if (bx - px) ^ 2 + (by - py) ^ 2 < (size / 2 + 2.5) ^ 2 then ok = false end
                end
                if ok then return x, y end
            end
        end
    end
end

local function pickBuilder(w, st)
    local best
    for _, u in ipairs(st.workers) do
        local o = u.order
        if not o then return u end
        if o.type == "gather" and o.res == "lumber" and o.state ~= "return" then best = best or u end
    end
    if best then return best end
    for _, u in ipairs(st.workers) do
        local o = u.order
        if o and o.type == "gather" and o.state ~= "inMine" and not u.carry then return u end
    end
end

local function tryBuild(w, ai, st, id, nx, ny)
    local def = D.Buildings[id]
    if not S.canAfford(w, ai.p, def) then return false end
    if not S.requirementMet(w, ai.p, id) then return false end
    local u = pickBuilder(w, st)
    if not u then return false end
    local mine = S.nearestMine(w, nx or st.hall.x, ny or st.hall.y, 14)
    local x, y = findSpot(w, ai, st, def.size, nx, ny, not nx and mine or nil, id)
    if not x then return false end
    local resume = u.order and u.order.type == "gather" and { type = "gather", res = u.order.res, mine = u.order.mine, tree = u.order.tree } or nil
    local ok = S.build(w, ai.p, u.id, id, x, y)
    if ok and u.order then u.order.after = resume end
    return ok
end

local function armyCentre(army)
    local x, y, n = 0, 0, 0
    for _, u in ipairs(army) do x, y, n = x + u.x, y + u.y, n + 1 end
    if n == 0 then return nil end
    return x / n, y / n
end

local function nearestEnemyThing(w, p, x, y, unitsOnly)
    local best, bd
    for _, e in ipairs(w.list) do
        if S.alive(e) and e.owner ~= p and e.owner >= 1 and e.owner <= 2 and not e.hidden and (e.kind == "building" or (not unitsOnly and e.kind == "unit")) then
            local d = S.dist(x, y, e.x, e.y)
            if not bd or d < bd then best, bd = e, d end
        end
    end
    return best, bd
end


-- fighting strength (supply weighted by health) of each side around a point; towers count too
function AI.strength(w, p, x, y, r, creeps)
    local ours, theirs = 0, 0
    for _, e in ipairs(w.list) do
        if S.alive(e) and abs(e.x - x) < r and abs(e.y - y) < r and e.owner >= 1 and e.owner <= 3 then
            local v = 0
            if e.kind == "unit" and not e.def.worker and e.def.dmin then
                v = (e.def.supply or 1) * (0.4 + 0.6 * e.hp / e.maxhp)
                if e.def.hero then v = v + (e.level or 1) end
            elseif e.kind == "building" and e.def.attack and e.built and not e.def.noAttackWhenEmpty
                   and not (e.def.garrisonMax and #(e.garrison or {}) == 0) then
                v = 4
            end
            if e.owner == p then ours = ours + v elseif e.owner ~= 3 or creeps then theirs = theirs + v end
        end
    end
    return ours, theirs
end

-- what to attack: the nearest enemy building or unit the AI has seen. It remembers buildings it
-- has spotted (fog of war applies to the computer too); with nothing known it heads for the
-- enemy's start.
function AI.target(w, ai, x, y)
    local p = ai.p
    ai.seen = ai.seen or {}
    local best, bd
    for _, e in ipairs(w.list) do
        if S.alive(e) and e.owner ~= p and e.owner >= 1 and e.owner <= 2 and not e.hidden then
            local vis = w.noFog or S.visibleTo(w, p, e)
            if vis and e.kind == "building" then ai.seen[e.id] = true end
            if (e.kind == "building" and ai.seen[e.id]) or (e.kind == "unit" and vis) then
                local d = S.dist(x, y, e.x, e.y)
                if not bd or d < bd then best, bd = e, d end
            end
        end
    end
    if best then return best end
    local other = w.starts and w.starts[p == 1 and 2 or 1]
    if other then
        local hx, hy = other.hall[1] + 1, other.hall[2] + 1
        -- arrived and found nothing there: fall back to anything at all
        if S.dist(x, y, hx, hy) < 6 then return nearestEnemyThing(w, p, x, y) end
        return { x = hx, y = hy }
    end
    return nearestEnemyThing(w, p, x, y)
end

-- ---------------------------------------------------------- heroes
-- which heroes the computer picks (first, second, third) and the order it learns skills,
-- following common WC3 builds
AI.HEROES = {
    alliance = { { "archmage", "mountainKing", "paladin" }, { "mountainKing", "archmage", "paladin" }, { "paladin", "archmage", "mountainKing" } },
    orcs = { { "farSeer", "taurenChieftain", "shadowHunter" }, { "blademaster", "farSeer", "taurenChieftain" }, { "taurenChieftain", "farSeer", "shadowHunter" } },
    nightelf = { { "demonHunter", "keeper", "priestess" }, { "keeper", "demonHunter", "warden" }, { "priestess", "keeper", "demonHunter" } },
    undead = { { "deathKnight", "lich", "dreadlord" }, { "deathKnight", "cryptLord", "lich" }, { "dreadlord", "lich", "deathKnight" } },
}
AI.SKILLS = {
    paladin = { "holyLight", "devotionAura", "holyLight", "divineShield", "holyLight", "resurrection", "devotionAura", "devotionAura", "divineShield", "divineShield" },
    archmage = { "waterElemental", "brillianceAura", "waterElemental", "brillianceAura", "waterElemental", "massTeleport", "brillianceAura", "blizzard", "blizzard", "blizzard" },
    mountainKing = { "stormBolt", "thunderClap", "stormBolt", "thunderClap", "stormBolt", "avatar", "thunderClap", "bash", "bash", "bash" },
    bloodMage = { "flameStrike", "banish", "flameStrike", "siphonMana", "flameStrike", "phoenix", "siphonMana", "siphonMana", "banish", "banish" },
    blademaster = { "windWalk", "criticalStrike", "windWalk", "criticalStrike", "criticalStrike", "bladestorm", "windWalk", "mirrorImage", "mirrorImage", "mirrorImage" },
    farSeer = { "feralSpirit", "chainLightning", "feralSpirit", "chainLightning", "feralSpirit", "earthquake", "chainLightning", "farSight", "farSight", "farSight" },
    taurenChieftain = { "warStomp", "enduranceAura", "warStomp", "enduranceAura", "shockwave", "reincarnation", "warStomp", "enduranceAura", "shockwave", "shockwave" },
    shadowHunter = { "healingWave", "serpentWard", "healingWave", "hex", "healingWave", "bigBadVoodoo", "serpentWard", "serpentWard", "hex", "hex" },
    darkRanger = { "blackArrow", "silence", "blackArrow", "lifeDrain", "blackArrow", "charm", "silence", "silence", "lifeDrain", "lifeDrain" },
    beastmaster = { "summonBear", "summonQuilbeast", "summonBear", "summonHawk", "summonBear", "stampede", "summonQuilbeast", "summonQuilbeast", "summonHawk", "summonHawk" },
    brewmaster = { "drunkenHaze", "breathOfFire", "drunkenBrawler", "breathOfFire", "breathOfFire", "stormEarthFire", "drunkenBrawler", "drunkenBrawler", "drunkenHaze", "drunkenHaze" },
    seaWitch = { "forkedLightning", "frostArrows", "forkedLightning", "manaShield", "forkedLightning", "tornado", "frostArrows", "frostArrows", "manaShield", "manaShield" },
    pitLord = { "rainOfFire", "cleavingAttack", "rainOfFire", "howlOfTerror", "rainOfFire", "doom", "cleavingAttack", "cleavingAttack", "howlOfTerror", "howlOfTerror" },
    tinker = { "pocketFactory", "clusterRockets", "pocketFactory", "engineeringUpgrade", "pocketFactory", "roboGoblin", "engineeringUpgrade", "engineeringUpgrade", "clusterRockets", "clusterRockets" },
    alchemist = { "healingSpray", "acidBomb", "healingSpray", "chemicalRage", "healingSpray", "transmute", "chemicalRage", "chemicalRage", "acidBomb", "acidBomb" },
    demonHunter = { "manaBurn", "immolation", "evasion", "manaBurn", "evasion", "metamorphosis", "evasion", "immolation", "manaBurn", "immolation" },
    keeper = { "entanglingRoots", "forceOfNature", "thornsAura", "entanglingRoots", "forceOfNature", "tranquility", "entanglingRoots", "forceOfNature", "thornsAura", "thornsAura" },
    priestess = { "searingArrows", "trueshotAura", "searingArrows", "trueshotAura", "searingArrows", "starfall", "trueshotAura", "scout", "scout", "scout" },
    warden = { "fanOfKnives", "shadowStrike", "blink", "fanOfKnives", "fanOfKnives", "vengeance", "blink", "shadowStrike", "shadowStrike", "blink" },
    deathKnight = { "deathCoil", "unholyAura", "deathCoil", "unholyAura", "deathCoil", "animateDead", "unholyAura", "deathPact", "deathPact", "deathPact" },
    lich = { "frostNova", "frostArmor", "frostNova", "darkRitual", "frostNova", "deathAndDecay", "frostArmor", "frostArmor", "darkRitual", "darkRitual" },
    dreadlord = { "carrionSwarm", "vampiricAura", "dreadSleep", "carrionSwarm", "carrionSwarm", "inferno", "vampiricAura", "vampiricAura", "dreadSleep", "dreadSleep" },
    cryptLord = { "impale", "spikedCarapace", "impale", "carrionScarabs", "impale", "locustSwarm", "carrionScarabs", "carrionScarabs", "spikedCarapace", "spikedCarapace" },
    firelord = { "lavaSpawn", "soulBurn", "lavaSpawn", "incinerate", "lavaSpawn", "volcano", "soulBurn", "soulBurn", "incinerate", "incinerate" },
}

local function learnSkills(w, h)
    local list = AI.SKILLS[h.def.id] or {}
    local guard = 0
    while (h.points or 0) > 0 and guard < 12 do
        guard = guard + 1
        local done = false
        local spent = 0
        for _, v in pairs(h.skills) do spent = spent + v end
        local nextAb = list[spent + 1]
        if nextAb and S.canLearn(h, nextAb) then S.learn(w, h, nextAb) done = true end
        if not done then
            for _, ab in ipairs(list) do
                if S.canLearn(h, ab) then S.learn(w, h, ab) done = true break end
            end
        end
        if not done then
            for _, ab in ipairs(h.def.abilities) do if S.canLearn(h, ab) then S.learn(w, h, ab) done = true break end end
        end
        if not done then break end
    end
end

-- enemies (and wounded friends) around a hero, sized up once a think
local function around(w, h, r)
    local en, fr = {}, {}
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and S.alive(e) and not e.hidden and abs(e.x - h.x) < r and abs(e.y - h.y) < r then
            if S.isEnemy(h, e) then
                if S.targetable(w, h, e) or S.hasBuff(e, "ethereal") then en[#en + 1] = e end
            elseif e.owner == h.owner then fr[#fr + 1] = e end
        end
    end
    return en, fr
end

local function countNear(list, x, y, r)
    local n = 0
    for _, e in ipairs(list) do if S.dist(e.x, e.y, x, y) <= r then n = n + 1 end end
    return n
end

-- the densest spot among enemies (for area spells)
local function bestCluster(list, r)
    local best, bn
    for _, e in ipairs(list) do
        local n = countNear(list, e.x, e.y, r)
        if not bn or n > bn then best, bn = e, n end
    end
    return best, bn or 0
end

local function juiciest(list, wantMana)
    local best, bs
    for _, e in ipairs(list) do
        if not S.spellImmune(e) and (not wantMana or (e.mana or 0) > 40) then
            local s = (e.def.hero and 1000 or 0) + (e.def.supply or 1) * 50 + e.hp * 0.1 - (e.def.worker and 300 or 0)
            if not bs or s > bs then best, bs = e, s end
        end
    end
    return best
end

local function cast(w, ai, h, ab, t)
    t.type, t.ability = "cast", ab
    return S.command(w, ai.p, { h.id }, t)
end

local function heroSpells(w, ai, st, h)
    if not h or (h.stun or 0) > 0 or h.channel or (h.order and h.order.type == "cast") or h.hidden then return end
    local en, fr = around(w, h, 9)
    if h.def.tavern or h.def.faction == "undead" or h.def.faction == "nightelf" then
        -- neutral heroes: each ability knows when it's worth casting
        local closest, cdist
        for _, e in ipairs(en) do local d = S.dist(e.x, e.y, h.x, h.y) if not cdist or d < cdist then closest, cdist = e, d end end
        local ctx = { fight = #en > 0, friends = fr, closest = closest, cd = cdist, cluster = bestCluster, juiciest = juiciest, countNear = countNear }
        for _, abId in ipairs(h.def.abilities) do
            local ab = D.Abilities[abId]
            if ab.ai and S.skillLevel(h, abId) > 0 and S.canCast(w, h, abId) and (ctx.fight or abId == "summonHawk") then
                local t = ab.ai(w, h, en, ctx)
                if t then return cast(w, ai, h, abId, t) end
            end
        end
        return
    end
    local function ready(ab) return S.skillLevel(h, ab) > 0 and S.canCast(w, h, ab) end
    local function lv(ab) return S.skillLevel(h, ab) end
    local fight = #en > 0
    local hurt = h.hp < h.maxhp * 0.35
    -- saving ourselves
    if hurt and fight and ready("divineShield") then return cast(w, ai, h, "divineShield", {}) end
    if hurt and fight and ready("windWalk") then return cast(w, ai, h, "windWalk", {}) end
    -- heals
    if ready("holyLight") then
        for _, f in ipairs(fr) do
            if f ~= h and f.maxhp - f.hp >= 150 * lv("holyLight") and not f.def.summon and S.dist(f.x, f.y, h.x, h.y) < 7 then return cast(w, ai, h, "holyLight", { target = f.id }) end
        end
    end
    if ready("healingWave") then
        local wounded, first = 0, nil
        for _, f in ipairs(fr) do if f.maxhp - f.hp >= 100 then wounded = wounded + 1 first = first or f end end
        if wounded >= 2 then return cast(w, ai, h, "healingWave", { target = first.id }) end
    end
    if ready("resurrection") then
        local n = 0
        for _, c in ipairs(w.corpses or {}) do if c.owner == h.owner and S.dist(c.x, c.y, h.x, h.y) < 7 and w.time - c.t < 60 then n = n + 1 end end
        if n >= 4 then return cast(w, ai, h, "resurrection", {}) end
    end
    if not fight then
        -- summons and auras: nothing to do out of combat
        return
    end
    local closest, cd
    for _, e in ipairs(en) do local d = S.dist(e.x, e.y, h.x, h.y) if not cd or d < cd then closest, cd = e, d end end
    -- ultimates
    if ready("avatar") and countNear(en, h.x, h.y, 5) >= 4 then return cast(w, ai, h, "avatar", {}) end
    if ready("bladestorm") and countNear(en, h.x, h.y, 2.2) >= 3 then return cast(w, ai, h, "bladestorm", {}) end
    if ready("bigBadVoodoo") and #fr >= 6 and #en >= 5 then return cast(w, ai, h, "bigBadVoodoo", {}) end
    if ready("phoenix") and #en >= 3 then return cast(w, ai, h, "phoenix", {}) end
    if ready("earthquake") then
        local bc, bn
        for _, b in ipairs(w.list) do
            if b.kind == "building" and S.alive(b) and S.isEnemy(h, b) and S.dist(b.x, b.y, h.x, h.y) < 8 then
                local n = 0
                for _, o in ipairs(w.list) do if o.kind == "building" and S.alive(o) and o.owner == b.owner and S.dist(o.x, o.y, b.x, b.y) < 3 then n = n + 1 end end
                if not bn or n > bn then bc, bn = b, n end
            end
        end
        if bc and bn >= 2 then return cast(w, ai, h, "earthquake", { x = bc.x, y = bc.y }) end
    end
    -- summons as soon as a fight starts
    if ready("waterElemental") then return cast(w, ai, h, "waterElemental", {}) end
    if ready("feralSpirit") then return cast(w, ai, h, "feralSpirit", {}) end
    if ready("serpentWard") and closest and cd < 6 then
        return cast(w, ai, h, "serpentWard", { x = (h.x + closest.x) / 2, y = (h.y + closest.y) / 2 })
    end
    if ready("mirrorImage") and #en >= 3 and h.mana >= 150 then return cast(w, ai, h, "mirrorImage", {}) end
    -- stomps
    for _, ab in ipairs({ "warStomp", "thunderClap" }) do
        if ready(ab) and countNear(en, h.x, h.y, D.Abilities[ab].radiusL[lv(ab)] * 0.9) >= 2 then return cast(w, ai, h, ab, {}) end
    end
    -- area nukes on clumps
    for _, ab in ipairs({ "blizzard", "flameStrike" }) do
        if ready(ab) then
            local c, n = bestCluster(en, 1.6)
            if c and n >= 3 then return cast(w, ai, h, ab, { x = c.x, y = c.y }) end
        end
    end
    if ready("shockwave") and closest and countNear(en, closest.x, closest.y, 2.5) >= 2 then
        return cast(w, ai, h, "shockwave", { x = closest.x, y = closest.y })
    end
    if ready("chainLightning") and #en >= 2 then
        local t = juiciest(en) if t then return cast(w, ai, h, "chainLightning", { target = t.id }) end
    end
    -- single targets: save some mana for the bigger spells
    if ready("stormBolt") then
        local t = juiciest(en)
        if t and (t.def.hero or h.mana > 150) then return cast(w, ai, h, "stormBolt", { target = t.id }) end
    end
    if ready("hex") then
        local t = juiciest(en)
        if t and (t.def.hero or (t.def.supply or 1) >= 3) then return cast(w, ai, h, "hex", { target = t.id }) end
    end
    if ready("siphonMana") and h.mana < h.maxMana * 0.5 then
        local t = juiciest(en, true)
        if t then return cast(w, ai, h, "siphonMana", { target = t.id }) end
    end
end

-- spells of ordinary units that don't autocast (Heal, Slow, Inner Fire and Bloodlust look after themselves)
local function unitSpells(w, ai, st)
    for _, u in ipairs(st.army) do
        local spells = u.def.spells
        if spells and not u.def.hero and not (u.order and u.order.type == "cast") and (u.stun or 0) <= 0 then
            local function ready(ab) return S.skillLevel(u, ab) > 0 and S.canCast(w, u, ab) end
            local en, fr = around(w, u, 8)
            local done = false
            local function go(ab, t) if not done then done = cast(w, ai, u, ab, t) and true or false end end
            if #en > 0 then
                local closest, cd
                for _, e in ipairs(en) do local d = S.dist(e.x, e.y, u.x, u.y) if not cd or d < cd then closest, cd = e, d end end
                -- enemy summons and wards: dispel them
                for _, ab in ipairs({ "dispelMagic", "disenchant" }) do
                    if ready(ab) then
                        for _, e in ipairs(en) do
                            if e.def.summon and countNear(en, e.x, e.y, 1.6) >= 1 and not e.def.ward or (e.def.summon and e.hp > 150) then go(ab, { x = e.x, y = e.y }) break end
                        end
                    end
                end
                if ready("purge") then
                    for _, e in ipairs(en) do
                        if e.def.summon and not e.def.ward or S.hasBuff(e, "bloodlust") or S.hasBuff(e, "innerFire") or (e.def.hero and not S.hasBuff(e, "purged")) then
                            go("purge", { target = e.id }) break
                        end
                    end
                end
                if ready("polymorph") then
                    local t = juiciest(en)
                    if t and not t.def.hero and not t.def.summon and (t.def.supply or 1) >= 3 then go("polymorph", { target = t.id }) end
                end
                if ready("lightningShield") then
                    local c, n = bestCluster(en, 1.3)
                    if c and n >= 3 and not S.hasBuff(c, "lightningShield") then go("lightningShield", { target = c.id }) end
                end
                if ready("ensnare") then
                    for _, e in ipairs(en) do
                        if (e.def.air or (e.def.hero and e.hp < e.maxhp * 0.4)) and not S.hasBuff(e, "ensnare") and S.dist(e.x, e.y, u.x, u.y) < 5 then go("ensnare", { target = e.id }) break end
                    end
                end
                if ready("devour") and closest and not closest.def.hero and not closest.def.air and not closest.def.ward and (closest.def.level or 1) <= 4 and cd < 3 then
                    go("devour", { target = closest.id })
                end
                if ready("unstableConcoction") then
                    for _, e in ipairs(en) do if e.def.air and e.hp >= 250 then go("unstableConcoction", { target = e.id }) break end end
                end
                if ready("berserk") and closest and cd < 4 and u.hp > u.maxhp * 0.5 then go("berserk", {}) end
                if ready("stasisTrap") and closest and cd < 6 then go("stasisTrap", { x = (u.x + closest.x) / 2, y = (u.y + closest.y) / 2 }) end
                if ready("spiritLink") and not S.hasBuff(u, "link") and #fr >= 3 then go("spiritLink", { target = u.id }) end
                if ready("sentryWard") and not ai.wardT or (ai.wardT and w.time - ai.wardT > 90 and ready("sentryWard")) then
                    ai.wardT = w.time
                    go("sentryWard", { x = u.x, y = u.y })
                end
            end
            if ready("healingWard") then
                local hurt = 0
                for _, f in ipairs(fr) do if f.maxhp - f.hp > 120 and S.dist(f.x, f.y, u.x, u.y) < 3 then hurt = hurt + 1 end end
                if hurt >= 3 then go("healingWard", { x = u.x, y = u.y }) end
            end
            if ready("ancestralSpirit") then go("ancestralSpirit", {}) end
            -- Spirit Walkers turn ethereal when badly hurt, and back when safe
            if ready("etherealForm") then
                local eth = u.buffs and u.buffs.ethereal and u.buffs.ethereal.form
                if not eth and u.hp < u.maxhp * 0.35 and #en > 0 then go("etherealForm", {})
                elseif eth and (#en == 0 or u.hp > u.maxhp * 0.7) then go("etherealForm", {}) end
            end
        end
    end
end


-- ---------------------------------------------------------- looking after the base
-- Scout Towers become Guard Towers, a new expansion gets a tower, workers repair damaged
-- buildings, and a worker runs over early on to scout the enemy base.
function AI.upkeepBase(w, ai, st, hall, F, reserve)
    local p = ai.p
    local pl = w.players[p]
    -- a building left half-built (its builder was killed or pulled away): send someone to finish it
    for _, b in ipairs(st.buildings) do
        if not b.built and not b.upgrading and not b.selfBuild then
            local on = false
            for _, u in ipairs(st.workers) do
                local o = u.order
                if o and ((o.type == "construct" and o.b == b.id) or (o.type == "build" and o.placed == b.id)) then on = true break end
            end
            if not on and (w.time - (b.leftT or w.time)) > 4 then
                local u = pickBuilder(w, st)
                if u and not u.militia then S.issue(w, u, { type = "construct", b = b.id }) end
            end
            b.leftT = on and w.time or (b.leftT or w.time)
        end
    end
    -- Scout Tower -> Guard Tower (the Scout Tower itself can't shoot)
    if pl.faction == "alliance" then
        for _, b in ipairs(st.buildings) do
            if b.def.id == "scoutTower" and b.built and not b.upgrading and S.requirementMet(w, p, "guardTower") then
                local g, l = S.upgradeCost(b, "guardTower")
                if pl.gold >= g + reserve and pl.lumber >= l then S.upgradeBuilding(w, p, b.id, "guardTower") end
                break
            end
        end
    end
    -- a tower by each expansion
    for i = 2, #st.halls do
        local h2 = st.halls[i]
        local has = false
        for _, b in ipairs(st.buildings) do
            if (b.def.attack or b.def.id == F.tower or (D.Counts[F.tower] and b.def.id == D.Counts[F.tower][1])) and S.dist(b.x, b.y, h2.x, h2.y) < 8 then has = true break end
        end
        for _, u in ipairs(st.workers) do if u.order and u.order.type == "build" and u.order.bid == F.tower then has = true end end
        if not has and pl.gold > reserve + 200 then
            local saved = st.hall
            st.hall = h2
            tryBuild(w, ai, st, F.tower, h2.x + 2, h2.y + 2)
            st.hall = saved
            break
        end
    end
    -- repair
    local repairing = 0
    for _, u in ipairs(st.workers) do if u.order and u.order.type == "repair" then repairing = repairing + 1 end end
    if repairing < 4 then
        for _, b in ipairs(st.buildings) do
            if b.built and b.hp < b.maxhp * 0.8 and not b.def.noRepair then
                local _, theirs = AI.strength(w, p, b.x, b.y, 7)
                -- towers get fixed even under fire; other buildings once the fighting has moved off
                if theirs < 3 or (b.def.attack and theirs < 14) then
                    local on = 0
                    for _, u in ipairs(st.workers) do if u.order and u.order.type == "repair" and u.order.target == b.id then on = on + 1 end end
                    local want = (b.def.attack and theirs > 0) and 3 or (b.hp < b.maxhp * 0.5 and 2 or 1)
                    while on < want and repairing < 4 do
                        local best, bd
                        for _, u in ipairs(st.workers) do
                            local o = u.order
                            if S.canRepair(u, b) and not u.carry and not u.militia and (not o or (o.type == "gather" and o.state ~= "inMine")) and u.id ~= ai.scout then
                                local d = S.dist(u.x, u.y, b.x, b.y)
                                if d < 18 and (not bd or d < bd) then best, bd = u, d end
                            end
                        end
                        if not best then break end
                        S.issue(w, best, { type = "repair", target = b.id })
                        on, repairing = on + 1, repairing + 1
                    end
                end
            end
        end
    end
    -- scouting: one worker walks to the enemy start and back, about a minute in
    local other = w.starts and w.starts[p == 1 and 2 or 1]
    if other and not ai.scouted and w.time > 50 then
        local u = ai.scout and w.ents[ai.scout]
        if not S.alive(u) then
            ai.scout = nil
            -- don't walk a worker into a creep camp on the way
            local hx, hy = other.hall[1] + 1, other.hall[2] + 1
            for _, c in ipairs(w.campSpots or {}) do
                local dx, dy = hx - hall.x, hy - hall.y
                local len2 = dx * dx + dy * dy
                local t = max(0, min(1, ((c.x - hall.x) * dx + (c.y - hall.y) * dy) / len2))
                if S.dist(c.x, c.y, hall.x + dx * t, hall.y + dy * t) < 6 then ai.scouted = true end
            end
            for _, wk in ipairs(ai.scouted and {} or st.workers) do
                local o = wk.order
                if o and o.type == "gather" and o.res == "gold" and o.state == "toMine" and not wk.carry then ai.scout = wk.id u = wk break end
            end
            if u then S.issue(w, u, { type = "move", x = other.hall[1] + 1, y = other.hall[2] + 4 }) ai.scoutT = w.time end
        else
            local seen = S.dist(u.x, u.y, other.hall[1] + 1, other.hall[2] + 1) < 9
            -- turn back as soon as anything bites
            if seen or not u.order or u.hp < u.maxhp * 0.9 or w.time - (ai.scoutT or 0) > 90 then
                ai.scouted = true
                ai.scout = nil
                local m = S.nearestMine(w, hall.x, hall.y, 12)
                if m then S.issue(w, u, { type = "gather", res = "gold", mine = m.id }) else u.order = nil end
            end
        end
    end
end

-- the Undead economy: a Haunted Gold Mine on each mine by a hall, Ghouls on the lumber, Ziggurats
-- made into Spirit Towers, and Obsidian Statues turned into Destroyers
function AI.undeadEconomy(w, ai, st, hall, F, mines)
    local p = ai.p
    local pl = w.players[p]
    ai.saveForMine = nil
    for _, h in ipairs(st.halls) do
        local m = S.nearestMine(w, h.x, h.y, 9, p)
        if m and not m.haunted then
            local going = false
            for _, u in ipairs(st.workers) do if u.order and u.order.type == "build" and u.order.bid == F.mineBuilding then going = true end end
            if not going and F.entangleMine then
                if not (h.def.entangle and S.entangle(w, p, h.id)) then ai.saveForMine = nil end
            elseif not going then
                if S.canAfford(w, p, D.Buildings[F.mineBuilding]) then
                    local u = pickBuilder(w, st)
                    if u then S.build(w, p, u.id, F.mineBuilding, m.tx, m.ty) end
                else
                    ai.saveForMine = true
                end
            end
        end
    end
    if not F.gatherer then return end
    -- Ghouls on the lumber
    local want = (AI.PLANS.undead.lumberGhouls or {})[ai.level] or 4
    -- (with some slack, so Ghouls don't keep being sent off and replaced)
    if pl.lumber > 900 then want = 1 elseif pl.lumber > 500 then want = max(1, want - 1) end
    if #(st.lumberers or {}) > want and pl.lumber < 1200 then want = #st.lumberers end
    local list = st.lumberers or {}
    for i, g in ipairs(list) do
        if i > want then
            g.aiLumber = nil
            g.order = nil
        elseif not g.order then
            local tree = M.nearestTree(w, hall.x, hall.y, 16)
            if tree then S.issue(w, g, { type = "gather", res = "lumber", tree = tree }) end
        end
    end
    local have = math.min(#list, want)
    if have < want then
        for i = #st.army, 1, -1 do
            local u = st.army[i]
            if have >= want then break end
            if u.def.id == F.gatherer and not u.order and S.dist(u.x, u.y, hall.x, hall.y) < 16 then
                u.aiLumber = true
                table.remove(st.army, i)
                st.armySupply = st.armySupply - u.def.supply
                local tree = M.nearestTree(w, hall.x, hall.y, 16)
                if tree then S.issue(w, u, { type = "gather", res = "lumber", tree = tree }) end
                have = have + 1
            end
        end
        if have < want then
            local queued = 0
            for _, b in ipairs(st.buildings) do for _, q in ipairs(b.queue) do if q == F.gatherer then queued = queued + 1 end end end
            if queued < want - have then
                for _, b in ipairs(st.buildings) do
                    if b.def.id == F.barracks and b.built and #b.queue < 2 and S.train(w, p, b.id, F.gatherer) then break end
                end
            end
        end
    end
    -- a Ziggurat or two becomes a Spirit Tower
    local towers = 0
    for _, b in ipairs(st.buildings) do if b.def.id == "spiritTower" or b.def.id == "nerubianTower" or b.upgrading == "spiritTower" then towers = towers + 1 end end
    if (ai.tier or 1) >= 2 and towers < (ai.cfg.towers or 1) + min(2, ai.raids or 0) and S.requirementMet(w, p, "spiritTower") then
        for _, b in ipairs(st.buildings) do
            if b.def.id == "ziggurat" and b.built and not b.upgrading then
                local g, l = S.upgradeCost(b, "spiritTower")
                if pl.gold >= g + 150 and pl.lumber >= l then S.upgradeBuilding(w, p, b.id, "spiritTower") end
                break
            end
        end
    end
    -- Obsidian Statues: keep about half as statues, make the rest Destroyers
    local statues, destroyers = 0, 0
    for _, u in ipairs(st.army) do
        if u.def.id == "obsidianStatue" then statues = statues + 1 elseif u.def.id == "destroyer" then destroyers = destroyers + 1 end
    end
    if statues > destroyers + 1 then
        for _, u in ipairs(st.army) do
            if u.def.id == "obsidianStatue" and S.canCast(w, u, "destroyerMorph") then S.command(w, p, { u.id }, { type = "cast", ability = "destroyerMorph" }) break end
        end
    end
end

-- a neutral hero: walk something to the Tavern and hire it there
function AI.hireTavern(w, ai, p, st, id)
    local def = D.Units[id]
    local pl = w.players[p]
    if w.tavernTaken and w.tavernTaken[id] then
        -- someone else got there first: pick another
        for i, h in ipairs(ai.heroPicks or {}) do if h == id then ai.heroPicks[i] = (AI.HEROES[pl.faction][1])[i] end end
        return
    end
    if pl.gold < def.gold or pl.lumber < def.lumber then return end
    local tav, td
    local hall = st.hall
    for _, e in ipairs(w.list) do
        if e.kind == "building" and e.def.heroes and S.alive(e) then
            local d = S.dist(e.x, e.y, hall.x, hall.y)
            if not td or d < td then tav, td = e, d end
        end
    end
    if not tav then return end
    if S.shopUnit(w, p, tav) then
        S.hireHero(w, p, tav.id, id)
        local r = w.ents[ai.tavernRunner or 0]
        if r and r.def.worker then r.order = nil end
        ai.tavernRunner = nil
        return
    end
    local r = w.ents[ai.tavernRunner or 0]
    if not (r and S.alive(r)) then
        r = st.heroes and st.heroes[1] or st.army[1] or st.workers[#st.workers]
        ai.tavernRunner = r and r.id
    end
    if r and (not r.order or r.order.type ~= "move") then
        S.issue(w, r, { type = "move", x = tav.x, y = tav.y + tav.size / 2 + 0.8 })
    end
end

-- summon (or revive) heroes: one, then a second at tier 2 and a third at tier 3
local function heroWanted(w, ai, p, F)
    local picks = ai.heroPicks
    if not picks then
        local opts = AI.HEROES[w.players[p].faction]
        picks = {}
        for i, id in ipairs(opts[w.rng.next() % #opts + 1]) do picks[i] = id end
        -- on maps with a Tavern, sometimes take a neutral hero as the second one
        for _, e in ipairs(w.list) do
            if e.kind == "building" and e.def.heroes then
                if w.rng.next() % 100 < 40 then
                    local th = D.TAVERN_HEROES or {}
                    if #th > 0 then picks[2] = th[w.rng.next() % #th + 1] end
                end
                break
            end
        end
        ai.heroPicks = picks
    end
    local pl = w.players[p]
    for _, rec in ipairs(pl.deadHeroes or {}) do
        if S.heroAllowed(w, p, rec.id) then return rec.id, true end
    end
    local maxHeroes = ai.cfg.heroes or 3
    if S.heroCount(w, p) >= maxHeroes then return nil end
    for _, id in ipairs(picks) do
        if S.heroAllowed(w, p, id) and not S.hasHeroType(w, p, id) then return id end
    end
end

function AI.think(w, ai)
    local p, cfg = ai.p, ai.cfg
    local pl = w.players[p]
    local F = D.Factions[pl.faction]
    local st = myStuff(w, p)
    if not st.hall then
        -- no hall: rebuild one if we can, otherwise throw everything at the enemy
        if #st.workers > 0 and S.canAfford(w, p, D.Buildings[F.hall]) and total(st, F.hall) == 0 then
            local u = st.workers[1]
            local x, y = M.nearestOpen(w, floor(u.x), floor(u.y), 6)
            for r = 0, 8 do
                local done = false
                for yy = y - r, y + r do for xx = x - r, x + r do
                    if not done and M.canPlace(w, xx, yy, 4) then done = S.build(w, p, u.id, F.hall, xx, yy) end
                end end
                if done then break end
            end
        end
        local tgt = nearestEnemyThing(w, p, w.w / 2, w.h / 2)
        if tgt and #st.army > 0 then
            local ids = {} for _, u in ipairs(st.army) do if not u.order then ids[#ids + 1] = u.id end end
            if #ids > 0 then S.command(w, p, ids, { type = "amove", x = tgt.x, y = tgt.y }) end
        end
        return
    end
    local hall = st.hall
    -- mines worked from each hall
    local mines = {}
    for _, h in ipairs(st.halls) do
        local m = S.nearestMine(w, h.x, h.y, 9, p)
        if m and F.mineBuilding and not (m.haunted and w.ents[m.haunted] and w.ents[m.haunted].built) then m = nil end
        if m then mines[#mines + 1] = { hall = h, mine = m, n = 0 } end
    end
    local mine = mines[1] and mines[1].mine

    -- ---------------------------------------------------------- economy
    local nWorkers = (st.count[F.worker] or 0)
    local wantWorkers = cfg.workers + (#mines > 1 and 5 or 0)
    -- Undead: five Acolytes on each Haunted Gold Mine and one to summon buildings; Ghouls cut the lumber
    if F.mineBuilding then wantWorkers = 5 * max(1, #mines) + 1 + (F.gatherer and 0 or (cfg.lumber or 4) + 1) end
    if F.mineBuilding then AI.undeadEconomy(w, ai, st, hall, F, mines) end
    for _, h in ipairs(st.halls) do
        if #h.queue < 1 and nWorkers < wantWorkers and pl.used < pl.cap then
            if S.train(w, p, h.id, F.worker) then nWorkers = nWorkers + 1 end
        end
    end
    local onLumber = 0
    for _, u in ipairs(st.workers) do
        local o = u.order
        if o and o.type == "gather" then
            if o.res == "gold" then
                for _, mm in ipairs(mines) do if mm.mine.id == o.mine then mm.n = mm.n + 1 end end
            else
                onLumber = onLumber + 1
            end
        end
    end
    local function freeMine()
        local best
        for _, mm in ipairs(mines) do
            if mm.n < 5 and (not best or mm.n < best.n) then best = mm end
        end
        return best
    end
    local wantLumber = pl.lumber > 600 and 2 or (cfg.lumber or 5)
    for _, u in ipairs(st.workers) do
        if not u.order and u.def.haunt and not u.def.wispHarvest then
            local mm = freeMine()
            if mm then S.issue(w, u, { type = "gather", res = "gold", mine = mm.mine.id }) mm.n = mm.n + 1 end
        elseif not u.order then
            local mm = freeMine()
            if mm and (onLumber >= wantLumber or mm.n < 3) then
                S.issue(w, u, { type = "gather", res = "gold", mine = mm.mine.id })
                mm.n = mm.n + 1
            else
                local tree = M.nearestTree(w, hall.x, hall.y, 16)
                if tree then
                    S.issue(w, u, { type = "gather", res = "lumber", tree = tree })
                    onLumber = onLumber + 1
                elseif mm then
                    S.issue(w, u, { type = "gather", res = "gold", mine = mm.mine.id })
                    mm.n = mm.n + 1
                end
            end
        end
    end
    -- a mine with more than 5 workers just makes them queue: move extras along
    for _, mm in ipairs(mines) do
        if mm.n > 5 then
            for _, u in ipairs(st.workers) do
                if mm.n <= 5 then break end
                local o = u.order
                if o and o.type == "gather" and o.res == "gold" and o.mine == mm.mine.id and o.state == "toMine" and not u.carry then
                    local other = freeMine()
                    if other and other ~= mm then
                        S.issue(w, u, { type = "gather", res = "gold", mine = other.mine.id })
                        other.n = other.n + 1
                    elseif u.def.haunt then
                        u.order = nil
                    else
                        local tree = M.nearestTree(w, hall.x, hall.y, 16)
                        if tree then S.issue(w, u, { type = "gather", res = "lumber", tree = tree }) end
                    end
                    mm.n = mm.n - 1
                end
            end
        end
    end

    -- ---------------------------------------------------------- expanding
    -- when the home mine starts running low, take the nearest free mine
    local lowGold = 0
    for _, mm in ipairs(mines) do lowGold = lowGold + mm.mine.gold end
    if not ai.expand and (lowGold < 4000 or (#mines == 0)) and w.time > 240 then
        local best, bd
        for _, e in ipairs(w.list) do
            if e.kind == "mine" and S.alive(e) and e.gold > 2000 then
                local taken = false
                for _, b in ipairs(w.list) do
                    if b.kind == "building" and S.alive(b) and b.def.hall and S.dist(b.x, b.y, e.x, e.y) < 10 then taken = true end
                end
                if not taken then
                    local d = S.dist(e.x, e.y, hall.x, hall.y)
                    if not bd or d < bd then best, bd = e, d end
                end
            end
        end
        if best then ai.expand = { mine = best.id } end
    end
    if ai.expand then
        local m = w.ents[ai.expand.mine]
        if not S.alive(m) then ai.expand = nil
        else
            -- clear creeps guarding it first
            local guard
            for _, e in ipairs(w.list) do
                if e.owner == 3 and S.alive(e) and S.dist(e.x, e.y, m.x, m.y) < 9 then guard = e break end
            end
            ai.expandGuard = guard and guard.id or nil
            local placed = false
            for _, b in ipairs(w.list) do
                if b.kind == "building" and b.owner == p and S.alive(b) and b.def.hall and S.dist(b.x, b.y, m.x, m.y) < 10 then placed = true end
            end
            for _, u in ipairs(st.workers) do if u.order and u.order.type == "build" and u.order.bid == F.hall then placed = true end end
            if placed then
                if st.halls[2] or #mines > 1 then ai.expand = nil end
            elseif not guard then
                ai.saveForHall = true
            end
            if not placed and not guard and S.canAfford(w, p, D.Buildings[F.hall]) then
                local bx, by, bd
                for y = m.ty - 7, m.ty + 7 do
                    for x = m.tx - 7, m.tx + 7 do
                        if M.canPlace(w, x - 1, y - 1, 6) then
                            local d = S.dist(x + 1, y + 1, m.x, m.y)
                            if d >= 4.5 and (not bd or d < bd) then bx, by, bd = x, y, d end
                        end
                    end
                end
                local u = pickBuilder(w, st)
                if bx and u and S.build(w, p, u.id, F.hall, bx, by) then ai.saveForHall = false end
            end
        end
    end

    -- ---------------------------------------------------------- buildings & tiers
    local plan = AI.PLANS[pl.faction]
    local tier = 1
    for _, h in ipairs(st.halls) do tier = max(tier, h.def.tier or 1) end
    ai.tier = tier
    local farmsBuilding = (st.pendingBuild[F.farm] or 0)
    local need = pl.cap < D.MAX_SUPPLY and (pl.cap - pl.used) <= (pl.used > 30 and 8 or 5)
    local reserve = 0
    if need and farmsBuilding < (pl.used > 40 and 2 or 1) then
        tryBuild(w, ai, st, F.farm)
        reserve = reserve + 80
    else
        for _, step in ipairs(plan.build) do
            local id, count, at, tierNeed = step[1], step[2], step[3] or 0, step.tier or 1
            if id == F.tower then count = cfg.towers + (ai.style and ai.style.towers or 0) + min(2, ai.raids or 0) end
            if id == F.barracks and count > 1 then count = cfg.barracks end
            if total(st, id) < count and w.time >= at and tier >= tierNeed and (not step.gold or pl.gold >= step.gold) then
                if S.requirementMet(w, p, id) then
                    local nx, ny
                    if id == F.tower then
                        -- towers go on the side of the base facing the enemy
                        local ex, ey = w.w / 2, w.h / 2
                        local dx, dy = ex - hall.x, ey - hall.y
                        local d = max(1, sqrt(dx * dx + dy * dy))
                        nx, ny = hall.x + dx / d * 6, hall.y + dy / d * 6
                    end
                    if not tryBuild(w, ai, st, id, nx, ny) then reserve = reserve + D.Buildings[id].gold end
                    break
                end
            end
        end
    end

    -- the next hall tier
    local upAt = cfg.tierTimes and cfg.tierTimes[tier] and cfg.tierTimes[tier] - (ai.style and ai.style.earlyTier or 0)
    local armyFor = tier == 1 and 10 or 20
    if upAt and w.time >= upAt and (st.armySupply >= armyFor or pl.gold > 900) and hall.def.upgrade and not hall.upgrading and #hall.queue == 0 then
        local to = hall.def.upgrade
        if S.requirementMet(w, p, to) then
            local g, l = S.upgradeCost(hall, to)
            if pl.gold >= g and pl.lumber >= l then S.upgradeBuilding(w, p, hall.id, to)
            else reserve = reserve + g end
        elseif total(st, F.altar) == 0 then
            tryBuild(w, ai, st, F.altar)
        end
    end
    if hall.upgrading then reserve = reserve + 0 end

    -- ---------------------------------------------------------- research
    -- research only once there's an army worth upgrading (or money to spare)
    local done = 0
    for _, lv in pairs(pl.research) do done = done + lv end
    local armyOk = st.armySupply >= 6 + 5 * done or pl.gold > 700
    if cfg.research and armyOk and pl.gold > reserve + 150 then
        for _, rid in ipairs(plan.research) do
            local r = D.Research[rid]
            local g, l, _, lv = S.researchCost(w, p, rid)
            if g and not pl.researching[rid] and S.requirementMet(w, p, rid, lv) and pl.gold >= g + reserve + 100 and pl.lumber >= l then
                local where
                for _, b in ipairs(st.buildings) do
                    local ok = b.def.id == r.at or (r.at == F.hall and b.def.hall)
                    if ok and b.built and not b.upgrading and #b.queue == 0 then where = b break end
                end
                if where and S.research(w, p, where.id, rid) then break end
            end
        end
    end

    -- ---------------------------------------------------------- towers, repair, scouting
    if ai.level ~= "easy" then AI.upkeepBase(w, ai, st, hall, F, reserve) end

    -- ---------------------------------------------------------- units
    -- save up for the hero as soon as there's an altar
    if ai.saveForHall and ai.expand then reserve = reserve + D.Buildings[F.hall].gold end
    if ai.saveForMine and F.mineBuilding then reserve = reserve + D.Buildings[F.mineBuilding].gold end
    local wantHero, revive = nil, false
    if have(st, F.altar) then wantHero, revive = heroWanted(w, ai, p, F) end
    if wantHero and S.heroCount(w, p) > 0 then
        local rec = revive and S.deadHero(w, p, wantHero)
        reserve = reserve + (rec and S.reviveCost(rec) or D.Units[wantHero].gold)
    end
    -- does the enemy fly? then lean on things that shoot air
    local enemyAir = 0
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and S.alive(e) and e.owner ~= p and e.owner <= 2 and e.def.air then enemyAir = enemyAir + e.def.supply end
    end
    for _, b in ipairs(st.buildings) do
        if b.built and b.def.trains and not b.upgrading then
            if b.def.id == F.altar then
                if wantHero and D.Units[wantHero].tavern and not revive then
                    AI.hireTavern(w, ai, p, st, wantHero)
                elseif wantHero and #b.queue == 0 then S.train(w, p, b.id, wantHero) end
            elseif not b.def.hall and #b.queue < 2 and ai.nextUnit and ai.nextUnit[b.id] then
                -- the unit already chosen for this building: wait until it's affordable instead of
                -- always ending up with whatever is cheapest
                local uid = ai.nextUnit[b.id]
                local u = D.Units[uid]
                if not S.requirementMet(w, p, uid) then ai.nextUnit[b.id] = nil
                elseif pl.gold - reserve >= u.gold and pl.lumber >= (u.lumber or 0) then
                    if S.train(w, p, b.id, uid) then ai.nextUnit[b.id] = nil end
                end
            elseif not b.def.hall and #b.queue < 2 and pl.gold - reserve > 100 then
                -- weighted pick among what this building can make right now
                ai.nextUnit = ai.nextUnit or {}
                local options, totalW = {}, 0
                for _, uid in ipairs(b.def.trains) do
                    local wt = plan.weights[uid] or 0
                    local u = D.Units[uid]
                    if wt > 0 and S.requirementMet(w, p, uid) then
                        if enemyAir > 6 and u.hitsAir then wt = wt * 2.5 end
                        if plan.limit and plan.limit[uid] and (st.count[uid] or 0) >= plan.limit[uid] then wt = 0 end
                        if wt > 0 then options[#options + 1] = { uid, wt } totalW = totalW + wt end
                    end
                end
                if totalW > 0 then
                    local roll = w.rng.float() * totalW
                    for _, o in ipairs(options) do
                        roll = roll - o[2]
                        if roll <= 0 then
                            if not S.train(w, p, b.id, o[1]) then ai.nextUnit[b.id] = o[1] end
                            break
                        end
                    end
                end
            end
            if not b.rally and not b.def.hall then
                local gx, gy = hall.x + (w.w / 2 - hall.x) * 0.25, hall.y + (w.h / 2 - hall.y) * 0.25
                S.setRally(w, p, b.id, gx, gy)
            end
        end
    end

    unitSpells(w, ai, st)
    -- heroes: drink a potion when hurt, pick up items lying nearby, and buy potions at home
    for _, h in ipairs(st.heroes or {}) do
        if h.inv then
            for i = 1, 6 do
                local sl = h.inv[i]
                local it = sl and D.Items[sl.id]
                if it and ((it.heal and h.hp < h.maxhp * 0.4) or (it.mana and not it.heal and h.mana < h.maxMana * 0.25 and it.class ~= "permanent")) and S.canUseItem(w, h, i) then
                    S.useItem(w, h, i)
                end
            end
        end
        if not (h.order and (h.order.type == "pickup" or h.order.type == "cast")) and S.freeSlot(h) then
            for _, e in ipairs(w.list) do
                if e.kind == "item" and S.alive(e) and S.dist(e.x, e.y, h.x, h.y) < 8 then S.issue(w, h, { type = "pickup", item = e.id }) break end
            end
        end
        if pl.gold > 450 then
            for _, b in ipairs(st.buildings) do
                if b.built and b.def.shop and S.shopHero(w, p, b) == h then
                    local have = 0
                    for i = 1, 6 do if h.inv and h.inv[i] and h.inv[i].id == "phea" then have = have + 1 end end
                    if have < 2 then S.buyItem(w, p, b.id, "phea") end
                end
            end
        end
    end
    ai.heroHome = ai.heroHome or {}
    for _, h in ipairs(st.heroes or {}) do
        learnSkills(w, h)
        heroSpells(w, ai, st, h)
        -- a badly hurt hero walks home to heal
        if h.hp < h.maxhp * 0.3 and not ai.heroHome[h.id] and not h.reviveT then
            ai.heroHome[h.id] = true
            if not (h.order and h.order.type == "cast") then S.issue(w, h, { type = "move", x = hall.x + 2, y = hall.y + 2 }) end
        elseif ai.heroHome[h.id] and h.hp > h.maxhp * 0.8 then
            ai.heroHome[h.id] = nil
        end
        if ai.heroHome[h.id] then
            for i = #st.army, 1, -1 do if st.army[i] == h then table.remove(st.army, i) end end
        end
    end

    -- ---------------------------------------------------------- army
    ai.issueT = ai.issueT - cfg.think
    local threat, threatD
    for _, e in ipairs(w.list) do
        if e.kind == "unit" and S.alive(e) and e.owner ~= p and e.owner >= 1 and e.owner <= 2 and not e.hidden then
            local d = S.dist(e.x, e.y, hall.x, hall.y)
            if d < 16 and (not threatD or d < threatD) then threat, threatD = e, d end
        end
    end
    ai.pulled = ai.pulled or {}
    local function sendAll(x, y, force)
        local ids, back = {}, {}
        local cx, cy = armyCentre(st.army)
        for _, u in ipairs(st.army) do
            local o = u.order
            if not ai.pulled[u.id] and not (ai.waiting and ai.waiting[u.id]) and (force or not o or (o.type == "move" and not o.kite) or (o.type == "amove" and not o.target)) then
                if not (o and o.type == "cast") then
                    -- casters and mortars walk a little behind the rest
                    if AI.fragile(u.def) and ai.level ~= "easy" then back[#back + 1] = u.id else ids[#ids + 1] = u.id end
                end
            end
        end
        if #ids > 0 then S.command(w, p, ids, { type = "amove", x = x, y = y }) end
        if #back > 0 then
            local bx, by = x, y
            if cx then
                local dx, dy = x - cx, y - cy
                local d = sqrt(dx * dx + dy * dy)
                if d > 4 then bx, by = x - dx / d * 2.5, y - dy / d * 2.5 end
            end
            S.command(w, p, back, { type = "amove", x = bx, y = by })
        end
    end

    -- how much enemy army is in the base, against how much of ours is home
    local enemyNear, oursNear = 0, 0
    if threat then
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and S.alive(e) and e.owner >= 1 and e.owner <= 2 and not e.def.worker and S.dist(e.x, e.y, hall.x, hall.y) < 18 then
                if e.owner == p then oursNear = oursNear + (e.def.supply or 1) else enemyNear = enemyNear + (e.def.supply or 1) end
            end
        end
    end
    if threat then
        if ai.issueT <= 0 then
            ai.issueT = 2
            sendAll(threat.x, threat.y)
            local mil = {}
            for _, u in ipairs(st.militia or {}) do if not u.order or (u.order.type == "amove" and not u.order.target) then mil[#mil + 1] = u.id end end
            if #mil > 0 and threatD < 14 then S.command(w, p, mil, { type = "amove", x = threat.x, y = threat.y }) end
        end
        -- outnumbered at home: Peons man the burrows, Peasants take up arms
        -- (Peasants only take up arms when Militia can tip the fight; against a far bigger army they'd
        -- just die, and the base dies with its workers)
        local worthIt = pl.faction == "orcs" or enemyNear <= oursNear + #st.workers * 0.8
        if enemyNear >= 6 and enemyNear > oursNear and worthIt and not ai.workersArmed then
            local ok = pl.faction == "orcs" and S.battleStations(w, p, hall.id) or (pl.faction == "alliance" and S.callToArms(w, p, hall.id))
            if ok then ai.workersArmed = true end
        end
        if not ai.defending and enemyNear >= 4 then ai.raids = (ai.raids or 0) + 1 end
        ai.defending = true
        return
    end
    if ai.workersArmed then
        ai.workersArmed = nil
        S.backToWorkAll(w, p, hall.id)
    end
    ai.defending = false

    local guard = ai.expandGuard and w.ents[ai.expandGuard]
    if S.alive(guard) and st.armySupply >= 10 then
        if ai.issueT <= 0 then
            ai.issueT = 3
            sendAll(guard.x, guard.y, true)
        end
        return
    end

    if ai.attacking then
        if st.armySupply < ai.wave * 0.3 then
            ai.attacking = false
            ai.wave = min(D.MAX_SUPPLY - 16, ai.wave + cfg.waveGrow)
            local gx, gy = hall.x + (w.w / 2 - hall.x) * 0.25, hall.y + (w.h / 2 - hall.y) * 0.25
            local ids = {} for _, u in ipairs(st.army) do ids[#ids + 1] = u.id end
            S.command(w, p, ids, { type = "move", x = gx, y = gy })
            return
        end
        -- losing the fight badly away from home: fall back and regroup, as the WC3 AI does
        local cx, cy = armyCentre(st.army)
        if cx and ai.level ~= "easy" and (ai.retreatT or 0) < w.time then
            local ours, theirs = AI.strength(w, p, cx, cy, 11)
            if theirs > ours * 1.7 and theirs > 8 and S.dist(cx, cy, hall.x, hall.y) > 18 then
                ai.attacking = false
                ai.retreatT = w.time + 30
                ai.wave = min(D.MAX_SUPPLY - 16, max(ai.wave, floor(st.armySupply * 1.3)))
                local gx, gy = hall.x + (w.w / 2 - hall.x) * 0.25, hall.y + (w.h / 2 - hall.y) * 0.25
                local ids = {} for _, u in ipairs(st.army) do if not (u.order and u.order.type == "cast") then ids[#ids + 1] = u.id end end
                S.command(w, p, ids, { type = "move", x = gx, y = gy })
                return
            end
        end
        if ai.issueT <= 0 then
            ai.issueT = 3
            -- reinforcements wait at home until there are a few of them, instead of walking
            -- one at a time into the enemy
            ai.waiting = nil
            if cx and ai.level ~= "easy" then
                local list = {}
                for _, u in ipairs(st.army) do
                    if not u.def.hero and S.dist(u.x, u.y, hall.x, hall.y) < 16 and S.dist(u.x, u.y, cx, cy) > 14 then list[#list + 1] = u end
                end
                if #list > 0 and #list < 4 then
                    ai.waiting = {}
                    for _, u in ipairs(list) do ai.waiting[u.id] = true end
                end
            end
            local tgt = cx and AI.target(w, ai, cx, cy)
            if tgt then sendAll(tgt.x, tgt.y) end
        end
        return
    end

    -- creep with the hero before the first attack
    if st.hero and st.armySupply - st.hero.def.supply >= 8 and not ai.creeping and ai.issueT <= 0 and (ai.creepBackT or 0) < w.time then
        -- size up each camp (total creep levels) against our army and heroes, and take the closest one we can beat
        local camps = {}
        for _, e in ipairs(w.list) do
            if e.owner == 3 and S.alive(e) and e.camp and e.kind == "unit" then
                local key = e.camp[1] .. ":" .. e.camp[2]
                local c = camps[key]
                if not c then c = { lv = 0, unit = e } camps[key] = c end
                -- creep casters (healers, Inner Fire, Sleep) make a camp much harder than its levels suggest
                c.lv = c.lv + (e.def.level or 1) * ((e.def.spells and 1.4) or 1)
            end
        end
        local power = st.armySupply
        for _, h in ipairs(st.heroes or {}) do power = power + h.level * 2 end
        local camp, cd
        for _, c in pairs(camps) do
            local d = S.dist(hall.x, hall.y, c.unit.x, c.unit.y)
            if d < 45 and c.lv <= power * 0.6 and (not cd or d < cd) then camp, cd = c.unit, d end
        end
        if camp then
            ai.issueT = 3
            sendAll(camp.x, camp.y, true)
            ai.creepTarget = camp.id
        end
    end
    if ai.creepTarget and not S.alive(w.ents[ai.creepTarget]) then ai.creepTarget = nil end
    -- a camp that turns out too strong: back off before the army is lost (WC3's AI does this too)
    if ai.creepTarget and ai.level ~= "easy" then
        local c = w.ents[ai.creepTarget]
        local ours, theirs = AI.strength(w, p, c.x, c.y, 8, true)
        if theirs > ours * 1.3 and ours > 0 then
            ai.creepTarget = nil
            ai.creepBackT = w.time + 45
            local gx, gy = hall.x + (w.w / 2 - hall.x) * 0.25, hall.y + (w.h / 2 - hall.y) * 0.25
            local ids = {} for _, u in ipairs(st.army) do if not (u.order and u.order.type == "cast") then ids[#ids + 1] = u.id end end
            S.command(w, p, ids, { type = "move", x = gx, y = gy })
        end
    end

    -- normal and hard compare armies before committing (they peek at the enemy's army size)
    local want = ai.wave
    if ai.level ~= "easy" then
        local enemy = 0
        for _, e in ipairs(w.list) do
            if e.kind == "unit" and S.alive(e) and e.owner ~= p and e.owner <= 2 and not e.def.worker then enemy = enemy + e.def.supply end
        end
        want = max(want, floor(enemy * 1.15) + 2)
        if pl.used >= pl.cap - 2 and pl.cap >= D.MAX_SUPPLY - 4 then want = min(want, st.armySupply) end
    end
    if st.armySupply >= want then
        ai.attacking = true
        ai.issueT = 0
    end
end


-- ---------------------------------------------------------- tactics (run twice a second)
-- What a good WC3 player (and the better WC3 AI) does in a fight: everyone shoots the enemy that
-- will die soonest for the most value, badly hurt units step out of the fight, and spellcasters and
-- mortars keep behind the melee line.

local function fragile(def)
    return not def.hero and (def.role == "caster" or def.role == "siege" or (def.mana and def.mana > 0)) and not def.air
end
AI.fragile = fragile

-- rough damage of one attack of u against e (dice average, WC3 type table, armour)
local function hitOn(w, u, e)
    local wp = S.weaponFor(w, u, e)
    if not wp then return nil end
    local avg = wp.base + (wp.dice or 1) * ((wp.sides or 1) + 1) / 2
    if u.def.hero then local _, _, _, main = S.heroStats(u) avg = avg + main end
    local a, t = S.armorOf(w, e)
    if e.def.hero then t = "hero" end
    local mult = (D.ATTACK_VS[wp.atype or "normal"] or D.ATTACK_VS.normal)[t] or 1
    return max(1, avg * mult * S.armorMult(a)), wp
end

-- how much a target is worth killing first
local function worth(e)
    local v = (e.def.supply or 1) ^ 0.5
    if e.def.hero then v = v * 3 end
    if fragile(e.def) then v = v * 1.6 end
    if e.def.summon then v = v * 0.6 end
    if e.def.worker then v = v * 0.3 end
    if e.def.ward then v = v * 0.8 end
    return v
end

function AI.micro(w, ai)
    local p = ai.p
    local pl = w.players[p]
    if ai.level == "easy" then return end
    local hall
    local mine, foes = {}, {}
    for _, e in ipairs(w.list) do
        if S.alive(e) and not e.hidden then
            if e.owner == p then
                if e.kind == "unit" and not e.def.worker and not e.def.ward and e.def.dmin then mine[#mine + 1] = e end
                if e.kind == "building" and e.def.hall and not hall then hall = e end
            elseif e.kind == "unit" and e.owner >= 1 and (e.owner <= 3) and e.owner ~= 0 then
                foes[#foes + 1] = e
            end
        end
    end
    if #mine == 0 or #foes == 0 then return end
    ai.pulled = ai.pulled or {}
    ai.kite = ai.kite or {}
    local alloc = {}        -- damage per volley already pointed at each enemy
    for _, u in ipairs(mine) do
        local o = u.order
        local busy = o and (o.type == "cast" or o.type == "pickup" or o.type == "garrison" or o.type == "repair" or o.type == "leash")
        local tid = o and o.target
        if not busy and tid and w.ents[tid] then
            local h = hitOn(w, u, w.ents[tid])
            if h then alloc[tid] = (alloc[tid] or 0) + h end
        end
    end
    local now = w.time
    for _, u in ipairs(mine) do
        local o = u.order
        local busy = (u.stun or 0) > 0 or u.channel or (o and (o.type == "cast" or o.type == "pickup" or o.type == "garrison" or o.type == "repair"
            or o.type == "move" or o.type == "leash" or o.type == "patrol" or o.type == "follow"))
        local ff = fragile(u.def)
        -- 1. step out of the fight when badly hurt (heroes look after themselves elsewhere)
        local pulled = ai.pulled[u.id]
        if pulled then
            if u.hp >= u.maxhp * 0.65 or now - pulled > 45 then ai.pulled[u.id] = nil
            elseif not u.order and hall then S.issue(w, u, { type = "move", x = hall.x + 1.5, y = hall.y + 1.5 }) end
        elseif not u.def.hero and not u.def.summon and u.hp < u.maxhp * 0.28 and u.maxhp >= 250 and not busy then
            -- only worth it if something is hitting it
            local threat
            for _, e in ipairs(foes) do
                if abs(e.x - u.x) < 4 and abs(e.y - u.y) < 4 and S.isEnemy(e, u) then threat = e break end
            end
            if threat and hall and S.dist(u.x, u.y, hall.x, hall.y) > 12 then
                ai.pulled[u.id] = now
                S.issue(w, u, { type = "move", x = hall.x + 1.5, y = hall.y + 1.5 })
            elseif threat then
                -- fighting at home: just back off a few steps
                local dx, dy = u.x - threat.x, u.y - threat.y
                local d = max(0.1, sqrt(dx * dx + dy * dy))
                ai.pulled[u.id] = now - 35
                S.issue(w, u, { type = "move", x = u.x + dx / d * 4, y = u.y + dy / d * 4 })
            end
        elseif ff and not busy and (ai.kite[u.id] or 0) < now then
            -- 2. casters and mortars back away from melee units that reach them
            for _, e in ipairs(foes) do
                if abs(e.x - u.x) < 2.5 and abs(e.y - u.y) < 2.5 and S.isEnemy(e, u) and e.def.dmin and (e.def.range or 1) < 1.5
                   and not e.def.air and S.gap(e, u) < 0.9 then
                    local dx, dy = u.x - e.x, u.y - e.y
                    local d = max(0.1, sqrt(dx * dx + dy * dy))
                    ai.kite[u.id] = now + 1.6
                    local tx, ty = u.x + dx / d * 3, u.y + dy / d * 3
                    if M.walkable(w, floor(tx) + 1, floor(ty) + 1) then
                        -- go back, then carry on with what we were doing
                        local back = o and o.type == "amove" and { type = "amove", x = o.x, y = o.y } or nil
                        S.issue(w, u, { type = "move", x = tx, y = ty, kite = true })
                        if back then u.queue = { back } end
                    end
                    break
                end
            end
        end
        -- Footmen raise Defend against arrows and spears, and lower it when fighting melee
        if u.def.id == "footman" and S.level(w, p, "defend") > 0 and (ai.defT or {})[u.id] ~= floor(now / 2) then
            ai.defT = ai.defT or {}
            ai.defT[u.id] = floor(now / 2)
            local pierce, other = 0, 0
            for _, e in ipairs(foes) do
                if abs(e.x - u.x) < 9 and abs(e.y - u.y) < 9 and S.isEnemy(u, e) and e.def.dmin then
                    if (e.def.atype or "normal") == "pierce" then pierce = pierce + (e.def.supply or 1) else other = other + (e.def.supply or 1) end
                end
            end
            local want = pierce > 0 and pierce >= other * 0.6
            if pierce + other == 0 then want = u.defend end
            if (want and true or false) ~= (u.defend and true or false) then S.command(w, p, { u.id }, { type = "defend", on = want }) end
        end
        -- 3. focus fire: pick the enemy in reach that dies soonest for the most value
        o = u.order
        if not ai.pulled[u.id] and o and (o.type == "amove" or o.type == "attack" or o.type == "hold") and (u.stun or 0) <= 0 and not u.channel then
            local rng = S.rangeOf(w, u)
            local melee = rng < 1.5
            local reach = rng + (melee and 0.35 or 0.6)
            local cur = o.target and w.ents[o.target]
            local best, bs, cs
            for _, e in ipairs(foes) do
                if abs(e.x - u.x) < reach + 2 and abs(e.y - u.y) < reach + 2 and S.isEnemy(u, e) and S.targetable(w, u, e) then
                    local g = S.gap(u, e)
                    if g <= reach then
                        local h = hitOn(w, u, e)
                        if h then
                            local already = alloc[e.id] or 0
                            if cur == e then already = max(0, already - h) end
                            local left = e.hp - already
                            local sc
                            if left <= 0 then sc = 99 + e.hp / h          -- enough already on it: don't overkill
                            else sc = (left / h) / worth(e) end
                            if cur == e then cs = sc end
                            if not bs or sc < bs then best, bs = e, sc end
                        end
                    end
                end
            end
            if best and best ~= cur and (not cs or bs < cs * 0.7) then
                if cur then local h = hitOn(w, u, cur) if h then alloc[cur.id] = (alloc[cur.id] or 0) - h end end
                local h = hitOn(w, u, best)
                alloc[best.id] = (alloc[best.id] or 0) + (h or 0)
                if o.type == "attack" and not o.auto then
                    S.issue(w, u, { type = "attack", target = best.id, auto = true, home = { u.x, u.y } })
                else
                    o.target = best.id
                    if o.type == "attack" then o.home = o.home or { u.x, u.y } end
                end
            end
        end
    end
end

function AI.step(w, dt)
    for p = 1, 2 do
        local ai = w.players[p].ai
        if ai and type(ai) == "table" and ai.cfg then
            ai.t = ai.t - dt
            if ai.t <= 0 then
                ai.t = ai.cfg.think
                AI.think(w, ai)
            end
            ai.mt = (ai.mt or 0) - dt
            if ai.mt <= 0 then
                ai.mt = ai.level == "hard" and 0.3 or 0.5
                AI.micro(w, ai)
            end
        end
    end
end
