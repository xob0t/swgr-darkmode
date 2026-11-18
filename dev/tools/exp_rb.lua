-- Experiment: dump live RB_Hover retainer boxes (effect material + params) and the card's top-level layout.
local f = io.open("C:/Users/admin/src/swgr-darkmode/dev/out/rb.txt", "w")
local n = 0
for _, w in ipairs(FindAllOf("RetainerBox") or {}) do
    if valid(w) and short(w) == "RB_Hover" and full(w):find("/Engine/Transient", 1, true) and n < 2 then
        n = n + 1
        f:write(full(w), "\n")
        f:write("  retain=", tostring(ok(function() return w.bRetainRender end)), " phase=", tostring(ok(function() return w.Phase end)),
            " phases=", tostring(ok(function() return w.PhaseCount end)), "\n")
        local m = ok(function() return w:GetEffectMaterial() end) or ok(function() return w.EffectMaterial end)
        f:write("  effect=", valid(m) and full(m) or "none", "\n")
        local p = m
        for _ = 1, 4 do
            if not valid(p) then break end
            ok(function() p.VectorParameterValues:ForEach(function(_, it)
                local e = it:get(); f:write("   vec ", e.ParameterInfo.Name:ToString(), " = ", fmt(e.ParameterValue), "\n") end) end)
            ok(function() p.ScalarParameterValues:ForEach(function(_, it)
                local e = it:get(); f:write(string.format("   scalar %s = %.3f\n", e.ParameterInfo.Name:ToString(), e.ParameterValue)) end) end)
            ok(function() p.TextureParameterValues:ForEach(function(_, it)
                local e = it:get(); f:write("   tex ", e.ParameterInfo.Name:ToString(), " = ", full(e.ParameterValue), "\n") end) end)
            p = ok(function() return p.Parent end)
            if valid(p) then f:write("  parent ", full(p), "\n") end
        end
        -- the owning button widget and its direct visual layers
        local outer = ok(function() return w:GetOuter() end)
        local owner = valid(outer) and ok(function() return outer:GetOuter() end)
        f:write("  owner=", valid(owner) and full(owner) or "?", "\n")
    end
end
f:close()
return n
