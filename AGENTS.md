# Aplicación para desbloqueo de usuarios MVP (Versión Nativa Windows)

## Requisitos de Negocio

Este proyecto es una Aplicación de Gestión de Usuarios exclusiva para la Mesa de Ayuda (Soporte IT). Características principales:

* **Control de Acceso:** La aplicación debe ser accesible solo por personal autorizado. Al ser un entorno 100% nativo, el servidor se ejecutará bajo el contexto y las credenciales de red del analista de soporte logueado en la máquina del dominio, heredando sus permisos del Directorio Activo (ej. "Admins. del dominio").
* **Desbloqueo:** Un analista de soporte autorizado puede buscar una cuenta ingresando el usuario de dominio (formato: `nombre.apellido`).
* Al ingresar el usuario, se habilita el botón de "Desbloquear usuario".
* El sistema muestra un modal de notificación confirmando el "Desbloqueo exitoso" o un "Error" detallado.
* **Regla de Negocio:** El sistema primero debe validar el estado de la cuenta. Si un usuario está INHABILITADO (Disabled), NO se podrá desbloquear y mostrará un error. Solo se ejecuta la acción de desbloqueo en usuarios HABILITADOS (Enabled) que tengan el estado de bloqueo por intentos fallidos (Locked out).

## Limitaciones

* Para el MVP: No se implementará reseteo de contraseñas, solo desbloqueo.
* CERO INSTALACIONES EXTERNAS: No se puede instalar Node.js, Python, ni servidores web de terceros (Apache, Nginx). Tampoco se requiere instalar IDEs (se puede desarrollar con PowerShell ISE o Bloc de Notas).
* El entorno de ejecución será un equipo local de la Mesa de Ayuda ya unido al dominio de Aliar.

## Decisiones Técnicas

* **Frontend:** HTML, CSS y Vanilla JavaScript en un solo archivo o servido de forma simple. Usar Tailwind CSS (vía CDN) o Bootstrap (CDN) para una UI limpia y rápida.
* **Backend (El Servidor Web):** Script nativo de Windows PowerShell. Debe utilizar la clase de .NET `System.Net.HttpListener` para levantar un servidor web ligero (ej. en `http://localhost:8080`) que reciba las peticiones POST/GET del frontend.
* **Base de Datos:** NO se usará base de datos relacional externa. La única fuente de verdad será el Directorio Activo.
* **Integración AD:** El mismo script de PowerShell que actúa de servidor importará el módulo ActiveDirectory y ejecutará directamente los cmdlets nativos (`Unlock-ADAccount` y `Get-ADUser`).
* **Autenticación y Seguridad:** Si es necesario aislar más el acceso, configurar el `HttpListener` para usar Autenticación Integrada de Windows (`AuthenticationSchemes = 'IntegratedWindowsAuthentication'`). De lo contrario, apoyarse en que el script corre de forma local bajo las credenciales del usuario de soporte.

## Esquema de Color y Diseño Visual

Mantener la interfaz web anónima (sin nombre de la compañía ni logo corporativo), aplicando únicamente la siguiente paleta de colores:

* Amarillos/Naranjas: `#FFDF80` `#FDC90A` - líneas acentuadas, destacados.
* Verde Primario: `#97C03C` - enlaces, secciones clave.
* Verde Secundario: `#208342` - botones de envío, acciones importantes, títulos principales.
* Azul Marino Oscuro: `#032147` - títulos principales.
* Texto Gris: `#888888` - texto de apoyo, etiquetas.

## Estándares de Codificación

1. Escribir código PowerShell robusto, manejando los bloqueos del listener y cerrando conexiones HTTP correctamente para evitar fugas de memoria.
2. Mantenerlo simple - NUNCA sobre-ingenierizar, SIEMPRE simplificar. Sin características extra - enfócate en la simplicidad.
3. Ser conciso. Mantener README mínimo. IMPORTANTE: nunca uses emojis en el código, comentarios o interfaz.
4. Cuando encuentres problemas, siempre identifica la causa raíz antes de intentar una solución. No adivines. Prueba con evidencia, luego corrige la causa raíz.

## Documentación de Trabajo

Todos los documentos para planificación y ejecución de este proyecto estarán en un directorio `/docs`.
Por favor revisa el documento `docs/PLAN.md` antes de continuar.

## Estructura del Proyecto Propuesta

```text
DesbloqueoUsuarios/
├── AGENTS.md                  # Reglas de negocio, decisiones tecnicas y estandares
├── README.md                  # Guia rapida de ejecucion y requisitos
├── Iniciar-App.bat            # Acceso directo para iniciar el servidor y abrir el navegador
├── docs/
│   └── PLAN.md                # Plan de ejecucion detallado con criterios de exito
├── public/
│   └── index.html             # Interfaz de usuario anonima (HTML5, Tailwind CSS CDN y Vanilla JS)
├── scripts/
│   ├── server.ps1             # Servidor HTTP nativo con System.Net.HttpListener
│   └── ad-service.ps1         # Logica de Active Directory (validacion de grupo, consulta y desbloqueo)
└── tests/
    └── backend.Tests.ps1      # Pruebas automatizadas de funciones AD y endpoints HTTP
```