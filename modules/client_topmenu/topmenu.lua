-- private variables
local topMenu
local leftButtonsPanel
local rightButtonsPanel
local leftGameButtonsPanel
local rightGameButtonsPanel
local fpsEvent
local fpsText = ''

-- drawer variables
local idleTimer = nil
local isHidden = false
local isAnimating = false
local IDLE_TIMEOUT = 15000
local ANIM_DURATION = 300
local ANIM_STEPS = 20
local originalMarginTop = 0
local dropButton = nil

-- private functions
local function addButton(id, description, icon, callback, panel, toggle, front)
  local class
  if toggle then
    class = 'TopToggleButton'
  else
    class = 'TopButton'
  end

  local button = panel:getChildById(id)
  if not button then
    button = g_ui.createWidget(class)
    if front then
      panel:insertChild(1, button)
    else
      panel:addChild(button)
    end
  end
  button:setId(id)
  button:setTooltip(description)
  button:setIcon(resolvepath(icon, 3))
  button.onMouseRelease = function(widget, mousePos, mouseButton)
    if widget:containsPoint(mousePos) and mouseButton ~= MouseMiddleButton then
      callback()
      return true
    end
  end
  return button
end

-- drawer functions
local function positionDropButton()
  if not dropButton or not topMenu then return end
  local root = g_ui.getRootWidget()
  local rootWidth = root:getWidth()
  local btnWidth = dropButton:getWidth()
  dropButton:setX(math.floor((rootWidth - btnWidth) / 2))
  dropButton:setY(0)
end

local function resetIdleTimer()
  if idleTimer then
    removeEvent(idleTimer)
    idleTimer = nil
  end
  if not isHidden and not isAnimating then
    idleTimer = scheduleEvent(function()
      if isHidden or isAnimating then return end
      isAnimating = true
      local height = topMenu:getHeight()
      if dropButton then
        positionDropButton()
        dropButton:show()
        dropButton:setOpacity(0)
        g_effects.fadeIn(dropButton, 200)
      end
      for i = 1, ANIM_STEPS do
        scheduleEvent(function()
          if topMenu and isAnimating then
            local progress = i / ANIM_STEPS
            local eased = 1 - (1 - progress) * (1 - progress)
            local newMargin = -math.floor(height * eased)
            topMenu:setMarginTop(newMargin)
            if i == ANIM_STEPS then
              topMenu:setMarginTop(-height)
              isHidden = true
              isAnimating = false
            end
          end
        end, math.floor(i * ANIM_DURATION / ANIM_STEPS))
      end
    end, IDLE_TIMEOUT)
  end
end

local function slideDown()
  if isAnimating or not isHidden then return end
  isAnimating = true
  if dropButton then
    g_effects.fadeOut(dropButton, 150)
    scheduleEvent(function()
      if dropButton then dropButton:hide() end
    end, 160)
  end
  local startMargin = topMenu:getMarginTop()
  for i = 1, ANIM_STEPS do
    scheduleEvent(function()
      if topMenu and isAnimating then
        local progress = i / ANIM_STEPS
        local eased = progress * progress
        local newMargin = math.floor(startMargin + (originalMarginTop - startMargin) * eased)
        topMenu:setMarginTop(newMargin)
        if i == ANIM_STEPS then
          topMenu:setMarginTop(originalMarginTop)
          isHidden = false
          isAnimating = false
          resetIdleTimer()
        end
      end
    end, math.floor(i * ANIM_DURATION / ANIM_STEPS))
  end
end

function onTopMenuMouseMove(self, mousePos, mouseMoved)
  if not isHidden and not isAnimating then
    resetIdleTimer()
  end
end

function onDropClick()
  slideDown()
end

