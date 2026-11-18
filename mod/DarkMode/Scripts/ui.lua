-- UI dark-mode rule engine. Developed in dev/live.lua (hot-reloaded by DarkModeDev); this is a copy.
--
-- Systemic, not per-menu. Every on-screen widget tree is walked and classified by component type:
--  * "paper" panels: Image/Border brushes that are plain panel shapes (squircle/pill/backing/tile
--    materials or textures, solid boxes) with a light, unsaturated tint            -> tinted dark
--  * screen-level layers (vignettes, blur tints, scrims) that are light             -> tinted dark
--  * light outlines/strokes around components                                       -> muted outline color
--  * dark text, dark Border content tints, dark UserWidget tints and dark rich-text defaults whose
--    effective background is dark (after the above)                                 -> the game's cream
-- Artwork (thumbnails, portraits, textures), decoration and colored panels are left alone.
--
-- Cost control: the host calls M.tick() every frame. A cycle (find on-screen
-- roots, walk them, merge targets) and yields whenever the per-frame budget is used up, so there are no
-- hitches. Type facts are cached per class and names per object address.
local M = {}

local CFG = {
    panel = { R = 0.034, G = 0.037, B = 0.040 },      -- linear; replaces paper panels (alpha kept)
    outline = { R = 0.090, G = 0.095, B = 0.100 },    -- replaces light outlines/strokes
    text = { R = 0.78, G = 0.73, B = 0.67 },          -- the game's own cream text color
    -- letters on light keyboard key caps. The textured input icons have cut-out glyphs that show the
    -- darkened hint bar through them (about sRGB 60), so the letters use that, not black.
    keytext = { R = 0.045, G = 0.042, B = 0.039 },
    dark_luma = 0.12,                                 -- text/panels darker than this are "dark"
    paper_luma = 0.30,                                -- panels lighter than this and unsaturated are "paper"
    paper_sat = 0.15,
    budget_ms = 1.0,                                  -- max engine time per frame
    rest_frames = 90,                                 -- frames between scan cycles (new widgets trigger one sooner)
    apply_every = 10,                                 -- frames between re-applying known targets
    force_prod = false,                               -- dev install: run the production path (no dumps)
    debug_file = "C:/Users/admin/src/swgr-darkmode/dev/out/decisions.txt",
    dev_out = "C:/Users/admin/src/swgr-darkmode/dev/out/",
}
-- panel shapes (material or texture resource names)
local PANEL_MATERIAL = { "Squircle", "Pill", "Backing", "Backer", "Panel", "Banner", "Rounded", "Box", "TileFill", "Section", "Card", "Plate", "_Fill", "TileButton", "Grunge" }
-- widget names that mean "this image is the base/backing of a component"
local PANEL_WIDGET = { "Img_Tile_Base", "Img_Tile_Fill", "Img_Backer", "Img_Backing", "Img_Base", "Img_Fill", "Img_Panel" }
-- screen-level layers. "Background" is only trusted on widget names: textures such as
-- T_UI_Insignia_Background_* are artwork.
local BACKDROP_RES = { "Vignette", "Gradient", "Blur", "Fade" }
local BACKDROP_NAME = { "Vignette", "Background", "Gradient", "Blur", "ColorFill", "Scrim", "Overlay_Tint" }
local SKIP_NAME = { "Icn", "Icon", "Shadow", "Glow", "Pulse", "MinSize", "Insignia", "Flash", "Portrait", "Avatar", "Thumbnail", "Preview" }
-- outlines around components: light ones become a muted outline color; never a "background"
local OUTLINE = { "Stroke", "Outline" }
-- thin decorative layers (swoops, line reveals, dials, barcodes): untouched and never a background for text
local DECOR = { "Deco", "Swoop", "Line", "Dial", "Barcode", "Title_Graphics", "ScreenTitles", "Divide" }
local SKIP_ROOT = { "Hud", "HUD", "MPC_Manager" }

local function ok(f, ...) local s, r = pcall(f, ...); if s then return r end end
local function valid(o) return o ~= nil and ok(function() return o:IsValid() end) end
local function short(o) return ok(function() return o:GetFName():ToString() end) or "?" end
local function full(o) return ok(function() return o:GetFullName() end) or "?" end
local function classname(o) return ok(function() return o:GetClass():GetFName():ToString() end) or "?" end
local function addr_of(o) return ok(function() return o:GetAddress() end) end
local TAG = "[DarkModeDev] "
local function log(s) print(TAG .. s .. "\n") end
local function luma(c) return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B end
local function sat(c) return math.max(c.R, c.G, c.B) - math.min(c.R, c.G, c.B) end
local function any(s, list) for _, p in ipairs(list) do if s:find(p, 1, true) then return true end end end
local function fmt(c) return c and string.format("(%.2f %.2f %.2f %.2f)", c.R, c.G, c.B, c.A or 1) or "nil" end
local function near(a, b) return math.abs(a - b) < 0.004 end
local function color4(v) return { R = v.R, G = v.G, B = v.B, A = v.A } end
local function cream(a) return { R = CFG.text.R, G = CFG.text.G, B = CFG.text.B, A = a } end
-- text/tint colors that read badly on a dark background: very dark, or unsaturated mid-gray
local function too_dark(c) local l = luma(c); return l < CFG.dark_luma or (l < 0.30 and sat(c) < 0.10) end
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local function mul(a, b) return { R = a.R * b.R, G = a.G * b.G, B = a.B * b.B, A = (a.A or 1) * (b.A or 1) } end
local function on_dark(bg) return bg == nil or bg == "paper" or bg == "dark" end

