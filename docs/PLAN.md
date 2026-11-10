# Plan de Ejecucion del Proyecto: Desbloqueo y Gestion de Usuarios

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
│   └── ad-service.ps1         # Logica de Active Directory (validacion de grupo, consulta, desbloqueo y cambio de clave)
└── tests/
    └── backend.Tests.ps1      # Pruebas automatizadas de funciones AD y endpoints HTTP
```

---

## Parte 1: Planificacion (Fase 1 - MVP Desbloqueo)

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

## Parte 7: Integracion Frontend + Backend y Pruebas Finales (Fase 1)

Conectar el frontend con la API del backend para completar el flujo de extremo a extremo de desbloqueo de usuarios.

### Lista de verificacion
- [x] 7.1. Conectar la carga inicial de `public/index.html` con `GET /api/session` y el envio del formulario con `POST /api/unlock` mediante `fetch()`.
- [x] 7.2. Manejar estados de carga en el boton ("Procesando...") para evitar envios duplicados.
- [x] 7.3. Mostrar en el modal el resultado exacto devuelto por el backend ("Desbloqueo exitoso" o detalle del error) y limpiar el campo tras un desbloqueo exitoso.
- [x] 7.4. Realizar pruebas integrales de extremo a extremo (E2E) verificando el funcionamiento completo.

### Pruebas y Criterios de Exito
- **Prueba:** Flujo completo de principio a fin probando los escenarios de negocio y verificando el renderizado de la interfaz y respuestas del servidor.
- **Criterio de exito:** La aplicacion opera de principio a fin sin dependencias externas, cumpliendo todas las reglas de `AGENTS.md` y `PLAN.md`.

---
---

# Fase 2: Escalabilidad - Modulo de Cambio de Contrasena en Active Directory

> **Restriccion Estricta de Pruebas (CRITICO):** Esta estrictamente prohibido utilizar usuarios aleatorios o el usuario personal del analista en las pruebas en vivo. Para TODAS las pruebas de esta fase se utilizara **UNICA Y EXCLUSIVAMENTE** la cuenta de pruebas: `henkia.pruebas`.

---

## Parte 8: Planificacion de la Fase 2 (Cambio de Contrasena)

Definir la arquitectura funcional, reglas de validacion y plan de trabajo para incorporar el restablecimiento de contrasenas desde la interfaz web.

### Lista de verificacion
- [x] 8.1. Analizar requerimientos de interfaz (botones 50/50, modal inspirado en la ventana nativa de AD) y comandos de Active Directory (`Set-ADAccountPassword`, `Set-ADUser -ChangePasswordAtLogon`, `Unlock-ADAccount`).
- [x] 8.2. Resolver preguntas abiertas con el usuario (validacion previa en AD al pulsar "Cambiar Contrasena", validacion de coincidencia de campos en el modal, boton "Aceptar" deshabilitado hasta coincidencia y estado inicial de los checkboxes).
- [x] 8.3. Actualizar `AGENTS.md` y `docs/PLAN.md` con las especificaciones y fases detalladas (Partes 8 a 11).
- [x] 8.4. Obtener aprobacion del usuario para iniciar la Parte 9.

### Pruebas y Criterios de Exito
- **Prueba:** Revision del plan actualizado en `docs/PLAN.md` y `AGENTS.md` por parte del usuario.
- **Criterio de exito:** El usuario aprueba formalmente el plan de la Fase 2 para comenzar con la Parte 9.

---

## Parte 9: Logica de Active Directory y Endpoints Backend para Cambio de Contrasena

Implementar en `scripts/ad-service.ps1` y `scripts/server.ps1` la consulta previa de estado del usuario y la ejecucion del cambio de contrasena junto con sus opciones en Active Directory.

### Lista de verificacion
- [x] 9.1. Implementar en `scripts/ad-service.ps1` la funcion `Invoke-UserStatusCheck` para validar que el usuario ingresado exista y este **HABILITADO** (`Enabled = $true`), retornando su `DisplayName` y estado actual de bloqueo (`LockedOut`) para mostrarlo en el modal de contrasena. Si no existe (`HTTP 404`) o esta **INHABILITADO** (`HTTP 422`), rechazar la apertura del modal.
- [x] 9.2. Implementar en `scripts/ad-service.ps1` la funcion `Invoke-UserPasswordReset` con las siguientes reglas:
  - Validar formato de `username`, que `newPassword` y `confirmPassword` no esten vacios y que sean identicos (`HTTP 400` en caso contrario).
  - Consultar el usuario en AD y verificar que exista (`HTTP 404`) y este **HABILITADO** (`Enabled = $true`; si es `$false`, retornar `HTTP 422 ACCOUNT_DISABLED` sin modificar nada).
  - Convertir la contrasena a `SecureString` (`ConvertTo-SecureString -AsPlainText -Force`) y ejecutar `Set-ADAccountPassword -Identity <usuario> -Reset -NewPassword <SecureString> -ErrorAction Stop`.
  - Ejecutar `Set-ADUser -Identity <usuario> -ChangePasswordAtLogon <bool> -ErrorAction Stop` segun el valor del primer checkbox.
  - Si el segundo checkbox (`unlockAccount`) fue marcado como `$true`, ejecutar `Unlock-ADAccount -Identity <usuario> -ErrorAction Stop`.
- [x] 9.3. Implementar los controladores HTTP `Invoke-UserStatusApiController` y `Invoke-PasswordResetApiController` en `scripts/ad-service.ps1`, y registrar en `scripts/server.ps1` las rutas:
  - `POST /api/user-status`
  - `POST /api/reset-password`
- [x] 9.4. Ampliar las pruebas unitarias en `tests/backend.Tests.ps1` (con mocks inyectados) para validar todos los escenarios de `Invoke-UserStatusCheck` e `Invoke-UserPasswordReset` (contrasenas distintas, cuenta inexistente, cuenta inhabilitada, cambio exitoso con `ChangePasswordAtLogon` y desbloqueo simultaneo).

### Pruebas y Criterios de Exito
- **Prueba:** Ejecucion de las pruebas unitarias en `tests/backend.Tests.ps1`.
- **Criterio de exito:** Todas las pruebas unitarias pasan, garantizando que nunca se cambie la contrasena de una cuenta inhabilitada y que los parametros `ChangePasswordAtLogon` y `Unlock-ADAccount` se apliquen segun lo indicado.

---

## Parte 10: Frontend (Botones 50/50 y Modal "Restablecer contrasena")

Actualizar `public/index.html` para incorporar la disposicion de botones 50/50 y el nuevo modal de cambio de contrasena basado en el dialogo nativo de Active Directory.

### Lista de verificacion
- [x] 10.1. Ajustar el contenedor de acciones del formulario principal en `public/index.html` para dividir el espacio en dos columnas iguales (50/50):
  - Izquierda: Boton `"Desbloquear Usuario"` en Verde Secundario (`#208342`).
  - Derecha: Boton `"Cambiar Contrasena"` en Verde Oscuro diferenciador (`#14532A`, hover `#0F3F20`) con icono SVG de llave/candado en linea fina.
  - Ambos botones permanecen deshabilitados hasta ingresar un usuario con formato `nombre.apellido` valido.