-- public functions
function init()
  connect(g_game, { onGameStart = online,
                    onGameEnd = offline,
                    onPingBack = updatePing })

  topMenu = g_ui.displayUI('topmenu')

  leftButtonsPanel = topMenu:getChildById('leftButtonsPanel')
  rightButtonsPanel = topMenu:getChildById('rightButtonsPanel')
  leftGameButtonsPanel = topMenu:getChildById('leftGameButtonsPanel')
  rightGameButtonsPanel = topMenu:getChildById('rightGameButtonsPanel')
  pingLabel = topMenu:getChildById('pingLabel')
  fpsLabel = topMenu:getChildById('fpsLabel')

  originalMarginTop = topMenu:getMarginTop()

  -- create drop button: parent it to root so it survives topMenu sliding up
  local root = g_ui.getRootWidget()
  dropButton = g_ui.createWidget('TopButton', root)
  if dropButton then
    dropButton:setId('dropButton')
    dropButton:setIcon(resolvepath('/data/images/topbuttons/drop.png', 3))
    dropButton:setTooltip('Mostrar barra superior')
    dropButton:setOpacity(0.7)
    dropButton:hide()
    positionDropButton()
    dropButton.onMouseRelease = function(widget, mousePos, mouseButton)
      if widget:containsPoint(mousePos) and mouseButton == MouseLeftButton then
        onDropClick()
        return true
      end
    end
    dropButton.onHoverChange = function(widget)
      if widget:isHovered() then
        widget:setOpacity(1.0)
      else
        widget:setOpacity(0.7)
      end
    end
  end

  updateFps()
  fpsEvent = cycleEvent(function() updateFps() end, 1000)

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  disconnect(g_game, { onGameStart = online,
                       onGameEnd = offline,
                       onPingBack = updatePing })

  if fpsEvent then
    removeEvent(fpsEvent)
    fpsEvent = nil
  end

  if idleTimer then
    removeEvent(idleTimer)
    idleTimer = nil
  end

  if dropButton then
    dropButton:destroy()
    dropButton = nil
  end

  topMenu:destroy()
end

function online()
  showGameButtons()
  g_game.enableFeature(GameClientPing)
  addEvent(function()
    fpsLabel:show()
    pingLabel:show()
    if isHidden then
      topMenu:setMarginTop(originalMarginTop)
      isHidden = false
      isAnimating = false
      if dropButton then dropButton:hide() end
    end
    resetIdleTimer()
  end)
end

function offline()
  hideGameButtons()
  pingLabel:hide()
  if idleTimer then
    removeEvent(idleTimer)
    idleTimer = nil
  end
  if isHidden then
    topMenu:setMarginTop(originalMarginTop)
    isHidden = false
    isAnimating = false
  end
  if dropButton then
    dropButton:hide()
  end
end

function updateFps(fps)
  fps = fps or g_app.getFps()
  if fps < 0 then fps = 0 end
  local text = 'FPS: ' .. fps
  if text ~= fpsText then
    fpsText = text
    fpsLabel:setText(text)
  end
end

function updatePing(ping)
  ping = math.ceil(ping/4)
  local text = 'PING: '
  local color
  if ( ping <= 70 ) then
    color = 'green'
  elseif ( ping <= 130 ) then
    color = 'yellow'
  else
    color = 'red'
  end
  text = text .. ping .. ' ms'

  pingLabel:setColor(color)
  pingLabel:setText(text)
  pingLabel:setVisible(ping >= 1)
end

function setPingVisible(enable)
  pingLabel:setVisible(enable)
end

function setFpsVisible(enable)
  fpsLabel:setVisible(enable)
end

function addLeftButton(id, description, icon, callback, front)
  return addButton(id, description, icon, callback, leftButtonsPanel, false, front)
end

function addLeftToggleButton(id, description, icon, callback, front)
  return addButton(id, description, icon, callback, leftButtonsPanel, true, front)
end

function addRightButton(id, description, icon, callback, front)
  return addButton(id, description, icon, callback, rightButtonsPanel, false, front)
end

function addRightToggleButton(id, description, icon, callback, front)
  return addButton(id, description, icon, callback, rightButtonsPanel, true, front)
end

function addLeftGameButton(id, description, icon, callback, front)
  return addButton(id, description, icon, callback, leftGameButtonsPanel, true, front)
end

function addLeftGameToggleButton(id, description, icon, callback, front)
  return addButton(id, description, icon, callback, leftGameButtonsPanel, true, front)
end

function addRightGameButton(id, description, icon, callback, front)
  return addButton(id, description, icon, callback, rightGameButtonsPanel, false, front)
end

function addRightGameToggleButton(id, description, icon, callback, front)
  return addButton(id, description, icon, callback, rightGameButtonsPanel, true, front)
end

function showGameButtons()
  leftGameButtonsPanel:show()
  rightGameButtonsPanel:show()
end

function hideGameButtons()
  leftGameButtonsPanel:hide()
  rightGameButtonsPanel:hide()
end

function getButton(id)
  return topMenu:recursiveGetChildById(id)
end

function getTopMenu()
  return topMenu
end
