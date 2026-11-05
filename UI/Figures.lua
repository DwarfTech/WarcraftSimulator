-- Skirmish: 3D models seen from above. Adapted from WarTable's TopDown.lua: each figure is a small
-- square ModelScene sitting on the map with its own camera looking straight down at one model, so
-- the model can't drift off its spot. Scenes are pooled and handed between figures so scrolling and
-- deaths don't keep creating new frames.

local ADDON, ns = ...
local UI = ns.UI
local F = {}
UI.Figures = F

local floor, min, max, abs, sqrt, atan2, tan, cos, sin, pi =
    math.floor, math.min, math.max, math.abs, math.sqrt, math.atan2, math.tan, math.cos, math.sin, math.pi
local FOV = 0.32

-- Warcraft III's camera looks down at the battlefield at 56 degrees, so you see the fronts of units
-- and buildings, not just their tops. Every figure's camera is tilted the same way (the map itself
-- stays flat). SkirmishDB.camera = "top" looks straight down instead.
local WC3_PITCH = math.rad(56)
function F.pitch()
    return (SkirmishDB and SkirmishDB.camera == "top") and pi / 2 or WC3_PITCH
end

F.groups = {}      -- group -> { key -> scene }
F.free = {}        -- group -> list of idle scenes
F.count = 0

local function vec(ok, a, b, c)
    if not ok then return nil end
    if type(a) == "table" then a, b, c = a.x or a[1], a.y or a[2], a.z or a[3] end
    if type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" then return nil end
    local l = sqrt(a * a + b * b + c * c)
    if l < 0.5 or l > 1.5 then return nil end
    return { a / l, b / l, c / l }
end

local function readAxes(s)
    local f = vec(pcall(s.GetCameraForward, s))
    local r = vec(pcall(s.GetCameraRight, s))
    local u = vec(pcall(s.GetCameraUp, s))
    if f then return { fwd = f, right = r or { 0, -1, 0 }, up = u or { 1, 0, 0 } } end
end

-- Point a scene's camera straight down. The first scene works out how the client wants that
-- said (and which way is "up" on screen); every later scene repeats the same call.
local function lookDown(s)
    if F.method then F.method(s) return end
    local tries = {
        function(sc) sc:SetCameraOrientationByAxisVectors(0, 0, -1, 0, -1, 0, 1, 0, 0) end,
        function(sc) sc:SetCameraOrientationByYawPitchRoll(0, pi / 2, 0) end,
        function(sc) sc:SetCameraOrientationByYawPitchRoll(0, -pi / 2, 0) end,
    }
    for _, t in ipairs(tries) do
        if pcall(t, s) then
            local a = readAxes(s)
            if not a or a.fwd[3] < -0.95 then
                F.method = t
                F.tiltOK = (t == tries[1])
                F.axes = a or { fwd = { 0, 0, -1 }, right = { 0, -1, 0 }, up = { 1, 0, 0 } }
                return
            end
        end
    end
    F.method = tries[1]
    pcall(tries[1], s)
    F.axes = { fwd = { 0, 0, -1 }, right = { 0, -1, 0 }, up = { 1, 0, 0 } }
end

