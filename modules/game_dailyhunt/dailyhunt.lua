local opcode = 166
local window = nil
local button = nil
local monsters = {}
local kills = {}
local killsRequired = 250
local rewards = {}

modules.game_dailyhunt = {}

function init()
  g_ui.importStyle('dailyhunt')
  connect(g_game, { onGameStart = online, onGameEnd = offline })
  if g_game.getLocalPlayer() then
    online()
  end
end

function terminate()
  pcall(function() ProtocolGame.unregisterExtendedOpcode(opcode) end)
  offline()
  disconnect(g_game, { onGameStart = online, onGameEnd = offline })
end

function online()
  local okW, errW = pcall(function() return g_ui.createWidget('DailyHuntWindow', rootWidget) end)
  if okW and errW then
    window = errW
    window:hide()
  end

  local okB, errB = pcall(function()
    return modules.client_topmenu.addRightGameToggleButton(
      'dailyHuntButton',
      tr('Daily Hunt'),
      '/images/topbuttons/dailyhunt',
      toggle,
      true
    )
  end)
  if okB and errB then
    button = errB
  end

  pcall(function()
    ProtocolGame.registerExtendedOpcode(opcode, function(protocol, op, buffer)
      receiveData(buffer)
    end)
  end)
end

function offline()
  monsters = {}
  kills = {}
  if window then
    window:destroy()
    window = nil
  end
  if button then
    button:destroy()
    button = nil
  end
end

function modules.game_dailyhunt.onEscape()
  if window and window:isVisible() then
    window:hide()
    if button then
      button:setOn(false)
    end
  end
end

function toggle()
  if not g_game.getLocalPlayer() or not window or not button then
    return
  end
  if button:isOn() then
    window:hide()
    button:setOn(false)
  else
    window:show()
    window:raise()
    window:focus()
    button:setOn(true)
    pcall(function()
      if g_game.getProtocolGame() then
        g_game.getProtocolGame():sendExtendedOpcode(opcode, "request")
      else
        g_game.talk("!dailyhunt")
      end
    end)
  end
end

function modules.game_dailyhunt.onClaimReward()
  if not g_game.getLocalPlayer() or not window then
    return
  end
  local claimBtn = window:getChildById('claimButton')
  if not claimBtn or claimBtn:getOpacity() < 0.9 then
    return
  end
  pcall(function()
    if g_game.getProtocolGame() then
      g_game.getProtocolGame():sendExtendedOpcode(opcode, "claim")
    end
  end)
end

function receiveData(buffer)
  if not window or not buffer or buffer == "" then
    return
  end

  local newMonsters = {}
  local newKills = {}
  local newOutfits = {}
  local newRewards = {}

  local parts = buffer:explode("|")
  for i, part in ipairs(parts) do
    local key, value = part:match("([^:]+):(.+)")
    if key then
      if key == "monsters" then
        local names = value:explode(",")
        for j, name in ipairs(names) do
          newMonsters[j] = name
        end
      elseif key == "kills" then
        local counts = value:explode(",")
        for j, count in ipairs(counts) do
          newKills[j] = tonumber(count) or 0
        end
      elseif key == "killsRequired" then
        killsRequired = tonumber(value) or 250
      elseif key == "outfits" then
        local list = value:explode(";")
        for j, str in ipairs(list) do
          local p = str:explode("_")
          newOutfits[j] = {
            type = tonumber(p[1]) or 0,
            head = tonumber(p[2]) or 0,
            body = tonumber(p[3]) or 0,
            legs = tonumber(p[4]) or 0,
            feet = tonumber(p[5]) or 0,
            addons = tonumber(p[6]) or 0,
            auxType = tonumber(p[7]) or 0,
          }
        end
      elseif key == "rewards" then
        local vals = value:explode(",")
        for j, v in ipairs(vals) do
          newRewards[j] = tonumber(v) or 0
        end
      end
    end
  end

  monsters = newMonsters
  kills = newKills
  rewards = newRewards

  local listPanel = window:getChildById('monsterList')
  if not listPanel then
    return
  end
  listPanel:destroyChildren()

  for i = 1, 5 do
    local name = monsters[i] or "Unknown"
    local count = kills[i] or 0
    local percent = math.min((count / killsRequired) * 100, 100)
    local complete = count >= killsRequired

    local ok, row = pcall(function() return g_ui.createWidget('DailyHuntRow', listPanel) end)
    if not ok or not row then
      break
    end

    local creature = row:getChildById('creatureIcon')
    if creature and newOutfits[i] then
      pcall(function() creature:setOutfit(newOutfits[i]) end)
    end

    local nameLabel = row:getChildById('monsterName')
    if nameLabel then
      nameLabel:setText(name)
      if complete then
        nameLabel:setColor('#33cc33')
      end
    end

    local countLabel = row:getChildById('killCount')
    if countLabel then
      countLabel:setText(count .. ' / ' .. killsRequired)
      if complete then
        countLabel:setColor('#33cc33')
      end
    end

    local prog = row:getChildById('progressBar')
    if prog then
      prog:setPercent(percent)
    end
  end

  local completed = 0
  for i = 1, 5 do
    if (kills[i] or 0) >= killsRequired then
      completed = completed + 1
    end
  end

  local claimBtn = window:getChildById('claimButton')
  if claimBtn then
    if completed >= 5 then
      window:setText('Daily Hunt - Complete!')
      if rewards[5] == 1 then
        claimBtn:setText('Reivindicado!')
        claimBtn:setOpacity(0.3)
      else
        claimBtn:setText('Resgatar 50%')
        claimBtn:setOpacity(1.0)
      end
    elseif completed >= 2 then
      window:setText('Daily Hunt - ' .. completed .. '/5')
      if rewards[2] == 1 then
        claimBtn:setText('Reivindicado!')
        claimBtn:setOpacity(0.3)
      else
        claimBtn:setText('Resgatar 10%')
        claimBtn:setOpacity(1.0)
      end
    else
      window:setText('Daily Hunt')
      claimBtn:setText(completed .. '/5 - Resgatar')
      claimBtn:setOpacity(0.3)
    end
  end
end
