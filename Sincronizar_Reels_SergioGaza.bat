@echo off
chcp 65001 >nul
title Extractor y Transcriptor de Reels de @mrsergiogaza para iOS (.ipa)
echo =====================================================================
echo   EXTRACTOR Y TRANSCRIPTOR DE REELS DE @MRSERGIOGAZA PARA IOS (.IPA)
echo =====================================================================
echo.
echo Opciones disponibles:
echo   [1] Abrir navegador para recolectar automaticamente todos los Reels de @mrsergiogaza
echo   [2] Procesar enlaces de urls.txt y/o videos que hayas puesto en raw_reels/
echo.
set /p opcion="Elige una opcion (1 o 2, Enter = 1): "

if "%opcion%"=="2" (
    python "%~dp0scripts\extract_reels.py"
) else (
    python "%~dp0scripts\extract_reels.py" --collect-browser
)

echo.
echo Proceso finalizado. Presiona cualquier tecla para salir...
pause >nul
