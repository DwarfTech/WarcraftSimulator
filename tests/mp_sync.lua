-- Runs two copies of the game linked by a fake network (random delay, uneven frame rates,
-- optional message loss with DROP=0.03) with a small scripted player on each side, and checks
-- that both games stay identical. Usage: lua5.1 mp_sync.lua <addon folder> [seed] [race1] [race2] [minutes]
local root = arg[1]
local seed = tonumber(arg[2]) or 1
local f1, f2 = arg[3] or "orcs", arg[4] or "nightelf"
local minutes = tonumber(arg[5]) or 8
local ns = { UI = {} }
for _, f in ipairs({ "Engine/Data.lua", "Engine/Sizes.lua", "Engine/Map.lua", "Engine/WC3Maps.lua", "Engine/Sim.lua", "Engine/Tech.lua", "Engine/Heroes.lua", "Engine/Spells.lua", "Engine/Neutral.lua", "Engine/Tavern.lua", "Engine/Rules.lua", "Engine/Undead.lua", "Engine/NightElf.lua", "Engine/AI.lua", "UI/Net.lua" }) do
  assert(loadfile(root .. "/" .. f))("Skirmish", ns)
end
local S, D, M, N = ns.Engine.Sim, ns.Engine.Data, ns.Engine.Map, ns.UI.Net
-- serializer round trip
local t = { "command", { n = 3, 1, { 4, 5, 6 }, { type = "smart", x = 12.345678901234567, y = 1 / 3, queue = false, tree = nil } } }
local back = N.unpack(N.pack(t))
assert(back[2][3].x == t[2][3].x and back[2][3].y == t[2][3].y and back[2][2][3] == 6 and back[2].n == 3, "round trip")
local seedRng = 12345
local function rnd() seedRng = (seedRng * 1103515245 + 12345) % 2147483648 return seedRng / 2147483648 end