-- tilt a scene's camera (its "up" on screen stays world +x, as in the straight-down view)
-- F.flip: the camera's "right" axis is given the other way round. Given as (0, -1, 0) the view came
-- out mirrored, which turns every triangle's winding round, so the game culled the fronts of models
-- and drew their insides (you saw a unit's far leg through its body). /skirmish flip toggles it.
function F.flipped() return not (SkirmishDB and SkirmishDB.viewFlip == false) end

local function orient(s)
    local p = F.pitch()
    local key = p .. (F.flipped() and "f" or "")
    if s.pitchWant == key then return end
    s.pitchWant = key
    local ry = F.flipped() and 1 or -1
    if not F.tiltOK
        or not pcall(s.SetCameraOrientationByAxisVectors, s, cos(p), 0, -sin(p), 0, ry, 0, sin(p), 0, cos(p)) then
        if F.method then pcall(F.method, s) end
        s.pitch = pi / 2
        return
    end
    s.pitch = p
end
function F.orientKey() return F.pitch() .. (F.flipped() and "f" or "") end
F.orient = orient

-- screen angle (radians; 0 = right, pi/2 = down the screen) -> actor yaw
function F.yawFor(angle)
    local a = F.axes
    if not a then return 0 end
    local c, s = cos(angle), sin(angle)
    -- screen right is a.right, screen down is -a.up
    local vx = a.right[1] * c - a.up[1] * s
    local vy = a.right[2] * c - a.up[2] * s
    -- Which way round models turn differs between clients. F.faceMode picks one of four
    -- corrections (mirror, and/or turn half way round); /skirmish face or the Facing button cycles them.
    local base = (WarTableDB and WarTableDB.yawSign) or 1
    local m = F.FACE_MODES[(SkirmishDB and SkirmishDB.facing) or 1] or F.FACE_MODES[1]
    local yaw = atan2(vy, vx) * base * m[1] + m[2]
    -- an unmirrored view needs the mirror image of the turn the old (mirrored) view was tuned for
    if F.flipped() then yaw = -yaw end
    return yaw
end

local function light(s)
    pcall(s.ClearFog, s)
    pcall(s.SetFogNear, s, 2000)
    pcall(s.SetFogFar, s, 4000)
    pcall(s.SetLightVisible, s, true)
    pcall(s.SetLightType, s, (Enum and Enum.ModelLightType and Enum.ModelLightType.Directional) or 0)
    pcall(s.SetLightDirection, s, 0.25, 0.2, -0.95)
    pcall(s.SetLightAmbientColor, s, 0.85, 0.83, 0.8)
    pcall(s.SetLightDiffuseColor, s, 0.95, 0.92, 0.85)
end

function F.available()
    if F.ok ~= nil then return F.ok end
    local ok, s = pcall(CreateFrame, "ModelScene", nil, UIParent)
    F.ok = ok and s and s.CreateActor and true or false
    if s and s.Hide then s:Hide() end
    return F.ok
end

local function newScene(parent)
    local s = CreateFrame("ModelScene", nil, parent)
    pcall(s.EnableMouse, s, false)
    light(s)
    lookDown(s)
    orient(s)
    pcall(s.SetCameraFieldOfView, s, FOV)
    pcall(s.SetCameraNearClip, s, 0.05)
    pcall(s.SetCameraFarClip, s, 500)
    local ok, a = pcall(s.CreateActor, s)
    s.actor = ok and a or nil
    F.count = F.count + 1
    return s
end

local function extent(a)
    for _, fn in ipairs({ "GetActiveBoundingBox", "GetMaxBoundingBox" }) do
        if a[fn] then
            local ok, x1, y1, z1, x2, y2, z2 = pcall(a[fn], a)
            if ok and type(x1) == "table" then
                local lo, hi = x1, y1
                x1, y1, z1 = lo.x or lo[1], lo.y or lo[2], lo.z or lo[3]
                x2, y2, z2 = hi.x or hi[1], hi.y or hi[2], hi.z or hi[3]
            end
            if ok and type(x2) == "number" and (x2 - x1) > 0.01 then
                local w = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) * 0.85
                return w, z2, (x1 + x2) / 2, (y1 + y2) / 2, (z2 or 0) - (z1 or 0), abs(x2 - x1), abs(y2 - y1)
            end
        end
    end
end

