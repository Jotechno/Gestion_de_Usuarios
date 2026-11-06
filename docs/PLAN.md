# Plan de Ejecucion del Proyecto: Desbloqueo de Usuarios MVP

## Estructura de Directorios Propuesta

```text
DesbloqueoUsuarios/
├── AGENTS.md                  # Reglas de negocio, decisiones tecnicas y estandares
├── README.md                  # Guia rapida de ejecucion y requisitos
├── Iniciar-App.bat            # Acceso directo para iniciar el servidor y abrir el navegador
├── demoView.jpg               # Imagen de referencia visual (mockup) para el frontend
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

---

## Parte 1: Planificacion

Enriquecer este documento para planificar cada una de las fases en detalle, con subpasos en lista de verificacion, pruebas y criterios de exito.

### Lista de verificacion
- [x] 1.1. Revisar `AGENTS.md` y `PLAN.md` para alinear requisitos de negocio y restricciones tecnicas.
- [x] 1.2. Definir la estructura de carpetas del proyecto en `AGENTS.md` y `PLAN.md`.
- [x] 1.3. Desglosar las Partes 2 a 7 con tareas verificables, pruebas y criterios de exito.
- [x] 1.4. Resolver preguntas abiertas con el usuario (flujo en un paso, validacion por sesion de Windows, grupo `Admins. del dominio` / `Domain Admins` y frontend anonimo sin marca ni logo).

### Pruebas y Criterios de Exito
- **Prueba:** Revision del documento `PLAN.md` junto al usuario.
- **Criterio de exito:** Todas las dudas de negocio/tecnicas estan aclaradas y el usuario aprueba iniciar la Parte 2.

---

## Parte 2: Estructura e Infraestructura Base

Configurar el encarpetado del proyecto y escribir el esqueleto inicial del servidor en `scripts/server.ps1` capaz de servir un archivo `public/index.html` estatico de prueba ("Hola Mundo") en local.

### Lista de verificacion
- [x] 2.1. Crear los directorios `docs/`, `public/`, `scripts/` y `tests/`.
- [x] 2.2. Reubicar `PLAN.md` dentro de `docs/PLAN.md` segun lo especificado en `AGENTS.md`.
- [x] 2.3. Crear un archivo `public/index.html` inicial de prueba para validar la entrega de contenido estatico.
- [x] 2.4. Implementar el ciclo de vida basico de `System.Net.HttpListener` en `scripts/server.ps1` (inicio en `http://localhost:8080/`, manejo de cierre limpio con `try/finally` y cierre de `OutputStream` en cada peticion).
- [x] 2.5. Crear `Iniciar-App.bat` y `README.md` minimo con instrucciones de ejecucion.

### Pruebas y Criterios de Exito
- **Prueba:** Levantar `scripts/server.ps1` y realizar una peticion `GET http://localhost:8080/` con `Invoke-WebRequest`.
- **Criterio de exito:** El servidor responde con codigo HTTP 200, entrega el HTML correctamente codificado en UTF-8 y libera los recursos sin bloquear la consola al detenerse.

---

## Parte 3: Frontend (Interfaz Visual Anonima segun demoView.jpg y Cliente HTTP)

Construir la interfaz visual en `public/index.html` siguiendo fielmente el diseno de muestra de `demoView.jpg`, manteniendo la web anonima (sin nombre de compania ni logo), aplicando la paleta de colores con Tailwind CSS (via CDN) y el flujo de un solo paso en Vanilla JavaScript.

