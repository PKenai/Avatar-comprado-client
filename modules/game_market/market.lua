-- ============================================================================
--  Market - Client module (game_market)
--  Opcode 230  <->  server data/lib/market_lib.lua
-- ============================================================================

Market = {}

mOpcode = 230
numPage = 1
lastSearch = ""
lastFilter = "all"

local marketWindow
local marketWindowAdd
local marketButton
local marketList
local btnNext
local btnPrev
local lblIndex
local edtSearch
local cmbFilter
local searchEvent

local function short(value, maxLine)
  if string.len(value) >= maxLine then
    return string.sub(value, 1, maxLine-4) .. " ..."
  else
    return value
  end
end

local function round(num, numDecimalPlaces)
  return tonumber(string.format("%." .. (numDecimalPlaces or 0) .. "f", num))
end

local function formatPrice(price)
  price = tonumber(price) or 0
  if price >= 1000000000000 then
    return round(price / 1000000000000, 2) .. "T"
  elseif price >= 1000000000 then
    return round(price / 1000000000, 2) .. "B"
  elseif price >= 1000000 then
    return round(price / 1000000, 2) .. "M"
  else
    return round(price / 1000, 2) .. "k"
  end
end

-- Filter categories. The data values must match the server (market_lib.lua)
-- getItemCategory() return values.
local filterOptions = {
  { 'Todas',      'all'    },
  { 'Armas',      'weapon' },
  { 'Escudos',    'shield' },
  { 'Capacetes',  'helmet' },
  { 'Armaduras',  'armor'  },
  { 'Calças',     'legs'   },
  { 'Botas',      'boots'  },
  { 'Anéis',      'ring'   },
  { 'Amuletos',   'amulet' },
  { 'Variados',   'misc'   }
}

local function requestOffers(page, search)
  local protocol = g_game.getProtocolGame()
  if not protocol then return end
  page = page or numPage
  search = search or lastSearch
  local filter = lastFilter or "all"
  if search and search ~= "" then
    protocol:sendExtendedOpcode(mOpcode, "search>" .. search .. ">" .. page .. ">" .. filter)
  else
    protocol:sendExtendedOpcode(mOpcode, "getOffer>" .. page .. ">" .. filter)
  end
end

