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

# Validacion de formato de usuario (con punto y de un solo nombre sin punto)
Assert-Condition -TestName "Formato con punto 'henkia.pruebas' es aceptado" `
    -Condition (Test-ValidUsernameFormat -Username 'henkia.pruebas')

Assert-Condition -TestName "Formato de un solo nombre sin punto 'henkiapruebas' es aceptado" `
    -Condition (Test-ValidUsernameFormat -Username 'henkiapruebas')

Assert-Condition -TestName "Formato con espacios intermedios es rechazado" `
    -Condition (-not (Test-ValidUsernameFormat -Username 'henkia pruebas'))

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

Write-Host "=== 3.B. Pruebas Unitarias de Inhabilitacion Masiva (Preview y Execute) ==="

# 3.B.1. CSV con encabezados con espacios al inicio/final y minusculas + delimitador ';'
$csvConEspacios = "  nombre  ; APELLIDO  `r`nhenkia ; pruebas`r`nusuario ; inactivo"
$previewRes = Invoke-BulkDisablePreview -CsvContent $csvConEspacios -SearchUsersCommand {
    param($nom, $ape)
    if ($nom -eq 'henkia' -and $ape -eq 'pruebas') {
        return @(
            [PSCustomObject]@{
                SamAccountName    = 'henkia.pruebas'
                Name              = 'Henkia Pruebas'
                DisplayName       = 'Henkia Pruebas'
                GivenName         = 'Henkia'
                Surname           = 'Pruebas'
                Enabled           = $true
                Description       = 'Arus Itagui - Antioquia'
                DistinguishedName = 'CN=Henkia Pruebas,OU=AL_EXTERNOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co'
            }
        )
    } else {
        # Cuenta inhabilitada que debe ser ignorada por el filtro de activos
        return @(
            [PSCustomObject]@{
                SamAccountName    = 'henkia.pruebas.inactivo'
                Name              = 'Usuario Inactivo'
                DisplayName       = 'Usuario Inactivo'
                GivenName         = 'Usuario'
                Surname           = 'Inactivo'
                Enabled           = $false
                Description       = 'Retirado'
                DistinguishedName = 'CN=Usuario Inactivo,OU=AL_INACTIVOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co'
            }
        )
    }
}

Assert-Condition -TestName "BulkPreview: Tolera encabezados con espacios/minusculas ('  nombre  ; APELLIDO  ') y filtra inactivos" `
    -Condition ($previewRes.httpStatus -eq 200 -and $previewRes.code -eq 'PREVIEW_READY' -and $previewRes.users.Count -eq 1 -and $previewRes.users[0].usuario -eq 'henkia.pruebas' -and $previewRes.unmatchedRows.Count -eq 1)

# 3.B.2. CSV sin columnas requeridas retorna HTTP 400 INVALID_CSV_HEADERS
$previewBadHeaders = Invoke-BulkDisablePreview -CsvContent "CORREO,AREA`r`ntest@aliar.com,TI"
Assert-Condition -TestName "BulkPreview: Rechaza CSV sin columnas NOMBRE y APELLIDO (HTTP 400)" `
    -Condition ($previewBadHeaders.httpStatus -eq 400 -and $previewBadHeaders.code -eq 'INVALID_CSV_HEADERS')

# 3.B.3. BulkExecute - Vacaciones: Solo inhabilita (NO cambia descripcion ni mueve de OU)
$vacDisableCalled = $false
$vacDescCalled = $false
$vacMoveCalled = $false

$execVacaciones = Invoke-BulkDisableExecute `
    -ProcessType 'Vacaciones' `
    -Usernames @('henkia.pruebas') `
    -GetUserCommand {
        param($u)
        return [PSCustomObject]@{
            SamAccountName    = $u
            Name              = 'Henkia Pruebas'
            DisplayName       = 'Henkia Pruebas'
            Enabled           = $true
            Description       = 'Arus Itagui - Antioquia'
            DistinguishedName = 'CN=Henkia Pruebas,OU=AL_EXTERNOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co'
        }
    } `
    -DisableAccountCommand { param($u) $script:vacDisableCalled = ($u -eq 'henkia.pruebas') } `
    -SetDescriptionCommand { param($u, $d) $script:vacDescCalled = $true } `
    -MoveObjectCommand { param($dn, $ou) $script:vacMoveCalled = $true }

Assert-Condition -TestName "BulkExecute (Vacaciones): Solo ejecuta Disable-ADAccount sin tocar Description ni OU" `
    -Condition ($execVacaciones.httpStatus -eq 200 -and $execVacaciones.success -and $vacDisableCalled -and (-not $vacDescCalled) -and (-not $vacMoveCalled))