### Especificacion de Estilo Visual (basada en `demoView.jpg`)
- **Barra Superior (Navbar):** Franja horizontal de ancho completo en Azul Marino Oscuro (`#032147`) con el texto `"Mesa de Ayuda - Gestion de Usuarios"` alineado a la derecha en tono claro.
- **Fondo Principal:** Fondo gris claro con patron geometrico poligonal sutil (SVG low-poly de fondo) que centra vertical y horizontalmente la tarjeta principal.
- **Tarjeta Central (Card):**
  - Contenedor blanco centrado con bordes redondeados (`rounded-2xl`) y sombra suave (`shadow-xl`).
  - **Borde superior acentuado:** Linea decorativa superior en Amarillo/Naranja (`#FDC90A` / `#FFDF80`) con detalle segmentado en el extremo derecho, tal como se aprecia en `demoView.jpg`.
  - **Titulo principal:** `"Desbloqueo de Usuarios de Dominio"` centrado, en negrita y color Azul Marino Oscuro (`#032147`).
  - **Subtitulo:** `"Ingrese el usuario de red del colaborador para realizar el desbloqueo en el Active Directory."` centrado en Texto Gris (`#888888`).
  - **Campo de entrada (Input):** Bordes totalmente redondeados (`rounded-full`), contenedor izquierdo sutil con icono SVG de usuario en linea fina, y campo de texto con placeholder `"nombre.apellido"`.
  - **Boton de accion:** Bordes totalmente redondeados (`rounded-full`), ancho completo, fondo Verde Secundario (`#208342`), icono SVG de candado en linea fina junto al texto `"Desbloquear Usuario"`. Permanece deshabilitado hasta ingresar un usuario valido.
  - **Nota inferior dentro de la tarjeta:** Texto centrado `"Solo se procesaran cuentas habilitadas."`
- **Indicador de Estado Inferior (fuera de la tarjeta):** Punto circular en Verde Primario (`#97C03C`) junto al texto de estado de conexion al dominio (anonimo, ej. `"Conectado al Dominio"` junto al usuario de soporte en sesion).

### Lista de verificacion
- [x] 3.1. Estructurar `public/index.html` con Tailwind CSS via CDN replicando la maquetacion y proporciones de `demoView.jpg` con la paleta de colores definida (`#032147`, `#208342`, `#97C03C`, `#FDC90A`, `#FFDF80`, `#888888`).
- [x] 3.2. Incorporar la barra superior en `#032147`, el fondo geometrico sutil, la tarjeta con linea superior amarilla segmentada y el indicador inferior de estado de conexion.
- [x] 3.3. Crear el formulario de un solo paso con el campo redondeado `nombre.apellido` (con icono SVG de usuario) y el boton redondeado `Desbloquear Usuario` (con icono SVG de candado).
- [x] 3.4. Implementar validacion en Vanilla JS: mantener el boton "Desbloquear Usuario" deshabilitado hasta que se ingrese un formato valido de usuario.
- [x] 3.5. Construir el componente modal de notificacion (armonizado con el estilo de `demoView.jpg`) para mostrar "Desbloqueo exitoso" o el detalle del "Error" retornado por el servidor.

### Pruebas y Criterios de Exito
- **Prueba:** Inspeccion visual comparativa contra `demoView.jpg` y prueba funcional de `public/index.html` validando campo vacio, texto con formato valido e interaccion con el modal.
- **Criterio de exito:** La interfaz reproduce fielmente el diseno de `demoView.jpg`, es anonima, no contiene emojis, el boton solo se habilita al ingresar un usuario valido y muestra el modal correctamente.

---

## Parte 4: Control de Acceso por Contexto de Sesion de Windows

Validar la identidad del analista a partir del contexto de la sesion de Windows del proceso local y verificar que pertenezca al grupo autorizado (`Admins. del dominio` / `Domain Admins`, configurable en el script).

### Lista de verificacion
- [x] 4.1. Obtener la identidad del usuario de Windows que ejecuta el proceso local mediante `[System.Security.Principal.WindowsIdentity]::GetCurrent()`.
- [x] 4.2. Implementar en `scripts/ad-service.ps1` la funcion de verificacion de pertenencia al grupo autorizado (`Admins. del dominio` / `Domain Admins`).
- [x] 4.3. Bloquear la ejecucion de acciones (HTTP 403 Forbidden) si el usuario en sesion no pertenece al grupo autorizado, e informar en la interfaz que no cuenta con permisos.
- [x] 4.4. Exponer el endpoint `GET /api/session` para que el frontend consulte el usuario actual y su estado de autorizacion al cargar la pagina.

### Pruebas y Criterios de Exito
- **Prueba:** Consultar `GET /api/session` y probar la funcion de autorizacion tanto para miembros del grupo autorizado como para usuarios sin permisos.
- **Criterio de exito:** Usuarios autorizados visualizan la interfaz habilitada con su cuenta de dominio; usuarios no autorizados reciben HTTP 403 y el formulario permanece bloqueado con aviso de permisos insuficientes.

---

