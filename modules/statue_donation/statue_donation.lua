--[[
================================================================================
  STATUE DONATION - client
  Servidor: data/lib/statueDonation.lua (extended opcode 121)
--------------------------------------------------------------------------------
  A janela NAO abre por conta propria: quem abre e' o servidor, quando o jogador
  usa a estatua no mapa (action 50030). O servidor tambem responde com o estado
  completo depois de cada doacao, entao a tela nunca "adivinha" nada:

    server -> client   {action="state", data={...}}   estado das 4 nacoes + abas
                       {action="msg",   data={type=, msg=}}
    client -> server   {action="donate", data={target="fire", amount=50000}}
                       {action="donate", data={target="exp",  amount=50000}}

  REGRA DO DINHEIRO (igual nos dois lados)
  - Todo alvo tem POOL: nacao 150.000 gold, aba Experience 350.000, aba Potions
    400.000. O player doa o QUANTO QUISER, o pool vai enchendo com a doacao de
    todo mundo e a bencao ativa quando o pool bate a meta (o excedente nunca e'
    cobrado, e a doacao e' limitada ao que falta). Com a bencao ativa o pool nao
    aceita mais nada - so' volta a encher quando ela terminar.
  - Quem manda no preco e' o SERVIDOR: aqui so' mostramos o `pool`/`goal` que
    ele manda no estado (o client nunca calcula meta).

  SINCRONIZACAO (por que a janela nunca fica velha)
  O client guarda o ultimo estado que recebeu, entao uma janela aberta com dado
  antigo parecia "a janela nao guarda o status do buff". Agora: show() PEDE o
  estado (action "open"), o timer de 1s re-sincroniza de 15 em 15s enquanto a
  janela esta' visivel e o fim de sessao (onGameEnd) zera o estado. O titulo da
  janela lista o que esta' ATIVO com o tempo que falta - assim nao tem como
  "nao ver" um relogio correndo, e se o titulo disser "waiting for the
  server..." e' porque nenhum estado chegou (problema de entrega, nao de tela).

  ESCOLHA DO ALVO
  Cada card e' um alvo: clicar escolhe (o servidor aceita doacao pra QUALQUER
  nacao - a do player e' so' a que ja' vem selecionada na primeira tela). O card
  do .otui precisa ser phantom: false, senao o clique nunca chega no card (a
  style Panel e' phantom por padrao e o engine descarta clique em widget
  phantom). O alvo escolhido aparece em "targetText" e no proprio botao.
================================================================================
]]

local OPCODE = 121

-- Brilho do ICONE do card com bencao ativa: o mesmo efeito que a skill tree
-- usa nos talentos, em verde (data/shaders/statue_border_glow.frag).
local GLOW_SHADER = "statue_border_glow"
local glowAvailable = false

local window = nil
local state = nil
local cards = {}          -- key -> {root=, bar=, pool=, status=, mine=, ...}
local BARS = {}           -- { { bar = widget da progressbar, color = "#rrggbb" } }
local glowEvent = nil     -- timer do brilho do preenchimento das barras
local selection = { kind = "nation", key = "fire" }
local selectionInitialized = false -- na primeira tela, seleciona a nacao do player
local lastFocused = nil   -- nao refocar o card a cada segundo (roubava o foco
                          -- do campo de valor enquanto o player digitava)
local timerEvent = nil
local clockOffset = 0     -- serverTime - os.time() do client
local autoFilled = nil    -- ultimo valor que NOS escrevemos no campo de valor
                          -- (o que o player digitou nunca e' sobrescrito)
local lastSync = 0        -- g_clock da ultima vez que pedimos/ recebemos estado
local SYNC_MS = 15000     -- re-sincroniza a janela aberta de 15 em 15s

-- ============================================================================
-- Helpers
-- ============================================================================
local function formatNumber(n)
  local value = math.floor(tonumber(n) or 0)
  local text = tostring(value)
  text = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  text = text:gsub("^,", "")
  return text
end

local function formatTime(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local hours = math.floor(seconds / 3600)
  local mins = math.floor((seconds % 3600) / 60)
  if hours > 0 then
    return hours .. "h " .. (mins < 10 and "0" or "") .. mins .. "m"
  end
  local secs = seconds % 60
  return mins .. "m " .. (secs < 10 and "0" or "") .. secs .. "s"
end

local function serverNow()
  return os.time() + clockOffset
end

-- Pede o estado completo do servidor. O servidor responde com action "open"
-- (o MESMO pacote que ele manda quando o player usa a estatua), entao a janela
-- nunca fica com dado velho: o unico jeito de ela estar errada era depender so'
-- do que o servidor empurrava. Nao custa nada: e' um pacote pequeno.
local function requestState()
  if not g_game.isOnline() then return end
  local protocol = g_game.getProtocolGame()
  if not protocol then return end
  lastSync = g_clock.millis()
  pcall(function()
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = "open" }))
  end)