---------------------------------------------------------------------------------------------------
-- caches
---------------------------------------------------------------------------------------------------
local CLS = {}        -- path -> UClass (or false)
local function uclass(path)
    local c = CLS[path]
    if c == nil then c = StaticFindObject(path) or false; if c and not valid(c) then c = false end; CLS[path] = c end
    return c or nil
end
local function isA(w, path)
    local c = uclass(path)
    return c ~= nil and ok(function() return w:IsA(c) end) == true
end

local CLASSF = {}     -- class address -> { name, kind, border, list, overlay, retainer }
local FACTS, FACT_N = {}, 0      -- object address -> { addr, cls, name, cf }
local RESNAME, RES_N = {}, 0     -- resource address -> short name

local function facts(w)
    local addr = addr_of(w)
    local clsobj = ok(function() return w:GetClass() end)
    local clsaddr = clsobj and addr_of(clsobj) or 0
    local f = addr and FACTS[addr]
    if f and f.cls == clsaddr then return f end
    local cf = CLASSF[clsaddr]
    if not cf then
        cf = { name = clsobj and short(clsobj) or "?" }
        local U = "/Script/UMG."
        if isA(w, U .. "TextBlock") then cf.kind = "text"
        elseif isA(w, U .. "RichTextBlock") then cf.kind = "rich"
        elseif isA(w, U .. "UserWidget") then cf.kind = "uw"
        elseif isA(w, U .. "Image") then cf.kind = "image"
        else
            cf.kind = "panel"
            cf.border = isA(w, U .. "Border")
            cf.list = isA(w, U .. "ListViewBase")
            -- entry boxes (CommonBoundActionBar = the button-hint bar) own pooled entry widgets
            cf.entrybox = isA(w, U .. "DynamicEntryBoxBase")
            cf.overlay = isA(w, U .. "Overlay") or isA(w, U .. "CanvasPanel")
            cf.retainer = isA(w, U .. "RetainerBox")
        end
        CLASSF[clsaddr] = cf
    end
    f = { addr = addr, cls = clsaddr, name = short(w), cf = cf }
    if cf.kind == "uw" then
        -- widgets created inside another widget live in its WidgetTree; only top-level ones can be screens
        -- UE4SS wraps a null outer in a non-nil userdata; calling methods on it is an access violation
        local outer = ok(function() return w:GetOuter() end)
        f.toplevel = not (valid(outer) and classname(outer) == "WidgetTree")
    end
    if addr then
        if FACT_N > 80000 then FACTS, FACT_N = {}, 0 end
        FACTS[addr] = f; FACT_N = FACT_N + 1
    end
    return f
end

-- Everything above is keyed by object address. After a garbage collection, freed addresses get reused
-- by new objects (often of the same class), so cached names/kinds would describe the wrong object.
-- A canary object that only GC can delete tells us when that happened.
-- (StaticFindObject/FindFirstOf scan the whole object array in this game: 2-10 ms each. Look up the
-- engine and the base class once.)
local function new_canary()
    DARKMODE_CANARY = nil
    pcall(function()
        if not valid(DARKMODE_ENGINE) then DARKMODE_ENGINE = FindFirstOf("GameEngine") end
        local base = uclass("/Script/CoreUObject.Object")
        DARKMODE_CANARY_N = (DARKMODE_CANARY_N or 0) + 1
        DARKMODE_CANARY = StaticConstructObject(base, DARKMODE_ENGINE, FName("DarkModeCanary_" .. DARKMODE_CANARY_N))
    end)
end
DARKMODE_GC_EPOCH = DARKMODE_GC_EPOCH or 0
local function forget_addresses()
    CLASSF, FACTS, FACT_N, RESNAME, RES_N = {}, {}, 0, {}, 0
    DARKMODE_GC_EPOCH = DARKMODE_GC_EPOCH + 1
end
-- true when a GC ran since the last call (the first call only sets up the canary)
local function gc_ran()
    if DARKMODE_CANARY ~= nil and valid(DARKMODE_CANARY) then return false end
    local had = DARKMODE_CANARY ~= nil
    new_canary()
    return had
end

local function resname_of(res)
    if res == nil then return "" end
    local a = addr_of(res)
    if not a or a == 0 then return "" end
    local n = RESNAME[a]
    if n then return n end
    n = valid(res) and short(res) or ""
    if RES_N > 20000 then RESNAME, RES_N = {}, 0 end
    RESNAME[a] = n; RES_N = RES_N + 1
    return n
end

