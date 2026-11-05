-- Skirmish UI: the building studio. WoW Classic's real buildings are WMOs, which a UI model scene
-- can't show, so every building here is put together from M2 props (towers, sheds, tents, roosts,
-- shrines...). The studio lets you swap the models of any building, resize and move its parts,
-- and add or remove parts, live in the running game. Choices are saved per building.
-- /skirmish studio   (or the "Buildings" button in the menu)

local ADDON, ns = ...
local E = ns.Engine
local D = E.Data
local UI = ns.UI
local St = {}
UI.Studio = St

local floor, max, min = math.floor, math.max, math.min

-- every building-sized M2 we know of in the Classic client, by look
St.CANDIDATES = {
    { 190505, "Westfall church" }, { 189601, "Elwynn blacksmith" }, { 190517, "Westfall shed" }, { 189611, "Elwynn distillery" },
    { 189445, "Duskwood barn" }, { 190655, "Westfall stable" }, { 190519, "Westfall windmill" }, { 204144, "Tirisfal windmill" },
    { 190508, "Grain silo" }, { 189629, "Human guard tower" }, { 189632, "Human watch tower" }, { 189288, "Ruined guard tower" },
    { 203634, "Alterac water tower" }, { 190515, "Westfall lighthouse" }, { 190511, "Red lighthouse" }, { 197108, "Large army tent" },
    { 197109, "Medium army tent" }, { 198621, "Stormwind vendor tent" }, { 189375, "Gypsy wagon" }, { 198288, "Stormwind wagon" },
    { 198261, "Gryphon roost" }, { 200143, "Ruined gryphon roost" }, { 198768, "Hippogryph roost" }, { 191109, "Paladin shrine" },
    { 198570, "Uther statue" }, { 198564, "Turalyon statue" }, { 198561, "Khadgar statue" }, { 198563, "Lion statue" },
    { 197044, "Ironforge mage portal" }, { 197831, "Altar" }, { 197832, "Altar (2)" }, { 197835, "Great altar" },
    { 203226, "Dwarven steam tank" }, { 203176, "The Great Anvil" }, { 203012, "Dark Iron forge" }, { 198459, "Shack" },
    { 190617, "Outhouse" }, { 198177, "Doghouse" }, { 200617, "Giant windmill" }, { 200619, "Tall windmill" },
    { 189641, "Stormwind gate" }, { 190165, "Oil rig" }, { 190160, "Crashed zeppelin" }, { 203124, "Ironforge rampart" },
    { 203129, "Ironforge tower" }, { 203133, "Ironforge wall tower" },
    { 199384, "Durotar orc tent" }, { 199385, "Durotar orc tent (2)" }, { 199387, "Orc tent" }, { 199389, "Orc tent (2)" },
    { 189200, "Orc camp tent" }, { 190175, "Troll watch tower" }, { 199454, "Wind rider roost" }, { 199451, "Wind rider nest" },
    { 199041, "Altar of Storms" }, { 200577, "Tauren totem" }, { 200578, "Tauren totem (2)" }, { 200581, "Tauren totem (5)" },
    { 200566, "Tauren windmill" }, { 189386, "Ogre mound" }, { 189186, "Orc anvil stone" }, { 190358, "Troll shrine" },
    { 190408, "Troll tree hut" }, { 190430, "Troll water hut" }, { 201389, "Raptor hut" }, { 202016, "Furbolg tent" },
    { 197120, "Centaur tent" }, { 200353, "Satyr tent" }, { 200332, "Quilboar hut" }, { 189359, "Gnoll tent" },
    { 199195, "Kodo wagon" }, { 200644, "Bat roost" }, { 190690, "Troll bat totem" }, { 199134, "Orc bonfire" },
    { 197791, "Goblin tent" }, { 197793, "Goblin tent (3)" }, { 197767, "Goblin machinery" }, { 197789, "Shredder suit" },
    { 197779, "Goblin rocket cart" }, { 197408, "Gyrocopter" },
    { 197996, "Lion banner" }, { 197995, "Gryphon banner" }, { 197977, "Magic banner" }, { 199070, "Warsong banner" },
    { 199058, "Clan banner" }, { 198294, "Hay pile" }, { 198339, "Lumber pile" }, { 189642, "Anvil" }, { 198278, "Mortar" },
    { 199205, "Meat rack" }, { 199208, "Orc bellows" }, { 189193, "Foundry pit" }, { 189204, "Tool rack" },
    { 203656, "Arathi farmhouse" }, { 203657, "Arathi farmhouse (2)" }, { 198331, "Log machine" }, { 198332, "Log machine (2)" },
    { 198333, "Log machine (3)" }, { 197679, "Gnome machine" }, { 197680, "Gnome machine (2)" }, { 197701, "Gnome hut machinery" },
    { 200409, "Tauren kiln" }, { 201390, "Raptor hut (2)" }, { 190431, "Troll water hut (2)" }, { 190409, "Troll tree hut (2)" },
    { 200332, "Quilboar hut (2)" }, { 197383, "Excavation pavilion" }, { 197212, "Dark Iron saw" }, { 189229, "Smelting cauldron" },
    { 190107, "Wooden spikes" }, { 200579, "Tauren totem (3)" }, { 199414, "Orc wagon" }, { 202687, "Tanaris water tower" },
}
local NAME = {}
for i, c in ipairs(St.CANDIDATES) do NAME[c[1]] = c[2] c.index = i end

