param(
    [switch]$IncludeLiveHttpTests
)

# Pruebas automatizadas de reglas de negocio de Active Directory y Controlador HTTP del Backend
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $scriptDir
$adServicePath = Join-Path (Join-Path $projectRoot 'scripts') 'ad-service.ps1'
$serverScriptPath = Join-Path (Join-Path $projectRoot 'scripts') 'server.ps1'

. $adServicePath

$totalTests = 0
$passedTests = 0
$failedTests = 0

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestName,
        [Parameter(Mandatory = $true)]
        [bool]$Condition,
        [string]$FailureMessage = 'La condicion evaluada fue falsa.'
    )

    $script:totalTests++
    if ($Condition) {
        $script:passedTests++
        Write-Host "[PASS] $TestName"
    } else {
        $script:failedTests++
        Write-Host "[FAIL] $TestName -> $FailureMessage"
    }
}

Write-Host "=== 1. Pruebas de Reglas de Negocio (ad-service.ps1) ==="

# Validacion de formato de usuario
Assert-Condition -TestName "Formato valido 'nombre.apellido' es aceptado" `
    -Condition (Test-ValidUsernameFormat -Username 'juan.tamayo')

Assert-Condition -TestName "Formato invalido sin punto es rechazado" `
    -Condition (-not (Test-ValidUsernameFormat -Username 'juantamayo'))

Assert-Condition -TestName "Intento de inyeccion de caracteres especiales es rechazado" `
    -Condition (-not (Test-ValidUsernameFormat -Username 'juan.tamayo; whoami'))

Assert-Condition -TestName "Formato vacio es rechazado en Invoke-UserUnlock (HTTP 400)" `
    -Condition ((Invoke-UserUnlock -Username '').code -eq 'INVALID_FORMAT')

# Escenario 1: Usuario no existe en AD
$unlockCalledScenario1 = $false
$resNotFound = Invoke-UserUnlock -Username 'usuario.inexistente' `
    -GetUserCommand { param($u) return $null } `
    -UnlockAccountCommand { param($u) $script:unlockCalledScenario1 = $true }

Assert-Condition -TestName "Escenario 1 (Usuario inexistente): retorna HTTP 404 y USER_NOT_FOUND" `
    -Condition ($resNotFound.httpStatus -eq 404 -and $resNotFound.code -eq 'USER_NOT_FOUND' -and -not $resNotFound.success)

Assert-Condition -TestName "Escenario 1 (Usuario inexistente): NO ejecuta Unlock-ADAccount" `
    -Condition (-not $unlockCalledScenario1)

# Escenario 2: Usuario INHABILITADO (Disabled) y bloqueado -> Regla de Negocio: NO desbloquear
$unlockCalledScenario2 = $false
$resDisabled = Invoke-UserUnlock -Username 'colaborador.retirado' `
    -GetUserCommand {
        param($u)
        return [PSCustomObject]@{
            SamAccountName = $u
            DisplayName    = 'Colaborador Inhabilitado'
            Enabled        = $false
            LockedOut      = $true
        }
    } `
    -UnlockAccountCommand { param($u) $script:unlockCalledScenario2 = $true }

Assert-Condition -TestName "Escenario 2 (Usuario inhabilitado): retorna HTTP 422 y ACCOUNT_DISABLED" `
    -Condition ($resDisabled.httpStatus -eq 422 -and $resDisabled.code -eq 'ACCOUNT_DISABLED' -and -not $resDisabled.success)

Assert-Condition -TestName "Escenario 2 (Usuario inhabilitado): NO ejecuta Unlock-ADAccount aunque LockedOut sea True" `
    -Condition (-not $unlockCalledScenario2)

# Escenario 3: Usuario HABILITADO (Enabled) pero NO bloqueado (LockedOut = False)
$unlockCalledScenario3 = $false
$resNotLocked = Invoke-UserUnlock -Username 'colaborador.activo' `
    -GetUserCommand {
        param($u)
        return [PSCustomObject]@{
            SamAccountName = $u
            DisplayName    = 'Colaborador Activo'
            Enabled        = $true
            LockedOut      = $false
        }
    } `
    -UnlockAccountCommand { param($u) $script:unlockCalledScenario3 = $true }

Assert-Condition -TestName "Escenario 3 (Usuario habilitado sin bloqueo): retorna HTTP 422 y ACCOUNT_NOT_LOCKED" `
    -Condition ($resNotLocked.httpStatus -eq 422 -and $resNotLocked.code -eq 'ACCOUNT_NOT_LOCKED' -and -not $resNotLocked.success)

Assert-Condition -TestName "Escenario 3 (Usuario habilitado sin bloqueo): NO ejecuta Unlock-ADAccount" `
    -Condition (-not $unlockCalledScenario3)

