local outfitScales = {
    ["fierce bear"] = 0.6,
    ["steel shell centipede"] = 0.6,
    ["wild wolf"] = 0.8,
    ["vacaceronte"] = 0.6,
    ["desert crocodile"] = 0.6,
    ["giant snail"] = 0.6,
    ["urso feroz"] = 0.6,
    ["centopeia carapaca de aco"] = 0.6,
    ["lobo selvagem"] = 0.8,
    ["crocodilo do deserto"] = 0.6,
    ["caracol gigante"] = 0.6,
}

function init()
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
        end
    end)
    if not ok then
    end
end

function setOutfitScaleByName(name, scale)
    if type(name) ~= "string" or type(scale) ~= "number" then return end
    outfitScales[name:lower()] = scale
end
