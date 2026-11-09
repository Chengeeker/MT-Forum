function Enter-ForumBuildTemp([string]$ProjectRoot) {
    $tempRoot = (New-Item -ItemType Directory -Force -Path (Join-Path $ProjectRoot 'tmp')).FullName
    if ((Get-Item -LiteralPath $tempRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'The project tmp directory must be a local directory.'
    }

    # Some native build tools need an ASCII path even though the checkout has a Chinese name.
    $occupied = @([IO.DriveInfo]::GetDrives().Name)
    $drive = $null
    foreach ($letter in 'Z','Y','X','W','V','U','T','S','R') {
        if ("${letter}:\" -in $occupied) { continue }
        & subst.exe "${letter}:" $tempRoot | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $drive = "${letter}:"
            break
        }
    }
    if (!$drive) { throw 'Could not map an ASCII drive for the project tmp directory.' }

    $previous = @{}
    foreach ($name in 'TEMP','TMP','JAVA_TOOL_OPTIONS','JAVA_HOME','MT_STORE_PASSWORD','MT_KEYSTORE') {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    $session = [pscustomobject]@{ Root=$tempRoot; Drive=$drive; Previous=$previous }
    try {
        $runtime = Join-Path "$drive\" ('runtime-' + [guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Path $runtime | Out-Null
        $env:TEMP = $runtime
        $env:TMP = $runtime
        $env:JAVA_TOOL_OPTIONS = "-Dfile.encoding=UTF-8 -Djava.io.tmpdir=$runtime -Djdk.net.unixdomain.tmpdir=$runtime"
        return $session
    } catch {
        Exit-ForumBuildTemp $session
        throw
    }
}

function Exit-ForumBuildTemp($Session) {
    foreach ($name in $Session.Previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $Session.Previous[$name], 'Process')
    }
    & subst.exe $Session.Drive /D | Out-Null
    if ($LASTEXITCODE) { Write-Warning "Could not release build drive $($Session.Drive)" }
}
