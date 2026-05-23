@echo off
REM Opencode VSCode Extension Build Script for Windows
REM Handles the complete build process for the Opencode VSCode extension.
REM Supports building two variants:
REM   - Standard:  bundles opencode binaries (default)
REM   - GUI-only:  no binaries, uses system opencode, embeds webgui-dist
REM
REM By default both variants are built. Use --gui-only or --standard-only to
REM build a single variant.

setlocal enabledelayedexpansion

REM Resolve key directories
set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%..\.."
for %%I in ("%ROOT_DIR%") do set "ROOT_DIR=%%~fI"
set "PLUGIN_DIR=%ROOT_DIR%\hosts\vscode-plugin"
set "WEBGUI_DIR=%ROOT_DIR%\packages\opencode\webgui"
set "WEBGUI_DIST=%ROOT_DIR%\packages\opencode\webgui-dist"

if not exist "%PLUGIN_DIR%\package.json" (
    echo [ERROR] package.json not found. Please run this script from the repository root.
    exit /b 1
)

echo Opencode VSCode Extension Build Script
echo Plugin directory: %PLUGIN_DIR%
echo Root directory: %ROOT_DIR%

set "BUILD_TYPE=development"
set "SKIP_BINARIES=false"
set "SKIP_TESTS=false"
set "PACKAGE_ONLY=false"
set "BUILD_STANDARD=true"
set "BUILD_GUI_ONLY=true"

:parse_args
if "%~1"=="" goto args_done
if "%~1"=="--production" (
    set "BUILD_TYPE=production"
    shift
    goto parse_args
)
if "%~1"=="--skip-binaries" (
    set "SKIP_BINARIES=true"
    shift
    goto parse_args
)
if "%~1"=="--skip-tests" (
    set "SKIP_TESTS=true"
    shift
    goto parse_args
)
if "%~1"=="--package-only" (
    set "PACKAGE_ONLY=true"
    shift
    goto parse_args
)
if "%~1"=="--gui-only" (
    set "BUILD_STANDARD=false"
    set "BUILD_GUI_ONLY=true"
    shift
    goto parse_args
)
if "%~1"=="--standard-only" (
    set "BUILD_STANDARD=true"
    set "BUILD_GUI_ONLY=false"
    shift
    goto parse_args
)
if "%~1"=="--help" (
    echo Usage: %0 [OPTIONS]
    echo   --production      Build for production (default: development)
    echo   --skip-binaries   Skip building backend binaries
    echo   --skip-tests      Skip running tests
    echo   --package-only    Only create the .vsix package (skip compilation)
    echo   --gui-only        Build only the gui-only variant (no binaries)
    echo   --standard-only   Build only the standard variant (with binaries)
    echo   --help            Show this help message
    exit /b 0
)
echo [ERROR] Unknown option: %~1
exit /b 1

:args_done

echo [INFO] Building VSCode extension in %BUILD_TYPE% mode
if "%BUILD_STANDARD%"=="true" echo [INFO]   Variant: standard (with binaries)
if "%BUILD_GUI_ONLY%"=="true" echo [INFO]   Variant: gui-only (system opencode)

cd /d "%PLUGIN_DIR%"

REM --- Shared preparation (compile once, package per-variant) ---

if "%PACKAGE_ONLY%"=="false" (
    echo [INFO] Cleaning previous build artifacts...
    if not exist "node_modules" (
        echo [WARN] Dependencies not installed; skipping script clean and removing artifacts manually.
        if exist "out" rmdir /s /q "out"
        del /f /q *.vsix 2>nul
    ) else (
        call pnpm run clean 2>nul
        if errorlevel 1 (
            echo [WARN] Clean command failed, applying fallback removal...
            if exist "out" rmdir /s /q "out"
            del /f /q *.vsix 2>nul
        )
    )
)

if "%PACKAGE_ONLY%"=="false" (
    echo [INFO] Installing dependencies...
    where pnpm >nul 2>&1
    if not errorlevel 1 (
        call pnpm install
    ) else (
        where npm >nul 2>&1
        if errorlevel 1 (
            echo [ERROR] Neither pnpm nor npm found. Please install a package manager.
            exit /b 1
        )
        call npm install
    )
)

