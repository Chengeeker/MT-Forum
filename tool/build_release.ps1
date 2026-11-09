param([switch]$Offline, [string]$BuildDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'build_temp.ps1')
$tempSession = Enter-ForumBuildTemp $root
try {
    $env:JAVA_HOME = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { Join-Path $env:USERPROFILE '.gradle/jdks/eclipse_adoptium-21-amd64-windows.2' }
    $signing = Get-Content -LiteralPath (Join-Path $root 'signing\signing.local.json') -Raw | ConvertFrom-Json
    $env:MT_STORE_PASSWORD = $signing.password
    $env:MT_KEYSTORE = Join-Path $root 'signing\release-signing.p12'
    if ($BuildDirectory) {
        $requested = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BuildDirectory).TrimEnd('\')
        if ((Split-Path -Parent $requested) -ne $tempSession.Root) {
            throw '-BuildDirectory must point to a direct child of the project tmp directory.'
        }
        $snapshotName = Split-Path -Leaf $requested
    } else {
        $snapshotName = 'mt-compose-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    }
    $realSnapshot = Join-Path $tempSession.Root $snapshotName
    if ((Test-Path -LiteralPath $realSnapshot) -and
        ((Get-Item -LiteralPath $realSnapshot).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The build snapshot must be a local directory.'
    }
    $snapshot = Join-Path "$($tempSession.Drive)\" $snapshotName
    New-Item -ItemType Directory -Force -Path $snapshot | Out-Null
    & robocopy $root $snapshot /E /XJ /XD build tmp signing .gradle .git .idea .agents .codex /XF '*.apk' '*.local.json' '*.p12' '*.bks' '*.log' /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) { throw 'Source snapshot failed' }
    ('sdk.dir=' + ($env:LOCALAPPDATA + '\Android\Sdk').Replace('\','\\')) | Set-Content -LiteralPath (Join-Path $snapshot 'local.properties') -Encoding ascii
    Push-Location $snapshot
    try {
        $arguments = @('--console=plain', '--no-daemon', 'testReleaseUnitTest', 'assembleRelease')
        if ($Offline) { $arguments += '--offline' }
        & .\gradlew.bat @arguments
        if ($LASTEXITCODE) { throw 'Compose tests or build failed' }
    } finally { Pop-Location }
    $apk = Join-Path $snapshot 'app\build\outputs\apk\release\app-release.apk'
    $sdkTools = Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools\37.0.0'
    $signature = & (Join-Path $sdkTools 'apksigner.bat') verify --print-certs $apk
    if ($LASTEXITCODE) { throw 'Signature verification failed' }
    if (-not ($signature -match '3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975')) { throw 'Signing identity differs from Flutter baseline' }
    $signature
    & (Join-Path $sdkTools 'zipalign.exe') -c -P 16 4 $apk
    if ($LASTEXITCODE) { throw 'APK alignment failed' }
    $badging = & (Join-Path $sdkTools 'aapt.exe') dump badging $apk
    if ($LASTEXITCODE -or $badging[0] -notlike "*name='bbs.binmt.cc' versionCode='71' versionName='1.6.19'*") { throw 'Unexpected package/version' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($apk)
    try {
        $abis = @($zip.Entries.FullName | ForEach-Object { if ($_ -match '^lib/([^/]+)/') { $Matches[1] } } | Select-Object -Unique)
        if ($abis.Count -ne 1 -or $abis[0] -ne 'arm64-v8a') { throw 'Unexpected native ABIs' }
        if ($zip.Entries.FullName -match 'libflutter.so|libapp.so|flutter_assets/') { throw 'Unexpected Flutter runtime' }
    } finally { $zip.Dispose() }
    $output = Join-Path $root 'MT论坛_v1.6.19_arm64.apk'
    Copy-Item -LiteralPath $apk -Destination $output
    New-Item -ItemType Directory -Force (Join-Path $root 'build') | Out-Null
    Copy-Item -LiteralPath (Join-Path $snapshot 'app\build\test-results\testReleaseUnitTest') -Destination (Join-Path $root 'build') -Recurse -Force
    [pscustomobject]@{Source=$realSnapshot;Package=$badging[0];Abis=$abis;Sha256=(Get-FileHash -LiteralPath $output).Hash;DeviceTested=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'build\verification.json')
    Get-FileHash -LiteralPath $output
} finally {
    Exit-ForumBuildTemp $tempSession
}
