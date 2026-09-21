@echo off
title Avatar Eclipse - Ferramenta de Protecao de Assets
setlocal enabledelayedexpansion

cd /d "%~dp0.."
set CLIENT_EXE=otclient_gl.exe
set SPR_DIR=modules\corelib\ui
set SPR_FILE=%SPR_DIR%\zUniD.spr

if not exist "%CLIENT_EXE%" (
    echo [ERRO] Executavel "%CLIENT_EXE%" nao encontrado na raiz!
    echo Compile o client antes de usar esta ferramenta.
    pause
    exit /b 1
)

:MENU
cls
echo ================================================================
echo           AVATAR ECLIPSE - PROTECAO DE ASSETS E SPRITES
echo ================================================================
echo.
echo   [1] Blindar e Embaralhar Sprites (zUniD.spr)
echo   [2] Criptografar Scripts e Modulos (Lua Bytecode + AV03)
echo   [3] Blindagem Completa (Sprites + Scripts + Modulos)
echo   [4] Sair
echo.
echo ================================================================
set /p OPT="Escolha uma opcao [1-4]: "

if "%OPT%"=="1" goto PROTECT_SPRITES
if "%OPT%"=="2" goto PROTECT_SCRIPTS
if "%OPT%"=="3" goto PROTECT_ALL
if "%OPT%"=="4" exit /b 0
goto MENU

:PROTECT_SPRITES
echo.
echo ================================================================
echo [1/2] Fazendo backup de seguranca do zUniD.spr...
echo ================================================================
if not exist "%SPR_FILE%" (
    echo [ERRO] Arquivo "%SPR_FILE%" nao encontrado!
    pause
    goto MENU
)
if not exist "%SPR_FILE%.backup_original" (
    echo Criando backup original: %SPR_FILE%.backup_original
    copy /y "%SPR_FILE%" "%SPR_FILE%.backup_original" >nul
)

echo.
echo [2/2] Criptografando e embaralhando sprites...
echo Isso pode levar de 1 a 3 minutos dependendo do tamanho do seu .spr.
echo Por favor, aguarde...
echo.
"%CLIENT_EXE%" --encrypt-sprites "%SPR_FILE%" "%SPR_FILE%.temp"

if exist "%SPR_FILE%.temp" (
    move /y "%SPR_FILE%.temp" "%SPR_FILE%" >nul
    echo.
    echo ================================================================
    echo [SUCESSO] Sprites blindadas e embaralhadas com sucesso!
    echo O arquivo zUniD.spr agora esta protegido com assinatura AVSP.
    echo Ferramentas publicas como Object Builder nao conseguem mais abri-lo.
    echo ================================================================
) else (
    echo [ERRO] Falha ao gerar o arquivo de sprites criptografado.
)
pause
goto MENU

:PROTECT_SCRIPTS
echo.
echo ================================================================
echo Criptografando scripts Lua (Bytecode) e Modulos (AV03)...
echo ================================================================
set /p SEED="Digite uma chave/seed de criptografia (ou aperte ENTER para chave padrao): "
if "%SEED%"=="" set SEED=AvatarEclipse2026MasterKey

echo Processando arquivos com a seed informada...
"%CLIENT_EXE%" --encrypt "%SEED%"
echo.
echo ================================================================
echo [SUCESSO] Scripts compilados em Bytecode e encriptados com sucesso!
echo ================================================================
pause
goto MENU

:PROTECT_ALL
echo.
echo ================================================================
echo INICIANDO BLINDAGEM COMPLETA DO AVATAR ECLIPSE
echo ================================================================
echo.

if not exist "%SPR_FILE%.backup_original" (
    echo Criando backup original: %SPR_FILE%.backup_original
    copy /y "%SPR_FILE%" "%SPR_FILE%.backup_original" >nul
)

echo [Passo 1] Criptografando e embaralhando zUniD.spr...
"%CLIENT_EXE%" --encrypt-sprites "%SPR_FILE%" "%SPR_FILE%.temp"
if exist "%SPR_FILE%.temp" (
    move /y "%SPR_FILE%.temp" "%SPR_FILE%" >nul
    echo [Passo 1 OK] Sprites blindadas com sucesso!
) else (
    echo [AVISO] Falha ao gerar sprites blindadas.
)

echo.
echo [Passo 2] Compilando Lua em bytecode e criptografando modulos...
"%CLIENT_EXE%" --encrypt AvatarEclipse2026MasterKey
echo [Passo 2 OK] Modulos e scripts criptografados!

echo.
echo ================================================================
echo [CONCLUIDO] Todos os assets foram protegidos com sucesso!
echo ================================================================
pause
goto MENU
