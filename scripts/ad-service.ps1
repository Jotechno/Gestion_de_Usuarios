# Servicio de integracion con Active Directory y Control de Acceso
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Grupos de Active Directory autorizados por defecto para usar la aplicacion
$script:AuthorizedADGroups = @(
    'Admins. del dominio',
    'Domain Admins'
)

function Initialize-ADModule {
    if (-not (Get-Module -Name ActiveDirectory)) {
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            throw "El modulo ActiveDirectory (RSAT) no esta instalado en este equipo."
        }
        Import-Module ActiveDirectory -WarningAction SilentlyContinue -ErrorAction Stop
    }
}

function Get-CurrentWindowsIdentityInfo {
    $windowsIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $windowsIdentity -or [string]::IsNullOrWhiteSpace($windowsIdentity.Name)) {
        throw "No fue posible determinar la identidad de la sesion de Windows actual."
    }

    $fullName = $windowsIdentity.Name
    $domain = ''
    $samAccountName = $fullName

    if ($fullName -match '^([^\\]+)\\(.+)$') {
        $domain = $Matches[1]
        $samAccountName = $Matches[2]
    }

    return [PSCustomObject]@{
        FullName       = $fullName
        Domain         = $domain
        SamAccountName = $samAccountName
        Identity       = $windowsIdentity
    }
}

function Get-AnalystSession {
    param(
        [string]$SamAccountName = '',
        [string[]]$AllowedGroups = $script:AuthorizedADGroups
    )

    $identityInfo = Get-CurrentWindowsIdentityInfo
    $targetUser = if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
        $identityInfo.SamAccountName
    } else {
        $SamAccountName.Trim()
    }

    $domainUser = if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
        $identityInfo.FullName
    } elseif (-not [string]::IsNullOrWhiteSpace($identityInfo.Domain)) {
        "$($identityInfo.Domain)\$targetUser"
    } else {
        $targetUser
    }

    try {
        Initialize-ADModule

        $adUser = Get-ADUser -Identity $targetUser -Properties MemberOf, DisplayName, Enabled -ErrorAction Stop

        if (-not $adUser.Enabled) {
            return [PSCustomObject]@{
                success      = $false
                authorized   = $false
                user         = $adUser.SamAccountName
                domainUser   = $domainUser
                displayName  = [string]$adUser.DisplayName
                matchedGroup = $null
                message      = "Acceso denegado: la cuenta del analista '$domainUser' se encuentra inhabilitada."
            }
        }

        $userGroups = @()
        if ($null -ne $adUser.MemberOf) {
            foreach ($dn in $adUser.MemberOf) {
                if ($dn -match '^CN=([^,]+),') {
                    $userGroups += $Matches[1]
                }
            }
        }

        $matchedGroup = $null
        foreach ($allowed in $AllowedGroups) {
            foreach ($ug in $userGroups) {
                if ([string]::Equals($ug.Trim(), $allowed.Trim(), [System.StringComparison]::OrdinalIgnoreCase)) {
                    $matchedGroup = $ug
                    break
                }
            }
            if ($null -ne $matchedGroup) {
                break
            }
        }

        if ($null -ne $matchedGroup) {
            return [PSCustomObject]@{
                success      = $true
                authorized   = $true
                user         = $adUser.SamAccountName
                domainUser   = $domainUser
                displayName  = [string]$adUser.DisplayName
                matchedGroup = $matchedGroup
                message      = "Sesion autorizada correctamente."
            }
        } else {
            $gruposRequeridos = ($AllowedGroups -join ' / ')
            return [PSCustomObject]@{
                success      = $false
                authorized   = $false
                user         = $adUser.SamAccountName
                domainUser   = $domainUser
                displayName  = [string]$adUser.DisplayName
                matchedGroup = $null
                message      = "Acceso denegado: el usuario '$domainUser' no pertenece al grupo autorizado ($gruposRequeridos)."
            }
        }
    } catch {
        return [PSCustomObject]@{
            success      = $false
            authorized   = $false
            user         = $targetUser
            domainUser   = $domainUser
            displayName  = ''
            matchedGroup = $null
            message      = "No se pudo validar la autorizacion en Active Directory: $($_.Exception.Message)"
        }
    }
}

