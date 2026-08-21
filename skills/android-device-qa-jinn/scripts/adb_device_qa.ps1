param(
  [Parameter(Mandatory=$true, Position=0)] [ValidateSet('list','install','launch','foreground','root-id','clear-logcat','pull','collect','guard','tap','swipe','input-text','back','screenshot','ui-dump','snapshot','logcat')] [string]$Action,
  [string]$Serial,
  [string]$Package,
  [string]$Apk,
  [string]$RemotePath,
  [string]$OutDir = '.\artifacts',
  [string]$OutFile,
  [string]$Text,
  [int]$X, [int]$Y,
  [int]$X1, [int]$Y1, [int]$X2, [int]$Y2,
  [int]$DurationSec = 30,
  [int]$IntervalMs = 500
)

$ErrorActionPreference = 'Stop'

function Invoke-Adb([string[]]$AdbArgs) {
  & adb @AdbArgs
  if ($LASTEXITCODE -ne 0) { throw "adb failed with exit code $LASTEXITCODE" }
}

function Require-Serial {
  if ([string]::IsNullOrWhiteSpace($Serial)) { throw 'A device serial is required. Run: adb devices -l' }
  & adb -s $Serial get-state 1>$null 2>$null
  if ($LASTEXITCODE -ne 0) { throw "Device is not available or authorized: $Serial" }
}

function Ensure-Dir([string]$Path) {
  New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Ensure-Parent([string]$Path) {
  $parent = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($parent)) { Ensure-Dir $parent }
}

function Pull-Screenshot([string]$Target) {
  $remote = '/data/local/tmp/codex_device_qa_screen.png'
  Invoke-Adb @('-s',$Serial,'shell','screencap','-p',$remote)
  Invoke-Adb @('-s',$Serial,'pull',$remote,$Target)
  Invoke-Adb @('-s',$Serial,'shell','rm',$remote)
}

function Pull-UiXml([string]$Target) {
  $remote = '/data/local/tmp/codex_device_qa_ui.xml'
  try {
    Invoke-Adb @('-s',$Serial,'shell','uiautomator','dump','--compressed',$remote)
    Invoke-Adb @('-s',$Serial,'pull',$remote,$Target)
  } finally {
    & adb -s $Serial shell rm -f $remote 1>$null 2>$null
  }
}

function Capture-UiOrError([string]$Target, [string]$ErrorTarget) {
  try {
    Pull-UiXml $Target
    return $true
  } catch {
    Ensure-Parent $ErrorTarget
    $_.Exception.Message | Set-Content -LiteralPath $ErrorTarget -Encoding UTF8
    return $false
  }
}

function Get-ForegroundPackage {
  $lines = & adb -s $Serial shell dumpsys activity activities 2>$null
  foreach ($line in $lines) {
    if ($line -match 'mResumedActivity|mCurrentFocus|topResumedActivity') {
      if ($line -match '\s([A-Za-z0-9._-]+)/[A-Za-z0-9_.$-]+') { return $Matches[1] }
    }
  }
  return ''
}

function Pull-Remote([string]$Path, [string]$TargetDir) {
  if ([string]::IsNullOrWhiteSpace($Path)) { throw 'RemotePath is required.' }
  if ($Path -notmatch '^[A-Za-z0-9_./-]+$') { throw 'RemotePath contains unsupported shell characters.' }
  Ensure-Dir $TargetDir
  & adb -s $Serial pull $Path $TargetDir
  if ($LASTEXITCODE -eq 0) { return }

  $tmp = "/data/local/tmp/codex_device_qa_pull_$PID"
  & adb -s $Serial shell su -c "rm -rf $tmp; cp -r $Path $tmp"
  if ($LASTEXITCODE -ne 0) { throw "Could not pull remote path with ADB or read-only root fallback: $Path" }
  try {
    Invoke-Adb @('-s',$Serial,'pull',$tmp,$TargetDir)
  } finally {
    & adb -s $Serial shell su -c "rm -rf $tmp" 1>$null 2>$null
  }
}

function Write-Logcat([string]$Target, [string]$TargetPackage) {
  Ensure-Parent $Target
  if ([string]::IsNullOrWhiteSpace($TargetPackage)) {
    & adb -s $Serial logcat -d | Set-Content -LiteralPath $Target -Encoding UTF8
  } else {
    $pidValue = (& adb -s $Serial shell pidof -s $TargetPackage 2>$null).Trim()
    if ($pidValue) { & adb -s $Serial logcat -d --pid $pidValue | Set-Content -LiteralPath $Target -Encoding UTF8 }
    else { & adb -s $Serial logcat -b crash -d | Set-Content -LiteralPath $Target -Encoding UTF8 }
  }
}

function Validate-Point([int]$PointX, [int]$PointY) {
  if ($PointX -lt 0 -or $PointY -lt 0) { throw 'Coordinates must be non-negative.' }
}

