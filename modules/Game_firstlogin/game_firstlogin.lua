-- modules/Game_firstlogin/game_firstlogin.lua
-- Tutorial interativo exibido apenas no primeiro login de cada personagem.
-- Também pode ser aberto a qualquer momento com a talkaction: !opentuto

moduleActive   = false
tutorialActive = false
currentImage   = 1

local overlay      = nil
local arrow        = nil
local tooltip      = nil
local imagesWindow = nil

local STEP = {
  IDLE       = 0, -- inativo
  WAIT_FOLDS = 1, -- aguardando a barra de skills ser configurada
  HEAL_INFO  = 2, -- texto 1 + botao avancar
  WAIT_MENU  = 3, -- aguardando abrir a janela Add Hotkey
  WAIT_ADD   = 4, -- aguardando pressionar ADD
  IMAGES     = 5, -- tutorial por imagens
}

local step      = STEP.IDLE
local healName  = nil
local waitEvent = nil
local polling   = false
local waitFoldsSince = nil

local ARROW_W = 64
local ARROW_H = 48

-- Se a barra de skills nao for configurada em FOLDS_GRACE segundos,
-- prosseguimos direto para a etapa de imagens (o tutorial nunca fica
-- preso / com a tela escurecida para sempre).
local FOLDS_GRACE = 8

-- Diagnostico: so logamos o estado do foldsReady uma vez por segundo
-- para nao poluir o log.
local lastFoldDiag = 0

local TEXTS = {
  heal      = "Esta é a sua dobra de cura. Ela é essencial para te manter vivo neste mundo.",
  hotkeyMenu = "Clique com o botão direito na imagem da dobra e selecione 'Add Hotkey'.",
  addKey    = "Escolha uma tecla do seu teclado para armazenar essa dobra e pressione em ADD.",
}

local IMAGES = {
  { text = 'Selecione o seu alvo clicando com o botão direito nele.' },
  { text = 'Use suas dobras para se sair melhor no combate contra criaturas selvagens.' },
  { text = 'Deposite seus itens no seu baú. Nenhum jogador além de você poderá retirar seus itens.' },
  { text = 'Explore o mundo utilizando o minimapa. Todas as áreas já descobertas permanecerão visíveis. Pressione CTRL + M ou utilize o menu superior para abri-lo.' },
  { text = 'Cada dobrador possui seu elemento exibido ao lado do nome. Preste atenção para não se confundir.' },
  { text = 'Todo o restante das funcionalidades importantes poderá ser encontrado no menu superior do client.' },
}

local function log(msg)
  g_logger.info("[game_firstlogin] " .. msg)
end

-- Diagnostico: estado real dos widgets (para depurar invisibilidade)
local function logWidgetState(tag)
  local function state(w)
    if not w then return "nil" end
    local pos = w:getPosition()
    return string.format("vis=%s opacity=%.2f x=%d y=%d w=%d h=%d parent=%s",
      tostring(w:isVisible()), w:getOpacity(), pos.x, pos.y,
      w:getWidth(), w:getHeight(), tostring(w:getParent() and w:getParent():getId() or 'none'))
  end
  log(tag .. " | overlay(" .. state(overlay) .. ") arrow(" .. state(arrow) ..
      ") tooltip(" .. state(tooltip) .. ") imgWin(" .. state(imagesWindow) .. ")")
end

-- Garante que o widget fica 100% opaco (neutraliza qualquer fade preso)
local function forceVisible(w)
  if not w then return end
  w:setOpacity(1)
  w:show()
  w:raise()
end

log("script carregado (inicio do arquivo)")

------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------

-- Posicao de um widget.
-- IMPORTANTE: nesta build os retangulos dos widgets sao ABSOLUTOS
-- (coordenadas em relacao ao rootWidget). O layout por ancora alinha
-- os filhos usando os retangulos absolutos dos irmaos, e o itemfly
-- (que funciona) usa getRect() direto em widgets aninhados. Entao
-- NAO somamos os pais — isso dobraria as coordenadas e a seta
-- ficaria fora do lugar.
local function rootPos(w)
  local p = w:getPosition()
  return p.x, p.y
end