function Market.init()
  connect(g_game, {
    onGameStart = Market.online,
    onGameEnd   = Market.offline
  })

  ProtocolGame.registerExtendedOpcode(mOpcode, function(protocol, opcode, buffer)
    if type(buffer) ~= "string" or buffer == "" then
      return
    end

    local ok, err = pcall(function()
      local action = buffer:explode('>')
      if action[1] == "create" then
        Market.updateControlsPagination(action[2])
        -- payload: create>COUNT>{lua table} - rejoin everything after count
        local data = {}
        for i = 3, #action do
          data[#data + 1] = action[i]
        end
        local list = {}
        local fn, cerr = loadstring("return " .. table.concat(data, ">"))
        if fn then
          list = fn() or {}
        else
          print("[market] loadstring error: " .. tostring(cerr))
        end
        Market.createList(list)
      elseif action[1] == "details" then
        displayInfoBox('Market', action[2] or "")
      end
    end)
    if not ok then
      print("[market] parse error: " .. tostring(err))
    end
  end)

  marketButton    = modules.client_topmenu.addRightGameButton('marketButton', tr('Market'), '/images/topbuttons/shop', Market.toggle, true)
  marketWindow    = g_ui.displayUI('market')
  marketWindowAdd = g_ui.displayUI('marketadd')

  -- NOTE: getChildById in this client only finds DIRECT children.
  -- The pagination/search widgets are nested inside panels, so use the
  -- recursive variant here.
  marketList = marketWindow:recursiveGetChildById('marketList')
  btnNext    = marketWindow:recursiveGetChildById('btnNext')
  btnPrev    = marketWindow:recursiveGetChildById('btnPrev')
  lblIndex   = marketWindow:recursiveGetChildById('lblIndex')
  edtSearch  = marketWindow:recursiveGetChildById('edtSearch')
  cmbFilter  = marketWindow:recursiveGetChildById('cmbFilter')

  -- Populate the filter dropdown.
  if cmbFilter then
    for i, opt in ipairs(filterOptions) do
      cmbFilter:addOption(opt[1], opt[2])
    end
    cmbFilter.onOptionChange = Market.onFilterChange
  end
end

function Market.terminate()
  disconnect(g_game, {
    onGameStart = Market.online,
    onGameEnd   = Market.offline
  })
  pcall(function() ProtocolGame.unregisterExtendedOpcode(mOpcode) end)
  marketButton:destroy()
  marketWindow:destroy()
  marketWindowAdd:destroy()
end

function Market.online()
  numPage = g_settings.getNumber('mNumPage', 1)
  lastSearch = ""
  lastFilter = "all"
  if cmbFilter then
    cmbFilter:setCurrentOption(tr('Todas'))
  end
  requestOffers(1, "")
end

function Market.offline()
  marketWindow:hide()
  g_settings.set('mNumPage', numPage)
end

function Market.toggle()
  local visible = not marketWindow:isVisible()
  marketWindow:setVisible(visible)
  if visible then
    numPage = 1
    requestOffers(1, lastSearch)
  end
end

function Market.refresh()
  numPage = 1
  requestOffers(1, lastSearch)
end

function Market.clearSearch()
  edtSearch:clearText()
  lastSearch = ""
  numPage = 1
  requestOffers(1, "")
end

function Market.onSearchTextChange(text)
  if searchEvent then
    searchEvent:cancel()
  end
  searchEvent = scheduleEvent(function()
    lastSearch = text or ""
    numPage = 1
    requestOffers(1, lastSearch)
  end, 300)
end

function Market.onFilterChange(self, text, data)
  lastFilter = data or "all"
  numPage = 1
  requestOffers(1, lastSearch)
end

function Market.showAddOffer()
  if ( not marketWindowAdd:isVisible() ) then
    marketWindowAdd:show()
    marketWindowAdd:focus()
    marketWindowAdd:raise()
  end
end

function Market.addOffer()
  local itemName  = marketWindowAdd:getChildById('edtItem')
  local itemPrice = marketWindowAdd:getChildById('edtPrice')
  local itemCount = marketWindowAdd:getChildById('edtCount')

  local name, price, count = itemName:getText(), itemPrice:getText(), itemCount:getText()
  if name == "" or price == "" or count == "" then
    displayInfoBox('Market', tr('Preencha todos os campos.'))
    return
  end

  local action = string.format("!offer add, %s, %s, %s", name, count, price)
  g_game.talkChannel(MessageModes.Market, MessageModes.None, action)

  itemName:clearText()
  itemPrice:clearText()
  itemCount:clearText()
  marketWindowAdd:hide()

  scheduleEvent(function() requestOffers(1, lastSearch) end, 500)
end

function Market.createList(list)
  marketList:destroyChildren()

  if not list or #list == 0 then
    local empty = g_ui.createWidget('MarketRow', marketList)
    empty:getChildById('uiItem'):setVisible(false)
    empty:getChildById('btnAction'):setVisible(false)
    -- re-anchor the label to the row start so the empty message is centered.
    -- This client has NO setAnchors; use breakAnchors + addAnchor instead.
    -- NOTE: breakAnchors() removes ALL anchors, so re-add vertical centering too.
    local lbl = empty:getChildById('lblItem')
    lbl:breakAnchors()
    lbl:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    lbl:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    lbl:setMarginLeft(8)
    lbl:setText(tr('Nenhuma oferta encontrada'))
    empty:getChildById('lblPlayer'):setText('')
    empty:getChildById('lblQtd'):setText('')
    empty:getChildById('lblPrice'):setText('')
    return
  end

  for i, value in ipairs(list) do
    local marketRow = g_ui.createWidget('MarketRow', marketList)

    marketRow.onDoubleClick = function(self)
      g_game.getProtocolGame():sendExtendedOpcode(mOpcode, "details>"..value.id)
    end

    local uiItem = marketRow:getChildById('uiItem')
    uiItem:setItemId(value.itemId or 0)

    -- "look real" tooltip with full item stats (sent by the server).
    -- Shown on both the sprite and the item name.
    local lblItem = marketRow:getChildById('lblItem')
    if value.look and value.look ~= "" then
      uiItem:setTooltip(value.look)
      lblItem:setTooltip(value.look)
    end

    lblItem:setText(short(value.itemName or "", 24))
    marketRow:getChildById('lblPlayer'):setText(short(value.player or "", 20))
    marketRow:getChildById('lblQtd'):setText(value.count or 0)
    marketRow:getChildById('lblPrice'):setText(formatPrice(value.price))

    local btnAction = marketRow:getChildById('btnAction')
    btnAction:setText(value.type == 0 and tr('Comprar') or tr('Remover'))
    btnAction.onClick = function(self)
      local action = (value.type == 0 and "!offer buy," or "!offer remove,")..value.id
      g_game.talkChannel(MessageModes.Market, MessageModes.None, action)
      scheduleEvent(function() requestOffers(numPage, lastSearch) end, 600)
    end
  end
end

function Market.nextAndPrev(control)
  numPage = ( control == 1 ) and ( numPage + 1 ) or ( numPage - 1 )
  if numPage < 1 then
    numPage = 1
  end
  requestOffers(numPage, lastSearch)
end

function Market.updateControlsPagination(value)
  local total = tonumber(value) or 0
  local totalPages = math.max(1, math.ceil(total / 15))
  btnPrev:setEnabled(numPage ~= 1)
  btnNext:setEnabled(numPage < totalPages)
  lblIndex:setText('Página: ' .. numPage .. '/' .. totalPages)
end