switch ($Action) {
  'list' { Invoke-Adb @('devices','-l'); break }
  'install' {
    Require-Serial
    if ([string]::IsNullOrWhiteSpace($Apk)) { throw 'APK path is required.' }
    if (-not (Test-Path -LiteralPath $Apk -PathType Leaf)) { throw "APK not found: $Apk" }
    Invoke-Adb @('-s',$Serial,'install','-r',$Apk)
    break
  }
  'launch' {
    Require-Serial
    if ([string]::IsNullOrWhiteSpace($Package)) { throw 'Package is required.' }
    $resolved = (& adb -s $Serial shell cmd package resolve-activity --brief $Package 2>$null | Select-Object -Last 1).Trim()
    if ([string]::IsNullOrWhiteSpace($resolved) -or $resolved -notmatch '/') { throw "Could not resolve launch activity for $Package" }
    Invoke-Adb @('-s',$Serial,'shell','am','start','-n',$resolved)
    break
  }
  'root-id' {
    Require-Serial
    $rootOutput = & adb -s $Serial shell su -c id 2>&1
    if ($LASTEXITCODE -eq 0 -and ($rootOutput -match 'uid=0')) {
      Write-Output 'ROOT_AVAILABLE'
    } elseif ($rootOutput) {
      Write-Output 'SU_PRESENT_NOT_ROOT'
      Write-Output $rootOutput
    } else {
      Write-Output 'ROOT_UNAVAILABLE'
    }
    break
  }
  'clear-logcat' {
    Require-Serial
    Invoke-Adb @('-s',$Serial,'logcat','-c')
    Write-Output 'LOGCAT_CLEARED'
    break
  }
  'pull' {
    Require-Serial
    Pull-Remote $RemotePath $OutDir
    Write-Output $OutDir
    break
  }
  'collect' {
    Require-Serial
    if ([string]::IsNullOrWhiteSpace($Package)) { throw 'Package is required.' }
    Ensure-Dir $OutDir
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $png = Join-Path $OutDir "screen-$stamp.png"
    $xml = Join-Path $OutDir "ui-$stamp.xml"
    $meta = Join-Path $OutDir "device-$stamp.txt"
    $fg = Join-Path $OutDir "foreground-$stamp.txt"
    $logs = Join-Path $OutDir "logcat-$stamp.txt"
    Pull-Screenshot $png
    $uiOk = Capture-UiOrError $xml (Join-Path $OutDir "ui-error-$stamp.txt")
    & adb -s $Serial shell getprop | Set-Content -LiteralPath $meta -Encoding UTF8
    & adb -s $Serial shell dumpsys activity activities | Set-Content -LiteralPath $fg -Encoding UTF8
    Write-Logcat $logs $Package
    $root = & adb -s $Serial shell su -c id 2>&1
    $root | Set-Content -LiteralPath (Join-Path $OutDir "root-$stamp.txt") -Encoding UTF8
    if (-not [string]::IsNullOrWhiteSpace($RemotePath)) { Pull-Remote $RemotePath (Join-Path $OutDir 'diagnostics') }
    [PSCustomObject]@{ Screenshot=$png; UiXml=$xml; UiAvailable=$uiOk; Metadata=$meta; Foreground=$fg; Logcat=$logs; DiagnosticsPath=$RemotePath } | Format-List
    break
  }
  'guard' {
    Require-Serial
    if ([string]::IsNullOrWhiteSpace($Package)) { throw 'Package is required.' }
    if ($DurationSec -lt 1 -or $IntervalMs -lt 100) { throw 'DurationSec must be positive and IntervalMs must be at least 100.' }
    $deadline = (Get-Date).AddSeconds($DurationSec)
    while ((Get-Date) -lt $deadline) {
      $current = Get-ForegroundPackage
      if ($current -ne $Package) {
        Write-Output "USER_INTERFERENCE target=$Package foreground=$current"
        exit 2
      }
      Start-Sleep -Milliseconds $IntervalMs
    }
    Write-Output "GUARD_OK target=$Package duration_seconds=$DurationSec"
    break
  }
  'foreground' {
    Require-Serial
    & adb -s $Serial shell dumpsys activity activities 2>$null | Select-String 'mResumedActivity|mCurrentFocus|topResumedActivity'
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect foreground activity.' }
    break
  }
  'tap' { Require-Serial; Validate-Point $X $Y; Invoke-Adb @('-s',$Serial,'shell','input','tap',"$X","$Y"); break }
  'swipe' { Require-Serial; Validate-Point $X1 $Y1; Validate-Point $X2 $Y2; Invoke-Adb @('-s',$Serial,'shell','input','swipe',"$X1","$Y1","$X2","$Y2"); break }
  'input-text' {
    Require-Serial
    if ($null -eq $Text) { throw 'Text is required.' }
    $safeText = $Text.Replace(' ', '%s')
    Invoke-Adb @('-s',$Serial,'shell','input','text',$safeText)
    break
  }
  'back' { Require-Serial; Invoke-Adb @('-s',$Serial,'shell','input','keyevent','4'); break }
  'screenshot' {
    Require-Serial; Ensure-Dir $OutDir
    if ([string]::IsNullOrWhiteSpace($OutFile)) { $OutFile = Join-Path $OutDir ("screen-{0}.png" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) }
    Pull-Screenshot $OutFile
    Write-Output $OutFile
    break
  }
  'ui-dump' {
    Require-Serial; Ensure-Dir $OutDir
    if ([string]::IsNullOrWhiteSpace($OutFile)) { $OutFile = Join-Path $OutDir ("ui-{0}.xml" -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff')) }
    Pull-UiXml $OutFile
    Write-Output $OutFile
    break
  }
  'snapshot' {
    Require-Serial; Ensure-Dir $OutDir
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $png = Join-Path $OutDir "screen-$stamp.png"
    $xml = Join-Path $OutDir "ui-$stamp.xml"
    $meta = Join-Path $OutDir "device-$stamp.txt"
    Pull-Screenshot $png
    $uiOk = Capture-UiOrError $xml (Join-Path $OutDir "ui-error-$stamp.txt")
    & adb -s $Serial shell getprop | Set-Content -LiteralPath $meta -Encoding UTF8
    [PSCustomObject]@{ Screenshot=$png; UiXml=$xml; UiAvailable=$uiOk; Metadata=$meta } | Format-List
    break
  }
  'logcat' {
    Require-Serial
    if ([string]::IsNullOrWhiteSpace($OutFile)) { $OutFile = Join-Path $OutDir 'logcat.txt' }
    Write-Logcat $OutFile $Package
    Write-Output $OutFile
    break
  }
}
