-- Skirmish: mouse and keyboard.
--   Left-click selects (Shift adds/removes, double-click picks every unit of that type on screen).
--   Left-drag draws a selection box. Right-click is the "smart" order: attack, gather, move, or
--   set a building's rally point. Mouse wheel zooms; middle-drag, arrow keys or the screen edges scroll.
--   Ctrl+1..5 makes a control group, 1..5 recalls it (twice to jump to it). F1-F3 select your heroes,
--   Space jumps to the last attack. Letters press the command card buttons.

local ADDON, ns = ...
local E = ns.Engine
local D, M, S = E.Data, E.Map, E.Sim
local UI = ns.UI
local In = {}
UI.Input = In

local floor, min, max, abs, sqrt = math.floor, math.min, math.max, math.abs, math.sqrt

In.keys = {}

-- ------------------------------------------------------------------ picking

-- the entity under a map position (units first, then buildings and mines)
function In.pick(x, y)
    local w = UI.w
    if not w or not x then return nil end
    local best, bd
    for _, e in ipairs(w.list) do
        if S.alive(e) and e.kind == "unit" and not e.hidden and S.visibleTo(w, UI.me, e) then
            local up = UI.Figures.pitch() < 1.5 and UI.Draw.bodyUp(UI.Draw.unitTarget(e.def)) * 0.4 or 0.25
            local d = sqrt((e.x - x) ^ 2 + (e.y - (e.def.air and 1.0 or 0) - up - y) ^ 2)
            if d < max((e.def.vis or e.def.radius) + 0.4, UI.Draw.selDiameter(e.def, D.WC3SIZE[e.def.id]) * 0.45) and (not bd or d < bd) then best, bd = e, d end
        end
    end
    if best then return best end
    for _, e in ipairs(w.list) do
        if S.alive(e) and e.kind == "item" and S.visibleTo(w, UI.me, e) and sqrt((e.x - x) ^ 2 + (e.y - 0.25 - y) ^ 2) < 0.45 then return e end
    end
    -- buildings before gold mines (a Haunted Gold Mine stands on its mine)
    for pass = 1, 2 do
        for _, e in ipairs(w.list) do
            if S.alive(e) and e.kind == (pass == 1 and "building" or "mine") and S.visibleTo(w, UI.me, e) then
                if x >= e.tx - 1 and x <= e.tx - 1 + e.size and y >= e.ty - 1 - 0.6 and y <= e.ty - 1 + e.size then return e end
            end
        end
    end
end

function In.treeAt(x, y)
    local w = UI.w
    if not x then return nil end
    local tx, ty = M.tileOf(x, y)
    if M.isTree(w, tx, ty) then return (ty - 1) * w.w + tx end
end

-- ------------------------------------------------------------------ selection

local function sortSel()
    local w = UI.w
    table.sort(UI.sel, function(a, b)
        local ea, eb = w.ents[a], w.ents[b]
        local pa = ea.def.hero and 0 or (ea.def.worker and 2 or 1)
        local pb = eb.def.hero and 0 or (eb.def.worker and 2 or 1)
        if pa ~= pb then return pa < pb end
        if ea.def.id ~= eb.def.id then return ea.def.id < eb.def.id end
        return a < b
    end)
end

function In.setSelection(ids, quiet)
    UI.sel = ids
    UI.subgroup = nil
    if not quiet and UI.Sound and UI.w then UI.Sound.selected(UI.w, ids) end
    if #ids > 1 then sortSel() end
    UI.mode = nil
    UI.Hud.submenu = nil
    UI.Hud.dirty = true
end

