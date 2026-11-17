# Gestión de Usuarios de Dominio (Mesa de Ayuda)

Aplicación web nativa en Windows PowerShell para la gestión de cuentas de Active Directory (desbloqueo individual, restablecimiento de contraseña e inhabilitación masiva por lotes `.csv` o `.xlsx` para procesos de Vacaciones y Paz y Salvo).

## Requisitos

- Equipo con Windows unido al dominio.
- Módulo `ActiveDirectory` (RSAT) instalado en el equipo.
- Sesión iniciada con una cuenta perteneciente al grupo autorizado (`Admins. del dominio` / `Domain Admins`).

## Ejecución

1. Hacer doble clic en `Iniciar-App.bat` (o ejecutar `powershell -ExecutionPolicy Bypass -File .\scripts\server.ps1`).
2. El navegador se abrirá automáticamente en `http://localhost:8080/`.

## Pruebas Automatizadas

- Pruebas unitarias, de controlador e interfaz:
  `powershell -ExecutionPolicy Bypass -File .\tests\backend.Tests.ps1`
- Pruebas integrales E2E (incluye servidor HTTP y Active Directory en vivo exclusivamente sobre la cuenta de pruebas `henkia.pruebas`):
  `powershell -ExecutionPolicy Bypass -File .\tests\backend.Tests.ps1 -IncludeLiveHttpTests`