-- Pull the camera back until the model fills `fill` of the square view.
local function frameCamera(s)
    local a = s.actor
    local w, top, cx, cy, h, sx, sy = extent(a)
    if w and (s.fitHeight == "h" or s.fitHeight == "long") and h and h > 0.1 then
        -- measured the way the unit's Warcraft III model was (Engine/Sizes.lua): by its height, or for
        -- long, low things (beasts, machines, flyers) by 0.6 x its length if that is more. A rider
        -- sits on top of the mount, so a mount alone is about 70% of the pair's height.
        local m = h
        if s.hasRider then m = h * 1.4 end
        if s.fitHeight == "long" then m = max(m, 0.6 * max(sx or 0, sy or 0)) end
        -- a WoW model much broader than its WC3 counterpart (elementals, winged things) is shrunk
        -- until it is no more than 1.3 times as wide
        if s.capRatio then m = max(m, max(sx or 0, sy or 0) / s.capRatio) end
        w = m
    elseif w and s.fitHeight and h and h > 0.1 then
        -- units are sized by their height, so a long weapon, a cloak or a wide attack pose doesn't
        -- shrink one unit next to another (footprint still counts for long beasts and machines)
        w = max(h * 0.5, w * 0.6)
    end
    if not w then
        s.tries = (s.tries or 0) + 1
        w, top, cx, cy = s.guessW, 2, 0, 0
        if s.tries >= 40 then s.fitted = true end
    else
        -- a building's main part is kept no taller than its WC3 counterpart allows (tall towers
        -- fitted by their narrow footprint would otherwise reach two rows up the screen)
        if s.capHU and h and h > 0.1 then w = max(w, h * s.fill / s.capHU) end
        -- remember the size so the model doesn't "breathe" as its animation bounds change
        if s.fixedW then w = s.fixedW else s.fixedW = w end
        s.mTop, s.mSpan = top, max(sx or 0, sy or 0)
        s.fitted = true
        if s.hasRider and s.rider and not s.attached then pcall(s.rider.SetPosition, s.rider, 0, 0, (top or 1.6) * 0.5) end
        if s.gear then F.equip(s) end
    end
    orient(s)
    local view = w / s.fill
    local pad = s.pad or 1
    local yaw = s.yaw or 0
    local ox = (cx or 0) * cos(yaw) - (cy or 0) * sin(yaw)
    local oy = (cx or 0) * sin(yaw) + (cy or 0) * cos(yaw)
    if s.fixedW then ox, oy = 0, 0 end
    local p = s.pitch or pi / 2
    if p >= pi / 2 - 0.001 then
        -- straight down; pad > 1: a bigger frame around the same-sized model (the camera backs off to match)
        local d = (view / 2 / tan(FOV / 2) + (top or 2)) * pad
        s.camD = d
        local f = F.axes.fwd
        s.liftU, s.extra = 0, 1
        pcall(s.SetCameraPosition, s, ox - f[1] * d, oy - f[2] * d, -f[3] * d)
    else
        -- tilted: aim half way up the model, and move the frame up by the same amount on screen so
        -- the model's feet (its origin) stay on the unit's spot. Tall models (towers, halls) get a
        -- bigger frame, the camera backing off to match, so nothing is cut off at the frame's edge.
        local mt = s.mTop or top or 1
        local aimZ = mt * 0.5
        local c, n = cos(p), sin(p)
        local need = (mt * c + (s.mSpan or w) * n) * 1.15
        local extra = max(1, need / (view * pad))
        s.extra = extra
        local d = view * pad * extra / 2 / tan(FOV / 2) + mt
        s.camD = d
        s.liftU = aimZ * c / (view * pad)
        pcall(s.SetCameraPosition, s, ox - c * d, oy, aimZ + n * d)
    end
end

-- hand the model its weapons (tried a few ways; clients differ in what they accept)
local function equip(s)
    local g, a = s.gear, (s.hasRider and s.rider) or s.actor
    if not g or not a or s.geared == s.modelKey then return end
    s.geared = s.modelKey
    local function put(id, slot)
        if not id then return end
        local ok = pcall(a.TryOn, a, "item:" .. id, slot)
        if not ok then pcall(a.TryOn, a, id, slot) end
    end
    put(g.main, "MAINHANDSLOT")
    put(g.off, "SECONDARYHANDSLOT")
    pcall(a.SetSheathed, a, false)
end
F.equip = equip

