-- Skirmish: sounds. Unit replies when you select and order them, plus the warnings
-- (under attack, building complete, upgrade complete, hero level up).
--
-- WoW still ships some of Warcraft III's own voice lines (Peasant, Peon, Rifleman, Mortar Team,
-- Footman, Grunt, Troll, Tauren, Witch Doctor, Wolf Rider, Mountain King). Those are used where
-- they exist; other units borrow the matching WoW race's voice emotes (yes / hello / attack).

local ADDON, ns = ...
local E = ns.Engine
local D, S = E.Data, E.Sim
local UI = ns.UI
local So = {}
UI.Sound = So

-- ------------------------------------------------------------------ voice sets
-- what = selected, yes = move order, attack = attack order, ready = trained, pissed = clicked a lot

local RACE = {
    humanMale = { what = { 540674, 540664, 540681, 540665 }, yes = { 540702, 540709, 540667 }, attack = { 540686, 540713, 540696, 540717, 540688 } },
    humanFemale = { what = { 540629, 540608, 540657 }, yes = { 540624, 540605, 540632 }, attack = { 540627, 540619, 540623, 540618 } },
    dwarf = { what = { 540077, 540082, 540072, 540073 }, yes = { 540047, 540062, 540022, 540044 }, attack = { 540036, 540068, 540046, 540085, 540088 } },
    gnome = { what = { 540490, 540505, 540469, 540485 }, yes = { 540471, 540477, 540483 }, attack = { 540473, 540487, 540491, 540509 } },
    orc = { what = { 541408, 541425, 541418 }, yes = { 541424, 541399, 541379, 541377 }, attack = { 541417, 541407, 541384, 541389, 541391 } },
    troll = { what = { 543332, 543282, 543309 }, yes = { 543313, 543306, 543328, 543312 }, attack = { 543299, 543316, 543284, 543293 } },
    tauren = { what = { 543074, 543035, 543029 }, yes = { 543046, 543030, 543036 }, attack = { 543023, 543073, 543040, 543071 } },
    undeadMale = { what = { 542761, 542764, 542752 }, yes = { 542750, 542741, 542789 }, attack = { 542756, 542774, 542762, 542738 } },
    nightelfMale = { what = { 541089, 541090, 541097 }, yes = { 541099, 541130, 541137 }, attack = { 541088, 541119, 541081, 541092 } },
    nightelfFemale = { what = { 541030, 541032, 541041 }, yes = { 541046, 541058, 541071 }, attack = { 541042, 541053, 541023, 541025 } },
    undeadFemale = { what = { 542699, 542678, 542722 }, yes = { 542729, 542703, 542718 }, attack = { 542683, 542702, 542712, 542725 } },
}

-- Warcraft III's own lines, as WoW has them
local WC3 = {
    peasant = { what = { 558128, 558127, 558120 }, yes = { 558119, 558124, 558125 }, attack = { 558123, 558117, 558126 },
                ready = { 558118 }, pissed = { 558122 }, warcry = { 558121 } },
    peon = { what = { 558141, 558134, 558143, 558135 }, yes = { 558136, 558139, 558147, 558140 }, attack = { 558145, 558138 },
             ready = { 558137 }, pissed = { 558133, 558144, 558142, 558146 }, done = { 558132 } },
    rifleman = { what = { 559204, 559194 }, yes = { 559197, 559207, 559198 }, attack = { 559206, 559202, 559195, 559205 },
                 ready = { 559203 }, pissed = { 559196, 559200, 559201, 559199 } },
    mortarTeam = { yes = { 555838 }, attack = { 555836 }, ready = { 555842 }, pissed = { 555837, 555840, 555841, 555839 } },
    footman = { attack = { 549226, 549227, 549225 } },
    grunt = { attack = { 551331, 551330, 551332, 551329 }, warcry = { 551328 } },
    troll = { attack = { 549239, 549240, 549238 }, warcry = { 549241 } },
    tauren = { what = { 561481 }, yes = { 561484 }, attack = { 561482, 561480 }, pissed = { 561483 }, warcry = { 561485 } },
    witchDoctor = { what = { 564185, 564196, 564184 }, yes = { 564193, 564186, 564191 }, attack = { 564190, 564194, 564188 },
                    ready = { 564189 }, pissed = { 564187, 564183, 564195 }, warcry = { 564192 } },
    wolfRider = { what = { 564203, 564207 }, yes = { 564201, 564202 }, attack = { 564200, 564204 }, ready = { 564199 },
                  pissed = { 564205, 564208 }, warcry = { 564206 } },
    mountainKing = { yes = { 551773 }, attack = { 551772 } },
    gryphon = { what = { 551348 }, attack = { 551352, 551349 } },
    wyvern = { what = { 564754 }, attack = { 564755, 564750 } },
}