end

local function inputValue()
  local input = window and window:getChildById("amountInput")
  if not input then return nil end
  local text = input:getText() or ""
  text = text:gsub("[^%d]", "") -- somente digitos
  if text == "" then return nil end
  return tonumber(text)
end

-- ============================================================================
-- Criacao da janela
-- ============================================================================
-- Liga/desliga o brilho verde NO ICONE do card (cardImage) conforme a bencao
-- daquele card. So' mexe quando o estado MUDA (o refresh roda de segundo em
-- segundo) e nao faz nada se o client nao tiver o shader: a imagem entao
-- continua desenhando normal, sem moldura nenhuma em volta do card.
local function applyGlow(card, active)
  if not card.image then
    return
  end
  local want = (active and glowAvailable) and true or false
  if card.glowOn == want then
    return
  end
  card.glowOn = want
  pcall(function() card.image:setImageShader(want and GLOW_SHADER or "") end)
end

local function makeNationCard(nation)
  local row = window:getChildById("nationsRow")
  local card = g_ui.createWidget("NationCard", row)
  card:setId("nation_" .. nation.key)
  -- Tooltip do card (aparece ao passar o mouse): o percentual vem do SERVIDOR
  -- (nationDamage), entao mexer no data/lib/statueDonation.lua muda a tela
  -- tambem. O corelib (modules/corelib/ui/tooltip.lua) mostra no hover.
  card:setTooltip("+" .. tostring(state.nationDamage or 5) .. "% damage to creatures in PvE")
  card:getChildById("cardTitle"):setText(nation.label)
  card:getChildById("cardBar"):setBackgroundColor(nation.color or "#666666")
  card:getChildById("cardMine"):setText("")
  card.onClick = function() modules.statue_donation.select("nation", nation.key) end

  local bar = card:getChildById("cardBar")
  table.insert(BARS, { bar = bar, color = nation.color or "#666666" })

  cards[nation.key] = {
    root = card,
    kind = "nation",
    bar = bar,
    pool = card:getChildById("cardPool"),
    status = card:getChildById("cardStatus"),
    mine = card:getChildById("cardMine"),
    image = card:getChildById("cardImage"),
  }
end

local function makeGlobalCard(tab)
  local row = window:getChildById("globalsRow")
  local card = g_ui.createWidget("GlobalCard", row)
  card:setId("global_" .. tab.key)
  card:getChildById("cardTitle"):setText(tab.label)
  -- A meta do pool da aba (350.000 exp / 400.000 potions), igual nas nacoes.
  card:getChildById("cardCost"):setText(formatNumber(tab.cost) .. " gold - whole server")
  -- tab.detail vem do servidor (dono da regra): e' ele que diz o que o bonus
  -- afeta. Fallback pro rotulo quando o servidor nao mandar. Texto curto de
  -- proposito: assim cabe numa linha do card, sem corte.
  card:getChildById("cardDesc"):setText("+" .. tab.bonus .. "% " ..
    (tab.detail or (string.lower(tab.label) .. " gain")) ..
    " - whole server, " .. tab.hours .. "h")
  card:getChildById("cardBar"):setBackgroundColor(tab.color or "#666666")
  card.onClick = function() modules.statue_donation.select("global", tab.key) end

  local bar = card:getChildById("cardBar")
  table.insert(BARS, { bar = bar, color = tab.color or "#666666" })

  cards[tab.key] = {
    root = card,
    kind = "global",
    status = card:getChildById("cardStatus"),
    image = card:getChildById("cardImage"),
    bar = bar,
  }
