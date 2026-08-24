-- Outfit Scales Module
-- Define creature name -> scale factor mappings below.

local outfitScales = {
    ["urso feroz"] = 0.6,
}

function init()
    print("[OutfitScales] Module loaded. Scales:")
    for k, v in pairs(outfitScales) do print("[OutfitScales]   " .. k .. " = " .. v) end
    connect(Creature, {
        onAppear = onCreatureAppearScale,
    })
end

function terminate()
    disconnect(Creature, {
        onAppear = onCreatureAppearScale,
    })
end

function onCreatureAppearScale(creature)
    if not creature then return end
    local ok, err = pcall(function()
        local id = creature:getId()
        if not id or id == 0 then return end
        local name = creature:getName()
        if not name or name == "" then return end
        local scale = outfitScales[name:lower()]
        if scale then
            creature:setOutfitScale(scale)
            print("[OutfitScales] Applied scale " .. scale .. " to '" .. name .. "'")
        end
    end)
    if not ok then
        print("[OutfitScales] ERROR: " .. tostring(err))
    end
end

function setOutfitScaleByName(name, scale)
    if type(name) ~= "string" or type(scale) ~= "number" then return end
    outfitScales[name:lower()] = scale
end
