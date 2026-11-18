-- DarkMode for STAR WARS Galactic Racer (UE4SS Lua mod)
--
-- Front-end scene: the menus sit in front of a white "photo studio" set in L_FrontEnd.
-- Instead of hiding it (which leaves holes), we tint its materials dark:
--   SM_FrontEndStudio_01 slot 1 (unlit cyclorama wall)  -> dark teal
--   SM_FrontEndStudio_01 slot 0 (lit floor)             -> dark brown
--   SM_LiminalSphereBackground (unlit cream spheres)    -> hidden
--   BP_FogPlane_VFX_C (white haze cards)                -> hidden
--   DirectionalLight in the lighting rig                -> 20% (only lights the floor/sand)
-- All of these materials expose a single vector parameter named "Param" (base color).
--
-- Everything is idempotent and re-applied once per second while the front end is loaded,
-- so level reloads and the game resetting things are handled without hooks.
--
-- UI widgets are handled by ui.lua (rule engine over reusable components; see that file).

local CONFIG = {
    wall = { R = 0.020, G = 0.034, B = 0.036, A = 1.0 },   -- linear color
    floor = { R = 0.030, G = 0.019, B = 0.011, A = 1.0 },
    sun_scale = 0.2,
    hide_spheres = true,
    hide_fog_planes = true,
    ui = true,              -- recolor UI widgets (ui.lua)
}

local function ok(f, ...) local s, r = pcall(f, ...); if s then return r end end
local function valid(o) return o ~= nil and ok(function() return o:IsValid() end) end
local function full(o) return ok(function() return o:GetFullName() end) or "" end
local function short(o) return ok(function() return o:GetFName():ToString() end) or "" end
local function log(s) print("[DarkMode] " .. s .. "\n") end
local function live(list)
    local r = {}
    for _, o in ipairs(list or {}) do
        if valid(o) and not full(o):find("Default__", 1, true) then r[#r + 1] = o end
    end
    return r
end

local PARAM = nil              -- FName("Param"), created lazily on the game thread
local scene = nil              -- cached objects for the currently loaded front-end world
local sun_orig = {}            -- original sun intensity per component full name

local function in_front_end()
    local pc = FindFirstOf("PlayerController")
    local w = valid(pc) and ok(function() return pc:GetWorld() end)
    return valid(w) and full(w):find("/L_FrontEnd.", 1, true) ~= nil
end

local function mid_for(comp, slot)
    local m = ok(function() return comp:GetMaterial(slot) end)
    if not valid(m) then return nil end
    if full(m):find("MaterialInstanceDynamic", 1, true) then return m end
    return ok(function() return comp:CreateDynamicMaterialInstance(slot, m, FName("None")) end)
end

local function discover()
    scene = { tints = {}, hide = {}, suns = {} }
    for _, a in ipairs(live(FindAllOf("StaticMeshActor"))) do
        local comp = ok(function() return a.StaticMeshComponent end)
        local mesh = valid(comp) and ok(function() return comp.StaticMesh end)
        local name = valid(mesh) and short(mesh) or ""
        if name == "SM_FrontEndStudio_01" then
            local wall, floor = mid_for(comp, 1), mid_for(comp, 0)
            if valid(wall) then scene.tints[#scene.tints + 1] = { mid = wall, color = CONFIG.wall } end
            if valid(floor) then scene.tints[#scene.tints + 1] = { mid = floor, color = CONFIG.floor } end
        elseif name == "SM_LiminalSphereBackground" and CONFIG.hide_spheres then
            scene.hide[#scene.hide + 1] = a
        end
    end
    if CONFIG.hide_fog_planes then
        for _, a in ipairs(live(FindAllOf("BP_FogPlane_VFX_C"))) do scene.hide[#scene.hide + 1] = a end
    end
    for _, l in ipairs(live(FindAllOf("DirectionalLightComponent"))) do
        local key = full(l)
        sun_orig[key] = sun_orig[key] or l.Intensity
        scene.suns[#scene.suns + 1] = { obj = l, want = sun_orig[key] * CONFIG.sun_scale }
    end
    log(string.format("front end: %d tints, %d hidden actors, %d suns", #scene.tints, #scene.hide, #scene.suns))
end

local function stale()
    if not scene then return true end
    for _, t in ipairs(scene.tints) do if not valid(t.mid) then return true end end
    return #scene.tints == 0
end

local function apply_scene()
    PARAM = PARAM or FName("Param")
    if stale() then discover() end
    for _, t in ipairs(scene.tints) do
        if valid(t.mid) then t.mid:SetVectorParameterValue(PARAM, t.color) end
    end
    for _, a in ipairs(scene.hide) do
        if valid(a) and ok(function() return a.bHidden end) == false then a:SetActorHiddenInGame(true) end
    end
    for _, s in ipairs(scene.suns) do
        if valid(s.obj) and math.abs(s.obj.Intensity - s.want) > 1e-3 then s.obj:SetIntensity(s.want) end
    end
end

LoopInGameThreadWithDelay(1000, function()
    if in_front_end() then
        local s, e = pcall(apply_scene)
        if not s then log("scene error: " .. tostring(e)); scene = nil end
    else
        scene = nil
    end
end)

if CONFIG.ui then
    local loaded, UI = pcall(require, "ui")
    if loaded and type(UI) == "table" and UI.tick then
        local uictx = { state = {}, reloaded = true, dev = false }
        local lastErr
        LoopInGameThreadWithDelay(500, function()
            local s, e = pcall(UI.tick, uictx)
            if not s and e ~= lastErr then lastErr = e; log("ui error: " .. tostring(e)) end
        end)
    else
        log("ui.lua failed to load: " .. tostring(UI))
    end
end

log("loaded")