end

local function buildCards()
  if not window then return end
  if #window:getChildById("nationsRow"):getChildren() > 0 then return end
  if not state then return end

  for _, nation in ipairs(state.nations or {}) do
    makeNationCard(nation)
  end
  for _, tab in ipairs(state.globals or {}) do
    makeGlobalCard(tab)
  end
end

local function create()
  if window then return window end
  window = g_ui.displayUI("statue_donation")
  if not window then return nil end
  window:hide()
  return window
end

-- ============================================================================
-- Render
-- ============================================================================
local SELECTED_BORDER = "#ffd479"
local IDLE_BORDER = "#3a3a3a"

-- Pinta o card escolhido (so' a borda: o card nao tem fundo). Precisa ser na
-- mao: o card perde o foco quando o player clica no campo de valor (e o $focus
-- do .otui iria junto).
local function paintSelection()
  for key, card in pairs(cards) do
    local isSelected = card.kind == selection.kind and key == selection.key
    card.root:setBorderColor(isSelected and SELECTED_BORDER or IDLE_BORDER)
    card.root:setBorderWidth(isSelected and 2 or 1)
  end
end

-- Lista do que esta' ativo AGORA (nacoes + abas), com o tempo que falta. Serve
-- pra duas coisas: o titulo da janela (ficou impossivel "nao ver" que tem
-- relogio correndo) e o proprio refresh do titulo a cada segundo.
local function activeList()
  if not state then return {} end
  local out = {}
  for _, n in ipairs(state.nations or {}) do
    local left = (n.until_ or 0) - serverNow()
    if left > 0 then table.insert(out, n.label .. " " .. formatTime(left)) end
  end
  for _, g in ipairs(state.globals or {}) do
    local left = (g.until_ or 0) - serverNow()
    if left > 0 then table.insert(out, g.label .. " " .. formatTime(left)) end
  end
  return out
end

local function updateTitle()
  if not window or not window.setText then return end
  local title = "Statue Donation"
  -- Sem estado nenhum a janela esta' mostrando o texto padrao do .otui: avisa
  -- no titulo em vez de fingir que esta' tudo inativo.
  if not state then
    title = title .. "  -  waiting for the server..."
  else
    local active = activeList()
    if #active > 0 then
      title = title .. "  -  ACTIVE: " .. table.concat(active, ", ")
    end
  end
  pcall(function() window:setText(title) end)
end

local function findNation(key)
  for _, n in ipairs(state.nations or {}) do
    if n.key == key then return n end
  end
  return nil
end

local function findGlobal(key)
  for _, g in ipairs(state.globals or {}) do
    if g.key == key then return g end
  end
  return nil
end

local function refreshSelection()
  -- destacar o card selecionado (so' quando MUDA: refocar todo segundo
  -- tirava o foco do campo de valor no meio da digitacao)
  local want = selection.kind .. ":" .. selection.key
  local justChanged = want ~= lastFocused
  if justChanged then
    local card = cards[selection.key]
    if card and card.root and card.kind == selection.kind then
      card.root:focus()
      lastFocused = want
    end
  end

  paintSelection()

  local input = window:getChildById("amountInput")
  local hint = window:getChildById("amountHint")
  local target = window:getChildById("targetText")
  local button = window:getChildById("donateButton")
  local amountLabel = window:getChildById("amountLabel")

  if selection.kind == "global" then
    local tab = findGlobal(selection.key)
    -- Aba global: MESMA mecanica da nacao - pool. O campo de valor e' livre (o
    -- player doa o quanto quiser) e o servidor limita ao que falta.
    if input then input:setEnabled(true) end
    if amountLabel then amountLabel:setText("Amount (gold)") end

    if tab then
      local left = (tab.until_ or 0) - serverNow()
      local goal = tonumber(tab.goal or tab.cost) or 0
      local pool = math.max(0, tab.pool or 0)
      local missing = math.max(0, goal - pool)

      if target then
        target:setText("Donating to: " .. tab.label .. " pool (whole server, " .. tab.hours .. "h)")
      end

      if left > 0 then
        -- Bencao ativa: nao da' pra doar. O botao fica bloqueado (o engine nao
        -- entrega clique em widget disabled) e o servidor tambem recusa.
        if button then
          button:setEnabled(false)
          button:setText("Active for " .. formatTime(left))
        end
      elseif button then
        button:setEnabled(true)
        button:setText("Donate to " .. tab.label)
      end

      -- Sugere o valor que falta so' quando o alvo acabou de mudar e o campo
      -- esta' vazio (ou ainda mostra o que NOS preenchemos): o refresh roda de
      -- segundo em segundo e nunca reescreve o que o player digitou.
      if justChanged and input then
        local text = input:getText() or ""
        if left <= 0 and missing >= 1 and (text == "" or text == autoFilled) then
          input:setText(tostring(missing))
          autoFilled = tostring(missing)
        elseif left > 0 and text == autoFilled then
          input:setText("")
          autoFilled = ""
        end
      end

      if hint then
        if left > 0 then
          hint:setText(tab.label .. " is already active (" .. formatTime(left) .. " left). The pool can only " ..
            "be filled again when it ends - nothing is stored for the next cycle.")
        else
          local available = (state.money or 0) + (state.bank or 0)
          hint:setText("Missing " .. formatNumber(missing) ..
            " gold to bless the whole server. Donate any amount; you have " ..
            formatNumber(available) .. " (backpack + bank).")
        end
      end
    end
    return
  end

  local nation = findNation(selection.key)
  if input then input:setEnabled(true) end
  if amountLabel then amountLabel:setText("Amount (gold)") end
  if nation then
    local left = (nation.until_ or 0) - serverNow()
    local missing = math.max(0, (nation.goal or 0) - (nation.pool or 0))

    if target then
      target:setText("Donating to: " .. nation.label ..
        (state.element == nation.element and " (your nation)" or ""))
    end

    if left > 0 then
      if button then
        button:setEnabled(false)
        button:setText("Blessed for " .. formatTime(left))
      end
    elseif button then
      button:setEnabled(true)
      button:setText("Donate to " .. nation.label)
    end

    -- Sugere o valor que falta - SO' quando o alvo acabou de mudar e o campo
    -- esta' vazio (ou ainda mostra o valor que NOS preenchemos): o refresh roda
    -- de segundo em segundo e nunca pode reescrever o que o player digitou.
    if justChanged and input then
      local text = input:getText() or ""
      if left <= 0 and missing >= 1 and (text == "" or text == autoFilled) then
        input:setText(tostring(missing))
        autoFilled = tostring(missing)
      elseif left > 0 and text == autoFilled then
        input:setText("")
        autoFilled = ""
      end
    end

    if hint then
      if left > 0 then
        hint:setText(nation.label .. " is already blessed (" .. formatTime(left) .. " left). You can't " ..
          "donate to this pool while it's active and nothing is stored for the next cycle.")
      else
        hint:setText("Missing " .. formatNumber(missing) .. " gold to bless " .. nation.label ..
          ". You are charged only what's missing (" .. formatNumber(missing) .. "), never more.")
      end
    end
  end