# 3.B.4. BulkExecute - Paz y Salvo: Inhabilita, antepone '(R) ' y mueve a AL_INACTIVOS
$pysDisableCalled = $false
$pysNewDesc = ''
$pysTargetOU = ''

$execPazYSalvo = Invoke-BulkDisableExecute `
    -ProcessType 'Paz y Salvo' `
    -Usernames @('henkia.pruebas') `
    -GetUserCommand {
        param($u)
        return [PSCustomObject]@{
            SamAccountName    = $u
            Name              = 'Henkia Pruebas'
            DisplayName       = 'Henkia Pruebas'
            Enabled           = $true
            Description       = 'Arus Itagui - Antioquia'
            DistinguishedName = 'CN=Henkia Pruebas,OU=AL_EXTERNOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co'
        }
    } `
    -DisableAccountCommand { param($u) $script:pysDisableCalled = ($u -eq 'henkia.pruebas') } `
    -SetDescriptionCommand { param($u, $d) $script:pysNewDesc = $d } `
    -MoveObjectCommand { param($dn, $ou) $script:pysTargetOU = $ou }

Assert-Condition -TestName "BulkExecute (Paz y Salvo): Inhabilita, agrega '(R) ' y mueve a AL_INACTIVOS" `
    -Condition ($execPazYSalvo.httpStatus -eq 200 -and $execPazYSalvo.success -and $pysDisableCalled -and ($pysNewDesc -eq '(R) Arus Itagui - Antioquia') -and ($pysTargetOU -eq 'OU=AL_INACTIVOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co'))

# 3.B.5. Controladores API Masivos bloquean sesiones no autorizadas (HTTP 403)
$apiForbiddenPreview = Invoke-BulkPreviewApiController -SessionInfo $mockUnauthSession -RawBody '{"csvContent":"NOMBRE,APELLIDO\nhenkia,pruebas"}'
$apiForbiddenExecute = Invoke-BulkExecuteApiController -SessionInfo $mockUnauthSession -RawBody '{"processType":"Vacaciones","usernames":["henkia.pruebas"]}'
Assert-Condition -TestName "API Masivo: Sesion no autorizada retorna HTTP 403 en preview y execute" `
    -Condition ($apiForbiddenPreview.httpStatus -eq 403 -and $apiForbiddenExecute.httpStatus -eq 403)

# 3.B.6. Normalizacion de Ñ, tildes, dieresis y caracter de reemplazo (U+FFFD)
$normEne = ConvertTo-NormalizedADSearchText -InputText "SANDOVAL ACU$([char]0x00D1)A"
$normTildes = ConvertTo-NormalizedADSearchText -InputText "G$([char]0x00D3)MEZ P$([char]0x00C9)REZ G$([char]0x00DC)$([char]0x00C9)MEZ"
$normCorrupto = ConvertTo-NormalizedADSearchText -InputText "SANDOVAL ACU$([char]0xFFFD)A"

Assert-Condition -TestName "Normalizacion AD: Convierte Ñ->N ('SANDOVAL ACUÑA' -> 'SANDOVAL ACUNA'), quita tildes/dieresis y reemplaza U+FFFD por '*'" `
    -Condition ($normEne -eq 'SANDOVAL ACUNA' -and $normTildes -eq 'GOMEZ PEREZ GUEMEZ' -and $normCorrupto -eq 'SANDOVAL ACU*A')

$csvConTildesYEne = "NOMBRE;APELLIDO`r`nHenki$([char]0x00E1);Pru$([char]0x00E9)bas"
$previewNormalized = Invoke-BulkDisablePreview -CsvContent $csvConTildesYEne -SearchUsersCommand {
    param($nom, $ape)
    if ($nom -eq 'Henkia' -and $ape -eq 'Pruebas') {
        return @(
            [PSCustomObject]@{
                SamAccountName    = 'henkia.pruebas'
                Name              = 'Henkia Pruebas'
                DisplayName       = 'Henkia Pruebas'
                GivenName         = 'Henkia'
                Surname           = 'Pruebas'
                Enabled           = $true
                Description       = 'Arus Itagui - Antioquia'
                DistinguishedName = 'CN=Henkia Pruebas,OU=AL_EXTERNOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co'
            }
        )
    }
    return @()
}

Assert-Condition -TestName "BulkPreview: Normaliza tildes y Ñ antes de consultar AD y localiza la cuenta sin diacriticos" `
    -Condition ($previewNormalized.httpStatus -eq 200 -and $previewNormalized.users.Count -eq 1 -and $previewNormalized.users[0].usuario -eq 'henkia.pruebas')

