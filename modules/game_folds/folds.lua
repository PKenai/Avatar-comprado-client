dofile("/modules/gamelib/opcodes.lua")

infos = {
    vocation = 1,
    hotkey = "Ctrl+F",
    spells = {},
    currentEvents = {},
    maxNumberSpells = 16,
    buy = {}
}

function string.explode(str, sep, limit)
    local i, pos, tmp, t = 0, 1, "", {}
    
    for s, e in function() return string.find(str, sep, pos) end do
        tmp = str:sub(pos, s - 1):trim()
        table.insert(t, tmp)
        pos = e + 1

        i = i + 1
        if(limit ~= nil and i == limit) then
            break
        end
    end

    tmp = str:sub(pos):trim()
    table.insert(t, tmp)
    
    return t
end

function getPrimaryAndSecondary(msg)
    local strings = string.explode(msg, "#")

    if doMessageCheck(strings[3], ",") then
        local number = string.explode(strings[3], ",")

        return {tonumber(number[1]), tonumber(number[2])}
    else
        return {tonumber(strings[3])}
    end
end

function checkIsFoldMsg(msg)
    local containsM = doMessageCheck(msg, "#m#")
    local containsV = doMessageCheck(msg, "#v#")
    local containsJ = doMessageCheck(msg, "#j#")
    local Ms = {}

    if containsM or containsV or containsJ then
        local strings = string.explode(msg, ";")

        for x = 1, #strings do
            if doMessageCheck(strings[x], "#m#") then
                local a = getPrimaryAndSecondary(strings[x])
                infos.spells[a[1]] = a[2]
                table.insert(Ms, a[1])
            
            elseif doMessageCheck(strings[x], "#v#") then
                local vocationId = getPrimaryAndSecondary(strings[x])[1]

                if vocationId > 0 and vocationId < 5 then
                    infos.vocation = vocationId
                end

            elseif doMessageCheck(strings[x], "#j#") then
                local a = getPrimaryAndSecondary(strings[x])
                infos.buy[a[1]] = true
            end
        end

        if containsV then
            configureFolds(infos.vocation)
        end

        if containsM then
            refreshCDs(Ms)
        end

        if containsJ then
            checkBuys()
        end

        return true
    end

    return false
end

function doRefleshClient()
    local protocolGame = g_game.getProtocolGame()

    if protocolGame then
        protocolGame:sendExtendedOpcode(2) --manda pro server, mandar todas spells
		protocolGame:sendExtendedOpcode(40)
    end
end


function refreshCDs(CDs)
    local level = g_game.getLocalPlayer():getLevel()

    for x = 1, #CDs do
        local a, currentLevel = CDs[x], 0

        if spellInfos[infos.vocation][a] then
            currentLevel = spellInfos[infos.vocation][a].level
        end

        if level >= currentLevel then
            local delay = infos.spells[a]
            local progress = miniWindow:getChildById("p"..a)

            if progress then
                cancelEventFold(a)
                progress:setColor("#8892a4")

                if delay == 0 then
                    progress:setPercent(100)
                    progress:setText()
                
                elseif delay > 0 then
                    progress:setPercent(0)
                    progress:setText(delay)

                    for y = 1, delay do
                        local event = scheduleEvent(function()
                            if y < delay then
                                progress:setText(delay-y)
                                infos.spells[a] = delay-y
                            else
                                progress:setText()
                                progress:setPercent(100)
                                infos.spells[a] = 0    
                            end
                        end, 1000*y)

                        table.insert(infos.currentEvents[a], event)
                    end

                elseif delay < 0 then
                    progress:setPercent(0)
                end
            end
        end
    end
end

function checkBuys()
    local playerLevel = g_game.getLocalPlayer():getLevel()

    for x = 12, #spellInfos[infos.vocation] do
        local current = spellInfos[infos.vocation][x]
        local progress = miniWindow:getChildById("p"..x)

        if not infos.buy[x] then
            progress:setText("NPC")
            progress:setColor("#8892a4")
            progress:setPercent(0)
        else
            if progress:getText() == "NPC" and infos.spells[x] == 0 then
                if playerLevel >= current.level then
                    progress:setText()
                    progress:setPercent(100)
                else
                    progress:setText("L"..current.level)            progress:setColor("#a855f7")
        end
            end
        end
    end
end

function refreshLevel()
    local level = g_game.getLocalPlayer():getLevel()

    for x = 1, #spellInfos[infos.vocation] do
        local progress = miniWindow:getChildById("p"..x)

        if level >= spellInfos[infos.vocation][x].level then
            if infos.spells[x] == 0 then
                progress:setText()
                progress:setPercent(100)
            end
        else
            progress:setText("L"..spellInfos[infos.vocation][x].level)
            progress:setColor("#a855f7")
            progress:setPercent(0)
        end
    end

    checkBuys()
end

