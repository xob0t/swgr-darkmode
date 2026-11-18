-- UI dark-mode rule engine (hot-reloaded by DarkModeDev).
--
-- Systemic, not per-menu:
--  * "paper" panels = Image/Border brushes that are plain panel shapes (procedural squircle/pill/backing
--    materials or solid boxes) with a light, unsaturated tint  -> tinted dark
--  * dark text whose effective background is a darkened panel or the (now dark) backdrop -> light
--  * CommonUI text style classes with dark text colors -> patched once on their CDO
-- Artwork (textures, portrait materials) and colored panels are left alone.
local M = {}

local CFG = {
    panel = { R = 0.034, G = 0.037, B = 0.040 },      -- linear; replaces paper panels (alpha kept)
    outline = { R = 0.090, G = 0.095, B = 0.100 },    -- replaces light outlines/strokes
    text = { R = 0.78, G = 0.73, B = 0.67 },          -- the game's own cream text color
    dark_luma = 0.12,                                 -- text/panels darker than this are "dark"
    paper_luma = 0.30,                                -- panels lighter than this and unsaturated are "paper"
    paper_sat = 0.15,
    walk_every = 6,                                   -- ticks (0.5 s each) between full re-walks
    debug_file = "C:/Users/admin/src/swgr-darkmode/dev/out/decisions.txt",
}
-- panel shapes (material or texture resource names)
local PANEL_MATERIAL = { "Squircle", "Pill", "Backing", "Backer", "Panel", "Banner", "Rounded", "Box", "TileFill", "Section", "Card", "Plate", "_Fill", "TileButton", "Grunge" }
-- widget names that mean "this image is the base/backing of a component"
local PANEL_WIDGET = { "Img_Tile_Base", "Img_Tile_Fill", "Img_Backer", "Img_Backing", "Img_Base", "Img_Fill", "Img_Panel" }
-- screen-level decoration: never counts as "art" behind text; darkened if light
local BACKDROP_RES = { "Vignette", "Gradient", "Background", "Blur", "Fade" }
local BACKDROP_NAME = { "Vignette", "Background", "Gradient", "Blur", "ColorFill", "Scrim", "Overlay_Tint" }
local SKIP_NAME = { "Icn", "Icon", "Shadow", "Glow", "Pulse", "MinSize", "Insignia", "Flash", "Portrait", "Avatar" }
-- outlines around components: light ones become a muted outline color; never a "background"
local OUTLINE = { "Stroke", "Outline" }
local SKIP_ROOT = { "Hud", "HUD", "MPC_Manager" }

local function ok(f, ...) local s, r = pcall(f, ...); if s then return r end end
local function valid(o) return o ~= nil and ok(function() return o:IsValid() end) end
local function short(o) return ok(function() return o:GetFName():ToString() end) or "?" end
local function full(o) return ok(function() return o:GetFullName() end) or "?" end
local function classname(o) return ok(function() return o:GetClass():GetFName():ToString() end) or "?" end
local function isa(o, c) return ok(function() return o:IsA(c) end) end
local function log(s) print("[DarkModeDev] " .. s .. "\n") end
local function luma(c) return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B end
local function sat(c) return math.max(c.R, c.G, c.B) - math.min(c.R, c.G, c.B) end
local function any(s, list) for _, p in ipairs(list) do if s:find(p, 1, true) then return true end end end
local function fmt(c) return c and string.format("(%.2f %.2f %.2f %.2f)", c.R, c.G, c.B, c.A or 1) or "nil" end
local function near(a, b) return math.abs(a - b) < 0.004 end
-- text/tint colors that read badly on a dark background: very dark, or unsaturated mid-gray
local function too_dark(c) local l = luma(c); return l < CFG.dark_luma or (l < 0.30 and sat(c) < 0.10) end

