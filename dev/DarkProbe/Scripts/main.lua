-- DarkProbe: dumps the on-screen UMG widget trees (colors, brushes, materials)
-- once per distinct set of visible screens. Read-only; changes nothing.
local OUT = "C:/Users/admin/src/swgr-re/darkprobe_out/"
local seen, dumps, materials = {}, 0, {}

local function ok(f, ...) local s, r = pcall(f, ...); if s then return r end end
local function name(o) return ok(function() return o:GetFullName() end) or "?" end
local function valid(o) return o ~= nil and ok(function() return o:IsValid() end) end
local function lc(c)
    if not c then return "nil" end
    return ok(function() return string.format("(%.2f %.2f %.2f %.2f)", c.R, c.G, c.B, c.A) end) or "?"
end
local function sc(s)
    if not s then return "nil" end
    return ok(function() return lc(s.SpecifiedColor) .. (s.ColorUseRule ~= 0 and "/rule" .. s.ColorUseRule or "") end) or "?"
end
local function res(o)
    if not valid(o) then return "none" end
    local n = name(o)
    if n:find("^MaterialInstance") or n:find("^Material ") then materials[n] = o end
    return n
end
local function brush(b)
    if not b then return "nil" end
    return ok(function()
        return string.format("tint=%s res=%s drawAs=%s", sc(b.TintColor), res(b.ResourceObject), tostring(b.DrawAs))
    end) or "?"
end

