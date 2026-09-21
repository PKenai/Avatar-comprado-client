-- ============================================================================
-- PIX (doacao / Buy Coins) - LADO CLIENT
-- ----------------------------------------------------------------------------
-- Quem manda no fluxo e' o servidor (data/creaturescripts/scripts/game_pix.lua,
-- extended opcode 120): ele cria o pedido, calcula os coins, gera o codigo PIX
-- e credita os pontos quando o pagamento e' confirmado. Este modulo:
--
--   * mostra a janela de doacao (nome, ultimo nome, valor);
--   * pede a cobranca pro servidor e busca o QR Code do Mercado Pago diretamente
--     pelo client (sem precisar abrir navegador!);
--   * mostra a imagem do QR Code e copia automaticamente a chave Copia e Cola;
--   * pergunta o status a cada 5s para confirmar na hora que o jogador pagar.
--
-- O botao "Buy Coins" da loja nova (mods/game_store) chama modules.game_pix.open().
-- ============================================================================

local PIX_OP = 120
local CHECK_INTERVAL = 5000

local topButton = nil
local mainWindow = nil
local qrCodeWindowPix = nil
local checkEvent = nil
local acceptWindow = {}
local currentTxid = nil
local currentCharge = nil -- { stage, value, coins, payload, checkoutUrl, qrImage }

local httpCallbacks = {}
local httpConnected = false

-- ============================================================================
-- Helpers
-- ============================================================================
function comma_value(n)
  local left, num, right = string.match(tostring(n or 0), '^([^%d]*%d)(%d*)(.-)$')
  if not num then return tostring(n or 0) end
  return left .. (num:reverse():gsub('(%d%d%d)', '%1.'):reverse()) .. right
end

local function qrWidget(id)
  if not qrCodeWindowPix then
    return nil
  end
  return qrCodeWindowPix:recursiveGetChildById(id)
end

local function isValidName(name)
  return type(name) == "string" and #name >= 2 and #name <= 30 and not name:match("%d") and not name:match("[^%a%s%-]")
end

local function isValidValue(value)
  return type(value) == "number" and value == value and value >= 0.10
end