local function setModel(s, model)
    local a = s.actor
    local mkey = (model.display or 0) .. ":" .. (model.file or 0) .. ":" .. (model.mount or 0) .. (model.gear and ":g" or "")
    if s.modelKey == mkey then return end
    if model.mount then
        -- the mount is the main model; the rider sits on its back (as in WarTable)
        pcall(a.SetModelByCreatureDisplayID, a, model.mount)
        if not s.rider then
            local ok, r = pcall(s.CreateActor, s)
            s.rider = ok and r or nil
        end
        if s.rider then
            pcall(s.rider.SetModelByCreatureDisplayID, s.rider, model.display)
            pcall(s.rider.Show, s.rider)
            pcall(s.rider.SetAnimation, s.rider, 91)    -- riding pose
            -- seat the rider on the mount's own saddle point, the way the mount journal does
            s.attached = false
            if a.AttachToMount then
                if a.CalculateMountScale and s.rider.SetRequestedScale then
                    local ok, sc = pcall(a.CalculateMountScale, a, s.rider)
                    if ok and type(sc) == "number" and sc > 0 then pcall(s.rider.SetRequestedScale, s.rider, 1 / sc) end
                end
                s.attached = pcall(a.AttachToMount, a, s.rider, 91, 0) and true or false
            end
        end
    elseif model.file then pcall(a.SetModelByFileID, a, model.file)
    else pcall(a.SetModelByCreatureDisplayID, a, model.display) end
    if not model.mount and s.rider then pcall(s.rider.Hide, s.rider) end
    s.hasRider = model.mount ~= nil
    pcall(a.SetPosition, a, 0, 0, 0)
    s.modelKey = mkey
    s.fitted, s.tries, s.fixedW = false, 0, nil
    s.anim = nil
    s.geared = nil
    s.gear = model.gear
end

local function take(group, key, parent, mkey)
    local g = F.groups[group]
    if not g then g = {} F.groups[group] = g end
    local s = g[key]
    if s then return s end
    local free = F.free[group]
    if free and #free > 0 then
        -- prefer an idle scene already holding this model (no reload)
        local pick = #free
        if mkey then
            for i = #free, max(1, #free - 30), -1 do
                if free[i].modelKey == mkey then pick = i break end
            end
        end
        s = table.remove(free, pick)
    else
        s = newScene(parent)
    end
    g[key] = s
    s.key = key
    return s
end

