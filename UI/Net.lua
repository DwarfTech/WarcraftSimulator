-- Warcraft Simulator: 1v1 multiplayer.
-- Both players run the same game. Only the orders travel, as hidden addon whispers, and each
-- order is carried out on both machines at the same game tick (lockstep, the way Warcraft III
-- did it on Battle.net). Every TURN (0.2 s) each side sends the orders it gave, to be carried out
-- DELAY turns later; a side that hasn't heard the other's orders for a turn waits for them.
-- Every few seconds the two games compare a checksum, to catch them drifting apart.

local ADDON, ns = ...
local UI = ns.UI
local E = ns.Engine
local D, S = E.Data, E.Sim

local N = {}
UI.Net = N

local floor, min, max = math.floor, math.min, math.max
local format, byte, char, concat = string.format, string.byte, string.char, table.concat

N.PREFIX = "WarSim1"
N.TURN = 2          -- ticks per turn (0.2 s)
N.DELAY = 2         -- turns between giving an order and it happening (0.4 s)
N.CHUNK = 220       -- payload characters per message (whispers carry 255)
N.HASH_EVERY = 25   -- turns between checksums (5 s)

-- ------------------------------------------------------------------ packing values into text

-- n<number>;  s<string>;  T F Z (true false nil)  e<entity id>;  { key value ... }
local function esc(s) return (s:gsub("[^%w_%.%-]", function(c) return format("%%%02X", byte(c)) end)) end
local function unesc(s) return (s:gsub("%%(%x%x)", function(h) return char(tonumber(h, 16)) end)) end