# Escenario 4: Usuario HABILITADO (Enabled = True) y BLOQUEADO (LockedOut = True)
$unlockCalledScenario4 = $false
$unlockedTargetUser = ''
$resUnlocked = Invoke-UserUnlock -Username 'colaborador.bloqueado' `
    -GetUserCommand {
        param($u)
        return [PSCustomObject]@{
            SamAccountName = $u
            DisplayName    = 'Colaborador Bloqueado'
            Enabled        = $true
            LockedOut      = $true
        }
    } `
    -UnlockAccountCommand {
        param($u)
        $script:unlockCalledScenario4 = $true
        $script:unlockedTargetUser = $u
    }

Assert-Condition -TestName "Escenario 4 (Usuario habilitado y bloqueado): retorna HTTP 200 y UNLOCKED_SUCCESS" `
    -Condition ($resUnlocked.httpStatus -eq 200 -and $resUnlocked.code -eq 'UNLOCKED_SUCCESS' -and $resUnlocked.success)

Assert-Condition -TestName "Escenario 4 (Usuario habilitado y bloqueado): EJECUTA Unlock-ADAccount para el usuario correcto" `
    -Condition ($unlockCalledScenario4 -and $unlockedTargetUser -eq 'colaborador.bloqueado')

Write-Host "=== 2. Pruebas del Controlador API Backend (POST /api/unlock) ==="

$mockAuthSession = [PSCustomObject]@{
    authorized = $true
    message    = 'Sesion autorizada.'
}

$mockUnauthSession = [PSCustomObject]@{
    authorized = $false
    message    = 'Acceso denegado: no pertenece al grupo autorizado.'
}

# 2.1. Sesion no autorizada bloquea ejecucion con HTTP 403
$apiForbidden = Invoke-UnlockApiController -SessionInfo $mockUnauthSession -RawBody '{"username":"juan.tamayo"}'
Assert-Condition -TestName "API: Sesion sin permisos retorna HTTP 403 FORBIDDEN" `
    -Condition ($apiForbidden.httpStatus -eq 403 -and $apiForbidden.body.code -eq 'FORBIDDEN')

# 2.2. Cuerpo vacio retorna HTTP 400
$apiEmpty = Invoke-UnlockApiController -SessionInfo $mockAuthSession -RawBody ''
Assert-Condition -TestName "API: Cuerpo vacio retorna HTTP 400 INVALID_PAYLOAD" `
    -Condition ($apiEmpty.httpStatus -eq 400 -and $apiEmpty.body.code -eq 'INVALID_PAYLOAD')

# 2.3. JSON malformado retorna HTTP 400
$apiBadJson = Invoke-UnlockApiController -SessionInfo $mockAuthSession -RawBody '{username: sin_comillas}'
Assert-Condition -TestName "API: JSON invalido retorna HTTP 400 INVALID_JSON" `
    -Condition ($apiBadJson.httpStatus -eq 400 -and $apiBadJson.body.code -eq 'INVALID_JSON')

# 2.4. JSON sin propiedad username retorna HTTP 400
$apiMissingField = Invoke-UnlockApiController -SessionInfo $mockAuthSession -RawBody '{"user":"juan.tamayo"}'
Assert-Condition -TestName "API: JSON sin campo username retorna HTTP 400 MISSING_USERNAME" `
    -Condition ($apiMissingField.httpStatus -eq 400 -and $apiMissingField.body.code -eq 'MISSING_USERNAME')

# 2.5. Sanitizacion de mayusculas/espacios y desbloqueo exitoso via controlador API
$apiSuccess = Invoke-UnlockApiController -SessionInfo $mockAuthSession -RawBody '{"username":"  Ana.Gomez  "}' `
    -GetUserCommand {
        param($u)
        return [PSCustomObject]@{
            SamAccountName = $u
            DisplayName    = 'Ana Gomez'
            Enabled        = $true
            LockedOut      = $true
        }
    } `
    -UnlockAccountCommand { param($u) }