end

local function refreshCards()
  if not window or not state then
    updateTitle()
    return
  end

  updateTitle()

  -- Texto curto de ajuda (o .otui tem o mesmo texto como fallback).
  local header = window:getChildById("headerText")
  if header then
    header:setText("Select a card to donate and earn some bonuses")
  end

  window:getChildById("goldText"):setText("Backpack: " .. formatNumber(state.money or 0) ..
    " gold   |   Bank: " .. formatNumber(state.bank or 0) .. " gold")

  for _, nation in ipairs(state.nations or {}) do
    local card = cards[nation.key]
    if card then
      if card.image then
        card.image:setImageSource(nation.image or "")
      end

      local pool = math.max(0, nation.pool or 0)
      local goal = math.max(1, nation.goal or 1)
      local percent = math.min(100, math.floor(pool * 100 / goal))
      card.bar:setPercent(percent)
      card.bar:setText(formatNumber(pool) .. " / " .. formatNumber(goal))
      card.pool:setText(percent .. "%  (" .. formatNumber(math.max(0, goal - pool)) .. " left)")

      local left = (nation.until_ or 0) - serverNow()
      if left > 0 then
        card.status:setText("Blessed for " .. formatTime(left))
        card.status:setColor("#8fe08f")
      else
        card.status:setText("Not blessed")
        card.status:setColor("#bdbdbd")
      end

      -- Curto de proposito: o aviso fica na base do card e uma linha a mais
      -- encostaria no cardStatus.
      if state.element == nation.element then
        card.mine:setText("Your nation (+5% PvE)")
      else
        card.mine:setText("")
      end

      -- Contorno verde enquanto a nacao estiver abencoada
      applyGlow(card, left > 0)
    end
  end

  for _, tab in ipairs(state.globals or {}) do
    local card = cards[tab.key]
    if card then
      if card.image then
        card.image:setImageSource(tab.image or "")
      end
      local left = (tab.until_ or 0) - serverNow()
      local goal = math.max(1, tonumber(tab.goal or tab.cost) or 1)
      local pool = math.max(0, tab.pool or 0)
      local percent = math.min(100, math.floor(pool * 100 / goal))

      if left > 0 then
        card.status:setText("ACTIVE for " .. formatTime(left))
        card.status:setColor("#8fe08f")
      else
        -- Sem os numeros do pool: quem mostra eles e' a barra logo acima.
        card.status:setText("Not active")
        card.status:setColor("#bdbdbd")
      end

      -- Barra: com a bencao ativa ela mostra o progresso do TEMPO (enche conforme
      -- as horas passam); inativa ela mostra o POOL, igual a barra da nacao.
      if card.bar then
        local total = math.max(1, (tonumber(tab.hours) or 0) * 3600)
        if left > 0 then
          card.bar:setPercent(math.min(100, math.max(0, math.floor((total - left) * 100 / total))))
          card.bar:setText(formatTime(left) .. " left")
        else
          card.bar:setPercent(percent)
          card.bar:setText(formatNumber(pool) .. " / " .. formatNumber(goal))
        end
      end

      -- Contorno verde enquanto a bencao da aba estiver ativa
      applyGlow(card, left > 0)
    end
  end

  refreshSelection()