local function pack(v, out)
    local t = type(v)
    if t == "number" then
        if v == floor(v) and v > -1e15 and v < 1e15 then out[#out + 1] = format("n%d;", v)
        else out[#out + 1] = format("n%.17g;", v) end
    elseif t == "string" then out[#out + 1] = "s" .. esc(v) .. ";"
    elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
    elseif t == "nil" then out[#out + 1] = "Z"
    elseif t == "table" then
        if v.id and v.kind and v.def then out[#out + 1] = format("e%d;", v.id) return end
        out[#out + 1] = "{"
        -- array part first, in order, then the rest sorted (so both sides write the same text)
        local n = #v
        out[#out + 1] = format("n%d;", n)
        for i = 1, n do pack(v[i], out) end
        local keys = {}
        for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n and k == floor(k)) then keys[#keys + 1] = k end end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do pack(k, out) pack(v[k], out) end
        out[#out + 1] = "}"
    end
end
function N.pack(v) local out = {} pack(v, out) return concat(out) end

local function unpackAt(s, i, w)
    local c = s:sub(i, i)
    if c == "n" or c == "s" or c == "e" then
        local j = s:find(";", i, true)
        local body = s:sub(i + 1, j - 1)
        if c == "n" then return tonumber(body), j + 1 end
        if c == "s" then return unesc(body), j + 1 end
        return w and w.ents[tonumber(body)] or { missing = tonumber(body) }, j + 1
    elseif c == "T" then return true, i + 1
    elseif c == "F" then return false, i + 1
    elseif c == "Z" then return nil, i + 1
    elseif c == "{" then
        local t = {}
        local n
        n, i = unpackAt(s, i + 1, w)
        for k = 1, n do t[k], i = unpackAt(s, i, w) end
        while s:sub(i, i) ~= "}" do
            local k, v
            k, i = unpackAt(s, i, w)
            v, i = unpackAt(s, i, w)
            t[k] = v
        end
        return t, i + 1
    end
    error("bad packed text at " .. i)
end
function N.unpack(s, w) return (unpackAt(s, 1, w)) end

-- ------------------------------------------------------------------ the orders

-- every way the interface changes the game. Most take the player as their first argument; the
-- rest take one of the player's units (checked against the sender).
N.BYPLAYER = { command = true, toggleAutocast = true, train = true, setRally = true, cancelTrain = true, uproot = true,
    upgradeBuilding = true, unsummon = true, sellItem = true, research = true, hireHero = true, hire = true, entangle = true,
    cancelBuilding = true, callToArms = true, sellOrDrop = true, buyItem = true, build = true, battleStations = true, backToWorkAll = true }
N.BYUNIT = { learn = true, useItem = true, dropItem = true }

-- carry out one order for player p; returns what the game function returned
function N.run(w, p, fn, args)
    local f = S[fn]
    if not f then return false end
    if N.BYPLAYER[fn] then
        if args[1] ~= p then return false end
    elseif N.BYUNIT[fn] then
        local u = args[1]
        if type(u) ~= "table" or not u.owner or u.owner ~= p then return false end
    else
        return false
    end
    return f(w, unpack(args, 1, args.n or #args))
end

-- the interface gives every order through here: at once in a single-player game, or into the
-- next turn's packet in a multiplayer one
function UI.act(fn, ...)
    local w = UI.w
    if not w then return false end
    local sess = N.session
    if not sess then return S[fn](w, ...) end
    local args = { n = select("#", ...), ... }
    local text = N.pack({ fn, args })
    sess.mine[#sess.mine + 1] = text
    return true
end

-- ------------------------------------------------------------------ a game session (lockstep)

-- send(text) delivers a message to the other side. The session doesn't touch WoW itself, so
-- tests can run two of them against each other.
function N.newSession(w, me, send)
    local sess = { w = w, me = me, other = 3 - me, send = send, turn = 0, tick = 0, acc = 0,
        orders = {}, parts = {}, mine = {}, hashes = {}, waiting = 0, lastHeard = 0, desync = nil }
    for t = 0, N.DELAY - 1 do sess.orders[t] = { [1] = {}, [2] = {} } end
    return sess
end

local function sendTurn(sess, t, list)
    local body = concat(list, "\1")
    local n = max(1, math.ceil(#body / N.CHUNK))
    local log = {}
    for i = 1, n do
        log[i] = format("C~%d~%d~%d~%s", t, i, n, body:sub((i - 1) * N.CHUNK + 1, i * N.CHUNK))
        sess.send(log[i])
    end
    -- kept for a while in case the other side asks again (a lost message)
    sess.sent = sess.sent or {}
    sess.sent[t] = log
    sess.sent[t - 50] = nil
end

local function split(body)
    local out = {}
    if body == "" then return out end
    for part in (body .. "\1"):gmatch("(.-)\1") do out[#out + 1] = part end
    return out
end

-- a checksum of everything that matters
function N.hash(w)
    local h = floor(w.time * 10) % 1000003
    for _, e in ipairs(w.list) do
        if not e.removed then
            local v = (e.id * 7 + floor((e.hp or 0) * 4) * 13 + floor((e.x or 0) * 64) * 31 + floor((e.y or 0) * 64) * 17) % 1000003
            h = (h * 31 + v) % 2147483647
        end
    end
    for p = 1, 2 do
        local pl = w.players[p]
        h = (h * 31 + floor(pl.gold or 0) * 3 + floor(pl.lumber or 0)) % 2147483647
    end
    return h
end

-- a message from the other side
function N.receive(sess, msg)
    sess.lastHeard = 0
    local kind, rest = msg:match("^(%a)~(.*)$")
    if kind == "C" then
        local t, i, n, body = rest:match("^(%d+)~(%d+)~(%d+)~(.*)$")
        t, i, n = tonumber(t), tonumber(i), tonumber(n)
        if not t then return end
        local p = sess.parts[t] or { n = n, got = 0 }
        sess.parts[t] = p
        if not p[i] then p[i] = body p.got = p.got + 1 end
        if p.got >= p.n then
            sess.parts[t] = nil
            sess.orders[t] = sess.orders[t] or {}
            sess.orders[t][sess.other] = split(concat(p, "", 1, p.n))
        end
    elseif kind == "H" then
        local t, h = rest:match("^(%d+)~(%d+)$")
        t, h = tonumber(t), tonumber(h)
        local mine = sess.hashes[t]
        if mine and mine ~= h and not sess.desync then sess.desync = t end
        sess.hashes[t] = sess.hashes[t] or false
        sess.theirHash = sess.theirHash or {}
        sess.theirHash[t] = h
    elseif kind == "R" then
        -- the other side is missing one of our turns: send it again
        local t = tonumber(rest:match("^(%d+)"))
        for _, m in ipairs(sess.sent and sess.sent[t] or {}) do sess.send(m) end
    elseif kind == "Q" then
        sess.left = true
    end
end

-- move the game on by up to `elapsed` seconds; onStep(w) is called after each tick (events),
-- onError(why) for orders of yours that turned out not to be possible
function N.advance(sess, elapsed, onStep, onError)
    local w = sess.w
    sess.lastHeard = sess.lastHeard + elapsed
    if w.over then return end
    sess.acc = min(sess.acc + elapsed, D.TICK * 6)
    local stepped = 0
    while sess.acc >= D.TICK and stepped < 6 do
        if sess.tick == 0 then
            -- the start of a turn: everyone's orders for it must be here
            local o = sess.orders[sess.turn]
            if not (o and o[1] and o[2]) then
                sess.waiting = sess.waiting + elapsed
                -- still nothing after a second and a half: ask for that turn again
                sess.askT = (sess.askT or 0) + elapsed
                if sess.waiting > 1.5 and sess.askT > 1.5 then
                    sess.askT = 0
                    sess.send(format("R~%d", sess.turn))
                end
                return
            end
            sess.askT = 0
            sess.waiting = 0
            -- our orders for DELAY turns from now go out now
            local ahead = sess.turn + N.DELAY
            sess.orders[ahead] = sess.orders[ahead] or {}
            sess.orders[ahead][sess.me] = sess.mine
            sendTurn(sess, ahead, sess.mine)
            sess.mine = {}
            -- this turn's orders, player 1's first, the same on both machines
            for p = 1, 2 do
                for _, text in ipairs(o[p]) do
                    local ok, cmd = pcall(N.unpack, text, w)
                    if ok and type(cmd) == "table" and type(cmd[1]) == "string" and type(cmd[2]) == "table" then
                        local good, r1, r2 = pcall(N.run, w, p, cmd[1], cmd[2])
                        if p == sess.me and onError and good and r1 == false and r2 then onError(r2) end
                    end
                end
            end
            sess.orders[sess.turn] = nil
            if sess.turn % N.HASH_EVERY == 0 then
                local h = N.hash(w)
                sess.hashes[sess.turn] = h
                if sess.theirHash and sess.theirHash[sess.turn] and sess.theirHash[sess.turn] ~= h and not sess.desync then sess.desync = sess.turn end
                sess.send(format("H~%d~%d", sess.turn, h))
            end
        end
        S.currentWorld = w
        S.step(w, D.TICK)
        if onStep then onStep(w) end
        sess.acc = sess.acc - D.TICK
        stepped = stepped + 1
        sess.tick = sess.tick + 1
        if sess.tick >= N.TURN then sess.tick = 0 sess.turn = sess.turn + 1 end
        if w.over then return end
    end
end

-- ------------------------------------------------------------------ WoW: inviting, accepting, playing

local VERSION = ((C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata or function() return "?" end)(ADDON, "Version") or "?"
N.VERSION = VERSION

local function short(name) return (name or ""):match("^([^%-]+)") or name end
local function same(a, b) return a and b and short(a):lower() == short(b):lower() end

local function whisper(target, msg)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(N.PREFIX, msg, "WHISPER", target)
    elseif SendAddonMessage then SendAddonMessage(N.PREFIX, msg, "WHISPER", target) end
end

-- invite someone (by name) to a game
function N.invite(name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
    if not name or name == "" then return false, "Type the name of the player to invite." end
    if same(name, UnitName("player")) then return false, "You can't invite yourself." end
    N.pending = { peer = name, t = 0, host = true }
    whisper(name, format("I~%s~%s", VERSION, SkirmishDB.faction or "alliance"))
    return true
end

function N.cancelInvite()
    if N.pending and N.pending.peer then whisper(N.pending.peer, "D~cancel") end
    N.pending = nil
end

-- the host starts the game once the invitation is accepted
local function hostStart(peer, theirFaction)
    local seed = floor(GetTime() * 1000) % 100000 + 1
    local map = SkirmishDB.map or "classic"
    local fog = SkirmishDB.fog == false and "0" or "1"
    local mine = SkirmishDB.faction or "alliance"
    whisper(peer, format("S~%d~%s~%s~%s~%s", seed, map, fog, mine, theirFaction))
    N.begin(peer, 1, { seed = seed, map = map, fog = fog == "1", factions = { mine, theirFaction } })
end

-- both sides: start the shared game
function N.begin(peer, me, o)
    N.pending = nil
    N.offlineSaid = nil
    if UI.Hud and UI.Hud.hideMulti then UI.Hud.hideMulti() end
    if not UI.built or not UI.frame:IsShown() then UI.Toggle() end
    UI.newGame({ net = true, me = me, seed = o.seed, map = o.map, fog = o.fog, factions = o.factions })
    N.peer = peer
    N.session = N.newSession(UI.w, me, function(msg) whisper(peer, msg) end)
    UI.say(format("multiplayer game against %s started. You are %s.", short(peer), D.Factions[o.factions[me]].name))
end

-- leave the game (counts as a loss)
function N.leave()
    local sess = N.session
    if not sess then return end
    whisper(N.peer, "Q~left")
    local w = sess.w
    if w and not w.over then
        w.over = true
        w.winner = sess.other
        S.event(w, { t = "gameOver", winner = sess.other })
    end
    N.session = nil
end

-- the game has ended: back to single player afterwards
function N.finished()
    N.session = nil
end

local function onAddonMessage(prefix, msg, channel, sender)
    if prefix ~= N.PREFIX then return end
    local kind = msg:sub(1, 1)
    local sess = N.session
    if sess and same(sender, N.peer) and (kind == "C" or kind == "H" or kind == "Q" or kind == "R") then
        N.receive(sess, msg)
        if kind == "Q" then
            local w = sess.w
            if not w.over then
                w.over = true
                w.winner = sess.me
                S.event(w, { t = "gameOver", winner = sess.me })
            end
            UI.say(short(sender) .. " left the game.")
        end
        return
    end
    local f = { strsplit("~", msg) }
    if kind == "I" then
        -- an invitation
        if sess then whisper(sender, "D~busy") return end
        if f[2] ~= VERSION then
            whisper(sender, "D~version~" .. VERSION)
            UI.say(format("%s invited you to a game but has version %s (you have %s). You both need the same version.", short(sender), f[2] or "?", VERSION))
            return
        end
        N.incoming = { peer = sender, faction = f[3] }
        StaticPopupDialogs.WARSIM_INVITE = StaticPopupDialogs.WARSIM_INVITE or {
            text = "%s invites you to a 1v1 game of Warcraft Simulator.\nYou will play as %s (change it in the game's start screen).",
            button1 = ACCEPT or "Accept", button2 = DECLINE or "Decline", timeout = 60, whileDead = true, hideOnEscape = true,
            OnAccept = function() N.accept() end,
            OnCancel = function() if N.incoming then whisper(N.incoming.peer, "D~declined") N.incoming = nil end end,
        }
        local mine = D.Factions[SkirmishDB.faction or "alliance"]
        StaticPopup_Show("WARSIM_INVITE", short(sender), mine and mine.name or "Alliance")
    elseif kind == "A" then
        -- our invitation was accepted
        local p = N.pending
        if not (p and p.host and same(sender, p.peer)) then return end
        if f[2] ~= VERSION then
            UI.say(format("%s has version %s; you have %s. You both need the same version.", short(sender), f[2] or "?", VERSION))
            N.pending = nil
            return
        end
        hostStart(sender, D.Factions[f[3]] and f[3] or "orcs")
    elseif kind == "S" then
        -- the host started the game
        local inc = N.joining
        if not (inc and same(sender, inc.peer)) then return end
        N.joining = nil
        N.begin(sender, 2, { seed = tonumber(f[2]), map = f[3], fog = f[4] == "1", factions = { f[5], f[6] } })
    elseif kind == "D" then
        local p = N.pending
        if p and same(sender, p.peer) then
            local why = f[2] == "busy" and "is already in a game" or (f[2] == "version" and ("has a different version (" .. (f[3] or "?") .. ")") or "declined")
            UI.say(short(sender) .. " " .. why .. ".")
            if UI.Hud and UI.Hud.multiStatus then UI.Hud.multiStatus(short(sender) .. " " .. why .. ".") end
            N.pending = nil
        end
        if N.incoming and same(sender, N.incoming.peer) then
            N.incoming = nil
            StaticPopup_Hide("WARSIM_INVITE")
        end
    end
end

function N.accept()
    local inc = N.incoming
    if not inc then return end
    N.incoming = nil
    N.joining = { peer = inc.peer, t = 0 }
    whisper(inc.peer, format("A~%s~%s", VERSION, SkirmishDB.faction or "alliance"))
    UI.say("joining " .. short(inc.peer) .. "'s game...")
end

-- drive the shared game every frame, even while the window is closed (the other player is still playing)
local function onUpdate(_, elapsed)
    if elapsed > 0.25 then elapsed = 0.25 end
    local p = N.pending
    if p then
        p.t = p.t + elapsed
        if p.t > 60 then
            UI.say(short(p.peer) .. " didn't answer the invitation.")
            if UI.Hud and UI.Hud.multiStatus then UI.Hud.multiStatus(short(p.peer) .. " didn't answer.") end
            N.pending = nil
        end
    end
    if N.joining then
        N.joining.t = N.joining.t + elapsed
        if N.joining.t > 20 then UI.say("the game didn't start.") N.joining = nil end
    end
    local sess = N.session
    if not sess then return end
    N.advance(sess, elapsed, UI.handleEvents, function(why) if UI.Hud then UI.Hud.error(why) end end)
    UI.acc = sess.acc
    if sess.desync and not sess.desyncSaid then
        sess.desyncSaid = true
        UI.say("|cffff4040the two games have drifted apart (out of sync).|r Please tell the addon's author what happened just before.")
    end
    if sess.w.over then N.finished() end
end

function N.init()
    if not CreateFrame then return end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(N.PREFIX)
    elseif RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(N.PREFIX) end
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender) onAddonMessage(prefix, msg, channel, sender) end)
    f:SetScript("OnUpdate", onUpdate)
    N.frame = f
    -- whispering someone who has gone offline makes the server say so each time: say it once
    if ChatFrame_AddMessageEventFilter and ERR_CHAT_PLAYER_NOT_FOUND_S then
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
            local peer = (N.session and N.peer) or (N.pending and N.pending.peer)
            if peer and (msg == format(ERR_CHAT_PLAYER_NOT_FOUND_S, short(peer)) or msg == format(ERR_CHAT_PLAYER_NOT_FOUND_S, peer)) then
                if N.offlineSaid then return true end
                N.offlineSaid = true
                return false
            end
        end)
    end
end
N.init()