-- unit -> { WC3 set (or nil), race fallback }
local VOICE = {
    peasant = { "peasant", "humanMale" }, militia = { "peasant", "humanMale" },
    footman = { "footman", "humanMale" }, knight = { nil, "humanMale" }, rifleman = { "rifleman", "dwarf" },
    priest = { nil, "humanFemale" }, sorceress = { nil, "humanFemale" }, mortarTeam = { "mortarTeam", "dwarf" },
    flyingMachine = { nil, "gnome" }, siegeEngine = { nil, "gnome" }, gryphonRider = { "gryphon", "dwarf" },
    spellBreaker = { nil, "humanMale" }, dragonhawk = { nil, "humanMale" },
    paladin = { nil, "humanMale" }, archmage = { nil, "humanMale" }, mountainKing = { "mountainKing", "dwarf" }, bloodMage = { nil, "humanMale" },
    peon = { "peon", "orc" }, grunt = { "grunt", "orc" }, headhunter = { "troll", "troll" }, berserker = { "troll", "troll" },
    demolisher = { nil, "orc" }, raider = { "wolfRider", "orc" }, kodoBeast = { nil, "orc" }, windRider = { "wyvern", "orc" },
    batrider = { nil, "troll" }, shaman = { nil, "orc" }, witchDoctor = { "witchDoctor", "troll" }, spiritWalker = { nil, "tauren" },
    tauren = { "tauren", "tauren" },
    blademaster = { nil, "orc" }, farSeer = { nil, "orc" }, taurenChieftain = { "tauren", "tauren" }, shadowHunter = { "troll", "troll" },
    goblinSapper = { nil, "gnome" }, goblinShredder = { nil, "gnome" },
    darkRanger = { nil, "humanFemale" }, beastmaster = { nil, "orc" }, brewmaster = { nil, "dwarf" }, seaWitch = { nil, "humanFemale" },
    pitLord = { nil, "orc" }, tinker = { nil, "gnome" }, alchemist = { nil, "gnome" }, firelord = { nil, "orc" },
    banshee = { nil, "undeadFemale" }, shade = { nil, "undeadFemale" },
    archer = { nil, "nightelfFemale" }, huntress = { nil, "nightelfFemale" }, dryad = { nil, "nightelfFemale" }, hippogryphRider = { nil, "nightelfFemale" },
    priestess = { nil, "nightelfFemale" }, warden = { nil, "nightelfFemale" },
}

