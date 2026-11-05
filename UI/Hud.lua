-- Skirmish: the resource bar, the selection panel, the command card, messages, the game menu and
-- the end-of-game screen.

local ADDON, ns = ...
local E = ns.Engine
local D, M, S = E.Data, E.Map, E.Sim
local UI = ns.UI
local H = {}
UI.Hud = H

local floor, min, max = math.floor, math.min, math.max
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- hotkeys for things you train or build
-- hotkeys come from the data (def.key), as in Warcraft III

local function setIcon(t, path)
    local ok = t:SetTexture(path or QUESTION)
    if ok == false then t:SetTexture(QUESTION) end
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
end

-- ------------------------------------------------------------------ building

local function topBar(f)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -14)
    title:SetText("Warcraft Simulator")
    local x = 150
    local function res(icon, w)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetSize(16, 16)
        t:SetPoint("TOPLEFT", x, -14)
        setIcon(t, icon)
        local s = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s:SetPoint("LEFT", t, "RIGHT", 5, 0)
        x = x + w
        return s
    end
    H.goldText = res("Interface\\Icons\\INV_Misc_Coin_01", 110)
    H.lumberText = res("Interface\\Icons\\INV_Misc_Branch_01", 110)
    H.supplyText = res("Interface\\Icons\\INV_Misc_Food_15", 230)
    H.clockText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    H.clockText:SetPoint("TOPLEFT", x + 10, -15)
    H.fpsText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    H.fpsText:SetPoint("TOPRIGHT", f, "TOPLEFT", UI.VIEW_X + UI.VIEW_W - 6, -UI.VIEW_Y - UI.VIEW_H - 2)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    local menu = UI.button(f, "Menu (F10)", 96, 20)
    menu:SetPoint("TOPRIGHT", -40, -12)
    menu:SetScript("OnClick", function() H.showMenu() end)
    local pause = UI.button(f, "Pause", 64, 20)
    pause:SetPoint("RIGHT", menu, "LEFT", -6, 0)
    pause:SetScript("OnClick", function() UI.paused = not UI.paused end)
    H.pauseBtn = pause
    local speed = UI.button(f, "Speed: normal", 108, 20)
    H.speedBtn = speed
    speed:SetPoint("RIGHT", pause, "LEFT", -6, 0)
    speed:SetScript("OnClick", function()
        UI.speed = UI.speed == 1 and 1.5 or 1
        speed:SetText(UI.speed == 1 and "Speed: normal" or "Speed: fast")
    end)
    local face = UI.button(f, "Fix facing", 92, 20)
    face:SetPoint("RIGHT", speed, "LEFT", -6, 0)
    face:SetScript("OnClick", function()
        local n, name = UI.Figures.cycleFacing()
        UI.dirtyStatic = true
        H.message("Model facing " .. n .. " of 8: " .. name .. ". Click again if units still walk backwards.")
    end)
    face:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Fix facing")
        GameTooltip:AddLine("If units walk backwards or sideways, click until they face the way they move. It's remembered.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    face:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local bigger = UI.button(f, "+", 24, 20)
    bigger:SetPoint("RIGHT", face, "LEFT", -8, 0)
    bigger:SetScript("OnClick", function() UI.rescale(0.05) end)
    local smaller = UI.button(f, "-", 24, 20)
    smaller:SetPoint("RIGHT", bigger, "LEFT", -2, 0)
    smaller:SetScript("OnClick", function() UI.rescale(-0.05) end)
end

local function messages(view)
    H.msg = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    H.msg:SetPoint("TOP", view, "TOP", 0, -40)
    H.msg:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
    H.msgT = 0
    H.err = view:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    H.err:SetPoint("BOTTOM", view, "BOTTOM", 0, 60)
    H.err:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
    H.err:SetTextColor(1, 0.25, 0.2)
    H.errT = 0
    H.hover = view:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    H.hover:SetPoint("TOPLEFT", view, "TOPLEFT", 64, -8)
    H.hover:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    H.paused = view:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    H.paused:SetPoint("CENTER", view, "CENTER", 0, 40)
    H.paused:SetText("PAUSED")
    H.paused:Hide()
    -- all of these sit above the map layers
    local holder = CreateFrame("Frame", nil, view)
    holder:SetAllPoints()
    holder:SetFrameLevel(UI.overLayer:GetFrameLevel() + 20)
    for _, fs in ipairs({ H.msg, H.err, H.hover, H.paused }) do fs:SetParent(holder) end
end

local function cardButton(parent, i)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(54, 54)
    local col, row = (i - 1) % 4, floor((i - 1) / 4)
    b:SetPoint("TOPLEFT", 8 + col * 58, -8 - row * 58)
    b:SetBackdrop({ bgFile = UI.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    b:SetBackdropColor(0, 0, 0, 0.6)
    b:SetBackdropBorderColor(0.5, 0.45, 0.35, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3)
    b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    b.cd = b:CreateTexture(nil, "OVERLAY")
    b.cd:SetTexture(UI.WHITE)
    b.cd:SetVertexColor(0, 0, 0, 0.65)
    b.cd:SetPoint("TOPLEFT", 3, -3)
    b.cd:SetPoint("TOPRIGHT", -3, -3)
    b.key = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.key:SetPoint("TOPLEFT", 5, -4)
    b.key:SetTextColor(1, 0.85, 0.3)
    b.active = b:CreateTexture(nil, "OVERLAY")
    b.active:SetTexture(UI.WHITE)
    b.active:SetVertexColor(0.3, 1, 0.3, 0.25)
    b.active:SetAllPoints(b.icon)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(b.icon)
    -- autocast border (Heal, Slow, Bloodlust, Inner Fire): gold when on
    b.auto = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.auto:SetTexture("Interface\\Buttons\\UI-AutoCastableOverlay")
    b.auto:SetPoint("TOPLEFT", -12, 12)
    b.auto:SetPoint("BOTTOMRIGHT", 12, -12)
    b.auto:Hide()
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, btn)
        local e = self.entry
        if not e then return end
        if btn == "RightButton" and e.onRightClick then e.onRightClick() H.dirty = true
        elseif e.onClick then e.onClick() end
    end)
    b:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine(e.name .. (e.key and ("  |cffffd100(" .. e.key .. ")|r") or ""))
        if e.cost then
            local parts = {}
            if (e.cost.gold or 0) > 0 then parts[#parts + 1] = "|cffffd100" .. e.cost.gold .. " gold|r" end
            if (e.cost.lumber or 0) > 0 then parts[#parts + 1] = "|cff66dd66" .. e.cost.lumber .. " lumber|r" end
            if (e.cost.supply or 0) > 0 then parts[#parts + 1] = e.cost.supply .. " supply" end
            if e.cost.mana then parts[#parts + 1] = "|cff6699ff" .. e.cost.mana .. " mana|r" end
            if #parts > 0 then GameTooltip:AddLine(table.concat(parts, "   "), 1, 1, 1) end
        end
        if e.tip then GameTooltip:AddLine(e.tip, 0.85, 0.85, 0.85, true) end
        if e.why then GameTooltip:AddLine(e.why, 1, 0.3, 0.3, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

local function panel(f)
    local p = CreateFrame("Frame", nil, f, "BackdropTemplate")
    p:SetPoint("BOTTOMLEFT", 228, 12)
    p:SetSize(754, 212)
    p:SetBackdrop({ bgFile = UI.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    p:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
    p:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    H.panel = p

    local port = CreateFrame("PlayerModel", nil, p)
    port:SetSize(120, 120)
    port:SetPoint("TOPLEFT", 12, -12)
    H.portrait = port
    local pbg = p:CreateTexture(nil, "BACKGROUND", nil, 1)
    pbg:SetTexture(UI.WHITE)
    pbg:SetVertexColor(0.12, 0.1, 0.08, 1)
    pbg:SetAllPoints(port)

    H.name = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    H.name:SetPoint("TOPLEFT", 148, -14)
    H.sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    H.sub:SetPoint("TOPLEFT", H.name, "BOTTOMLEFT", 0, -4)
    H.lines = {}
    for i = 1, 6 do
        local s = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s:SetPoint("TOPLEFT", 148, -52 - (i - 1) * 18)
        s:SetJustifyH("LEFT")
        s:SetWidth(470)
        s:SetWordWrap(false)
        H.lines[i] = s
    end
    -- hp / mana under the portrait
    H.hpText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    H.hpText:SetPoint("TOP", port, "BOTTOM", 0, -6)
    H.manaText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    H.manaText:SetPoint("TOP", H.hpText, "BOTTOM", 0, -3)
    H.manaText:SetTextColor(0.4, 0.6, 1)

    -- training queue / multi-selection icons
    H.icons = {}
    for i = 1, 24 do
        local b = CreateFrame("Button", nil, p, "BackdropTemplate")
        b:SetSize(40, 40)
        b:SetBackdrop({ bgFile = UI.WHITE })
        b:SetBackdropColor(0, 0, 0, 0.8)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 6)
        b.bar = b:CreateTexture(nil, "OVERLAY")
        b.bar:SetTexture(UI.WHITE)
        b.bar:SetPoint("BOTTOMLEFT", 2, 1)
        b.bar:SetHeight(4)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, btn) if self.onClick then self.onClick(btn) end end)
        b:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tip)
            if self.tip2 then GameTooltip:AddLine(self.tip2, 0.8, 0.8, 0.8) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        H.icons[i] = b
    end

    -- the hero's inventory: six slots (WC3 numpad keys 7 8 / 4 5 / 1 2)
    H.inv = {}
    local INVKEY = { "7", "8", "4", "5", "1", "2" }
    for i = 1, 6 do
        local b = CreateFrame("Button", nil, p, "BackdropTemplate")
        b:SetSize(40, 40)
        b:SetPoint("TOPRIGHT", -12 - ((i % 2 == 1) and 44 or 0), -30 - floor((i - 1) / 2) * 44)
        b:SetBackdrop({ bgFile = UI.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        b:SetBackdropColor(0, 0, 0, 0.7)
        b:SetBackdropBorderColor(0.5, 0.45, 0.3, 1)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 3, -3)
        b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", -3, 3)
        b.key = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.key:SetPoint("TOPLEFT", 4, -3)
        b.key:SetTextColor(1, 0.85, 0.3)
        b.key:SetText(INVKEY[i])
        b.cd = b:CreateTexture(nil, "OVERLAY")
        b.cd:SetTexture(UI.WHITE)
        b.cd:SetVertexColor(0, 0, 0, 0.65)
        b.cd:SetPoint("TOPLEFT", 3, -3)
        b.cd:SetPoint("TOPRIGHT", -3, -3)
        b.slot = i
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, btn) H.useSlot(self.slot, btn == "RightButton") end)
        b:SetScript("OnEnter", function(self)
            local w = UI.w
            local h = w and UI.sel[1] and w.ents[UI.sel[1]]
            local s = h and h.inv and h.inv[self.slot]
            local it = s and D.Items[s.id]
            if not it then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(it.name .. "  |cffffd100(" .. INVKEY[self.slot] .. ")|r")
            if it.tip and it.tip ~= "" then GameTooltip:AddLine(it.tip, 1, 1, 1, true) end
            GameTooltip:AddLine((it.class == "permanent" and not (it.teleport or it.sanctuary)) and "Works on its own." or "Left-click to use.", 0.6, 0.8, 1)
            GameTooltip:AddLine("Right-click: sell (next to a shop) or drop.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        H.inv[i] = b
    end

    local card = CreateFrame("Frame", nil, f, "BackdropTemplate")
    card:SetPoint("BOTTOMRIGHT", -10, 12)
    card:SetSize(248, 186)
    card:SetBackdrop({ bgFile = UI.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    card:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
    card:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    H.card = {}
    for i = 1, 12 do H.card[i] = cardButton(card, i) end
end

-- ------------------------------------------------------------------ menu & end screen

local function choiceRow(parent, y, label, options, get, set, width)
    width = width or 100
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", 30, y)
    l:SetText(label)
    local btns = {}
    for i, o in ipairs(options) do
        local b = UI.button(parent, o[2], width, 22)
        b:SetPoint("TOPLEFT", 170 + (i - 1) * (width + 6), y + 4)
        b:SetScript("OnClick", function() set(o[1]) for _, bb in ipairs(btns) do bb.refresh() end end)
        b.refresh = function()
            if get() == o[1] then b:LockHighlight() else b:UnlockHighlight() end
        end
        btns[#btns + 1] = b
    end
    return btns
end

local function buildMenu(f)
    -- the start screen: pick a race and a difficulty and play. Everything else is under Options.
    local m = CreateFrame("Frame", nil, f, "BackdropTemplate")
    m:SetSize(470, 300)
    m:SetPoint("CENTER", UI.view, "CENTER")
    m:SetFrameLevel(UI.overLayer:GetFrameLevel() + 60)
    UI.backdrop(m, true)
    m:EnableMouse(true)
    local t = m:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    t:SetPoint("TOP", 0, -22)
    t:SetText("Warcraft Simulator")
    local st = m:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    st:SetPoint("TOP", t, "BOTTOM", 0, -6)
    st:SetText("Destroy every enemy building to win.")
    local rows = {}
    local function add(r) for _, b in ipairs(r) do rows[#rows + 1] = b end end
    -- big centred choice rows
    local function bigRow(y, label, options, get, set, width)
        local l = m:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOP", 0, y)
        l:SetText(label)
        local btns = {}
        local total = #options * width + (#options - 1) * 6
        for i, o in ipairs(options) do
            local bt = UI.button(m, o[2], width, 26)
            bt:SetPoint("TOPLEFT", (470 - total) / 2 + (i - 1) * (width + 6), y - 20)
            bt:SetScript("OnClick", function() set(o[1]) for _, bb in ipairs(btns) do bb.refresh() end end)
            bt.refresh = function() if get() == o[1] then bt:LockHighlight() else bt:UnlockHighlight() end end
            btns[#btns + 1] = bt
        end
        add(btns)
    end
    bigRow(-78, "Play as", { { "alliance", "Alliance" }, { "orcs", "Orcs" }, { "undead", "Undead" }, { "nightelf", "Night Elves" } },
        function() return SkirmishDB.faction or "alliance" end, function(v) SkirmishDB.faction = v end, 100)
    bigRow(-140, "Difficulty", { { "easy", "Easy" }, { "normal", "Normal" }, { "hard", "Hard" } },
        function() return SkirmishDB.level or "normal" end, function(v) SkirmishDB.level = v end, 100)

    local start = UI.button(m, "Play", 180, 34)
    start:SetPoint("BOTTOM", 0, 62)
    start:SetScript("OnClick", function()
        -- in a multiplayer game this button leaves it (a loss)
        if UI.Net and UI.Net.session then UI.Net.leave() H.hideMenu() return end
        UI.newGame({})
    end)
    H.playBtn = start
    local resume = UI.button(m, "Resume", 120, 26)
    resume:SetPoint("BOTTOM", m, "BOTTOM", -126, 24)
    resume:SetScript("OnClick", function() H.hideMenu() end)
    H.resumeBtn = resume
    local multi = UI.button(m, "Multiplayer", 120, 26)
    multi:SetPoint("BOTTOM", m, "BOTTOM", 0, 24)
    local opts = UI.button(m, "Options", 120, 26)
    opts:SetPoint("BOTTOM", m, "BOTTOM", 126, 24)
    m.rows = rows
    m:Hide()
    H.menu = m

    -- Options: the rest of the settings, and the controls
    local o = CreateFrame("Frame", nil, f, "BackdropTemplate")
    o:SetSize(640, 560)
    o:SetPoint("CENTER", UI.view, "CENTER")
    o:SetFrameLevel(UI.overLayer:GetFrameLevel() + 61)
    UI.backdrop(o, true)
    o:EnableMouse(true)
    local ot = o:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ot:SetPoint("TOP", 0, -20)
    ot:SetText("Options")
    local orows = {}
    local function oadd(r) for _, b in ipairs(r) do orows[#orows + 1] = b end end
    oadd(choiceRow(o, -60, "Enemy race", { { "random", "Random" }, { "alliance", "Alliance" }, { "orcs", "Orcs" }, { "undead", "Undead" }, { "nightelf", "Night Elves" } },
        function() return SkirmishDB.enemy or "random" end, function(v) SkirmishDB.enemy = (v ~= "random") and v or nil end, 84))
    -- the map: Blizzard's own 1v1 maps, or one of the two made for this game. Click for the next, right-click for the previous.
    do
        local list = { { "classic", "Twin Groves (64x64)" }, { "crossing", "Lordaeron Crossing (80x80)" } }
        local ids = {}
        for id in pairs(D.WC3MAPS or {}) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return D.WC3MAPS[a].name < D.WC3MAPS[b].name end)
        for _, id in ipairs(ids) do local mp = D.WC3MAPS[id] list[#list + 1] = { id, string.format("%s (%dx%d)", mp.name, mp.w, mp.h) } end
        local l = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", 30, -92)
        l:SetText("Map")
        local b = UI.button(o, "", 300, 22)
        b:SetPoint("TOPLEFT", 170, -88)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local function cur()
            for i, e in ipairs(list) do if e[1] == (SkirmishDB.map or "classic") then return i end end
            return 1
        end
        b.refresh = function() b:SetText(list[cur()][2]) end
        b:SetScript("OnClick", function(_, btn)
            local i = cur() + (btn == "RightButton" and -1 or 1)
            if i < 1 then i = #list elseif i > #list then i = 1 end
            SkirmishDB.map = list[i][1]
            b.refresh()
        end)
        local hint = o:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("LEFT", b, "RIGHT", 8, 0)
        hint:SetText("click: next  right-click: back")
        oadd({ b })
    end
    oadd(choiceRow(o, -124, "Fog of war", { { true, "On" }, { false, "Off" } },
        function() return SkirmishDB.fog ~= false end, function(v) SkirmishDB.fog = v end))
    oadd(choiceRow(o, -156, "Gold & lumber", { { false, "Normal" }, { true, "Unlimited" } },
        function() return SkirmishDB.cheat == true end, function(v) SkirmishDB.cheat = v or nil end))
    oadd(choiceRow(o, -188, "Build & research", { { 1, "Normal" }, { 10, "10x faster" }, { 1000, "Instant" } },
        function() return SkirmishDB.buildSpeed or 1 end, function(v) SkirmishDB.buildSpeed = (v ~= 1) and v or nil end))
    oadd(choiceRow(o, -220, "Sound", { { true, "On" }, { false, "Off" } },
        function() return SkirmishDB.sound ~= false end, function(v) SkirmishDB.sound = v end))
    oadd(choiceRow(o, -252, "Edge scrolling", { { true, "On" }, { false, "Off" } },
        function() return SkirmishDB.edgeScroll ~= false end, function(v) SkirmishDB.edgeScroll = v end))
    oadd(choiceRow(o, -284, "Camera", { { "wc3", "Warcraft III angle" }, { "top", "Straight down" } },
        function() return SkirmishDB.camera or "wc3" end, function(v) SkirmishDB.camera = (v ~= "wc3") and v or nil UI.dirtyStatic = true end, 140))
    oadd(choiceRow(o, -316, "Unit size", { { 1, "Small" }, { 2, "Normal" }, { 3, "Large" } },
        function() return SkirmishDB.unitSize or 2 end, function(v) SkirmishDB.unitSize = (v ~= 2) and v or nil end))
    oadd(choiceRow(o, -348, "Tree models", { { "all", "Every tree" }, { "dense", "Dense" }, { "light", "Edges only" }, { "flat", "Off" } },
        function() return SkirmishDB.trees or "dense" end, function(v) SkirmishDB.trees = v UI.Draw.treeMode = v UI.dirtyStatic = true end))
    oadd(choiceRow(o, -380, "Minimap camps", { { true, "Show" }, { false, "Hide" } },
        function() return SkirmishDB.miniCamps ~= false end, function(v) SkirmishDB.miniCamps = v end))
    local help = o:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 30, -420)
    help:SetWidth(580)
    help:SetJustifyH("LEFT")
    help:SetSpacing(3)
    help:SetText("|cffffd100Controls|r\n" ..
        "Left-click or drag to select. Right-click to move, attack, gather or set a rally point.\n" ..
        "Letters press the command buttons (A attack, P patrol, S stop, B build...). Shift queues orders. Tab cycles unit types.\n" ..
        "Ctrl+1-5 makes a group, 1-5 selects it (twice to jump there). F1-F3 select your heroes. Space jumps to the last attack.\n" ..
        "Mouse wheel zooms. Arrow keys, the screen edges or middle-drag scroll. Esc cancels, then closes the window (pausing the game).")
    local back = UI.button(o, "Back", 120, 26)
    back:SetPoint("BOTTOM", 0, 20)
    back:SetScript("OnClick", function() o:Hide() m:Show() end)
    o.rows = orows
    o:Hide()
    H.options = o
    opts:SetScript("OnClick", function()
        for _, b in ipairs(orows) do b.refresh() end
        m:Hide() o:Show()
    end)

    -- Multiplayer: invite another player (who has the addon) to a 1v1
    local mp = CreateFrame("Frame", nil, f, "BackdropTemplate")
    mp:SetSize(470, 300)
    mp:SetPoint("CENTER", UI.view, "CENTER")
    mp:SetFrameLevel(UI.overLayer:GetFrameLevel() + 61)
    UI.backdrop(mp, true)
    mp:EnableMouse(true)
    local mt = mp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    mt:SetPoint("TOP", 0, -20)
    mt:SetText("Multiplayer (1v1)")
    local info = mp:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOP", 0, -52)
    info:SetWidth(420)
    info:SetSpacing(3)
    mp.info = info
    local nl = mp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nl:SetPoint("TOPLEFT", 40, -138)
    nl:SetText("Player name")
    local eb = CreateFrame("EditBox", nil, mp, "InputBoxTemplate")
    eb:SetSize(200, 22)
    eb:SetPoint("LEFT", nl, "RIGHT", 16, 0)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    mp.name = eb
    local inv = UI.button(mp, "Invite", 90, 24)
    inv:SetPoint("LEFT", eb, "RIGHT", 10, 0)
    local status = mp:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOP", 0, -180)
    status:SetWidth(420)
    mp.status = status
    local function doInvite()
        eb:ClearFocus()
        local ok, why = UI.Net.invite(eb:GetText())
        if ok then status:SetText("Invitation sent to " .. eb:GetText() .. ". Waiting for an answer...")
        else status:SetText("|cffff6060" .. why .. "|r") end
    end
    inv:SetScript("OnClick", doInvite)
    eb:SetScript("OnEnterPressed", doInvite)
    local mback = UI.button(mp, "Back", 120, 26)
    mback:SetPoint("BOTTOM", 0, 20)
    mback:SetScript("OnClick", function()
        if UI.Net.pending then UI.Net.cancelInvite() end
        mp:Hide() m:Show()
    end)
    mp:Hide()
    H.multi = mp
    multi:SetScript("OnClick", function()
        local race = D.Factions[SkirmishDB.faction or "alliance"]
        info:SetText(string.format("Both players need Warcraft Simulator %s and must be on the same realm.\n" ..
            "You play as |cffffd100%s|r. As the host, your map and fog settings are used.\n" ..
            "Type the other player's name (or target them) and press Invite.", UI.Net.VERSION, race and race.name or "Alliance"))
        local tn = UnitIsPlayer and UnitIsPlayer("target") and UnitName("target")
        if tn and tn ~= UnitName("player") then eb:SetText(tn) end
        status:SetText("")
        m:Hide() mp:Show()
    end)

    -- the end-of-game score screen, laid out like Warcraft III's: Overview / Units / Heroes / Resources
    local en = CreateFrame("Frame", nil, f, "BackdropTemplate")
    en:SetSize(660, 460)
    en:SetPoint("CENTER", UI.view, "CENTER")
    en:SetFrameLevel(UI.overLayer:GetFrameLevel() + 60)
    UI.backdrop(en, true)
    en:EnableMouse(true)
    en.title = en:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    en.title:SetPoint("TOP", 0, -20)
    en.tabs = {}
    local TABS = { "Overview", "Units", "Heroes", "Resources" }
    for i, name in ipairs(TABS) do
        local t = UI.button(en, name, 120, 24)
        t:SetPoint("TOPLEFT", 70 + (i - 1) * 132, -58)
        t:SetScript("OnClick", function() H.endTab = i H.fillEnd() end)
        en.tabs[i] = t
    end
    -- column headings + up to 6 rows of label / you / enemy
    en.lines = {}
    for i = 1, 7 do
        local row = {}
        for j = 1, 3 do
            local fs = en:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormal" or "GameFontHighlight")
            fs:SetPoint("TOPLEFT", j == 1 and 50 or (j == 2 and 330 or 480), -100 - (i - 1) * 24)
            fs:SetWidth(j == 1 and 270 or 140)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row[j] = fs
        end
        en.lines[i] = row
    end
    -- hero portraits (Heroes tab)
    en.heroIcons = {}
    for p = 1, 2 do
        en.heroIcons[p] = {}
        for k = 1, 3 do
            local ic = en:CreateTexture(nil, "ARTWORK")
            ic:SetSize(30, 30)
            ic:SetPoint("TOPLEFT", (p == 1 and 330 or 480) + (k - 1) * 34, -120)
            ic:Hide()
            local lv = en:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            lv:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 0, 0)
            en.heroIcons[p][k] = { ic = ic, lv = lv }
        end
    end
    -- the graph (Overview): army size over the game
    local g = CreateFrame("Frame", nil, en, "BackdropTemplate")
    g:SetSize(560, 130)
    g:SetPoint("BOTTOM", 0, 62)
    g:SetBackdrop({ bgFile = UI.WHITE })
    g:SetBackdropColor(0, 0, 0, 0.45)
    g.label = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    g.label:SetPoint("BOTTOMLEFT", g, "TOPLEFT", 0, 3)
    g.label:SetText("Army size (food) over time")
    g.lines = {}
    g.peak = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g.peak:SetPoint("TOPRIGHT", g, "TOPRIGHT", -4, -3)
    en.graph = g
    local again = UI.button(en, "Play again", 130, 26)
    again:SetPoint("BOTTOM", -70, 20)
    again:SetScript("OnClick", function() UI.newGame({}) end)
    local look = UI.button(en, "Look around", 130, 26)
    look:SetPoint("BOTTOM", 70, 20)
    look:SetScript("OnClick", function() en:Hide() end)
    en:Hide()
    H.endFrame = en
end

function H.showMenu()
    if not H.menu then return end
    for _, b in ipairs(H.menu.rows) do b.refresh() end
    H.resumeBtn:SetEnabled(UI.w ~= nil and not UI.w.over)
    H.playBtn:SetText((UI.Net and UI.Net.session) and "Leave game" or "Play")
    H.menu:Show()
    UI.menuPause = true
end
function H.hideMenu() if H.menu then H.menu:Hide() end if H.options then H.options:Hide() end if H.multi then H.multi:Hide() end UI.menuPause = false end
function H.menuShown() return (H.menu and H.menu:IsShown()) or (H.options and H.options:IsShown()) or (H.multi and H.multi:IsShown()) end
function H.hideMulti() if H.multi then H.multi:Hide() end end
function H.multiStatus(text) if H.multi then H.multi.status:SetText(text) end end
function H.hideEnd() if H.endFrame then H.endFrame:Hide() end end

-- WC3-style scores. Blizzard never published the exact formulas, so these weigh the same things
-- (kills, razing, heroes, gathering) in the same spirit.
function H.scores(w, p)
    local st = w.players[p].stats
    local unit = st.trained * 10 + st.killed * 10 + st.razed * 25 + (st.largest or 0) * 5
    local hero = (st.heroKills or 0) * 100 + (st.items or 0) * 20 + (st.hired or 0) * 15 + floor((st.xp or 0) / 10)
    local res = floor((st.gold + st.lumber) / 10) + floor(H.techPct(w, p) * 2)
    return unit, hero, res, unit + hero + res
end

function H.techPct(w, p)
    local pl = w.players[p]
    local have, total = 0, 0
    for id, r in pairs(D.Research) do
        if r.faction == pl.faction then
            total = total + (r.levels or 1)
            have = have + min(r.levels or 1, pl.research[id] or 0)
        end
    end
    return total > 0 and floor(have / total * 100 + 0.5) or 0
end

local function setRows(en, rows)
    for i = 1, 7 do
        local r = rows[i]
        for j = 1, 3 do en.lines[i][j]:SetText(r and tostring(r[j]) or "") end
    end
end

function H.fillEnd()
    local en, w = H.endFrame, UI.w
    if not en or not w then return end
    local tab = H.endTab or 1
    for i, t in ipairs(en.tabs) do if i == tab then t:LockHighlight() else t:UnlockHighlight() end end
    local p1, p2 = w.players[1], w.players[2]
    local s1, s2 = p1.stats, p2.stats
    local head = { "", D.Factions[p1.faction].short .. (UI.me == 1 and " (you)" or ""), D.Factions[p2.faction].short .. (UI.me == 2 and " (you)" or "") }
    for p = 1, 2 do for k = 1, 3 do en.heroIcons[p][k].ic:Hide() en.heroIcons[p][k].lv:SetText("") end end
    en.graph:SetShown(tab == 1)
    if tab == 1 then
        local u1, h1, r1, t1 = H.scores(w, 1)
        local u2, h2, r2, t2 = H.scores(w, 2)
        setRows(en, { head, { "Unit score", u1, u2 }, { "Hero score", h1, h2 }, { "Resource score", r1, r2 },
            { "|cffffd100Total score|r", "|cffffd100" .. t1 .. "|r", "|cffffd100" .. t2 .. "|r" },
            { "Game time", string.format("%d:%02d", floor(w.time / 60), floor(w.time % 60)), "" } })
        H.drawGraph(w)
    elseif tab == 2 then
        setRows(en, { head, { "Units produced", s1.trained, s2.trained }, { "Units killed", s1.killed, s2.killed },
            { "Buildings produced", s1.built, s2.built }, { "Buildings razed", s1.razed, s2.razed },
            { "Largest army", s1.largest or 0, s2.largest or 0 }, { "Units lost", s1.lost, s2.lost } })
    elseif tab == 3 then
        setRows(en, { head, { "Heroes", "", "" }, { "", "", "" }, { "Heroes killed", s1.heroKills or 0, s2.heroKills or 0 },
            { "Items obtained", s1.items or 0, s2.items or 0 }, { "Mercenaries hired", s1.hired or 0, s2.hired or 0 },
            { "Experience gained", s1.xp or 0, s2.xp or 0 } })
        for p = 1, 2 do
            local k = 0
            local pl = w.players[p]
            local function add(def, lvl, dead)
                k = k + 1
                if k > 3 or not def then return end
                local slot = en.heroIcons[p][k]
                setIcon(slot.ic, def.icon)
                slot.ic:SetDesaturated(dead and true or false)
                slot.ic:Show()
                slot.lv:SetText(lvl or 1)
            end
            for _, id in ipairs(pl.heroes or {}) do local h = w.ents[id] if h and not h.illusion then add(h.def, h.level) end end
            for _, rec in ipairs(pl.deadHeroes or {}) do add(D.Units[rec.id], rec.level, true) end
        end
    else
        setRows(en, { head, { "Gold mined", s1.gold, s2.gold }, { "Lumber harvested", s1.lumber, s2.lumber },
            { "Gold lost to upkeep", s1.upkeepLost or 0, s2.upkeepLost or 0 },
            { "Tech percentage", H.techPct(w, 1) .. "%", H.techPct(w, 2) .. "%" },
            { "Creeps killed", s1.creeps or 0, s2.creeps or 0 } })
    end
end

function H.drawGraph(w)
    local g = H.endFrame.graph
    for _, l in ipairs(g.lines) do l:Hide() end
    local n = 0
    local function line(x1, y1, x2, y2, r, gg, b)
        n = n + 1
        local l = g.lines[n]
        if not l then
            if not g.CreateLine then return end
            l = g:CreateLine(nil, "ARTWORK")
            l:SetTexture(UI.WHITE)
            l:SetThickness(2)
            g.lines[n] = l
        end
        l:SetColorTexture(r, gg, b, 1)
        l:SetStartPoint("BOTTOMLEFT", g, x1, y1)
        l:SetEndPoint("BOTTOMLEFT", g, x2, y2)
        l:Show()
    end
    local peak, last = 1, 1
    for p = 1, 2 do
        for _, h in ipairs(w.players[p].stats.hist or {}) do peak = max(peak, h[2]) last = max(last, h[1]) end
    end
    last = max(last, w.time)
    local W, Hh = 552, 120
    for p = 1, 2 do
        local hist = w.players[p].stats.hist or {}
        local c = p == UI.me and { 0.25, 1, 0.25 } or { 1, 0.3, 0.25 }
        local px, py
        for _, h in ipairs(hist) do
            local x, y = 4 + h[1] / last * W, 4 + h[2] / peak * Hh
            if px then line(px, py, x, y, c[1], c[2], c[3]) end
            px, py = x, y
        end
    end
    g.peak:SetText("peak " .. peak .. " food")
end

function H.showEnd(won)
    local en = H.endFrame
    en.title:SetText(won and "|cff40ff40Victory!|r" or "|cffff4040Defeat|r")
    H.endTab = 1
    H.fillEnd()
    en:Show()
end

-- WC3's idle worker button: shows how many workers are doing nothing; click (or F8) to pick the next one
-- WC3's hero bar: a portrait for each of your heroes down the left edge of the view, with health,
-- mana and level. Click to select, double-click to jump there. A "+" shows unspent skill points.
local function heroBar(view)
    H.heroBtns = {}
    for i = 1, 3 do
        local b = CreateFrame("Button", nil, view, "BackdropTemplate")
        b:SetSize(44, 44)
        b:SetPoint("TOPLEFT", view, "TOPLEFT", 8, -8 - (i - 1) * 64)
        b:SetFrameLevel(UI.overLayer:GetFrameLevel() + 25)
        b:SetBackdrop({ bgFile = UI.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        b:SetBackdropColor(0, 0, 0, 0.75)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 3, -3)
        b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        b.level = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.level:SetPoint("BOTTOMRIGHT", -3, 3)
        b.plus = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        b.plus:SetPoint("TOPRIGHT", 0, 1)
        b.plus:SetText("|cffffd100+|r")
        b.hpBg = b:CreateTexture(nil, "BACKGROUND")
        b.hpBg:SetTexture(UI.WHITE)
        b.hpBg:SetVertexColor(0, 0, 0, 0.8)
        b.hpBg:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 1, -1)
        b.hpBg:SetSize(42, 11)
        b.hp = b:CreateTexture(nil, "ARTWORK")
        b.hp:SetTexture(UI.WHITE)
        b.hp:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 2, -2)
        b.hp:SetHeight(4)
        b.mp = b:CreateTexture(nil, "ARTWORK")
        b.mp:SetTexture(UI.WHITE)
        b.mp:SetVertexColor(0.25, 0.45, 1)
        b.mp:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 2, -7)
        b.mp:SetHeight(4)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, btn)
            local w = UI.w
            local h = w and self.unit and w.ents[self.unit]
            if not S.alive(h) then return end
            if btn == "RightButton" then
                -- right-click a hero portrait: send the selection to it (follow / help)
                local units = UI.Input.ownUnits()
                if #units > 0 then UI.Input.smartAt(h.x, h.y, h) end
                return
            end
            local now = GetTime()
            if (self.lastT and now - self.lastT < 0.4) or (#UI.sel == 1 and UI.sel[1] == h.id) then UI.lookAt(h.x, h.y) end
            self.lastT = now
            UI.Input.setSelection({ h.id })
        end)
        b:SetScript("OnEnter", function(self)
            local w = UI.w
            local h = w and self.unit and w.ents[self.unit]
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if h then
                GameTooltip:AddLine(h.def.name .. "  level " .. (h.level or 1) .. "  |cffffd100(F" .. self.idx .. ")|r")
                GameTooltip:AddLine(floor(h.hp) .. " / " .. h.maxhp .. " health   " .. floor(h.mana or 0) .. " / " .. (h.maxMana or 0) .. " mana", 1, 1, 1)
                if (h.points or 0) > 0 then GameTooltip:AddLine("Skill point to spend", 1, 0.82, 0) end
            elseif self.dead then
                GameTooltip:AddLine(self.dead .. "  |cffff4040(dead)|r")
                GameTooltip:AddLine("Revive at your altar.", 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b.idx = i
        b:Hide()
        H.heroBtns[i] = b
    end
end

function H.updateHeroBar(w)
    local pl = w.players[UI.me]
    local list = {}
    for _, id in ipairs(pl.heroes or {}) do
        local h = w.ents[id]
        if h and not h.illusion then list[#list + 1] = { unit = h } end
    end
    for _, rec in ipairs(pl.deadHeroes or {}) do list[#list + 1] = { rec = rec } end
    for i, b in ipairs(H.heroBtns) do
        local it = list[i]
        if not it then b:Hide() else
            b:Show()
            if it.unit then
                local h = it.unit
                b.unit, b.dead = h.id, nil
                setIcon(b.icon, h.def.icon)
                b.icon:SetDesaturated(false)
                b.level:SetText(h.level or 1)
                b.plus:SetShown((h.points or 0) > 0)
                local f = max(0, min(1, h.hp / h.maxhp))
                b.hp:SetWidth(max(1, 40 * f))
                b.hp:SetVertexColor(f > 0.6 and 0.1 or 0.95, f > 0.3 and 0.85 or 0.15, 0.1)
                local m = (h.maxMana or 0) > 0 and (h.mana or 0) / h.maxMana or 0
                b.mp:SetWidth(max(1, 40 * m))
                b.hp:Show() b.mp:Show() b.hpBg:Show()
                local sel = false
                for _, id in ipairs(UI.sel) do if id == h.id then sel = true break end end
                b:SetBackdropBorderColor(sel and 0.3 or 1, sel and 1 or 0.85, sel and 0.3 or 0.3, 1)
            else
                local def = D.Units[it.rec.id]
                b.unit, b.dead = nil, def and def.name or "Hero"
                setIcon(b.icon, def and def.icon)
                b.icon:SetDesaturated(true)
                b.level:SetText(it.rec.level or 1)
                b.plus:Hide()
                b.hp:Hide() b.mp:Hide() b.hpBg:Hide()
                b:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            end
        end
    end
end

local function idleButton(view)
    local b = CreateFrame("Button", nil, view, "BackdropTemplate")
    b:SetSize(46, 46)
    b:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 8, 8)
    b:SetFrameLevel(UI.overLayer:GetFrameLevel() + 25)
    b:SetBackdrop({ bgFile = UI.WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    b:SetBackdropColor(0, 0, 0, 0.7)
    b:SetBackdropBorderColor(1, 0.85, 0.3, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3)
    b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    setIcon(b.icon, "Interface\\Icons\\INV_Pick_02")
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    b:SetScript("OnClick", function() H.nextIdleWorker() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Idle Workers  |cffffd100(F8)|r")
        GameTooltip:AddLine("Selects the next worker that isn't doing anything.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    H.idleBtn = b
end

function H.idleWorkers()
    local w = UI.w
    local out = {}
    if not w then return out end
    for _, u in ipairs(w.list) do
        if u.kind == "unit" and u.owner == UI.me and S.alive(u) and u.def.worker and not u.order and not u.hidden then out[#out + 1] = u end
    end
    return out
end

function H.nextIdleWorker()
    local idle = H.idleWorkers()
    if #idle == 0 then return end
    H.idleIndex = ((H.idleIndex or 0) % #idle) + 1
    local u = idle[H.idleIndex]
    UI.Input.setSelection({ u.id })
    UI.lookAt(u.x, u.y)
end

function H.build(f)
    topBar(f)
    messages(UI.view)
    idleButton(UI.view)
    heroBar(UI.view)
    panel(f)
    buildMenu(f)
    UI.Draw.treeMode = SkirmishDB.trees or "dense"
end

-- ------------------------------------------------------------------ messages

function H.error(text)
    H.err:SetText(text)
    H.errT = 2.5
    H.err:SetAlpha(1)
    if SkirmishDB.sound ~= false then pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST or 846) end
end

function H.message(text, warn)
    H.msg:SetText(text)
    H.msg:SetTextColor(warn and 1 or 1, warn and 0.3 or 0.85, warn and 0.25 or 0.3)
    H.msgT = 3.5
    H.msg:SetAlpha(1)
    if warn and not UI.Sound and SkirmishDB.sound ~= false then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
end

function H.setHover(e, tree)
    if e then
        local own = e.owner == UI.me and "" or (e.owner == 3 and " |cffffd100(creep)|r" or (e.owner == 0 and "" or " |cffff4040(enemy)|r"))
        local extra = ""
        if e.kind == "mine" then extra = "  " .. e.gold .. " gold" end
        H.hover:SetText((e.def.name or "") .. own .. extra)
    elseif tree then
        H.hover:SetText("Tree  " .. (UI.w.trees[tree] or 0) .. " lumber")
    else
        H.hover:SetText("")
    end
end

-- ------------------------------------------------------------------ the command card

local function entryCost(def, mult)
    mult = mult or 1
    return { gold = floor((def.gold or 0) * mult), lumber = floor((def.lumber or 0) * mult), supply = def.supply }
end

local CANCEL = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local function armTarget(cmd, extra)
    UI.mode = { type = "target", cmd = cmd }
    if extra then for k, v in pairs(extra) do UI.mode[k] = v end end
    H.dirty = true
end

local function unitCard(w, units)
    local c = {}
    -- move/stop/hold/attack/patrol go to the whole selection; everything else to the active subgroup (Tab)
    local _, sub = UI.Input.subgroup()
    local all = units
    local ids = #sub > 0 and sub or units
    local prime = w.ents[ids[1]]
    c[1] = { icon = "Interface\\Icons\\Ability_Rogue_Sprint", key = "M", name = "Move", tip = "Move to a spot, ignoring enemies on the way.",
        onClick = function() armTarget("move") end, active = UI.mode and UI.mode.cmd == "move" }
    c[2] = { icon = "Interface\\Icons\\Spell_Holy_SealOfValor", key = "S", name = "Stop", tip = "Stop what they're doing.",
        onClick = function() UI.act("command", UI.me, all, { type = "stop" }) end }
    c[3] = { icon = "Interface\\Icons\\INV_Shield_05", key = "H", name = "Hold Position", tip = "Stay put and only fight what comes into range.",
        onClick = function() UI.act("command", UI.me, all, { type = "hold" }) end }
    c[4] = { icon = "Interface\\Icons\\INV_Sword_04", key = "A", name = "Attack", tip = "Attack a target, or attack-move: walk there and fight anything met on the way.",
        onClick = function() armTarget("amove") end, active = UI.mode and UI.mode.cmd == "amove" }
    if not prime.def.worker then
        c[5] = { icon = "Interface\\Icons\\Ability_Tracking", key = "P", name = "Patrol",
            tip = "Walk back and forth between here and a spot, fighting anything met on the way. Shift-click to add more points.",
            onClick = function() armTarget("patrol") end, active = UI.mode and UI.mode.cmd == "patrol" }
    end
    if prime.def.worker then
        if H.submenu == "build" then
            local c2 = {}
            local list = D.BuildMenu[w.players[UI.me].faction]
            for i, bid in ipairs(list) do
                local def = D.Buildings[bid]
                local ok, need = S.requirementMet(w, UI.me, bid)
                c2[i] = { icon = def.buildIcon or def.icon, key = def.key, name = "Build " .. def.name, tip = def.tip,
                    cost = entryCost(def), disabled = not ok or not S.canAfford(w, UI.me, def),
                    why = not ok and S.needText(need) or nil,
                    onClick = function()
                        local ok2, need2 = S.requirementMet(w, UI.me, bid)
                        if not ok2 then H.error(S.needText(need2)) return end
                        local ok3, why = S.canAfford(w, UI.me, def)
                        if not ok3 then H.error(why) return end
                        UI.mode = { type = "place", bid = bid }
                        H.dirty = true
                    end, active = UI.mode and UI.mode.bid == bid }
            end
            c2[12] = { icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", key = "ESC", name = "Cancel",
                onClick = function() H.submenu = nil UI.mode = nil H.dirty = true end }
            return c2
        end
        c[5] = { icon = "Interface\\Icons\\INV_Pick_02", key = "G", name = "Gather", tip = prime.def.haunt and "Mine gold from a Haunted Gold Mine (5 Acolytes at most). Acolytes can't cut lumber." or "Mine gold from a gold mine or cut lumber from trees.",
            onClick = function() armTarget("gather") end, active = UI.mode and UI.mode.cmd == "gather" }
        local carrying = false
        for _, id in ipairs(ids) do local u = w.ents[id] if u and u.carry then carrying = true end end
        if carrying then
            c[6] = { icon = "Interface\\Icons\\INV_Misc_Bag_10", key = "T", name = "Return Resources", tip = "Carry what they're holding back to the hall.",
                onClick = function() UI.act("command", UI.me, ids, { type = "return" }) end }
        end
        c[9] = { icon = "Interface\\Icons\\Trade_Engineering", key = "B", name = "Build Structure", tip = "Open the list of buildings.",
            onClick = function() H.submenu = "build" H.dirty = true end }
        if not prime.def.lumberOnly then
            c[7] = { icon = "Interface\\Icons\\Trade_BlackSmithing", key = "R", name = "Repair",
                tip = "Repair a damaged building or machine. A full repair costs 35% of its price. You can also right-click it.",
                onClick = function() armTarget("repair") end, active = UI.mode and UI.mode.cmd == "repair" }
        end
    end
    if prime.def.gatherer then
        -- Ghouls: fighters that also cut lumber
        c[6] = { icon = "Interface\\Icons\\INV_Axe_03", key = "G", name = "Harvest Lumber", tip = "Cut lumber from trees (20 a trip) and carry it to a Necropolis or Graveyard.",
            onClick = function() armTarget("gather") end, active = UI.mode and UI.mode.cmd == "gather" }
        local carrying = false
        for _, id in ipairs(ids) do local u = w.ents[id] if u and u.carry then carrying = true end end
        if carrying then
            c[7] = { icon = "Interface\\Icons\\INV_Misc_Bag_10", key = "T", name = "Return Resources", tip = "Carry the lumber back.",
                onClick = function() UI.act("command", UI.me, ids, { type = "return" }) end }
        end
    end
    if prime.def.id == "footman" and S.level(w, UI.me, "defend") > 0 then
        c[9] = { icon = "Interface\\Icons\\INV_Shield_05", key = "D", name = prime.defend and "Stop Defending" or "Defend",
            tip = "Take half damage from piercing attacks (arrows, guns, spears) but move 30% slower.", active = prime.defend,
            onClick = function() UI.act("command", UI.me, ids, { type = "defend", on = not prime.defend }) end }
    end
    if prime.militia then
        c[9] = { icon = "Interface\\Icons\\INV_Pick_02", key = "W", name = "Back to Work",
            tip = string.format("Turn back into a Peasant and return to work (%d s left).", math.ceil(prime.militiaT or 0)),
            onClick = function() UI.act("command", UI.me, ids, { type = "backToWork" }) end }
    end
    if prime.def.spells then
        -- unit spells (WC3: Adept / Master Training unlock the second and third)
        local slot = 9
        for _, abId in ipairs(prime.def.spells) do
            local ab = D.Abilities[abId]
            local lv = S.skillLevel(prime, abId)
            local ok, why = S.canCast(w, prime, abId)
            -- any selected caster of this kind that can cast makes the button live
            if not ok and lv > 0 then
                for _, id in ipairs(ids) do
                    local u = w.ents[id]
                    if u and u.def == prime.def and S.canCast(w, u, abId) then ok, why = true, nil break end
                end
            end
            local cd = prime.abilityCd and prime.abilityCd[abId] or 0
            local full = S.abilityValue(ab, "cd", 1) or 1
            local name = ab.name
            if abId == "etherealForm" and prime.buffs and prime.buffs.ethereal and prime.buffs.ethereal.form then name = "Corporeal Form" end
            local mana = S.abilityValue(ab, "mana", 1) or 0
            if slot <= 12 then
                c[slot] = { icon = ab.icon, key = ab.key, name = name, tip = ab.tip, cost = mana > 0 and { mana = mana } or nil,
                    disabled = not ok, why = lv < 1 and why or nil, cdFrac = cd > 0 and min(1, cd / full) or nil,
                    active = UI.mode and UI.mode.ability == abId,
                    autocast = (ab.autocast and lv > 0) and S.autocastOn(prime, abId) or nil,
                    onRightClick = ab.autocast and function()
                        local on = not S.autocastOn(prime, abId)
                        UI.act("toggleAutocast", UI.me, ids, abId)
                        H.message(ab.name .. " autocast " .. (on and "on" or "off") .. ".")
                    end or nil,
                    onClick = function()
                        local ok2, why2 = S.canCast(w, prime, abId)
                        if not ok2 then
                            for _, id in ipairs(ids) do local u = w.ents[id] if u and S.canCast(w, u, abId) then ok2 = true break end end
                        end
                        if not ok2 then if why2 then H.error(why2) end return end
                        if ab.target == "none" or ab.target == "self" then
                            UI.act("command", UI.me, ids, { type = "cast", ability = abId })
                        else
                            armTarget("cast", { ability = abId, unit = prime.id, ids = ids })
                        end
                    end }
            end
            slot = slot + 1
        end
    end
    if prime.def.hero and not prime.illusion then
        local learning = H.submenu == "learn" and (prime.points or 0) > 0
        if H.submenu == "learn" and not learning then H.submenu = nil end
        if learning then
            -- the Hero Abilities menu: pick a skill to learn or improve
            local c2 = {}
            for i, abId in ipairs(prime.def.abilities) do
                local ab = D.Abilities[abId]
                local cur = S.skillLevel(prime, abId)
                local ok, why = S.canLearn(prime, abId)
                c2[i] = { icon = ab.icon, key = ab.key, name = "Learn " .. ab.name .. " - level " .. min(cur + 1, ab.maxLevel),
                    tip = S.abilityTip(ab, min(cur + 1, ab.maxLevel)), disabled = not ok, why = not ok and why or nil,
                    onClick = function()
                        local ok2, why2 = UI.act("learn", prime, abId)
                        if not ok2 and why2 then H.error(why2) end
                        if (prime.points or 0) <= 0 then H.submenu = nil end
                        H.dirty = true
                    end }
            end
            c2[12] = { icon = CANCEL, key = "ESC", name = "Cancel", onClick = function() H.submenu = nil H.dirty = true end }
            return c2
        end
        if (prime.points or 0) > 0 then
            c[8] = { icon = "Interface\\Icons\\INV_Misc_Book_09", key = "O", name = "Hero Abilities",
                tip = "Learn a new ability or improve one (" .. prime.points .. " point" .. (prime.points > 1 and "s" or "") .. " to spend).",
                onClick = function() H.submenu = "learn" H.dirty = true end, glow = true }
        end
        for i, abId in ipairs(prime.def.abilities) do
            local ab = D.Abilities[abId]
            local lv = S.skillLevel(prime, abId)
            if lv > 0 then
                local passive = ab.target == "passive" or ab.target == "aura"
                local ok = passive or S.canCast(w, prime, abId)
                local orb = ab.autocast and passive
                local cd = prime.abilityCd[abId] or 0
                local full = S.abilityValue(ab, "cd", lv) or 1
                c[8 + i] = { icon = ab.icon, key = not passive and ab.key or nil, name = ab.name .. " (level " .. lv .. ")",
                    tip = S.abilityTip(ab, lv) .. (passive and "\n|cffaaaaaa" .. (ab.target == "aura" and "Aura" or "Passive") .. "|r" or ""),
                    cost = (S.abilityValue(ab, "mana", lv) or 0) > 0 and { mana = S.abilityValue(ab, "mana", lv) } or nil,
                    disabled = not ok, cdFrac = cd > 0 and min(1, cd / full) or nil,
                    active = UI.mode and UI.mode.ability == abId,
                    autocast = orb and S.autocastOn(prime, abId) or nil,
                    onRightClick = orb and function()
                        local on = not S.autocastOn(prime, abId)
                        UI.act("toggleAutocast", UI.me, { prime.id }, abId)
                        H.message(ab.name .. " " .. (on and "on" or "off") .. ".")
                        H.dirty = true
                    end or nil,
                    onClick = orb and function()
                        local on = not S.autocastOn(prime, abId)
                        UI.act("toggleAutocast", UI.me, { prime.id }, abId)
                        H.message(ab.name .. " " .. (on and "on" or "off") .. ".")
                        H.dirty = true
                    end or not passive and function()
                        local ok2, why2 = S.canCast(w, prime, abId)
                        if not ok2 then if why2 then H.error(why2) end return end
                        if ab.target == "none" or ab.target == "self" then
                            UI.act("command", UI.me, { prime.id }, { type = "cast", ability = abId })
                        else
                            armTarget("cast", { ability = abId, unit = prime.id })
                        end
                    end or nil }
            end
        end
    end
    return c
end

-- the Trees' and Ancients' Uproot button
function H.uprootEntry(w, b)
    local ok, why = S.canUproot(w, UI.me, b)
    return { icon = "Interface\\Icons\\Ability_Druid_Ancient", key = "R", name = "Uproot",
        tip = "Pulls up its roots (2.5 seconds): it can walk and fight, with Heavy armour, but can't train, research or sell until it roots again.",
        disabled = not ok, why = not ok and why or nil,
        onClick = function()
            local ok2, why2 = UI.act("uproot", UI.me, b.id)
            if not ok2 and why2 then H.error(why2) end
            H.dirty = true
        end }
end

local function buildingCard(w, b)
    local c = {}
    if not b.built then
        c[12] = { icon = CANCEL, key = "ESC", name = "Cancel Construction",
            tip = "Tear it down and get 75% of the cost back.", onClick = function() UI.act("cancelBuilding", UI.me, b.id) end }
        return c
    end
    if b.upgrading then
        local to = D.Buildings[b.upgrading]
        c[12] = { icon = CANCEL, key = "ESC", name = "Cancel Upgrade",
            tip = "Stop upgrading to " .. to.name .. " and get the cost back.", onClick = function() UI.act("cancelTrain", UI.me, b.id, 1) end }
        return c
    end
    local pl = w.players[UI.me]
    local slot = 0
    for _, uid0 in ipairs(b.def.trains or {}) do
        local uid = S.trainId(w, UI.me, uid0)
        local def = D.Units[uid]
        local ok, need = S.requirementMet(w, UI.me, uid)
        local cost, name, why0 = entryCost(def), "Train " .. def.name, nil
        local disabled = false
        if def.hero then
            local rec = S.deadHero(w, UI.me, uid)
            local allowed, whyH = S.heroAllowed(w, UI.me, uid)
            if rec then
                local g, l, t = S.reviveCost(rec)
                cost = { gold = g, lumber = 0, supply = def.supply }
                name = "Revive " .. def.name .. " (level " .. rec.level .. ")"
            else
                name = "Summon " .. def.name
                if S.heroCount(w, UI.me) == 0 then cost = { gold = 0, lumber = 0, supply = def.supply } end
            end
            if not allowed then disabled, why0 = true, whyH end
        end
        disabled = disabled or not ok or pl.gold < (cost.gold or 0) or pl.lumber < (cost.lumber or 0)
        slot = slot + 1
        c[slot] = { icon = def.icon, key = def.key, name = name, tip = def.tip, cost = cost,
            disabled = disabled,
            why = why0 or (not ok and S.needText(need) or nil),
            onClick = function()
                local ok2, why = UI.act("train", UI.me, b.id, uid0)
                if not ok2 and why then H.error(why) end
                H.dirty = true
            end }
    end
    -- fallen Tavern heroes are revived at the Altar too
    local isAltar = false
    for _, uid in ipairs(b.def.trains or {}) do if D.Units[uid] and D.Units[uid].hero then isAltar = true end end
    if isAltar then
        for _, rec in ipairs(pl.deadHeroes or {}) do
            local def = D.Units[rec.id]
            if def and def.tavern and slot < 11 then
                local g = S.reviveCost(rec)
                slot = slot + 1
                c[slot] = { icon = def.icon, name = "Revive " .. def.name .. " (level " .. rec.level .. ")", tip = def.tip,
                    cost = { gold = g, lumber = 0, supply = def.supply }, disabled = pl.gold < g,
                    onClick = function()
                        local ok2, why = UI.act("train", UI.me, b.id, rec.id)
                        if not ok2 and why then H.error(why) end
                        H.dirty = true
                    end }
            end
        end
    end
    -- research (WC3 shows the next level's name and cost; finished ones disappear)
    for _, rid in ipairs(b.def.researches or {}) do
        local r = D.Research[rid]
        local g, l, t, lv = S.researchCost(w, UI.me, rid)
        if g and slot < 11 then
            local ok, need = S.requirementMet(w, UI.me, rid, lv)
            local busy = pl.researching[rid]
            slot = slot + 1
            c[slot] = { icon = r.icon, key = r.key, name = r.names[lv] .. (r.levels > 1 and (" (level " .. lv .. ")") or ""),
                tip = r.tip, cost = { gold = g, lumber = l }, research = true,
                disabled = busy or not ok or pl.gold < g or pl.lumber < l,
                why = busy and "Being researched." or (not ok and S.needText(need) or nil),
                onClick = function()
                    local ok2, why = UI.act("research", UI.me, b.id, rid)
                    if not ok2 and why then H.error(why) end
                    H.dirty = true
                end }
        end
    end
    -- upgrades into another building (hall tiers, tower types)
    local ups = b.def.upgradesTo or (b.def.upgrade and { b.def.upgrade })
    for _, toId in ipairs(ups or {}) do
        local to = D.Buildings[toId]
        local g, l = S.upgradeCost(b, toId)
        local ok, need = S.requirementMet(w, UI.me, toId)
        slot = slot + 1
        c[slot] = { icon = to.icon, key = b.def.upgrade and "U" or to.key, name = "Upgrade to " .. to.name, tip = to.tip,
            cost = { gold = g, lumber = l }, disabled = not ok or pl.gold < g or pl.lumber < l or #b.queue > 0,
            why = not ok and S.needText(need) or (#b.queue > 0 and "Finish the queue first." or nil),
            onClick = function()
                local ok2, why = UI.act("upgradeBuilding", UI.me, b.id, toId)
                if not ok2 and why then H.error(why) end
                H.dirty = true
            end }
    end
    if b.def.garrisonMax or (b.def.hall and pl.faction == "orcs") then
        c[10] = { icon = "Interface\\Icons\\Ability_Warrior_BattleShout", key = "B", name = "Battle Stations",
            tip = "Nearby Peons run into the Orc Burrows (4 each) and throw spears at attackers.",
            onClick = function()
                local ok2, why = UI.act("battleStations", UI.me, b.id)
                if not ok2 and why then H.error(why) end
                H.dirty = true
            end }
        c[11] = { icon = "Interface\\Icons\\INV_Pick_02", key = "W", name = "Back to Work", tip = "Peons leave the burrows and go back to what they were doing.",
            onClick = function() UI.act("backToWorkAll", UI.me, b.id) H.dirty = true end }
    end
    if b.def.faction == "undead" and S.canUnsummon then
        local ok, why = S.canUnsummon(w, UI.me, b)
        c[10] = { icon = "Interface\\Icons\\Spell_Shadow_SacrificialShield", key = "X", name = "Unsummon Building",
            tip = "An Acolyte unsummons it: it loses 50 hit points a second and, once gone, half of what it cost comes back.",
            disabled = not ok, why = not ok and why or nil,
            onClick = function()
                local ok2, why2 = UI.act("unsummon", UI.me, b.id)
                if not ok2 and why2 then H.error(why2) end
                H.dirty = true
            end }
    end
    if b.def.uproot then c[10] = H.uprootEntry(w, b) end
    if b.def.entangle and b.built then
        -- the Tree of Life wraps the nearest free gold mine in roots
        local m = S.entangleTarget(w, UI.me, b)
        c[11] = { icon = "Interface\\Icons\\Spell_Nature_StrangleVines", key = "E", name = "Entangle Gold Mine",
            tip = "Wraps the nearest free gold mine in roots so Wisps can mine it (up to 5 at a time).",
            disabled = not m, why = not m and "There is no free gold mine near the Tree." or nil,
            onClick = function()
                local ok2, why = UI.act("entangle", UI.me, b.id)
                if not ok2 and why then H.error(why) end
                H.dirty = true
            end }
    end
    if b.def.hall and pl.faction == "alliance" then
        c[11] = { icon = "Interface\\Icons\\INV_Sword_05", key = "C", name = "Call to Arms",
            tip = "Every Peasant near the hall takes up arms as Militia for 45 seconds.",
            onClick = function()
                local ok2, why = UI.act("callToArms", UI.me, b.id)
                if not ok2 and why then H.error(why) end
                H.dirty = true
            end }
    end
    if b.def.trains then
        c[12] = { icon = "Interface\\Icons\\INV_Banner_02", key = "Y", name = "Set Rally Point",
            tip = "Where new units walk to. Workers sent to a gold mine or tree start gathering. You can also right-click.",
            onClick = function() armTarget("rally") end, active = UI.mode and UI.mode.cmd == "rally" }
    end
    return c
end

-- a shop's card: its items (bought for your hero standing next to it) or the units it hires
function H.shopCard(w, b)
    local c = {}
    local pl = w.players[UI.me]
    local hero = S.shopHero(w, UI.me, b)
    local slot = 0
    local KEYS = { "Q", "W", "E", "R", "A", "S", "D", "F", "Z", "X", "C" }
    for _, id in ipairs(b.def.shop or {}) do
        local it = D.Items[id]
        if it and slot < 11 then
            slot = slot + 1
            local st = S.stockOf(w, UI.me, b, id, it)
            local why = not hero and "A hero must be next to the shop." or (st.n < 1 and string.format(st.startAt and "First in stock in %d s." or "Restocks in %d s.", math.ceil(st.startAt and (st.startAt - UI.w.time) or (st.regen - st.t))) or nil)
            c[slot] = { icon = it.icon, key = KEYS[slot], name = "Buy " .. it.name .. "  (" .. st.n .. ")", tip = it.tip, cost = { gold = it.gold, lumber = it.lumber or 0 },
                disabled = not hero or st.n < 1 or pl.gold < it.gold or pl.lumber < (it.lumber or 0), why = why,
                onClick = function()
                    local ok, why2 = UI.act("buyItem", UI.me, b.id, id)
                    if not ok and why2 then H.error(why2) end
                    H.dirty = true
                end }
        end
    end
    local near = S.shopUnit(w, UI.me, b)
    -- the Tavern: neutral heroes, each hired once
    for _, uid in ipairs(b.def.heroes or {}) do
        local def = D.Units[uid]
        if def and slot < 11 then
            slot = slot + 1
            local why = S.tavernWhy(w, UI.me, b, uid)
            local free = S.heroCount(w, UI.me) == 0
            local cost = free and { gold = 0, lumber = 0, supply = def.supply } or { gold = def.gold, lumber = def.lumber, supply = def.supply }
            c[slot] = { icon = def.icon, key = KEYS[slot], name = "Hire " .. def.name, tip = def.tip, cost = cost,
                disabled = why ~= nil or pl.gold < cost.gold or pl.lumber < cost.lumber, why = why,
                onClick = function()
                    local ok, why2 = UI.act("hireHero", UI.me, b.id, uid)
                    if not ok and why2 then H.error(why2) end
                    H.dirty = true
                end }
        end
    end
    for _, uid in ipairs(b.def.hires or {}) do
        local def = D.Units[uid]
        if def and slot < 11 then
            slot = slot + 1
            local st = S.stockOf(w, UI.me, b, uid, def)
            local why = not near and "One of your units must be next to it." or (st.n < 1 and string.format(st.startAt and "First available in %d s." or "Available again in %d s.", math.ceil(st.startAt and (st.startAt - UI.w.time) or (st.regen - st.t))) or nil)
            c[slot] = { icon = def.icon, key = KEYS[slot], name = "Hire " .. def.name .. "  (" .. st.n .. ")", tip = def.tip or (def.name .. ", level " .. (def.level or 1) .. " mercenary."),
                cost = { gold = def.gold, lumber = def.lumber or 0, supply = def.supply }, disabled = not near or st.n < 1 or pl.gold < def.gold or pl.lumber < (def.lumber or 0), why = why,
                onClick = function()
                    local ok, why2 = UI.act("hire", UI.me, b.id, uid)
                    if not ok and why2 then H.error(why2) end
                    H.dirty = true
                end }
        end
    end
    if b.owner == UI.me and b.def.uproot then c[12] = H.uprootEntry(w, b) c[12].key = "V" end
    return c
end

function H.cardEntries()
    local w = UI.w
    if not w or #UI.sel == 0 then return {} end
    local first = w.ents[UI.sel[1]]
    if not first then return {} end
    if first.kind == "building" and first.owner == 0 and (first.def.shop or first.def.hires or first.def.heroes) then return H.shopCard(w, first) end
    if first.owner ~= UI.me then return {} end
    if first.kind == "building" and first.def.shop and first.built then return H.shopCard(w, first) end
    if first.kind == "building" then return buildingCard(w, first) end
    local units = UI.Input.ownUnits()
    if #units == 0 then return {} end
    return unitCard(w, units)
end

local drawCard
function H.pressKey(key)
    if key == "ESCAPE" then return false end
    if H.dirty then drawCard() end
    for _, b in ipairs(H.card) do
        local e = b:IsShown() and b.entry
        if e and e.key == key and e.onClick then
            e.onClick()
            H.dirty = true
            return true
        end
    end
    return false
end

function drawCard()
    local entries = H.cardEntries()
    for i, b in ipairs(H.card) do
        local e = entries[i]
        b.entry = e
        if e then
            setIcon(b.icon, e.icon)
            b.icon:SetDesaturated(e.disabled and true or false)
            b.icon:SetVertexColor(e.disabled and 0.6 or 1, e.disabled and 0.6 or 1, e.disabled and 0.6 or 1)
            b.key:SetText(e.key or "")
            if e.cdFrac then
                b.cd:SetHeight(max(1, 48 * e.cdFrac))
                b.cd:Show()
            else
                b.cd:Hide()
            end
            b.active:SetShown(e.active and true or false)
            if e.autocast ~= nil then
                b.auto:Show()
                if e.autocast then b.auto:SetVertexColor(1, 0.85, 0.2, 1) else b.auto:SetVertexColor(0.5, 0.5, 0.5, 0.6) end
            else
                b.auto:Hide()
            end
            b:Show()
        else
            b:Hide()
        end
    end
end

-- ------------------------------------------------------------------ the selection panel

local function setPortrait(e)
    local p = H.portrait
    local key
    if not e then p:Hide() H.portraitKey = nil return end
    p:Show()
    if e.kind == "unit" and e.def.modelFile and not (SkirmishDB.models and SkirmishDB.models[e.def.id]) then
        key = "f" .. e.def.modelFile
        if H.portraitKey ~= key then
            p:ClearModel()
            pcall(p.SetModel, p, e.def.modelFile)
            pcall(p.SetPortraitZoom, p, 0)
            pcall(p.SetCamDistanceScale, p, 1.3)
            H.portraitKey = key
        end
    elseif e.kind == "unit" then
        local disp = SkirmishDB.models and SkirmishDB.models[e.def.id] or e.def.display[((e.variant or 1) - 1) % #e.def.display + 1]
        key = "d" .. disp
        if H.portraitKey ~= key then
            p:ClearModel()
            pcall(p.SetDisplayInfo, p, disp)
            pcall(p.SetPortraitZoom, p, 0.85)
            pcall(p.SetCamDistanceScale, p, 1)
            H.portraitKey = key
        end
    else
        local m1 = e.def.models[1]
        local file = m1.file or m1.display
        key = "f" .. file
        if H.portraitKey ~= key then
            p:ClearModel()
            if m1.display then pcall(p.SetDisplayInfo, p, m1.display) else pcall(p.SetModel, p, file) end
            pcall(p.SetPortraitZoom, p, 0)
            pcall(p.SetCamDistanceScale, p, 1.6)
            pcall(p.SetRotation, p, 0.6)
            H.portraitKey = key
        end
    end
end

local function iconAt(i, x, y)
    local b = H.icons[i]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", H.panel, "TOPLEFT", x, y)
    b:Show()
    return b
end

-- use, sell or drop the item in a slot of the selected hero
function H.useSlot(slot, alt)
    local w = UI.w
    local h = w and UI.sel[1] and w.ents[UI.sel[1]]
    if not h or h.owner ~= UI.me or not h.def.hero then return end
    local s = h.inv and h.inv[slot]
    if not s then return end
    local it = D.Items[s.id]
    if alt then
        UI.act("sellOrDrop", UI.me, h.id, slot)
    elseif it.target then
        UI.mode = { type = "target", cmd = "item", slot = slot, unit = h.id }
    else
        local ok, why = UI.act("useItem", h, slot)
        if not ok and why then H.error(why) end
    end
    H.dirty = true
end

local function drawInventory(w, e)
    local show = e and e.kind == "unit" and e.def.hero and e.owner == UI.me and not e.illusion
    for i, b in ipairs(H.inv) do
        if not show then b:Hide()
        else
            b:Show()
            local s = e.inv and e.inv[i]
            local it = s and D.Items[s.id]
            if it then
                setIcon(b.icon, it.icon)
                b.icon:Show()
                b.count:SetText((s.charges and it.uses and it.uses > 1) and s.charges or "")
                if (s.cd or 0) > 0 and it.cd and it.cd > 0 then b.cd:SetHeight(max(1, 34 * min(1, s.cd / it.cd))) b.cd:Show() else b.cd:Hide() end
            else
                b.icon:Hide()
                b.count:SetText("")
                b.cd:Hide()
            end
        end
    end
end

local function drawPanel()
    local w = UI.w
    drawInventory(w, w and #UI.sel == 1 and w.ents[UI.sel[1]] or nil)
    for _, b in ipairs(H.icons) do b:Hide() b.onClick = nil b.tip = nil b.tip2 = nil b:SetBackdropColor(0, 0, 0, 0.8) end
    for _, l in ipairs(H.lines) do l:SetText("") end
    H.name:SetText("")
    H.sub:SetText("")
    H.hpText:SetText("")
    H.manaText:SetText("")
    if not w or #UI.sel == 0 then setPortrait(nil) return end
    local e = w.ents[UI.sel[1]]
    if not e then setPortrait(nil) return end
    setPortrait(e)

    if #UI.sel > 1 then
        -- several units: an icon each
        H.name:SetText(#UI.sel .. " units")
        for i, id in ipairs(UI.sel) do
            local u = w.ents[id]
            if u and i <= 24 then
                local col, row = (i - 1) % 12, floor((i - 1) / 12)
                local b = iconAt(i, 148 + col * 48, -52 - row * 50)
                setIcon(b.icon, u.def.icon)
                local active = UI.Input.subgroup() == u.def.id and u.owner == UI.me
                b:SetBackdropColor(active and 0.9 or 0, active and 0.75 or 0, active and 0.2 or 0, active and 0.95 or 0.8)
                local f = u.hp / u.maxhp
                b.bar:SetWidth(max(1, 36 * f))
                b.bar:SetVertexColor(f > 0.6 and 0.1 or 0.95, f > 0.3 and 0.85 or 0.15, 0.1)
                b.tip = u.def.name .. (u.level and (" (level " .. u.level .. ")") or "")
                b.tip2 = floor(u.hp) .. " / " .. u.maxhp .. " health"
                b.onClick = function(btn)
                    if IsShiftKeyDown() or btn == "RightButton" then
                        local ids = {}
                        for _, x in ipairs(UI.sel) do if x ~= id then ids[#ids + 1] = x end end
                        UI.Input.setSelection(ids)
                    else
                        UI.Input.setSelection({ id })
                    end
                end
            end
        end
        return
    end

    local def = e.def
    H.name:SetText(def.name or "")
    local whose = e.owner == UI.me and "" or (e.owner == 3 and "Neutral creep" or (e.owner == 0 and "" or "Enemy"))
    if e.kind ~= "mine" then H.hpText:SetText(floor(e.hp) .. " / " .. e.maxhp) end
    if e.kind == "unit" then
        local L = H.lines
        if def.hero then
            local need = D.HERO_XP[(e.level or 1) + 1]
            H.sub:SetText("Level " .. e.level .. (e.illusion and " illusion" or " hero") .. (need and ("   " .. e.xp .. " / " .. need .. " xp") or "   max level") ..
                (whose ~= "" and ("   " .. whose) or ""))
            H.manaText:SetText(floor(e.mana) .. " / " .. e.maxMana)
        else
            H.sub:SetText(whose)
            if e.maxMana and e.maxMana > 0 then H.manaText:SetText(floor(e.mana or 0) .. " / " .. e.maxMana) end
        end
        local lv = e.level and (e.level - 1) * (def.dmgPerLevel or 0) or 0
        local bn = S.bonus(w, e)
        if def.hero then
            local str, agi, int, main = S.heroStats(e)
            local extra = S.hasBuff(e, "avatar") and 20 or 0
            L[1]:SetText(string.format("Damage: %d - %d   Hero", main + 2 + extra, main + 2 * def.sides + extra))
            local function att(n, v) return (def.primary == n and "|cffffd100" or "") .. v .. (def.primary == n and "|r" or "") end
            L[4]:SetText(att("str", "Strength " .. str) .. "   " .. att("agi", "Agility " .. agi) .. "   " .. att("int", "Intelligence " .. int))
        elseif def.dmin then
            local plus = (bn.dice or 0)
            local lo = def.dmin + lv + plus + (bn.dmg or 0)
            local hi = def.dmax + lv + plus * (def.sides or 1) + (bn.dmg or 0)
            L[1]:SetText(string.format("Damage: %d - %d   %s%s", lo, hi, D.ATTACK_NAMES[def.atype] or def.atype,
                plus > 0 and ("   |cff40ff40(+" .. plus .. " upgrades)|r") or ""))
        end
        local armor, dtype = S.armorOf(w, e)
        L[2]:SetText(string.format("Armour: %.0f   %s%s", armor, D.ARMOR_NAMES[dtype] or dtype, (bn.armor or 0) > 0 and ("   |cff40ff40(+" .. bn.armor .. ")|r") or ""))
        local rng = def.dmin and S.rangeOf(w, e) or 0
        L[3]:SetText(string.format("Range: %s   Speed: %.1f%s", rng > 1 and string.format("%.1f", rng) or "melee", def.speed,
            def.air and "   Flying" or ""))
        local hits = {}
        if def.hitsGround then hits[#hits + 1] = "ground" end
        if def.hitsAir then hits[#hits + 1] = "air" end
        if def.weapon2 and bn.flags and bn.flags.weapon2 then
            if def.weapon2.hitsAir then hits[#hits + 1] = "air" end
            if def.weapon2.hitsGround then hits[#hits + 1] = "ground" end
        end
        if def.dmin and #hits > 0 then L[6]:SetText("Attacks " .. table.concat(hits, " and ") .. (def.hitsBuildings and not def.hitsGround and " (buildings only)" or "")) end
        if e.militia then L[5]:SetText(string.format("|cffffd100Militia for %d more seconds|r", math.ceil(e.militiaT or 0))) end
        if e.defend then L[5]:SetText("|cff8080ffDefending|r") end
        if e.poisonT and e.poisonT > 0 then L[5]:SetText("|cff40ff40Poisoned|r") end
        if e.carry then L[4]:SetText("Carrying " .. e.carry.amt .. " " .. e.carry.res) end
        if def.cargoMax then L[4]:SetText(string.format("Corpses: %d / %d", e.cargo or 0, def.cargoMax)) end
        if def.blightRegen and not def.hero and e.hp < e.maxhp then L[6]:SetText(S.onBlight(w, e) and "|cffcc88ffHealing on blight|r" or "|cffaaaaaaHeals only on blight|r") end
        if e.stun > 0 then L[5]:SetText("|cffffff40Stunned|r") elseif e.slow > 0 then L[5]:SetText("|cff8080ffSlowed|r") end
        local status = {}
        for id, label in pairs({ invuln = "|cffffff80Divine Shield|r", avatar = "|cffffd100Avatar|r", ethereal = "|cff80ff80Ethereal|r", hex = "|cff40ff40Hexed|r",
                                 innerFire = "|cffffff80Inner Fire|r", bloodlust = "|cffff6040Bloodlust|r", slowSpell = "|cff8080ffSlowed|r", invis = "|cffaaaaffInvisible|r",
                                 poly = "|cffffffffPolymorphed|r", lightningShield = "|cff80c0ffLightning Shield|r", link = "|cffcc88ffSpirit Link|r",
                                 ensnare = "|cffaaff66Ensnared|r", purged = "|cff66ffccPurged|r", berserk = "|cffff4040Berserk|r",
                                 windWalk = "|cffaaaaffWind Walk|r", bladestorm = "|cffff8040Bladestorm|r", voodoo = "|cffcc66ffBig Bad Voodoo|r",
                                 curse = "|cffcc66ffCursed|r", frenzy = "|cffff6040Unholy Frenzy|r", cripple = "|cff8080ffCrippled|r", ams = "|cff80ff80Anti-magic Shell|r",
                                 frostArmor = "|cff80c0ffFrost Armor|r", sleep = "|cffaaaaffAsleep|r", plague = "|cff80ff40Diseased|r", burrowed = "|cffaaaaaaBurrowed|r",
                                 locusts = "|cffaaff66Locust Swarm|r" }) do
            if S.hasBuff(e, id) then status[#status + 1] = label end
        end
        if e.life then status[#status + 1] = string.format("|cffaaaaaa%d s left|r", math.ceil(e.life)) end
        if e.reviveT then status[#status + 1] = "|cffffd100Reincarnating|r" end
        if #status > 0 then L[5]:SetText(table.concat(status, "  ")) end
    elseif e.kind == "mine" then
        H.sub:SetText(e.gold .. " gold left")
        H.lines[1]:SetText("Workers go inside one at a time.")
        H.lines[2]:SetText("Five workers keep a mine busy.")
        if e.haunted then H.lines[1]:SetText("Haunted: only its owner's Acolytes can mine it.") end
    else
        H.sub:SetText(whose ~= "" and whose or (e.built and "" or "Under construction"))
        local L = H.lines
        if not e.built then
            L[1]:SetText(string.format(e.selfBuild and "Summoning: %d%%" or "Building: %d%%", floor(e.progress * 100)))
        else
            if def.onMine and e.mine and w.ents[e.mine] then L[5]:SetText(w.ents[e.mine].gold .. " gold left. Up to 5 workers mine it.") end
            if def.moonWell then L[5]:SetText(string.format("Mana: %d / %d", floor(e.wellMana or 0), e.wellMax or def.wellMana or 0)) end
            if e.frozenT and e.frozenT > w.time then L[6]:SetText("|cff80c0ffFrozen by Freezing Breath|r") end
            if def.supplyGiven > 0 then L[1]:SetText("Provides " .. def.supplyGiven .. " food") end
            if def.garrisonMax then L[5]:SetText(string.format("Peons inside: %d / %d", #(e.garrison or {}), def.garrisonMax)) end
            if e.liquid and e.liquid > 0 then L[6]:SetText("|cffff6020Burning (Liquid Fire): can't be repaired|r") end
            if def.attack then L[2]:SetText(string.format("Damage: %d - %d   Range: %.1f   %s%s", def.attack.dmin, def.attack.dmax, def.attack.range,
                D.ATTACK_NAMES[def.attack.atype] or "", def.attack.hitsAir and "   (ground and air)" or "")) end
            if def.dropoff == true then L[3]:SetText("Gold and lumber are returned here")
            elseif def.dropoff == "lumber" then L[3]:SetText("Lumber is returned here") end
            local armor, dtype = S.armorOf(w, e)
            L[4]:SetText(string.format("Armour: %d   %s", armor, D.ARMOR_NAMES[dtype] or dtype))
        end
        -- training queue
        if e.owner == UI.me and e.built and e.queue[1] then
            local kind1 = S.queueItem(e.queue[1])
            for i = 2, #L do L[i]:SetText("") end
            L[1]:SetText(kind1 == "upgrade" and "Upgrading:" or (kind1 == "research" and "Researching:" or "Training:"))
            for i, q in ipairs(e.queue) do
                local kind, u, qid = S.queueItem(q)
                local info = e.qinfo and e.qinfo[i] or {}
                local b = iconAt(i, 148 + (i - 1) * 48, -78)
                setIcon(b.icon, u.icon)
                local f = i == 1 and min(1, e.trainT / (info.time or u.time or 30)) or 0
                b.bar:SetWidth(max(1, 36 * f))
                b.bar:SetVertexColor(0.3, 0.6, 1)
                b.tip = kind == "research" and (u.names[info.level or 1] or u.names[1]) or (kind == "upgrade" and ("Upgrade to " .. u.name) or u.name)
                b.tip2 = "Click to cancel"
                local idx = i
                b.onClick = function() UI.act("cancelTrain", UI.me, e.id, idx) H.dirty = true end
            end
        end
    end
end

-- ------------------------------------------------------------------ per frame

function H.update(elapsed)
    local w = UI.w
    H.msgT = H.msgT - elapsed
    if H.msgT < 1 then H.msg:SetAlpha(max(0, H.msgT)) end
    H.errT = H.errT - elapsed
    if H.errT < 1 then H.err:SetAlpha(max(0, H.errT)) end
    if not w then return end
    -- a multiplayer game can't be paused or sped up; it shows when it is waiting for the other player
    local sess = UI.Net and UI.Net.session
    if w.net then
        local wait = sess and sess.waiting > 0.6
        H.paused:SetText(wait and string.format("Waiting for %s... (%d s)", (UI.Net.peer or "the other player"):match("^[^%-]+") or "", sess.waiting) or "PAUSED")
        H.paused:SetShown(wait and true or false)
        H.pauseBtn:Hide() H.speedBtn:Hide()
    else
        H.paused:SetText("PAUSED")
        H.paused:SetShown(UI.paused and true or false)
        H.pauseBtn:Show() H.speedBtn:Show()
    end
    H.pauseBtn:SetText(UI.paused and "Resume" or "Pause")

    H.topT = (H.topT or 0) - elapsed
    if H.topT <= 0 then
        H.topT = 0.2
        local pl = w.players[UI.me]
        H.goldText:SetText(pl.gold)
        H.lumberText:SetText(pl.lumber)
        local full = pl.used >= pl.cap
        local up = S.upkeep(w, UI.me)
        local upk = up >= 1 and "|cff40ff40No upkeep|r" or (up >= 0.7 and "|cffffd100Low upkeep|r" or "|cffff4040High upkeep|r")
        H.supplyText:SetText((full and "|cffff4040" or "") .. pl.used .. " / " .. pl.cap .. (full and "|r" or "") .. "   " .. upk)
        local tod = S.timeOfDay(w)
        H.clockText:SetText(string.format("%s %d:%02d   |cffaaaaaa%d:%02d|r", w.night and "|cff8899ffNight|r" or "|cffffd100Day|r",
            floor(tod), floor((tod % 1) * 60), floor(w.time / 60), floor(w.time % 60)))
        H.updateHeroBar(w)
        local idle = #H.idleWorkers()
        H.idleBtn:SetShown(idle > 0)
        H.idleBtn.count:SetText(idle)
        -- testing: faster or instant building, training, research and upgrades (your side only;
        -- never in a multiplayer game, where both machines must play the same game)
        if not w.net then w.players[UI.me].buildSpeed = SkirmishDB.buildSpeed end
        -- testing: unlimited gold and lumber
        if SkirmishDB.cheat and not w.net then
            local me = w.players[UI.me]
            if me.gold < 50000 then me.gold = 99999 end
            if me.lumber < 50000 then me.lumber = 99999 end
        end
        H.fpsText:SetText(string.format("%d fps  %d models", floor(GetFramerate() + 0.5), UI.Figures.liveCount()))
    end
    H.panelT = (H.panelT or 0) - elapsed
    if H.dirty or H.panelT <= 0 then
        H.dirty = false
        H.panelT = 0.25
        drawPanel()
        drawCard()
    end
end