## Parte 5: Integracion con Active Directory (Comandos Nativos)

Estructurar las funciones nativas del modulo `ActiveDirectory` en `scripts/ad-service.ps1` para consultar y desbloquear cuentas en un solo flujo cumpliendo la regla de negocio.

### Lista de verificacion
- [x] 5.1. Validar disponibilidad e importacion del modulo `ActiveDirectory` (`Import-Module ActiveDirectory`).
- [x] 5.2. Implementar la consulta del usuario con `Get-ADUser -Identity <usuario> -Properties LockedOut, Enabled, DisplayName`.
- [x] 5.3. Implementar la regla de negocio estricta en `Invoke-UserUnlock`:
  - Si el usuario no existe en AD: retornar error indicando que la cuenta no fue encontrada.
  - Si `Enabled -eq $false` (Inhabilitado): NO ejecutar desbloqueo y retornar error indicando que la cuenta esta INHABILITADA.
  - Si `Enabled -eq $true` y `LockedOut -eq $false`: retornar aviso indicando que la cuenta esta habilitada pero no se encuentra bloqueada.
  - Si `Enabled -eq $true` y `LockedOut -eq $true`: ejecutar `Unlock-ADAccount -Identity <usuario>` y retornar confirmacion de "Desbloqueo exitoso".

### Pruebas y Criterios de Exito
- **Prueba:** Pruebas unitarias en `tests/backend.Tests.ps1` para los 4 escenarios (usuario inexistente, usuario inhabilitado, usuario habilitado no bloqueado, usuario habilitado y bloqueado).
- **Criterio de exito:** `Unlock-ADAccount` se ejecuta unica y exclusivamente cuando `Enabled` es verdadero y `LockedOut` es verdadero.

---

## Parte 6: Backend (Servidor HTTP y API en PowerShell)

Completar `scripts/server.ps1` integrando `scripts/ad-service.ps1` para escuchar las peticiones del frontend y responder en formato JSON estandarizado.

### Lista de verificacion
- [x] 6.1. Implementar enrutador HTTP en `scripts/server.ps1` para:
  - `GET /` (entrega de `public/index.html`).
  - `GET /api/session` (datos del analista en sesion y estado de autorizacion).
  - `POST /api/unlock` (recibe `{ "username": "nombre.apellido" }`, valida estado y ejecuta desbloqueo).
- [x] 6.2. Sanitizar y validar el formato del `username` en el backend antes de invocar cmdlets de AD.
- [x] 6.3. Estandarizar respuestas JSON (`{ success: bool, code: string, message: string, user: object }`) con codigos HTTP apropiados (200, 400, 403, 404, 422, 500).
- [x] 6.4. Escribir y ejecutar `tests/backend.Tests.ps1` para validar la logica del backend, el control de acceso y las reglas de negocio.

### Pruebas y Criterios de Exito
- **Prueba:** Ejecucion de `tests/backend.Tests.ps1` e invocacion de los endpoints con `Invoke-RestMethod`.
- **Criterio de exito:** Todas las pruebas pasan, las conexiones HTTP se cierran correctamente en bloques `finally` y las respuestas JSON son consistentes.

---

## Parte 7: Integracion Frontend + Backend y Pruebas Finales

Conectar el frontend con la API del backend para completar el flujo de extremo a extremo de desbloqueo de usuarios.

### Lista de verificacion
- [x] 7.1. Conectar la carga inicial de `public/index.html` con `GET /api/session` y el envio del formulario con `POST /api/unlock` mediante `fetch()`.
- [x] 7.2. Manejar estados de carga en el boton ("Procesando...") para evitar envios duplicados.
- [x] 7.3. Mostrar en el modal el resultado exacto devuelto por el backend ("Desbloqueo exitoso" o detalle del error) y limpiar el campo tras un desbloqueo exitoso.
- [x] 7.4. Realizar pruebas integrales de extremo a extremo (E2E) verificando el funcionamiento completo.

### Pruebas y Criterios de Exito
- **Prueba:** Flujo completo de principio a fin probando los escenarios de negocio y verificando el renderizado de la interfaz y respuestas del servidor.
- **Criterio de exito:** La aplicacion opera de principio a fin sin dependencias externas, cumpliendo todas las reglas de `AGENTS.md` y `PLAN.md`.
