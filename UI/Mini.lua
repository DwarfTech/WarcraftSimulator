-- Skirmish: the minimap (bottom left). Click or drag to move the camera; right-click to send the
-- selected units there.

local ADDON, ns = ...
local E = ns.Engine
local D, M, S = E.Data, E.Map, E.Sim
local UI = ns.UI
local Mi = {}
UI.Mini = Mi

local floor, min, max = math.floor, math.min, math.max
local SIZE = 200

function Mi.build(f)
    local m = CreateFrame("Frame", nil, f, "BackdropTemplate")
    m:SetSize(SIZE + 12, SIZE + 12)
    m:SetPoint("BOTTOMLEFT", 10, 12)
    m:SetBackdrop({ bgFile = UI.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    m:SetBackdropColor(0, 0, 0, 1)
    m:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    local inner = CreateFrame("Frame", nil, m)
    inner:SetSize(SIZE, SIZE)
    inner:SetPoint("CENTER")
    inner:EnableMouse(true)
    Mi.frame, Mi.inner = m, inner
    Mi.terrain = UI.pool(inner, "BACKGROUND", 0)
    Mi.camps = UI.pool(inner, "BORDER", 0)
    Mi.dots = UI.pool(inner, "ARTWORK", 0)
    Mi.ringTex = UI.pool(inner, "OVERLAY", 1)
    Mi.camTex = UI.pool(inner, "OVERLAY", 0)
    Mi.pings = {}

    local function mapPos()
        local cx, cy = GetCursorPosition()
        local s = inner:GetEffectiveScale()
        local x, y = cx / s - inner:GetLeft(), inner:GetTop() - cy / s
        local w = UI.w
        return max(0, min(w.w, x / SIZE * w.w)), max(0, min(w.h, y / SIZE * w.h))
    end
    inner:SetScript("OnMouseDown", function(_, button)
        if not UI.w then return end
        local x, y = mapPos()
        if button == "LeftButton" then
            if UI.mode and UI.mode.type == "target" then
                UI.Input.targetAt(x, y, nil)
            else
                Mi.dragging = true
                UI.lookAt(x, y)
            end
        elseif button == "RightButton" then
            UI.Input.smartAt(x, y, nil)
        end
    end)
    inner:SetScript("OnMouseUp", function() Mi.dragging = false end)
    inner:SetScript("OnUpdate", function()
        if Mi.dragging and UI.w then
            if not IsMouseButtonDown("LeftButton") then Mi.dragging = false return end
            local x, y = mapPos()
            UI.lookAt(x, y)
        end
    end)
end

local function px(v, n) return v / n * SIZE end

local function put(pool, x, y, w, h, r, g, b, a)
    local t = pool:get()
    t:SetTexture(UI.WHITE)
    t:SetTexCoord(0, 1, 0, 1)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", Mi.inner, "TOPLEFT", x, -y)
    t:SetSize(max(1, w), max(1, h))
    t:SetVertexColor(r, g, b, a or 1)
    return t
end

-- the ground: grass, trees, fog. Row runs keep the texture count low.
local function drawTerrain(w)
    Mi.terrain:reset()
    local pl = w.players[UI.me]
    local W, H = w.w, w.h
    local cw, ch = SIZE / W, SIZE / H
    local function colour(i)
        local fog = 0
        if not w.noFog then
            if not pl.explored[i] then return 0 end
            if not pl.visible[i] then fog = 1 end
        end
        local b = w.block[i]
        local base = b == "tree" and 1 or ((b == "water" or (w.shallow and w.shallow[i])) and 3 or (b == "cliff" and 4 or 2))
        return base * 10 + fog
    end
    local COL = {
        [10] = { 0.08, 0.24, 0.08 }, [11] = { 0.05, 0.14, 0.05 },
        [20] = { 0.30, 0.44, 0.18 }, [21] = { 0.17, 0.25, 0.10 },
        [30] = { 0.12, 0.30, 0.50 }, [31] = { 0.07, 0.17, 0.30 },
        [40] = { 0.32, 0.30, 0.28 }, [41] = { 0.18, 0.17, 0.16 },
        [0] = { 0, 0, 0 },
    }
    local ts = UI.Draw.tileset and UI.Draw.tileset(w)
    if ts then
        local c = ts[5]
        COL[20] = { min(1, c[1] * 1.35), min(1, c[2] * 1.35), min(1, c[3] * 1.35) }
        COL[21] = { c[1] * 0.75, c[2] * 0.75, c[3] * 0.75 }
    end
    for y = 1, H do
        local runStart, runC
        for x = 1, W + 1 do
            local c = x <= W and colour((y - 1) * W + x) or -1
            if c ~= runC then
                if runC and runC ~= 0 then
                    local col = COL[runC]
                    put(Mi.terrain, (runStart - 1) * cw, (y - 1) * ch, (x - runStart) * cw + 0.5, ch + 0.5, col[1], col[2], col[3], 1)
                end
                runStart, runC = x, c
            end
        end
    end
    Mi.terrain:finish()
end

function Mi.ping(x, y, r, g, b)
    Mi.pings[#Mi.pings + 1] = { x = x, y = y, t = 0, r = r or 1, g = g or 0.1, b = b or 0.1 }
end

local MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local CAMP_COL = { green = { 0.2, 0.95, 0.2 }, orange = { 1, 0.6, 0.1 }, red = { 1, 0.15, 0.1 } }

-- WC3 marks creep camps you have seen on the minimap, coloured by how tough they are
local function drawCamps(w)
    Mi.camps:reset()
    local pl = w.players[UI.me]
    local alive = {}
    for _, u in ipairs(w.list) do
        if u.camp and u.kind == "unit" and S.alive(u) then alive[floor(u.camp[1] * 10) * 10000 + floor(u.camp[2] * 10)] = true end
    end
    for _, c in ipairs(w.campSpots or {}) do
        local tx, ty = floor(c.x) + 1, floor(c.y) + 1
        if alive[floor(c.x * 10) * 10000 + floor(c.y * 10)] and (w.noFog or pl.explored[(ty - 1) * w.w + tx]) then
            local col = CAMP_COL[c.kind] or CAMP_COL.green
            local t = put(Mi.camps, px(c.x, w.w) - 5, px(c.y, w.h) - 5, 10, 10, 0, 0, 0, 0.85)
            t:SetTexture(MASK)
            local t2 = put(Mi.camps, px(c.x, w.w) - 3.5, px(c.y, w.h) - 3.5, 7, 7, col[1], col[2], col[3], 1)
            t2:SetTexture(MASK)
        end
    end
    Mi.camps:finish()
end

function Mi.update(elapsed)
    local w = UI.w
    if not w then return end
    Mi.tT = (Mi.tT or 0) - elapsed
    if Mi.dirtyTerrain or Mi.tT <= 0 then
        Mi.dirtyTerrain = false
        Mi.tT = 1.5
        drawTerrain(w)
    end
    Mi.dT = (Mi.dT or 0) - elapsed
    if Mi.dT > 0 and #Mi.pings == 0 then return end
    Mi.dT = 0.2
    local W, H = w.w, w.h
    if SkirmishDB.miniCamps ~= false then drawCamps(w) else Mi.camps:reset() Mi.camps:finish() end
    Mi.dots:reset()
    Mi.ringTex:reset()
    for _, e in ipairs(w.list) do
        if S.alive(e) and not e.hidden and S.visibleTo(w, UI.me, e) then
            local r, g, b
            if e.owner == 0 then r, g, b = 1, 0.85, 0.1
            elseif e.owner == 3 then r, g, b = 0.75, 0.65, 0.4
            else
                local c = D.Factions[w.players[e.owner].faction].color
                r, g, b = c[1], c[2], c[3]
                if e.owner == UI.me then r, g, b = 0.2, 1, 0.2 end
            end
            if e.kind == "item" then
                -- items aren't shown on the minimap
            elseif e.kind == "unit" then
                if e.camp and SkirmishDB.miniCamps ~= false then
                    -- shown as its camp marker
                elseif e.def.hero then
                    -- heroes are bigger dots, as in WC3
                    local t = put(Mi.dots, px(e.x, W) - 3, px(e.y, H) - 3, 6, 6, r, g, b, 1)
                else
                    put(Mi.dots, px(e.x, W) - 1.5, px(e.y, H) - 1.5, 3, 3, r, g, b, 1)
                end
            elseif e.owner == 0 and e.kind == "building" and e.def.icon then
                -- shops and other neutral buildings show their icon
                local t = put(Mi.dots, px(e.x, W) - 5, px(e.y, H) - 5, 10, 10, 1, 1, 1, 1)
                t:SetTexture(e.def.icon)
                t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                put(Mi.dots, px(e.tx - 1, W), px(e.ty - 1, H), px(e.size, W), px(e.size, H), r, g, b, 1)
            end
        end
    end
    -- attack pings
    local keep = {}
    for _, p in ipairs(Mi.pings) do
        p.t = p.t + 0.2
        if p.t < 4 then
            keep[#keep + 1] = p
            -- a pulsing circle, like WC3's attack ping
            local f = p.t % 1
            local s = 8 + f * 22
            local t = put(Mi.ringTex, px(p.x, W) - s / 2, px(p.y, H) - s / 2, s, s, p.r, p.g, p.b, 0.7 * (1 - f))
            t:SetTexture(MASK)
            local c = put(Mi.ringTex, px(p.x, W) - 3, px(p.y, H) - 3, 6, 6, p.r, p.g, p.b, 0.9)
            c:SetTexture(MASK)
        end
    end
    Mi.pings = keep
    Mi.dots:finish()
    Mi.ringTex:finish()
    -- camera box
    Mi.camTex:reset()
    local x1, y1, x2, y2 = UI.viewRect()
    local ax, ay, bx, by = px(x1, W), px(y1, H), px(x2, W), px(y2, H)
    put(Mi.camTex, ax, ay, bx - ax, 1, 1, 1, 1, 0.9)
    put(Mi.camTex, ax, by - 1, bx - ax, 1, 1, 1, 1, 0.9)
    put(Mi.camTex, ax, ay, 1, by - ay, 1, 1, 1, 0.9)
    put(Mi.camTex, bx - 1, ay, 1, by - ay, 1, 1, 1, 0.9)
    Mi.camTex:finish()
end