---------------------------------------------------------------------------------------------------
-- classification
---------------------------------------------------------------------------------------------------
-- Classify a brush * widget color:
--   "paper"    light unsaturated panel shape            -> darkened, counts as dark backing
--   "backdrop" screen-level layer (vignette, scrim)     -> darkened if light, text on it is lightened
--   "outline"  component outline                        -> muted if light, never a backing
--   "decor"    thin decoration                          -> untouched, never a backing
--   "dark"     already dark backing
--   "art"      artwork / colored panel                  -> untouched, text on it untouched
--   nil        draws nothing visible
-- 4th return value: whether to recolor it.
local function classify(brush, color, wname, opacity)
    if any(wname, SKIP_NAME) then return nil end
    local tint = ok(function() return brush.TintColor.SpecifiedColor end)
    local drawAs = ok(function() return brush.DrawAs end)
    if drawAs == 0 or not tint or not color then return nil end
    local c = { R = tint.R * color.R, G = tint.G * color.G, B = tint.B * color.B, A = tint.A * color.A * (opacity or 1) }
    local resname = resname_of(ok(function() return brush.ResourceObject end))
    local l = luma(c)
    local light = l > CFG.paper_luma and sat(c) < CFG.paper_sat
    -- screen-level layers (scrims, vignettes) matter even when quite transparent
    if any(resname, BACKDROP_RES) or any(wname, BACKDROP_NAME) then
        if c.A < 0.08 then return nil end
        return "backdrop", c, resname, light
    end
    if c.A < 0.35 then return nil end
    -- blank keyboard key caps (the key letter is a text drawn on top): light cap, dark letter, like
    -- the textured input icons. Classified by resource, whatever color they currently have.
    if resname:find("T_UI_Cntrl_", 1, true) and resname:find("Blank", 1, true) then
        return "keycap", c, resname, l < CFG.paper_luma
    end
    if any(wname, DECOR) or any(resname, DECOR) then return "decor", c, resname end
    if any(wname, OUTLINE) or any(resname, OUTLINE) then return "outline", c, resname, light end
    if l < CFG.dark_luma then return "dark", c, resname end
    local panel = resname == "" or any(resname, PANEL_MATERIAL) or any(wname, PANEL_WIDGET)
    if panel and light then return "paper", c, resname, true end
    return "art", c, resname
end