-- Classify a brush * widget color:
--   "paper"    light unsaturated panel shape            -> darkened, counts as dark backing
--   "backdrop" screen-level decoration (vignette, bg)   -> darkened if light, text on it is lightened
--   "dark"     already dark backing
--   "art"      artwork / colored panel                  -> untouched, text on it untouched
--   nil        draws nothing visible
local function classify(brush, color, wname, opacity)
    if any(wname, SKIP_NAME) then return nil end
    local tint = ok(function() return brush.TintColor.SpecifiedColor end)
    local drawAs = ok(function() return brush.DrawAs end)
    if drawAs == 0 or not tint or not color then return nil end
    local c = { R = tint.R * color.R, G = tint.G * color.G, B = tint.B * color.B, A = tint.A * color.A * (opacity or 1) }
    local res = ok(function() return brush.ResourceObject end)
    local resname = valid(res) and short(res) or ""
    local l = luma(c)
    -- screen-level layers (scrims, vignettes) matter even when quite transparent
    if any(resname, BACKDROP_RES) or any(wname, BACKDROP_NAME) then
        if c.A < 0.08 then return nil end
        return "backdrop", c, resname, l > CFG.paper_luma and sat(c) < CFG.paper_sat
    end
    if c.A < 0.35 then return nil end
    if any(wname, OUTLINE) or any(resname, OUTLINE) then
        return "outline", c, resname, l > CFG.paper_luma and sat(c) < CFG.paper_sat
    end
    local panel = resname == "" or any(resname, PANEL_MATERIAL) or any(wname, PANEL_WIDGET)
    if l < CFG.dark_luma then return "dark", c, resname end
    if panel and l > CFG.paper_luma and sat(c) < CFG.paper_sat then return "paper", c, resname, true end
    return "art", c, resname
end

