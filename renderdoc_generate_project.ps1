# GameMaker: Studio 2 RenderDoc settings generator script.
# By @odditica. 10/04/20.
# 
# https://github.com/odditica/renderdoc-gms2-kit/
#
# 1) Place this script in the project folder (where the *.yyp file is)
# 2) Start (build) the game in GMS2 and close it.
# 3) Run this script.
# 4) In RenderDoc, load the generated settings file and launch the game.

function bail($message) {
        Write-Host "$message"
        Read-Host -Prompt "Press Enter to exit"
        exit
}

$MODE_NONE=-1
$MODE_VM=0
$MODE_YYC=1

$MODE=$MODE_NONE

$SCRIPT_ROOT = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

cd "$SCRIPT_ROOT"

# Figure out the project name

$PROJECT_FILE = Get-ChildItem -Path "$SCRIPT_ROOT" -Filter "*.yyp" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

$PROJECT_NAME = $PROJECT_FILE.BaseName
if (! $PROJECT_NAME) { 
    bail("*.yyp file not found!")
}

# Find .win file

$TEMP_PATHS = @(
    "$env:LOCALAPPDATA\GameMakerStudio2-LTS2026\GMS2TEMP\",
    "$env:LOCALAPPDATA\GameMakerStudio2\GMS2TEMP\",
    "$env:TEMP\GameMaker\"
)

$TEMP_PATH = $TEMP_PATHS | Where-Object { Test-Path -Path $_ } | Select-Object -First 1

if (! $TEMP_PATH) {
    bail("Base data path not found!`nChecked:`n$($TEMP_PATHS -join "`n")")
}

$BUILD_PATH=Get-ChildItem -Path $TEMP_PATH -Recurse -Include "$($PROJECT_NAME).exe", "$($PROJECT_NAME).win" | Sort-Object LastWriteTime -Descending | Select-Object -first 1 | select -ExpandProperty FullName
if ($BUILD_PATH -match '.exe$') {
    $MODE=$MODE_YYC
} else {
    if ($BUILD_PATH -match '.win$') {
        $MODE=$MODE_VM
    }
}

if ($MODE -eq $MODE_VM) {

    # Find the runner

    $RUNTIME_PATH="$env:ProgramData\GameMakerStudio2\Cache\runtimes\"
    if (! (Test-Path -Path "$RUNTIME_PATH")) {
        bail("Runtime path not found!`n(Expected: $RUNTIME_PATH)")
    }
$SYSTEM_ARCH = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$SYSTEM_ARCH = $SYSTEM_ARCH.ToLower()

$RUNNER_PATH = Get-ChildItem -Path $RUNTIME_PATH -Recurse -Filter "Runner.exe" |
    Where-Object { $_.FullName -like "*\windows\*\Runner.exe" } |
    Sort-Object @{
        Expression = {
            $RUNNER_FOLDER = Split-Path -Leaf (Split-Path -Parent $_.FullName)
            $RUNNER_FOLDER = $RUNNER_FOLDER.ToLower()

            $SCORE = 0

            if ($RUNNER_FOLDER -eq $SYSTEM_ARCH)
            {
                $SCORE += 1000
            }

            for ($i = 0; $i -lt $RUNNER_FOLDER.Length; $i++)
            {
                $CHAR = $RUNNER_FOLDER.Substring($i, 1)

                if ($SYSTEM_ARCH.Contains($CHAR))
                {
                    $SCORE += 10
                }
                else
                {
                    $SCORE -= 10
                }
            }

            for ($i = 0; $i -lt $SYSTEM_ARCH.Length; $i++)
            {
                $CHAR = $SYSTEM_ARCH.Substring($i, 1)

                if ($RUNNER_FOLDER.Contains($CHAR))
                {
                    $SCORE += 1
                }
            }

            -$SCORE
        }
    }, LastWriteTime -Descending |
    Select-Object -First 1 |
    Select-Object -ExpandProperty FullName

    if (! (Test-Path -Path $RUNNER_PATH)) { 
        bail("No runner found!`n(Expected: $RUNNER_PATH)") 
    }
} else {
    if ($MODE -eq $MODE_NONE) {  
        bail("No compatible build found (neither YYC nor VM).")  
    }
}

# Template used to generate the settings file.

$RENDERDOC_JSON_TEMPLATE='{
    "rdocCaptureSettings": 1,
    "settings": {
        "autoStart": false,
        "commandLine": "",
        "environment": [
        ],
        "executable": "",
        "inject": false,
        "numQueuedFrames": 0,
        "options": {
            "allowFullscreen": true,
            "allowVSync": true,
            "apiValidation": false,
            "captureAllCmdLists": false,
            "captureCallstacks": false,
            "captureCallstacksOnlyDraws": false,
            "debugOutputMute": true,
            "delayForDebugger": 0,
            "hookIntoChildren": false,
            "refAllResources": false,
            "verifyBufferAccess": false
        },
        "queuedFrameCap": 0,
        "workingDir": ""
    }
}'

$RENDERDOC_SETTINGS_FILENAME=".\renderdoc_settings_$($PROJECT_NAME).cap"

# If the settings file already exists, only change the required values, otherwise create a new one.

if (Test-Path -Path "$RENDERDOC_SETTINGS_FILENAME") {
    $RENDERDOC_SETTINGS_JSON = Get-Content -Raw -Path "$RENDERDOC_SETTINGS_FILENAME" | ConvertFrom-Json
    if (( $RENDERDOC_SETTINGS_JSON.settings.commandLine -eq $Null ) -or ( $RENDERDOC_SETTINGS_JSON.settings.executable -eq $Null ) ) {
        bail("Existing RenderDoc settings file doesn't contain expected fields. This is likely due to a recent RenderDoc update, meaning this script will need to be updated - please report on GitHub.")
    } 
} else {
    $RENDERDOC_SETTINGS_JSON = $RENDERDOC_JSON_TEMPLATE | ConvertFrom-Json
}

if ($MODE -eq $MODE_VM) {
    $RENDERDOC_SETTINGS_JSON.settings.commandLine="-game `"$($BUILD_PATH)`""
    $RENDERDOC_SETTINGS_JSON.settings.executable = "$RUNNER_PATH"
} else {
    if ($MODE -eq $MODE_YYC) {
        $RENDERDOC_SETTINGS_JSON.settings.commandLine=""
        $RENDERDOC_SETTINGS_JSON.settings.executable = "$BUILD_PATH"
    }
}

$RENDERDOC_SETTINGS_JSON | ConvertTo-Json | Out-File -encoding ascii "$RENDERDOC_SETTINGS_FILENAME"
