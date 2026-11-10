# Aplicación para desbloqueo y gestión de usuarios (Versión Nativa Windows)

## Requisitos de Negocio

Este proyecto es una Aplicación de Gestión de Usuarios exclusiva para la Mesa de Ayuda (Soporte IT). Características principales:

* **Control de Acceso:** La aplicación debe ser accesible solo por personal autorizado. Al ser un entorno 100% nativo, el servidor se ejecutará bajo el contexto y las credenciales de red del analista de soporte logueado en la máquina del dominio, heredando sus permisos del Directorio Activo (ej. "Admins. del dominio").
* **Búsqueda y Acciones 50/50:** Un analista de soporte autorizado puede ingresar el usuario de dominio (formato: `nombre.apellido`). Al ingresar un formato válido, se habilitan dos botones en proporción 50/50:
  * Izquierda: `"Desbloquear Usuario"` (color verde secundario `#208342`).
  * Derecha: `"Cambiar Contraseña"` (color verde oscuro diferenciador `#14532A`).
* **Desbloqueo:** Muestra un modal de notificación confirmando el "Desbloqueo exitoso" o un "Error" detallado.
* **Cambio de Contraseña (Restablecimiento):**
  * Al hacer clic en `"Cambiar Contraseña"`, el sistema valida primero en Active Directory que el usuario exista y esté **HABILITADO**. Si no existe o está inhabilitado, muestra el modal de error inmediatamente.
  * Si la cuenta es válida y está habilitada, despliega un modal integrado con el diseño visual pero con los mismos elementos que la ventana nativa de Active Directory (`Restablecer contraseña`):
    * Campo `"Contraseña nueva"` y `"Confirmar contraseña"`.
    * Checkbox `"El usuario debe cambiar la contraseña en el siguiente inicio de sesión"` (marcado por defecto) junto con la nota `"El usuario ha de cerrar la sesión y volver a abrirla para que los cambios tengan efecto."`
    * Indicador `"Estado de bloqueo de cuenta en este controlador de dominio: Desbloqueado / Bloqueado"`.
    * Checkbox `"Desbloquear la cuenta del usuario"` (desmarcado por defecto).
    * Botón `"Aceptar"` (habilitado solo cuando ambos campos de contraseña tienen contenido y coinciden) y botón `"Cancelar"`.
* **Regla de Negocio Estricta:** El sistema primero debe validar el estado de la cuenta. Si un usuario está INHABILITADO (Disabled), NO se podrá desbloquear ni cambiar su contraseña y mostrará un error.

## Limitaciones y Restricción Estricta de Pruebas

* CERO INSTALACIONES EXTERNAS: No se puede instalar Node.js, Python, ni servidores web de terceros (Apache, Nginx). Tampoco se requiere instalar IDEs (se puede desarrollar con PowerShell ISE o Bloc de Notas).
* El entorno de ejecución será un equipo local de la Mesa de Ayuda ya unido al dominio de Aliar.
* **RESTRICCIÓN CRÍTICA DE PRUEBAS:** Está estrictamente prohibido utilizar usuarios aleatorios o el usuario personal del analista para pruebas de bloqueo o cambio de contraseña. Para TODAS las pruebas en vivo de esta fase se utilizará **ÚNICA Y EXCLUSIVAMENTE** la cuenta de pruebas: `henkia.pruebas`.

## Decisiones Técnicas

* **Frontend:** HTML, CSS y Vanilla JavaScript en un solo archivo o servido de forma simple. Usar Tailwind CSS (vía CDN) o Bootstrap (CDN) para una UI limpia y rápida.
* **Backend (El Servidor Web):** Script nativo de Windows PowerShell. Debe utilizar la clase de .NET `System.Net.HttpListener` para levantar un servidor web ligero (ej. en `http://localhost:8080`) que reciba las peticiones POST/GET del frontend.
* **Base de Datos:** NO se usará base de datos relacional externa. La única fuente de verdad será el Directorio Activo.
* **Integración AD:** El mismo script de PowerShell que actúa de servidor importará el módulo ActiveDirectory y ejecutará directamente los cmdlets nativos (`Get-ADUser`, `Unlock-ADAccount`, `Set-ADAccountPassword` y `Set-ADUser`).
* **Autenticación y Seguridad:** El servidor valida la sesión local de Windows del analista contra el grupo autorizado en Active Directory (`Admins. del dominio` / `Domain Admins`).

## Esquema de Color y Diseño Visual

Mantener la interfaz web anónima (sin nombre de la compañía ni logo corporativo), aplicando únicamente la siguiente paleta de colores:

* Amarillos/Naranjas: `#FFDF80` `#FDC90A` - líneas acentuadas, destacados.
* Verde Primario: `#97C03C` - enlaces, secciones clave.
* Verde Secundario: `#208342` - botón de desbloqueo, acciones importantes.
* Verde Oscuro Diferenciador: `#14532A` - botón de cambio de contraseña.
* Azul Marino Oscuro: `#032147` - títulos principales y barra superior.
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
│   └── ad-service.ps1         # Logica de Active Directory (validacion de grupo, consulta, desbloqueo y cambio de clave)
└── tests/
    └── backend.Tests.ps1      # Pruebas automatizadas de funciones AD y endpoints HTTP
```
