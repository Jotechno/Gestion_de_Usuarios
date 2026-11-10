# =============================================================================
# Script: Test-Inhabilitaciones.ps1
# Descripcion: PoC para inhabilitacion masiva de usuarios en Active Directory
#              por Vacaciones o Paz y Salvo (Mesa de Ayuda - Aliar).
#              Incluye seleccion de CSV mediante OpenFileDialog, confirmacion
#              en Out-GridView con columnas personalizadas y bucle de ejecucion.
# =============================================================================

param (
    [switch]$AutoRevertir,
    [switch]$SoloRevertir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Constantes del dominio y cuenta de pruebas autorizada
$CuentaPruebaAutorizada = "henkia.pruebas"
$OUInactivos            = "OU=AL_INACTIVOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co"
$OUPorDefectoPrueba     = "OU=AL_EXTERNOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co"
$DescripcionPorDefecto  = "Arus Itagui - Antioquia"

# -----------------------------------------------------------------------------
# Funcion de Auto-Reversion para dejar lista la cuenta henkia.pruebas
# -----------------------------------------------------------------------------
function Invoke-ReversionHenkiaPruebas {
    param (
        [string]$OUOriginal = $OUPorDefectoPrueba,
        [string]$DescripcionOriginal = $DescripcionPorDefecto
    )

    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "   INICIANDO AUTO-REVERSION DE CUENTA: $CuentaPruebaAutorizada" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan

    try {
        $UsuarioAD = Get-ADUser -Identity $CuentaPruebaAutorizada -Properties Enabled, Description, DistinguishedName -ErrorAction Stop

        # 1. Re-habilitar la cuenta
        try {
            Enable-ADAccount -Identity $CuentaPruebaAutorizada -ErrorAction Stop
            Write-Host "[REVERSION OK] Cuenta '$CuentaPruebaAutorizada' re-habilitada." -ForegroundColor Green
        }
        catch {
            throw "Fallo al re-habilitar la cuenta: $($_.Exception.Message)"
        }

        # 2. Restaurar la descripcion original (quitando el prefijo '(R) ' si existe)
        try {
            $DescripcionLimpia = $DescripcionOriginal
            if ([string]::IsNullOrWhiteSpace($DescripcionLimpia) -and $null -ne $UsuarioAD.Description) {
                $DescripcionLimpia = ($UsuarioAD.Description -replace '^\(R\)\s*', '')
            }
            Set-ADUser -Identity $CuentaPruebaAutorizada -Description $DescripcionLimpia -ErrorAction Stop
            Write-Host "[REVERSION OK] Descripcion restaurada a: '$DescripcionLimpia'." -ForegroundColor Green
        }
        catch {
            throw "Fallo al restaurar la descripcion: $($_.Exception.Message)"
        }

        # 3. Devolver el objeto a su OU original si fue movido
        try {
            $UsuarioActualizado = Get-ADUser -Identity $CuentaPruebaAutorizada -Properties DistinguishedName -ErrorAction Stop
            $OUActual = $UsuarioActualizado.DistinguishedName -replace '^CN=[^,]+,', ''

            if ($OUActual -ne $OUOriginal) {
                Move-ADObject -Identity $UsuarioActualizado.DistinguishedName -TargetPath $OUOriginal -ErrorAction Stop
                Write-Host "[REVERSION OK] Usuario devuelto a su OU original: '$OUOriginal'." -ForegroundColor Green
            }
            else {
                Write-Host "[REVERSION INFO] El usuario ya se encuentra en su OU original: '$OUOriginal'." -ForegroundColor Gray
            }
        }
        catch {
            throw "Fallo al mover el usuario a su OU original '$OUOriginal': $($_.Exception.Message)"
        }

        # Verificar y mostrar el estado final restaurado
        $EstadoFinal = Get-ADUser -Identity $CuentaPruebaAutorizada -Properties Enabled, Description, DistinguishedName -ErrorAction Stop
        Write-Host ""
        Write-Host "[EVIDENCIA DE ESTADO RESTAURADO EN AD]" -ForegroundColor Yellow
        Write-Host "  SamAccountName    : $($EstadoFinal.SamAccountName)"
        Write-Host "  Enabled           : $($EstadoFinal.Enabled)"
        Write-Host "  Description       : $($EstadoFinal.Description)"
        Write-Host "  DistinguishedName : $($EstadoFinal.DistinguishedName)"
    }
    catch {
        Write-Host "[ERROR EN AUTO-REVERSION] $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "   SISTEMA DE INHABILITACION MASIVA DE USUARIOS - POC ALIAR   " -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Verificacion de modulos requeridos (ActiveDirectory y Windows.Forms)
# -----------------------------------------------------------------------------
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "El modulo ActiveDirectory (RSAT) no esta instalado en este equipo."
    }
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "[INFO] Modulos ActiveDirectory y System.Windows.Forms cargados correctamente." -ForegroundColor Gray
}
catch {
    Write-Host "[ERROR] No se pudieron cargar los modulos requeridos: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Si se invoca unicamente para revertir el estado de prueba
if ($SoloRevertir) {
    Invoke-ReversionHenkiaPruebas
    exit 0
}

# -----------------------------------------------------------------------------
# Bucle principal para permitir procesar multiples lotes de usuarios
# -----------------------------------------------------------------------------
$ContinuarEjecucion = $true

while ($ContinuarEjecucion) {

    # -------------------------------------------------------------------------
    # Parte 2.1: Menu interactivo de seleccion de proceso
    # -------------------------------------------------------------------------
    $TipoProceso = $null

    do {
        Write-Host ""
        Write-Host "Seleccione el tipo de proceso a ejecutar:" -ForegroundColor Yellow
        Write-Host "  1. Vacaciones  (Solo inhabilita la cuenta)"
        Write-Host "  2. Paz y Salvo (Inhabilita, agrega '(R) ' a la descripcion y mueve a AL_INACTIVOS)"
        $Entrada = (Read-Host "Ingrese una opcion (1 o 2)").Trim()

        switch ($Entrada) {
            "1" { $TipoProceso = "Vacaciones" }
            "2" { $TipoProceso = "Paz y Salvo" }
            default {
                Write-Host "[ADVERTENCIA] Opcion invalida '$Entrada'. Debe ingresar '1' para Vacaciones o '2' para Paz y Salvo." -ForegroundColor Red
            }
        }
    } while ($null -eq $TipoProceso)

    Write-Host "[INFO] Proceso seleccionado: $TipoProceso" -ForegroundColor Green

    # -------------------------------------------------------------------------
    # Parte 2.2: Seleccion de archivo CSV con ventana nativa OpenFileDialog
    # -------------------------------------------------------------------------
    Write-Host "[INFO] Abriendo ventana para seleccionar el archivo .csv..." -ForegroundColor Yellow

    $DialogoArchivo = New-Object System.Windows.Forms.OpenFileDialog
    $DialogoArchivo.Title = "Seleccione el archivo CSV de usuarios para $TipoProceso"
    $DialogoArchivo.Filter = "Archivos CSV (*.csv)|*.csv"
    $DialogoArchivo.InitialDirectory = $PSScriptRoot
    $DialogoArchivo.Multiselect = $false

    # Formulario auxiliar con TopMost para asegurar que el cuadro de dialogo aparezca al frente
    $VentanaPadre = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
    $ResultadoDialogo = $DialogoArchivo.ShowDialog($VentanaPadre)
    $VentanaPadre.Dispose()

    if ($ResultadoDialogo -ne [System.Windows.Forms.DialogResult]::OK -or [string]::IsNullOrWhiteSpace($DialogoArchivo.FileName)) {
        Write-Host "[CANCELADO] No se selecciono ningun archivo CSV." -ForegroundColor Yellow
    }
    else {
        $RutaArchivo = $DialogoArchivo.FileName
        $DatosUsuarios = @()
        $ArchivoValido = $false

        # ---------------------------------------------------------------------
        # Parte 2.3: Lectura exclusiva de archivo .csv mediante Import-Csv
        # ---------------------------------------------------------------------
        try {
            if (-not (Test-Path -Path $RutaArchivo -PathType Leaf)) {
                throw "No se encontro el archivo CSV en la ruta: $RutaArchivo"
            }

            $Extension = [System.IO.Path]::GetExtension($RutaArchivo).ToLower()
            if ($Extension -ne ".csv") {
                throw "Formato de archivo no soportado ($Extension). Este sistema admite unicamente archivos .csv."
            }

            Write-Host "[INFO] Leyendo archivo CSV: $RutaArchivo" -ForegroundColor Gray

            $PrimeraLinea = Get-Content -Path $RutaArchivo -TotalCount 1 -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($PrimeraLinea)) {
                throw "El archivo CSV esta vacio."
            }

            $Delimitador = if ($PrimeraLinea -match ";") { ";" } else { "," }
            $DatosUsuarios = @(Import-Csv -Path $RutaArchivo -Delimiter $Delimitador -Encoding UTF8)

            if ($DatosUsuarios.Count -eq 0) {
                throw "El archivo CSV no contiene filas de datos para procesar."
            }

            $ColumnasArchivo = $DatosUsuarios[0].PSObject.Properties.Name | ForEach-Object { $_.ToUpper().Trim() }
            if (("NOMBRE" -notin $ColumnasArchivo) -or ("APELLIDO" -notin $ColumnasArchivo)) {
                throw "El archivo CSV debe contener las columnas 'NOMBRE' y 'APELLIDO'. Columnas detectadas: $($ColumnasArchivo -join ', ')"
            }

            Write-Host "[OK] Archivo CSV cargado exitosamente. Filas leidas: $($DatosUsuarios.Count)" -ForegroundColor Green
            $ArchivoValido = $true
        }
        catch {
            Write-Host "[ERROR] Fallo en la lectura del archivo CSV: $($_.Exception.Message)" -ForegroundColor Red
        }

        if ($ArchivoValido) {
            # -----------------------------------------------------------------
            # Parte 3: Logica de Busqueda y Filtrado en Active Directory
            # -----------------------------------------------------------------
            Write-Host ""
            Write-Host "[INFO] Buscando coincidencias de usuarios activos en Active Directory..." -ForegroundColor Cyan

            $UsuariosVista = @()
            $MetadatosUsuariosAD = @{}

            foreach ($Fila in $DatosUsuarios) {
                $Nombre   = if ($null -ne $Fila.NOMBRE)   { $Fila.NOMBRE.ToString().Trim() }   else { "" }
                $Apellido = if ($null -ne $Fila.APELLIDO) { $Fila.APELLIDO.ToString().Trim() } else { "" }

                if ([string]::IsNullOrWhiteSpace($Nombre) -and [string]::IsNullOrWhiteSpace($Apellido)) {
                    Write-Host "[ADVERTENCIA] Se omitio una fila con NOMBRE y APELLIDO vacios." -ForegroundColor Yellow
                    continue
                }

                try {
                    # Busqueda principal por GivenName y Surname (excluyendo cuentas ya inhabilitadas)
                    $FiltroPrincipal = "Enabled -eq '$true' -and GivenName -like '*$Nombre*' -and Surname -like '*$Apellido*'"
                    $CoincidenciasAD = @(Get-ADUser -Filter $FiltroPrincipal -Properties SamAccountName, Name, DisplayName, GivenName, Surname, Enabled, Description, DistinguishedName -ErrorAction Stop)

                    # Busqueda de respaldo en Name, DisplayName o SamAccountName si no hubo coincidencia directa
                    if ($CoincidenciasAD.Count -eq 0) {
                        $FiltroRespaldo = "Enabled -eq '$true' -and (Name -like '*$Nombre*$Apellido*' -or DisplayName -like '*$Nombre*$Apellido*' -or SamAccountName -like '*$Nombre*$Apellido*')"
                        $CoincidenciasAD = @(Get-ADUser -Filter $FiltroRespaldo -Properties SamAccountName, Name, DisplayName, GivenName, Surname, Enabled, Description, DistinguishedName -ErrorAction Stop)
                    }

                    if ($CoincidenciasAD.Count -eq 0) {
                        Write-Host "[SIN COINCIDENCIAS] No se encontraron cuentas activas para: '$Nombre $Apellido' (no existe o ya esta inhabilitada)." -ForegroundColor Yellow
                        continue
                    }

                    foreach ($UsuarioAD in $CoincidenciasAD) {
                        if (-not $UsuarioAD.Enabled) {
                            continue
                        }

                        # Evitar duplicados en la lista si el mismo usuario aparece dos veces
                        if ($MetadatosUsuariosAD.ContainsKey($UsuarioAD.SamAccountName)) {
                            continue
                        }

                        $OUOriginal   = $UsuarioAD.DistinguishedName -replace '^CN=[^,]+,', ''
                        $DescOriginal = if ($null -ne $UsuarioAD.Description) { [string]$UsuarioAD.Description } else { "" }
                        $NombreMostrar   = if (-not [string]::IsNullOrWhiteSpace($UsuarioAD.GivenName)) { $UsuarioAD.GivenName } else { $Nombre }
                        $ApellidoMostrar = if (-not [string]::IsNullOrWhiteSpace($UsuarioAD.Surname))   { $UsuarioAD.Surname }   else { $Apellido }

                        # Guardar metadatos tecnicos internamente para uso del script y reversion
                        $MetadatosUsuariosAD[$UsuarioAD.SamAccountName] = [PSCustomObject]@{
                            SamAccountName      = $UsuarioAD.SamAccountName
                            NombreCompleto      = $UsuarioAD.Name
                            DescriptionOriginal = $DescOriginal
                            OUOriginal          = $OUOriginal
                            DistinguishedName   = $UsuarioAD.DistinguishedName
                        }

                        # Objeto limpio exclusivamente con las 5 columnas solicitadas para Out-GridView
                        $ObjetoVista = [PSCustomObject]@{
                            "Nombre"      = $NombreMostrar
                            "Apellido"    = $ApellidoMostrar
                            "Usuario"     = $UsuarioAD.SamAccountName
                            "Estado"      = if ($UsuarioAD.Enabled) { "Activo" } else { "Inactivo" }
                            "Descripción" = $DescOriginal
                        }

                        $UsuariosVista += $ObjetoVista
                        Write-Host "[ENCONTRADO] Usuario activo: $($UsuarioAD.SamAccountName) ($($UsuarioAD.Name)) | OU: $OUOriginal" -ForegroundColor Green
                    }
                }
                catch {
                    Write-Host "[ERROR BUSQUEDA AD] Error al buscar '$Nombre $Apellido' en Active Directory: $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            # -----------------------------------------------------------------
            # Parte 4: Interfaz de Confirmacion (Staging con Out-GridView)
            # -----------------------------------------------------------------
            if ($UsuariosVista.Count -eq 0) {
                Write-Host ""
                Write-Host "[AVISO] No se encontraron usuarios activos para procesar con este archivo." -ForegroundColor Yellow
            }
            else {
                Write-Host ""
                Write-Host "[INFO] Desplegando ventana de confirmacion (Out-GridView)..." -ForegroundColor Yellow
                Write-Host "       -> Use Clic (o Ctrl + Clic) para marcar SOLO los usuarios que desea inhabilitar." -ForegroundColor Gray
                Write-Host "       -> Los usuarios que deje sin seleccionar NO seran inhabilitados." -ForegroundColor Gray

                $UsuariosConfirmados = @($UsuariosVista | Out-GridView -PassThru -Title "Confirme usuarios para inhabilitar")

                if ($UsuariosConfirmados.Count -eq 0) {
                    Write-Host "[CANCELADO] No se selecciono ningun usuario en la ventana de confirmacion. Operacion detenida sin cambios en AD." -ForegroundColor Yellow
                }
                else {
                    Write-Host "[INFO] Usuarios confirmados para procesar ($TipoProceso): $($UsuariosConfirmados.Count)" -ForegroundColor Green

                    # ---------------------------------------------------------
                    # Parte 5: Ejecucion de Reglas de Negocio (Bifurcacion)
                    # ---------------------------------------------------------
                    Write-Host ""
                    Write-Host "==============================================================" -ForegroundColor Cyan
                    Write-Host "   EJECUTANDO PROCESO: $TipoProceso" -ForegroundColor Cyan
                    Write-Host "==============================================================" -ForegroundColor Cyan

                    $RespaldoPrueba = $null

                    foreach ($ItemVista in $UsuariosConfirmados) {
                        $Cuenta = $ItemVista.Usuario
                        $InfoTecnica = $MetadatosUsuariosAD[$Cuenta]

                        # Regla estricta de seguridad de la PoC: Prohibido modificar cuentas reales
                        if ($Cuenta -ne $CuentaPruebaAutorizada) {
                            Write-Host "[BLOQUEO DE SEGURIDAD] Se omitio '$Cuenta'. Esta PoC solo permite modificar la cuenta '$CuentaPruebaAutorizada'." -ForegroundColor Red
                            continue
                        }

                        $RespaldoPrueba = $InfoTecnica
                        Write-Host ""
                        Write-Host "[PROCESANDO] Usuario: $Cuenta ($($InfoTecnica.NombreCompleto))" -ForegroundColor Cyan

                        if ($TipoProceso -eq "Vacaciones") {
                            # Regla Vacaciones: Solo se inhabilita la cuenta
                            try {
                                Disable-ADAccount -Identity $Cuenta -ErrorAction Stop
                                Write-Host "  [EXITO - VACACIONES] Cuenta '$Cuenta' inhabilitada correctamente (sin cambios en descripcion ni OU)." -ForegroundColor Green
                            }
                            catch {
                                Write-Host "  [ERROR - VACACIONES] Fallo al inhabilitar la cuenta '$Cuenta': $($_.Exception.Message)" -ForegroundColor Red
                            }
                        }
                        elseif ($TipoProceso -eq "Paz y Salvo") {
                            # Regla Paz y Salvo: 1) Inhabilitar, 2) Prefijo '(R) ' en descripcion, 3) Mover a OU AL_INACTIVOS
                            $PasoExitoso = $true

                            # Paso 1: Inhabilitar la cuenta
                            try {
                                Disable-ADAccount -Identity $Cuenta -ErrorAction Stop
                                Write-Host "  [PASO 1/3 OK] Cuenta '$Cuenta' inhabilitada correctamente." -ForegroundColor Green
                            }
                            catch {
                                $PasoExitoso = $false
                                Write-Host "  [ERROR PASO 1/3 - INHABILITAR] Fallo al inhabilitar la cuenta '$Cuenta': $($_.Exception.Message)" -ForegroundColor Red
                            }

                            # Paso 2: Agregar prefijo '(R) ' al inicio de la descripcion
                            if ($PasoExitoso) {
                                try {
                                    $DescBase = $InfoTecnica.DescriptionOriginal
                                    if ($DescBase -match '^\(R\)\s*') {
                                        $NuevaDescripcion = $DescBase
                                    }
                                    elseif ([string]::IsNullOrWhiteSpace($DescBase)) {
                                        $NuevaDescripcion = "(R)"
                                    }
                                    else {
                                        $NuevaDescripcion = "(R) $DescBase"
                                    }

                                    Set-ADUser -Identity $Cuenta -Description $NuevaDescripcion -ErrorAction Stop
                                    Write-Host "  [PASO 2/3 OK] Descripcion actualizada a: '$NuevaDescripcion'." -ForegroundColor Green
                                }
                                catch {
                                    $PasoExitoso = $false
                                    Write-Host "  [ERROR PASO 2/3 - DESCRIPCION] Fallo al actualizar la descripcion de '$Cuenta': $($_.Exception.Message)" -ForegroundColor Red
                                }
                            }

                            # Paso 3: Mover el objeto al OU de inactivos
                            if ($PasoExitoso) {
                                try {
                                    $ObjetoActualAD = Get-ADUser -Identity $Cuenta -Properties DistinguishedName -ErrorAction Stop
                                    Move-ADObject -Identity $ObjetoActualAD.DistinguishedName -TargetPath $OUInactivos -ErrorAction Stop
                                    Write-Host "  [PASO 3/3 OK] Usuario '$Cuenta' movido exitosamente a '$OUInactivos'." -ForegroundColor Green
                                }
                                catch {
                                    $PasoExitoso = $false
                                    Write-Host "  [ERROR PASO 3/3 - MOVER OU] Fallo al mover '$Cuenta' a '$OUInactivos': $($_.Exception.Message)" -ForegroundColor Red
                                }
                            }
                        }

                        # Mostrar el estado en AD tras la ejecucion de la regla de negocio
                        try {
                            $EstadoPostProceso = Get-ADUser -Identity $Cuenta -Properties Enabled, Description, DistinguishedName -ErrorAction Stop
                            Write-Host ""
                            Write-Host "  [ESTADO EN AD TRAS $TipoProceso]" -ForegroundColor Yellow
                            Write-Host "    SamAccountName    : $($EstadoPostProceso.SamAccountName)"
                            Write-Host "    Enabled           : $($EstadoPostProceso.Enabled)"
                            Write-Host "    Description       : $($EstadoPostProceso.Description)"
                            Write-Host "    DistinguishedName : $($EstadoPostProceso.DistinguishedName)"
                        }
                        catch {
                            Write-Host "  [ADVERTENCIA] No se pudo consultar el estado posterior de '$Cuenta': $($_.Exception.Message)" -ForegroundColor Yellow
                        }
                    }

                    # ---------------------------------------------------------
                    # Parte 6: Bloque de Auto-Reversion para henkia.pruebas
                    # ---------------------------------------------------------
                    if ($null -ne $RespaldoPrueba) {
                        Write-Host ""
                        if ($AutoRevertir) {
                            Invoke-ReversionHenkiaPruebas -OUOriginal $RespaldoPrueba.OUOriginal -DescripcionOriginal $RespaldoPrueba.DescriptionOriginal
                        }
                        else {
                            $RespuestaReversion = (Read-Host "Desea revertir los cambios realizados a '$CuentaPruebaAutorizada' para dejarlo en su estado original? (S/N)").Trim().ToUpper()
                            if ($RespuestaReversion -eq "S" -or $RespuestaReversion -eq "SI") {
                                Invoke-ReversionHenkiaPruebas -OUOriginal $RespaldoPrueba.OUOriginal -DescripcionOriginal $RespaldoPrueba.DescriptionOriginal
                            }
                            else {
                                Write-Host "[INFO] No se ejecutaron cambios de reversion. Puede revertir en cualquier momento ejecutando: .\Test-Inhabilitaciones.ps1 -SoloRevertir" -ForegroundColor Yellow
                            }
                        }
                    }
                }
            }
        }
    }

    # -------------------------------------------------------------------------
    # Preguntar si desea realizar otro proceso antes de cerrar el programa
    # -------------------------------------------------------------------------
    Write-Host ""
    $RespuestaContinuar = (Read-Host "Desea inhabilitar a mas usuarios (ejecutar otro proceso)? (S/N)").Trim().ToUpper()
    if ($RespuestaContinuar -ne "S" -and $RespuestaContinuar -ne "SI") {
        $ContinuarEjecucion = $false
        Write-Host ""
        Write-Host "[FIN] Ejecucion finalizada. Cerrando el programa." -ForegroundColor Cyan
    }
}
