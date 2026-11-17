# Aplicación para gestión de usuarios de dominio (Versión Nativa Windows)

## Requisitos de Negocio

Este proyecto es una Aplicación de Gestión de Usuarios exclusiva para la Mesa de Ayuda (Soporte IT). Características principales:

* **Control de Acceso:** La aplicación debe ser accesible solo por personal autorizado. Al ser un entorno 100% nativo, el servidor se ejecutará bajo el contexto y las credenciales de red del analista de soporte logueado en la máquina del dominio, heredando sus permisos del Directorio Activo (ej. "Admins. del dominio").
* **Navegación por Módulos:** La interfaz permite alternar armónicamente mediante un selector superior (Segmented Control) entre dos módulos principales:
  1. **Desbloqueo / Contraseña (Gestión Individual)**
  2. **Inhabilitación Masiva (Procesamiento por Lotes CSV / XLSX)**
* **Módulo 1 - Búsqueda y Acciones 50/50 (Desbloqueo y Cambio de Contraseña):**
  * Un analista autorizado ingresa cualquier usuario de dominio válido sin espacios (`nombre.apellido` o un solo nombre como `usuario`), habilitando dos botones en proporción 50/50:
    * Izquierda: `"Desbloquear Usuario"` (color verde secundario `#208342`).
    * Derecha: `"Cambiar Contraseña"` (color verde oscuro diferenciador `#14532A`).
  * **Desbloqueo:** Muestra un modal de notificación confirmando el "Desbloqueo exitoso" o un "Error" detallado.
  * **Cambio de Contraseña (Restablecimiento):**
    * Valida primero en Active Directory que el usuario exista y esté **HABILITADO**. Si no existe o está inhabilitado, muestra el modal de error inmediatamente.
    * Si la cuenta es válida y está habilitada, despliega el modal `"Restablecer contraseña"` con los elementos nativos de Active Directory (`Contraseña nueva`, `Confirmar contraseña`, checkbox `"El usuario debe cambiar la contraseña en el siguiente inicio de sesión"` marcado por defecto, indicador de `"Estado de bloqueo de cuenta en este controlador de dominio: Desbloqueado / Bloqueado"` y checkbox `"Desbloquear la cuenta del usuario"` desmarcado por defecto).
  * **Regla de Negocio Estricta (Módulo 1):** Si un usuario está INHABILITADO (Disabled), NO se podrá desbloquear ni cambiar su contraseña y mostrará un error.
* **Módulo 2 - Inhabilitación Masiva por CSV / XLSX (Vacaciones y Paz y Salvo):**
  * **Formulario de Carga:** Cuenta con un `<select>` para elegir el tipo de proceso (`Vacaciones` o `Paz y Salvo`), un `<input type="file" accept=".csv,.xlsx">` y un botón `"Analizar Archivo"`.
  * **Previsualización y Normalización (`POST /api/masivo/preview`):**
    * Admite archivos tanto en formato `.csv` (UTF-8 o Windows-1252 ANSI) como libros de Excel `.xlsx` (leídos de forma 100% nativa en PowerShell mediante `System.IO.Compression.ZipArchive` y XML sin instalar librerías ni requerir Excel).
    * Analiza la primera hoja/tabla que contenga la fila de encabezados con ambas columnas `NOMBRE` y `APELLIDO` (sin importar si empieza en la fila 1, 3, 4 o 5), aplicando `.Trim().ToUpperInvariant()` para tolerar espacios o minúsculas.
    * Al escanear los encabezados de izquierda a derecha, **se detiene tan pronto ubica las columnas `NOMBRE` y `APELLIDO`**, extrayendo únicamente esas dos columnas e ignorando cualquier columna duplicada posterior (como `VIATICOS` o `DIAS DE SUSPENSION`). Se detiene al finalizar el bloque de registros de esa tabla.
    * Normaliza `Ñ -> N` y elimina tildes/diéresis antes de buscar en Active Directory coincidencias activas (`Enabled -eq $true`).
  * **Modal de Verificación (Reemplazo Web de `Out-GridView`):**
    * Presenta la lista de usuarios activos encontrados con las columnas: **Selección (Checkbox)**, **Nombre**, **Apellido**, **Usuario**, **Estado** y **Descripción** (con los checkboxes desmarcados por defecto y opción de `"Seleccionar todos"`), además de informar las filas del CSV que no tuvieron coincidencia activa en AD.
    * Al presionar `"Ejecutar"`, únicamente los usuarios marcados con check se envían al endpoint `POST /api/masivo/execute`.
  * **Reglas de Negocio de Ejecución (`POST /api/masivo/execute`):**
    * **Vacaciones:** Solo se inhabilita la cuenta (`Disable-ADAccount`). No se modifica la descripción ni se cambia de Unidad Organizativa (OU).
    * **Paz y Salvo:**
      1. Se inhabilita la cuenta (`Disable-ADAccount`).
      2. Se actualiza la descripción anteponiendo `"(R) "` al inicio (`Set-ADUser -Description`), evitando duplicar el prefijo si ya lo tiene.
      3. Se mueve el objeto en Active Directory (`Move-ADObject`) a la OU de inactivos: `OU=AL_INACTIVOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co`.