local map = os.getenv("MAP")
local w = { S.newWorld({ seed = seed, factions = { f1, f2 }, creeps = true, map = map }), nil }
w[2] = S.newWorld({ seed = seed, factions = { f1, f2 }, creeps = true, map = map })
w[1].net, w[2].net = true, true
for k = 1, 2 do for p = 1, 2 do w[k].players[p].gold, w[k].players[p].lumber = 20000, 20000 end end
local inflight = {}   -- { at, to, msg }
local clock = 0
local sess = {}
for p = 1, 2 do
  sess[p] = N.newSession(w[p], p, function(msg)
    assert(#msg <= 255, "message too long " .. #msg)
    if rnd() > (tonumber(os.getenv('DROP') or 0)) then inflight[#inflight + 1] = { at = clock + 0.05 + rnd() * 0.3, to = 3 - p, msg = msg } end
  end)
end
-- a tiny scripted player that only gives orders through the lockstep packets
local function order(p, fn, ...)
  local args = { n = select("#", ...), ... }
  local s = sess[p]
  s.mine[#s.mine + 1] = N.pack({ fn, args })
end
local botT = { 0, 0 }
local botAltar = {}
local function bot(p, dt)
  local ww = w[p]
  botT[p] = botT[p] - dt
  if botT[p] > 0 then return end
  botT[p] = 1
  local F = D.Factions[ww.players[p].faction]
  local pl = ww.players[p]
  local hall, workers, army, idle, barracks = nil, 0, {}, {}, {}
  for _, e in ipairs(ww.list) do
    if e.owner == p and S.alive(e) then
      if e.kind == "building" and e.def.hall then hall = e end
      if e.kind == "building" and e.def.id == F.barracks and e.built then barracks[#barracks + 1] = e end
      if e.kind == "unit" and e.def.worker then workers = workers + 1 if not e.order then idle[#idle + 1] = e.id end end
      if e.kind == "unit" and not e.def.worker and not e.def.hero and e.def.dmin then army[#army + 1] = e.id end
    end
  end
  if not hall then return end
  if workers < 10 and #hall.queue == 0 then order(p, "train", p, hall.id, F.worker) end
  local mine for _, e in ipairs(ww.list) do if e.kind == "mine" and (not mine or ((e.x - hall.x) ^ 2 + (e.y - hall.y) ^ 2 < (mine.x - hall.x) ^ 2 + (mine.y - hall.y) ^ 2)) then mine = e end end
  if #idle > 0 and mine then
    local g, l = {}, {}
    for i, id in ipairs(idle) do if (botT.n or 0) % 2 == 0 and i % 2 == 0 then l[#l + 1] = id else g[#g + 1] = id end end
    botT.n = (botT.n or 0) + 1
    if #g > 0 then order(p, "command", p, g, { type = "smart", target = (mine.haunted or mine.id), x = mine.x, y = mine.y }) end
    local tree = M.nearestTree(ww, hall.x, hall.y, 16)
    if #l > 0 and tree then order(p, "command", p, l, { type = "gather", tree = tree }) end
  end
  local want = nil
  if pl.used >= pl.cap - 4 and pl.gold > 100 and (botT.farmT or 0) <= ww.time then want = F.farm botT.farmT = ww.time + 25
  elseif #barracks < 2 and pl.gold > 200 and pl.lumber > 60 then want = F.barracks end
  if want then
    local builder
    for _, e in ipairs(ww.list) do if e.owner == p and e.kind == "unit" and e.def.worker and S.alive(e) then builder = e end end
    if builder then
      for r = 5, 10 do
        local done
        for k = 1, 16 do
          local a = k / 16 * 2 * math.pi
          local tx, ty = math.floor(hall.x + math.cos(a) * r), math.floor(hall.y + math.sin(a) * r)
          if S.canPlaceFor(ww, p, want, tx, ty) then order(p, "build", p, builder.id, want, tx, ty, false) done = true break end
        end
        if done then break end
      end
    end
  end
  -- a hero from the altar, and spend its skill points
  for _, e in ipairs(ww.list) do
    if e.owner == p and S.alive(e) and e.kind == "building" and e.def.id == F.altar and e.built and #e.queue == 0 and not pl.heroAlive then
      order(p, "train", p, e.id, e.def.trains[1 + (p + seed) % #e.def.trains])
    end
    if e.owner == p and S.alive(e) and e.def.hero and (e.points or 0) > 0 then
      for _, ab in ipairs(e.def.abilities) do order(p, "learn", e, ab) end
      army[#army + 1] = e.id
    end
  end
  if not botAltar[p] and pl.gold > 200 then
    botAltar[p] = true
    local builder for _, e in ipairs(ww.list) do if e.owner == p and e.kind == "unit" and e.def.worker and S.alive(e) then builder = e end end
    for r = 6, 12 do local done
      for k = 1, 16 do local a = k / 16 * 2 * math.pi local tx, ty = math.floor(hall.x + math.cos(a) * r), math.floor(hall.y + math.sin(a) * r)
        if builder and S.canPlaceFor(ww, p, F.altar, tx, ty) then order(p, "build", p, builder.id, F.altar, tx, ty, false) done = true break end end
      if done then break end end
  end
  for _, b in ipairs(barracks) do if #b.queue < 2 then order(p, "train", p, b.id, b.def.trains[1]) end end
  if #army >= 6 then
    local eh for _, e in ipairs(ww.list) do if e.owner == 3 - p and e.kind == "building" and e.def.hall and S.alive(e) then eh = e end end
    if eh then order(p, "command", p, army, { type = "amove", x = eh.x + rnd() * 0.01, y = eh.y }) end
  end
end
local dtFor = { 1 / 30, 1 / 47 }
local endT = minutes * 60
while clock < endT * 1.3 do
  local dt = 1 / 60
  clock = clock + dt
  -- deliver messages
  local keep = {}
  for _, m in ipairs(inflight) do if m.at <= clock then N.receive(sess[m.to], m.msg) else keep[#keep + 1] = m end end
  inflight = keep
  for p = 1, 2 do
    -- uneven frame rates: client p runs its frame every dtFor[p]
    sess[p].frameAcc = (sess[p].frameAcc or 0) + dt
    if sess[p].frameAcc >= dtFor[p] then
      local el = sess[p].frameAcc
      sess[p].frameAcc = 0
      bot(p, el)
      N.advance(sess[p], el, function(ww) ww.events = {} end)
    end
  end
  if w[1].over and w[2].over then break end
  if w[1].time >= endT and w[2].time >= endT then break end
end
local common = 0
for t, h in pairs(sess[1].hashes) do if sess[2].hashes[t] then common = common + 1 assert(h == sess[2].hashes[t], "hash differs at turn " .. t) end end
print(string.format("t1 %.1f t2 %.1f turns %d/%d common hashes %d desync %s/%s over %s/%s winner %s/%s units %d/%d",
  w[1].time, w[2].time, sess[1].turn, sess[2].turn, common, tostring(sess[1].desync), tostring(sess[2].desync), tostring(w[1].over), tostring(w[2].over), tostring(w[1].winner), tostring(w[2].winner), #w[1].list, #w[2].list))
-- the army sizes at the end
for p = 1, 2 do local n = 0 for _, e in ipairs(w[1].list) do if e.owner == p and e.kind == "unit" and S.alive(e) then n = n + 1 end end io.write("P", p, " units ", n, "  ") end print()
for p = 1, 2 do
  local c = {} for _, e in ipairs(w[1].list) do if e.owner == p and S.alive(e) then c[e.def.id] = (c[e.def.id] or 0) + 1 end end
  local t = {} for k, v in pairs(c) do t[#t + 1] = k .. "=" .. v end table.sort(t)
  print("P" .. p, w[1].players[p].gold, w[1].players[p].lumber, table.concat(t, " "))
end

assert(common > 0, "no checksums compared")
assert(not sess[1].desync and not sess[2].desync, "desync")
print("OK")