function Test-ValidUsernameFormat {
    param(
        [AllowEmptyString()]
        [string]$Username
    )

    if ([string]::IsNullOrWhiteSpace($Username)) {
        return $false
    }

    $trimmed = $Username.Trim()
    if ($trimmed.Length -gt 64) {
        return $false
    }

    return ($trimmed -match '^[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)+$')
}

function Get-TargetADUser {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Username
    )

    Initialize-ADModule

    try {
        return Get-ADUser -Identity $Username -Properties LockedOut, Enabled, DisplayName -ErrorAction Stop
    } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        return $null
    } catch {
        if ($_.Exception.GetType().Name -eq 'ADIdentityNotFoundException' -or $_.FullyQualifiedErrorId -like '*ADIdentityNotFoundException*') {
            return $null
        }
        throw
    }
}

function Invoke-UserUnlock {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Username,
        [scriptblock]$GetUserCommand = $null,
        [scriptblock]$UnlockAccountCommand = $null
    )

    $cleanUser = if ($null -ne $Username) { $Username.Trim().ToLowerInvariant() } else { '' }

    if (-not (Test-ValidUsernameFormat -Username $cleanUser)) {
        return [PSCustomObject]@{
            httpStatus = 400
            success    = $false
            code       = 'INVALID_FORMAT'
            title      = 'Formato de usuario inválido'
            message    = "El usuario ingresado debe tener el formato 'nombre.apellido'."
            user       = $null
        }
    }

    try {
        $adUser = if ($null -ne $GetUserCommand) {
            & $GetUserCommand $cleanUser
        } else {
            Get-TargetADUser -Username $cleanUser
        }

        if ($null -eq $adUser) {
            return [PSCustomObject]@{
                httpStatus = 404
                success    = $false
                code       = 'USER_NOT_FOUND'
                title      = 'Usuario no encontrado'
                message    = "La cuenta '$cleanUser' no existe en el Directorio Activo."
                user       = $null
            }
        }

        $userSummary = [PSCustomObject]@{
            username    = [string]$adUser.SamAccountName
            displayName = [string]$adUser.DisplayName
            enabled     = [bool]$adUser.Enabled
            lockedOut   = [bool]$adUser.LockedOut
        }

        # Regla de Negocio 1: Si el usuario esta INHABILITADO (Disabled), NO se puede desbloquear
        if (-not [bool]$adUser.Enabled) {
            return [PSCustomObject]@{
                httpStatus = 422
                success    = $false
                code       = 'ACCOUNT_DISABLED'
                title      = 'Cuenta inhabilitada'
                message    = "No es posible desbloquear al usuario '$cleanUser' porque su cuenta se encuentra INHABILITADA en el Directorio Activo."
                user       = $userSummary
            }
        }

        # Regla de Negocio 2: Si el usuario esta HABILITADO pero NO tiene estado de bloqueo activo
        if (-not [bool]$adUser.LockedOut) {
            return [PSCustomObject]@{
                httpStatus = 422
                success    = $false
                code       = 'ACCOUNT_NOT_LOCKED'
                title      = 'Cuenta sin bloqueo activo'
                message    = "La cuenta '$cleanUser' se encuentra habilitada y no presenta bloqueo por intentos fallidos en el Directorio Activo."
                user       = $userSummary
            }
        }

        # Regla de Negocio 3: Solo se desbloquea si Enabled = True y LockedOut = True
        if ($null -ne $UnlockAccountCommand) {
            & $UnlockAccountCommand $cleanUser
        } else {
            Initialize-ADModule
            Unlock-ADAccount -Identity $cleanUser -ErrorAction Stop
        }

        $userSummary.lockedOut = $false
        $displayLabel = if (-not [string]::IsNullOrWhiteSpace($userSummary.displayName)) {
            " ($($userSummary.displayName))"
        } else {
            ""
        }

        return [PSCustomObject]@{
            httpStatus = 200
            success    = $true
            code       = 'UNLOCKED_SUCCESS'
            title      = 'Desbloqueo exitoso'
            message    = "La cuenta '$cleanUser'$displayLabel ha sido desbloqueada exitosamente en el Directorio Activo."
            user       = $userSummary
        }
    } catch {
        return [PSCustomObject]@{
            httpStatus = 500
            success    = $false
            code       = 'AD_ERROR'
            title      = 'Error en Active Directory'
            message    = "Ocurrió un error al procesar la cuenta '$cleanUser' en Active Directory: $($_.Exception.Message)"
            user       = $null
        }
    }
}