end

-- ============================================================================
-- Timer (contagem regressiva na tela)
-- ============================================================================
-- ============================================================================
-- Brilho do preenchimento das barras
-- ----------------------------------------------------------------------------
-- O preenchimento da progressbar e' um RETANGULO colorido (background-rect),
-- nao uma textura - o shader dos icones so' age em imagem. Entao aqui o brilho
-- e' um pulso no proprio background-color, na MESMA cadencia do shader
-- (sin(t * 2.6), ~2.4s), pra barra e icone respirarem juntos.
-- ============================================================================
local function hexToRgb(hex)
  hex = tostring(hex or ""):gsub("#", "")
  if #hex == 3 then
    hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
  end
  return tonumber(hex:sub(1, 2), 16) or 102,
         tonumber(hex:sub(3, 4), 16) or 102,
         tonumber(hex:sub(5, 6), 16) or 102
end

-- amount 0 = cor pura, 1 = branco
local function brighten(hex, amount)
  local r, g, b = hexToRgb(hex)
  r = math.floor(r + (255 - r) * amount)
  g = math.floor(g + (255 - g) * amount)
  b = math.floor(b + (255 - b) * amount)
  return string.format("#%02x%02x%02x", r, g, b)
end

local function pulseBars()
  glowEvent = nil
  if not window or not window:isVisible() then
    return
  end

  local k = 0.07 + 0.28 * (0.5 + 0.5 * math.sin((g_clock.millis() / 1000) * 2.6))
  for _, entry in ipairs(BARS) do
    local percent = 0
    if entry.bar.getPercent then
      percent = entry.bar:getPercent() or 0
    end
    -- barra vazia nao brilha (nao ha' preenchimento pra iluminar)
    if percent > 0 then
      entry.bar:setBackgroundColor(brighten(entry.color, k))
    end
  end

  glowEvent = scheduleEvent(pulseBars, 60)
end

local function startBarGlow()
  if glowEvent then
    return
  end
  glowEvent = scheduleEvent(pulseBars, 60)
end

local function stopBarGlow()
  if glowEvent then
    removeEvent(glowEvent)
    glowEvent = nil
  end
  for _, entry in ipairs(BARS) do
    entry.bar:setBackgroundColor(entry.color)
  end
end

local function stopTimer()
  stopBarGlow()
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
  end
end

local function startTimer()
  stopTimer()
  startBarGlow()
  timerEvent = scheduleEvent(function()
    if window and window:isVisible() then
      refreshCards()
      -- Re-sincroniza a janela aberta: cobre server restart, !resetstatue de
      -- outro admin, e qualquer pacote que tenha se perdido no caminho.
      if (g_clock.millis() - lastSync) > SYNC_MS then
        requestState()
      end
    end
    startTimer()
  end, 1000)
end

-- ============================================================================
-- API do module
-- ============================================================================
function init()
  -- Registra o shader do contorno verde (mesmo esquema do game_talenttree).
  -- createShader e' assincrono no thread grafico, mas so' aplicamos bem depois
  -- (quando um buff fica ativo), entao da' tempo de compilar.
  pcall(function()
    if g_shaders and g_shaders.createShader then
      g_shaders.createShader(GLOW_SHADER, "/shaders/map_default_vertex", "/shaders/statue_border_glow")
      glowAvailable = true
    end
  end)

  connect(g_game, {
    onGameStart = prepare,
    onGameEnd = onGameEnd,
  })
  pcall(function() ProtocolGame.unregisterExtendedOpcode(OPCODE) end)
  ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
  if g_game.isOnline() then
    prepare()
  end
end

function prepare()
  create()
end

-- Fim de sessao: o estado que estava na tela nao vale mais (o personagem pode
-- ter mudado, a bencao pode ter sido resetada enquanto ele estava fora). Zera
-- pra a proxima abertura SEMPRE pedir/esperar dado novo em vez de reusar o
-- antigo - era esse reuso que aparecia como "a janela nao guarda o status".
function onGameEnd()
  hide()
  state = nil
  selectionInitialized = false
  selection = { kind = "nation", key = "fire" }
  lastFocused = nil
  lastSync = 0
  updateTitle()
end

function terminate()
  disconnect(g_game, {
    onGameStart = prepare,
    onGameEnd = onGameEnd,
  })
  stopTimer()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  if window then
    window:destroy()
    window = nil
  end
  cards = {}
  BARS = {}
  lastFocused = nil
  state = nil
end

function onExtendedOpcode(protocol, code, buffer)
  local ok, decoded = pcall(function() return json.decode(buffer) end)
  if not ok or type(decoded) ~= "table" then return false end

  local action = decoded.action
  local data = decoded.data
  if type(data) ~= "table" then return true end

  if action == "open" then
    applyState(data, true)
  elseif action == "state" then
    -- atualizacao: NAO abre a janela. Ela so' e' aberta por "open" (uso da
    -- estatua) - doacao de outro jogador nao pode abrir tela em ninguem.
    applyState(data, false)
  elseif action == "msg" then
    displayInfoBox("Statue Donation", data.msg or "")
  end
  return true
end

function applyState(data, shouldShow)
  state = data
  lastSync = g_clock.millis()
  clockOffset = (tonumber(data.serverTime) or os.time()) - os.time()

  if not create() then return end
  buildCards()

  -- primeira tela: deixa a nacao do proprio jogador ja' selecionada
  if not selectionInitialized and state.element then
    for _, n in ipairs(state.nations or {}) do
      if n.element == state.element and cards[n.key] then
        selection = { kind = "nation", key = n.key }
        lastFocused = nil
        break
      end
    end
    selectionInitialized = true
  end

  refreshCards()

  if shouldShow then
    window:show()
    window:raise()
    window:focus()
    startTimer()
  elseif window:isVisible() then
    startTimer()
  end
end

function select(kind, key)
  selection = { kind = kind, key = key }
  lastFocused = nil -- forca o destaque do card novo
  refreshSelection()
end

function donate()
  if not state then return end
  local protocol = g_game.getProtocolGame()
  if not protocol then return end

  if selection.kind == "global" then
    local tab = findGlobal(selection.key)
    -- Bencao ativa: nem manda o pedido. O botao ja' fica bloqueado (widget
    -- disabled nao recebe clique) - isto e' cinto de seguranca.
    if tab and (tab.until_ or 0) - serverNow() > 0 then
      displayInfoBox("Statue Donation", tab.label .. " is already active (" ..
        formatTime((tab.until_ or 0) - serverNow()) .. " left).")
      return
    end

    -- Pool da aba: doa o quanto quiser, cortado no que falta (o servidor tambem
    -- limita - assim o valor cobrado nunca surpreende).
    local amount = inputValue()
    if not amount or amount < 1 then
      displayInfoBox("Statue Donation", "Type how much gold you want to donate.")
      return
    end
    if tab then
      local missing = math.max(0, tonumber(tab.goal or tab.cost or 0) - math.max(0, tab.pool or 0))
      if missing > 0 and amount > missing then amount = missing end
    end

    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = "donate", data = { target = selection.key, amount = amount } }))
    return
  end

  local nation = findNation(selection.key)
  if nation and (nation.until_ or 0) - serverNow() > 0 then
    displayInfoBox("Statue Donation", nation.label .. " is already blessed (" ..
      formatTime((nation.until_ or 0) - serverNow()) .. " left).")
    return
  end

  local amount = inputValue()
  if not amount or amount < 1 then
    displayInfoBox("Statue Donation", "Type how much gold you want to donate.")
    return
  end

  -- "So' pode doar o valor que falta": manda no maximo o que falta no pool (o
  -- servidor tambem limita - assim o valor cobrado nunca surpreende).
  if nation then
    local missing = math.max(0, (nation.goal or 0) - (nation.pool or 0))
    if missing > 0 and amount > missing then amount = missing end
  end

  protocol:sendExtendedOpcode(OPCODE, json.encode({ action = "donate", data = { target = selection.key, amount = amount } }))
end

function onAmountKeyPress()
  if window and window:isVisible() then
    refreshSelection()
  end
end

function show()
  if not window then return end
  updateTitle()
  window:show()
  window:raise()
  startTimer()
  -- Pedido fresco ao servidor: quem abriu a janela localmente nunca fica vendo
  -- o estado de antes.
  requestState()
end

function hide()
  stopTimer()
  if window then window:hide() end
end

function toggle()
  if not window then return end
  if window:isVisible() then
    hide()
  else
    show()
  end
end