# 3.B.7. CSV complejo de nomina/paz y salvo: encabezados en fila 5, celdas multilinea, columnas duplicadas ('VIATICOS', 'DIAS DE SUSPENSION') y tablas inferiores
$csvComplejoMulticapa = @"
,,,,,,,,
,,,,,,,,
,,1,2,3,4,5,6,7
NOMINA,,,CARTERA,"CONTABILIDAD
(Area Financiera)",,"GESTION HUMANA
(Viaticos)",,
FECHA DE SOLICITUD,FECHA DE TERMINACION,CEDULA,NOMBRE ,APELLIDO,CARGO,VIATICOS,DETALLE DEL CONCEPTO,VIATICOS,DIAS DE SUSPENSION,DIAS DE SUSPENSION
2026-11-13,2026-11-03,0000000000,Henkia,Pruebas,ANALISTA PRUEBAS,0,,0,0,0
,,,,,,,,
,,,,,,,,
PAZ Y SALVO EMPRESARIAL,,,,,,,,
,CEDULA,0000000000,9999999999,8888888888,,,,
,NOMBRE,HENKIA PRUEBAS,OTRO REGISTRO,NO LEER,,,,
"@

$searchedPairsCsvComplejo = @()
$previewComplejo = Invoke-BulkDisablePreview -CsvContent $csvComplejoMulticapa -SearchUsersCommand {
    param($nom, $ape)
    $script:searchedPairsCsvComplejo += "$nom|$ape"
    if ($nom -eq 'Henkia' -and $ape -eq 'Pruebas') {
        return @(
            [PSCustomObject]@{
                SamAccountName    = 'henkia.pruebas'
                Name              = 'Henkia Pruebas'
                DisplayName       = 'Henkia Pruebas'
                GivenName         = 'Henkia'
                Surname           = 'Pruebas'
                Enabled           = $true
                Description       = 'Arus Itagui - Antioquia'
                DistinguishedName = 'CN=Henkia Pruebas,OU=AL_EXTERNOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co'
            }
        )
    }
    return @()
}