if "%SKIP_BINARIES%"=="false" (
    if "%PACKAGE_ONLY%"=="false" (
        if "%BUILD_STANDARD%"=="true" (
            echo [INFO] Building backend binaries...
            cd /d "%ROOT_DIR%"
            if exist "hosts\scripts\build_opencode.bat" (
                call hosts\scripts\build_opencode.bat
                if errorlevel 1 (
                    echo [ERROR] Backend binary build failed.
                    exit /b 1
                )
            ) else (
                echo [ERROR] Backend build script not found at hosts\scripts\build_opencode.bat
                exit /b 1
            )
            cd /d "%PLUGIN_DIR%"
        )
    )
)

if "%PACKAGE_ONLY%"=="false" (
    echo [INFO] Compiling TypeScript...
    if "%BUILD_TYPE%"=="production" (
        call pnpm run compile:production
    ) else (
        call pnpm run compile
    )
)

if "%PACKAGE_ONLY%"=="false" (
    echo [INFO] Running linter...
    call pnpm run lint
    if errorlevel 1 echo [WARN] Linting failed, continuing with build...
)

if "%SKIP_TESTS%"=="false" (
    if "%PACKAGE_ONLY%"=="false" (
        echo [INFO] Running tests...
        call pnpm run test
        if errorlevel 1 echo [WARN] Tests failed, continuing with build...
    )
)

REM --- Resolve vsce command ---

set "VSCE_CMD=vsce"
where vsce >nul 2>&1
if errorlevel 1 (
    where npx >nul 2>&1
    if not errorlevel 1 (
        set "VSCE_CMD=npx -y @vscode/vsce"
    ) else (
        echo [WARN] vsce not found and npx unavailable; attempting global install via npm
        call npm install -g @vscode/vsce
    )
)

REM Generate timestamp
for /f "tokens=2-4 delims=/ " %%a in ('date /t') do (
    for /f "tokens=1-2 delims=/" %%c in ("%%a") do (
        set "MONTH=%%c"
        set "DAY=%%d"
    )
    set "YEAR=%%b"
)
for /f "tokens=1-2 delims=: " %%a in ('time /t') do (
    set "HOUR=%%a"
    set "MINUTE=%%b"
)
set "TIMESTAMP=%YEAR%%MONTH%%DAY%-%HOUR%%MINUTE%"

REM --- Build helper: package a single variant ---

if "%BUILD_STANDARD%"=="true" (
    call :build_variant_standard
    if errorlevel 1 exit /b 1
)

if "%BUILD_GUI_ONLY%"=="true" (
    call :build_variant_gui_only
    if errorlevel 1 exit /b 1
)

echo [INFO] Build completed successfully!
echo [INFO] Extension packages created in: %PLUGIN_DIR%

echo Packages created:
for %%F in ("%PLUGIN_DIR%\*.vsix") do echo   %%~nxF

endlocal
exit /b 0

REM --- Build variant: standard ---
:build_variant_standard
echo [INFO] === Packaging STANDARD variant ===

cd /d "%PLUGIN_DIR%"

REM Check for required binaries
echo [INFO] Checking for required binaries...
set "MISSING_BINARIES=false"
if not exist "resources\bin\windows\amd64\opencode.exe" (
    echo [WARN] Missing binary: resources\bin\windows\amd64\opencode.exe
    set "MISSING_BINARIES=true"
)
if not exist "resources\bin\macos\amd64\opencode" (
    echo [WARN] Missing binary: resources\bin\macos\amd64\opencode
    set "MISSING_BINARIES=true"
)
if not exist "resources\bin\macos\arm64\opencode" (
    echo [WARN] Missing binary: resources\bin\macos\arm64\opencode
    set "MISSING_BINARIES=true"
)
if not exist "resources\bin\linux\amd64\opencode" (
    echo [WARN] Missing binary: resources\bin\linux\amd64\opencode
    set "MISSING_BINARIES=true"
)
if not exist "resources\bin\linux\arm64\opencode" (
    echo [WARN] Missing binary: resources\bin\linux\arm64\opencode
    set "MISSING_BINARIES=true"
)
if "%MISSING_BINARIES%"=="true" (
    echo [WARN] Some binaries are missing. The extension may not work on all platforms.
    echo [WARN] Run 'hosts\scripts\build_opencode.bat' from the repository root to build all binaries.
)

REM Package with original package.json and .vscodeignore
if "%BUILD_TYPE%"=="production" (
    call %VSCE_CMD% package --no-dependencies --out "opencode-vscode-%TIMESTAMP%.vsix"
) else (
    call %VSCE_CMD% package --pre-release --no-dependencies --out "opencode-vscode-dev-%TIMESTAMP%.vsix"
)
if errorlevel 1 exit /b 1

echo [INFO] Standard variant packaged successfully
exit /b 0