-- WC3 subgroups: in a mixed selection one unit type is "active" and its abilities fill the
-- command card. Tab steps to the next type.
function In.subgroup()
    local w = UI.w
    local units = In.ownUnits()
    local first, has = nil, {}
    for _, id in ipairs(units) do
        local d = w.ents[id].def.id
        if not first then first = d end
        has[d] = true
    end
    local cur = UI.subgroup and has[UI.subgroup] and UI.subgroup or first
    local ids = {}
    for _, id in ipairs(units) do if w.ents[id].def.id == cur then ids[#ids + 1] = id end end
    return cur, ids, units
end

function In.nextSubgroup()
    local w = UI.w
    local cur, _, units = In.subgroup()
    local order, seen = {}, {}
    for _, id in ipairs(units) do
        local d = w.ents[id].def.id
        if not seen[d] then seen[d] = true order[#order + 1] = d end
    end
    if #order < 2 then return end
    for i, d in ipairs(order) do
        if d == cur then UI.subgroup = order[i % #order + 1] break end
    end
    UI.mode = nil
    UI.Hud.submenu = nil
    UI.Hud.dirty = true
end

function In.ownUnits()
    local out = {}
    for _, id in ipairs(UI.sel) do
        local e = UI.w.ents[id]
        if e and e.kind == "unit" and e.owner == UI.me and S.alive(e) then out[#out + 1] = id end
    end
    return out
end

local function clickSelect(x, y)
    local w = UI.w
    local e = In.pick(x, y)
    local shift = IsShiftKeyDown()
    if not e then
        if not shift then In.setSelection({}) end
        return
    end
    if e.kind == "item" then return end     -- items are picked up with a right-click, not selected
    local now = GetTime()
    if not shift and e.kind == "unit" and e.owner == UI.me and In.lastClick and In.lastClick.def == e.def.id and now - In.lastClick.t < 0.4 then
        -- double-click: every unit of that type on screen
        local x1, y1, x2, y2 = UI.viewRect()
        local ids = {}
        for _, u in ipairs(w.list) do
            if u.kind == "unit" and u.owner == UI.me and S.alive(u) and not u.hidden and u.def.id == e.def.id
               and u.x > x1 and u.x < x2 and u.y > y1 and u.y < y2 and #ids < 24 then
                ids[#ids + 1] = u.id
            end
        end
        In.setSelection(ids)
        In.lastClick = nil
        return
    end
    In.lastClick = { def = e.def.id, t = now }
    if shift and e.owner == UI.me and e.kind == "unit" then
        local ids, found = {}, false
        for _, id in ipairs(UI.sel) do
            if id == e.id then found = true else
                local s = w.ents[id]
                if s and s.kind == "unit" and s.owner == UI.me then ids[#ids + 1] = id end
            end
        end
        if not found and #ids < 24 then ids[#ids + 1] = e.id end
        In.setSelection(ids)
    else
        In.setSelection({ e.id })
    end
end

local function boxSelect(ax, ay, bx, by)
    local w = UI.w
    local x1, x2 = min(ax, bx), max(ax, bx)
    local y1, y2 = min(ay, by), max(ay, by)
    local ids = {}
    if IsShiftKeyDown() then
        for _, id in ipairs(In.ownUnits()) do ids[#ids + 1] = id end
    end
    local have = {}
    for _, id in ipairs(ids) do have[id] = true end
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and u.owner == UI.me and S.alive(u) and not u.hidden and not have[u.id] then
            if u.x >= x1 - 0.2 and u.x <= x2 + 0.2 and u.y >= y1 - 0.2 and u.y <= y2 + 0.4 and #ids < 24 then
                ids[#ids + 1] = u.id
            end
        end
    end
    if #ids == 0 then
        for _, b in ipairs(w.list) do
            if b.kind == "building" and b.owner == UI.me and S.alive(b) then
                if b.x >= x1 and b.x <= x2 and b.y >= y1 and b.y <= y2 then ids = { b.id } break end
            end
        end
    end
    if #ids > 0 or not IsShiftKeyDown() then In.setSelection(ids) end
end

-- ------------------------------------------------------------------ orders

local function report(ok, why)
    if not ok and why then UI.Hud.error(why) end
    return ok
end

-- right-click
function In.smartAt(x, y, e)
    local w = UI.w
    if not w then return end
    local units = In.ownUnits()
    local tree = not e and In.treeAt(x, y) or nil
    if #units > 0 then
        local ok, why = UI.act("command", UI.me, units, { type = "smart", target = e and e.id, tree = tree, x = x, y = y, queue = IsShiftKeyDown() })
        report(ok, why)
        if ok and UI.Sound then UI.Sound.ordered(w, units, e and S.isEnemy(w.ents[units[1]], e) and "attack" or "yes") end
        if ok then
            if e and S.isEnemy(w.ents[units[1]], e) then UI.Draw.marker(e.x, e.y, 1, 0.2, 0.2)
            elseif e or tree then UI.Draw.marker(x, y, 1, 0.85, 0.2)
            else UI.Draw.marker(x, y, 0.2, 1, 0.2) end
        end
        return
    end
    -- a building selected: set its rally point
    local b = UI.sel[1] and w.ents[UI.sel[1]]
    if b and b.kind == "building" and b.owner == UI.me and b.def.trains then
        UI.act("setRally", UI.me, b.id, x, y, e and e.id)
        if tree then b.rally.tree = tree end
        UI.Draw.marker(x, y, 0.2, 1, 0.2)
    end
end

-- left-click while a command card target is armed
function In.targetAt(x, y, e)
    local w = UI.w
    local mode = UI.mode
    if not mode then return end
    local units = In.ownUnits()
    local cmd = mode.cmd
    local ok, why = true, nil
    if cmd == "amove" or cmd == "attack" then
        if e and S.isEnemy(w.ents[units[1]] or {}, e) then
            ok, why = UI.act("command", UI.me, units, { type = "attack", target = e.id, queue = IsShiftKeyDown() })
            UI.Draw.marker(e.x, e.y, 1, 0.2, 0.2)
        else
            ok, why = UI.act("command", UI.me, units, { type = "amove", x = x, y = y, queue = IsShiftKeyDown() })
            UI.Draw.marker(x, y, 1, 0.2, 0.2)
        end
    elseif cmd == "move" then
        if e and e.kind == "unit" and not S.isEnemy(w.ents[units[1]] or {}, e) then
            -- Move onto a friendly unit: follow it
            ok, why = UI.act("command", UI.me, units, { type = "follow", target = e.id, queue = IsShiftKeyDown() })
            UI.Draw.marker(e.x, e.y, 0.2, 1, 0.2)
        else
            ok, why = UI.act("command", UI.me, units, { type = "move", x = x, y = y, queue = IsShiftKeyDown() })
            UI.Draw.marker(x, y, 0.2, 1, 0.2)
        end
    elseif cmd == "patrol" then
        ok, why = UI.act("command", UI.me, units, { type = "patrol", x = x, y = y, queue = IsShiftKeyDown() })
        UI.Draw.marker(x, y, 1, 0.85, 0.2)
    elseif cmd == "gather" then
        local tree = not e and In.treeAt(x, y)
        -- a Haunted Gold Mine counts as its gold mine
        if e and e.kind == "building" and e.def.onMine and e.mine then e = w.ents[e.mine] end
        if (e and e.kind == "mine") or tree then
            ok, why = UI.act("command", UI.me, units, { type = "gather", mine = e and e.kind == "mine" and e.id or nil, tree = tree, queue = IsShiftKeyDown() })
            UI.Draw.marker(x, y, 1, 0.85, 0.2)
        else
            ok, why = false, "Must target a gold mine or a tree."
        end
    elseif cmd == "cast" then
        local hero = w.ents[mode.unit]
        local ab = D.Abilities[mode.ability]
        if ab.target == "enemy" or ab.target == "ally" or ab.target == "unit" then
            if not e or e.kind ~= "unit" then ok, why = false, "Must target a unit."
            else ok, why = UI.act("command", UI.me, mode.ids or { hero.id }, { type = "cast", ability = mode.ability, target = e.id }) end
        elseif ab.target == "friend" then
            if not e or e.owner ~= UI.me then ok, why = false, "Must target one of your units or buildings."
            else ok, why = UI.act("command", UI.me, { hero.id }, { type = "cast", ability = mode.ability, target = e.id }) end
        else
            ok, why = UI.act("command", UI.me, mode.ids or { hero.id }, { type = "cast", ability = mode.ability, x = x, y = y })
        end
    elseif cmd == "repair" then
        ok, why = UI.act("command", UI.me, units, { type = "repair", target = e and e.id })
    elseif cmd == "item" then
        local hero = w.ents[mode.unit or 0]
        if hero then ok, why = UI.act("useItem", hero, mode.slot, e and e.id, x, y) end
    elseif cmd == "rally" then
        local b = w.ents[UI.sel[1]]
        if b then
            UI.act("setRally", UI.me, b.id, x, y, e and e.id)
            local tree = not e and In.treeAt(x, y)
            if tree then b.rally.tree = tree end
            UI.Draw.marker(x, y, 0.2, 1, 0.2)
        end
    end
    report(ok, why)
    if ok and UI.Sound and #units > 0 and cmd ~= "rally" and cmd ~= "item" then
        UI.Sound.ordered(w, units, (cmd == "amove" or cmd == "attack" or cmd == "patrol" or (cmd == "cast" and e and S.isEnemy(w.ents[units[1]], e))) and "attack" or "yes")
    end
    if not IsShiftKeyDown() or not ok then UI.mode = nil UI.Hud.dirty = true end
end

local function placeTile(x, y, size, bid)
    -- a Haunted Gold Mine snaps onto the gold mine under the cursor
    if bid and D.Buildings[bid].onMine then
        local m = S.mineNear(UI.w, x, y)
        if m then return m.tx, m.ty end
    end
    return floor(x - size / 2 + 0.5) + 1, floor(y - size / 2 + 0.5) + 1
end

local function canPlaceHere(tx, ty, size, bid)
    local w = UI.w
    if bid then
        local ok, why = S.canPlaceFor(w, UI.me, bid, tx, ty)
        if not ok then return false, why end
    elseif not M.canPlace(w, tx, ty, size) then return false end
    if w.noFog then return true end
    local pl = w.players[UI.me]
    for yy = ty, ty + size - 1 do
        for xx = tx, tx + size - 1 do
            if not pl.explored[(yy - 1) * w.w + xx] then return false end
        end
    end
    return true
end

local function placeAt(x, y)
    local w = UI.w
    local def = D.Buildings[UI.mode.bid]
    local tx, ty = placeTile(x, y, def.size, def.id)
    local okHere, whyHere = canPlaceHere(tx, ty, def.size, def.id)
    if not okHere then UI.Hud.error(whyHere or "Can't build there.") return end
    -- the selected worker closest to the spot does the building; with Shift, the one that
    -- already has buildings lined up adds this one to its list
    local shift = IsShiftKeyDown()
    local best, bd
    for _, id in ipairs(In.ownUnits()) do
        local u = w.ents[id]
        if u.def.worker then
            local d = (u.x - x) ^ 2 + (u.y - y) ^ 2
            if shift and (u.queue or (u.order and (u.order.type == "build" or u.order.type == "construct"))) then d = d - 1e6 end
            if not bd or d < bd then best, bd = u, d end
        end
    end
    if not best then UI.mode = nil return end
    local resume = best.order and best.order.type == "gather" and { type = "gather", res = best.order.res, mine = best.order.mine, tree = best.order.tree } or nil
    local wasBuilding = best.order and (best.order.type == "build" or best.order.type == "construct")
    local ok, why = UI.act("build", UI.me, best.id, def.id, tx, ty, shift)
    if ok and shift and resume and not wasBuilding then best.order.after = resume end
    report(ok, why)
    if ok then UI.Draw.marker(tx - 1 + def.size / 2, ty - 1 + def.size / 2, 0.2, 1, 0.2) end
    if ok and not IsShiftKeyDown() then UI.mode = nil UI.Hud.submenu = nil UI.Hud.dirty = true end
end

-- ------------------------------------------------------------------ control groups & keys

local function selectGroup(n)
    local w = UI.w
    local g = UI.groups[n]
    if not g then return end
    local ids = {}
    for _, id in ipairs(g) do if S.alive(w.ents[id]) then ids[#ids + 1] = id end end
    UI.groups[n] = ids
    if #ids == 0 then return end
    local now = GetTime()
    if In.lastGroup == n and now - (In.lastGroupT or 0) < 0.45 then
        local e = w.ents[ids[1]]
        UI.lookAt(e.x, e.y)
    end
    In.lastGroup, In.lastGroupT = n, now
    In.setSelection(ids)
end

function In.key(key)
    local w = UI.w
    if not w then
        if key == "ESCAPE" then UI.frame:Hide() return true end
        return false
    end
    if key == "UP" or key == "DOWN" or key == "LEFT" or key == "RIGHT" then
        In.keys[key] = true
        return true
    end
    if key == "ESCAPE" then
        if UI.mode then UI.mode = nil UI.Hud.dirty = true return true end
        if UI.Hud.submenu then UI.Hud.submenu = nil UI.Hud.dirty = true return true end
        if UI.Hud.options and UI.Hud.options:IsShown() then UI.Hud.options:Hide() UI.Hud.showMenu() return true end
        if UI.Hud.multi and UI.Hud.multi:IsShown() then UI.Hud.multi:Hide() UI.Hud.showMenu() return true end
        if UI.Hud.menuShown() then UI.Hud.hideMenu() return true end
        UI.frame:Hide()
        return true
    end
    if key == "F10" then UI.Hud.showMenu() return true end
    if key == "PAUSE" then UI.paused = not UI.paused UI.Hud.dirty = true return true end
    if key == "F1" or key == "F2" or key == "F3" then
        -- WC3: F1-F3 select your heroes in the order they were summoned
        local list = w.players[UI.me].heroes or {}
        local h = w.ents[list[(key == "F1" and 1) or (key == "F2" and 2) or 3] or 0]
        if S.alive(h) then
            if #UI.sel == 1 and UI.sel[1] == h.id then UI.lookAt(h.x, h.y) end
            In.setSelection({ h.id })
        end
        return true
    end
    if key == "F8" then UI.Hud.nextIdleWorker() return true end
    if key == "TAB" then In.nextSubgroup() return true end
    local INV = { NUMPAD7 = 1, NUMPAD8 = 2, NUMPAD4 = 3, NUMPAD5 = 4, NUMPAD1 = 5, NUMPAD2 = 6 }
    if INV[key] then UI.Hud.useSlot(INV[key]) return true end
    if key == "SPACE" then
        if UI.attackAt then UI.lookAt(UI.attackAt[1], UI.attackAt[2]) UI.attackAt = nil
        elseif UI.sel[1] and w.ents[UI.sel[1]] then local e = w.ents[UI.sel[1]] UI.lookAt(e.x, e.y) end
        return true
    end
    local n = tonumber(key)
    if n and n >= 1 and n <= 9 then
        if IsControlKeyDown() then
            local ids = {}
            for _, id in ipairs(UI.sel) do local e = w.ents[id] if e and e.owner == UI.me then ids[#ids + 1] = id end end
            UI.groups[n] = ids
            UI.Hud.message("Group " .. n .. " set.")
        else
            selectGroup(n)
        end
        return true
    end
    if IsControlKeyDown() or IsAltKeyDown() then return false end
    return UI.Hud.pressKey(key)
end

-- ------------------------------------------------------------------ building the handlers

function In.build(f, view)
    f:EnableKeyboard(true)
    pcall(f.SetPropagateKeyboardInput, f, true)
    f:SetScript("OnKeyDown", function(self, key)
        local ok, handled = pcall(In.key, key)
        if not ok then UI.say("|cffff4040error|r: " .. tostring(handled)) handled = false end
        if not InCombatLockdown() then pcall(self.SetPropagateKeyboardInput, self, not handled) end
    end)
    f:SetScript("OnKeyUp", function(_, key) In.keys[key] = nil end)

    view:SetScript("OnMouseDown", function(_, button)
        if not UI.w then return end
        local x, y, sx, sy = UI.cursorMap()
        if not x then return end
        if button == "LeftButton" then
            if UI.mode and UI.mode.type == "target" then
                In.targetAt(x, y, In.pick(x, y))
            elseif UI.mode and UI.mode.type == "place" then
                placeAt(x, y)
            else
                In.drag = { x = x, y = y, sx = sx, sy = sy }
            end
        elseif button == "RightButton" then
            if UI.mode then UI.mode = nil UI.Hud.dirty = true return end
            In.smartAt(x, y, In.pick(x, y))
        elseif button == "MiddleButton" then
            In.pan = { sx = sx, sy = sy, cx = UI.camX, cy = UI.camY }
        end
    end)
    view:SetScript("OnMouseUp", function(_, button)
        if button == "MiddleButton" then In.pan = nil return end
        if button ~= "LeftButton" or not In.drag then return end
        local d = In.drag
        In.drag = nil
        local x, y, sx, sy = UI.cursorMap()
        if not x then x, y, sx, sy = d.x, d.y, d.sx, d.sy end
        if abs(sx - d.sx) < 6 and abs(sy - d.sy) < 6 then clickSelect(d.x, d.y)
        else boxSelect(d.x, d.y, x, y) end
    end)
    view:SetScript("OnMouseWheel", function(_, delta)
        if not UI.w then return end
        local _, _, sx, sy = UI.cursorMap()
        UI.setZoom(UI.zoom + delta * 0.1, sx, sy)
    end)
    view:SetScript("OnLeave", function() pcall(ResetCursor) In.cursorSet = nil end)
end

-- ------------------------------------------------------------------ per frame: scrolling, hover

function In.update(elapsed)
    local w = UI.w
    if not w or not UI.frame:IsShown() then return end
    local speed = 1100 / UI.zoom * elapsed
    local dx, dy = 0, 0
    if In.keys.LEFT then dx = dx - speed end
    if In.keys.RIGHT then dx = dx + speed end
    if In.keys.UP then dy = dy - speed end
    if In.keys.DOWN then dy = dy + speed end
    local x, y, sx, sy = UI.cursorMap()
    if In.pan and sx then
        if not IsMouseButtonDown("MiddleButton") then In.pan = nil
        else
            UI.camX = In.pan.cx - (sx - In.pan.sx) / UI.zoom
            UI.camY = In.pan.cy - (sy - In.pan.sy) / UI.zoom
        end
    elseif sx and not In.drag and SkirmishDB.edgeScroll ~= false then
        local m = 14
        if sx < m then dx = dx - speed elseif sx > UI.VIEW_W - m then dx = dx + speed end
        if sy < m then dy = dy - speed elseif sy > UI.VIEW_H - m then dy = dy + speed end
    end
    if dx ~= 0 or dy ~= 0 or In.pan then
        UI.camX, UI.camY = UI.camX + dx, UI.camY + dy
        UI.clampCamera()
    end
    if In.drag and not IsMouseButtonDown("LeftButton") then In.drag = nil end

    -- what's under the cursor
    In.hoverT = (In.hoverT or 0) - elapsed
    if In.hoverT <= 0 then
        In.hoverT = 0.05
        local e = x and In.pick(x, y)
        In.hoverId = e and e.id or nil
        In.hoverTree = (not e and x) and In.treeAt(x, y) or nil
        UI.Hud.setHover(e, In.hoverTree)
        if x then
            local cur
            if UI.mode and UI.mode.type == "target" then cur = "ATTACK_CURSOR"
            elseif e and e.owner ~= UI.me and e.owner ~= 0 and #In.ownUnits() > 0 then cur = "ATTACK_CURSOR"
            elseif (e and e.kind == "mine" or In.hoverTree) and #In.ownUnits() > 0 then
                local u = w.ents[In.ownUnits()[1]]
                if u and u.def.worker then cur = e and "MINE_CURSOR" or "LUMBER_CURSOR" end
            end
            if cur ~= In.cursorSet then
                In.cursorSet = cur
                if cur then pcall(SetCursor, cur) else pcall(ResetCursor) end
            end
        end
    end
end

-- drag box and building footprint, drawn on the overlay layer
function In.drawOverlay(pool, rect)
    local T = UI.TILE
    if In.drag then
        local x, y = UI.cursorMap()
        if x then
            local x1, x2 = min(In.drag.x, x) * T, max(In.drag.x, x) * T
            local y1, y2 = min(In.drag.y, y) * T, max(In.drag.y, y) * T
            if x2 - x1 > 4 or y2 - y1 > 4 then
                local fill = pool:get() fill:SetTexture(UI.WHITE) rect(fill, x1, y1, x2 - x1, y2 - y1, 0.2, 1, 0.2, 0.08)
                for _, s in ipairs({ { x1, y1, x2 - x1, 1 }, { x1, y2, x2 - x1, 1 }, { x1, y1, 1, y2 - y1 }, { x2, y1, 1, y2 - y1 } }) do
                    local t = pool:get() t:SetTexture(UI.WHITE) rect(t, s[1], s[2], s[3] + 1, s[4] + 1, 0.3, 1, 0.3, 0.9)
                end
            end
        end
    end
    -- buildings the selected workers are on their way to build (and shift-queued ones)
    for _, id in ipairs(UI.sel) do
        local u = UI.w.ents[id]
        if u and u.owner == UI.me and u.def.worker then
            local list = { u.order }
            for _, q in ipairs(u.queue or {}) do list[#list + 1] = q end
            for i, o in ipairs(list) do
                if o and o.type == "build" and not o.placed then
                    local bd = D.Buildings[o.bid]
                    local t = pool:get()
                    t:SetTexture(UI.WHITE)
                    t:SetTexCoord(0, 1, 0, 1)
                    rect(t, (o.tx - 1) * T + 2, (o.ty - 1) * T + 2, bd.size * T - 4, bd.size * T - 4, 0.3, 1, 0.3, 0.18)
                    local ic = pool:get()
                    ic:SetTexture(bd.icon)
                    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    rect(ic, (o.tx - 1 + bd.size / 2) * T - 14, (o.ty - 1 + bd.size / 2) * T - 14, 28, 28, 1, 1, 1, 0.7)
                end
            end
        end
    end
    if UI.mode and UI.mode.type == "place" then
        local x, y = UI.cursorMap()
        if x then
            local def = D.Buildings[UI.mode.bid]
            local tx, ty = placeTile(x, y, def.size, def.id)
            local w = UI.w
            local onMine = def.onMine and S.canPlaceFor(w, UI.me, def.id, tx, ty)
            for yy = ty, ty + def.size - 1 do
                for xx = tx, tx + def.size - 1 do
                    local ok = onMine or (not def.onMine and M.walkable(w, xx, yy) and (not def.needsBlight or S.blightAt(w, xx, yy)))
                    local t = pool:get()
                    t:SetTexture(UI.WHITE)
                    rect(t, (xx - 1) * T + 1, (yy - 1) * T + 1, T - 2, T - 2, ok and 0.1 or 1, ok and 1 or 0.1, 0.1, 0.4)
                end
            end
            local ic = pool:get()
            ic:SetTexture(def.icon)
            ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            rect(ic, (tx - 1 + def.size / 2) * T - 18, (ty - 1 + def.size / 2) * T - 18, 36, 36, 1, 1, 1, 0.85)
        end
    end
    -- WC3-style area-of-effect circle under the cursor while aiming an area spell
    if UI.mode and UI.mode.type == "target" and UI.mode.cmd == "cast" then
        local x, y = UI.cursorMap()
        local ab = D.Abilities[UI.mode.ability]
        local caster = UI.w.ents[UI.mode.unit or 0]
        if x and ab and caster then
            local lv = max(1, S.skillLevel(caster, ab.id))
            local function dot(px, py, sz, a)
                local t = pool:get()
                t:SetTexture(UI.WHITE)
                t:SetTexCoord(0, 1, 0, 1)
                rect(t, px * T - sz / 2, py * T - sz / 2, sz, sz, 0.55, 1, 0.45, a)
            end
            if ab.length then
                -- Shockwave: a band from the caster towards the cursor
                local dx, dy = x - caster.x, y - caster.y
                local d = sqrt(dx * dx + dy * dy)
                if d > 0.05 then
                    dx, dy = dx / d, dy / d
                    local half = (ab.width or 2) / 2
                    for s2 = 0, ab.length, 0.35 do
                        dot(caster.x + dx * s2 - dy * half, caster.y + dy * s2 + dx * half, 4, 0.85)
                        dot(caster.x + dx * s2 + dy * half, caster.y + dy * s2 - dx * half, 4, 0.85)
                    end
                end
            else
                local r = ab.radius or (ab.radiusL and ab.radiusL[min(lv, #ab.radiusL)])
                if ab.target == "point" or ab.target == "anywhere" then r = r or 0.6 end
                if r then
                    local disc = pool:get()
                    disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                    disc:SetTexCoord(0, 1, 0, 1)
                    rect(disc, (x - r) * T, (y - r) * T, 2 * r * T, 2 * r * T, 0.45, 1, 0.35, 0.16)
                    local n = max(16, floor(r * 14))
                    for i = 1, n do
                        local a = i / n * 2 * math.pi
                        dot(x + math.cos(a) * r, y + math.sin(a) * r, 4, 0.9)
                    end
                end
            end
            -- out of range: a faint ring showing how far the caster can reach
            local range = ab.range
            if range and range < 50 and sqrt((x - caster.x) ^ 2 + (y - caster.y) ^ 2) > range + 0.5 then
                local n = max(24, floor(range * 10))
                for i = 1, n do
                    local a = i / n * 2 * math.pi
                    local t = pool:get()
                    t:SetTexture(UI.WHITE)
                    t:SetTexCoord(0, 1, 0, 1)
                    rect(t, (caster.x + math.cos(a) * range) * T - 1.5, (caster.y + math.sin(a) * range) * T - 1.5, 3, 3, 1, 1, 1, 0.35)
                end
            end
        end
    end
end