function Invoke-UserStatusCheck {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Username,
        [scriptblock]$GetUserCommand = $null
    )

    $cleanUser = if ($null -ne $Username) { $Username.Trim().ToLowerInvariant() } else { '' }

    if (-not (Test-ValidUsernameFormat -Username $cleanUser)) {
        return [PSCustomObject]@{
            httpStatus = 400
            success    = $false
            code       = 'INVALID_FORMAT'
            title      = 'Formato de usuario inválido'
            message    = "El usuario ingresado debe tener el formato 'nombre.apellido'."
            user       = $null
        }
    }

    try {
        $adUser = if ($null -ne $GetUserCommand) {
            & $GetUserCommand $cleanUser
        } else {
            Get-TargetADUser -Username $cleanUser
        }

        if ($null -eq $adUser) {
            return [PSCustomObject]@{
                httpStatus = 404
                success    = $false
                code       = 'USER_NOT_FOUND'
                title      = 'Usuario no encontrado'
                message    = "La cuenta '$cleanUser' no existe en el Directorio Activo."
                user       = $null
            }
        }

        $userSummary = [PSCustomObject]@{
            username    = [string]$adUser.SamAccountName
            displayName = [string]$adUser.DisplayName
            enabled     = [bool]$adUser.Enabled
            lockedOut   = [bool]$adUser.LockedOut
        }

        if (-not [bool]$adUser.Enabled) {
            return [PSCustomObject]@{
                httpStatus = 422
                success    = $false
                code       = 'ACCOUNT_DISABLED'
                title      = 'Cuenta inhabilitada'
                message    = "No es posible cambiar la contraseña del usuario '$cleanUser' porque su cuenta se encuentra INHABILITADA en el Directorio Activo."
                user       = $userSummary
            }
        }

        return [PSCustomObject]@{
            httpStatus = 200
            success    = $true
            code       = 'USER_VALID'
            title      = 'Usuario válido'
            message    = "La cuenta '$cleanUser' está habilitada."
            user       = $userSummary
        }
    } catch {
        return [PSCustomObject]@{
            httpStatus = 500
            success    = $false
            code       = 'AD_ERROR'
            title      = 'Error en Active Directory'
            message    = "Ocurrió un error al consultar la cuenta '$cleanUser' en Active Directory: $($_.Exception.Message)"
            user       = $null
        }
    }
}