local DEFAULTS = {}
local function copyModels(list)
    local out = {}
    for i, m in ipairs(list) do
        local c = {}
        for k, v in pairs(m) do c[k] = v end
        out[i] = c
    end
    return out
end

-- apply saved choices (called at login and after every change)
function St.apply()
    SkirmishDB.buildingModels = SkirmishDB.buildingModels or {}
    for id, b in pairs(D.Buildings) do
        if b.models and not DEFAULTS[id] then DEFAULTS[id] = copyModels(b.models) end
        local saved = SkirmishDB.buildingModels[id]
        b.models = saved and copyModels(saved) or copyModels(DEFAULTS[id] or b.models or {})
    end
end

local function save(id)
    SkirmishDB.buildingModels[id] = copyModels(D.Buildings[id].models)
end

-- ------------------------------------------------------------------ the panel

local state = { id = nil, part = 1 }

local function buildingIds()
    local fac = UI.w and UI.w.players[UI.me].faction
    local out = {}
    for id, b in pairs(D.Buildings) do if b.models and (not fac or b.faction == fac) then out[#out + 1] = id end end
    table.sort(out, function(a, b) return D.Buildings[a].name < D.Buildings[b].name end)
    return out
end

local function current()
    -- follow the selected building when there is one
    local w = UI.w
    local sel = w and UI.sel[1] and w.ents[UI.sel[1]]
    if sel and sel.kind == "building" and sel.def.models and sel.def.id ~= state.followed then
        state.id, state.part, state.followed = sel.def.id, 1, sel.def.id
    end
    if not state.id then state.id = buildingIds()[1] end
    return state.id and D.Buildings[state.id]
end

local function refresh()
    local f = St.frame
    if not f or not f:IsShown() then return end
    local b = current()
    if not b then return end
    local m = b.models[state.part] or b.models[1]
    if not b.models[state.part] then state.part = 1 end
    f.title:SetText(b.name .. "  (" .. b.size .. "x" .. b.size .. ")")
    f.part:SetText(string.format("Part %d of %d", state.part, #b.models))
    if m then
        f.model:SetText((NAME[m.file or 0] or ("model " .. tostring(m.file or m.display))) .. "  |cff888888" .. tostring(m.file or m.display) .. "|r")
        f.size:SetText(string.format("Size %.1f   Offset %.1f, %.1f   Turn %d", m.size, m.dx or 0, m.dy or 0, floor(((m.yaw or (math.pi * 0.5)) / math.pi * 180) + 0.5) % 360))
    end
    f.saved:SetText(SkirmishDB.buildingModels[state.id] and "|cff40ff40Customised (saved)|r" or "|cffaaaaaaDefault models|r")
end
St.refresh = refresh

local function change(fn)
    local b = current()
    if not b then return end
    local m = b.models[state.part]
    if m then fn(b, m) end
    save(state.id)
    refresh()
end

local function cycleModel(dir)
    change(function(b, m)
        local i = NAME[m.file] and 1 or 0
        for k, c in ipairs(St.CANDIDATES) do if c[1] == m.file then i = k break end end
        i = ((i - 1 + dir) % #St.CANDIDATES) + 1
        m.file = St.CANDIDATES[i][1]
    end)
end

function St.build()
    local f = CreateFrame("Frame", "SkirmishStudio", UI.frame, "BackdropTemplate")
    f:SetSize(330, 268)
    f:SetPoint("TOPRIGHT", UI.view, "TOPRIGHT", -8, -8)
    f:SetFrameLevel(UI.overLayer:GetFrameLevel() + 40)
    UI.backdrop(f, true)
    f:EnableMouse(true)
    f:Hide()
    St.frame = f
    local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", 12, -10)
    head:SetText("Building studio")
    local close = UI.button(f, "x", 22, 20)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() f:Hide() end)
    local function text(y, font, width)
        local s = f:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
        s:SetPoint("TOPLEFT", 12, y)
        s:SetWidth(width or 306)
        s:SetWordWrap(false)
        s:SetJustifyH("LEFT")
        return s
    end
    local function btn(label, x, y, w, fn)
        local b = UI.button(f, label, w or 30, 20)
        b:SetPoint("TOPLEFT", x, y)
        b:SetScript("OnClick", fn)
        return b
    end
    f.title = text(-30, "GameFontNormalLarge", 200)
    btn("<", 220, -28, 26, function()
        local ids = buildingIds()
        for i, id in ipairs(ids) do if id == state.id then state.id = ids[(i - 2) % #ids + 1] break end end
        state.part, state.followed = 1, nil
        refresh()
    end)
    btn(">", 250, -28, 26, function()
        local ids = buildingIds()
        for i, id in ipairs(ids) do if id == state.id then state.id = ids[i % #ids + 1] break end end
        state.part, state.followed = 1, nil
        refresh()
    end)
    f.part = text(-58, nil, 200)
    btn("<", 220, -54, 26, function() local b = current() state.part = (state.part - 2) % #b.models + 1 refresh() end)
    btn(">", 250, -54, 26, function() local b = current() state.part = state.part % #b.models + 1 refresh() end)
    f.model = text(-84)
    btn("< Model", 12, -102, 80, function() cycleModel(-1) end)
    btn("Model >", 96, -102, 80, function() cycleModel(1) end)
    btn("<<", 180, -102, 34, function() cycleModel(-10) end)
    btn(">>", 218, -102, 34, function() cycleModel(10) end)
    f.size = text(-130, "GameFontHighlightSmall")
    btn("Smaller", 12, -146, 70, function() change(function(b, m) m.size = max(0.3, m.size - 0.2) end) end)
    btn("Bigger", 86, -146, 70, function() change(function(b, m) m.size = m.size + 0.2 end) end)
    btn("Turn", 160, -146, 60, function() change(function(b, m) m.yaw = ((m.yaw or (math.pi * 0.5)) + math.pi / 4) % (2 * math.pi) end) end)
    btn("Left", 12, -170, 50, function() change(function(b, m) m.dx = (m.dx or 0) - 0.2 end) end)
    btn("Right", 66, -170, 50, function() change(function(b, m) m.dx = (m.dx or 0) + 0.2 end) end)
    btn("Up", 120, -170, 46, function() change(function(b, m) m.dy = (m.dy or 0) - 0.2 end) end)
    btn("Down", 170, -170, 50, function() change(function(b, m) m.dy = (m.dy or 0) + 0.2 end) end)
    btn("Add part", 12, -198, 80, function()
        local b = current()
        b.models[#b.models + 1] = { file = 197996, size = 1.5, fill = 0.9, guess = 3, dx = 0, dy = 0 }
        state.part = #b.models
        save(state.id) refresh()
    end)
    btn("Remove part", 96, -198, 96, function()
        local b = current()
        if #b.models > 1 then table.remove(b.models, state.part) state.part = 1 save(state.id) refresh() end
    end)
    btn("Reset", 196, -198, 60, function()
        SkirmishDB.buildingModels[state.id] = nil
        St.apply()
        state.part = 1
        refresh()
    end)
    f.saved = text(-226, "GameFontHighlightSmall", 210)
    local exp = btn("Copy all", 230, -222, 90, function() St.export() end)
    local help = text(-246, "GameFontDisableSmall")
    help:SetText("Select one of your buildings to edit it. Tip: turn on Instant build in the menu.")
    f:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) - el
        if self.t <= 0 then self.t = 0.3 refresh() end
    end)

    -- export box: every customised building as Lua, to paste back to Claude
    local ex = CreateFrame("Frame", nil, UI.frame, "BackdropTemplate")
    ex:SetSize(520, 300)
    ex:SetPoint("CENTER", UI.view, "CENTER")
    ex:SetFrameLevel(f:GetFrameLevel() + 10)
    UI.backdrop(ex, true)
    ex:Hide()
    local sf = CreateFrame("ScrollFrame", nil, ex, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -30)
    sf:SetPoint("BOTTOMRIGHT", -32, 12)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(460)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() ex:Hide() end)
    sf:SetScrollChild(eb)
    local t = ex:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", 12, -10)
    t:SetText("Ctrl+A, Ctrl+C, then paste it to Claude")
    local c = UI.button(ex, "Close", 70, 20)
    c:SetPoint("TOPRIGHT", -8, -6)
    c:SetScript("OnClick", function() ex:Hide() end)
    St.exportFrame, St.exportBox = ex, eb
end

function St.export()
    local lines = {}
    local ids = {}
    for id in pairs(SkirmishDB.buildingModels or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local parts = {}
        for _, m in ipairs(SkirmishDB.buildingModels[id]) do
            parts[#parts + 1] = string.format("{%d,%.1f,%.1f,%.1f,%.2f}", m.file or m.display or 0, m.size, m.dx or 0, m.dy or 0, m.yaw or (math.pi * 0.5))
        end
        lines[#lines + 1] = id .. "=" .. table.concat(parts, ",")
    end
    if #lines == 0 then lines[1] = "(nothing customised yet)" end
    St.exportBox:SetText(table.concat(lines, "\n"))
    St.exportFrame:Show()
    St.exportBox:SetFocus()
    St.exportBox:HighlightText()
end

function St.toggle()
    if not St.frame then return end
    if St.frame:IsShown() then St.frame:Hide() else St.frame:Show() refresh() end
end

-- ------------------------------------------------------------------ the model gallery
-- /skirmish gallery [page]: every building-sized prop we know of in the Classic client, 24 to a page,
-- each drawn the way buildings are on the map, with its file number underneath. For picking models.

St.GALLERY = {
    { 189200, "orctent" }, { 189280, "warlockshrine" }, { 189288, "abandonedhumanguardtower" }, { 189359, "gnolltent02" },
    { 189361, "gnolltent03" }, { 189375, "gypsywagon" }, { 189386, "ogremound" }, { 189445, "barnduskwood" },
    { 189601, "blacksmith" }, { 189611, "distillery" }, { 189629, "humanguardtower" }, { 189632, "humanwatchtower" },
    { 190060, "karazahn_rrh_house" }, { 190175, "trollwatchtower" }, { 190358, "trollshrine" }, { 190363, "serpentaltar" },
    { 190408, "losttreehuts01" }, { 190409, "losttreehuts02" }, { 190410, "losttreehuts03" }, { 190430, "waterhut01" },
    { 190431, "waterhut02" }, { 190505, "westfallchurch" }, { 190508, "westfallgrainsilo01" }, { 190517, "westfallshed" },
    { 190519, "westfallwindmill" }, { 190657, "westfallwagon01" }, { 191019, "carni_wagon01" }, { 191022, "carnietent_small01" },
    { 191026, "coketent" }, { 191084, "altartidalmastery01" }, { 191109, "paladinshrine" }, { 197108, "humantentlarge" },
    { 197109, "humantentmedium" }, { 197120, "centaurtent01" }, { 197383, "excavationtentpavillion" }, { 197388, "excavationtent01" },
    { 197394, "excavationwaterwagon" }, { 197635, "gnomemachine" }, { 197678, "gnomemachine01" }, { 197679, "gnomemachine02" },
    { 197701, "gnomehutmachinery" }, { 197766, "goblinhutbottles" }, { 197767, "goblinmachinery" }, { 197791, "goblintent01" },
    { 197792, "goblintent02" }, { 197793, "goblintent03" }, { 198261, "gryphonroost01" }, { 198288, "stormwindgypsywagon01" },
    { 198331, "logmachine01" }, { 198332, "logmachine02" }, { 198333, "logmachine03" }, { 198346, "cavekoboldminemachine" },
    { 198380, "generaloutpost01" }, { 198381, "generaloutpost02" }, { 198382, "generaloutpost03" }, { 198383, "generaloutpost04" },
    { 198621, "stormwindvendortent01" }, { 198717, "murlocaltar_01" }, { 198768, "hippogryphroost" }, { 198969, "nightelfwagon" },
    { 199144, "burntoutpost01" }, { 199145, "burntoutpost02" }, { 199146, "burntoutpost03" }, { 199195, "kodowagon" },
    { 199226, "wailingcavernsraptornest01" }, { 199384, "durotarorctent01" }, { 199385, "durotarorctent02" }, { 199387, "orctent01" },
    { 199389, "orctent02" }, { 199414, "orcwagon01" }, { 199451, "wyvernnest01" }, { 199454, "wyvernroost01" },
    { 199893, "beerfest_foodtent" }, { 199894, "beerfest_opentent" }, { 199896, "beerfest_wagon" }, { 200332, "quillboar_hut01" },
    { 200353, "satyrtent01" }, { 200409, "taurenkiln01" }, { 200566, "taurenwindmilla" }, { 200573, "grimtotem01" },
    { 200577, "taurentotem01" }, { 200592, "warharnesstotem01" }, { 200617, "windmillgiant01" }, { 200618, "windmillsmall01" },
    { 200619, "windmilltall01" }, { 200644, "batroost" }, { 200660, "undercitytower01" }, { 200661, "undercitytower02" },
    { 200662, "undercitytower03" }, { 200663, "undercitytower04" }, { 200664, "meatwagon" }, { 201263, "corruptdryadshrine01" },
    { 201264, "dryadshrine01" }, { 201265, "dryadshrine02" }, { 201267, "neshrine" }, { 201269, "neshrinesatyr" },
    { 201380, "mkshrine" }, { 201389, "raptorhut01" }, { 201390, "raptorhut02" }, { 201416, "barrenswagon01" },
    { 201982, "nightelfguardtower" }, { 202016, "furbolgtent" }, { 202017, "furbolgtent2" }, { 202029, "kalidarnest01" },
    { 202292, "burnedgypsywagon01" }, { 202494, "elventowersilithus02" }, { 202495, "elventowersilithus03" }, { 202611, "stonetalonharpysnest01" },
    { 202687, "tanariswatertower" }, { 202839, "furbolgtentsnow" }, { 203634, "alteracwatertower" }, { 203656, "arathifarmhouse01" },
    { 203657, "arathifarmhouse02" }, { 204116, "tirisfalloutpost01" }, { 204117, "tirisfalloutpost02" }, { 204118, "tirisfalloutpost03" },
    { 204119, "tirisfalloutpost04" }, { 204142, "uthershrinepedestal" }, { 204144, "tirisfallwindmill" },
}
-- Lordaeron, Plaguelands, Stratholme, Scholomance and Undercity props for the Undead buildings
St.GALLERY_UD = {
    { 200660, "undercitytower01" }, { 200661, "undercitytower02" }, { 200662, "undercitytower03" }, { 200663, "undercitytower04" },
    { 204006, "furnace_skull01" }, { 203718, "arcoftriumphplagued01" }, { 204076, "arcoftriumph01" }, { 204007, "deathknight_gate01" },
    { 204005, "zigguratdoor" }, { 203989, "largeportcullis" }, { 203993, "nox_door_plague" }, { 203990, "nox_door_abom" },
    { 203749, "plaguecauldron" }, { 191217, "plaguecauldronactive" }, { 191218, "plaguecauldronactivebase" }, { 203881, "greenbubblingcauldron" },
    { 203737, "plaugelandscage01" }, { 203752, "plaguechariot" }, { 203754, "plaguewagon" }, { 203755, "plaguewagon02" },
    { 200782, "undead_operation_table" }, { 203895, "creepyoperationtable01" }, { 200667, "meatwagonhauler" }, { 200784, "undead_teslacoil" },
    { 204019, "nox_tesla" }, { 203726, "bonewall_01" }, { 203723, "bonespike_01" }, { 203831, "undeadwall_01" },
    { 204090, "massgrave" }, { 204104, "brillcoffins" }, { 204105, "brillgraves01" }, { 204107, "brillgraves03" },
    { 204114, "tirisfallopengrave01" }, { 189496, "duskwoodmausoleum" }, { 189536, "tombstonemonument01" }, { 189538, "tombstonemonument02" },
    { 200754, "lordaeron_statue_01" }, { 200755, "lordaeron_statue_02" }, { 200756, "lordaeron_statue_03" }, { 204142, "uthershrinepedestal" },
    { 189280, "warlockshrine" }, { 190706, "spiderpod01" }, { 204065, "kelthuzad_throne" }, { 200659, "tyranusthrone" },
    { 200644, "batroost" }, { 200645, "batroost02" }, { 203912, "ghoul_in_a_jar" }, { 203913, "skeleton_in_a_jar" },
    { 204091, "scourgebodyhanging01" }, { 200793, "undeadelevator" }, { 204013, "plaguewingsporetrap" }, { 203845, "scholomancebrazier01purple" },
    { 204116, "tirisfalloutpost01" }, { 204118, "tirisfalloutpost03" }, { 204120, "tirisfalloutpost05" }, { 204122, "tirisfalloutpost07" },
}
local PER, COLS = 24, 6

function St.gallery(page)
    local g = St.gal
    if not g then
        g = CreateFrame("Frame", "SkirmishGallery", UI.frame, "BackdropTemplate")
        g:SetAllPoints(UI.view)
        g:SetFrameLevel(UI.overLayer:GetFrameLevel() + 50)
        UI.backdrop(g, true)
        g:EnableMouse(true)
        g:EnableMouseWheel(true)
        g.title = g:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        g.title:SetPoint("TOPLEFT", 14, -10)
        g.labels = {}
        for i = 1, PER do
            local l = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            g.labels[i] = l
        end
        local close = UI.button(g, "Close", 70, 22)
        close:SetPoint("TOPRIGHT", -10, -8)
        close:SetScript("OnClick", function() g.auto = false g:Hide() end)
        local nxt = UI.button(g, "Next", 70, 22)
        nxt:SetPoint("RIGHT", close, "LEFT", -6, 0)
        nxt:SetScript("OnClick", function() St.gallery(g.page + 1) end)
        local prev = UI.button(g, "Back", 70, 22)
        prev:SetPoint("RIGHT", nxt, "LEFT", -6, 0)
        prev:SetScript("OnClick", function() St.gallery(g.page - 1) end)
        g:SetScript("OnMouseWheel", function(_, d) St.gallery(g.page - d) end)
        g:SetScript("OnHide", function() UI.Figures.clear("gallery") end)
        g:SetScript("OnUpdate", function(self, elapsed)
            local F = UI.Figures
            -- "/skirmish gallery auto" turns the page by itself every 8 seconds
            if self.auto then
                self.autoT = (self.autoT or 0) + (elapsed or 0)
                if self.autoT > 8 then self.autoT = 0 St.gallery(self.page % math.ceil(#(self.list or St.GALLERY) / PER) + 1) end
            end
            local W, H = UI.VIEW_W or self:GetWidth(), (UI.VIEW_H or self:GetHeight()) - 40
            local cw, ch = W / COLS, H / (PER / COLS)
            F.begin("gallery")
            for i = 1, PER do
                local it = (self.list or St.GALLERY)[(self.page - 1) * PER + i]
                local l = self.labels[i]
                local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
                local cx, by = cw * (col + 0.5), 40 + ch * (row + 1)
                if it then
                    l:SetText(it[1] .. "  " .. it[2])
                    l:ClearAllPoints()
                    l:SetPoint("BOTTOM", self, "TOPLEFT", cx, -by + 4)
                    l:Show()
                    F.place("gallery", i, self, { file = it[1], pad = 1.6 }, cx, by - ch * 0.42, cw * 0.95, 0.85, 8,
                        F.yawFor(math.pi * 0.5), 2 + row * 2, 0, 1)
                else
                    l:Hide()
                end
            end
            F.finish("gallery")
        end)
        St.gal = g
    end
    -- "/skirmish gallery undead [auto]" shows the Undead candidates instead
    if type(page) == "string" and page:match("^undead") then
        g.list = St.GALLERY_UD
        page = page:match("auto") and "auto" or (tonumber(page:match("%d+")) or 1)
    elseif type(page) == "string" and page ~= "" then
        g.list = nil
    end
    local pages = math.ceil(#(g.list or St.GALLERY) / PER)
    if page == "auto" then g.auto, g.autoT, page = true, 0, 1 elseif type(page) == "string" then g.auto = false end
    page = tonumber(page) or g.page or 1
    if page < 1 then page = pages elseif page > pages then page = 1 end
    g.page = page
    UI.Figures.clear("gallery")
    g.title:SetText(string.format("Model gallery  page %d of %d  (mouse wheel or Next/Back)", page, pages))
    g:Show()
end
