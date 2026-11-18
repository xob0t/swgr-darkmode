-- DarkMode for STAR WARS Galactic Racer (UE4SS Lua mod)
--
-- Backdrops: menus with a 3D scene sit in front of a white "photo studio" set. It exists in the
-- front end (L_FrontEnd) and, as a copy, in the planet hubs (L_<Planet>_PADDOCK) behind vehicle select.
-- Instead of hiding it (which leaves holes or shows the level behind it), we tint its materials dark:
--   SM_FrontEndStudio_01 slot 1 (unlit cyclorama wall)  -> dark teal
--   SM_FrontEndStudio_01 slot 0 (lit floor)             -> dark brown
--   SM_LiminalSphereBackground (unlit cream spheres)    -> dark teal (the backdrop in the hubs)
--   BP_FogPlane_VFX_C (white haze cards)                -> hidden: all in the front end, only the ones
--                                                         near the spheres in the hubs (Loadout backdrop)
-- Front end only (the hubs are playable, so their lighting stays as it is):
--   DirectionalLight in the lighting rig                -> 20% (only lights the floor/sand)
-- All of these materials expose a single vector parameter named "Param" (base color).
--
-- The set is found once per level (FindAllOf, ~15 ms) and re-tinted once per second, so the game
-- resetting things is handled without hooks.
--
-- UI widgets are handled by ui.lua (rule engine over reusable components; see that file).

local VERSION = "dev"      -- set from the git tag by the release workflow

local CONFIG = {
    wall = { R = 0.020, G = 0.034, B = 0.036, A = 1.0 },   -- linear color
    floor = { R = 0.030, G = 0.019, B = 0.011, A = 1.0 },
    sun_scale = 0.2,        -- front end only
    hide_fog_planes = true, -- all in the front end, near the backdrop in the hubs
    fog_radius = 20000,     -- hubs: hide haze cards within this distance (cm) of a backdrop sphere
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
local scene = nil              -- cached objects for the current world
local sun_orig = {}            -- original sun intensity per component full name

-- FindFirstOf scans every object (~10 ms here), so keep the controller and world and only look
-- them up again once they are gone (level change)
local pc_cached, world_cached, world_name = nil, nil, ""
local function current_world()
    if not valid(pc_cached) then pc_cached = FindFirstOf("PlayerController"); world_cached = nil end
    if not valid(world_cached) then
        world_cached = valid(pc_cached) and ok(function() return pc_cached:GetWorld() end) or nil
        world_name = valid(world_cached) and full(world_cached) or ""
    end
    return world_cached, world_name
end

local function mid_for(comp, slot)
    local m = ok(function() return comp:GetMaterial(slot) end)
    if not valid(m) then return nil end
    if full(m):find("MaterialInstanceDynamic", 1, true) then return m end
    return ok(function() return comp:CreateDynamicMaterialInstance(slot, m, FName("None")) end)
end

local function discover(world, name)
    local fe = name:find("/L_FrontEnd.", 1, true) ~= nil
    scene = { world = ok(function() return world:GetAddress() end), tints = {}, hide = {}, suns = {} }
    local function tint(comp, slot, color)
        local m = mid_for(comp, slot)
        if valid(m) then scene.tints[#scene.tints + 1] = { mid = m, color = color } end
    end
    local spheres = {}
    -- includes subclasses (the hubs use BP_GfnStaticMeshActor_C)
    for _, a in ipairs(live(FindAllOf("StaticMeshActor"))) do
        local comp = ok(function() return a.StaticMeshComponent end)
        local mesh = valid(comp) and ok(function() return comp.StaticMesh end)
        local mname = valid(mesh) and short(mesh) or ""
        if mname == "SM_FrontEndStudio_01" then
            tint(comp, 1, CONFIG.wall)
            tint(comp, 0, CONFIG.floor)
        elseif mname == "SM_LiminalSphereBackground" then
            tint(comp, 0, CONFIG.wall)
            local l = ok(function() return a:K2_GetActorLocation() end)
            if l then spheres[#spheres + 1] = { X = l.X, Y = l.Y, Z = l.Z } end
        end
    end
    if CONFIG.hide_fog_planes and (fe or #spheres > 0) then
        local r2 = CONFIG.fog_radius * CONFIG.fog_radius
        for _, a in ipairs(live(FindAllOf("BP_FogPlane_VFX_C"))) do
            local near = fe
            if not near then
                local l = ok(function() return a:K2_GetActorLocation() end)
                for _, c in ipairs(spheres) do
                    if l and (l.X - c.X) ^ 2 + (l.Y - c.Y) ^ 2 + (l.Z - c.Z) ^ 2 < r2 then near = true; break end
                end
            end
            if near then scene.hide[#scene.hide + 1] = a end
        end
    end
    if fe then
        for _, l in ipairs(live(FindAllOf("DirectionalLightComponent"))) do
            local key = full(l)
            sun_orig[key] = sun_orig[key] or l.Intensity
            scene.suns[#scene.suns + 1] = { obj = l, want = sun_orig[key] * CONFIG.sun_scale }
        end
    end
    log(string.format("%s: %d tints, %d hidden actors, %d suns", name:match("([%w_]+)$") or "?",
        #scene.tints, #scene.hide, #scene.suns))
end

-- rediscover on a level change, or when something we tinted is gone (never just because a level has
-- no studio set: race levels would pay for a FindAllOf every second)
local function stale(world)
    if not scene or scene.world ~= ok(function() return world:GetAddress() end) then return true end
    for _, t in ipairs(scene.tints) do if not valid(t.mid) then return true end end
    return false
end

local function apply_scene()
    PARAM = PARAM or FName("Param")
    local world, name = current_world()
    if not valid(world) then scene = nil; return end
    if stale(world) then discover(world, name) end
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
    local s, e = pcall(apply_scene)
    if not s then log("scene error: " .. tostring(e)); scene = nil end
end)

if CONFIG.ui then
    local loaded, UI = pcall(require, "ui")
    if loaded and type(UI) == "table" and UI.tick then
        local uictx = { state = {}, reloaded = true, dev = false }
        local lastErr
        local function step()
            local s, e = pcall(UI.tick, uictx)
            if not s and e ~= lastErr then lastErr = e; log("ui error: " .. tostring(e)) end
        end
        -- ui.lua time-slices its own work (about 2 ms per frame at most), so it wants a per-frame tick
        if type(LoopInGameThreadAfterFrames) == "function" then
            LoopInGameThreadAfterFrames(1, step)
        else
            LoopInGameThreadWithDelay(16, step)
        end
    else
        log("ui.lua failed to load: " .. tostring(UI))
    end
end

log("loaded " .. VERSION)