local function sendCancelBox(header, text)
  if #acceptWindow > 0 then
    acceptWindow[#acceptWindow]:destroy()
    acceptWindow = {}
  end

  local closeFunc = function()
    if #acceptWindow > 0 then
      acceptWindow[#acceptWindow]:destroy()
      acceptWindow = {}
    end
  end

  acceptWindow[#acceptWindow + 1] = displayGeneralBox(tr(header), text,
    { { text = tr("OK"), callback = closeFunc } }, closeFunc)
end

local function sendRequest(action, data)
  local proto = g_game.getProtocolGame()
  if not proto then
    return false
  end

  proto:sendExtendedOpcode(PIX_OP, json.encode({ action = action, data = data or {} }))
  return true
end

local function stopChecking()
  if checkEvent then
    removeEvent(checkEvent)
    checkEvent = nil
  end
end

local function startChecking()
  stopChecking()
  checkEvent = scheduleEvent(function()
    if not g_game.isOnline() or not currentTxid then
      stopChecking()
      return
    end
    sendRequest("check", { txid = currentTxid })
    startChecking()
  end, CHECK_INTERVAL)
end

-- ============================================================================
-- Integracao HTTP direta no Client (Busca QR Code do Gateway em segundo plano)
-- ============================================================================
local activeOpId = nil

local function cancelActiveHttp()
  if activeOpId then
    if g_http and g_http.cancel then
      pcall(function() g_http.cancel(activeOpId) end)
    end
    httpCallbacks[activeOpId] = nil
    activeOpId = nil
  end
end

local function onHttpGet(opId, url, err, data)
  local cb = httpCallbacks[opId]
  if cb then
    httpCallbacks[opId] = nil
    if activeOpId == opId then
      activeOpId = nil
    end
    if err and #err > 0 then
      cb(nil, err)
    else
      local ok, res = pcall(json.decode, data)
      if ok and type(res) == "table" then
        cb(res, nil)
      else
        cb(nil, "JSON decode error")
      end
    end
  end
end

-- Atribui diretamente para garantir que o C++ chame sem intermediarios
g_http.onGet = onHttpGet

local function fetchPixGateway(url, callback)
  if not g_http then
    callback(nil, "HTTP not supported")
    return
  end

  cancelActiveHttp()

  if g_http.setUserAgent then
    g_http.setUserAgent("AvatarClient/1.0")
  end

  local opId = g_http.get(url, 15)
  if opId and opId > 0 then
    activeOpId = opId
    httpCallbacks[opId] = callback
  else
    callback(nil, "Failed to start HTTP")
  end
end

-- ============================================================================
-- Janela do QR / copia e cola
-- ============================================================================
function copyCode()
  local code = currentCharge and currentCharge.payload or ""
  if code and code ~= "" then
    g_window.setClipboardText(code)
    modules.game_textmessage.displayGameMessage(tr("Codigo Pix Copia e Cola copiado com sucesso!"))
  end
end

local function showQrWindow(charge)
  if not qrCodeWindowPix then
    return
  end

  if mainWindow then
    mainWindow:hide()
  end

  currentCharge = charge
  currentCharge.stage = "charge"
  currentTxid = charge.txid

  local header = qrWidget("text")
  if header then
    local charName = g_game.isOnline() and g_game.getCharacterName() or "Jogador"
    local text = tr("Ola %s!\nValor: R$ %s | Coins: %s",
      charName, charge.value or "?", comma_value(charge.coins or 0))
    if charge.canceledPrevious then
      text = text .. '\n(' .. tr("Pix anterior cancelado") .. ')'
    end
    header:setText(text)
  end

  local qrImage = qrWidget("qrCode")
  local loading = qrWidget("Loading")
  local codeEdit = qrWidget("qrCodeEdit")
  local siteButton = qrWidget("siteButton")

  if siteButton then
    siteButton:hide()
  end

  -- Se ja recebemos a imagem do QR pronta em base64:
  if charge.qrImage and charge.qrImage ~= "" then
    if loading then loading:hide() end
    if qrImage then
      qrImage:setImageSourceBase64(charge.qrImage)
      qrImage:show()
    end
    if codeEdit then
      codeEdit:setText(charge.payload or "")
      codeEdit:setEditable(false)
    end
    if charge.payload and charge.payload ~= "" then
      g_window.setClipboardText(charge.payload)
    end
  else
    -- Ainda sem a imagem da cobranca: mostra loading e busca via HTTP no gateway
    if qrImage then qrImage:hide() end
    if loading then loading:show() end
    if codeEdit then
      codeEdit:setText(tr("Gerando Pix com o Mercado Pago... Aguarde..."))
      codeEdit:setEditable(false)
    end
    if charge.payload and charge.payload ~= "" then
      g_window.setClipboardText(charge.payload)
    end

    if charge.checkoutUrl and charge.checkoutUrl ~= "" then
      local separator = charge.checkoutUrl:find("?", 1, true) and "&" or "?"
      local tokenParam = ""
      if charge.jsonToken and charge.jsonToken ~= "" then
        tokenParam = "&token=" .. tostring(charge.jsonToken)
      end
      local url = charge.checkoutUrl .. separator .. "txid=" .. tostring(charge.txid) .. "&json=1&ngrok-skip-browser-warning=1" .. tokenParam
      local thisTxid = charge.txid

      fetchPixGateway(url, function(data, err)
        if currentTxid ~= thisTxid then
          return
        end

        if loading then loading:hide() end

        if data and data.ok and (not data.txid or data.txid == thisTxid) then
          if qrImage and data.qr_base64 and data.qr_base64 ~= "" then
            qrImage:setImageSourceBase64(data.qr_base64)
            qrImage:show()
          end
          if codeEdit and data.qr_code and data.qr_code ~= "" then
            codeEdit:setText(data.qr_code)
            g_window.setClipboardText(data.qr_code)
            currentCharge.payload = data.qr_code
          end
          modules.game_textmessage.displayGameMessage(tr("Codigo Pix Copia e Cola copiado para a area de transferencia!"))
        else
          -- Fallback: se o gateway falhar, mantem o payload basico
          if qrImage then qrImage:hide() end
          if siteButton then siteButton:show() end
        end
      end)
    end
  end

  qrCodeWindowPix:show()
  qrCodeWindowPix:focus()
  qrCodeWindowPix:raise()

  startChecking()
end

-- ============================================================================
-- Respostas do servidor
-- ============================================================================
local function onPixStage(msg)
  local stage = msg.stage

  if stage == "charge" then
    showQrWindow(msg)
  elseif stage == "pending" then
    -- segue esperando o pagamento (o servidor avisa quando confirmar)
  elseif stage == "paid" then
    stopChecking()
    currentTxid = nil
    if qrCodeWindowPix then
      qrCodeWindowPix:hide()
    end
    sendCancelBox("Pagamento confirmado",
      tr("Seu pagamento foi confirmado!\nCoins recebidos: %s\nSaldo atual: %s\nObrigado e bom jogo!",
        comma_value(msg.coins or 0), comma_value(msg.points or 0)))
  elseif stage == "expired" then
    stopChecking()
    currentTxid = nil
    if qrCodeWindowPix then
      qrCodeWindowPix:hide()
    end
    sendCancelBox("Pix expirado", tr("O tempo para pagar este Pix acabou. Abra a janela e gere outro."))
  elseif stage == "canceled" then
    stopChecking()
    currentTxid = nil
  elseif stage == "error" then
    sendCancelBox("Aviso", msg.message or tr("Nao foi possivel concluir a operacao."))
  end
end

function onExtendedOpcode(protocol, code, buffer)
  if code ~= PIX_OP then
    return false
  end

  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= "table" or msg.action ~= "pix" then
    return false
  end

  onPixStage(msg)
  return true
end

-- ============================================================================
-- Janela de doacao
-- ============================================================================
function sendDonate()
  if not mainWindow then
    return
  end

  if not g_game.isOnline() then
    sendCancelBox("Aviso", tr("Voce precisa estar online para doar."))
    return
  end

  local firstName = mainWindow.firstNameText:getText()
  local lastName = mainWindow.lastNameText:getText()
  local rawValue = tostring(mainWindow.valorText:getText()):gsub("%s+", ""):gsub(",", ".")
  if rawValue:sub(1, 1) == "." then
    rawValue = "0" .. rawValue
  end
  -- Se o usuario digitou 0010 ou 010 (sem ponto ou virgula), interpreta como centavos (0010 = 0.10)
  if rawValue:match("^00%d+$") then
    local cents = tonumber(rawValue) or 0
    rawValue = tostring(cents / 100)
  end
  local valor = tonumber(rawValue) or 0

  if not isValidName(firstName) or not isValidName(lastName) then
    sendCancelBox("Aviso", tr("Voce precisa digitar um nome valido."))
    return
  end

  if not isValidValue(valor) then
    sendCancelBox("Aviso", tr("Voce precisa doar um valor minimo de 10 centavos."))
    return
  end

  local confirmFunc = function()
    if #acceptWindow > 0 then
      acceptWindow[#acceptWindow]:destroy()
      acceptWindow = {}
    end
    if mainWindow then
      mainWindow:hide()
    end
    sendRequest("create", { name = firstName, lastname = lastName, value = valor })
  end

  local cancelFunc = function()
    if #acceptWindow > 0 then
      acceptWindow[#acceptWindow]:destroy()
      acceptWindow = {}
    end
  end

  if #acceptWindow > 0 then
    acceptWindow[#acceptWindow]:destroy()
  end

  acceptWindow[#acceptWindow + 1] = displayGeneralBox(tr("Tem certeza?"),
    tr("Voce deseja prosseguir com a doacao?\nValor: R$ %.2f", valor),
    {
      { text = tr("Sim"), callback = confirmFunc },
      { text = tr("Nao"), callback = cancelFunc },
    }, confirmFunc, cancelFunc)
end

function cancelDonate()
  cancelActiveHttp()

  if qrCodeWindowPix then
    qrCodeWindowPix:hide()
  end
  if mainWindow then
    mainWindow:hide()
  end

  stopChecking()

  -- se havia uma cobranca aberta, avisa o servidor pra cancelar o pedido
  if currentTxid and currentCharge and currentCharge.stage == "charge" then
    sendRequest("cancel", { txid = currentTxid })
  end

  currentTxid = nil
  currentCharge = nil
end

function toggle()
  if not mainWindow then
    return
  end

  if mainWindow:isVisible() then
    cancelDonate()
  else
    if qrCodeWindowPix and qrCodeWindowPix:isVisible() then
      qrCodeWindowPix:hide()
    end
    mainWindow:focus()
    mainWindow:raise()
    mainWindow:show()
  end
end

-- Usado pelo botao "Buy Coins" da loja nova (mods/game_store/store.lua)
function open()
  if not mainWindow then
    return false
  end

  if not mainWindow:isVisible() then
    mainWindow:focus()
    mainWindow:raise()
    mainWindow:show()
  else
    mainWindow:raise()
  end
  return true
end

-- chamado pelo botao "Abrir no navegador" da janela do QR caso necessario
function openSite()
  local url = currentCharge and currentCharge.checkoutUrl
  if not url or url == "" then
    return
  end

  local separator = url:find("?", 1, true) and "&" or "?"
  g_platform.openUrl(url .. separator .. "txid=" .. tostring(currentTxid or ""))
end

-- ============================================================================
-- Ciclo de vida
-- ============================================================================
function init()
  if g_http and g_http.setUserAgent then
    g_http.setUserAgent("AvatarClient/1.0")
  end

  mainWindow = g_ui.displayUI("game_pix")
  mainWindow:hide()

  qrCodeWindowPix = g_ui.displayUI("qrcodePix")
  qrCodeWindowPix:hide()

  local siteButton = qrWidget("siteButton")
  if siteButton then
    siteButton.onClick = openSite
    siteButton:hide()
  end

  local copyButton = qrWidget("copyButton")
  if copyButton then
    copyButton.onClick = copyCode
  end

  local qrImage = qrWidget("qrCode")
  if qrImage then
    qrImage.onClick = copyCode
  end

  local codeEdit = qrWidget("qrCodeEdit")
  if codeEdit then
    codeEdit.onMousePress = function()
      copyCode()
      return false
    end
  end

  ProtocolGame.registerExtendedOpcode(PIX_OP, onExtendedOpcode)

  if modules.client_topmenu then
    topButton = modules.client_topmenu.addRightGameToggleButton("gamePixButton", tr("Doar via Pix"),
      "/images/topbuttons/pix_icon", toggle, false)
  end

  connect(g_game, { onGameEnd = cancelDonate })
end

function terminate()
  cancelActiveHttp()
  ProtocolGame.unregisterExtendedOpcode(PIX_OP, onExtendedOpcode)
  disconnect(g_game, { onGameEnd = cancelDonate })

  stopChecking()

  if topButton then
    topButton:destroy()
    topButton = nil
  end

  if qrCodeWindowPix then
    qrCodeWindowPix:destroy()
    qrCodeWindowPix = nil
  end

  if mainWindow then
    mainWindow:destroy()
    mainWindow = nil
  end
end