## Limitaciones y Restricción Estricta de Pruebas

* CERO INSTALACIONES EXTERNAS: No se puede instalar Node.js, Python, ni servidores web de terceros (Apache, Nginx). Tampoco se requiere instalar IDEs (se puede desarrollar con PowerShell ISE o Bloc de Notas).
* El entorno de ejecución será un equipo local de la Mesa de Ayuda ya unido al dominio de Aliar.
* **RESTRICCIÓN CRÍTICA DE PRUEBAS:** Está estrictamente prohibido utilizar usuarios aleatorios o el usuario personal del analista para pruebas en vivo. Para TODAS las pruebas automatizadas en vivo (`tests/backend.Tests.ps1`) se utilizará **ÚNICA Y EXCLUSIVAMENTE** la cuenta de pruebas: `henkia.pruebas` (revirtiendo su estado al finalizar el test). En el código de producción (`scripts/ad-service.ps1`) el motor de Active Directory queda limpio sin bloqueos de usuario de prueba ni auto-reversión.

## Decisiones Técnicas

* **Frontend:** HTML, CSS y Vanilla JavaScript en un solo archivo (`public/index.html`). Usar Tailwind CSS (vía CDN) para una UI limpia y rápida, 100% web (sin `OpenFileDialog` ni `Out-GridView`).
* **Backend (El Servidor Web):** Script nativo de Windows PowerShell (`scripts/server.ps1`). Utiliza `System.Net.HttpListener` para levantar un servidor web ligero en `http://localhost:8080`.
* **Base de Datos:** NO se usará base de datos relacional externa. La única fuente de verdad será el Directorio Activo.
* **Integración AD:** El servicio `scripts/ad-service.ps1` importa el módulo `ActiveDirectory` y ejecuta directamente los cmdlets nativos (`Get-ADUser`, `Unlock-ADAccount`, `Set-ADAccountPassword`, `Set-ADUser`, `Disable-ADAccount` y `Move-ADObject`).
* **Autenticación y Seguridad:** El servidor valida la sesión local de Windows del analista contra el grupo autorizado en Active Directory (`Admins. del dominio` / `Domain Admins`).

## Esquema de Color y Diseño Visual

Mantener la interfaz web anónima (sin nombre de la compañía ni logo corporativo), aplicando únicamente la siguiente paleta de colores:

* Amarillos/Naranjas: `#FFDF80` `#FDC90A` - líneas acentuadas, destacados.
* Verde Primario: `#97C03C` - enlaces, secciones clave.
* Verde Secundario: `#208342` - botón de desbloqueo, acciones importantes.
* Verde Oscuro Diferenciador: `#14532A` - botón de cambio de contraseña y acciones secundarias.
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
│   └── ad-service.ps1         # Logica de Active Directory (desbloqueo, cambio de clave e inhabilitacion masiva)
└── tests/
    └── backend.Tests.ps1      # Pruebas automatizadas de funciones AD y endpoints HTTP
```
