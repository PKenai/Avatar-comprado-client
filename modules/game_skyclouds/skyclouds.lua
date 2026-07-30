-- Sky Clouds Module
-- Realistic animated cloud layer with per-pixel occlusion.
--
-- Shader registration & server opcode handling are done in game_shaders/shaders.lua.
-- This module handles:
--   - Player Z position tracking (above-ground vs underground)
--   - Auto-enable/disable clouds based on Z level
--   - Public API (setEnabled, isEnabled, refresh, isActive)
--   - Settings persistence

local SHADER_NAME = "sky_clouds"
local ENABLED_KEY = "skyCloudsEnabled"
local POLL_INTERVAL_MS = 1000

local cloudsEnabled = true
local wasAboveGround = nil
local moduleLoaded = false
local pollEvent = nil

-- ═══════════════════════════════════════════════════════════════════════════
--  Initialization
-- ═══════════════════════════════════════════════════════════════════════════

function init()
  g_logger.info("[SkyClouds] *** INIT CALLED *** Module is loading...")

  -- Restore user preference
  local saved = g_settings.get(ENABLED_KEY)
  if saved ~= nil then
    cloudsEnabled = (saved == true or saved == "true" or saved == "1")
  else
    cloudsEnabled = true
  end
  -- cloudsEnabled is now controlled by client_options (skyClouds toggle)
  g_logger.info("[SkyClouds] Loaded setting: enabled=" .. tostring(cloudsEnabled))

  -- Shader creation is async on graphics thread, so we can't check existence here
  g_logger.info("[SkyClouds] Shader '" .. SHADER_NAME .. "' creation requested (async on graphics thread)")

  -- Connect game events
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  g_logger.info("[SkyClouds] Connected to g_game events")

  moduleLoaded = true
  g_logger.info("[SkyClouds] *** INIT COMPLETE *** Module ready!")
end

function terminate()
  g_logger.info("[SkyClouds] terminate() called")

  stopPolling()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  removeShader()
  moduleLoaded = false

  g_logger.info("[SkyClouds] terminate() done")
end

-- ═══════════════════════════════════════════════════════════════════════════
--  Polling (periodic Z check)
-- ═══════════════════════════════════════════════════════════════════════════

function startPolling()
  stopPolling()

  local function tick()
    if not moduleLoaded then return end
    checkPlayerZ()
    -- Schedule next tick
    pollEvent = scheduleEvent(tick, POLL_INTERVAL_MS)
  end

  -- First tick
  pollEvent = scheduleEvent(tick, 500)
  g_logger.info("[SkyClouds] Started Z position polling (every " .. POLL_INTERVAL_MS .. "ms)")
end

function stopPolling()
  if pollEvent then
    removeEvent(pollEvent)
    pollEvent = nil
  end
end

function checkPlayerZ()
  local player = g_game.getLocalPlayer()
  if not player then
    if wasAboveGround ~= false then
      wasAboveGround = false
      removeShader()
    end
    return
  end

  local pos = player:getPosition()
  if not pos or not pos.z then
    return
  end

  local aboveGround = (pos.z <= 7)

  if aboveGround ~= wasAboveGround then
    wasAboveGround = aboveGround
    g_logger.info("[SkyClouds] Z changed to " .. pos.z .. " (aboveGround=" .. tostring(aboveGround) .. ")")
    if aboveGround and cloudsEnabled then
      applyShader()
    else
      removeShader()
    end
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
--  Event handlers
-- ═══════════════════════════════════════════════════════════════════════════

function onGameStart()
  g_logger.info("[SkyClouds] onGameStart fired!")
  -- Start periodic Z checking
  addEvent(startPolling)
end

function onGameEnd()
  g_logger.info("[SkyClouds] onGameEnd fired!")
  stopPolling()
  wasAboveGround = nil
  removeShader()
end

-- ═══════════════════════════════════════════════════════════════════════════
--  Shader management
-- ═══════════════════════════════════════════════════════════════════════════

function getMapPanel()
  if modules and modules.game_interface and modules.game_interface.getMapPanel then
    return modules.game_interface.getMapPanel()
  end
  return nil
end

function applyShader()
  local mapPanel = getMapPanel()
  if not mapPanel then
    g_logger.warning("[SkyClouds] applyShader() — no map panel!")
    return
  end

  local before = mapPanel:getShader()
  mapPanel:setShader(SHADER_NAME)

  if mapPanel:getShader() == SHADER_NAME then
    g_logger.info("[SkyClouds] Shader applied! '" .. tostring(before) .. "' -> 'sky_clouds'")
  else
    g_logger.warning("[SkyClouds] Shader set failed! Current: '" .. tostring(mapPanel:getShader()) .. "'")
  end
end

function removeShader()
  local mapPanel = getMapPanel()
  if not mapPanel then
    return
  end

  if mapPanel:getShader() == SHADER_NAME then
    mapPanel:setShader("")
    g_logger.info("[SkyClouds] Shader removed")
  end
end

-- ═══════════════════════════════════════════════════════════════════════════
--  Public API
-- ═══════════════════════════════════════════════════════════════════════════

function setEnabled(enabled)
  g_logger.info("[SkyClouds] setEnabled(" .. tostring(enabled) .. ")")
  cloudsEnabled = enabled
  g_settings.set(ENABLED_KEY, enabled)

  if enabled and wasAboveGround then
    applyShader()
  else
    removeShader()
  end
end

function isEnabled()
  return cloudsEnabled
end

function refresh()
  g_logger.info("[SkyClouds] refresh()")
  removeShader()
  if cloudsEnabled and wasAboveGround then
    applyShader()
  end
end

function isActive()
  local panel = getMapPanel()
  return panel ~= nil and panel:getShader() == SHADER_NAME
end

-- For debugging from console: modules.game_skyclouds.forceEnable()
function forceEnable()
  g_logger.info("[SkyClouds] forceEnable() — forcing shader ON")
  cloudsEnabled = true
  wasAboveGround = true
  g_settings.set(ENABLED_KEY, true)
  applyShader()
end