Assert-Condition -TestName "API: Sanitiza espacios/mayusculas y retorna HTTP 200 con estructura JSON estandar" `
    -Condition ($apiSuccess.httpStatus -eq 200 -and $apiSuccess.body.success -and $apiSuccess.body.user.username -eq 'ana.gomez')

if ($IncludeLiveHttpTests) {
    Write-Host "=== 3. Pruebas Integrales E2E: Frontend + HTTP Server + Active Directory (server.ps1) ==="
    Add-Type -AssemblyName System.Net.Http
    $httpClient = New-Object System.Net.Http.HttpClient
    $testPort = 8085
    $proc = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$serverScriptPath`" -Port $testPort -MaxRequests 6" -NoNewWindow -PassThru
    Start-Sleep -Milliseconds 1500

    try {
        # 3.1. GET / (Entrega de Frontend index.html)
        $resIndex = $httpClient.GetAsync("http://localhost:$testPort/").Result
        $htmlContent = $resIndex.Content.ReadAsStringAsync().Result
        Assert-Condition -TestName "E2E Live: GET / entrega interfaz public/index.html (HTTP 200)" `
            -Condition ([int]$resIndex.StatusCode -eq 200 -and $htmlContent.Contains('Desbloqueo de Usuarios de Dominio') -and $htmlContent.Contains('/api/unlock'))

        # 3.2. GET /favicon.ico (Sin errores 404 en consola del navegador)
        $resFavicon = $httpClient.GetAsync("http://localhost:$testPort/favicon.ico").Result
        Assert-Condition -TestName "E2E Live: GET /favicon.ico responde HTTP 204 No Content" `
            -Condition ([int]$resFavicon.StatusCode -eq 204)

        # 3.3. GET /api/session
        $resSession = $httpClient.GetAsync("http://localhost:$testPort/api/session").Result
        $sessionJson = $resSession.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        Assert-Condition -TestName "E2E Live: GET /api/session autentica sesion de Windows en AD (HTTP 200)" `
            -Condition ([int]$resSession.StatusCode -eq 200 -and $sessionJson.authorized -eq $true -and -not [string]::IsNullOrWhiteSpace($sessionJson.user))

        # 3.4. POST /api/unlock con formato invalido -> HTTP 400 INVALID_FORMAT
        $content400 = New-Object System.Net.Http.StringContent('{"username":"formato_invalido_sin_punto"}', [System.Text.Encoding]::UTF8, 'application/json')
        $res400 = $httpClient.PostAsync("http://localhost:$testPort/api/unlock", $content400).Result
        $body400 = $res400.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        Assert-Condition -TestName "E2E Live: POST /api/unlock formato invalido retorna HTTP 400 INVALID_FORMAT" `
            -Condition ([int]$res400.StatusCode -eq 400 -and $body400.code -eq 'INVALID_FORMAT' -and -not $body400.success)

        # 3.5. POST /api/unlock con usuario inexistente en AD -> HTTP 404 USER_NOT_FOUND
        $content404 = New-Object System.Net.Http.StringContent('{"username":"usuario.inexistente999"}', [System.Text.Encoding]::UTF8, 'application/json')
        $res404 = $httpClient.PostAsync("http://localhost:$testPort/api/unlock", $content404).Result
        $body404 = $res404.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        Assert-Condition -TestName "E2E Live: POST /api/unlock usuario inexistente en AD retorna HTTP 404 USER_NOT_FOUND" `
            -Condition ([int]$res404.StatusCode -eq 404 -and $body404.code -eq 'USER_NOT_FOUND' -and -not $body404.success)

        # 3.6. POST /api/unlock con usuario activo no bloqueado en AD -> HTTP 422 ACCOUNT_NOT_LOCKED
        $payloadActivo = "{`"username`":`"$($sessionJson.user)`"}"
        $content422 = New-Object System.Net.Http.StringContent($payloadActivo, [System.Text.Encoding]::UTF8, 'application/json')
        $res422 = $httpClient.PostAsync("http://localhost:$testPort/api/unlock", $content422).Result
        $body422 = $res422.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        Assert-Condition -TestName "E2E Live: POST /api/unlock cuenta activa sin bloqueo en AD retorna HTTP 422 ACCOUNT_NOT_LOCKED" `
            -Condition ([int]$res422.StatusCode -eq 422 -and $body422.code -eq 'ACCOUNT_NOT_LOCKED' -and -not $body422.success -and $body422.user.enabled -eq $true)
    } finally {
        $httpClient.Dispose()
        $proc.WaitForExit(3000) | Out-Null
        if (-not $proc.HasExited) {
            try { $proc.Kill() } catch {}
        }
    }
}

Write-Host "--------------------------------------------------------"
Write-Host "Total: $totalTests | Aprobadas: $passedTests | Fallidas: $failedTests"

if ($failedTests -gt 0) {
    exit 1
}