-- O flag de conclusao fica gravado em STORAGE no SERVIDOR (nao no
-- client): assim segue o personagem em qualquer maquina. A comunicacao
-- usa o extended opcode do patch tools/tfs_extendedopcode.patch.
-- O servidor deve responder a este opcode em
-- data/creaturescripts/scripts/extendedopcode.lua.
local TUTORIAL_OPCODE = 220
local TUTORIAL_STORAGE = 42001 -- chave de storage usada no servidor

local storageReplied   = false
local pendingOpen       = false
local storageWaitEvent = nil

local function sendStorageRequest(cmd)
  pcall(function()
    if g_game.getProtocolGame() then
      g_game.getProtocolGame():sendExtendedOpcode(TUTORIAL_OPCODE, cmd)
    end
  end)
end

-- Resposta do servidor:
--   "open" -> push do creaturescript de login (primeiro login): abrir tutorial
--   "1"    -> ja concluido, nada a mostrar
--   "0"    -> pendente (fallback para servidores sem o script de login)
local function onStorageReply(buffer)
  storageReplied = true
  if storageWaitEvent then
    storageWaitEvent:cancel()
    storageWaitEvent = nil
  end
  log("resposta do servidor (storage): " .. tostring(buffer))
  if not g_game.isOnline() then
    -- o push "open" pode chegar antes do onGameStart (durante o login)
    if buffer == "open" then pendingOpen = true end
    return
  end
  if buffer == "1" then
    log("personagem ja fez o tutorial (storage), nada a mostrar")
  elseif buffer == "open" then
    log("servidor pediu para abrir o tutorial (primeiro login)")
    scheduleEvent(startTutorial, 300)
  else
    scheduleEvent(startTutorial, 300)
  end
end

local function requestStorage()
  storageReplied = false
  sendStorageRequest("get")
  -- fallback: se o servidor nao responder (sem o script do patch),
  -- inicia o tutorial mesmo assim (nunca deixa o jogador sem tutorial)
  storageWaitEvent = scheduleEvent(function()
    storageWaitEvent = nil
    if not storageReplied then
      log("sem resposta do servidor, iniciando tutorial")
      storageReplied = true
      if g_game.isOnline() then startTutorial() end
    end
  end, 3000)
end

local function markDone()
  sendStorageRequest("set")
end

local function resetStorage()
  sendStorageRequest("reset")
end

-- A barra de folds so fica util depois que o servidor envia a vocacao
local function foldsReady()
  local folds = modules.game_folds
  if not folds then return false end
  if not folds.infos then return false end
  local voc = folds.infos.vocation
  if not voc or voc < 1 or voc > 4 then return false end
  local mini = folds.miniWindow
  if not mini then return false end
  local p = mini:getChildById('p2')
  if not p then return false end
  return p.name ~= nil and p.name ~= ''
end

-- A segunda magia da barra e sempre a dobra de cura (ex: Fire Recover)
local function getHealName()
  local folds = modules.game_folds
  if not folds or not folds.miniWindow then return nil end
  local p = folds.miniWindow:getChildById('p2')
  return p and p.name or nil
end

local function getAssignWindow()
  return rootWidget:recursiveGetChildById('assignWindow')
end

------------------------------------------------------------------
-- UI helpers
------------------------------------------------------------------

local function clampToScreen(x, y, w, h)
  local sw, sh = g_window.getSize().width, g_window.getSize().height
  x = math.max(2, math.min(x, sw - w - 2))
  y = math.max(2, math.min(y, sh - h - 2))
  return x, y
end

local function placeArrow(x, y, rot)
  if not arrow then return end
  x, y = clampToScreen(x, y, ARROW_W, ARROW_H)
  arrow:setPosition({ x = x, y = y })
  arrow:setRotation(rot or 0)
  arrow:raise()
end

local function placeTooltipNear(x, y)
  if not tooltip then return end
  local tw, th = tooltip:getWidth(), tooltip:getHeight()
  local px = x + 24
  if px + tw > g_window.getSize().width - 8 then px = x - tw - 24 end
  local py = y + 24
  if py + th > g_window.getSize().height - 8 then py = y - th - 24 end
  -- clamp final dentro da tela (mesma garantia da seta)
  px, py = clampToScreen(px, py, tw, th)
  tooltip:setPosition({ x = px, y = py })
  tooltip:raise()
