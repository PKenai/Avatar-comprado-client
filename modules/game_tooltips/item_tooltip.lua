local CODE_TOOLTIPS = 105

local tooltipWindow = nil
local itemSprite = nil
local itemWeightLabel = nil
local labels = nil
local hoveredItem = nil
local player = nil
local protocolGame = nil
local showingVirtual = nil
local hoveredLinked = nil

local BASE_WIDTH = 170
local BASE_HEIGHT = 0

local tooltipWidth = 0
local tooltipWidthBase = BASE_WIDTH
local tooltipHeight = BASE_HEIGHT
local longestString = 0

local cachedItems = {}

local Colors = {
  Default = "#ffffff",
  ItemLevel = "#abface",
  Description = "#8080ff",
  Implicit = "#ffbb22",
  Attribute = "#2266ff",
  Mirrored = "#22ffbb"
}

function init()
  connect(UIItem, {onHoverChange = onHoverChange})
  connect(g_game, {onGameEnd = resetData})

  ProtocolGame.registerExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

  tooltipWindow = g_ui.displayUI("item_tooltip")
  tooltipWindow:hide()

  labels = tooltipWindow:getChildById("labels")
  itemWeightLabel = tooltipWindow:getChildById("itemWeightLabel")
  itemSprite = tooltipWindow:getChildById("itemSprite")
end

function terminate()
  disconnect(UIItem, {onHoverChange = onHoverChange})
  disconnect(g_game, {onGameEnd = resetData})

  ProtocolGame.unregisterExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

  if tooltipWindow then
    cachedItems = {}
    hoveredItem = nil
    player = nil
    protocolGame = nil
    showingVirtual = nil
    hoveredLinked = nil

    itemWeightLabel = nil
    itemSprite = nil
    labels = nil

    tooltipWindow:destroy()
    tooltipWindow = nil
  end
end

function onExtendedOpcode(protocol, code, buffer)
  local json_status, json_data =
    pcall(
    function()
      return json.decode(buffer)
    end
  )

  if not json_status then
    g_logger.error("Tooltips JSON error: " .. json_data)
    return
  end

  local action = json_data.action
  local data = json_data.data
  if not action or not data then
    return
  end
  if action == "new" then
    newTooltip(data)
  end
end

function newTooltip(data)
  local _itemUId = data.uid
  local _itemName = data.itemName
  local _itemDesc = data.desc
  local _itemId = data.clientId
  local _lookText = data.lookText
  local _weight = data.weight
  local _reqLvl = data.reqLvl or 0
  local _isStackable = data.stackable

  cachedItems[_itemUId] = {
    last = os.time(),
    name = _itemName,
    desc = _itemDesc,
    lookText = _lookText,
    weight = _weight,
    reqLvl = _reqLvl,
    stackable = _isStackable,
    itemId = _itemId
  }

  if hoveredLinked and _itemUId == hoveredLinked.uid then
    hoveredLinked.cached = true
    for key, value in pairs(cachedItems[_itemUId]) do
      hoveredLinked[key] = value
    end
    buildItemTooltip(hoveredLinked:getLinkedTooltip())
    return
  end

  if hoveredItem and _itemId == hoveredItem:getId() then
    hoveredItem.uid = _itemUId
    hoveredItem.name = _itemName
    showTooltip(_itemUId)
  end
end

function resetData()
  cachedItems = {}
  hoveredItem = nil
  player = nil
  protocolGame = nil
  showingVirtual = nil
  hoveredLinked = nil
  tooltipWindow:hide()
end

function onHoverChange(widget, hovered)
  if not protocolGame then
    protocolGame = g_game.getProtocolGame()
  end

  if widget.getLinkedTooltip then
    hoveredLinked = widget
    if not widget.cached then
      if protocolGame then
        protocolGame:sendExtendedOpcode(CODE_TOOLTIPS, json.encode({widget.uid}))
      end
    else
      if hovered then
        showingVirtual = widget:getLinkedTooltip()
        buildItemTooltip(widget:getLinkedTooltip())
      else
        tooltipWindow:hide()
        showingVirtual = nil
      end
    end
    return
  end

  local item = widget:getItem()
  if item and widget.getItemTooltip then
    if hovered then
      buildItemTooltip(widget:getItemTooltip())
    else
      tooltipWindow:hide()
    end
    return
  end
  if not item or widget:getId() == "containerItemWidget" or widget:isVirtual() then
    return
  end

  if player == nil then
    player = g_game.getLocalPlayer()
  end

  if hovered then
    hoveredItem = item
    if protocolGame then
      local pos = item:getPosition()
      if pos and pos.x and pos.x < 65000 then
        print('[TOOLTIPS] Sending hover request pos=' .. pos.x .. ',' .. pos.y .. ',' .. pos.z)
        protocolGame:sendExtendedOpcode(CODE_TOOLTIPS, json.encode({pos.x, pos.y, pos.z, item:getStackPos()}))
      else
        local widgetId = widget:getId()
        local slotNum = tonumber(string.match(widgetId or "", 'slot(%d+)'))
        if slotNum then
          print('[TOOLTIPS] Sending inventory slot request slot=' .. slotNum)
          protocolGame:sendExtendedOpcode(CODE_TOOLTIPS, json.encode({-1, slotNum}))
        end
      end
    end
  else
    hoveredItem = nil
    tooltipWindow:hide()
  end
