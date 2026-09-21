local HIGH_OP = 73

local window, button
local highscoreData = {}
local categoryId, page, pages
local searchText = ""

local filterOptions = {
  { label = "All Vocations", filter = {0,1,2,3,4,5,6,7,8} }
}

local serverToName = {
  [0] = "None",
  [1] = "Sorcerer", [5] = "Master Sorcerer",
  [2] = "Druid", [6] = "Elder Druid",
  [3] = "Paladin", [7] = "Royal Paladin",
  [4] = "Knight", [8] = "Elite Knight",
}

local categories = {
  { id = 0, label = "Level" },
  { id = 1, label = "Sword" },
  { id = 2, label = "Axe" },
  { id = 3, label = "Club" },
  { id = 5, label = "Shielding" },
  { id = 6, label = "Bending" },
  { id = 7, label = "Fishing" }
}

local function getCategoryIndex(id)
  for index, category in ipairs(categories) do
    if category.id == id then
      return index
    end
  end
  return 1
end

local function getCategory()
  return categories[getCategoryIndex(categoryId or 0)]
end

local function getScore(entry)
  if (categoryId or 0) == 0 then
    return entry.level
  end
  return entry.experience
end

local function matchesSearch(entry)
  if searchText == "" then
    return true
  end
  return entry.name and entry.name:lower():find(searchText, 1, true) ~= nil
end

local function getWidget(id)
  return window and window:recursiveGetChildById(id)
end

local function getRankColor(rank)
  rank = tonumber(rank)
  if rank == 1 then
    return "#ffd800"
  elseif rank == 2 then
    return "#ffffff"
  elseif rank == 3 then
    return "#cd7f32"
  end
  return "#dfdfdf"
end

local function updateYourPosition()
  if not window then
    return
  end

  local player = g_game.getLocalPlayer()
  local playerName = player and player:getName()
  local text = "-"

  if playerName then
    for _, entry in ipairs(highscoreData) do
      if entry.name == playerName then
        text = "#" .. comma_value(entry.rank)
        break
      end
    end
  end

  getWidget("position"):setText("Your position: " .. text)
end

local function sendHighscoreRequest(cat, pg, perPage)
  local proto = g_game.getProtocolGame()
  if not proto then return end

  local payload = json.encode{
    action = "request",
    category = cat,
    vocation = 0,
    page = pg,
    entriesPerPage = perPage,
    type = 0,
    vocations = filterOptions[1].filter,
  }

  proto:sendExtendedOpcode(HIGH_OP, payload)
  if window then
    getWidget("next"):setEnabled(false)
    getWidget("prev"):setEnabled(false)
  end
end

function onHighscore(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or msg.action ~= "highscore" then return false end
  if not window then return false end

  categoryId, page, pages = msg.category, msg.page, msg.pages
  highscoreData = msg.data or {}

  local category = getCategory()
  getWidget("categoryBox"):setText(category.label)
  getWidget("scoreHeader"):setText(category.label)
  getWidget("page"):setText(("Page %d / %d"):format(page, pages))

  updateYourPosition()
  createHighscores()

  getWidget("next"):setEnabled(page < pages)
  getWidget("prev"):setEnabled(page > 1)
  return true
end

function createHighscores()
  local container = getWidget("data")
  container:destroyChildren()

  local player = g_game.getLocalPlayer()
  local playerName = player and player:getName()
  local shown = 0

  for i, entry in ipairs(highscoreData) do
    if matchesSearch(entry) then
      shown = shown + 1

      local row = g_ui.createWidget("HighScoreData", container)
      row:setBackgroundColor((shown % 2 == 0) and "#ffffff08" or "#00000018")
      local rankColor = getRankColor(entry.rank)
      row.rank:setText(entry.rank)
      row.rank:setColor(rankColor)
      row.name:setText(entry.name)
      row.name:setColor(rankColor)
      row.voc:setText(serverToName[entry.vocation] or "??")
      row.score:setText(comma_value(getScore(entry)))

      if entry.name == playerName then
        row:setBackgroundColor("#1f6fb866")
        row.name:setColor("#66d9ff")
        row.voc:setColor("#66d9ff")
      end
    end
  end

  if shown == 0 then
    local row = g_ui.createWidget("HighScoreData", container)
    row.rank:setText("")
    row.name:setText("No records found.")
    row.voc:setText("")
    row.score:setText("")
  end
end

function create()
  if window then return end
  window = g_ui.displayUI("highscore")
  local worldName = g_game.getWorldName and g_game.getWorldName()
  if worldName and worldName ~= "" then
    window:setText("Highscores - " .. worldName)
  end

  local cb = getWidget("categoryBox")
  cb:clearOptions()
  for _, category in ipairs(categories) do
    cb:addOption(category.label)
  end
  cb:setCurrentIndex(1)
  cb.onOptionChange = function(self)
    categoryId = categories[self.currentIndex].id
    searchText = ""
    getWidget("searchEdit"):setText("")
    sendHighscoreRequest(categoryId, 1, 10)
  end

  local searchEdit = getWidget("searchEdit")
  searchEdit.onTextChange = function(widget, text)
    searchText = (text or ""):lower()
    createHighscores()
  end

  getWidget("searchButton").onClick = function()
    searchText = (searchEdit:getText() or ""):lower()
    createHighscores()
  end

  getWidget("next").onClick = function() sendHighscoreRequest(categoryId, page + 1, 10) end
  getWidget("prev").onClick = function() sendHighscoreRequest(categoryId, page - 1, 10) end

  categoryId = 0
  page = 1
  pages = 1
  sendHighscoreRequest(0, 1, 10)
end

function toggle()
  if window and window:isVisible() then
    window:hide()
    if button then button:setOn(false) end
  else
    if not window then
      create()
    else
      sendHighscoreRequest(categoryId or 0, page or 1, 10)
    end
    if window then
      window:show()
      if button then button:setOn(true) end
    end
  end
end

function hide() if window then window:destroy() window = nil end end
function destroy() hide() if button then button:destroy() button = nil end end

function setColorTo(row, color)
  row.rank:setColor(color)
  row.name:setColor(color)
  row.voc:setColor(color)
  row.score:setColor(color)
end

function load()
  connect(g_game, { onGameEnd = hide })
  ProtocolGame.registerExtendedOpcode(HIGH_OP, onHighscore)

  if modules.client_topmenu then
    button = modules.client_topmenu.addRightGameToggleButton(
      "highscoreButton",
      tr("Highscores"),
      "/images/topbuttons/highscore",
      toggle,
      false,
      9
    )
  end
end

function unload()
  ProtocolGame.unregisterExtendedOpcode(HIGH_OP, onHighscore)
  disconnect(g_game, { onGameEnd = hide })
  destroy()
end
