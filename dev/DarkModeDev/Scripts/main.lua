-- Dev loader: re-reads live.lua when it changes (checked every 30 frames) and calls its tick() every frame.
local LIVE = "C:/Users/admin/src/swgr-darkmode/dev/live.lua"  -- absolute path to the hot-reloaded logic file
local ctx = { state = {}, dev = true }
local src, mod, frame = nil, nil, 0

local function check_reload()
    local f = io.open(LIVE, "r")
    if not f then return end
    local s = f:read("*a"); f:close()
    if s == src then return end
    src = s
    local chunk, err = load(s, "live.lua")
    if not chunk then print("[DarkModeDev] compile error: " .. tostring(err) .. "\n"); mod = nil; return end
    local ok, m = pcall(chunk)
    if ok then mod = m; ctx.reloaded = true; print("[DarkModeDev] reloaded\n")
    else print("[DarkModeDev] load error: " .. tostring(m) .. "\n"); mod = nil end
end

local function step()
    frame = frame + 1
    if frame % 30 == 1 then check_reload() end
    if mod and mod.tick then
        local ok, err = pcall(mod.tick, ctx)
        if not ok and err ~= ctx.lastErr then ctx.lastErr = err; print("[DarkModeDev] tick error: " .. tostring(err) .. "\n") end
    end
end

if type(LoopInGameThreadAfterFrames) == "function" then
    LoopInGameThreadAfterFrames(1, step)
    print("[DarkModeDev] dev loader started (per frame)\n")
else
    LoopInGameThreadWithDelay(16, step)
    print("[DarkModeDev] dev loader started (16 ms timer)\n")
end