end

function showTooltip(uid)
  local cachedItem = cachedItems[uid]
  if not cachedItem then return end

  cachedItem.id = hoveredItem:getId()
  cachedItem.count = hoveredItem:getCount()

  buildItemTooltip(cachedItem)
end

function buildItemTooltip(item)
  tooltipWidth = 0
  longestString = 0
  tooltipWidthBase = BASE_WIDTH
  tooltipHeight = BASE_HEIGHT
  tooltipWindow:setWidth(tooltipWidth)
  tooltipWindow:setHeight(tooltipHeight)

  labels:destroyChildren()

  local id = item.id
  local name = item.name
  local lookText = item.lookText
  local count = item.count
  local weight = item.weight
  local reqLvl = item.reqLvl or 0

  itemWeightLabel:setText(formatWeight(weight))
  itemSprite:setItemId(id)
  itemSprite:setItemCount(count)

  -- Title case the name
  name = name:gsub("(%a)(%a+)", function(a, b)
    return string.upper(a) .. string.lower(b)
  end)

  -- Item name
  addString(name, "#ffffff")

  -- Required level
  if reqLvl > 0 then
    addString("Required Level " .. reqLvl, Colors.ItemLevel)
  end

  -- Split lookText by commas and display each as a line
  if lookText and lookText:len() > 0 then
    addSeparator()
    addEmpty(5)

    -- Split by comma, trim each part
    local parts = {}
    for part in lookText:gmatch("[^,]+") do
      local trimmed = part:match("^%s*(.-)%s*$")
      if trimmed and trimmed:len() > 0 then
        table.insert(parts, trimmed)
      end
    end

    for _, part in ipairs(parts) do
      -- Color bracketed text differently (unique bonuses)
      if part:sub(1, 1) == "[" then
        addString(part, Colors.Attribute)
      else
        addString(part, Colors.Implicit)
      end
    end
  end

  shrinkSeparators()
  showItemTooltip()
end

function addString(text, color, resize)
  local label = g_ui.createWidget("TooltipLabel", labels)
  label:setColor(color)

  if resize then
    tooltipWindow:setWidth(tooltipWidth)
    label:setTextWrap(true)
    label:setTextAutoResize(true)
    label:setText(text)
    tooltipHeight = tooltipHeight + label:getTextSize().height + 4
  else
    label:setText(text)
    local textSize = label:getTextSize()
    if longestString == 0 then
      longestString = textSize.width + itemWeightLabel:getWidth()
      tooltipWidth = tooltipWidthBase + longestString
      label:addAnchor(AnchorTop, "parent", AnchorTop)
    elseif textSize.width > longestString then
      longestString = textSize.width
      tooltipWidth = tooltipWidthBase + longestString
    end
    tooltipHeight = tooltipHeight + textSize.height
  end
end

function shrinkSeparators()
  local children = labels:getChildren()
  local m = math.max(60, math.floor(tooltipWidth / 4))
  for _, child in ipairs(children) do
    if child:getStyleName() == "TooltipSeparator" then
      child:setMarginLeft(m)
      child:setMarginRight(m)
    end
  end
end

function addSeparator()
  local sep = g_ui.createWidget("TooltipSeparator", labels)
  tooltipHeight = tooltipHeight + sep:getHeight() + sep:getMarginTop() + sep:getMarginBottom()
end

function addEmpty(height)
  local empty = g_ui.createWidget("TooltipEmpty", labels)
  empty:setHeight(height)
  tooltipHeight = tooltipHeight + height
end

function showItemTooltip()
  local mousePos = g_window.getMousePosition()
  tooltipHeight = math.max(tooltipHeight, 40)
  tooltipWindow:setWidth(tooltipWidth)
  tooltipWindow:setHeight(tooltipHeight)

  local windowSize = g_window.getSize()
  if mousePos.x > windowSize.width / 2 then
    tooltipWindow:move(mousePos.x - (tooltipWidth + 2), math.min(windowSize.height - tooltipHeight, mousePos.y + 5))
  else
    tooltipWindow:move(mousePos.x + 5, mousePos.y + 10)
  end
  tooltipWindow:raise()
  tooltipWindow:show()
  g_effects.fadeIn(tooltipWindow, 100)
end

function formatWeight(weight)
  local ss

  if weight < 10 then
    ss = "0.0" .. weight
  elseif weight < 100 then
    ss = "0." .. weight
  else
    local weightString = tostring(weight)
    local len = weightString:len()
    ss = weightString:sub(1, len - 2) .. "." .. weightString:sub(len - 1, len)
  end

  ss = ss .. " oz."
  return ss
end
