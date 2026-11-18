-- Deterministic test: every step sets ABSOLUTE values for every knob (re-applied each tick),
-- so nothing can compound between steps or reloads. Originals are captured once per game session.
local M = {}
local TICKS_PER_STEP = 10   -- 5 s per step

local function ok(f, ...) local s, r = pcall(f, ...); if s then return r end end
local function valid(o) return o ~= nil and ok(function() return o:IsValid() end) end
local function full(o) return ok(function() return o:GetFullName() end) or "?" end
local function short(o) return ok(function() return o:GetFName():ToString() end) or "?" end
local function live(list)
    local r = {}
    for _, o in ipairs(list or {}) do
        if valid(o) and not full(o):find("Default__", 1, true) then r[#r + 1] = o end
    end
    return r
end
local function log(s) print("[DarkMode] " .. s .. "\n") end
local function near(a, b) return a and b and math.abs(a - b) < 1e-3 end

-- Originals survive hot reloads (stored in a global), so they are captured from the untouched scene once.
DARKMODE_ORIG = DARKMODE_ORIG or {}
local O = DARKMODE_ORIG

local K   -- knobs: discovered objects
local function discover()
    K = { lights = {}, mids = {}, fogplanes = live(FindAllOf("BP_FogPlane_VFX_C")) }
    for _, kind in ipairs({ "DirectionalLightComponent", "SkyLightComponent", "SpotLightComponent", "PointLightComponent", "RectLightComponent" }) do
        for _, l in ipairs(live(FindAllOf(kind))) do
            local key = full(l)
            if O[key] == nil then O[key] = l.Intensity end
            K.lights[#K.lights + 1] = { obj = l, orig = O[key] }
        end
    end
    local TINTABLE = { SM_LiminalSphereBackground = true, Plane = true, SM_FrontEndStudio_01 = true }
    for _, a in ipairs(live(FindAllOf("StaticMeshActor"))) do
        local comp = ok(function() return a.StaticMeshComponent end)
        local mesh = valid(comp) and ok(function() return comp.StaticMesh end)
        local meshname = valid(mesh) and short(mesh) or ""
        if TINTABLE[meshname] then
            local n = ok(function() return comp:GetNumMaterials() end) or 1
            for slot = 0, n - 1 do
                local m = ok(function() return comp:GetMaterial(slot) end)
                if valid(m) and full(m):find("FrontendFloor", 1, true) then
                    local mid = m
                    if not full(m):find("MaterialInstanceDynamic", 1, true) then
                        mid = comp:CreateDynamicMaterialInstance(slot, m, FName("None"))
                    end
                    local key = "param:" .. full(a) .. ":" .. slot
                    if O[key] == nil then
                        local c = mid:K2_GetVectorParameterValue(FName("Param"))
                        O[key] = { R = c.R, G = c.G, B = c.B, A = c.A }
                    end
                    K.mids[#K.mids + 1] = { obj = mid, orig = O[key], name = short(a), mesh = meshname, slot = slot }
                end
            end
        end
    end
    local f = io.open("C:/Users/admin/src/swgr-re/darkmode/originals.txt", "w")
    for _, l in ipairs(K.lights) do f:write(full(l.obj):match("[^%.]+$"), " ", tostring(l.orig), "\n") end
    for _, m in ipairs(K.mids) do f:write(m.mesh, " slot ", m.slot, " ", m.name, string.format(" Param %.3f %.3f %.3f\n", m.orig.R, m.orig.G, m.orig.B)) end
    f:close()
end

local DARK = { R = 0.02, G = 0.019, B = 0.018, A = 1 }
-- Each step lists only what differs from the untouched scene. Fields:
--   dir / sky / other = light scale for directional / sky / all other lights
--   bg = backdrop color, nofogplanes, noatm, nofog, ui
-- The height fog is OFF in the untouched scene, so every step keeps nofog = true.
-- Redo of rounds 2 (cumulative) and 3 (combinations), each at 100% and 20% light.
local function L20(t) t.sky = 0.2; t.dir = 0.2; t.other = 0.2; return t end
local function S(t) t.nofog = true; t.nosph = true; t.nofogplanes = true; t.noflr = true; t.nostu = true; t.ui = true; return t end
local TEAL = { R = 0.020, G = 0.034, B = 0.036, A = 1 }
local BROWN = { R = 0.030, G = 0.019, B = 0.011, A = 1 }
local function T(t) t.nofog = true; t.nosph = true; t.nofogplanes = true; t.dir = 0.2; t.ui = true; return t end
local STEPS = {
    { "sun20: studio slot1 teal, floor brown", T({ stu1 = TEAL, floortint = BROWN }) },
    { "sun20: studio slot0+1 teal, floor brown", T({ stu0 = TEAL, stu1 = TEAL, floortint = BROWN }) },
    { "sun20: studio slot0 brown, slot1 teal, floor brown", T({ stu0 = BROWN, stu1 = TEAL, floortint = BROWN }) },
    { "sun20: studio slot1 teal, floor brown, atmosphere hidden", T({ stu1 = TEAL, floortint = BROWN, noatm = true }) },
    { "sun100: studio slot1 teal, floor brown", T({ stu1 = TEAL, floortint = BROWN, dir = 1.0 }) },
    { "sun20: studio hidden, floor brown", T({ nostu = true, floortint = BROWN }) },
    { "done (all restored)", { nofog = true, ui = true } },
}
local STUDIO_STEPS = {
    { "studio set hidden, lights 100%", S({}) },
    { "studio set hidden, sun 20%", S({ dir = 0.2 }) },
    { "studio set hidden, sun 5%", S({ dir = 0.05 }) },
    { "studio set hidden, atmosphere hidden", S({ noatm = true }) },
    { "studio set hidden, atmosphere hidden, skylight 60%", S({ noatm = true, sky = 0.6 }) },
    { "studio set hidden, sun 5%, skylight 60%", S({ dir = 0.05, sky = 0.6 }) },
    { "studio set hidden, all lights 20% (redo of step 16)", S({ dir = 0.2, sky = 0.2, other = 0.2 }) },
    { "done (all restored)", { nofog = true, ui = true } },
}
local OLD_STEPS = {
    { "R2 baseline", { nofog = true } },
    { "R2 spheres", { nofog = true, nosph = true } },
    { "R2 spheres+fogplanes", { nofog = true, nosph = true, nofogplanes = true } },
    { "R2 spheres+fogplanes+floor", { nofog = true, nosph = true, nofogplanes = true, noflr = true } },
    { "R2 spheres+fogplanes+floor+studio", { nofog = true, nosph = true, nofogplanes = true, noflr = true, nostu = true } },
    { "R2 same, UI shown", { nofog = true, nosph = true, nofogplanes = true, noflr = true, nostu = true, ui = true } },
    { "R3 fogplanes", { nofog = true, nofogplanes = true } },
    { "R3 floor", { nofog = true, noflr = true } },
    { "R3 spheres+floor", { nofog = true, nosph = true, noflr = true } },
    { "L20 baseline", L20({ nofog = true }) },
    { "L20 spheres", L20({ nofog = true, nosph = true }) },
    { "L20 floor", L20({ nofog = true, noflr = true }) },
    { "L20 spheres+floor", L20({ nofog = true, nosph = true, noflr = true }) },
    { "L20 spheres+fogplanes+floor", L20({ nofog = true, nosph = true, nofogplanes = true, noflr = true }) },
    { "L20 spheres+fogplanes+floor+studio", L20({ nofog = true, nosph = true, nofogplanes = true, noflr = true, nostu = true }) },
    { "L20 same, UI shown", L20({ nofog = true, nosph = true, nofogplanes = true, noflr = true, nostu = true, ui = true }) },
    { "done (all restored)", { nofog = true, ui = true } },
}

local function lightclass(l)
    local c = full(l):match("^(%S+)")
    if c == "DirectionalLightComponent" then return "dir" elseif c == "SkyLightComponent" then return "sky" end
    return "other"
end

local function apply(step)
    local s = step[2]
    for _, l in ipairs(K.lights) do
        l.class = l.class or lightclass(l.obj)
        local want = l.orig * (s[l.class] or 1.0)
        if valid(l.obj) and not near(l.obj.Intensity, want) then l.obj:SetIntensity(want) end
    end
    for _, m in ipairs(K.mids) do
        local c
        if m.mesh == "SM_LiminalSphereBackground" then c = s.bg
        elseif m.mesh == "Plane" then c = s.floortint
        elseif m.mesh == "SM_FrontEndStudio_01" then c = s["stu" .. m.slot] end
        if valid(m.obj) then m.obj:SetVectorParameterValue(FName("Param"), c or m.orig) end
    end
    if not K.spheres then
        K.spheres = {}
        for _, a in ipairs(live(FindAllOf("StaticMeshActor"))) do
            local comp = ok(function() return a.StaticMeshComponent end)
            local mesh = valid(comp) and ok(function() return comp.StaticMesh end)
            if valid(mesh) and short(mesh) == "SM_LiminalSphereBackground" then K.spheres[#K.spheres + 1] = a end
        end
    end
    for _, a in ipairs(K.spheres) do
        local h = s.nosph == true
        if valid(a) and ok(function() return a.bHidden end) ~= h then a:SetActorHiddenInGame(h) end
    end
    if not K.floor then
        K.floor = {}
        for _, a in ipairs(live(FindAllOf("StaticMeshActor"))) do
            local comp = ok(function() return a.StaticMeshComponent end)
            local mesh = valid(comp) and ok(function() return comp.StaticMesh end)
            if valid(mesh) and short(mesh) == "Plane" then K.floor[#K.floor + 1] = a end
        end
    end
    for _, a in ipairs(K.floor) do
        local h = s.noflr == true
        if valid(a) and ok(function() return a.bHidden end) ~= h then a:SetActorHiddenInGame(h) end
    end
    if not K.studio then
        K.studio = {}
        for _, a in ipairs(live(FindAllOf("StaticMeshActor"))) do
            local comp = ok(function() return a.StaticMeshComponent end)
            local mesh = valid(comp) and ok(function() return comp.StaticMesh end)
            if valid(mesh) and short(mesh) == "SM_FrontEndStudio_01" then K.studio[#K.studio + 1] = a end
        end
    end
    if not K.studioDumped then
        K.studioDumped = true
        local f = io.open("C:/Users/admin/src/swgr-re/darkmode/studio_material.txt", "w")
        for _, a in ipairs(K.studio) do
            local comp = ok(function() return a.StaticMeshComponent end)
            local n = ok(function() return comp:GetNumMaterials() end) or 1
            for i = 0, n - 1 do
                local m = ok(function() return comp:GetMaterial(i) end)
                f:write(short(a), " slot ", i, ": ", full(m), "\n")
                local p = m
                for _ = 1, 4 do
                    ok(function() p.VectorParameterValues:ForEach(function(_, it)
                        local e = it:get(); local c = e.ParameterValue
                        f:write(string.format("   vec %s = %.3f %.3f %.3f %.3f\n", e.ParameterInfo.Name:ToString(), c.R, c.G, c.B, c.A)) end) end)
                    ok(function() p.ScalarParameterValues:ForEach(function(_, it)
                        local e = it:get(); f:write(string.format("   scalar %s = %.3f\n", e.ParameterInfo.Name:ToString(), e.ParameterValue)) end) end)
                    ok(function() p.TextureParameterValues:ForEach(function(_, it)
                        local e = it:get(); f:write("   tex ", e.ParameterInfo.Name:ToString(), " = ", full(e.ParameterValue), "\n") end) end)
                    p = ok(function() return p.Parent end)
                    if not valid(p) then break end
                    f:write("   parent ", full(p), "\n")
                end
            end
        end
        f:close()
    end
    for _, a in ipairs(K.studio) do
        local h = s.nostu == true
        if valid(a) and ok(function() return a.bHidden end) ~= h then a:SetActorHiddenInGame(h) end
    end
    for _, a in ipairs(K.fogplanes) do
        local h = s.nofogplanes == true
        if valid(a) and ok(function() return a.bHidden end) ~= h then a:SetActorHiddenInGame(h) end
    end
    K.atm = K.atm or live(FindAllOf("SkyAtmosphereComponent"))
    K.fog = K.fog or live(FindAllOf("ExponentialHeightFogComponent"))
    for _, c in ipairs(K.atm) do if ok(function() return c:IsVisible() end) ~= not s.noatm then c:SetVisibility(not s.noatm, false) end end
    for _, c in ipairs(K.fog) do
        if ok(function() return c:IsVisible() end) ~= not s.nofog then c:SetVisibility(not s.nofog, false) end
        local key = "fogstart:" .. full(c)
        if O[key] == nil then O[key] = c.StartDistance end
        local want = s.fogstart or O[key]
        if not near(c.StartDistance, want) then c:SetStartDistance(want) end
    end
    local o = s.ui and 1.0 or 0.0
    for _, w in ipairs(live(FindAllOf("UserWidget"))) do
        if ok(function() return w:IsInViewport() end) and ok(function() return w.RenderOpacity end) ~= o then w:SetRenderOpacity(o) end
    end
end

function M.tick(ctx)
    if ctx.reloaded then ctx.reloaded = false; ctx.state = { wait = 0, t = 0, i = 0 }; K = nil end
    local st = ctx.state
    if st.finished then return end
    if st.i == 0 then
        local mm = FindFirstOf("WBP_FE_MainMenu_C")
        if not valid(mm) or not ok(function() return mm:IsInViewport() end) then return end
        st.wait = st.wait + 1
        if st.wait < 10 then return end   -- let the menu settle 5 s
        discover()
        log(string.format("discovered %d lights, %d backdrop materials, %d fog planes", #K.lights, #K.mids, #K.fogplanes))
        st.i, st.t = 1, 0
        log("step 1: " .. STEPS[1][1])
    end
    local s, e = pcall(apply, STEPS[st.i])
    if not s and not st.err then st.err = true; log("apply error: " .. tostring(e)) end
    st.t = st.t + 1
    if st.t < TICKS_PER_STEP then return end
    st.t = 0
    st.i = st.i + 1
    if not STEPS[st.i] then st.finished = true; return end
    log("step " .. st.i .. ": " .. STEPS[st.i][1])
end

return M
-- run 1794963226
-- run 1794963343
-- run 1794963445
-- run 1794963622
-- run 1794963727
-- run 1794963841
-- run 1794964003
-- run 1794964651
