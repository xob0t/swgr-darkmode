-- Dev loader: re-reads live.lua whenever it changes and calls its tick() on the game thread.
local LIVE = "C:/Users/admin/src/swgr-darkmode/dev/live.lua"  -- absolute path to the hot-reloaded logic file
local ctx = { state = {} }
local src, mod = nil, nil
LoopInGameThreadWithDelay(500, function()
    local f = io.open(LIVE, "r")
    if f then
        local s = f:read("*a"); f:close()
        if s ~= src then
            src = s
            local chunk, err = load(s, "live.lua")
            if not chunk then print("[DarkModeDev] compile error: " .. tostring(err) .. "\n"); mod = nil
            else
                local ok, m = pcall(chunk)
                if ok then mod = m; ctx.reloaded = true; print("[DarkModeDev] reloaded\n")
                else print("[DarkModeDev] load error: " .. tostring(m) .. "\n"); mod = nil end
            end
        end
    end
    if mod and mod.tick then
        local ok, err = pcall(mod.tick, ctx)
        if not ok and err ~= ctx.lastErr then ctx.lastErr = err; print("[DarkModeDev] tick error: " .. tostring(err) .. "\n") end
    end
end)
print("[DarkModeDev] dev loader started\n")