function Invoke-UserPasswordReset {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Username,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$NewPassword,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ConfirmPassword,
        [bool]$ChangePasswordAtLogon = $true,
        [bool]$UnlockAccount = $false,
        [scriptblock]$GetUserCommand = $null,
        [scriptblock]$SetPasswordCommand = $null,
        [scriptblock]$SetChangeAtLogonCommand = $null,
        [scriptblock]$UnlockAccountCommand = $null
    )

    $cleanUser = if ($null -ne $Username) { $Username.Trim().ToLowerInvariant() } else { '' }

    if (-not (Test-ValidUsernameFormat -Username $cleanUser)) {
        return [PSCustomObject]@{
            httpStatus = 400
            success    = $false
            code       = 'INVALID_FORMAT'
            title      = 'Formato de usuario inválido'
            message    = "El usuario ingresado debe tener el formato 'nombre.apellido'."
            user       = $null
        }
    }

    if ([string]::IsNullOrEmpty($NewPassword) -or [string]::IsNullOrEmpty($ConfirmPassword)) {
        return [PSCustomObject]@{
            httpStatus = 400
            success    = $false
            code       = 'EMPTY_PASSWORD'
            title      = 'Contraseña requerida'
            message    = 'Los campos Contraseña nueva y Confirmar contraseña no pueden estar vacíos.'
            user       = $null
        }
    }

    if ($NewPassword -cne $ConfirmPassword) {
        return [PSCustomObject]@{
            httpStatus = 400
            success    = $false
            code       = 'PASSWORD_MISMATCH'
            title      = 'Las contraseñas no coinciden'
            message    = 'La contraseña nueva y su confirmación deben coincidir exactamente.'
            user       = $null
        }
    }

    try {
        $adUser = if ($null -ne $GetUserCommand) {
            & $GetUserCommand $cleanUser
        } else {
            Get-TargetADUser -Username $cleanUser
        }

        if ($null -eq $adUser) {
            return [PSCustomObject]@{
                httpStatus = 404
                success    = $false
                code       = 'USER_NOT_FOUND'
                title      = 'Usuario no encontrado'
                message    = "La cuenta '$cleanUser' no existe en el Directorio Activo."
                user       = $null
            }
        }

        $userSummary = [PSCustomObject]@{
            username    = [string]$adUser.SamAccountName
            displayName = [string]$adUser.DisplayName
            enabled     = [bool]$adUser.Enabled
            lockedOut   = [bool]$adUser.LockedOut
        }

        # Regla de Negocio Estricta: Si el usuario esta INHABILITADO, NO se puede cambiar su contrasena
        if (-not [bool]$adUser.Enabled) {
            return [PSCustomObject]@{
                httpStatus = 422
                success    = $false
                code       = 'ACCOUNT_DISABLED'
                title      = 'Cuenta inhabilitada'
                message    = "No es posible cambiar la contraseña del usuario '$cleanUser' porque su cuenta se encuentra INHABILITADA en el Directorio Activo."
                user       = $userSummary
            }
        }

        $securePassword = ConvertTo-SecureString -String $NewPassword -AsPlainText -Force

        if ($null -ne $SetPasswordCommand) {
            & $SetPasswordCommand $cleanUser $securePassword
        } else {
            Initialize-ADModule
            Set-ADAccountPassword -Identity $cleanUser -Reset -NewPassword $securePassword -ErrorAction Stop
        }

        if ($null -ne $SetChangeAtLogonCommand) {
            & $SetChangeAtLogonCommand $cleanUser $ChangePasswordAtLogon
        } else {
            Initialize-ADModule
            if ($ChangePasswordAtLogon) {
                Set-ADUser -Identity $cleanUser -PasswordNeverExpires $false -ChangePasswordAtLogon $true -ErrorAction Stop
            } else {
                Set-ADUser -Identity $cleanUser -ChangePasswordAtLogon $false -ErrorAction Stop
            }
        }

        if ($UnlockAccount) {
            if ($null -ne $UnlockAccountCommand) {
                & $UnlockAccountCommand $cleanUser
            } else {
                Initialize-ADModule
                Unlock-ADAccount -Identity $cleanUser -ErrorAction Stop
            }
            $userSummary.lockedOut = $false
        }

        $displayLabel = if (-not [string]::IsNullOrWhiteSpace($userSummary.displayName)) {
            " ($($userSummary.displayName))"
        } else {
            ""
        }

        $details = @("La contraseña de la cuenta '$cleanUser'$displayLabel ha sido restablecida exitosamente.")
        if ($ChangePasswordAtLogon) {
            $details += "El usuario deberá cambiar la contraseña en el siguiente inicio de sesión."
        }
        if ($UnlockAccount) {
            $details += "La cuenta también fue desbloqueada."
        }

        return [PSCustomObject]@{
            httpStatus = 200
            success    = $true
            code       = 'PASSWORD_RESET_SUCCESS'
            title      = 'Cambio de contraseña exitoso'
            message    = ($details -join ' ')
            user       = $userSummary
        }
    } catch {
        $isPolicyError = ($_.Exception.GetType().Name -eq 'ADPasswordComplexityException') -or ($_.FullyQualifiedErrorId -like '*ADPasswordComplexityException*')
        $statusCode = if ($isPolicyError) { 422 } else { 500 }
        $errorCode = if ($isPolicyError) { 'PASSWORD_POLICY_ERROR' } else { 'AD_ERROR' }
        $errorTitle = if ($isPolicyError) { 'Política de contraseñas del dominio' } else { 'Error al restablecer contraseña' }

        return [PSCustomObject]@{
            httpStatus = $statusCode
            success    = $false
            code       = $errorCode
            title      = $errorTitle
            message    = "No fue posible cambiar la contraseña de '$cleanUser' en Active Directory: $($_.Exception.Message)"
            user       = $null
        }
    }
}