---------------------------------------------------------------------------------------------------
-- walk: an explicit work stack, so a cycle can be spread over many frames
-- (UE4SS can't call into the engine from Lua coroutines)
---------------------------------------------------------------------------------------------------
local DEV = true            -- debug strings only in dev

---------------------------------------------------------------------------------------------------
-- template learning: a UserWidget's tree is copied from its class's template tree
-- (<class path>:WidgetTree.<widget name>) when the widget initializes. Every recolor decision is also
-- recorded for the template it came from (saved to learned.txt), and a class's learned templates are
-- patched when its first instance is created, before that instance copies them. Screens then come up
-- dark from their first frame instead of flashing white until a scan cycle catches up.
-- Templates are reached by walking class.WidgetTree (StaticFindObject scans every object here).
---------------------------------------------------------------------------------------------------
local APPLY                 -- defined below (apply section)
local LEARN_FILE = (function()
    local src = debug.getinfo(1, "S").source or ""
    local dir = src:match("^@(.*[/\\])")         -- shipped: next to ui.lua
    return (dir or CFG.dev_out) .. "learned.txt"  -- dev: live.lua is loaded from a string
end)()
-- global (survives dev hot reloads): by[class path][widget name] = kind, n[class path] = count
DARKMODE_LEARN = DARKMODE_LEARN or nil
local function learned()
    local LL = DARKMODE_LEARN
    if LL then return LL end
    LL = { by = {}, n = {}, fresh = {}, dirty = {} }
    local f = io.open(LEARN_FILE, "r")
    if f then
        for line in f:lines() do
            local k, cp, name = line:match("^(%w+)\t(%S+):WidgetTree%.(%S+)$")
            if k then
                local e = LL.by[cp] or {}; LL.by[cp] = e
                if not e[name] then e[name] = k; LL.n[cp] = (LL.n[cp] or 0) + 1 end
            end
        end
        f:close()
    end
    DARKMODE_LEARN = LL
    return LL
end

-- per class address: { path, epoch, done = learned entries already applied, map = name -> template }
DARKMODE_TPLCLS = DARKMODE_TPLCLS or {}
local function class_path(cls) return full(cls):match("^%S+ (/.+)$") end
local function class_info(cls)
    local a = addr_of(cls)
    if not a then return nil end
    local ci = DARKMODE_TPLCLS[a]
    if ci and ci.epoch ~= DARKMODE_GC_EPOCH then
        -- after a GC the address may belong to another (or a reloaded) class: re-check, re-walk
        if class_path(cls) ~= ci.path then ci = nil else ci.epoch, ci.map, ci.done = DARKMODE_GC_EPOCH, nil, 0 end
    end
    if not ci then
        local p = class_path(cls)
        if not p then return nil end
        ci = { path = p, epoch = DARKMODE_GC_EPOCH, done = 0 }
        DARKMODE_TPLCLS[a] = ci
    end
    return ci
end

local function template_map(ci, cls)
    if ci.map then return ci.map end
    local map, stack, guard = {}, {}, 0
    -- a widget class that inherits another widget Blueprint without adding its own tree uses its
    -- parent's tree (UE's FindWidgetTreeOwningClass), so walk up to the class that owns one
    local c, root = cls, nil
    for _ = 1, 10 do
        root = ok(function() return c.WidgetTree.RootWidget end)
        if valid(root) then break end
        c = ok(function() return c:GetSuperStruct() end)
        if not valid(c) then break end
    end
    stack[1] = root
    while #stack > 0 and guard < 4000 do
        guard = guard + 1
        local w = stack[#stack]; stack[#stack] = nil
        if valid(w) then
            map[short(w)] = w
            local n = ok(function() return w:GetChildrenCount() end) or 0
            for i = 0, n - 1 do stack[#stack + 1] = ok(function() return w:GetChildAt(i) end) end
            -- content placed into a child UserWidget's named slot belongs to this class's tree
            ok(function() w.NamedSlotBindings:ForEach(function(_, b) stack[#stack + 1] = b:get().Content end) end)
        end
    end
    ci.map = map
    return map
end

local function patch_class(cls)
    local ci = class_info(cls)
    if not ci then return end
    local LL = learned()
    local n = LL.n[ci.path] or 0
    if n == 0 or ci.done == n then return end
    local map = template_map(ci, cls)
    for name, kind in pairs(LL.by[ci.path]) do
        local t = map[name]
        if t and valid(t) and APPLY[kind] then pcall(APPLY[kind], t) end
    end
    ci.done = n
end

-- called for every new UserWidget (NotifyOnNewObject), before it initializes its tree
local function on_new(o)
    -- skip CDOs, archetypes and objects being loaded (those can be created off the game thread)
    local s, skip = pcall(function() return o:HasAnyFlags(0x10 | 0x20 | 0x400 | 0x80000) end)
    if not s or skip then return end
    local cls = ok(function() return o:GetClass() end)
    if valid(cls) then patch_class(cls) end
end

-- (timed: this runs inside object construction, outside the per-frame budget)
PERF = PERF or { tick = 0, tick_max = 0, cb = 0, cb_n = 0, frames = 0 }
DARKMODE_ON_NEW = function(o)
    local t0 = os.clock()
    on_new(o)
    local dt = os.clock() - t0
    PERF.cb = PERF.cb + dt; PERF.cb_n = PERF.cb_n + 1
end

-- the template a widget instance came from: its outer is a WidgetTree whose outer is the UserWidget
local function template_owner(w, F)
    if F.tplc ~= nil then return F.tplc, F.tplp end
    F.tplc = false
    local wt = ok(function() return w:GetOuter() end)
    if valid(wt) and classname(wt) == "WidgetTree" then
        local uw = ok(function() return wt:GetOuter() end)
        local cls = valid(uw) and ok(function() return uw:GetClass() end)
        local cp = valid(cls) and class_path(cls)
        if cp and F.name ~= "?" then F.tplc, F.tplp = cls, cp end
    end
    return F.tplc, F.tplp
end

-- targets are keyed by object address (UE4SS hands out a new Lua wrapper per access)
local function add(out, kind, w, addr, rb)
    if not addr then return end
    out[kind][addr] = { obj = w, rb = rb }
    local F = FACTS[addr]
    if not F then return end
    local cls, cp = template_owner(w, F)
    if cls then
        local LL = learned()
        local e = LL.by[cp] or {}; LL.by[cp] = e
        if not e[F.name] then
            e[F.name] = kind; LL.n[cp] = (LL.n[cp] or 0) + 1
            LL.fresh[#LL.fresh + 1] = kind .. "\t" .. cp .. ":WidgetTree." .. F.name
            LL.dirty[cp] = cls
        end
    end
end

-- One task = one widget plus the context it inherits:
--   bg   = what is drawn behind it (nil = backdrop, which is dark after the scene/vignette fixes)
--   tint = inherited color multiplier (Border.ContentColorAndOpacity, UserWidget.ColorAndOpacity)
--   rb   = nearest RetainerBox ancestor (they cache their content and need a re-render)
local function process(t, out, push)
    local w, bg, depth, path, tint, rb = t.w, t.bg, t.depth, t.path, t.tint or WHITE, t.rb
    if depth > 45 or not valid(w) then return end
    local vis = ok(function() return w.Visibility end)
    if vis == 1 or vis == 2 then return end
    local F = facts(w)
    local cf, n = F.cf, F.name
    local ind
    if DEV then path = path .. "/" .. n; ind = string.rep(" ", depth) end

    if cf.kind == "text" then
        local c = ok(function() return w.ColorAndOpacity.SpecifiedColor end)
        if DEV then
            local txt = ok(function() return w:GetText():ToString() end) or ""
            out.tree[#out.tree + 1] = ind .. "T " .. n .. " " .. fmt(c) .. " eff=" .. fmt(c and mul(c, tint)) .. " bg=" .. tostring(bg or "backdrop") .. ' "' .. txt:sub(1, 40):gsub("%c", " ") .. '"'
        end
        -- a key letter on a (lightened) key cap
        if bg == "keycap" then
            if c and not near(c.R, CFG.keytext.R) then
                add(out, "keytext", w, F.addr, rb)
                if DEV then out.log[#out.log + 1] = "KEYTEXT " .. path .. " " .. fmt(c) end
            end
            return
        end
        -- only fix the text itself when its own color is the dark part (dark tints are fixed at the tint)
        if c and too_dark(c) and on_dark(bg) then
            add(out, "text", w, F.addr, rb)
            if DEV then out.log[#out.log + 1] = "TEXT    " .. path .. " " .. fmt(c) .. " on " .. tostring(bg or "backdrop") end
        end
        return
    end
    if cf.kind == "rich" then
        -- default (untagged) style comes from the style table; it's resolved into DefaultTextStyle
        local c = ok(function() return w.DefaultTextStyle.ColorAndOpacity.SpecifiedColor end)
        if DEV then out.tree[#out.tree + 1] = ind .. "R " .. n .. " " .. fmt(c) .. " bg=" .. tostring(bg or "backdrop") end
        if c and too_dark(c) and on_dark(bg) then
            add(out, "rich", w, F.addr, rb)
            if DEV then out.log[#out.log + 1] = "RICH    " .. path .. " " .. fmt(c) end
        end
        return
    end
    if cf.kind == "uw" then
        local uc = ok(function() return color4(w.ColorAndOpacity) end) or WHITE
        if DEV then out.tree[#out.tree + 1] = ind .. "U " .. cf.name .. " " .. n .. (luma(uc) < 0.99 and (" uw=" .. fmt(uc)) or "") end
        if too_dark(uc) and on_dark(bg) then
            add(out, "uwtints", w, F.addr, rb)
            uc = cream(uc.A)
        end
        local root = ok(function() return w.WidgetTree.RootWidget end)
        if root then push({ w = root, bg = bg, depth = depth + 1, path = path, tint = mul(tint, uc), rb = rb }) end
        return
    end
    if cf.kind == "image" then return end   -- images are handled by their parent (they can be backings)

    local childBg, childTint = bg, tint
    if cf.border then
        local myop = ok(function() return w.RenderOpacity end) or 1
        local kind, c, res, darken = classify(ok(function() return w.Background end), ok(function() return w.BrushColor end), n, myop)
        if darken then
            add(out, "borders", w, F.addr, rb)
            if DEV then out.log[#out.log + 1] = "BORDER  " .. path .. " " .. fmt(c) .. " " .. res end
        end
        if kind == "backdrop" then childBg = nil elseif kind and kind ~= "decor" and kind ~= "outline" then childBg = kind end
        local cc = ok(function() return color4(w.ContentColorAndOpacity) end) or WHITE
        if too_dark(cc) and on_dark(childBg) then
            add(out, "contents", w, F.addr, rb)
            if DEV then out.log[#out.log + 1] = "CONTENT " .. path .. " " .. fmt(cc) end
            cc = cream(cc.A)
        end
        childTint = mul(tint, cc)
        if DEV then out.tree[#out.tree + 1] = ind .. "B " .. n .. " " .. tostring(kind) .. (darken and "*" or "") .. " " .. fmt(c) .. " " .. tostring(res) .. " content=" .. fmt(cc) end
    elseif DEV then
        out.tree[#out.tree + 1] = ind .. cf.name:gsub("^Fuse", "") .. " " .. n
    end

    if cf.list or cf.entrybox then
        -- list/tile views and entry boxes generate entry widgets; they are not panel children
        local entries = {}
        local r = ok(function() return cf.list and w:GetDisplayedEntryWidgets() or w:GetAllEntries() end)
        if type(r) == "table" then
            for _, e in ipairs(r) do entries[#entries + 1] = (type(e) == "userdata" and ok(function() return e:get() end)) or e end
        elseif r ~= nil then
            ok(function() r:ForEach(function(_, it) entries[#entries + 1] = it:get() end) end)
        end
        if DEV then out.tree[#out.tree + 1] = ind .. " (" .. #entries .. " list entries)" end
        for i = #entries, 1, -1 do push({ w = entries[i], bg = childBg, depth = depth + 1, path = path, tint = childTint, rb = rb }) end
        return
    end

    local childRb = rb
    if cf.retainer then childRb = w; out.retainers[#out.retainers + 1] = w end
    local count = ok(function() return w:GetChildrenCount() end) or 0
    local siblingBg = childBg
    local later = {}
    for i = 0, count - 1 do
        local child = ok(function() return w:GetChildAt(i) end)
        if valid(child) then
            local CF = facts(child)
            if CF.cf.kind == "image" then
                -- images are classified inline, in paint order, because in an overlay they are the
                -- backing of the siblings drawn after them
                local cvis = ok(function() return child.Visibility end)
                if cvis ~= 1 and cvis ~= 2 then
                    local cname = CF.name
                    local cop = ok(function() return child.RenderOpacity end) or 1
                    local kind, c, res, darken = classify(ok(function() return child.Brush end), ok(function() return child.ColorAndOpacity end), cname, cop)
                    if DEV then
                        local sz = ok(function() local d = child:GetDesiredSize(); return string.format("%.0fx%.0f", d.X, d.Y) end) or "?"
                        out.tree[#out.tree + 1] = ind .. " I " .. cname .. " " .. tostring(kind) .. (darken and "*" or "") .. " " .. fmt(c) .. " " .. tostring(res) .. " " .. sz
                    end
                    if darken then
                        add(out, kind == "outline" and "outlines" or kind == "keycap" and "keycaps" or "images", child, CF.addr, childRb)
                        if DEV then out.log[#out.log + 1] = "IMAGE   " .. path .. "/" .. cname .. " " .. fmt(c) .. " " .. res end
                    end
                    if kind and cf.overlay and kind ~= "outline" and kind ~= "decor" then
                        if kind == "backdrop" then siblingBg = childBg else siblingBg = kind end
                    end
                end
            else
                later[#later + 1] = { w = child, bg = cf.overlay and siblingBg or childBg, depth = depth + 1, path = path, tint = childTint, rb = childRb }
            end
        end
    end
    for i = #later, 1, -1 do push(later[i]) end   -- reversed so the stack pops them in order
end

local KINDS = { "images", "outlines", "keycaps", "borders", "text", "keytext", "contents", "uwtints", "rich" }
local function new_out()
    local o = { retainers = {}, log = {}, tree = {} }
    for _, k in ipairs(KINDS) do o[k] = {} end
    if not DEV then
        local sink = setmetatable({}, { __newindex = function() end })
        o.log, o.tree = sink, sink
    end
    return o
end

-- A cycle: phase "roots" scans all UserWidgets for on-screen roots, phase "walk" processes the stack.
-- step() works until the deadline and returns the result table when the cycle is complete.
DARKMODE_TOPS = DARKMODE_TOPS or {}   -- global: address -> top-level UserWidget
DARKMODE_NEW = DARKMODE_NEW or {}     -- global: UserWidgets created since the last cycle (NotifyOnNewObject)
local function new_cycle(full_scan)
    -- candidates for on-screen roots: top-level UserWidgets. Recorded as they are created (see the
    -- NotifyOnNewObject hook); a full FindAllOf reseed runs on the first cycle and every 30 cycles.
    local all = {}
    local fresh = DARKMODE_NEW
    DARKMODE_NEW = {}
    if full_scan then
        all = FindAllOf("UserWidget") or {}
    else
        for a, o in pairs(DARKMODE_TOPS) do
            if valid(o) then all[#all + 1] = o else DARKMODE_TOPS[a] = nil end
        end
        for _, o in ipairs(fresh) do all[#all + 1] = o end
    end
    return { phase = "roots", all = all, full = full_scan, i = 0, list = {}, keyparts = {}, stack = {} }
end

local function step_cycle(cy, deadline)
    if cy.phase == "roots" then
        local all = cy.all
        while cy.i < #all do
            cy.i = cy.i + 1
            local w = all[cy.i]
            if valid(w) then
                local F = facts(w)
                if F.toplevel and F.addr then DARKMODE_TOPS[F.addr] = w end
                local cn = F.cf.name
                if F.toplevel and cn:sub(1, 4) == "WBP_" and not any(cn, SKIP_ROOT) and ok(function() return w:IsInViewport() end) then
                    cy.list[#cy.list + 1] = w; cy.keyparts[#cy.keyparts + 1] = cn
                end
            end
            if cy.i % 8 == 0 and os.clock() > deadline then return nil end
        end
        table.sort(cy.keyparts)
        cy.key = table.concat(cy.keyparts, ",")
        cy.out = new_out()
        for i = #cy.list, 1, -1 do
            local r = cy.list[i]
            cy.stack[#cy.stack + 1] = { w = r, bg = nil, depth = 0, path = DEV and facts(r).cf.name or "", tint = WHITE, rb = nil }
        end
        cy.all = nil
        cy.phase = "walk"
    end
    local stack, out = cy.stack, cy.out
    local function push(t) stack[#stack + 1] = t end
    local n = 0
    while #stack > 0 do
        local t = stack[#stack]; stack[#stack] = nil
        process(t, out, push)
        n = n + 1
        if os.clock() > deadline then return nil end
    end
    return { list = cy.list, key = cy.key, out = out }
end

---------------------------------------------------------------------------------------------------
-- apply
---------------------------------------------------------------------------------------------------
-- Each returns true when it actually changed something (so cached RetainerBoxes can be re-rendered).
-- Recolors are conditional on the current color, not just "not ours yet": the same widget gets other
-- colors from the game (accents, highlights, hover states) that must pass through untouched.
local function is_paper(c) return luma(c) > CFG.paper_luma and sat(c) < CFG.paper_sat end
local function paint(img, col, cond)
    local c = ok(function() return img.ColorAndOpacity end)
    if c and not near(c.R, col.R) and cond(c) then img:SetColorAndOpacity({ R = col.R, G = col.G, B = col.B, A = c.A }); return true end
end
APPLY = {
    images = function(w) return paint(w, CFG.panel, is_paper) end,
    outlines = function(w) return paint(w, CFG.outline, is_paper) end,
    keycaps = function(w) return paint(w, CFG.text, function(c) return luma(c) < CFG.paper_luma end) end,
    keytext = function(t)
        local c = ok(function() return t.ColorAndOpacity.SpecifiedColor end)
        if c and not near(c.R, CFG.keytext.R) then
            t:SetColorAndOpacity({ SpecifiedColor = { R = CFG.keytext.R, G = CFG.keytext.G, B = CFG.keytext.B, A = c.A }, ColorUseRule = 0 })
            return true
        end
    end,
    borders = function(b)
        local c = ok(function() return b.BrushColor end)
        if c and not near(c.R, CFG.panel.R) and is_paper(c) then b:SetBrushColor({ R = CFG.panel.R, G = CFG.panel.G, B = CFG.panel.B, A = c.A }); return true end
    end,
    text = function(t)
        local c = ok(function() return t.ColorAndOpacity.SpecifiedColor end)
        if c and too_dark(c) then t:SetColorAndOpacity({ SpecifiedColor = cream(c.A), ColorUseRule = 0 }); return true end
    end,
    contents = function(b)
        local c = ok(function() return b.ContentColorAndOpacity end)
        if c and too_dark(c) then b:SetContentColorAndOpacity(cream(c.A)); return true end
    end,
    uwtints = function(w)
        local c = ok(function() return w.ColorAndOpacity end)
        if c and too_dark(c) then w:SetColorAndOpacity(cream(c.A)); return true end
    end,
    rich = function(w)
        local c = ok(function() return w.DefaultTextStyle.ColorAndOpacity.SpecifiedColor end)
        if c and too_dark(c) then w:SetDefaultColorAndOpacity({ SpecifiedColor = cream(c.A), ColorUseRule = 0 }); return true end
    end,
}

local function apply(targets)
    local rerender = {}
    for _, k in ipairs(KINDS) do
        local f = APPLY[k]
        for a, e in pairs(targets[k]) do
            if valid(e.obj) then
                local s, changed = pcall(f, e.obj)
                if s and changed and e.rb then rerender[addr_of(e.rb) or 0] = e.rb end
            else
                targets[k][a] = nil
            end
        end
    end
    for _, rb in pairs(rerender) do
        if valid(rb) then pcall(function() rb:RequestRender() end) end
    end
end

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

local function save_learned()
    local LL = learned()
    if #LL.fresh == 0 then return end
    local f = io.open(LEARN_FILE, "a")
    if f then f:write(table.concat(LL.fresh, "\n"), "\n"); f:close() end
    LL.fresh = {}
end

---------------------------------------------------------------------------------------------------
-- setter hooks: the game recolors widgets at runtime (hover/focus states, screen intro animations,
-- reactivated screens). Those go through these native setters (also when called from Blueprints or
-- UMG animations), so a post-hook re-applies our color in the same frame, before anything is drawn.
-- Only widgets we know are touched: current targets, or instances of a learned template.
---------------------------------------------------------------------------------------------------
local CUR_ST                -- the tick's state (targets)
local SETTERS = {
    { "/Script/UMG.TextBlock:SetColorAndOpacity", { "text", "keytext" } },
    { "/Script/UMG.Image:SetColorAndOpacity", { "images", "outlines", "keycaps" } },
    { "/Script/UMG.Border:SetBrushColor", { "borders" } },
    { "/Script/UMG.Border:SetContentColorAndOpacity", { "contents" } },
    { "/Script/UMG.UserWidget:SetColorAndOpacity", { "uwtints" } },
    { "/Script/UMG.RichTextBlock:SetDefaultColorAndOpacity", { "rich" } },
}
local in_set = false
local function on_set(kinds, ctx)
    if in_set then return end          -- our own Set* calls
    local w = ok(function() return ctx:get() end)
    if not valid(w) then return end
    local F = facts(w)
    local kind
    local tg = CUR_ST and CUR_ST.targets
    if tg and F.addr then
        for _, k in ipairs(kinds) do if tg[k][F.addr] then kind = k; break end end
    end
    if not kind then
        local cls, cp = template_owner(w, F)
        local lk = cls and learned().by[cp]
        lk = lk and lk[F.name]
        if lk then for _, k in ipairs(kinds) do if k == lk then kind = k; break end end end
    end
    if kind then
        in_set = true
        pcall(APPLY[kind], w)
        in_set = false
    end
end
DARKMODE_ON_SET = function(kinds, ctx)
    local t0 = os.clock()
    on_set(kinds, ctx)
    PERF.set = (PERF.set or 0) + (os.clock() - t0); PERF.set_n = (PERF.set_n or 0) + 1
end
local function register_setter_hooks()
    if DARKMODE_HOOKED or type(RegisterHook) ~= "function" then return end
    DARKMODE_HOOKED = true   -- global: once per Lua state; the callbacks go through DARKMODE_ON_SET
    for _, s in ipairs(SETTERS) do
        local kinds = s[2]
        local okr, err = pcall(RegisterHook, s[1], function() end, function(ctx)
            if DARKMODE_ON_SET then pcall(DARKMODE_ON_SET, kinds, ctx) end
        end)
        if not okr then log("hook failed: " .. s[1] .. " " .. tostring(err)) end
    end
end

---------------------------------------------------------------------------------------------------
-- tick (called every frame by the host)
---------------------------------------------------------------------------------------------------
local function finish(ctx, st, res)
    local out, key = res.out, res.key
    if DEV then
        local req = io.open(CFG.dev_out .. "dump.req", "r")
        if req then req:close(); os.remove(CFG.dev_out .. "dump.req") end
        if req or (key ~= st.key and st.frame - (st.last_dump or -1e9) > 300) then
            st.last_dump = st.frame
            log(string.format("%d roots: %d panels + %d borders + %d outlines, %d texts, %d rich, %d content tints, %d widget tints",
                #res.list, count(out.images), count(out.borders), count(out.outlines), count(out.text), count(out.rich), count(out.contents), count(out.uwtints)))
            local f = io.open(CFG.debug_file, "a")
            if f then f:write("== ", key, "\n", table.concat(out.log, "\n"), "\n"); f:close() end
            DARKMODE_SCREEN_N = (DARKMODE_SCREEN_N or 0) + 1
            DARKMODE_SESSION = DARKMODE_SESSION or os.date("%m%d_%H%M%S")   -- per game launch: no overwrites
            local g = io.open(string.format("%sscreens/%s_%03d.txt", CFG.dev_out, DARKMODE_SESSION, DARKMODE_SCREEN_N), "w")
            if g then g:write("screens: ", key, "\n", table.concat(out.tree, "\n"), "\n"); g:close() end
            log("screen dump " .. DARKMODE_SCREEN_N)
        end
    end
    -- keep earlier targets (once recolored they no longer classify as targets), also from screens that
    -- are not showing now: CommonUI reuses deactivated screens (pause menu under settings). A GC clears them.
    if st.targets then
        for _, k in ipairs(KINDS) do
            for a, e in pairs(st.targets[k]) do
                if out[k][a] == nil and valid(e.obj) then out[k][a] = e end
            end
        end
    end
    st.key, st.targets = key, out
    apply(out)
    save_learned()
    -- retainer boxes cache their content; refresh them once per cycle so earlier changes show
    -- (the cycle spanned several frames: anything collected may have been destroyed since)
    for _, rb in ipairs(out.retainers) do
        if valid(rb) then pcall(function() rb:RequestRender() end) end
    end
end

local function tick_body(ctx)
    if ctx.reloaded then ctx.reloaded = false; ctx.state = { frame = 0 } end
    local st = ctx.state
    st.frame = st.frame + 1
    CUR_ST = st
    DEV = ctx.dev ~= false and not CFG.force_prod
    TAG = DEV and "[DarkModeDev] " or "[DarkMode] "
    register_setter_hooks()
    if not DARKMODE_LEARN_LOGGED then
        DARKMODE_LEARN_LOGGED = true
        local n = 0
        for _, c in pairs(learned().n) do n = n + c end
        log(string.format("%d learned templates (%s)", n, LEARN_FILE))
    end
    TAG = DEV and "[DarkModeDev] " or "[DarkMode] "

    -- dev only: one-shot experiments (out/exp.lua is run once with helpers, then deleted)
    if DEV and st.frame % 30 == 0 then
        local ef = io.open(CFG.dev_out .. "exp.lua", "r")
        if ef then
            local src = ef:read("*a"); ef:close(); os.remove(CFG.dev_out .. "exp.lua")
            local chunk, err = load(src, "exp.lua", "t", setmetatable({ ok = ok, valid = valid, short = short, full = full,
                classname = classname, log = log, fmt = fmt, CFG = CFG }, { __index = _G }))
            if chunk then
                local s, e = pcall(chunk)
                log("exp: " .. (s and ("ok " .. tostring(e)) or ("error " .. tostring(e))))
            else log("exp compile error: " .. tostring(err)) end
        end
    end

    -- garbage collection: address-keyed caches and held objects are no longer trustworthy
    if gc_ran() or st.frame == st.gc_again then
        if st.frame ~= st.gc_again then st.gc_again = st.frame + 30 end   -- purging can span frames
        forget_addresses()
        st.co, st.targets, st.key = nil, nil, nil
        st.next_scan = math.min(st.next_scan or 0, st.frame + 2)
        if DEV then log("gc: caches dropped") end
    end

    -- scan cycle, time-sliced
    -- new widgets were created (a screen opened): start a cycle now instead of waiting
    if not DARKMODE_NOTIFY and type(NotifyOnNewObject) == "function" then
        DARKMODE_NOTIFY = true   -- global: registered once per Lua state, survives hot reloads
        -- the callback runs inside object construction: only queue the object, inspect it later
        pcall(NotifyOnNewObject, "/Script/UMG.UserWidget", function(o)
            DARKMODE_DIRTY = true
            local q = DARKMODE_NEW
            if #q < 20000 then q[#q + 1] = o end
            if DARKMODE_ON_NEW then pcall(DARKMODE_ON_NEW, o) end
        end)
    end
    if DARKMODE_DIRTY and not st.co then DARKMODE_DIRTY = false; st.next_scan = math.min(st.next_scan or 0, math.max(st.frame + 2, (st.last_end or 0) + 15)) end
    if not st.co and st.frame >= (st.next_scan or 0) then
        local t0 = os.clock()
        -- FindAllOf scans every object (one long frame): only seed once, new widgets come from NotifyOnNewObject
        st.co = new_cycle(st.cycles == nil)
        st.cycle_ms, st.cycle_slices = (os.clock() - t0) * 1000, 0
    end
    if st.co then
        local t0 = os.clock()
        local okr, res = pcall(step_cycle, st.co, t0 + CFG.budget_ms / 1000)
        local dt = (os.clock() - t0) * 1000
        st.cycle_ms = st.cycle_ms + dt; st.cycle_slices = st.cycle_slices + 1
        st.max_slice = math.max(st.max_slice or 0, dt)
        if not okr then
            log("scan error: " .. tostring(res))
            st.co = nil; st.next_scan = st.frame + 120
        elseif res then
            st.co = nil; st.next_scan = st.frame + CFG.rest_frames; st.last_end = st.frame
            local s, e = pcall(finish, ctx, st, res)
            if not s then log("finish error: " .. tostring(e)) end
            st.cycles = (st.cycles or 0) + 1
            if ctx.dev ~= false and st.cycles % 20 == 0 then
                log(string.format("cycle: %.1f ms over %d frames (max slice %.1f ms)", st.cycle_ms, st.cycle_slices, st.max_slice))
                st.max_slice = 0
            end
        end
    end

    -- classes that learned something new: patch their templates now
    local LL = learned()
    if next(LL.dirty) then
        local d = LL.dirty; LL.dirty = {}
        for _, cls in pairs(d) do if valid(cls) then pcall(patch_class, cls) end end
    end

    -- keep known targets recolored (the game resets colors on hover/state changes)
    if st.targets and not st.co and st.frame % CFG.apply_every == 0 then
        local s, e = pcall(apply, st.targets)
        if not s then log("apply error: " .. tostring(e)) end
    end
end

function M.tick(ctx)
    local t0 = os.clock()
    tick_body(ctx)
    local dt = os.clock() - t0
    PERF.tick = PERF.tick + dt; PERF.frames = PERF.frames + 1
    if dt > PERF.tick_max then PERF.tick_max = dt end
    if PERF.frames >= 300 then
        if ctx.dev ~= false then
            log(string.format("perf: tick avg %.2f ms max %.1f ms; new-widget callbacks %d, %.2f ms/frame; setter hooks %d, %.2f ms/frame",
                PERF.tick * 1000 / PERF.frames, PERF.tick_max * 1000, PERF.cb_n, PERF.cb * 1000 / PERF.frames,
                PERF.set_n or 0, (PERF.set or 0) * 1000 / PERF.frames))
        end
        PERF.tick, PERF.tick_max, PERF.cb, PERF.cb_n, PERF.frames, PERF.set, PERF.set_n = 0, 0, 0, 0, 0, 0, 0
    end
end

return M