Assert-Condition -TestName "BulkPreview (CSV multicapa): Localiza encabezados en fila 5, ignora columnas duplicadas ('VIATICOS') y detiene lectura al terminar la tabla" `
    -Condition ($previewComplejo.httpStatus -eq 200 -and $previewComplejo.users.Count -eq 1 -and $searchedPairsCsvComplejo.Count -eq 1 -and $searchedPairsCsvComplejo[0] -eq 'Henkia|Pruebas')

# 3.B.8. Archivo Excel (.xlsx) nativo en memoria con encabezados en fila 5, columnas repetidas y multiples hojas
Add-Type -AssemblyName System.IO.Compression
$xlsxMem = New-Object System.IO.MemoryStream
$xlsxZip = New-Object System.IO.Compression.ZipArchive($xlsxMem, [System.IO.Compression.ZipArchiveMode]::Create, $true)

$ssXmlContent = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="9" uniqueCount="9">
  <si><t>NOMINA</t></si>
  <si><t>FECHA DE SOLICITUD</t></si>
  <si><t>CEDULA</t></si>
  <si><t>NOMBRE </t></si>
  <si><t>APELLIDO</t></si>
  <si><t>VIATICOS</t></si>
  <si><t>Henkia</t></si>
  <si><t>Pruebas</t></si>
  <si><t>PAZ Y SALVO EMPRESARIAL</t></si>
</sst>
'@

$sheet1XmlContent = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="s"><v>0</v></c></row>
    <row r="5">
      <c r="A5" t="s"><v>1</v></c>
      <c r="B5" t="s"><v>2</v></c>
      <c r="D5" t="s"><v>3</v></c>
      <c r="E5" t="s"><v>4</v></c>
      <c r="F5" t="s"><v>5</v></c>
      <c r="G5" t="s"><v>5</v></c>
    </row>
    <row r="6">
      <c r="A6"><v>2026-11-13</v></c>
      <c r="B6"><v>0000</v></c>
      <c r="D6" t="s"><v>6</v></c>
      <c r="E6" t="s"><v>7</v></c>
      <c r="F6"><v>0</v></c>
      <c r="G6"><v>0</v></c>
    </row>
    <row r="7"></row>
    <row r="8">
      <c r="A8" t="s"><v>8</v></c>
    </row>
  </sheetData>
</worksheet>
'@

$ssEntryTest = $xlsxZip.CreateEntry('xl/sharedStrings.xml')
$ssWriter = New-Object System.IO.StreamWriter($ssEntryTest.Open(), [System.Text.Encoding]::UTF8)
$ssWriter.Write($ssXmlContent)
$ssWriter.Close()

$sh1EntryTest = $xlsxZip.CreateEntry('xl/worksheets/sheet1.xml')
$sh1Writer = New-Object System.IO.StreamWriter($sh1EntryTest.Open(), [System.Text.Encoding]::UTF8)
$sh1Writer.Write($sheet1XmlContent)
$sh1Writer.Close()

$xlsxZip.Dispose()
$xlsxBase64Test = [Convert]::ToBase64String($xlsxMem.ToArray())
$xlsxMem.Dispose()

$xlsxJsonBody = @{ xlsxBase64 = $xlsxBase64Test } | ConvertTo-Json -Compress
$apiXlsxRes = Invoke-BulkPreviewApiController -SessionInfo $mockAuthSession -RawBody $xlsxJsonBody -SearchUsersCommand {
    param($nom, $ape)
    if ($nom -eq 'Henkia' -and $ape -eq 'Pruebas') {
        return @(
            [PSCustomObject]@{
                SamAccountName    = 'henkia.pruebas'
                Name              = 'Henkia Pruebas'
                DisplayName       = 'Henkia Pruebas'
                GivenName         = 'Henkia'
                Surname           = 'Pruebas'
                Enabled           = $true
                Description       = 'Arus Itagui - Antioquia'
                DistinguishedName = 'CN=Henkia Pruebas,OU=AL_EXTERNOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co'
            }
        )
    }
    return @()
}

Assert-Condition -TestName "API BulkPreview (.xlsx): Procesa libro Excel nativo con encabezados en fila 5 y columnas duplicadas, extrayendo 'henkia.pruebas'" `
    -Condition ($apiXlsxRes.httpStatus -eq 200 -and $apiXlsxRes.body.code -eq 'PREVIEW_READY' -and $apiXlsxRes.body.users.Count -eq 1 -and $apiXlsxRes.body.users[0].usuario -eq 'henkia.pruebas')

Write-Host "=== 3.C. Pruebas Estructurales de Interfaz Web (public/index.html) ==="
$indexPath = Join-Path (Join-Path $projectRoot 'public') 'index.html'
$indexRaw = Get-Content -Path $indexPath -Raw -Encoding UTF8

Assert-Condition -TestName "Frontend: Incluye Segmented Control (tabIndividualBtn, tabBulkBtn, viewIndividual, viewBulk)" `
    -Condition ($indexRaw.Contains('id="tabIndividualBtn"') -and $indexRaw.Contains('id="tabBulkBtn"') -and $indexRaw.Contains('id="viewIndividual"') -and $indexRaw.Contains('id="viewBulk"'))

Assert-Condition -TestName "Frontend: Admite archivos .csv y .xlsx (xlsxBase64) y decodificacion ANSI Windows-1252 para Ñ/tildes" `
    -Condition ($indexRaw.Contains('accept=".csv,.xlsx') -and $indexRaw.Contains('xlsxBase64') -and $indexRaw.Contains('windows-1252'))