end

-- Aponta a seta para a dobra de cura
local function updateHealPointers()
  local folds = modules.game_folds
  if not folds or not folds.miniWindow then return end
  local slot = folds.miniWindow:getChildById('p2')
  if not slot then return end
  local sx, sy = rootPos(slot)
  if not sx or not sy or (sx == 0 and sy == 0) then
    -- fallback: centraliza na tela (nunca deixa a seta fora da area visivel)
    local sw, sh = g_window.getSize().width, g_window.getSize().height
    sx, sy = sw / 2, sh / 2
  end
  placeArrow(sx + slot:getWidth() / 2 - ARROW_W / 2, sy - ARROW_H - 8, 0)
  placeTooltipNear(sx, sy - ARROW_H - 8)
end

-- Aponta a seta para a janela Add Hotkey
local function updateWindowPointers()
  local win = getAssignWindow()
  if not win then return end
  local wx, wy = rootPos(win)
  placeArrow(wx + win:getWidth() / 2 - ARROW_W / 2, wy - ARROW_H - 8, 0)
  placeTooltipNear(wx + win:getWidth(), wy)
end

local function setTooltipText(text)
  if not tooltip then return end
  local label = tooltip:getChildById('tipText')
  if label then label:setText(text) end
end

local function showImage(index)
  if not imagesWindow then return end
  local textLabel = imagesWindow:getChildById('imageText')
  if textLabel then textLabel:setText(IMAGES[index].text) end
  -- O widget da imagem e filho do imageFrame (neto da janela), entao
  -- precisamos de busca recursiva. Trocamos o image-source em runtime:
  -- garantia de que a imagem sempre troca ao avancar/voltar.
  local img = imagesWindow:recursiveGetChildById('img')
  if img then
    img:setImageSource('/modules/Game_firstlogin/img/IMG' .. index)
  end
  local prev = imagesWindow:getChildById('prevButton')
  local nextBtn = imagesWindow:getChildById('nextButton')
  if prev then prev:setEnabled(index > 1) end
  if nextBtn then nextBtn:setEnabled(index < #IMAGES) end
end

------------------------------------------------------------------
-- Etapas
------------------------------------------------------------------

local function enterStep(newStep)
  step = newStep

  if newStep == STEP.HEAL_INFO then
    setTooltipText(TEXTS.heal)
    local btn = tooltip:getChildById('nextButton')
    if btn then btn:show() end
    tooltip:setPhantom(false)
    forceVisible(overlay)  -- overlay por baixo, mas garantido opaco
    forceVisible(tooltip)
    forceVisible(arrow)
    updateHealPointers()
    logWidgetState("etapa HEAL_INFO")

  elseif newStep == STEP.WAIT_MENU then
    setTooltipText(TEXTS.hotkeyMenu)
    local btn = tooltip:getChildById('nextButton')
    if btn then btn:show() end
    tooltip:setPhantom(false)
    forceVisible(tooltip)
    forceVisible(arrow)
    updateHealPointers()
    log("etapa: WAIT_MENU (ensina Add Hotkey)")

  elseif newStep == STEP.WAIT_ADD then
    setTooltipText(TEXTS.addKey)
    local btn = tooltip:getChildById('nextButton')
    if btn then btn:show() end
    tooltip:setPhantom(false)
    forceVisible(tooltip)
    forceVisible(arrow)
    local win = getAssignWindow()
    if win then updateWindowPointers() else updateHealPointers() end
    log("etapa: WAIT_ADD (ensina escolher a tecla)")

  elseif newStep == STEP.IMAGES then
    arrow:hide()
    tooltip:hide()
    overlay:setPhantom(false) -- bloqueia o restante da interface
    currentImage = 1
    showImage(currentImage)
    forceVisible(imagesWindow)
    logWidgetState("etapa IMAGES")
  end
end

local function pollTick()
  if not tutorialActive then
    polling = false
    return
  end
  if not g_game.isOnline() then
    log("poll: perdeu conexao, parando tutorial")
    stopTutorial()
    polling = false
    return
  end

  local s = step
  if s == STEP.HEAL_INFO or s == STEP.WAIT_MENU or s == STEP.WAIT_ADD then
    if os.time() - lastFoldDiag > 2 then
      lastFoldDiag = os.time()
      logWidgetState("poll " .. s)
    end
  end
  if s == STEP.WAIT_FOLDS then
    if foldsReady() then
      healName = getHealName()
      log("folds prontas, dobra de cura: " .. tostring(healName))
      enterStep(STEP.HEAL_INFO)
    else
      local now = os.time()
      if now - (waitFoldsSince or now) > FOLDS_GRACE then
        -- sem dobras a tempo: pula as etapas que dependem da barra e
        -- vai direto para o tutorial de imagens (nunca fica preso)
        local folds = modules.game_folds
        local voc = folds and folds.infos and folds.infos.vocation
        local mini = folds and folds.miniWindow
        local p = mini and mini:getChildById('p2')
        log(string.format("folds nao configuradas apos %ds, pulando para imagens (voc=%s mini=%s p2=%s p2.name=%s)",
          FOLDS_GRACE, tostring(voc), tostring(mini ~= nil), tostring(p ~= nil),
          tostring(p and p.name or 'nil')))
        enterStep(STEP.IMAGES)
      elseif now - lastFoldDiag > 1 then
        lastFoldDiag = now
        local folds = modules.game_folds
        local voc = folds and folds.infos and folds.infos.vocation
        local mini = folds and folds.miniWindow
        local p = mini and mini:getChildById('p2')
        log(string.format("aguardando folds: voc=%s mini=%s p2=%s p2.name=%s",
          tostring(voc), tostring(mini ~= nil), tostring(p ~= nil),
          tostring(p and p.name or 'nil')))
      end
    end
  elseif s == STEP.HEAL_INFO then
    updateHealPointers()
  elseif s == STEP.WAIT_MENU then
    updateHealPointers()
  elseif s == STEP.WAIT_ADD then
    if getAssignWindow() then updateWindowPointers() else updateHealPointers() end
  end

  if tutorialActive and step ~= STEP.IMAGES then
    waitEvent = scheduleEvent(pollTick, 150)
  else
    polling = false
  end
end

local function startPolling()
  if polling then return end
  polling = true
  waitEvent = scheduleEvent(pollTick, 150)
end

local function stopTutorial()
  tutorialActive = false
  step = STEP.IDLE
  if waitEvent then
    waitEvent:cancel()
    waitEvent = nil
  end
  polling = false
  if overlay then overlay:hide() end
  if arrow then arrow:hide() end
  if tooltip then tooltip:hide() end
  if imagesWindow then imagesWindow:hide() end
end

------------------------------------------------------------------
-- API publica (usada pelo .otui)
------------------------------------------------------------------

function startTutorial()
  if not g_game.isOnline() then
    log("startTutorial ignorado: sem conexao")
    return
  end
  stopTutorial()
  tutorialActive = true
  currentImage = 1
  step = STEP.WAIT_FOLDS
  waitFoldsSince = os.time()
  lastFoldDiag = 0
  forceVisible(overlay)
  overlay:setPhantom(true)
  log("tutorial iniciado, aguardando folds")
  logWidgetState("startTutorial")
  pcall(function() modules.game_folds.doOpen() end)
  startPolling()
end

function onNextStep()
  if step == STEP.HEAL_INFO then
    enterStep(STEP.WAIT_MENU)
  elseif step == STEP.WAIT_MENU then
    enterStep(STEP.WAIT_ADD)
  elseif step == STEP.WAIT_ADD then
    enterStep(STEP.IMAGES)
  end
end

function onPrevImage()
  if step == STEP.IMAGES and currentImage > 1 then
    currentImage = currentImage - 1
    showImage(currentImage)
  end
end

function onNextImage()
  if step == STEP.IMAGES and currentImage < #IMAGES then
    currentImage = currentImage + 1
    showImage(currentImage)
  end
end

function onCloseImages()
  if step ~= STEP.IMAGES then return end
  -- so marca como concluido ao fechar apos a ultima imagem;
  -- fechar antes apenas fecha (o tutorial reaparece no proximo login)
  if currentImage >= #IMAGES then
    markDone()
    log("tutorial concluido para " .. g_game.getCharacterName())
  end
  stopTutorial()
end

------------------------------------------------------------------
-- Talkaction !opentuto
------------------------------------------------------------------

local function talkFilter(msg)
  if not g_game.isOnline() then return false end
  if msg and msg:lower():match("^%!opentuto%s*$") then
    log("talkaction !opentuto detectada, abrindo tutorial")
    startTutorial()
    return true -- consome a mensagem, nao envia ao servidor
  end
  if msg and msg:lower():match("^%!resettuto%s*$") then
    -- Reseta a storage no servidor para o tutorial voltar a aparecer
    -- no proximo login (util para testes).
    resetStorage()
    log("talkaction !resettuto: storage resetada no servidor")
    return true -- consome a mensagem, nao envia ao servidor
  end
  return false
end

------------------------------------------------------------------
-- Ciclo de vida
------------------------------------------------------------------

function onGameStart()
  log("onGameStart: solicitando storage do tutorial (char=" .. tostring(g_game.getCharacterName()) .. ")")
  if pendingOpen then
    pendingOpen = false
    log("push 'open' recebido antes do login completo, iniciando tutorial")
    scheduleEvent(startTutorial, 300)
  else
    requestStorage()
  end
end

function onGameEnd()
  log("onGameEnd, parando tutorial")
  pendingOpen = false
  if storageWaitEvent then
    storageWaitEvent:cancel()
    storageWaitEvent = nil
  end
  stopTutorial()
end

function init()
  -- Diagnostico: se algo falhar ao carregar os estilos/widgets, registramos
  -- o motivo no log em vez de falhar silenciosamente.
  local ok, err = pcall(function()
    g_ui.importStyle('game_firstlogin')
    overlay      = g_ui.createWidget('FirstLoginOverlay', rootWidget)
    arrow        = g_ui.createWidget('FirstLoginArrow', rootWidget)
    tooltip      = g_ui.createWidget('FirstLoginTooltip', rootWidget)
    imagesWindow = g_ui.createWidget('FirstLoginImagesWindow', rootWidget)
  end)
  if not ok then
    g_logger.error("[game_firstlogin] falha no init: " .. tostring(err))
    return
  end
  if not (overlay and arrow and tooltip and imagesWindow) then
    g_logger.error(string.format(
      "[game_firstlogin] widgets nao criados: overlay=%s arrow=%s tooltip=%s imagesWindow=%s",
      tostring(overlay ~= nil), tostring(arrow ~= nil),
      tostring(tooltip ~= nil), tostring(imagesWindow ~= nil)))
    return
  end

  overlay:hide()
  arrow:hide()
  tooltip:hide()
  imagesWindow:hide()

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd   = onGameEnd,
  })

  local opOk = pcall(function()
    ProtocolGame.registerExtendedOpcode(TUTORIAL_OPCODE, function(protocol, op, buffer)
      onStorageReply(buffer)
    end)
  end)
  if not opOk then
    g_logger.error("[game_firstlogin] falha ao registrar opcode do storage")
  end

  local filterOk = pcall(function() modules.game_console.addFilter(talkFilter) end)
  if not filterOk then
    g_logger.error("[game_firstlogin] falha ao registrar filtro do console")
  end

  moduleActive = true
  log("modulo iniciado (widgets criados, eventos conectados)")
end

function terminate()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd   = onGameEnd,
  })

  pcall(function() modules.game_console.removeFilter(talkFilter) end)
  pcall(function() ProtocolGame.unregisterExtendedOpcode(TUTORIAL_OPCODE) end)
  if storageWaitEvent then
    storageWaitEvent:cancel()
    storageWaitEvent = nil
  end

  stopTutorial()

  if overlay then overlay:destroy() end
  if arrow then arrow:destroy() end
  if tooltip then tooltip:destroy() end
  if imagesWindow then imagesWindow:destroy() end

  overlay, arrow, tooltip, imagesWindow = nil, nil, nil, nil
  moduleActive = false
end