function Invoke-UnlockApiController {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SessionInfo,
        [AllowEmptyString()]
        [string]$RawBody,
        [scriptblock]$GetUserCommand = $null,
        [scriptblock]$UnlockAccountCommand = $null
    )

    if (-not $SessionInfo.authorized) {
        return [PSCustomObject]@{
            httpStatus = 403
            body       = [PSCustomObject]@{
                success = $false
                code    = 'FORBIDDEN'
                title   = 'Acceso denegado'
                message = $SessionInfo.message
                user    = $null
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($RawBody)) {
        return [PSCustomObject]@{
            httpStatus = 400
            body       = [PSCustomObject]@{
                success = $false
                code    = 'INVALID_PAYLOAD'
                title   = 'Solicitud inválida'
                message = 'El cuerpo de la petición no puede estar vacío.'
                user    = $null
            }
        }
    }

    $parsed = $null
    try {
        $parsed = $RawBody | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return [PSCustomObject]@{
            httpStatus = 400
            body       = [PSCustomObject]@{
                success = $false
                code    = 'INVALID_JSON'
                title   = 'Formato JSON inválido'
                message = 'El cuerpo de la petición no contiene un formato JSON válido.'
                user    = $null
            }
        }
    }

    $usernameProp = $parsed.PSObject.Properties['username']
    if ($null -eq $usernameProp -or $null -eq $usernameProp.Value) {
        return [PSCustomObject]@{
            httpStatus = 400
            body       = [PSCustomObject]@{
                success = $false
                code    = 'MISSING_USERNAME'
                title   = 'Usuario requerido'
                message = 'Debe proporcionar el campo username en la solicitud.'
                user    = $null
            }
        }
    }

    $username = [string]$usernameProp.Value
    $result = Invoke-UserUnlock -Username $username -GetUserCommand $GetUserCommand -UnlockAccountCommand $UnlockAccountCommand

    return [PSCustomObject]@{
        httpStatus = $result.httpStatus
        body       = [PSCustomObject]@{
            success = $result.success
            code    = $result.code
            title   = $result.title
            message = $result.message
            user    = $result.user
        }
    }
}

function Invoke-UserStatusApiController {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SessionInfo,
        [AllowEmptyString()]
        [string]$RawBody,
        [scriptblock]$GetUserCommand = $null
    )

    if (-not $SessionInfo.authorized) {
        return [PSCustomObject]@{
            httpStatus = 403
            body       = [PSCustomObject]@{
                success = $false
                code    = 'FORBIDDEN'
                title   = 'Acceso denegado'
                message = $SessionInfo.message
                user    = $null
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($RawBody)) {
        return [PSCustomObject]@{
            httpStatus = 400
            body       = [PSCustomObject]@{
                success = $false
                code    = 'INVALID_PAYLOAD'
                title   = 'Solicitud inválida'
                message = 'El cuerpo de la petición no puede estar vacío.'
                user    = $null
            }
        }
    }

    $parsed = $null
    try {
        $parsed = $RawBody | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return [PSCustomObject]@{
            httpStatus = 400
            body       = [PSCustomObject]@{
                success = $false
                code    = 'INVALID_JSON'
                title   = 'Formato JSON inválido'
                message = 'El cuerpo de la petición no contiene un formato JSON válido.'
                user    = $null
            }
        }
    }

    $usernameProp = $parsed.PSObject.Properties['username']
    if ($null -eq $usernameProp -or $null -eq $usernameProp.Value) {
        return [PSCustomObject]@{
            httpStatus = 400
            body       = [PSCustomObject]@{
                success = $false
                code    = 'MISSING_USERNAME'
                title   = 'Usuario requerido'
                message = 'Debe proporcionar el campo username en la solicitud.'
                user    = $null
            }
        }
    }

    $username = [string]$usernameProp.Value
    $result = Invoke-UserStatusCheck -Username $username -GetUserCommand $GetUserCommand

    return [PSCustomObject]@{
        httpStatus = $result.httpStatus
        body       = [PSCustomObject]@{
            success = $result.success
            code    = $result.code
            title   = $result.title
            message = $result.message
            user    = $result.user
        }
    }
}

function Invoke-PasswordResetApiController {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SessionInfo,
        [AllowEmptyString()]
        [string]$RawBody,
        [scriptblock]$GetUserCommand = $null,
        [scriptblock]$SetPasswordCommand = $null,
        [scriptblock]$SetChangeAtLogonCommand = $null,
        [scriptblock]$UnlockAccountCommand = $null
    )

    if (-not $SessionInfo.authorized) {
        return [PSCustomObject]@{
            httpStatus = 403
            body       = [PSCustomObject]@{
                success = $false
                code    = 'FORBIDDEN'
                title   = 'Acceso denegado'
                message = $SessionInfo.message
                user    = $null
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($RawBody)) {
        return [PSCustomObject]@{
            httpStatus = 400
            body       = [PSCustomObject]@{
                success = $false
                code    = 'INVALID_PAYLOAD'
                title   = 'Solicitud inválida'
                message = 'El cuerpo de la petición no puede estar vacío.'
                user    = $null
            }
        }
    }

    $parsed = $null
    try {
        $parsed = $RawBody | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return [PSCustomObject]@{
            httpStatus = 400
            body       = [PSCustomObject]@{
                success = $false
                code    = 'INVALID_JSON'
                title   = 'Formato JSON inválido'
                message = 'El cuerpo de la petición no contiene un formato JSON válido.'
                user    = $null
            }
        }
    }

    $usernameProp = $parsed.PSObject.Properties['username']
    if ($null -eq $usernameProp -or $null -eq $usernameProp.Value) {
        return [PSCustomObject]@{
            httpStatus = 400
            body       = [PSCustomObject]@{
                success = $false
                code    = 'MISSING_USERNAME'
                title   = 'Usuario requerido'
                message = 'Debe proporcionar el campo username en la solicitud.'
                user    = $null
            }
        }
    }

    $newPassProp = $parsed.PSObject.Properties['newPassword']
    $confirmPassProp = $parsed.PSObject.Properties['confirmPassword']
    $newPassword = if ($null -ne $newPassProp -and $null -ne $newPassProp.Value) { [string]$newPassProp.Value } else { '' }
    $confirmPassword = if ($null -ne $confirmPassProp -and $null -ne $confirmPassProp.Value) { [string]$confirmPassProp.Value } else { '' }

    $changeAtLogonProp = $parsed.PSObject.Properties['changePasswordAtLogon']
    $changePasswordAtLogon = if ($null -ne $changeAtLogonProp -and $null -ne $changeAtLogonProp.Value) {
        [bool]$changeAtLogonProp.Value
    } else {
        $true
    }

    $unlockProp = $parsed.PSObject.Properties['unlockAccount']
    $unlockAccount = if ($null -ne $unlockProp -and $null -ne $unlockProp.Value) {
        [bool]$unlockProp.Value
    } else {
        $false
    }

    $result = Invoke-UserPasswordReset `
        -Username ([string]$usernameProp.Value) `
        -NewPassword $newPassword `
        -ConfirmPassword $confirmPassword `
        -ChangePasswordAtLogon $changePasswordAtLogon `
        -UnlockAccount $unlockAccount `
        -GetUserCommand $GetUserCommand `
        -SetPasswordCommand $SetPasswordCommand `
        -SetChangeAtLogonCommand $SetChangeAtLogonCommand `
        -UnlockAccountCommand $UnlockAccountCommand

    return [PSCustomObject]@{
        httpStatus = $result.httpStatus
        body       = [PSCustomObject]@{
            success = $result.success
            code    = $result.code
            title   = $result.title
            message = $result.message
            user    = $result.user
        }
    }
}
