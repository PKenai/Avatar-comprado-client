--[[
  *Sistema de multi-world, by Mirto (milton33b@hotmail.com)
]]--


servers = {

  {txt = "Raava", port = 9191},
  {txt = "Moon", port = 8181},
  {txt = "Beta", port = 7171},
  {txt = "Local", host = "127.0.0.1", port = 9191}
}

--[[
  *Cada server novo adicionado, deve ser adicionada a nova porta, sistema � configurado para suportar um n�mero infinito de servidores.
  *A lista obedece a ordem correta, caso a port seja 0, o servidor nega a entrada.
]]--