Assert-Condition -TestName "Frontend: Incluye Modal de Verificacion Masiva con checkboxes desmarcados por defecto (bulkVerifyModal, selectAllUsersCheckbox, executeBulkBtn)" `
    -Condition ($indexRaw.Contains('id="bulkVerifyModal"') -and $indexRaw.Contains('id="selectAllUsersCheckbox"') -and $indexRaw.Contains('id="bulkUsersTableBody"') -and $indexRaw.Contains('id="executeBulkBtn"') -and $indexRaw.Contains('checkbox.checked = false'))

if ($IncludeLiveHttpTests) {
    Write-Host "=== 4. Pruebas Integrales E2E en Vivo (EXCLUSIVAMENTE cuenta 'henkia.pruebas') ==="
    Initialize-ADModule
    $targetTestAccount = 'henkia.pruebas'
    $originalOU = 'OU=AL_EXTERNOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co'
    $inactiveOU = 'OU=AL_INACTIVOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co'
    $originalDescription = 'Arus Itagui - Antioquia'

    function Restore-HenkiaPruebasState {
        try {
            Enable-ADAccount -Identity $targetTestAccount -ErrorAction SilentlyContinue
            Unlock-ADAccount -Identity $targetTestAccount -ErrorAction SilentlyContinue
            Set-ADUser -Identity $targetTestAccount -Description $originalDescription -ErrorAction SilentlyContinue
            $currentAdObj = Get-ADUser -Identity $targetTestAccount -Properties DistinguishedName -ErrorAction Stop
            $currentParentOU = $currentAdObj.DistinguishedName -replace '^CN=[^,]+,', ''
            if ($currentParentOU -ne $originalOU) {
                Move-ADObject -Identity $currentAdObj.DistinguishedName -TargetPath $originalOU -ErrorAction Stop
            }
        } catch {
            Write-Host "[ADVERTENCIA] Error al restaurar '$targetTestAccount': $($_.Exception.Message)"
        }
    }

    # Garantizar estado inicial limpio de henkia.pruebas antes de iniciar las pruebas en vivo
    Restore-HenkiaPruebasState

    Add-Type -AssemblyName System.Net.Http
    $httpClient = New-Object System.Net.Http.HttpClient
    $testPort = 8085
    $proc = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$serverScriptPath`" -Port $testPort -MaxRequests 8" -NoNewWindow -PassThru
    Start-Sleep -Milliseconds 1500

    try {
        # 4.1. GET / (Entrega de Frontend index.html con modulos Individual e Inhabilitacion Masiva)
        $resIndex = $httpClient.GetAsync("http://localhost:$testPort/").Result
        $htmlContent = $resIndex.Content.ReadAsStringAsync().Result
        Assert-Condition -TestName "E2E Live: GET / entrega interfaz public/index.html con modulos Individual y Masivo (HTTP 200)" `
            -Condition ([int]$resIndex.StatusCode -eq 200 -and $htmlContent.Contains('/api/user-status') -and $htmlContent.Contains('/api/masivo/preview') -and $htmlContent.Contains('/api/masivo/execute'))

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

        # 4.7. POST /api/masivo/preview con encabezados con espacios y minusculas (" nombre , APELLIDO \nhenkia,pruebas")
        $previewPayloadObj = @{
            csvContent = " nombre , APELLIDO `r`nhenkia,pruebas"
        } | ConvertTo-Json -Compress
        $contentPreview = New-Object System.Net.Http.StringContent($previewPayloadObj, [System.Text.Encoding]::UTF8, 'application/json')
        $resPreview = $httpClient.PostAsync("http://localhost:$testPort/api/masivo/preview", $contentPreview).Result
        $bodyPreview = $resPreview.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        $previewUsers = @($bodyPreview.users)
        Assert-Condition -TestName "E2E Live: POST /api/masivo/preview localiza 'henkia.pruebas' con encabezados con espacios (HTTP 200)" `
            -Condition ([int]$resPreview.StatusCode -eq 200 -and $bodyPreview.code -eq 'PREVIEW_READY' -and $previewUsers.Count -ge 1 -and ($previewUsers[0].usuario -eq 'henkia.pruebas')) `
            -FailureMessage "Respuesta recibida: $($bodyPreview | ConvertTo-Json -Compress)"

        # 4.8. POST /api/masivo/execute (Vacaciones) exclusivamente sobre 'henkia.pruebas'
        $vacPayloadObj = @{
            processType = 'Vacaciones'
            usernames   = @('henkia.pruebas')
        } | ConvertTo-Json -Compress
        $contentVac = New-Object System.Net.Http.StringContent($vacPayloadObj, [System.Text.Encoding]::UTF8, 'application/json')
        $resVac = $httpClient.PostAsync("http://localhost:$testPort/api/masivo/execute", $contentVac).Result
        $bodyVac = $resVac.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        $adAfterVac = Get-ADUser -Identity 'henkia.pruebas' -Properties Enabled, Description, DistinguishedName
        $ouAfterVac = $adAfterVac.DistinguishedName -replace '^CN=[^,]+,', ''
        Assert-Condition -TestName "E2E Live: POST /api/masivo/execute (Vacaciones) inhabilita 'henkia.pruebas' sin alterar Description ni OU" `
            -Condition ([int]$resVac.StatusCode -eq 200 -and $bodyVac.success -eq $true -and $adAfterVac.Enabled -eq $false -and $adAfterVac.Description -eq $originalDescription -and $ouAfterVac -eq $originalOU) `
            -FailureMessage "Respuesta Vacaciones: $($bodyVac | ConvertTo-Json -Compress) | AD Enabled=$($adAfterVac.Enabled), Desc=$($adAfterVac.Description), OU=$ouAfterVac"

        # Rehabilitar 'henkia.pruebas' para probar el flujo completo de Paz y Salvo
        Enable-ADAccount -Identity 'henkia.pruebas' -ErrorAction Stop

        # 4.9. POST /api/masivo/execute (Paz y Salvo) exclusivamente sobre 'henkia.pruebas'
        $pysPayloadObj = @{
            processType = 'Paz y Salvo'
            usernames   = @('henkia.pruebas')
        } | ConvertTo-Json -Compress
        $contentPys = New-Object System.Net.Http.StringContent($pysPayloadObj, [System.Text.Encoding]::UTF8, 'application/json')
        $resPys = $httpClient.PostAsync("http://localhost:$testPort/api/masivo/execute", $contentPys).Result
        $bodyPys = $resPys.Content.ReadAsStringAsync().Result | ConvertFrom-Json
        $adAfterPys = Get-ADUser -Identity 'henkia.pruebas' -Properties Enabled, Description, DistinguishedName
        $ouAfterPys = $adAfterPys.DistinguishedName -replace '^CN=[^,]+,', ''
        Assert-Condition -TestName "E2E Live: POST /api/masivo/execute (Paz y Salvo) inhabilita 'henkia.pruebas', antepone '(R) ' y mueve a AL_INACTIVOS" `
            -Condition ([int]$resPys.StatusCode -eq 200 -and $bodyPys.success -eq $true -and $adAfterPys.Enabled -eq $false -and $adAfterPys.Description -eq "(R) $originalDescription" -and $ouAfterPys -eq $inactiveOU) `
            -FailureMessage "Respuesta Paz y Salvo: $($bodyPys | ConvertTo-Json -Compress) | AD Enabled=$($adAfterPys.Enabled), Desc=$($adAfterPys.Description), OU=$ouAfterPys"
    } finally {
        Restore-HenkiaPruebasState
        $httpClient.Dispose()
        $proc.WaitForExit(3000) | Out-Null
        if (-not $proc.HasExited) {
            try { $proc.Kill() } catch {}
        }
    }

    # 4.10. Verificar que 'henkia.pruebas' fue restaurada exitosamente a su estado, descripcion y OU originales
    $adRestored = Get-ADUser -Identity 'henkia.pruebas' -Properties Enabled, Description, DistinguishedName
    $ouRestored = $adRestored.DistinguishedName -replace '^CN=[^,]+,', ''
    Assert-Condition -TestName "E2E Live: Restauracion post-test devuelve 'henkia.pruebas' a Enabled=True, Descripcion original y OU AL_EXTERNOS" `
        -Condition ($adRestored.Enabled -eq $true -and $adRestored.Description -eq $originalDescription -and $ouRestored -eq $originalOU) `
        -FailureMessage "Estado tras restauracion: Enabled=$($adRestored.Enabled), Desc=$($adRestored.Description), OU=$ouRestored"
}

Write-Host "--------------------------------------------------------"
Write-Host "Total: $totalTests | Aprobadas: $passedTests | Fallidas: $failedTests"

if ($failedTests -gt 0) {
    exit 1
}