REM --- Build variant: gui-only ---
:build_variant_gui_only
echo [INFO] === Packaging GUI-ONLY variant ===

cd /d "%PLUGIN_DIR%"

REM Always rebuild webgui to pick up source changes
REM The monorepo uses bun workspaces a deps are already installed at root level
echo [INFO] Building webgui...
cd /d "%WEBGUI_DIR%"
where bun >nul 2>&1
if not errorlevel 1 (
    call bun run build
) else (
    call npm run build
)
cd /d "%PLUGIN_DIR%"

if not exist "%WEBGUI_DIST%" (
    echo [ERROR] webgui-dist not found at %WEBGUI_DIST% after build
    exit /b 1
)

REM Copy webgui-dist into plugin resources for embedding
echo [INFO] Embedding webgui-dist into plugin resources...
if exist "resources\webgui-app" rmdir /s /q "resources\webgui-app"
xcopy /s /e /i "%WEBGUI_DIST%" "resources\webgui-app\" >nul

REM Move binaries completely outside the plugin tree so vsce cannot bundle them
set "BIN_STASH=%TEMP%\opencode_bin_stash_%RANDOM%"
if exist "resources\bin" (
    mkdir "%BIN_STASH%"
    robocopy "resources\bin" "%BIN_STASH%\bin" /E /MOV >nul
    if errorlevel 8 (
        echo [WARN] Failed to stash binaries; will rely on .vscodeignore exclusion
    )
)

REM Temporarily swap package.json with gui-only overrides and .vscodeignore
copy "%PLUGIN_DIR%\package.json" "%PLUGIN_DIR%\package.json.bak" >nul
copy "%PLUGIN_DIR%\.vscodeignore" "%PLUGIN_DIR%\.vscodeignore.bak" >nul

REM Deep-merge gui-only overrides into package.json using PowerShell's built-in JSON support
powershell -NoProfile -Command "$b=Get-Content 'package.json'|ConvertFrom-Json;$o=Get-Content 'package.gui-only.json'|ConvertFrom-Json;function m($t,$s){foreach($p in $s.PSObject.Properties){$v=$p.Value;if($v-is[array]-and$t.($p.Name)-is[array]){$a=$t.($p.Name);for($i=0;$i-lt$v.Count;$i++){if($i-lt$a.Count-and$v[$i]-is[pscustomobject]){m $a[$i] $v[$i]}else{$a[$i]=$v[$i]}}}elseif($v-is[pscustomobject]-and$t.($p.Name)-is[pscustomobject]){m $t.($p.Name) $v}else{$t|Add-Member -MemberType NoteProperty -Name $p.Name -Value $v -Force}}};m $b $o;$b|ConvertTo-Json -Depth 100|Set-Content 'package.json'"
if errorlevel 1 (
    echo [ERROR] Failed to merge gui-only package.json overrides
    call :gui_only_cleanup
    exit /b 1
)

REM Swap .vscodeignore
copy "%PLUGIN_DIR%\.vscodeignore.gui-only" "%PLUGIN_DIR%\.vscodeignore" >nul
if errorlevel 1 (
    echo [ERROR] Failed to swap .vscodeignore
    call :gui_only_cleanup
    exit /b 1
)

REM Package gui-only variant
if "%BUILD_TYPE%"=="production" (
    call %VSCE_CMD% package --no-dependencies --out "opencode-vscode-gui-only-%TIMESTAMP%.vsix"
) else (
    call %VSCE_CMD% package --pre-release --no-dependencies --out "opencode-vscode-gui-only-dev-%TIMESTAMP%.vsix"
)
set "PACKAGE_RESULT=%ERRORLEVEL%"

REM Restore originals
call :gui_only_cleanup

if "%PACKAGE_RESULT%"=="1" exit /b 1

echo [INFO] GUI-only variant packaged successfully
exit /b 0

REM --- Cleanup helper for gui-only ---
:gui_only_cleanup
cd /d "%PLUGIN_DIR%"
if exist "package.json.bak" (
    move /y "package.json.bak" "package.json" >nul
)
if exist ".vscodeignore.bak" (
    move /y ".vscodeignore.bak" ".vscodeignore" >nul
)
if exist "%BIN_STASH%\bin" (
    if exist "resources\bin" rmdir /s /q "resources\bin"
    move "%BIN_STASH%\bin" "resources\bin" >nul
)
if exist "%BIN_STASH%" rmdir /s /q "%BIN_STASH%"
if exist "resources\webgui-app" rmdir /s /q "resources\webgui-app"
exit /b 0