local function describe(w)
    local cls = name(w:GetClass())
    local short = cls:match("%.([%w_]+)$") or cls
    local parts = { short, (name(w):match("[%.:]([%w_]+)$") or "?") }
    local vis = ok(function() return w.Visibility end)
    parts[#parts + 1] = "vis=" .. tostring(vis)
    local op = ok(function() return w.RenderOpacity end)
    if op and op ~= 1 then parts[#parts + 1] = string.format("op=%.2f", op) end
    local ds = ok(function() return w:GetDesiredSize() end)
    if ds then parts[#parts + 1] = string.format("size=%.0fx%.0f", ds.X or 0, ds.Y or 0) end
    local function add(label, v) if v then parts[#parts + 1] = label .. "=" .. v end end
    if ok(function() return w:IsA("/Script/UMG.Image") end) then
        add("brush", ok(function() return brush(w.Brush) end))
        add("color", ok(function() return lc(w.ColorAndOpacity) end))
    end
    if ok(function() return w:IsA("/Script/UMG.Border") end) then
        add("bg", ok(function() return brush(w.Background) end))
        add("brushColor", ok(function() return lc(w.BrushColor) end))
        add("content", ok(function() return lc(w.ContentColorAndOpacity) end))
    end
    if ok(function() return w:IsA("/Script/UMG.TextLayoutWidget") end) then
        add("textColor", ok(function() return sc(w.ColorAndOpacity) end))
        add("text", ok(function() return '"' .. w:GetText():ToString():sub(1, 40):gsub("\n", " ") .. '"' end))
        add("style", ok(function() return name(w.Style) end))
        add("styleSet", ok(function() return name(w.TextStyleSet) end))
    end
    if ok(function() return w:IsA("/Script/UMG.Button") end) then
        add("normal", ok(function() return brush(w.WidgetStyle.Normal) end))
        add("hovered", ok(function() return brush(w.WidgetStyle.Hovered) end))
        add("btnBg", ok(function() return lc(w.BackgroundColor) end))
    end
    if ok(function() return w:IsA("/Script/CommonUI.CommonBorder") end) then
        add("cbStyle", ok(function() return name(w.Style) end))
    end
    if ok(function() return w:IsA("/Script/CommonUI.CommonButtonBase") end) then
        add("cbtnStyle", ok(function() return name(w.Style) end))
    end
    if ok(function() return w:IsA("/Script/UMG.UserWidget") end) then
        add("uwColor", ok(function() return lc(w.ColorAndOpacity) end))
    end
    return table.concat(parts, " "), vis
end

local function walk(w, depth, out, count)
    if not valid(w) or depth > 40 or count[1] > 6000 then return end
    count[1] = count[1] + 1
    local line, vis = describe(w)
    local hidden = (vis == 1 or vis == 2)
    out[#out + 1] = string.rep("  ", depth) .. (hidden and "[hidden] " or "") .. line
    if hidden then return end
    if ok(function() return w:IsA("/Script/UMG.UserWidget") end) then
        local root = ok(function() return w.WidgetTree.RootWidget end)
        walk(root, depth + 1, out, count)
    end
    local n = ok(function() return w:GetChildrenCount() end)
    if n then
        for i = 0, n - 1 do walk(ok(function() return w:GetChildAt(i) end), depth + 1, out, count) end
    end
end

local function dump_materials(f)
    for n, m in pairs(materials) do
        f:write(n, "\n")
        local p = m
        for _ = 1, 6 do
            p = ok(function() return p.Parent end)
            if not valid(p) then break end
            f:write("  parent ", name(p), "\n")
        end
        ok(function()
            m.VectorParameterValues:ForEach(function(_, it)
                local e = it:get()
                f:write("  vec ", e.ParameterInfo.Name:ToString(), " = ", lc(e.ParameterValue), "\n")
            end)
        end)
        ok(function()
            m.ScalarParameterValues:ForEach(function(_, it)
                local e = it:get()
                f:write(string.format("  scalar %s = %.3f\n", e.ParameterInfo.Name:ToString(), e.ParameterValue))
            end)
        end)
        ok(function()
            m.TextureParameterValues:ForEach(function(_, it)
                local e = it:get()
                f:write("  tex ", e.ParameterInfo.Name:ToString(), " = ", name(e.ParameterValue), "\n")
            end)
        end)
    end
end

local function dump_mpcs()
    local f = io.open(OUT .. "mpcs.txt", "w"); if not f then return end
    for _, c in ipairs(FindAllOf("MaterialParameterCollection") or {}) do
        f:write(name(c), "\n")
        ok(function() c.VectorParameters:ForEach(function(_, it)
            local e = it:get(); f:write("  vec ", e.ParameterName:ToString(), " = ", lc(e.DefaultValue), "\n") end) end)
        ok(function() c.ScalarParameters:ForEach(function(_, it)
            local e = it:get(); f:write(string.format("  scalar %s = %.3f\n", e.ParameterName:ToString(), e.DefaultValue)) end) end)
    end
    f:close()
end

local mpc_done = false
LoopInGameThreadWithDelay(1500, function()
    local roots, names = {}, {}
    for _, w in ipairs(FindAllOf("UserWidget") or {}) do
        if valid(w) and ok(function() return w:IsInViewport() end) then
            local cls = name(w:GetClass())
            if cls:find("/Game/", 1, true) then
                roots[#roots + 1] = w
                names[#names + 1] = cls:match("%.([%w_]+)$") or cls
            end
        end
    end
    if #roots == 0 then return end
    if not mpc_done then mpc_done = true; dump_mpcs() end
    table.sort(names)
    local key = table.concat(names, ",")
    if seen[key] then return end
    seen[key] = true
    dumps = dumps + 1
    local out, count = {}, { 0 }
    for _, r in ipairs(roots) do walk(r, 0, out, count) end
    local f = io.open(string.format("%sscreen_%02d.txt", OUT, dumps), "w")
    if f then
        f:write("screens: ", key, "\n\n", table.concat(out, "\n"), "\n")
        f:close()
    end
    local mf = io.open(OUT .. "materials.txt", "w")
    if mf then dump_materials(mf); mf:close() end
    print(string.format("[DarkProbe] dumped %d (%d widgets): %s\n", dumps, count[1], key))
end)
print("[DarkProbe] loaded\n")
