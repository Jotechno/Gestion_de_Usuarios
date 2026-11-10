param(
    [int]$Port = 8080,
    [int]$MaxRequests = 0,
    [string[]]$AllowedGroups = @('Admins. del dominio', 'Domain Admins')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $scriptDir
$publicDir = Join-Path $projectRoot 'public'
$adServicePath = Join-Path $scriptDir 'ad-service.ps1'

if (Test-Path $adServicePath) {
    . $adServicePath
} else {
    throw "No se encontro el archivo de servicio AD en: $adServicePath"
}

function Send-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory = $true)]
        [int]$StatusCode,
        [Parameter(Mandatory = $true)]
        [object]$BodyObject
    )

    $json = $BodyObject | ConvertTo-Json -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = 'application/json; charset=utf-8'
    $Response.Headers['Cache-Control'] = 'no-store, no-cache, must-revalidate'
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Read-RequestBody {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerRequest]$Request
    )

    if (-not $Request.HasEntityBody -or $null -eq $Request.InputStream) {
        return ''
    }

    $reader = New-Object System.IO.StreamReader($Request.InputStream, [System.Text.Encoding]::UTF8)
    try {
        return $reader.ReadToEnd()
    } finally {
        try { $reader.Close() } catch {}
    }
}

$prefix = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $sessionInfo = Get-AnalystSession -AllowedGroups $AllowedGroups
    $listener.Start()

    Write-Host "Servidor HTTP iniciado en $prefix"
    Write-Host "Analista en sesion: $($sessionInfo.domainUser) | Autorizado: $($sessionInfo.authorized)"
    Write-Host "Presione Ctrl+C para detener el servidor."

    $requestCount = 0

    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        try {
            $path = $request.Url.AbsolutePath
            $method = $request.HttpMethod

            if ($method -eq 'GET' -and ($path -eq '/' -or $path -eq '/index.html')) {
                $indexPath = Join-Path $publicDir 'index.html'
                if (Test-Path $indexPath) {
                    $contentBytes = [System.IO.File]::ReadAllBytes($indexPath)
                    $response.StatusCode = 200
                    $response.ContentType = 'text/html; charset=utf-8'
                    $response.Headers['Cache-Control'] = 'no-store, no-cache, must-revalidate'
                    $response.ContentLength64 = $contentBytes.Length
                    $response.OutputStream.Write($contentBytes, 0, $contentBytes.Length)
                } else {
                    $notFoundBytes = [System.Text.Encoding]::UTF8.GetBytes('Archivo index.html no encontrado.')
                    $response.StatusCode = 404
                    $response.ContentType = 'text/plain; charset=utf-8'
                    $response.ContentLength64 = $notFoundBytes.Length
                    $response.OutputStream.Write($notFoundBytes, 0, $notFoundBytes.Length)
                }
            } elseif ($method -eq 'GET' -and $path -eq '/favicon.ico') {
                $response.StatusCode = 204
                $response.ContentLength64 = 0
            } elseif ($method -eq 'GET' -and $path -eq '/api/session') {
                $statusCode = if ($sessionInfo.authorized) { 200 } else { 403 }
                Send-JsonResponse -Response $response -StatusCode $statusCode -BodyObject $sessionInfo
            } elseif ($method -eq 'POST' -and $path -eq '/api/unlock') {
                $rawBody = Read-RequestBody -Request $request
                $apiResult = Invoke-UnlockApiController -SessionInfo $sessionInfo -RawBody $rawBody
                $timestamp = (Get-Date).ToString('HH:mm:ss')
                Write-Host "[$timestamp] POST /api/unlock | Codigo: $($apiResult.body.code) | HTTP $($apiResult.httpStatus)"
                Send-JsonResponse -Response $response -StatusCode $apiResult.httpStatus -BodyObject $apiResult.body
            } elseif ($method -eq 'POST' -and $path -eq '/api/user-status') {
                $rawBody = Read-RequestBody -Request $request
                $apiResult = Invoke-UserStatusApiController -SessionInfo $sessionInfo -RawBody $rawBody
                $timestamp = (Get-Date).ToString('HH:mm:ss')
                Write-Host "[$timestamp] POST /api/user-status | Codigo: $($apiResult.body.code) | HTTP $($apiResult.httpStatus)"
                Send-JsonResponse -Response $response -StatusCode $apiResult.httpStatus -BodyObject $apiResult.body
            } elseif ($method -eq 'POST' -and $path -eq '/api/reset-password') {
                $rawBody = Read-RequestBody -Request $request
                $apiResult = Invoke-PasswordResetApiController -SessionInfo $sessionInfo -RawBody $rawBody
                $timestamp = (Get-Date).ToString('HH:mm:ss')
                Write-Host "[$timestamp] POST /api/reset-password | Codigo: $($apiResult.body.code) | HTTP $($apiResult.httpStatus)"
                Send-JsonResponse -Response $response -StatusCode $apiResult.httpStatus -BodyObject $apiResult.body
            } elseif ($path -like '/api/*') {
                if (-not $sessionInfo.authorized) {
                    Send-JsonResponse -Response $response -StatusCode 403 -BodyObject @{
                        success = $false
                        code    = 'FORBIDDEN'
                        title   = 'Acceso denegado'
                        message = $sessionInfo.message
                        user    = $null
                    }
                } else {
                    Send-JsonResponse -Response $response -StatusCode 404 -BodyObject @{
                        success = $false
                        code    = 'NOT_FOUND'
                        title   = 'Ruta no encontrada'
                        message = 'El endpoint solicitado no existe.'
                        user    = $null
                    }
                }
            } else {
                $notFoundBytes = [System.Text.Encoding]::UTF8.GetBytes('Ruta no encontrada.')
                $response.StatusCode = 404
                $response.ContentType = 'text/plain; charset=utf-8'
                $response.ContentLength64 = $notFoundBytes.Length
                $response.OutputStream.Write($notFoundBytes, 0, $notFoundBytes.Length)
            }
        } catch {
            try {
                Send-JsonResponse -Response $response -StatusCode 500 -BodyObject @{
                    success = $false
                    code    = 'INTERNAL_ERROR'
                    title   = 'Error interno del servidor'
                    message = $_.Exception.Message
                    user    = $null
                }
            } catch {}
        } finally {
            if ($null -ne $response) {
                try { $response.OutputStream.Close() } catch {}
                try { $response.Close() } catch {}
            }
        }

        $requestCount++
        if ($MaxRequests -gt 0 -and $requestCount -ge $MaxRequests) {
            break
        }
    }
} finally {
    if ($null -ne $listener) {
        if ($listener.IsListening) {
            try { $listener.Stop() } catch {}
        }
        try { $listener.Close() } catch {}
    }
    Write-Host "Servidor HTTP detenido correctamente."
}
