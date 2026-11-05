-- Skirmish engine: the map grid, map generation and pathfinding.
-- Tiles are 1..W by 1..H. A unit standing in tile (x, y) has a position between x-1 and x.
-- block[i] holds what stands on a tile: nil (open), "tree", or an entity (building / gold mine).

local _, ns = ...
local E = ns.Engine
local D = E.Data
local M = {}
E.Map = M

local floor, abs, max, min, sqrt = math.floor, math.abs, math.max, math.min, math.sqrt

function M.idx(w, x, y) return (y - 1) * w + x end

-- a small seeded random number generator (the same seed always gives the same map)
function M.rng(seed)
    local s = (seed or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    local r = {}
    function r.next() s = (s * 16807) % 2147483647 return s end
    function r.float() return r.next() / 2147483647 end
    function r.int(a, b) return a + r.next() % (b - a + 1) end
    return r
end

-- ------------------------------------------------------------------ queries

function M.inside(w, x, y) return x >= 1 and y >= 1 and x <= w.w and y <= w.h end

function M.blockAt(w, x, y)
    if not M.inside(w, x, y) then return "edge" end
    return w.block[(y - 1) * w.w + x]
end

function M.walkable(w, x, y)
    if x < 1 or y < 1 or x > w.w or y > w.h then return false end
    return w.block[(y - 1) * w.w + x] == nil
end

function M.tileOf(px, py) return floor(px) + 1, floor(py) + 1 end

function M.isTree(w, x, y) return M.inside(w, x, y) and w.block[(y - 1) * w.w + x] == "tree" end

-- can a footprint of `size` with its top-left tile at (x, y) be placed?
-- the cliff level of the tile under a map position (WC3 maps; 0 on the generated maps)
function M.levelAt(w, x, y)
    local L = w.layer
    if not L then return 0 end
    local tx, ty = floor(x) + 1, floor(y) + 1
    return L[(ty - 1) * w.w + tx] or 0
end

function M.canPlace(w, x, y, size)
    for yy = y, y + size - 1 do
        for xx = x, x + size - 1 do
            if not M.walkable(w, xx, yy) then return false end
            if w.noBuild and w.noBuild[(yy - 1) * w.w + xx] then return false end
        end
    end
    return true
end

function M.setRect(w, x, y, size, what)
    for yy = y, y + size - 1 do
        for xx = x, x + size - 1 do
            if M.inside(w, xx, yy) then w.block[(yy - 1) * w.w + xx] = what end
        end
    end
    w.blockVersion = (w.blockVersion or 0) + 1
end

-- ------------------------------------------------------------------ pathfinding (A* on an 8-way grid)

local heapPush, heapPop
do
    function heapPush(h, n, f)
        local i = #h + 1
        h[i] = n
        f[n] = f[n]
        while i > 1 do
            local p = floor(i / 2)
            if f[h[p]] <= f[h[i]] then break end
            h[p], h[i] = h[i], h[p]
            i = p
        end
    end
    function heapPop(h, f)
        local top = h[1]
        local last = h[#h]
        h[#h] = nil
        if #h > 0 then
            h[1] = last
            local i, n = 1, #h
            while true do
                local l, r, s = i * 2, i * 2 + 1, i
                if l <= n and f[h[l]] < f[h[s]] then s = l end
                if r <= n and f[h[r]] < f[h[s]] then s = r end
                if s == i then break end
                h[s], h[i] = h[i], h[s]
                i = s
            end
        end
        return top
    end
end

local DIRS = { { 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 },
               { 1, 1, 1.414 }, { 1, -1, 1.414 }, { -1, 1, 1.414 }, { -1, -1, 1.414 } }

-- straight-line walk check between tile centres (used to smooth paths)
function M.clearLine(w, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local steps = max(abs(dx), abs(dy)) * 2
    if steps == 0 then return true end
    for i = 1, steps do
        local t = i / steps
        local x, y = x1 + dx * t, y1 + dy * t
        -- check the tiles the unit's body would brush against
        local tx, ty = floor(x + 0.5), floor(y + 0.5)
        if not M.walkable(w, tx, ty) then return false end
        local fx, fy = x + 0.5 - tx, y + 0.5 - ty
        if fx < 0.3 and not M.walkable(w, tx - 1, ty) then return false end
        if fx > 0.7 and not M.walkable(w, tx + 1, ty) then return false end
        if fy < 0.3 and not M.walkable(w, tx, ty - 1) then return false end
        if fy > 0.7 and not M.walkable(w, tx, ty + 1) then return false end
    end
    return true
end

-- nearest open tile to (x, y), searching outward
function M.nearestOpen(w, x, y, maxR)
    x, y = max(1, min(w.w, x)), max(1, min(w.h, y))
    if M.walkable(w, x, y) then return x, y end
    for r = 1, maxR or 12 do
        local best, bd
        for yy = y - r, y + r do
            for xx = x - r, x + r do
                if (abs(xx - x) == r or abs(yy - y) == r) and M.walkable(w, xx, yy) then
                    local d = (xx - x) ^ 2 + (yy - y) ^ 2
                    if not bd or d < bd then best, bd = { xx, yy }, d end
                end
            end
        end
        if best then return best[1], best[2] end
    end
    return nil
end

-- Find a path from a tile to a goal. goal = { x, y } for a tile, or { x1, y1, x2, y2 } for a
-- blocked rectangle (a building, mine or tree): any open tile touching it will do.
-- Returns a list of { x, y } positions (tile centres, in map units) or nil.
function M.findPath(w, sx, sy, goal, maxNodes)
    local W = w.w
    local gx1, gy1, gx2, gy2 = goal[1], goal[2], goal[3] or goal[1], goal[4] or goal[2]
    local rectGoal = goal[3] ~= nil
    if not rectGoal and not M.walkable(w, gx1, gy1) then
        local nx, ny = M.nearestOpen(w, gx1, gy1, 10)
        if not nx then return nil end
        gx1, gy1, gx2, gy2 = nx, ny, nx, ny
    end
    local function isGoal(x, y)
        if rectGoal then
            return x >= gx1 - 1 and x <= gx2 + 1 and y >= gy1 - 1 and y <= gy2 + 1
        end
        return x == gx1 and y == gy1
    end
    local hx, hy = (gx1 + gx2) / 2, (gy1 + gy2) / 2
    local function h(x, y)
        local dx, dy = abs(x - hx), abs(y - hy)
        return max(dx, dy) + 0.414 * min(dx, dy)
    end
    if not M.walkable(w, sx, sy) then
        local nx, ny = M.nearestOpen(w, sx, sy, 4)
        if not nx then return nil end
        sx, sy = nx, ny
    end
    local start = (sy - 1) * W + sx
    local g, f, from, closed = { [start] = 0 }, { [start] = h(sx, sy) }, {}, {}
    local open = {}
    heapPush(open, start, f)
    local nodes, best, bestH = 0, start, h(sx, sy)
    local found
    while #open > 0 do
        local cur = heapPop(open, f)
        if not closed[cur] then
            closed[cur] = true
            local cx, cy = (cur - 1) % W + 1, floor((cur - 1) / W) + 1
            if isGoal(cx, cy) then found = cur break end
            nodes = nodes + 1
            if nodes > (maxNodes or 3000) then break end
            if w.nodeBudget then w.nodeBudget = w.nodeBudget - 1 end
            local ch = h(cx, cy)
            if ch < bestH then best, bestH = cur, ch end
            for i = 1, 8 do
                local d = DIRS[i]
                local nx, ny = cx + d[1], cy + d[2]
                if M.walkable(w, nx, ny) and (i <= 4 or (M.walkable(w, cx + d[1], cy) and M.walkable(w, cx, cy + d[2]))) then
                    local n = (ny - 1) * W + nx
                    if not closed[n] then
                        local ng = g[cur] + d[3]
                        if not g[n] or ng < g[n] then
                            g[n] = ng
                            f[n] = ng + h(nx, ny) * 1.05
                            from[n] = cur
                            heapPush(open, n, f)
                        end
                    end
                end
            end
        end
    end
    local last = found or best
    if last == start and not found then return nil end
    -- walk back
    local tiles = {}
    local n = last
    while n do
        tiles[#tiles + 1] = n
        n = from[n]
    end
    -- reverse into positions, smoothing out unneeded corners
    local raw = {}
    for i = #tiles, 1, -1 do
        local t = tiles[i]
        raw[#raw + 1] = { (t - 1) % W + 1, floor((t - 1) / W) + 1 }
    end
    local path = {}
    local i = 1
    while i < #raw do
        local j = #raw
        while j > i + 1 and not M.clearLine(w, raw[i][1], raw[i][2], raw[j][1], raw[j][2]) do j = j - 1 end
        path[#path + 1] = { raw[j][1] - 0.5, raw[j][2] - 0.5 }
        i = j
    end
    return path, found ~= nil
end

-- ------------------------------------------------------------------ map generation

-- The map is mirrored corner to corner so both bases are fair. Player 1 starts bottom-left,
-- player 2 top-right; two spare gold mines sit in the other corners.
-- the maps to choose from
D.MAPS = {
    { id = "classic", name = "Twin Groves (64x64)", size = 64 },
    { id = "crossing", name = "Lordaeron Crossing (80x80)", size = 80 },
}

-- Blizzard's own melee maps (Engine/WC3Maps.lua, converted from the real map files)
function M.loadWC3(w, seed, m)
    local W, H = m.w, m.h
    -- top-left tile of a footprint centred at a map position
    local function TL(c, size) return floor(c - size / 2 + 0.5) + 1 end
    w.w, w.h, w.mapName, w.tileset = W, H, m.name, m.tileset
    w.block, w.trees, w.treeKind, w.ground = {}, {}, {}, {}
    w.water, w.cliff, w.shallow, w.noBuild, w.layer = {}, {}, {}, {}, {}
    local r = M.rng(seed)
    for y = 1, H do
        local row, lv = m.rows[y], m.lv and m.lv[y]
        for x = 1, W do
            local i = (y - 1) * W + x
            local c = row:sub(x, x)
            if c == "T" then
                w.block[i] = "tree" w.trees[i] = D.TREE_LUMBER w.treeKind[i] = r.int(1, #D.TREES)
            elseif c == "W" then w.block[i] = "water" w.water[i] = true
            elseif c == "C" then w.block[i] = "cliff" w.cliff[i] = true
            elseif c == "w" then w.shallow[i] = true w.noBuild[i] = true end
            if lv then w.layer[i] = tonumber(lv:sub(x, x)) or 0 end
            w.ground[i] = r.int(1, 100)
        end
    end
    -- which start each player gets is random, as in WC3
    local starts = {}
    for _, s in ipairs(m.starts) do starts[#starts + 1] = s end
    if #starts >= 2 and r.int(1, 2) == 2 then starts[1], starts[2] = starts[2], starts[1] end
    local used = {}
    w.starts = {}
    for p = 1, 2 do
        local s = starts[p]
        local best, bd
        for k, mn in ipairs(m.mines) do
            local d = (mn[1] - s[1]) ^ 2 + (mn[2] - s[2]) ^ 2
            if not used[k] and (not bd or d < bd) then best, bd = k, d end
        end
        used[best] = true
        local mn = m.mines[best]
        w.starts[p] = { hall = { TL(s[1], 4), TL(s[2], 4) }, mine = { TL(mn[1], 3), TL(mn[2], 3) }, gold = mn[3] }
    end
    w.expansions = {}
    for k, mn in ipairs(m.mines) do
        if not used[k] then w.expansions[#w.expansions + 1] = { TL(mn[1], 3), TL(mn[2], 3), gold = mn[3] } end
    end
    -- creep camps exactly as Blizzard placed them, with their item drops
    w.campSpots, w.neutralSpots = {}, {}
    for _, c in ipairs(m.camps) do
        local lv = 0
        for _, u in ipairs(c.units) do local d = D.Units[u[1]] lv = lv + (d and d.level or 1) end
        w.campSpots[#w.campSpots + 1] = { x = c.x, y = c.y, units = c.units, kind = lv <= 9 and "green" or (lv <= 19 and "orange" or "red") }
    end
    for _, sh in ipairs(m.shops) do
        local def = D.Buildings[sh[1]]
        if def then
            w.neutralSpots[#w.neutralSpots + 1] = { id = sh[1], x = TL(sh[2], def.size), y = TL(sh[3], def.size) }
        end
    end
    w.blockVersion = 1
end

function M.generate(w, seed, style)
    if D.WC3MAPS and D.WC3MAPS[style] then return M.loadWC3(w, seed, D.WC3MAPS[style]) end
    if style == "crossing" then return M.generateCrossing(w, seed) end
    local W, H = D.MAP_W, D.MAP_H
    w.w, w.h = W, H
    w.block = {}
    w.trees = {}       -- tile index -> lumber left
    w.treeKind = {}    -- tile index -> which tree model
    w.ground = {}      -- tile index -> ground variant (for drawing)
    local r = M.rng(seed)
    local function setTree(x, y)
        if not M.inside(w, x, y) then return end
        local i = (y - 1) * W + x
        if w.block[i] == nil then
            w.block[i] = "tree"
            w.trees[i] = D.TREE_LUMBER
            w.treeKind[i] = r.int(1, #D.TREES)
        end
    end
    local function clear(x, y)
        if not M.inside(w, x, y) then return end
        local i = (y - 1) * W + x
        if w.block[i] == "tree" then w.block[i] = nil w.trees[i] = nil w.treeKind[i] = nil end
    end
    -- mirrored helpers: anything put at (x, y) is also put at (W+1-y, H+1-x)... we mirror
    -- through the centre: (x, y) <-> (W+1-x, H+1-y)
    local function both(fn, x, y) fn(x, y) fn(W + 1 - x, H + 1 - y) end

    -- forest border
    for y = 1, H do
        for x = 1, W do
            if x <= 2 or y <= 2 or x >= W - 1 or y >= H - 1 then setTree(x, y) end
        end
    end
    -- tree clumps (placed on one half, mirrored)
    for _ = 1, 26 do
        local cx, cy = r.int(4, W - 4), r.int(4, H - 4)
        if cx + cy < W + 4 then
            local rad = r.float() * 2.2 + 1.2
            for y = cy - 3, cy + 3 do
                for x = cx - 3, cx + 3 do
                    if (x - cx) ^ 2 + (y - cy) ^ 2 <= rad * rad and r.float() < 0.85 then both(setTree, x, y) end
                end
            end
        end
    end
    -- thick tree lines behind each base (lumber close to home)
    for i = 0, 10 do
        for d = 0, 2 do
            both(setTree, 3 + d, 40 + i)
            both(setTree, 14 + i, H - 2 - d)
        end
    end
    -- clear the base areas and the middle
    local starts = { { 12, 52 }, { W + 1 - 12, H + 1 - 52 } }
    for _, s in ipairs(starts) do
        for y = s[2] - 8, s[2] + 7 do
            for x = s[1] - 8, s[1] + 8 do
                if (x - s[1]) ^ 2 + (y - s[2]) ^ 2 < 64 then clear(x, y) end
            end
        end
    end
    for _, c in ipairs({ { 12, 12 }, { W + 1 - 12, H + 1 - 12 }, { 32, 32 } }) do
        for y = c[2] - 5, c[2] + 5 do
            for x = c[1] - 5, c[1] + 5 do
                if (x - c[1]) ^ 2 + (y - c[2]) ^ 2 < 25 then clear(x, y) end
            end
        end
    end
    -- make sure there is a wide road from base to base and to each expansion
    local function carve(x1, y1, x2, y2)
        local steps = max(abs(x2 - x1), abs(y2 - y1))
        for i = 0, steps do
            local x = floor(x1 + (x2 - x1) * i / steps + 0.5)
            local y = floor(y1 + (y2 - y1) * i / steps + 0.5)
            for yy = y - 1, y + 1 do for xx = x - 1, x + 1 do
                if xx > 2 and yy > 2 and xx < W - 1 and yy < H - 1 then clear(xx, yy) end
            end end
        end
    end
    carve(12, 52, 32, 32) carve(32, 32, W + 1 - 12, H + 1 - 52)
    carve(12, 52, 12, 12) carve(W + 1 - 12, H + 1 - 52, W + 1 - 12, H + 1 - 12)
    carve(12, 12, 32, 32) carve(W + 1 - 12, H + 1 - 12, 32, 32)

    -- creep camps (mirrored, the same creeps on both sides) and the neutral buildings
    w.campSpots, w.neutralSpots = {}, {}
    local function clearRound(cx, cy, rad)
        for y = floor(cy - rad), floor(cy + rad) + 1 do
            for x = floor(cx - rad), floor(cx + rad) + 1 do
                if (x - 0.5 - cx) ^ 2 + (y - 0.5 - cy) ^ 2 <= rad * rad then clear(x, y) end
            end
        end
    end
    local camps = { { 21.5, 43.5, "green" }, { 6.5, 30.5, "green" }, { 13.5, 13.5, "orange" }, { 25.5, 26.5, "red" } }
    for _, c in ipairs(camps) do
        local pick = r.int(1, 100)
        for _, p in ipairs({ { c[1], c[2] }, { W - c[1], H - c[2] } }) do
            clearRound(p[1], p[2], 3.2)
            w.campSpots[#w.campSpots + 1] = { x = p[1], y = p[2], kind = c[3], pick = pick }
        end
    end
    local function neutral(id, tx, ty, size, mirror)
        local spots = { { tx, ty } }
        if mirror then spots[2] = { W + 1 - (tx + size - 1), H + 1 - (ty + size - 1) } end
        for _, p in ipairs(spots) do
            clearRound(p[1] - 1 + size / 2, p[2] - 1 + size / 2, size / 2 + 2)
            w.neutralSpots[#w.neutralSpots + 1] = { id = id, x = p[1], y = p[2] }
        end
    end
    neutral("goblinMerchant", 18, 23, 3, true)
    neutral("mercCamp", 28, 46, 3, true)
    neutral("goblinLab", 31, 31, 3, false)
    neutral("tavern", 31, 35, 3, false)

    for y = 1, H do
        for x = 1, W do w.ground[(y - 1) * W + x] = r.int(1, 100) end
    end

    w.starts = {
        -- the mine sits two tiles from the hall, as on Warcraft III maps, so five workers keep it busy
        { hall = { 10, 50 }, mine = { 5, 51 } },                         -- bottom-left
        { hall = { W + 1 - 13, H + 1 - 53 }, mine = { W + 1 - 7, H + 1 - 53 } },  -- top-right (mirrored)
    }
    w.expansions = { { 9, 9 }, { W + 1 - 11, H + 1 - 11 } }
    -- the mine tiles and hall tiles must be clear of trees
    local function clearRect(x, y, s) for yy = y - 1, y + s do for xx = x - 1, x + s do clear(xx, yy) end end end
    for _, s in ipairs(w.starts) do clearRect(s.hall[1], s.hall[2], 4) clearRect(s.mine[1], s.mine[2], 3) end
    for _, e in ipairs(w.expansions) do clearRect(e[1], e[2], 3) end
    w.blockVersion = 1
end

-- tree removal when its lumber runs out
function M.removeTree(w, i)
    w.block[i] = nil
    w.trees[i] = nil
    w.treeKind[i] = nil
    w.blockVersion = (w.blockVersion or 0) + 1
    w.treesChanged = (w.treesChanged or 0) + 1
end

-- nearest tree tile with lumber, near (x, y)
function M.nearestTree(w, px, py, maxR, avoid)
    local tx, ty = M.tileOf(px, py)
    local best, bd
    maxR = maxR or 14
    for y = max(1, ty - maxR), min(w.h, ty + maxR) do
        for x = max(1, tx - maxR), min(w.w, tx + maxR) do
            local i = (y - 1) * w.w + x
            if w.trees[i] and (not avoid or not avoid[i]) then
                -- only trees a worker can actually stand next to
                if M.walkable(w, x + 1, y) or M.walkable(w, x - 1, y) or M.walkable(w, x, y + 1) or M.walkable(w, x, y - 1) then
                    local d = (x - 0.5 - px) ^ 2 + (y - 0.5 - py) ^ 2
                    if not bd or d < bd then best, bd = i, d end
                end
            end
        end
    end
    return best
end


-- ------------------------------------------------------------------ Lordaeron Crossing (80x80)
-- A bigger two-player map in the style of WC3's melee maps: a natural expansion next to each base,
-- a far expansion guarded by a red camp, a lake in the middle with Fountains of Health beside it,
-- ponds, dirt roads, and creep camps of every strength along the way. Mirrored corner to corner.
function M.generateCrossing(w, seed)
    local W, H = 80, 80
    w.w, w.h = W, H
    w.block, w.trees, w.treeKind, w.ground, w.road, w.water = {}, {}, {}, {}, {}, {}
    local r = M.rng(seed)
    local function idx(x, y) return (y - 1) * W + x end
    local function setTree(x, y)
        if not M.inside(w, x, y) then return end
        local i = idx(x, y)
        if w.block[i] == nil then w.block[i] = "tree" w.trees[i] = D.TREE_LUMBER w.treeKind[i] = r.int(1, #D.TREES) end
    end
    local function clear(x, y)
        if not M.inside(w, x, y) then return end
        local i = idx(x, y)
        if w.block[i] == "tree" then w.block[i] = nil w.trees[i] = nil w.treeKind[i] = nil end
    end
    local function setWater(x, y)
        if not M.inside(w, x, y) then return end
        local i = idx(x, y)
        w.block[i] = "water" w.trees[i] = nil w.treeKind[i] = nil w.water[i] = true
    end
    local function both(fn, x, y) fn(x, y) fn(W + 1 - x, H + 1 - y) end
    local function round(cx, cy, rad, fn)
        for y = floor(cy - rad), floor(cy + rad) + 1 do
            for x = floor(cx - rad), floor(cx + rad) + 1 do
                if (x - 0.5 - cx) ^ 2 + (y - 0.5 - cy) ^ 2 <= rad * rad then fn(x, y) end
            end
        end
    end
    local function roundBoth(cx, cy, rad, fn) round(cx, cy, rad, fn) round(W - cx, H - cy, rad, fn) end

    -- forest border, a thick forest belt along the sides, and mirrored clumps
    for y = 1, H do for x = 1, W do if x <= 3 or y <= 3 or x >= W - 2 or y >= H - 2 then setTree(x, y) end end end
    for _ = 1, 46 do
        local cx, cy = r.int(5, W - 5), r.int(5, H - 5)
        if cx + cy < W + 6 then
            local rad = r.float() * 2.6 + 1.4
            for y = cy - 4, cy + 4 do for x = cx - 4, cx + 4 do
                if (x - cx) ^ 2 + (y - cy) ^ 2 <= rad * rad and r.float() < 0.85 then both(setTree, x, y) end
            end end
        end
    end
    -- lumber close to each base
    for i = 0, 13 do for d = 0, 2 do both(setTree, 4 + d, 50 + i) both(setTree, 18 + i, H - 3 - d) end end

    -- open ground: bases, expansions, the middle, the camps
    local P1, NAT, FAR = { 13, 66 }, { 30, 70 }, { 10, 32 }
    roundBoth(P1[1], P1[2], 9.5, clear)
    roundBoth(NAT[1], NAT[2], 6, clear)
    roundBoth(FAR[1], FAR[2], 6, clear)
    round(W / 2, H / 2, 10, clear)
    -- roads (3 wide) between them, remembered so they can be drawn as dirt
    local function carve(x1, y1, x2, y2)
        local steps = max(abs(x2 - x1), abs(y2 - y1))
        for i = 0, steps do
            local x = floor(x1 + (x2 - x1) * i / steps + 0.5)
            local y = floor(y1 + (y2 - y1) * i / steps + 0.5)
            for yy = y - 1, y + 1 do for xx = x - 1, x + 1 do
                if xx > 3 and yy > 3 and xx < W - 2 and yy < H - 2 then
                    clear(xx, yy) clear(W + 1 - xx, H + 1 - yy)
                    w.road[idx(xx, yy)] = true w.road[idx(W + 1 - xx, H + 1 - yy)] = true
                end
            end end
        end
    end
    carve(P1[1], P1[2], NAT[1], NAT[2])
    carve(P1[1], P1[2], FAR[1], FAR[2])
    carve(P1[1] + 4, P1[2] - 4, W / 2 - 6, H / 2 + 6)
    carve(NAT[1], NAT[2], W / 2 + 2, H / 2 + 9)
    carve(FAR[1], FAR[2], W / 2 - 9, H / 2 - 2)
    carve(W / 2 - 6, H / 2 + 6, W / 2 + 6, H / 2 + 6)
    carve(FAR[1], FAR[2], FAR[1] + 4, 12)
    carve(FAR[1] + 4, 12, W / 2 + 6, H / 2 - 6)

    -- water: a lake in the middle, two ponds
    round(W / 2, H / 2, 4.2, setWater)
    roundBoth(22.5, 22.5, 3.2, setWater)

    -- camps (mirrored, the same creeps on both sides) and neutral buildings
    w.campSpots, w.neutralSpots = {}, {}
    local camps = {
        { 24.5, 56.5, "green" }, { 17.5, 47.5, "green" }, { 34.5, 64.5, "orange" }, { 14.5, 37.5, "red" },
        { 40.5, 58.5, "orange" }, { 31.5, 31.5, "red" }, { 52.5, 70.5, "green" },
    }
    for _, c in ipairs(camps) do
        local pick = r.int(1, 100)
        for _, p in ipairs({ { c[1], c[2] }, { W - c[1], H - c[2] } }) do
            round(p[1], p[2], 3.2, clear)
            w.campSpots[#w.campSpots + 1] = { x = p[1], y = p[2], kind = c[3], pick = pick }
        end
    end
    local function neutral(id, tx, ty, size)
        for _, p in ipairs({ { tx, ty }, { W + 1 - (tx + size - 1), H + 1 - (ty + size - 1) } }) do
            round(p[1] - 1 + size / 2, p[2] - 1 + size / 2, size / 2 + 2, clear)
            w.neutralSpots[#w.neutralSpots + 1] = { id = id, x = p[1], y = p[2] }
        end
    end
    neutral("goblinMerchant", 36, 50, 3)
    neutral("mercCamp", 46, 64, 3)
    neutral("goblinLab", 20, 26, 3)
    neutral("fountain", 33, 44, 2)
    -- one Tavern in the middle
    round(40, 40, 3.5, clear)
    w.neutralSpots[#w.neutralSpots + 1] = { id = "tavern", x = 39, y = 39 }

    for y = 1, H do for x = 1, W do w.ground[idx(x, y)] = r.int(1, 100) end end
    w.starts = {
        { hall = { P1[1] - 2, P1[2] - 2 }, mine = { P1[1] - 7, P1[2] - 1 } },
        { hall = { W + 1 - (P1[1] - 2 + 3), H + 1 - (P1[2] - 2 + 3) }, mine = { W + 1 - (P1[1] - 7 + 2), H + 1 - (P1[2] - 1 + 2) } },
    }
    w.expansions = {
        { NAT[1] - 1, NAT[2] - 1 }, { W + 1 - (NAT[1] - 1 + 2), H + 1 - (NAT[2] - 1 + 2) },
        { FAR[1] - 1, FAR[2] - 1 }, { W + 1 - (FAR[1] - 1 + 2), H + 1 - (FAR[2] - 1 + 2) },
    }
    local function clearRect(x, y, s2) for yy = y - 1, y + s2 do for xx = x - 1, x + s2 do clear(xx, yy) end end end
    for _, st in ipairs(w.starts) do clearRect(st.hall[1], st.hall[2], 4) clearRect(st.mine[1], st.mine[2], 3) end
    for _, e in ipairs(w.expansions) do clearRect(e[1], e[2], 3) end
    w.blockVersion = 1
end
