# Servicio de integracion con Active Directory y Control de Acceso
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Grupos de Active Directory autorizados por defecto para usar la aplicacion
$script:AuthorizedADGroups = @(
    'Admins. del dominio',
    'Domain Admins'
)

# Ruta de la Unidad Organizativa de cuentas inactivas para Paz y Salvo
$script:InactiveOUDistinguishedName = 'OU=AL_INACTIVOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co'

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

    return ($trimmed -match '^[a-zA-Z0-9._-]+$')
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
            message    = 'Ingrese un nombre de usuario de dominio válido sin espacios.'
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
            message    = 'Ingrese un nombre de usuario de dominio válido sin espacios.'
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
            message    = 'Ingrese un nombre de usuario de dominio válido sin espacios.'
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

function ConvertTo-NormalizedADSearchText {
    param(
        [AllowEmptyString()]
        [string]$InputText = ''
    )

    if ([string]::IsNullOrWhiteSpace($InputText)) {
        return ''
    }

    # 1. Reemplazar el caracter de reemplazo Unicode U+FFFD (si el CSV ya venia corrupto de origen) por comodin '*'
    $text = $InputText.Trim() -replace "[$([char]0xFFFD)]+", '*'

    # 2. Descomponer caracteres Unicode (FormD) para separar letras base de tildes, dieresis y virgulilla de la ñ/Ñ
    $formD = $text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder

    foreach ($ch in $formD.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }

    $clean = $sb.ToString().Normalize([System.Text.NormalizationForm]::FormC)

    # 3. Compactar espacios multiples y comodines repetidos
    $clean = ($clean -replace '\s+', ' ').Trim()
    $clean = $clean -replace '\*{2,}', '*'

    return $clean
}

function ConvertFrom-CsvToMatrix {
    param(
        [AllowEmptyString()]
        [string]$CsvText = ''
    )

    if ([string]::IsNullOrWhiteSpace($CsvText)) {
        return ,(@())
    }

    $cleanText = $CsvText.TrimStart([char]0xFEFF)
    $chars = $cleanText.ToCharArray()
    $len = $chars.Length

    # Detectar delimitador (',' vs ';') contando ocurrencias fuera de comillas en los primeros 4000 caracteres
    $sampleLimit = [Math]::Min($len, 4000)
    $inQuotesSample = $false
    $commaCount = 0
    $semicolonCount = 0

    for ($s = 0; $s -lt $sampleLimit; $s++) {
        $c = $chars[$s]
        if ($c -eq '"') {
            $inQuotesSample = -not $inQuotesSample
        } elseif (-not $inQuotesSample) {
            if ($c -eq ',') { $commaCount++ }
            elseif ($c -eq ';') { $semicolonCount++ }
        }
    }

    $delimiter = if ($semicolonCount -gt $commaCount) { [char]';' } else { [char]',' }

    $rows = New-Object System.Collections.Generic.List[object]
    $currentRow = New-Object System.Collections.Generic.List[string]
    $cellSb = New-Object System.Text.StringBuilder
    $inQuotes = $false

    for ($i = 0; $i -lt $len; $i++) {
        $ch = $chars[$i]

        if ($inQuotes) {
            if ($ch -eq '"') {
                if (($i + 1) -lt $len -and $chars[$i + 1] -eq '"') {
                    [void]$cellSb.Append('"')
                    $i++
                } else {
                    $inQuotes = $false
                }
            } else {
                [void]$cellSb.Append($ch)
            }
        } else {
            if ($ch -eq '"') {
                $inQuotes = $true
            } elseif ($ch -eq $delimiter) {
                [void]$currentRow.Add($cellSb.ToString())
                [void]$cellSb.Clear()
            } elseif ($ch -eq "`r" -or $ch -eq "`n") {
                if ($ch -eq "`r" -and ($i + 1) -lt $len -and $chars[$i + 1] -eq "`n") {
                    $i++
                }
                [void]$currentRow.Add($cellSb.ToString())
                [void]$cellSb.Clear()
                [void]$rows.Add($currentRow.ToArray())
                $currentRow = New-Object System.Collections.Generic.List[string]
            } else {
                [void]$cellSb.Append($ch)
            }
        }
    }

    if ($cellSb.Length -gt 0 -or $currentRow.Count -gt 0) {
        [void]$currentRow.Add($cellSb.ToString())
        [void]$rows.Add($currentRow.ToArray())
    }

    return ,($rows.ToArray())
}