- [x] 10.2. Construir en `public/index.html` el modal `"Restablecer contrasena"` armonizado con la paleta del proyecto e incluyendo todos los elementos de la ventana nativa de AD:
  - Encabezado con titulo `"Restablecer contrasena"`, badge del usuario seleccionado y boton de cierre (`X`).
  - Campo `"Contrasena nueva:"` (`type="password"`).
  - Campo `"Confirmar contrasena:"` (`type="password"`).
  - Checkbox 1 (**marcado por defecto**): `"El usuario debe cambiar la contrasena en el siguiente inicio de sesion"` + texto secundario indentado: `"El usuario ha de cerrar la sesion y volver a abrirla para que los cambios tengan efecto."`
  - Etiqueta de estado: `"Estado de bloqueo de cuenta en este controlador de dominio: Desbloqueado / Bloqueado"`.
  - Checkbox 2 (**desmarcado por defecto**): `"Desbloquear la cuenta del usuario"`.
  - Botones inferiores alineados a la derecha: `"Aceptar"` y `"Cancelar"`.
- [x] 10.3. Implementar validacion en Vanilla JS para los campos del modal de contrasena:
  - Mantener el boton `"Aceptar"` deshabilitado mientras alguno de los dos campos este vacio o las contrasenas no coincidan.
  - Mostrar un aviso en linea dentro del modal cuando ambos campos tengan texto pero no coincidan.

### Pruebas y Criterios de Exito
- **Prueba:** Verificacion estructural y funcional de `public/index.html` (botones 50/50, apertura/cierre del modal, estado por defecto de los checkboxes y bloqueo del boton `"Aceptar"` ante campos vacios o distintos).
- **Criterio de exito:** La interfaz respeta el diseno 50/50, el modal replica los controles nativos de AD con el estilo visual del proyecto, no contiene emojis y valida correctamente la coincidencia de contrasenas.

---

## Parte 11: Integracion Frontend + Backend y Pruebas E2E con `henkia.pruebas`

Conectar el flujo completo del frontend con los nuevos endpoints del backend y ejecutar las pruebas integrales en vivo utilizando exclusivamente la cuenta `henkia.pruebas`.

### Lista de verificacion
- [x] 11.1. Conectar el clic en `"Cambiar Contrasena"` con `POST /api/user-status`:
  - Mostrar estado de carga mientras se valida el usuario en AD.
  - Si el usuario no existe o esta inhabilitado, mostrar el modal de notificacion con el error correspondiente.
  - Si el usuario existe y esta habilitado, limpiar los campos del modal de contrasena, restablecer los checkboxes a sus valores por defecto, actualizar el texto `"Estado de bloqueo de cuenta en este controlador de dominio: Bloqueado / Desbloqueado"` y abrir el modal `"Restablecer contrasena"`.
- [x] 11.2. Conectar el envio del modal `"Restablecer contrasena"` (boton `"Aceptar"`) con `POST /api/reset-password`:
  - Enviar `{ username, newPassword, confirmPassword, changePasswordAtLogon, unlockAccount }`.
  - Al finalizar, cerrar el modal de contrasena y abrir el modal de notificacion confirmando el `"Cambio de contrasena exitoso"` o detallando el error devuelto por Active Directory (ej. politicas de complejidad).
- [x] 11.3. Actualizar la seccion `-IncludeLiveHttpTests` de `tests/backend.Tests.ps1` para que TODAS las pruebas en vivo utilicen **UNICA Y EXCLUSIVAMENTE** la cuenta `henkia.pruebas`, probando:
  - Consulta de estado (`POST /api/user-status`) para `henkia.pruebas`.
  - Cambio de contrasena, asignacion de `ChangePasswordAtLogon` y desbloqueo simultaneo (`POST /api/reset-password`) sobre `henkia.pruebas`.

### Pruebas y Criterios de Exito
- **Prueba:** Ejecucion completa de `tests/backend.Tests.ps1 -IncludeLiveHttpTests` operando exclusivamente sobre `henkia.pruebas`.
- **Criterio de exito:** Todas las pruebas unitarias y E2E en vivo aprueban sin errores, respetando estrictamente la restriccion de usar solo `henkia.pruebas`.
