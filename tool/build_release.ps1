param([switch]$RunChecks)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$previousJavaHome = $env:JAVA_HOME
if (-not (Test-Path -LiteralPath 'D:\jdk17\bin\java.exe')) { throw 'JDK 17 not found at D:\jdk17' }
# Android JDK image transforms fail with the host JDK 26.
$env:JAVA_HOME = 'D:\jdk17'
if ($RunChecks) {
    & node (Join-Path $projectRoot 'tool\check_login_bridge.mjs')
    if ($LASTEXITCODE) { throw 'Login bridge checks failed' }
}
$signing = Get-Content -LiteralPath (Join-Path $projectRoot 'android\signing.local.json') -Raw | ConvertFrom-Json
$env:MT_STORE_PASSWORD = $signing.password
$env:JAVA_TOOL_OPTIONS = '-Dfile.encoding=UTF-8 -Djdk.net.unixdomain.tmpdir=C:\Windows\Temp'
# The Flutter Windows batch wrapper stalls before launching Dart in this host.
$dart = 'D:\flutter_sdk\bin\cache\dart-sdk\bin\dart.exe'
$flutterPackages = 'D:\flutter_sdk\packages\flutter_tools\.dart_tool\package_config.json'
$flutterSnapshot = 'D:\flutter_sdk\bin\cache\flutter_tools.snapshot'
function Invoke-FlutterTool([string[]]$FlutterArguments) {
    & $dart "--packages=$flutterPackages" $flutterSnapshot @FlutterArguments
    if ($LASTEXITCODE) { throw "Flutter command failed: $($FlutterArguments -join ' ')" }
}
$releaseRoot = Join-Path $env:TEMP ('mt-forum-release-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $releaseRoot | Out-Null
# Native AOT/JNI tools fail under the Chinese checkout path; build an exact source snapshot.
$sourceFolders = @('lib', 'assets', 'packages')
if ($RunChecks) { $sourceFolders += 'test' }
foreach ($folder in $sourceFolders) { Copy-Item -LiteralPath (Join-Path $projectRoot $folder) -Destination $releaseRoot -Recurse }
foreach ($name in @('pubspec.yaml','pubspec.lock','analysis_options.yaml')) { Copy-Item -LiteralPath (Join-Path $projectRoot $name) -Destination $releaseRoot }
& robocopy (Join-Path $projectRoot 'android') (Join-Path $releaseRoot 'android') /E /XD .gradle build .cxx /XF signing.local.json /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -gt 7) { throw 'Android source copy failed' }
Push-Location $releaseRoot
try {
    Invoke-FlutterTool @('pub', 'get', '--offline')
    if ($RunChecks) {
        Invoke-FlutterTool @('test', '--no-pub', 'test/forum_test.dart', 'test/widget_test.dart', 'test/native_forum_test.dart', 'test/preview_test.dart', 'test/thread_ui_test.dart', 'test/collection_test.dart', '--reporter', 'expanded')
        foreach ($preview in @('preview-dark.png', 'preview-light.png', 'preview-reply-dark.png', 'preview-reply-light.png', 'preview-account-dark.png', 'preview-account-light.png', 'preview-board-dark.png', 'preview-board-light.png', 'preview-profile-dark.png', 'preview-profile-light.png', 'preview-ranking-dark.png', 'preview-ranking-light.png', 'preview-latest-dark.png', 'preview-latest-light.png', 'preview-sign-dark.png', 'preview-sign-light.png', 'preview-messages-dark.png', 'preview-messages-light.png', 'preview-quote-dark.png', 'preview-quote-light.png', 'preview-thread-dark.png', 'preview-thread-light.png', 'preview-composer-dark.png', 'preview-composer-light.png', 'preview-favorites-dark.png', 'preview-favorites-light.png', 'preview-history-dark.png', 'preview-history-light.png', 'preview-messages-tab-dark.png', 'preview-messages-tab-light.png', 'preview-messages-scaled-dark.png')) {
            Copy-Item -LiteralPath (Join-Path $releaseRoot ('docs\' + $preview)) -Destination (Join-Path $projectRoot ('docs\' + $preview))
        }
    }
    $encoded = (Get-Content -LiteralPath (Join-Path $projectRoot 'build\final-gradle-defines.txt') -Raw).Trim().Split(',')
    $buildVersion = ((Select-String -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Pattern '^version: ').Line -replace '^version:\s*','').Trim().Split('+')
    $propertiesPath = Join-Path $releaseRoot 'android\local.properties'
    $properties = Get-Content -LiteralPath $propertiesPath -Raw
    foreach ($entry in @{ 'flutter.versionName' = $buildVersion[0]; 'flutter.versionCode' = $buildVersion[1] }.GetEnumerator()) {
        $pattern = '(?m)^' + [regex]::Escape($entry.Key) + '=.*$'
        if ($properties -match $pattern) { $properties = $properties -replace $pattern, ($entry.Key + '=' + $entry.Value) }
        else { $properties = $properties.TrimEnd() + "`n" + $entry.Key + '=' + $entry.Value + "`n" }
    }
    Set-Content -LiteralPath $propertiesPath -Value $properties -Encoding utf8
    $utf8 = [System.Text.Encoding]::UTF8
    $encoded[0] = [Convert]::ToBase64String($utf8.GetBytes("FLUTTER_BUILD_NAME=$($buildVersion[0])"))
    $encoded[1] = [Convert]::ToBase64String($utf8.GetBytes("FLUTTER_BUILD_NUMBER=$($buildVersion[1])"))
    Push-Location (Join-Path $releaseRoot 'android')
    try {
        & .\gradlew.bat --offline --console=plain '-Ptarget-platform=android-arm64' '-Ptarget=lib/main.dart' '-Pbase-application-name=android.app.Application' ('-Pdart-defines='+($encoded -join ',')) '-Pdart-obfuscation=false' '-Ptrack-widget-creation=false' '-Ptree-shake-icons=true' assembleRelease
        if ($LASTEXITCODE) { throw 'Offline Android ARM64 release build failed' }
    } finally { Pop-Location }
    $apk = Join-Path $releaseRoot 'build\app\outputs\flutter-apk\app-release.apk'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($apk)
    try {
        $abis = @($archive.Entries.FullName | ForEach-Object { if ($_ -match '^lib/([^/]+)/') { $Matches[1] } } | Select-Object -Unique)
        if ($abis.Count -ne 1 -or $abis[0] -ne 'arm64-v8a') { throw "Unexpected APK ABIs: $abis" }
    } finally { $archive.Dispose() }
    $sdkTools = Join-Path $env:LOCALAPPDATA 'Android\Sdk\build-tools\37.0.0'
    $badging = & (Join-Path $sdkTools 'aapt.exe') dump badging $apk
    if ($LASTEXITCODE -or $badging[0] -notmatch "name='bbs.binmt.cc' versionCode='20' versionName='1.0.0'") { throw 'Package or version mismatch' }
    & (Join-Path $sdkTools 'apksigner.bat') verify $apk
    if ($LASTEXITCODE) { throw 'Signature verification failed' }
    $destination = Join-Path $projectRoot 'MT论坛_v1.0.0_arm64.apk'
    Copy-Item -LiteralPath $apk -Destination $destination
    $releaseRoot | Set-Content -LiteralPath (Join-Path $projectRoot 'build\release-source-path.txt')
    Get-FileHash -LiteralPath $destination -Algorithm SHA256
} finally {
    Pop-Location
    $env:JAVA_HOME = $previousJavaHome
    Remove-Item Env:MT_STORE_PASSWORD
}

