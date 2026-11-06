# Desbloqueo de Usuarios de Dominio (MVP)

Aplicacion web local para desbloqueo de cuentas de Active Directory exclusiva para Mesa de Ayuda.

## Requisitos

- Equipo con Windows unido al dominio.
- Modulo `ActiveDirectory` (RSAT) instalado en el equipo.
- Sesion iniciada con una cuenta perteneciente al grupo autorizado (`Admins. del dominio` / `Domain Admins`).

## Ejecucion

1. Hacer doble clic en `Iniciar-App.bat` (o ejecutar `powershell -ExecutionPolicy Bypass -File .\scripts\server.ps1`).
2. El navegador se abrira automaticamente en `http://localhost:8080/`.

## Pruebas Automatizadas

- Pruebas unitarias y de controlador:
  `powershell -ExecutionPolicy Bypass -File .\tests\backend.Tests.ps1`
- Pruebas integrales E2E (incluye servidor HTTP y Active Directory en vivo):
  `powershell -ExecutionPolicy Bypass -File .\tests\backend.Tests.ps1 -IncludeLiveHttpTests`
