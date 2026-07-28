local FADE_MS = 2000
local fadeTimer = nil
local SPIRITUAL_SHADER = "outfit_spiritual"
local SPIRITUAL_PREFIX = "Spiritual "
local appliedSpiritual = {}
local applyingSpiritual = false

function init()
  g_shaders.createShader("map_default", "/shaders/map_default_vertex", "/shaders/map_default_fragment")

  g_shaders.createShader("map_rainbow", "/shaders/map_rainbow_vertex", "/shaders/map_rainbow_fragment")
  g_shaders.addTexture("map_rainbow", "/images/shaders/rainbow.png")

  g_shaders.createShader("map_cloudy", "/shaders/map_cloudy_vertex", "/shaders/map_cloudy_fragment")
  g_shaders.createShader("background_particles", "/shaders/map_default_vertex", "/shaders/background_particles_fragment")
  createFadeShaders()
  createOutfitShaders()

  ProtocolGame.registerExtendedOpcode(ExtendedIds.MapShader, onMapShader)
  connect(g_game, { onGameEnd = onGameEndClearShader })
  connect(Creature, {
    onAppear = onCreatureAppearSpiritual,
    onDisappear = onCreatureDisappearSpiritual,
    onOutfitChange = onCreatureOutfitSpiritual
  })
end

function terminate()
  clearFadeTimer()
  ProtocolGame.unregisterExtendedOpcode(ExtendedIds.MapShader)
  disconnect(g_game, { onGameEnd = onGameEndClearShader })
  disconnect(Creature, {
    onAppear = onCreatureAppearSpiritual,
    onDisappear = onCreatureDisappearSpiritual,
    onOutfitChange = onCreatureOutfitSpiritual
  })
  appliedSpiritual = {}
end

function createFadeShaders()
  -- Recreating resets u_Time (link sets m_startTime).
  g_shaders.createShader("map_fade_out", "/shaders/map_default_vertex", "/shaders/map_fade_out_fragment")
  g_shaders.createShader("map_fade_in", "/shaders/map_default_vertex", "/shaders/map_fade_in_fragment")
  g_shaders.createShader("map_cloudy_fade_out", "/shaders/map_cloudy_vertex", "/shaders/map_cloudy_fade_out_fragment")
end

function createOutfitShaders()
  g_shaders.createOutfitShader(SPIRITUAL_SHADER, "/shaders/outfit_spiritual_vertex", "/shaders/outfit_spiritual_fragment")
end

local function setMapShader(name)
  local mapPanel = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
  if not mapPanel then
    return
  end
  if not name or name == "" or name == "off" or name == "none" or name == "map_default" then
    mapPanel:setShader("")
  else
    mapPanel:setShader(name)
  end
end

local function clearFadeTimer()
  if fadeTimer then
    removeEvent(fadeTimer)
    fadeTimer = nil
  end
end

local function notifyServer(buffer)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(ExtendedIds.MapShader, buffer)
  end
end

-- createShader is async on the graphics thread. Defer apply so we don't use a stale u_Time.
local function applyFade(shaderName, doneMsg, notifyAtMs)
  clearFadeTimer()
  setMapShader("")
  createFadeShaders()
  local waitMs = notifyAtMs or FADE_MS
  addEvent(function()
    addEvent(function()
      setMapShader(shaderName)
      fadeTimer = scheduleEvent(function()
        fadeTimer = nil
        notifyServer(doneMsg)
      end, waitMs)
    end)
  end)
end

function onMapShader(protocol, opcode, buffer)
  buffer = buffer or ""
  if buffer == "fade_out" then
    -- Start of flight: fully dark before staging teleport.
    applyFade("map_fade_out", "fade_out_done", FADE_MS)
  elseif buffer == "cloudy_fade_out" then
    -- End of flight: darken while clouds still play; TP as soon as nearly black.
    applyFade("map_cloudy_fade_out", "exit_fade_done", math.floor(FADE_MS * 0.9))
  elseif buffer == "fade_in" then
    applyFade("map_fade_in", "fade_in_done", math.floor(FADE_MS * 0.9))
  else
    clearFadeTimer()
    setMapShader(buffer)
  end
end

function onGameEndClearShader()
  clearFadeTimer()
  setMapShader("")
  appliedSpiritual = {}
end

local function isSpiritualName(name)
  return name and name:sub(1, #SPIRITUAL_PREFIX) == SPIRITUAL_PREFIX
end

function applySpiritualOutfitShader(creature)
  if applyingSpiritual or not creature or creature:isLocalPlayer() then
    return
  end
  if not isSpiritualName(creature:getName()) then
    return
  end

  local id = creature:getId()
  if appliedSpiritual[id] then
    return
  end

  local outfit = creature:getOutfit()
  outfit.shader = SPIRITUAL_SHADER
  appliedSpiritual[id] = true
  applyingSpiritual = true
  creature:setOutfit(outfit)
  applyingSpiritual = false
end

function onCreatureAppearSpiritual(creature)
  applySpiritualOutfitShader(creature)
end

function onCreatureDisappearSpiritual(creature)
  if creature then
    appliedSpiritual[creature:getId()] = nil
  end
end

function onCreatureOutfitSpiritual(creature, outfit, oldOutfit)
  if applyingSpiritual or not creature then
    return
  end
  -- External outfit update from server clears shader; mark dirty and re-apply.
  appliedSpiritual[creature:getId()] = nil
  applySpiritualOutfitShader(creature)
end