-- Place one figure.
-- model: { display = id } or { file = fileDataID }; cx, cy: centre in board units from the
-- board's top-left; size: the square view's size; fill: how much of it the model covers;
-- guess: model width to assume until it has loaded; yaw: actor yaw (F.yawFor); level: frame level
-- offset; anim: animation id; alpha: 0..1.
function F.place(group, key, parent, model, cx, cy, size, fill, guess, yaw, level, anim, alpha, animSpeed, animCycle)
    local mkey = (model.display or 0) .. ":" .. (model.file or 0) .. ":" .. (model.mount or 0) .. (model.gear and ":g" or "")
    local s = take(group, key, parent, mkey)
    local a = s.actor
    if not a then return end
    setModel(s, model)
    s.fill, s.guessW = fill, guess
    if s.pad ~= model.pad then s.pad = model.pad s.fitted = false end
    if s.fitHeight ~= model.fitHeight or s.capRatio ~= model.capRatio or s.capHU ~= model.capHU then
        s.fitHeight, s.capRatio, s.capHU = model.fitHeight, model.capRatio, model.capHU
        s.fixedW, s.fitted = nil, false
    end
    if s.yaw ~= yaw then
        pcall(a.SetYaw, a, yaw)
        if s.hasRider and s.rider and not s.attached then pcall(s.rider.SetYaw, s.rider, yaw) end
        s.yaw = yaw
        if not s.fixedW then s.fitted = false end
    end
    animSpeed = animSpeed or 1
    if s.anim ~= anim or (animCycle and s.animCycle ~= animCycle) then
        s.animCycle = animCycle
        pcall(a.SetAnimation, a, anim, 0, animSpeed)
        if s.hasRider and s.rider then
            -- the rider stays in the saddle, except when the pair goes down
            pcall(s.rider.SetAnimation, s.rider, (anim == 1 or anim == 6) and anim or 91)
        end
        s.anim, s.animSpeed = anim, animSpeed
    elseif s.animSpeed ~= animSpeed then
        -- change pace without restarting the cycle
        if a.SetAnimationSpeed then pcall(a.SetAnimationSpeed, a, animSpeed) end
        s.animSpeed = animSpeed
    end
    if not s.fitted or s.pitchWant ~= F.orientKey() then frameCamera(s) end
    if s.cx ~= cx or s.cy ~= cy or s.size ~= size or s.placedLift ~= s.liftU or s.placedExtra ~= s.extra then
        local fs = size * (s.extra or 1)
        s:ClearAllPoints()
        s:SetSize(fs, fs)
        s:SetPoint("CENTER", parent, "TOPLEFT", cx, -cy + (s.liftU or 0) * size)
        s.cx, s.cy, s.size, s.placedLift, s.placedExtra = cx, cy, size, s.liftU, s.extra
    end
    -- near and far clip planes a sensible distance either side of the model: with a near plane right
    -- at the camera the shallow depth buffer can't tell a model's near side from its far side (its far
    -- leg shows through its body). Set again whenever the zoom changes.
    if s.camD and (s.clipD ~= s.camD or s.clipZoom ~= UI.zoom) then
        pcall(s.SetCameraNearClip, s, max(0.05, s.camD * 0.35))
        pcall(s.SetCameraFarClip, s, s.camD * 3)
        s.clipD, s.clipZoom = s.camD, UI.zoom
    end
    local lv = parent:GetFrameLevel() + level
    if s.level ~= lv then s:SetFrameLevel(lv) s.level = lv end
    alpha = alpha or 1
    if s.alpha ~= alpha then s:SetAlpha(alpha) s.alpha = alpha end
    if not s:IsShown() then s:Show() end
    s.used = true
    return s
end

function F.begin(group)
    local g = F.groups[group]
    if g then for _, s in pairs(g) do s.used = false end end
end

-- hide everything in a group that wasn't placed since begin(); give it back to the pool
function F.finish(group)
    local g = F.groups[group]
    if not g then return end
    local free = F.free[group]
    if not free then free = {} F.free[group] = free end
    for key, s in pairs(g) do
        if not s.used then
            s:Hide()
            g[key] = nil
            s.cx = nil
            free[#free + 1] = s
        end
    end
end

function F.clear(group)
    F.begin(group)
    F.finish(group)
end

-- models load over a few frames; re-frame each camera once it knows its size
function F.tick()
    for _, g in pairs(F.groups) do
        for _, s in pairs(g) do
            if not s.fitted and s.actor then frameCamera(s) end
        end
    end
end

-- { mirror, extra turn } for each facing fix
-- The first is the default: on Chad's client models came out mirrored left-right with the
-- original maths (walking right but facing left, up and down correct), so that's fixed here.
F.FACE_MODES = {
    { -1, 0 }, { 1, 0 }, { -1, pi }, { 1, pi },
    { -1, pi / 2 }, { -1, -pi / 2 }, { 1, pi / 2 }, { 1, -pi / 2 },
}
F.FACE_NAMES = { "standard", "mirrored", "turned around", "mirrored and turned around",
    "quarter turn left", "quarter turn right", "mirrored, quarter turn left", "mirrored, quarter turn right" }

function F.cycleFacing()
    SkirmishDB.facing = ((SkirmishDB.facing or 1) % #F.FACE_MODES) + 1
    for _, g in pairs(F.groups) do for _, sc in pairs(g) do sc.yaw = nil end end
    return SkirmishDB.facing, F.FACE_NAMES[SkirmishDB.facing]
end

function F.liveCount()
    local n = 0
    for _, g in pairs(F.groups) do for _ in pairs(g) do n = n + 1 end end
    return n
end
