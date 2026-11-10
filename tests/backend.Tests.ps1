param(
    [switch]$IncludeLiveHttpTests,
    [string]$LiveTestPassword = ''
)

if ([string]::IsNullOrWhiteSpace($LiveTestPassword)) {
    $randomNum = Get-Random -Minimum 1000 -Maximum 9999
    $LiveTestPassword = "SoporteTI#${randomNum}xZ!"
}

# Pruebas automatizadas de reglas de negocio de Active Directory y Controlador HTTP del Backend
# RESTRICCION ESTRICTA: Todas las pruebas utilizan unica y exclusivamente la cuenta 'henkia.pruebas'.
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

Write-Host "=== 1. Pruebas de Reglas de Negocio - Desbloqueo (ad-service.ps1) ==="

# Validacion de formato de usuario
Assert-Condition -TestName "Formato valido 'henkia.pruebas' es aceptado" `
    -Condition (Test-ValidUsernameFormat -Username 'henkia.pruebas')

Assert-Condition -TestName "Formato invalido sin punto es rechazado" `
    -Condition (-not (Test-ValidUsernameFormat -Username 'henkiapruebas'))

Assert-Condition -TestName "Intento de inyeccion de caracteres especiales es rechazado" `
    -Condition (-not (Test-ValidUsernameFormat -Username 'henkia.pruebas; whoami'))

Assert-Condition -TestName "Formato vacio es rechazado en Invoke-UserUnlock (HTTP 400)" `
    -Condition ((Invoke-UserUnlock -Username '').code -eq 'INVALID_FORMAT')

# Escenario 1: Usuario no existe en AD (Mock)
$unlockCalledScenario1 = $false
$resNotFound = Invoke-UserUnlock -Username 'henkia.pruebas' `
    -GetUserCommand { param($u) return $null } `
    -UnlockAccountCommand { param($u) $script:unlockCalledScenario1 = $true }

Assert-Condition -TestName "Escenario 1 (Usuario inexistente): retorna HTTP 404 y USER_NOT_FOUND" `
    -Condition ($resNotFound.httpStatus -eq 404 -and $resNotFound.code -eq 'USER_NOT_FOUND' -and -not $resNotFound.success)

Assert-Condition -TestName "Escenario 1 (Usuario inexistente): NO ejecuta Unlock-ADAccount" `
    -Condition (-not $unlockCalledScenario1)