local SFX = {
    underAttackHorde = 567446, underAttackAlliance = 567505,
    built = 567439,          -- quest complete chime ("Job's done" isn't in WoW)
    research = 567478,       -- level-up flourish for "Upgrade complete"
    levelup = 567431,
    heroDied = 567459,
    victory = 567434, defeat = 567459,
    night = 564211,          -- a wolf's howl at nightfall, as in WC3
    error = 567459,
}

-- ------------------------------------------------------------------ playing

local voiceHandle, voiceUntil = nil, 0

local function enabled() return SkirmishDB.sound ~= false end

local function play(id, channel)
    if not id or not enabled() then return end
    local ok, willPlay, handle = pcall(PlaySoundFile, id, channel or "SFX")
    return ok and willPlay and handle
end
So.play = play

local function pick(list) if list and #list > 0 then return list[math.random(#list)] end end

-- the line for a unit and a kind of reply (WC3 set first, then the race's voice)
local function lineFor(def, kind)
    local v = VOICE[def.id]
    if not v then
        if def.faction == "alliance" then v = { nil, "humanMale" } elseif def.faction == "orcs" then v = { nil, "orc" }
        elseif def.faction == "undead" then v = { nil, "undeadMale" } elseif def.faction == "nightelf" then v = { nil, "nightelfMale" } else return nil end
    end
    local own = v[1] and WC3[v[1]]
    local id = own and pick(own[kind])
    if id then return id end
    local race = RACE[v[2]]
    if kind == "ready" or kind == "pissed" then kind = "what" end
    if kind == "warcry" then kind = "attack" end
    return race and pick(race[kind])
end
So.lineFor = lineFor

-- one unit speaks at a time, as in WC3: a new reply cuts off the old one
local function speak(def, kind, force)
    if not enabled() or not def then return end
    local now = GetTime()
    if not force and now < voiceUntil then return end
    local id = lineFor(def, kind)
    if not id then return end
    if voiceHandle and StopSound then pcall(StopSound, voiceHandle, 150) end
    voiceHandle = play(id, "Dialog")
    voiceUntil = now + 0.6
end
So.speak = speak

-- ------------------------------------------------------------------ hooks from the game

local clicks = { id = nil, n = 0, t = 0 }

-- you selected something of yours
function So.selected(w, ids)
    local e = ids and ids[1] and w.ents[ids[1]]
    if not e or e.owner ~= UI.me or e.kind ~= "unit" then return end
    local now = GetTime()
    if clicks.id == e.id and now - clicks.t < 1.5 then clicks.n = clicks.n + 1 else clicks.n = 1 end
    clicks.id, clicks.t = e.id, now
    -- click the same unit over and over and it gets annoyed
    speak(e.def, clicks.n >= 4 and "pissed" or "what", true)
end

-- you gave an order
function So.ordered(w, ids, kind)
    local e = ids and ids[1] and w.ents[ids[1]]
    if not e or e.kind ~= "unit" then return end
    speak(e.def, kind == "attack" and "attack" or "yes", true)
end

local lastWarn = -99
function So.event(w, ev)
    if not enabled() then return end
    local me = UI.me
    local t = ev.t
    if t == "trained" and ev.owner == me then
        local u = w.ents[ev.unit]
        if u then speak(u.def, "ready") end
    elseif t == "built" and ev.owner == me then
        local b = w.ents[ev.unit]
        if b and w.players[me].faction == "orcs" then play(WC3.peon.done[1], "Dialog") else play(SFX.built) end
    elseif (t == "researched" or t == "upgraded") and ev.owner == me then
        play(SFX.research)
    elseif t == "levelup" then
        local u = w.ents[ev.unit]
        if u and u.owner == me then play(SFX.levelup) end
    elseif t == "heroDied" and ev.owner == me then
        play(SFX.heroDied)
    elseif t == "nightfall" then
        play(SFX.night, "Ambience")
    elseif t == "gameOver" then
        play(ev.winner == me and SFX.victory or SFX.defeat, "Master")
    end
end

-- "Our base is under attack!" (throttled by the caller)
function So.underAttack(w)
    local now = GetTime()
    if now - lastWarn < 4 then return end
    lastWarn = now
    play(w.players[UI.me].faction ~= "alliance" and SFX.underAttackHorde or SFX.underAttackAlliance, "Master")
end

function So.error()
    if not enabled() then return end
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST or 846)
end

-- debug: list what each unit says
function So.dump()
    for id, def in pairs(D.Units) do
        if VOICE[id] then UI.say(id .. ": what " .. tostring(lineFor(def, "what")) .. " yes " .. tostring(lineFor(def, "yes")) .. " attack " .. tostring(lineFor(def, "attack"))) end
    end
end