local CUR_RB = nil   -- nearest RetainerBox ancestor during the walk (they cache their content)
local RB_OF = setmetatable({}, { __mode = "k" })   -- target widget -> RetainerBox
local function add(out, kind, w) out[kind][#out[kind] + 1] = w; if CUR_RB then RB_OF[w] = CUR_RB end end
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local function mul(a, b) return { R = a.R * b.R, G = a.G * b.G, B = a.B * b.B, A = (a.A or 1) * (b.A or 1) } end
local function on_dark(bg) return bg == nil or bg == "paper" or bg == "dark" end

-- bg   = what is drawn behind this subtree (nil = backdrop, which is dark after the scene/vignette fixes)
-- tint = inherited color multiplier (Border.ContentColorAndOpacity, UserWidget.ColorAndOpacity)
local function collect(w, bg, out, depth, path, tint)
    if not valid(w) or depth > 45 then return end
    local vis = ok(function() return w.Visibility end)
    if vis == 1 or vis == 2 then return end
    tint = tint or WHITE
    local n = short(w)
    path = path .. "/" .. n
    local ind = string.rep(" ", depth)
    if isa(w, "/Script/UMG.TextBlock") then
        local c = ok(function() return w.ColorAndOpacity.SpecifiedColor end)
        local eff = c and mul(c, tint)
        local txt = ok(function() return w:GetText():ToString() end) or ""
        out.tree[#out.tree + 1] = ind .. "T " .. n .. " " .. fmt(c) .. " eff=" .. fmt(eff) .. " bg=" .. tostring(bg or "backdrop") .. ' "' .. txt:sub(1, 40):gsub("%c", " ") .. '"'
        -- only fix the text itself when its own color is the dark part (dark tints are fixed at the tint)
        if c and too_dark(c) and on_dark(bg) then
            add(out, "text", w)
            out.log[#out.log + 1] = "TEXT   " .. path .. " " .. fmt(c) .. " on " .. tostring(bg or "backdrop")
        end
        return
    end
    if isa(w, "/Script/UMG.RichTextBlock") then
        -- default (untagged) style comes from the style table; it's resolved into DefaultTextStyle
        local c = ok(function() return w.DefaultTextStyle.ColorAndOpacity.SpecifiedColor end)
        local set = ok(function() return short(w.TextStyleSet) end) or "?"
        out.tree[#out.tree + 1] = ind .. "R " .. n .. " " .. fmt(c) .. " set=" .. set .. " bg=" .. tostring(bg or "backdrop")
        if c and too_dark(c) and on_dark(bg) then
            add(out, "rich", w)
            out.log[#out.log + 1] = "RICH   " .. path .. " " .. fmt(c) .. " " .. set
        end
        return
    end
    if isa(w, "/Script/UMG.UserWidget") then
        local uc = ok(function() local v = w.ColorAndOpacity; return { R = v.R, G = v.G, B = v.B, A = v.A } end) or WHITE
        out.tree[#out.tree + 1] = ind .. "U " .. classname(w) .. " " .. n .. (luma(uc) < 0.99 and (" uw=" .. fmt(uc)) or "")
        if too_dark(uc) and on_dark(bg) then
            add(out, "uwtints", w)
            uc = { R = CFG.text.R, G = CFG.text.G, B = CFG.text.B, A = uc.A }
        end
        collect(ok(function() return w.WidgetTree.RootWidget end), bg, out, depth + 1, path, mul(tint, uc))
        return
    end
    local childBg, childTint = bg, tint
    local myop = ok(function() return w.RenderOpacity end) or 1
    if isa(w, "/Script/UMG.Border") then
        local kind, c, res, darken = classify(ok(function() return w.Background end), ok(function() return w.BrushColor end), n, myop)
        if darken then
            add(out, "borders", w)
            out.log[#out.log + 1] = "BORDER " .. path .. " " .. fmt(c) .. " " .. res
        end
        if kind == "backdrop" then childBg = nil elseif kind then childBg = kind end
        local cc = ok(function() local v = w.ContentColorAndOpacity; return { R = v.R, G = v.G, B = v.B, A = v.A } end) or WHITE
        if too_dark(cc) and on_dark(childBg) then
            add(out, "contents", w)
            out.log[#out.log + 1] = "CONTENT " .. path .. " " .. fmt(cc)
            cc = { R = CFG.text.R, G = CFG.text.G, B = CFG.text.B, A = cc.A }
        end
        childTint = mul(tint, cc)
        out.tree[#out.tree + 1] = ind .. "B " .. n .. " " .. tostring(kind) .. (darken and "*" or "") .. " " .. fmt(c) .. " " .. tostring(res) .. " content=" .. fmt(cc)
    else
        out.tree[#out.tree + 1] = ind .. classname(w):gsub("^Fuse", "") .. " " .. n
    end
    if isa(w, "/Script/UMG.ListViewBase") then
        -- list/tile views generate entry widgets; they are not panel children
        local entries = {}
        local r = ok(function() return w:GetDisplayedEntryWidgets() end)
        if type(r) == "table" then
            for _, e in ipairs(r) do entries[#entries + 1] = (type(e) == "userdata" and ok(function() return e:get() end)) or e end
        elseif r ~= nil then
            ok(function() r:ForEach(function(_, it) entries[#entries + 1] = it:get() end) end)
        end
        out.tree[#out.tree + 1] = ind .. " (" .. #entries .. " list entries, ret " .. type(r) .. ")"
        for _, e in ipairs(entries) do collect(e, childBg, out, depth + 1, path, childTint) end
        return
    end
    local count = ok(function() return w:GetChildrenCount() end) or 0
    local overlay = isa(w, "/Script/UMG.Overlay") or isa(w, "/Script/UMG.CanvasPanel")
    local siblingBg = childBg
    local prevRB = CUR_RB
    if isa(w, "/Script/UMG.RetainerBox") then CUR_RB = w; out.retainers[#out.retainers + 1] = w end
    for i = 0, count - 1 do
        local child = ok(function() return w:GetChildAt(i) end)
        if valid(child) and isa(child, "/Script/UMG.Image") then
            local cvis = ok(function() return child.Visibility end)
            if cvis ~= 1 and cvis ~= 2 then
                local cname = short(child)
                local cop = ok(function() return child.RenderOpacity end) or 1
                local kind, c, res, darken = classify(ok(function() return child.Brush end), ok(function() return child.ColorAndOpacity end), cname, cop)
                local sz = ok(function() local d = child:GetDesiredSize(); return string.format("%.0fx%.0f", d.X, d.Y) end) or "?"
                out.tree[#out.tree + 1] = ind .. " I " .. cname .. " " .. tostring(kind) .. (darken and "*" or "") .. " " .. fmt(c) .. " " .. tostring(res) .. " " .. sz
                if darken then
                    add(out, kind == "outline" and "outlines" or "images", child)
                    out.log[#out.log + 1] = "IMAGE  " .. path .. "/" .. cname .. " " .. fmt(c) .. " " .. res
                end
                if kind and overlay and kind ~= "outline" then
                    if kind == "backdrop" then siblingBg = childBg else siblingBg = kind end
                end
            end
        else
            collect(child, overlay and siblingBg or childBg, out, depth + 1, path, childTint)
        end
    end
    CUR_RB = prevRB
end

local function roots()
    local list, key = {}, {}
    for _, w in ipairs(FindAllOf("UserWidget") or {}) do
        if valid(w) and ok(function() return w:IsInViewport() end) then
            local cn = classname(w)
            if cn:find("^WBP_") and not any(cn, SKIP_ROOT) then list[#list + 1] = w; key[#key + 1] = cn end
        end
    end
    table.sort(key)
    return list, table.concat(key, ",")
end

-- Each returns true when it actually changed something (so cached RetainerBoxes can be re-rendered).
local function darken_image(img)
    local c = ok(function() return img.ColorAndOpacity end)
    if c and not near(c.R, CFG.panel.R) then img:SetColorAndOpacity({ R = CFG.panel.R, G = CFG.panel.G, B = CFG.panel.B, A = c.A }); return true end
end
local function darken_border(b)
    local c = ok(function() return b.BrushColor end)
    if c and not near(c.R, CFG.panel.R) then b:SetBrushColor({ R = CFG.panel.R, G = CFG.panel.G, B = CFG.panel.B, A = c.A }); return true end
end
local function lighten_text(t)
    local c = ok(function() return t.ColorAndOpacity.SpecifiedColor end)
    if c and too_dark(c) then
        t:SetColorAndOpacity({ SpecifiedColor = { R = CFG.text.R, G = CFG.text.G, B = CFG.text.B, A = c.A }, ColorUseRule = 0 })
        return true
    end
end
local function lighten_content(b)
    local c = ok(function() return b.ContentColorAndOpacity end)
    if c and too_dark(c) then
        b:SetContentColorAndOpacity({ R = CFG.text.R, G = CFG.text.G, B = CFG.text.B, A = c.A })
        return true
    end
end
local function lighten_uw(w)
    local c = ok(function() return w.ColorAndOpacity end)
    if c and too_dark(c) then
        w:SetColorAndOpacity({ R = CFG.text.R, G = CFG.text.G, B = CFG.text.B, A = c.A })
        return true
    end
end
local function lighten_rich(w)
    local c = ok(function() return w.DefaultTextStyle.ColorAndOpacity.SpecifiedColor end)
    if c and too_dark(c) then
        w:SetDefaultColorAndOpacity({ SpecifiedColor = { R = CFG.text.R, G = CFG.text.G, B = CFG.text.B, A = c.A }, ColorUseRule = 0 })
        return true
    end
end
local function outline_image(img)
    local c = ok(function() return img.ColorAndOpacity end)
    if c and not near(c.R, CFG.outline.R) then img:SetColorAndOpacity({ R = CFG.outline.R, G = CFG.outline.G, B = CFG.outline.B, A = c.A }); return true end
end
local KINDS = { "images", "outlines", "borders", "text", "contents", "uwtints", "rich" }
local APPLY = { images = darken_image, outlines = outline_image, borders = darken_border, text = lighten_text, contents = lighten_content, uwtints = lighten_uw, rich = lighten_rich }

function M.tick(ctx)
    if ctx.reloaded then ctx.reloaded = false; ctx.state = { n = 0 } end
    local st = ctx.state
    st.n = st.n + 1
    -- dev only: one-shot experiments (out/exp.lua is run once with helpers, then deleted)
    local EXP = "C:/Users/admin/src/swgr-darkmode/dev/out/exp.lua"
    local ef = (ctx.dev ~= false) and io.open(EXP, "r")
    if ef then
        local src = ef:read("*a"); ef:close(); os.remove(EXP)
        local chunk, err = load(src, "exp.lua", "t", setmetatable({ ok = ok, valid = valid, short = short, full = full,
            classname = classname, isa = isa, log = log, fmt = fmt, CFG = CFG }, { __index = _G }))
        if chunk then
            local s, e = pcall(chunk)
            log("exp: " .. (s and ("ok " .. tostring(e)) or ("error " .. tostring(e))))
        else log("exp compile error: " .. tostring(err)) end
    end
    if not st.targets or st.n % CFG.walk_every == 0 then
        local list, key = roots()
        local sink = setmetatable({}, { __newindex = function() end })   -- discards debug lines outside dev
        local out = { images = {}, outlines = {}, borders = {}, text = {}, contents = {}, uwtints = {}, rich = {}, retainers = {},
            log = (ctx.dev ~= false) and {} or sink, tree = (ctx.dev ~= false) and {} or sink }
        for _, r in ipairs(list) do collect(r, nil, out, 0, classname(r)) end
        local req = (ctx.dev ~= false) and io.open("C:/Users/admin/src/swgr-darkmode/dev/out/dump.req", "r")
        if req then req:close(); os.remove("C:/Users/admin/src/swgr-darkmode/dev/out/dump.req") end
        if (ctx.dev ~= false) and (key ~= st.key or req) then
            log(string.format("%d roots: %d panels + %d borders, %d texts, %d rich, %d content tints, %d widget tints",
                #list, #out.images, #out.borders, #out.text, #out.rich, #out.contents, #out.uwtints))
            local f = io.open(CFG.debug_file, "a")
            if f then f:write("== ", key, "\n", table.concat(out.log, "\n"), "\n"); f:close() end
            DARKMODE_SCREEN_N = (DARKMODE_SCREEN_N or 0) + 1
            local g = io.open(string.format("C:/Users/admin/src/swgr-darkmode/dev/out/screens/%03d.txt", DARKMODE_SCREEN_N), "w")
            if g then g:write("screens: ", key, "\n", table.concat(out.tree, "\n"), "\n"); g:close() end
            log("screen dump " .. DARKMODE_SCREEN_N)
        end
        -- keep earlier targets (once darkened they classify as "dark" and drop out of the walk)
        if st.targets and key == st.key then
            for _, k in ipairs(KINDS) do
                local seen = {}
                for _, o in ipairs(out[k]) do seen[o] = true end
                for _, o in ipairs(st.targets[k]) do if not seen[o] and valid(o) then out[k][#out[k] + 1] = o end end
            end
        end
        st.key, st.targets = key, out
        for _, rb in ipairs(out.retainers) do pcall(function() rb:RequestRender() end) end
        if #out.retainers > 0 and not st.rbLogged then st.rbLogged = true; log("retainer boxes re-rendered: " .. #out.retainers) end
    end
    local rerender = {}
    for _, k in ipairs(KINDS) do
        local f = APPLY[k]
        for _, o in ipairs(st.targets[k]) do
            if valid(o) then
                local s, changed = pcall(f, o)
                if s and changed and RB_OF[o] then rerender[RB_OF[o]] = true end
            end
        end
    end
    for rb in pairs(rerender) do
        if valid(rb) then pcall(function() rb:RequestRender() end) end
    end
end

return M