# Escenario 2: Usuario INHABILITADO (Disabled) y bloqueado -> Regla de Negocio: NO desbloquear
$unlockCalledScenario2 = $false
$resDisabled = Invoke-UserUnlock -Username 'henkia.pruebas' `
    -GetUserCommand {
        param($u)
        return [PSCustomObject]@{
            SamAccountName = $u
            DisplayName    = 'Usuario de Pruebas Inhabilitado'
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
$resNotLocked = Invoke-UserUnlock -Username 'henkia.pruebas' `
    -GetUserCommand {
        param($u)
        return [PSCustomObject]@{
            SamAccountName = $u
            DisplayName    = 'Usuario de Pruebas Activo'
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
$resUnlocked = Invoke-UserUnlock -Username 'henkia.pruebas' `
    -GetUserCommand {
        param($u)
        return [PSCustomObject]@{
            SamAccountName = $u
            DisplayName    = 'Usuario de Pruebas Bloqueado'
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

Assert-Condition -TestName "Escenario 4 (Usuario habilitado y bloqueado): EJECUTA Unlock-ADAccount para henkia.pruebas" `
    -Condition ($unlockCalledScenario4 -and $unlockedTargetUser -eq 'henkia.pruebas')

Write-Host "=== 2. Pruebas de Reglas de Negocio - Consulta de Estado y Cambio de Contrasena ==="

# 2.1. Invoke-UserStatusCheck: Cuenta inhabilitada rechaza apertura de modal (HTTP 422)
$statusDisabled = Invoke-UserStatusCheck -Username 'henkia.pruebas' -GetUserCommand {
    param($u)
    return [PSCustomObject]@{
        SamAccountName = $u
        DisplayName    = 'Henkia Pruebas'
        Enabled        = $false
        LockedOut      = $false
    }
}
Assert-Condition -TestName "UserStatusCheck: Cuenta inhabilitada retorna HTTP 422 ACCOUNT_DISABLED" `
    -Condition ($statusDisabled.httpStatus -eq 422 -and $statusDisabled.code -eq 'ACCOUNT_DISABLED' -and -not $statusDisabled.success)

# 2.2. Invoke-UserStatusCheck: Cuenta habilitada retorna HTTP 200 USER_VALID con estado LockedOut
$statusValid = Invoke-UserStatusCheck -Username 'henkia.pruebas' -GetUserCommand {
    param($u)
    return [PSCustomObject]@{
        SamAccountName = $u
        DisplayName    = 'Henkia Pruebas'
        Enabled        = $true
        LockedOut      = $true
    }
}
Assert-Condition -TestName "UserStatusCheck: Cuenta habilitada retorna HTTP 200 USER_VALID y estado lockedOut" `
    -Condition ($statusValid.httpStatus -eq 200 -and $statusValid.code -eq 'USER_VALID' -and $statusValid.user.lockedOut -eq $true)

# 2.3. Invoke-UserPasswordReset: Contrasenas vacias retorna HTTP 400 EMPTY_PASSWORD
$resetEmptyPass = Invoke-UserPasswordReset -Username 'henkia.pruebas' -NewPassword '' -ConfirmPassword ''
Assert-Condition -TestName "PasswordReset: Contrasenas vacias retorna HTTP 400 EMPTY_PASSWORD" `
    -Condition ($resetEmptyPass.httpStatus -eq 400 -and $resetEmptyPass.code -eq 'EMPTY_PASSWORD')

# 2.4. Invoke-UserPasswordReset: Contrasenas que no coinciden retorna HTTP 400 PASSWORD_MISMATCH
$resetMismatch = Invoke-UserPasswordReset -Username 'henkia.pruebas' -NewPassword 'Clave123*' -ConfirmPassword 'Clave999*'
Assert-Condition -TestName "PasswordReset: Contrasenas diferentes retorna HTTP 400 PASSWORD_MISMATCH" `
    -Condition ($resetMismatch.httpStatus -eq 400 -and $resetMismatch.code -eq 'PASSWORD_MISMATCH')

# 2.5. Invoke-UserPasswordReset: Cuenta inhabilitada NO ejecuta Set-ADAccountPassword y retorna HTTP 422
$setPassCalledOnDisabled = $false
$resetDisabled = Invoke-UserPasswordReset `
    -Username 'henkia.pruebas' `
    -NewPassword 'ClaveSegura2026*' `
    -ConfirmPassword 'ClaveSegura2026*' `
    -GetUserCommand {
        param($u)
        return [PSCustomObject]@{
            SamAccountName = $u
            DisplayName    = 'Henkia Pruebas'
            Enabled        = $false
            LockedOut      = $false
        }
    } `
    -SetPasswordCommand { param($u, $sec) $script:setPassCalledOnDisabled = $true }

Assert-Condition -TestName "PasswordReset: Cuenta inhabilitada retorna HTTP 422 y NO cambia la contrasena" `
    -Condition ($resetDisabled.httpStatus -eq 422 -and $resetDisabled.code -eq 'ACCOUNT_DISABLED' -and -not $setPassCalledOnDisabled)

# 2.6. Invoke-UserPasswordReset: Cambio exitoso con ChangePasswordAtLogon = True y UnlockAccount = True
$setPassCalled = $false
$setChangeAtLogonValue = $null
$unlockSimultaneousCalled = $false

$resetSuccess = Invoke-UserPasswordReset `
    -Username 'henkia.pruebas' `
    -NewPassword 'ClaveSegura2026*' `
    -ConfirmPassword 'ClaveSegura2026*' `
    -ChangePasswordAtLogon $true `
    -UnlockAccount $true `
    -GetUserCommand {
        param($u)
        return [PSCustomObject]@{
            SamAccountName = $u
            DisplayName    = 'Henkia Pruebas'
            Enabled        = $true
            LockedOut      = $true
        }
    } `
    -SetPasswordCommand { param($u, $sec) $script:setPassCalled = ($u -eq 'henkia.pruebas' -and $sec -is [System.Security.SecureString]) } `
    -SetChangeAtLogonCommand { param($u, $flag) $script:setChangeAtLogonValue = $flag } `
    -UnlockAccountCommand { param($u) $script:unlockSimultaneousCalled = ($u -eq 'henkia.pruebas') }

Assert-Condition -TestName "PasswordReset: Ejecuta Set-ADAccountPassword con SecureString, Set-ADUser y Unlock-ADAccount" `
    -Condition ($resetSuccess.httpStatus -eq 200 -and $resetSuccess.code -eq 'PASSWORD_RESET_SUCCESS' -and $setPassCalled -and ($setChangeAtLogonValue -eq $true) -and $unlockSimultaneousCalled)

Write-Host "=== 3. Pruebas de Controladores API Backend ==="

$mockAuthSession = [PSCustomObject]@{
    authorized = $true
    message    = 'Sesion autorizada.'
}

$mockUnauthSession = [PSCustomObject]@{
    authorized = $false
    message    = 'Acceso denegado: no pertenece al grupo autorizado.'
}

# 3.1. Sesion no autorizada bloquea todos los controladores con HTTP 403
$apiForbiddenUnlock = Invoke-UnlockApiController -SessionInfo $mockUnauthSession -RawBody '{"username":"henkia.pruebas"}'
$apiForbiddenStatus = Invoke-UserStatusApiController -SessionInfo $mockUnauthSession -RawBody '{"username":"henkia.pruebas"}'
$apiForbiddenReset  = Invoke-PasswordResetApiController -SessionInfo $mockUnauthSession -RawBody '{"username":"henkia.pruebas"}'

Assert-Condition -TestName "API: Sesion sin permisos retorna HTTP 403 FORBIDDEN en todos los endpoints" `
    -Condition ($apiForbiddenUnlock.httpStatus -eq 403 -and $apiForbiddenStatus.httpStatus -eq 403 -and $apiForbiddenReset.httpStatus -eq 403)

# 3.2. Cuerpo vacio retorna HTTP 400
$apiEmpty = Invoke-UnlockApiController -SessionInfo $mockAuthSession -RawBody ''
Assert-Condition -TestName "API: Cuerpo vacio retorna HTTP 400 INVALID_PAYLOAD" `
    -Condition ($apiEmpty.httpStatus -eq 400 -and $apiEmpty.body.code -eq 'INVALID_PAYLOAD')

# 3.3. JSON malformado retorna HTTP 400
$apiBadJson = Invoke-UnlockApiController -SessionInfo $mockAuthSession -RawBody '{username: sin_comillas}'
Assert-Condition -TestName "API: JSON invalido retorna HTTP 400 INVALID_JSON" `
    -Condition ($apiBadJson.httpStatus -eq 400 -and $apiBadJson.body.code -eq 'INVALID_JSON')

# 3.4. JSON sin propiedad username retorna HTTP 400
$apiMissingField = Invoke-UnlockApiController -SessionInfo $mockAuthSession -RawBody '{"user":"henkia.pruebas"}'
Assert-Condition -TestName "API: JSON sin campo username retorna HTTP 400 MISSING_USERNAME" `
    -Condition ($apiMissingField.httpStatus -eq 400 -and $apiMissingField.body.code -eq 'MISSING_USERNAME')

# 3.5. Controlador PasswordReset sanitiza username y procesa JSON correctamente
$apiResetOk = Invoke-PasswordResetApiController `
    -SessionInfo $mockAuthSession `
    -RawBody '{"username":"  Henkia.Pruebas  ","newPassword":"Clave123*","confirmPassword":"Clave123*","changePasswordAtLogon":true,"unlockAccount":false}' `
    -GetUserCommand {
        param($u)
        return [PSCustomObject]@{
            SamAccountName = $u
            DisplayName    = 'Henkia Pruebas'
            Enabled        = $true
            LockedOut      = $false
        }
    } `
    -SetPasswordCommand { param($u, $sec) } `
    -SetChangeAtLogonCommand { param($u, $flag) } `
    -UnlockAccountCommand { param($u) }

Assert-Condition -TestName "API PasswordReset: Sanitiza espacios/mayusculas y retorna HTTP 200 PASSWORD_RESET_SUCCESS" `
    -Condition ($apiResetOk.httpStatus -eq 200 -and $apiResetOk.body.success -and $apiResetOk.body.user.username -eq 'henkia.pruebas')

if ($IncludeLiveHttpTests) {
    Write-Host "=== 4. Pruebas Integrales E2E en Vivo (EXCLUSIVAMENTE cuenta 'henkia.pruebas') ==="
    Add-Type -AssemblyName System.Net.Http
    $httpClient = New-Object System.Net.Http.HttpClient
    $testPort = 8085
    $proc = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$serverScriptPath`" -Port $testPort -MaxRequests 5" -NoNewWindow -PassThru
    Start-Sleep -Milliseconds 1500

    try {
        # 4.1. GET / (Entrega de Frontend index.html con botones 50/50 y modal de contrasena)
        $resIndex = $httpClient.GetAsync("http://localhost:$testPort/").Result
        $htmlContent = $resIndex.Content.ReadAsStringAsync().Result
        Assert-Condition -TestName "E2E Live: GET / entrega interfaz public/index.html con botones 50/50 y modal (HTTP 200)" `
            -Condition ([int]$resIndex.StatusCode -eq 200 -and $htmlContent.Contains('/api/user-status') -and $htmlContent.Contains('/api/reset-password'))

        # 4.2. GET /api/session
        $resSession = $httpClient.GetAsync("http://localhost:$testPort/api/session").Result
        $sessionJson = $resSession.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        Assert-Condition -TestName "E2E Live: GET /api/session autentica sesion de Windows en AD (HTTP 200)" `
            -Condition ([int]$resSession.StatusCode -eq 200 -and $sessionJson.authorized -eq $true)

        # 4.3. POST /api/user-status para 'henkia.pruebas' -> HTTP 200 USER_VALID
        $contentStatus = New-Object System.Net.Http.StringContent('{"username":"henkia.pruebas"}', [System.Text.Encoding]::UTF8, 'application/json')
        $resStatus = $httpClient.PostAsync("http://localhost:$testPort/api/user-status", $contentStatus).Result
        $bodyStatus = $resStatus.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        Assert-Condition -TestName "E2E Live: POST /api/user-status valida cuenta 'henkia.pruebas' habilitada (HTTP 200)" `
            -Condition ([int]$resStatus.StatusCode -eq 200 -and $bodyStatus.code -eq 'USER_VALID' -and $bodyStatus.user.username -eq 'henkia.pruebas' -and $bodyStatus.user.enabled -eq $true) `
            -FailureMessage "Respuesta recibida: $($bodyStatus | ConvertTo-Json -Compress)"

        # 4.4. POST /api/reset-password para 'henkia.pruebas' con ChangePasswordAtLogon=true y UnlockAccount=true
        $resetPayloadObj = @{
            username              = 'henkia.pruebas'
            newPassword           = $LiveTestPassword
            confirmPassword       = $LiveTestPassword
            changePasswordAtLogon = $true
            unlockAccount         = $true
        } | ConvertTo-Json -Compress
        $contentReset = New-Object System.Net.Http.StringContent($resetPayloadObj, [System.Text.Encoding]::UTF8, 'application/json')
        $resReset = $httpClient.PostAsync("http://localhost:$testPort/api/reset-password", $contentReset).Result
        $bodyReset = $resReset.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        Assert-Condition -TestName "E2E Live: POST /api/reset-password en 'henkia.pruebas' cambia clave, fuerza cambio al iniciar sesion y desbloquea (HTTP 200)" `
            -Condition ([int]$resReset.StatusCode -eq 200 -and $bodyReset.code -eq 'PASSWORD_RESET_SUCCESS' -and $bodyReset.success -eq $true) `
            -FailureMessage "Respuesta recibida: $($bodyReset | ConvertTo-Json -Compress)"

        # 4.5. Verificar directamente en AD que 'henkia.pruebas' quedo con PasswordExpired=True (ChangePasswordAtLogon) y LockedOut=False
        $adVerify = Get-ADUser -Identity 'henkia.pruebas' -Properties PasswordExpired, LockedOut, Enabled
        Assert-Condition -TestName "E2E Live: Verificacion AD confirma que 'henkia.pruebas' tiene ChangePasswordAtLogon activo y cuenta desbloqueada" `
            -Condition ($adVerify.Enabled -eq $true -and $adVerify.LockedOut -eq $false -and $adVerify.PasswordExpired -eq $true)

        # 4.6. POST /api/unlock sobre 'henkia.pruebas' (ya desbloqueada)
        $contentUnlock = New-Object System.Net.Http.StringContent('{"username":"henkia.pruebas"}', [System.Text.Encoding]::UTF8, 'application/json')
        $resUnlock = $httpClient.PostAsync("http://localhost:$testPort/api/unlock", $contentUnlock).Result
        $bodyUnlock = $resUnlock.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        Assert-Condition -TestName "E2E Live: POST /api/unlock sobre 'henkia.pruebas' responde correctamente (HTTP 422 ACCOUNT_NOT_LOCKED)" `
            -Condition ([int]$resUnlock.StatusCode -eq 422 -and $bodyUnlock.code -eq 'ACCOUNT_NOT_LOCKED')
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