function Get-ExcelColumnIndexFromCellRef {
    param(
        [AllowEmptyString()]
        [string]$CellRef = ''
    )

    if ([string]::IsNullOrWhiteSpace($CellRef)) {
        return -1
    }

    if ($CellRef -notmatch '^([A-Za-z]+)') {
        return -1
    }

    $letters = $Matches[1].ToUpperInvariant()
    $colIndex = 0
    foreach ($ch in $letters.ToCharArray()) {
        $colIndex = ($colIndex * 26) + ([int][char]$ch - [int][char]'A' + 1)
    }

    return ($colIndex - 1)
}

function ConvertFrom-XlsxBase64ToSheetsMatrix {
    param(
        [Parameter(Mandatory = $true)]
        [string]$XlsxBase64
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop

    $cleanBase64 = ($XlsxBase64.Trim() -replace '^data:[^;]+;base64,', '')
    $bytes = [Convert]::FromBase64String($cleanBase64)

    $memStream = New-Object System.IO.MemoryStream(,$bytes)
    $zip = $null

    try {
        $zip = New-Object System.IO.Compression.ZipArchive($memStream, [System.IO.Compression.ZipArchiveMode]::Read)

        # 1. Leer tabla de textos compartidos (xl/sharedStrings.xml) si existe
        $sharedStrings = New-Object System.Collections.Generic.List[string]
        $ssEntry = $zip.Entries | Where-Object { $_.FullName -ieq 'xl/sharedStrings.xml' } | Select-Object -First 1

        if ($null -ne $ssEntry) {
            $ssStream = $ssEntry.Open()
            $ssReader = New-Object System.IO.StreamReader($ssStream, [System.Text.Encoding]::UTF8)
            try {
                [xml]$ssXml = $ssReader.ReadToEnd()
                $siNodes = $ssXml.SelectNodes("//*[local-name()='si']")
                if ($null -ne $siNodes) {
                    foreach ($si in $siNodes) {
                        $tNodes = $si.SelectNodes(".//*[local-name()='t']")
                        if ($null -ne $tNodes -and $tNodes.Count -gt 0) {
                            $parts = @($tNodes | ForEach-Object { $_.InnerText })
                            [void]$sharedStrings.Add(($parts -join ''))
                        } else {
                            [void]$sharedStrings.Add('')
                        }
                    }
                }
            } finally {
                $ssReader.Close()
                $ssStream.Close()
            }
        }

        # 2. Localizar hojas de trabajo (xl/worksheets/sheet*.xml) en orden
        $sheetEntries = @(
            $zip.Entries |
            Where-Object { $_.FullName -imatch '^xl/worksheets/sheet\d*\.xml$' } |
            Sort-Object {
                if ($_.Name -match '(\d+)') { [int]$Matches[1] } else { 0 }
            }
        )

        if ($sheetEntries.Count -eq 0) {
            throw "El archivo .xlsx no contiene hojas de cálculo válidas."
        }

        $sheetsList = New-Object System.Collections.Generic.List[object]

        foreach ($sheetEntry in $sheetEntries) {
            $sheetStream = $sheetEntry.Open()
            $sheetReader = New-Object System.IO.StreamReader($sheetStream, [System.Text.Encoding]::UTF8)
            try {
                [xml]$sheetXml = $sheetReader.ReadToEnd()
                $rowNodes = $sheetXml.SelectNodes("//*[local-name()='sheetData']/*[local-name()='row']")
                $sheetRows = New-Object System.Collections.Generic.List[object]
                $maxColNeeded = -1

                if ($null -ne $rowNodes) {
                    foreach ($rowNode in $rowNodes) {
                        $cellNodes = $rowNode.SelectNodes("./*[local-name()='c']")
                        if ($null -eq $cellNodes -or $cellNodes.Count -eq 0) {
                            [void]$sheetRows.Add(@())
                            continue
                        }

                        $rowCells = New-Object System.Collections.Generic.List[string]
                        $nextSequentialCol = 0
                        $seenNombreInRow = -1
                        $seenApellidoInRow = -1

                        foreach ($cellNode in $cellNodes) {
                            $refAttr = $cellNode.GetAttribute('r')
                            $colIdx = Get-ExcelColumnIndexFromCellRef -CellRef $refAttr
                            if ($colIdx -lt 0) {
                                $colIdx = $nextSequentialCol
                            }

                            # Si ya se identificaron las columnas NOMBRE y APELLIDO en esta hoja, detener lectura en la columna limite
                            if ($maxColNeeded -ge 0 -and $colIdx -gt $maxColNeeded) {
                                break
                            }

                            while ($rowCells.Count -lt $colIdx) {
                                [void]$rowCells.Add('')
                            }

                            $cellType = $cellNode.GetAttribute('t')
                            $cellText = ''

                            if ($cellType -eq 's') {
                                $vNode = $cellNode.SelectSingleNode("./*[local-name()='v']")
                                if ($null -ne $vNode -and -not [string]::IsNullOrWhiteSpace($vNode.InnerText)) {
                                    $ssIdx = 0
                                    if ([int]::TryParse($vNode.InnerText.Trim(), [ref]$ssIdx) -and $ssIdx -ge 0 -and $ssIdx -lt $sharedStrings.Count) {
                                        $cellText = $sharedStrings[$ssIdx]
                                    }
                                }
                            } elseif ($cellType -eq 'inlineStr') {
                                $tNodes = $cellNode.SelectNodes(".//*[local-name()='t']")
                                if ($null -ne $tNodes -and $tNodes.Count -gt 0) {
                                    $parts = @($tNodes | ForEach-Object { $_.InnerText })
                                    $cellText = ($parts -join '')
                                }
                            } else {
                                $vNode = $cellNode.SelectSingleNode("./*[local-name()='v']")
                                if ($null -ne $vNode) {
                                    $cellText = $vNode.InnerText
                                }
                            }

                            [void]$rowCells.Add($cellText)
                            $nextSequentialCol = $colIdx + 1

                            if ($maxColNeeded -lt 0) {
                                $normCandidate = (ConvertTo-NormalizedADSearchText -InputText $cellText).Trim().ToUpperInvariant()
                                if ($seenNombreInRow -lt 0 -and $normCandidate -eq 'NOMBRE') {
                                    $seenNombreInRow = $colIdx
                                } elseif ($seenApellidoInRow -lt 0 -and $normCandidate -eq 'APELLIDO') {
                                    $seenApellidoInRow = $colIdx
                                }

                                if ($seenNombreInRow -ge 0 -and $seenApellidoInRow -ge 0) {
                                    $maxColNeeded = [Math]::Max($seenNombreInRow, $seenApellidoInRow)
                                    break
                                }
                            }
                        }

                        [void]$sheetRows.Add($rowCells.ToArray())
                    }
                }

                [void]$sheetsList.Add($sheetRows.ToArray())
            } finally {
                $sheetReader.Close()
                $sheetStream.Close()
            }
        }

        return ,($sheetsList.ToArray())
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
        if ($null -ne $memStream) { $memStream.Dispose() }
    }
}

function Get-NombreApellidoRecordsFromMatrix {
    param(
        [AllowEmptyCollection()]
        [object[]]$Rows
    )

    if ($null -eq $Rows -or $Rows.Count -eq 0) {
        return [PSCustomObject]@{
            FoundHeaders    = $false
            DetectedHeaders = @()
            Records         = @()
        }
    }

    $headerRowIndex = -1
    $nombreColIdx = -1
    $apellidoColIdx = -1
    $detectedSample = @()

    for ($r = 0; $r -lt $Rows.Count; $r++) {
        $row = @($Rows[$r])
        if ($row.Count -eq 0) {
            continue
        }

        $tempNombreIdx = -1
        $tempApellidoIdx = -1
        $nonEmptyCellsInRow = @()

        for ($c = 0; $c -lt $row.Count; $c++) {
            $cellVal = if ($null -ne $row[$c]) { [string]$row[$c] } else { '' }
            $normHeader = (ConvertTo-NormalizedADSearchText -InputText $cellVal).Trim().ToUpperInvariant()

            if (-not [string]::IsNullOrWhiteSpace($normHeader)) {
                $nonEmptyCellsInRow += $normHeader
            }

            if ($tempNombreIdx -lt 0 -and $normHeader -eq 'NOMBRE') {
                $tempNombreIdx = $c
            } elseif ($tempApellidoIdx -lt 0 -and $normHeader -eq 'APELLIDO') {
                $tempApellidoIdx = $c
            }

            # Detener la lectura de columnas apenas se encuentren NOMBRE y APELLIDO (ignora columnas repetidas posteriores)
            if ($tempNombreIdx -ge 0 -and $tempApellidoIdx -ge 0) {
                break
            }
        }

        if ($detectedSample.Count -eq 0 -and $nonEmptyCellsInRow.Count -gt 0) {
            $detectedSample = $nonEmptyCellsInRow
        }

        if ($tempNombreIdx -ge 0 -and $tempApellidoIdx -ge 0) {
            $headerRowIndex = $r
            $nombreColIdx = $tempNombreIdx
            $apellidoColIdx = $tempApellidoIdx
            break
        }
    }

    if ($headerRowIndex -lt 0) {
        return [PSCustomObject]@{
            FoundHeaders    = $false
            DetectedHeaders = $detectedSample
            Records         = @()
        }
    }

    $records = New-Object System.Collections.Generic.List[object]

    for ($r = ($headerRowIndex + 1); $r -lt $Rows.Count; $r++) {
        $row = @($Rows[$r])

        $rawNom = if ($nombreColIdx -lt $row.Count -and $null -ne $row[$nombreColIdx]) { [string]$row[$nombreColIdx] } else { '' }
        $rawApe = if ($apellidoColIdx -lt $row.Count -and $null -ne $row[$apellidoColIdx]) { [string]$row[$apellidoColIdx] } else { '' }

        $nom = $rawNom.Trim()
        $ape = $rawApe.Trim()

        if ($nom -in @('NaN', '0', 'N/A')) { $nom = '' }
        if ($ape -in @('NaN', '0', 'N/A')) { $ape = '' }

        if ([string]::IsNullOrWhiteSpace($nom) -and [string]::IsNullOrWhiteSpace($ape)) {
            if ($records.Count -gt 0) {
                # Fin de la tabla principal de colaboradores
                break
            }
            continue
        }

        [void]$records.Add([PSCustomObject]@{
            Nombre   = $nom
            Apellido = $ape
        })
    }

    return [PSCustomObject]@{
        FoundHeaders    = $true
        DetectedHeaders = @('NOMBRE', 'APELLIDO')
        Records         = $records.ToArray()
    }
}

function Invoke-BulkDisablePreview {
    param(
        [AllowEmptyString()]
        [string]$CsvContent = '',
        [AllowEmptyString()]
        [string]$XlsxBase64 = '',
        [scriptblock]$SearchUsersCommand = $null
    )

    $hasCsv = -not [string]::IsNullOrWhiteSpace($CsvContent)
    $hasXlsx = -not [string]::IsNullOrWhiteSpace($XlsxBase64)

    if (-not $hasCsv -and -not $hasXlsx) {
        return [PSCustomObject]@{
            httpStatus    = 400
            success       = $false
            code          = 'EMPTY_CSV'
            title         = 'Archivo vacío'
            message       = 'El archivo seleccionado está vacío.'
            users         = @()
            unmatchedRows = @()
        }
    }

    $tableExtract = $null

    if ($hasXlsx) {
        try {
            $sheets = ConvertFrom-XlsxBase64ToSheetsMatrix -XlsxBase64 $XlsxBase64
            foreach ($sheetRows in $sheets) {
                $candidate = Get-NombreApellidoRecordsFromMatrix -Rows $sheetRows
                if ($null -eq $tableExtract) {
                    $tableExtract = $candidate
                }
                if ($candidate.FoundHeaders) {
                    $tableExtract = $candidate
                    break
                }
            }
        } catch {
            return [PSCustomObject]@{
                httpStatus    = 400
                success       = $false
                code          = 'INVALID_CSV_FORMAT'
                title         = 'Error de formato Excel (.xlsx)'
                message       = "No fue posible procesar el archivo Excel (.xlsx): $($_.Exception.Message)"
                users         = @()
                unmatchedRows = @()
            }
        }
    } else {
        try {
            $matrix = ConvertFrom-CsvToMatrix -CsvText $CsvContent
            if ($null -eq $matrix -or $matrix.Count -eq 0) {
                return [PSCustomObject]@{
                    httpStatus    = 400
                    success       = $false
                    code          = 'EMPTY_CSV'
                    title         = 'Archivo vacío'
                    message       = 'El archivo no contiene líneas válidas.'
                    users         = @()
                    unmatchedRows = @()
                }
            }
            $tableExtract = Get-NombreApellidoRecordsFromMatrix -Rows $matrix
        } catch {
            return [PSCustomObject]@{
                httpStatus    = 400
                success       = $false
                code          = 'INVALID_CSV_FORMAT'
                title         = 'Error de formato de archivo'
                message       = "No fue posible procesar el archivo: $($_.Exception.Message)"
                users         = @()
                unmatchedRows = @()
            }
        }
    }

    if ($null -eq $tableExtract -or (-not $tableExtract.FoundHeaders)) {
        $detectedList = if ($null -ne $tableExtract -and $tableExtract.DetectedHeaders.Count -gt 0) {
            ($tableExtract.DetectedHeaders -join ', ')
        } else {
            'Ninguna'
        }
        return [PSCustomObject]@{
            httpStatus    = 400
            success       = $false
            code          = 'INVALID_CSV_HEADERS'
            title         = 'Columnas requeridas faltantes'
            message       = "El archivo debe contener una fila con las columnas 'NOMBRE' y 'APELLIDO'. Columnas detectadas: $detectedList"
            users         = @()
            unmatchedRows = @()
        }
    }

    $extractedRecords = @($tableExtract.Records)
    if ($extractedRecords.Count -eq 0) {
        return [PSCustomObject]@{
            httpStatus    = 400
            success       = $false
            code          = 'EMPTY_CSV_ROWS'
            title         = 'Sin filas de datos'
            message       = 'El archivo no contiene filas de colaboradores debajo de los encabezados NOMBRE y APELLIDO.'
            users         = @()
            unmatchedRows = @()
        }
    }

    $foundUsers = @()
    $unmatchedRows = @()
    $seenUsers = @{}

    try {
        if ($null -eq $SearchUsersCommand) {
            Initialize-ADModule
        }

        foreach ($rec in $extractedRecords) {
            $nombreOriginal = if ($null -ne $rec.Nombre) { [string]$rec.Nombre } else { '' }
            $apellidoOriginal = if ($null -ne $rec.Apellido) { [string]$rec.Apellido } else { '' }

            if ([string]::IsNullOrWhiteSpace($nombreOriginal) -and [string]::IsNullOrWhiteSpace($apellidoOriginal)) {
                continue
            }

            # Normalizar Ñ -> N, vocales con tilde/dieresis -> vocales simples, y U+FFFD -> '*'
            $nombre = ConvertTo-NormalizedADSearchText -InputText $nombreOriginal
            $apellido = ConvertTo-NormalizedADSearchText -InputText $apellidoOriginal

            $matchesAD = @()
            if ($null -ne $SearchUsersCommand) {
                $matchesAD = @(& $SearchUsersCommand $nombre $apellido)
            } else {
                $safeNombre = $nombre -replace "'", "''"
                $safeApellido = $apellido -replace "'", "''"

                $primaryFilter = "Enabled -eq '$true' -and GivenName -like '*$safeNombre*' -and Surname -like '*$safeApellido*'"
                $matchesAD = @(Get-ADUser -Filter $primaryFilter -Properties SamAccountName, Name, DisplayName, GivenName, Surname, Enabled, Description, DistinguishedName -ErrorAction Stop)

                if ($matchesAD.Count -eq 0) {
                    $fallbackFilter = "Enabled -eq '$true' -and (Name -like '*$safeNombre*$safeApellido*' -or DisplayName -like '*$safeNombre*$safeApellido*' -or SamAccountName -like '*$safeNombre*$safeApellido*')"
                    $matchesAD = @(Get-ADUser -Filter $fallbackFilter -Properties SamAccountName, Name, DisplayName, GivenName, Surname, Enabled, Description, DistinguishedName -ErrorAction Stop)
                }

                # Si no hubo coincidencia con el texto sin tildes/Ñ y el original tenia tildes/Ñ, probar tambien con la grafia original
                $hasOriginalVariant = ($nombreOriginal -ne $nombre -or $apellidoOriginal -ne $apellido) -and (-not $nombreOriginal.Contains([char]0xFFFD)) -and (-not $apellidoOriginal.Contains([char]0xFFFD))
                if ($matchesAD.Count -eq 0 -and $hasOriginalVariant) {
                    $safeOrigNombre = $nombreOriginal -replace "'", "''"
                    $safeOrigApellido = $apellidoOriginal -replace "'", "''"

                    $origPrimaryFilter = "Enabled -eq '$true' -and GivenName -like '*$safeOrigNombre*' -and Surname -like '*$safeOrigApellido*'"
                    $matchesAD = @(Get-ADUser -Filter $origPrimaryFilter -Properties SamAccountName, Name, DisplayName, GivenName, Surname, Enabled, Description, DistinguishedName -ErrorAction Stop)

                    if ($matchesAD.Count -eq 0) {
                        $origFallbackFilter = "Enabled -eq '$true' -and (Name -like '*$safeOrigNombre*$safeOrigApellido*' -or DisplayName -like '*$safeOrigNombre*$safeOrigApellido*' -or SamAccountName -like '*$safeOrigNombre*$safeOrigApellido*')"
                        $matchesAD = @(Get-ADUser -Filter $origFallbackFilter -Properties SamAccountName, Name, DisplayName, GivenName, Surname, Enabled, Description, DistinguishedName -ErrorAction Stop)
                    }
                }
            }

            $activeMatches = @($matchesAD | Where-Object { $null -ne $_ -and [bool]$_.Enabled })

            if ($activeMatches.Count -eq 0) {
                $displayLabelNom = if ($nombreOriginal.Contains([char]0xFFFD)) { $nombre } else { $nombreOriginal }
                $displayLabelApe = if ($apellidoOriginal.Contains([char]0xFFFD)) { $apellido } else { $apellidoOriginal }
                $fullNameLabel = ("$displayLabelNom $displayLabelApe").Trim()
                if ($fullNameLabel -notin $unmatchedRows) {
                    $unmatchedRows += $fullNameLabel
                }
                continue
            }

            foreach ($adUser in $activeMatches) {
                $samKey = ([string]$adUser.SamAccountName).Trim().ToLowerInvariant()
                if ($seenUsers.ContainsKey($samKey)) {
                    continue
                }
                $seenUsers[$samKey] = $true

                $displayGiven = if (-not [string]::IsNullOrWhiteSpace($adUser.GivenName)) { [string]$adUser.GivenName } else { $nombre }
                $displaySurname = if (-not [string]::IsNullOrWhiteSpace($adUser.Surname)) { [string]$adUser.Surname } else { $apellido }
                $descText = if ($null -ne $adUser.Description) { [string]$adUser.Description } else { '' }

                $foundUsers += [PSCustomObject]@{
                    nombre      = $displayGiven
                    apellido    = $displaySurname
                    usuario     = [string]$adUser.SamAccountName
                    estado      = 'Activo'
                    descripcion = $descText
                }
            }
        }

        if ($foundUsers.Count -eq 0) {
            return [PSCustomObject]@{
                httpStatus    = 404
                success       = $false
                code          = 'NO_ACTIVE_USERS_FOUND'
                title         = 'Sin coincidencias activas'
                message       = 'No se encontraron usuarios activos en el Directorio Activo para los registros del archivo.'
                users         = @()
                unmatchedRows = $unmatchedRows
            }
        }

        return [PSCustomObject]@{
            httpStatus    = 200
            success       = $true
            code          = 'PREVIEW_READY'
            title         = 'Análisis completado'
            message       = "Se encontraron $($foundUsers.Count) usuario(s) activo(s) en el Directorio Activo."
            users         = $foundUsers
            unmatchedRows = $unmatchedRows
        }
    } catch {
        return [PSCustomObject]@{
            httpStatus    = 500
            success       = $false
            code          = 'AD_SEARCH_ERROR'
            title         = 'Error en búsqueda masiva'
            message       = "Ocurrió un error al consultar Active Directory: $($_.Exception.Message)"
            users         = @()
            unmatchedRows = @()
        }
    }
}

function Invoke-BulkDisableExecute {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ProcessType,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Usernames,
        [scriptblock]$GetUserCommand = $null,
        [scriptblock]$DisableAccountCommand = $null,
        [scriptblock]$SetDescriptionCommand = $null,
        [scriptblock]$MoveObjectCommand = $null
    )

    $cleanProcess = if ($null -ne $ProcessType) { $ProcessType.Trim() } else { '' }
    $normalizedProcess = ''
    if ([string]::Equals($cleanProcess, 'Vacaciones', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalizedProcess = 'Vacaciones'
    } elseif ([string]::Equals($cleanProcess, 'Paz y Salvo', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalizedProcess = 'Paz y Salvo'
    } else {
        return [PSCustomObject]@{
            httpStatus     = 400
            success        = $false
            code           = 'INVALID_PROCESS_TYPE'
            title          = 'Tipo de proceso inválido'
            message        = "El tipo de proceso debe ser 'Vacaciones' o 'Paz y Salvo'."
            results        = @()
            processedCount = 0
            failedCount    = 0
        }
    }

    $cleanUsers = @()
    if ($null -ne $Usernames) {
        foreach ($u in $Usernames) {
            if (-not [string]::IsNullOrWhiteSpace($u)) {
                $trimmedUser = $u.Trim().ToLowerInvariant()
                if ($trimmedUser -notin $cleanUsers) {
                    $cleanUsers += $trimmedUser
                }
            }
        }
    }

    if ($cleanUsers.Count -eq 0) {
        return [PSCustomObject]@{
            httpStatus     = 400
            success        = $false
            code           = 'NO_USERS_SELECTED'
            title          = 'Sin usuarios seleccionados'
            message        = 'Debe seleccionar al menos un usuario para ejecutar la inhabilitación.'
            results        = @()
            processedCount = 0
            failedCount    = 0
        }
    }

    if ($null -eq $GetUserCommand -or $null -eq $DisableAccountCommand -or $null -eq $SetDescriptionCommand -or $null -eq $MoveObjectCommand) {
        Initialize-ADModule
    }

    $results = @()
    $processedCount = 0
    $failedCount = 0

    foreach ($cuenta in $cleanUsers) {
        if (-not (Test-ValidUsernameFormat -Username $cuenta)) {
            $failedCount++
            $results += [PSCustomObject]@{
                username = $cuenta
                success  = $false
                message  = "Formato de usuario inválido ('$cuenta')."
            }
            continue
        }

        try {
            $adUser = if ($null -ne $GetUserCommand) {
                & $GetUserCommand $cuenta
            } else {
                Get-ADUser -Identity $cuenta -Properties SamAccountName, Name, DisplayName, Enabled, Description, DistinguishedName -ErrorAction Stop
            }

            if ($null -eq $adUser) {
                $failedCount++
                $results += [PSCustomObject]@{
                    username = $cuenta
                    success  = $false
                    message  = "La cuenta '$cuenta' no fue encontrada en Active Directory."
                }
                continue
            }

            if ($normalizedProcess -eq 'Vacaciones') {
                if ($null -ne $DisableAccountCommand) {
                    & $DisableAccountCommand $cuenta
                } else {
                    Disable-ADAccount -Identity $cuenta -ErrorAction Stop
                }

                $processedCount++
                $results += [PSCustomObject]@{
                    username = $cuenta
                    success  = $true
                    message  = "Cuenta '$cuenta' inhabilitada por Vacaciones."
                }
            } elseif ($normalizedProcess -eq 'Paz y Salvo') {
                # Paso 1: Inhabilitar la cuenta
                if ($null -ne $DisableAccountCommand) {
                    & $DisableAccountCommand $cuenta
                } else {
                    Disable-ADAccount -Identity $cuenta -ErrorAction Stop
                }

                # Paso 2: Agregar prefijo '(R) ' al inicio de la descripcion sin duplicar
                $descBase = if ($null -ne $adUser.Description) { [string]$adUser.Description } else { '' }
                $nuevaDescripcion = ''
                if ($descBase -match '^\(R\)\s*') {
                    $nuevaDescripcion = $descBase
                } elseif ([string]::IsNullOrWhiteSpace($descBase)) {
                    $nuevaDescripcion = '(R)'
                } else {
                    $nuevaDescripcion = "(R) $descBase"
                }

                if ($null -ne $SetDescriptionCommand) {
                    & $SetDescriptionCommand $cuenta $nuevaDescripcion
                } else {
                    Set-ADUser -Identity $cuenta -Description $nuevaDescripcion -ErrorAction Stop
                }

                # Paso 3: Mover el objeto al OU de inactivos
                if ($null -ne $MoveObjectCommand) {
                    & $MoveObjectCommand ([string]$adUser.DistinguishedName) $script:InactiveOUDistinguishedName
                } else {
                    $objetoActualAD = Get-ADUser -Identity $cuenta -Properties DistinguishedName -ErrorAction Stop
                    Move-ADObject -Identity $objetoActualAD.DistinguishedName -TargetPath $script:InactiveOUDistinguishedName -ErrorAction Stop
                }

                $processedCount++
                $results += [PSCustomObject]@{
                    username = $cuenta
                    success  = $true
                    message  = "Cuenta '$cuenta' inhabilitada, descripción actualizada a '$nuevaDescripcion' y movida a AL_INACTIVOS."
                }
            }
        } catch {
            $failedCount++
            $results += [PSCustomObject]@{
                username = $cuenta
                success  = $false
                message  = "Fallo al procesar '$cuenta' ($normalizedProcess): $($_.Exception.Message)"
            }
        }
    }

    $overallSuccess = ($processedCount -gt 0 -and $failedCount -eq 0)
    $httpStatus = if ($processedCount -gt 0) { 200 } else { 422 }
    $code = if ($overallSuccess) {
        'BULK_DISABLE_SUCCESS'
    } elseif ($processedCount -gt 0) {
        'BULK_DISABLE_PARTIAL'
    } else {
        'BULK_DISABLE_FAILED'
    }

    $title = if ($overallSuccess) {
        "Inhabilitación masiva exitosa ($normalizedProcess)"
    } elseif ($processedCount -gt 0) {
        "Procesamiento parcial ($normalizedProcess)"
    } else {
        "Error en inhabilitación masiva ($normalizedProcess)"
    }

    $summaryDetails = @($results | ForEach-Object { $_.message })
    $summaryMessage = "Procesados exitosamente: $processedCount | Fallidos: $failedCount. " + ($summaryDetails -join ' ')

    return [PSCustomObject]@{
        httpStatus     = $httpStatus
        success        = $overallSuccess
        code           = $code
        title          = $title
        message        = $summaryMessage
        results        = $results
        processedCount = $processedCount
        failedCount    = $failedCount
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

function Invoke-BulkPreviewApiController {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SessionInfo,
        [AllowEmptyString()]
        [string]$RawBody,
        [scriptblock]$SearchUsersCommand = $null
    )

    if (-not $SessionInfo.authorized) {
        return [PSCustomObject]@{
            httpStatus = 403
            body       = [PSCustomObject]@{
                success       = $false
                code          = 'FORBIDDEN'
                title         = 'Acceso denegado'
                message       = $SessionInfo.message
                users         = @()
                unmatchedRows = @()
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($RawBody)) {
        return [PSCustomObject]@{
            httpStatus = 400
            body       = [PSCustomObject]@{
                success       = $false
                code          = 'INVALID_PAYLOAD'
                title         = 'Solicitud inválida'
                message       = 'El cuerpo de la petición no puede estar vacío.'
                users         = @()
                unmatchedRows = @()
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
                success       = $false
                code          = 'INVALID_JSON'
                title         = 'Formato JSON inválido'
                message       = 'El cuerpo de la petición no contiene un formato JSON válido.'
                users         = @()
                unmatchedRows = @()
            }
        }
    }

    $csvProp = $parsed.PSObject.Properties['csvContent']
    $xlsxProp = $parsed.PSObject.Properties['xlsxBase64']

    $csvVal = if ($null -ne $csvProp -and $null -ne $csvProp.Value) { [string]$csvProp.Value } else { '' }
    $xlsxVal = if ($null -ne $xlsxProp -and $null -ne $xlsxProp.Value) { [string]$xlsxProp.Value } else { '' }

    if (($null -eq $csvProp -or $null -eq $csvProp.Value) -and ($null -eq $xlsxProp -or $null -eq $xlsxProp.Value)) {
        return [PSCustomObject]@{
            httpStatus = 400
            body       = [PSCustomObject]@{
                success       = $false
                code          = 'MISSING_CSV_CONTENT'
                title         = 'Archivo requerido'
                message       = 'Debe proporcionar el contenido del archivo CSV o XLSX en la solicitud.'
                users         = @()
                unmatchedRows = @()
            }
        }
    }

    $result = Invoke-BulkDisablePreview -CsvContent $csvVal -XlsxBase64 $xlsxVal -SearchUsersCommand $SearchUsersCommand

    return [PSCustomObject]@{
        httpStatus = $result.httpStatus
        body       = [PSCustomObject]@{
            success       = $result.success
            code          = $result.code
            title         = $result.title
            message       = $result.message
            users         = $result.users
            unmatchedRows = $result.unmatchedRows
        }
    }
}

function Invoke-BulkExecuteApiController {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SessionInfo,
        [AllowEmptyString()]
        [string]$RawBody,
        [scriptblock]$GetUserCommand = $null,
        [scriptblock]$DisableAccountCommand = $null,
        [scriptblock]$SetDescriptionCommand = $null,
        [scriptblock]$MoveObjectCommand = $null
    )

    if (-not $SessionInfo.authorized) {
        return [PSCustomObject]@{
            httpStatus = 403
            body       = [PSCustomObject]@{
                success        = $false
                code           = 'FORBIDDEN'
                title          = 'Acceso denegado'
                message        = $SessionInfo.message
                results        = @()
                processedCount = 0
                failedCount    = 0
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($RawBody)) {
        return [PSCustomObject]@{
            httpStatus = 400
            body       = [PSCustomObject]@{
                success        = $false
                code           = 'INVALID_PAYLOAD'
                title          = 'Solicitud inválida'
                message        = 'El cuerpo de la petición no puede estar vacío.'
                results        = @()
                processedCount = 0
                failedCount    = 0
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
                success        = $false
                code           = 'INVALID_JSON'
                title          = 'Formato JSON inválido'
                message        = 'El cuerpo de la petición no contiene un formato JSON válido.'
                results        = @()
                processedCount = 0
                failedCount    = 0
            }
        }
    }

    $processProp = $parsed.PSObject.Properties['processType']
    $usersProp = $parsed.PSObject.Properties['usernames']

    $processType = if ($null -ne $processProp -and $null -ne $processProp.Value) { [string]$processProp.Value } else { '' }
    $usernames = @()
    if ($null -ne $usersProp -and $null -ne $usersProp.Value) {
        $usernames = @($usersProp.Value | ForEach-Object { [string]$_ })
    }

    $result = Invoke-BulkDisableExecute `
        -ProcessType $processType `
        -Usernames $usernames `
        -GetUserCommand $GetUserCommand `
        -DisableAccountCommand $DisableAccountCommand `
        -SetDescriptionCommand $SetDescriptionCommand `
        -MoveObjectCommand $MoveObjectCommand

    return [PSCustomObject]@{
        httpStatus = $result.httpStatus
        body       = [PSCustomObject]@{
            success        = $result.success
            code           = $result.code
            title          = $result.title
            message        = $result.message
            results        = $result.results
            processedCount = $result.processedCount
            failedCount    = $result.failedCount
        }
    }
}
