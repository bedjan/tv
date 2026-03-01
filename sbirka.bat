@echo off
set "outputFile=%~dp0katalog_disku_E.html"

echo Generuji aktualni seznam souboru...

:: Spuštění PowerShellu pro vytvoření HTML
powershell -NoProfile -Command "$ErrorActionPreference = 'SilentlyContinue'; Get-ChildItem -Path 'E:\Torrent_cele', 'E:\Download' -Recurse | Select-Object FullName, @{Name='Velikost(MB)';Expression={'{0:N2}' -f ($_.Length / 1MB)}}, LastWriteTime | ConvertTo-Html -Title 'Katalog disku E' | Out-File -FilePath '%outputFile%' -Force -Encoding utf8"

echo Seznam vytvoren. Oteviram v prohlizeci...

:: Logika pro otevření prohlížeče
where firefox >nul 2>nul
if %ERRORLEVEL% equ 0 (
    start firefox "%outputFile%"
) else (
    where chrome >nul 2>nul
    if %ERRORLEVEL% equ 0 (
        start chrome "%outputFile%"
    ) else (
        :: Pokud neni Firefox ani Chrome, otevre vychozi prohlizec ve Windows
        start "" "%outputFile%"
    )
)

echo Vse hotovo!
timeout /t 3