function cancelEventFold(id)
    if infos.currentEvents[id] then
        if #infos.currentEvents[id] > 0 then
            for x = 1, #infos.currentEvents[id] do
                infos.currentEvents[id][x]:cancel()
            end
        end
    end

    infos.currentEvents[id] = {}
end

function configureFolds(voc)
    infos.buy = {}
    modules.game_healthinfo.setImageAvatar(voc)
    for x = 1, #spellInfos[voc] do
        cancelEventFold(x)

        local current = miniWindow:getChildById("m"..x)
        local progress = miniWindow:getChildById("p"..x)
        local levelFold = spellInfos[voc][x].level
		
		progress.info = spellInfos[voc][x].name..", lv. "..levelFold
        current:setImageSource(images[voc]..x)		
        progress:setTooltip(progress.info)
        progress.name = spellInfos[voc][x].name
        progress.slotIndex = x

        progress.onClick = function(self)
            if self.name == "Water Heal" and G.healTargetName and #G.healTargetName > 0 then
                local proto = g_game.getProtocolGame()
                if proto then
                    proto:sendExtendedOpcode(210, G.healTargetName)
                end
            end
            g_game.talk(self.name)
        end
        g_mouse.bindPress(progress, function() createMenu(progress) end, MouseRightButton)
    end
	tooltipHotkey()
    -- Re-apply Water Heal target tooltip (tooltipHotkey overwrites it)
    updateHealTargetTooltip()
    refreshLevel()
end

function toggle()
    if not miniWindow:isVisible() then
        doOpen()
    else
        doClose()
    end
end

function doOpen()
    if foldsButton then foldsButton:setOn(true) end
    miniWindow:show()
end

function doClose()
    if foldsButton then foldsButton:setOn(false) end
    miniWindow:hide()
end

function init()
    miniWindow = g_ui.loadUI('folds', modules.game_interface.getRootPanel())
    -- miniWindow:disableResize()

    -- Carrega o nome salvo do target da Water Heal
    G.healTargetName = g_settings.get('waterHealTarget') or nil
    if G.healTargetName and #G.healTargetName == 0 then
        G.healTargetName = nil
    end

    connect(g_game, {onGameStart = doRefleshClient})
    connect(LocalPlayer, {onLevelChange = refreshLevel})

    g_keyboard.bindKeyDown(infos.hotkey, toggle)
	local bendNames = tr('Bend List (Ctrl F)')
    -- foldsButton = modules.client_topmenu.addRightGameToggleButton('foldsButton', bendNames, '/images/topbuttons/cooldowns', toggle)
    -- miniWindow:setup()
end

function terminate()
    miniWindow:destroy()
    if foldsButton then foldsButton:destroy() end
    g_keyboard.unbindKeyDown(infos.hotkey)
    disconnect(g_game, {onGameStart = doRefleshClient})
    disconnect(LocalPlayer, {onLevelChange = refreshLevel})
end

function createMenu(spell)
    local menu   = g_ui.createWidget('PopupMenu')
    local hotkey = modules.game_hotkeys

    menu:addOption(tr('Add Hotkey'), function() hotkey.addSpell(spell) end)

    local spellHotkey = hotkey.checkSpell(spell.name)
    if spellHotkey then
        menu:addOption(tr('Remove Hotkey'), function()
            spell:setTooltip(spell.info)
            hotkey.removeSpell(spellHotkey)
        end)
    end

    -- Opcao extra para Water Heal: definir o alvo
    if spell.name == "Water Heal" then
        menu:addOption(tr('Set Heal Target'), function()
            local cur = G.healTargetName or ''
            displayTextInputBox(
                'Water Heal - Who to heal?',
                'Player name' .. (cur ~= '' and ' (current: ' .. cur .. ')' or ''),
                function(inputText)
                    local name = inputText:trim()
                    if name and #name > 0 then
                        G.healTargetName = name
                        g_settings.set('waterHealTarget', name)
                        g_settings.save()
                    else
                        G.healTargetName = nil
                        g_settings.set('waterHealTarget', '')
                        g_settings.save()
                    end
                    updateHealTargetTooltip()
                end,
                function() end
            )
        end)
    end

    menu:display()
end

function tooltipHotkey()
  for x = 1, #spellInfos[infos.vocation] do
    local progress = miniWindow:getChildById("p"..x)
	local hotkey = modules.game_hotkeys.checkSpell(progress.name)
	if ( hotkey ) then
	  progress:setTooltip(progress.info.." - Hotkey: "..hotkey)
	else
	  progress:setTooltip(progress.info)
	end
  end
end

function updateHealTargetTooltip()
    for x = 1, 24 do
        local progress = miniWindow:getChildById("p"..x)
        if progress and progress.name == "Water Heal" then
            if G.healTargetName and #G.healTargetName > 0 then
                progress:setTooltip(progress.info .. ' -> ' .. G.healTargetName)
            else
                progress:setTooltip(progress.info)
            end
            break
        end
    end
end