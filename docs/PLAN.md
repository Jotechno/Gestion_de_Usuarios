# Plan de Ejecucion del Proyecto: Gestion de Usuarios de Dominio

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
│   └── ad-service.ps1         # Logica de Active Directory (desbloqueo, cambio de clave e inhabilitacion masiva)
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

### Lista de verificacion
- [x] 3.1. Estructurar `public/index.html` con Tailwind CSS via CDN replicando la maquetacion y proporciones de `demoView.jpg` con la paleta de colores definida (`#032147`, `#208342`, `#97C03C`, `#FDC90A`, `#FFDF80`, `#888888`).
- [x] 3.2. Incorporar la barra superior en `#032147`, el fondo geometrico sutil, la tarjeta con linea superior amarilla segmentada y el indicador inferior de estado de conexion.
- [x] 3.3. Crear el formulario de un solo paso con el campo redondeado `nombre.apellido` (con icono SVG de usuario) y el boton redondeado `Desbloquear Usuario` (con icono SVG de candado).
- [x] 3.4. Implementar validacion en Vanilla JS: mantener el boton "Desbloquear Usuario" deshabilitado hasta que se ingrese un formato valido de usuario.
- [x] 3.5. Construir el componente modal de notificacion (armonizado con el estilo de `demoView.jpg`) para mostrar "Desbloqueo exitoso" o el detalle del "Error" retornado por el servidor.

---

## Parte 4: Control de Acceso por Contexto de Sesion de Windows

Validar la identidad del analista a partir del contexto de la sesion de Windows del proceso local y verificar que pertenezca al grupo autorizado (`Admins. del dominio` / `Domain Admins`, configurable en el script).

### Lista de verificacion
- [x] 4.1. Obtener la identidad del usuario de Windows que ejecuta el proceso local mediante `[System.Security.Principal.WindowsIdentity]::GetCurrent()`.
- [x] 4.2. Implementar en `scripts/ad-service.ps1` la funcion de verificacion de pertenencia al grupo autorizado (`Admins. del dominio` / `Domain Admins`).
- [x] 4.3. Bloquear la ejecucion de acciones (HTTP 403 Forbidden) si el usuario en sesion no pertenece al grupo autorizado, e informar en la interfaz que no cuenta con permisos.
- [x] 4.4. Exponer el endpoint `GET /api/session` para que el frontend consulte el usuario actual y su estado de autorizacion al cargar la pagina.

---

## Parte 5: Integracion con Active Directory (Comandos Nativos)

Estructurar las funciones nativas del modulo `ActiveDirectory` en `scripts/ad-service.ps1` para consultar y desbloquear cuentas en un solo flujo cumpliendo la regla de negocio.

### Lista de verificacion
- [x] 5.1. Validar disponibilidad e importacion del modulo `ActiveDirectory` (`Import-Module ActiveDirectory`).
- [x] 5.2. Implementar la consulta del usuario con `Get-ADUser -Identity <usuario> -Properties LockedOut, Enabled, DisplayName`.
- [x] 5.3. Implementar la regla de negocio estricta en `Invoke-UserUnlock`.

---

## Parte 6: Backend (Servidor HTTP y API en PowerShell)

Completar `scripts/server.ps1` integrando `scripts/ad-service.ps1` para escuchar las peticiones del frontend y responder en formato JSON estandarizado.

### Lista de verificacion
- [x] 6.1. Implementar enrutador HTTP en `scripts/server.ps1` para `GET /`, `GET /api/session` y `POST /api/unlock`.
- [x] 6.2. Sanitizar y validar el formato del `username` en el backend antes de invocar cmdlets de AD.
- [x] 6.3. Estandarizar respuestas JSON con codigos HTTP apropiados (200, 400, 403, 404, 422, 500).
- [x] 6.4. Escribir y ejecutar `tests/backend.Tests.ps1` para validar la logica del backend, el control de acceso y las reglas de negocio.

---

## Parte 7: Integracion Frontend + Backend y Pruebas Finales (Fase 1)

Conectar el frontend con la API del backend para completar el flujo de extremo a extremo de desbloqueo de usuarios.

### Lista de verificacion
- [x] 7.1. Conectar la carga inicial de `public/index.html` con `GET /api/session` y el envio del formulario con `POST /api/unlock` mediante `fetch()`.
- [x] 7.2. Manejar estados de carga en el boton ("Procesando...") para evitar envios duplicados.
- [x] 7.3. Mostrar en el modal el resultado exacto devuelto por el backend y limpiar el campo tras un desbloqueo exitoso.
- [x] 7.4. Realizar pruebas integrales de extremo a extremo (E2E) verificando el funcionamiento completo.

---
---

# Fase 2: Escalabilidad - Modulo de Cambio de Contrasena en Active Directory

> **Restriccion Estricta de Pruebas (CRITICO):** Esta estrictamente prohibido utilizar usuarios aleatorios o el usuario personal del analista en las pruebas en vivo. Para TODAS las pruebas de esta fase se utilizara **UNICA Y EXCLUSIVAMENTE** la cuenta de pruebas: `henkia.pruebas`.

---

## Parte 8: Planificacion de la Fase 2 (Cambio de Contrasena)

### Lista de verificacion
- [x] 8.1. Analizar requerimientos de interfaz (botones 50/50, modal inspirado en la ventana nativa de AD) y comandos de Active Directory (`Set-ADAccountPassword`, `Set-ADUser -ChangePasswordAtLogon`, `Unlock-ADAccount`).
- [x] 8.2. Resolver preguntas abiertas con el usuario.
- [x] 8.3. Actualizar `AGENTS.md` y `docs/PLAN.md` con las especificaciones y fases detalladas (Partes 8 a 11).
- [x] 8.4. Obtener aprobacion del usuario para iniciar la Parte 9.

---

## Parte 9: Logica de Active Directory y Endpoints Backend para Cambio de Contrasena

### Lista de verificacion
- [x] 9.1. Implementar en `scripts/ad-service.ps1` la funcion `Invoke-UserStatusCheck`.
- [x] 9.2. Implementar en `scripts/ad-service.ps1` la funcion `Invoke-UserPasswordReset`.
- [x] 9.3. Implementar los controladores HTTP `Invoke-UserStatusApiController` y `Invoke-PasswordResetApiController` en `scripts/ad-service.ps1`, y registrar en `scripts/server.ps1` las rutas `POST /api/user-status` y `POST /api/reset-password`.
- [x] 9.4. Ampliar las pruebas unitarias en `tests/backend.Tests.ps1`.

---

## Parte 10: Frontend (Botones 50/50 y Modal "Restablecer contrasena")

### Lista de verificacion
- [x] 10.1. Ajustar el contenedor de acciones del formulario principal en `public/index.html` para dividir el espacio en dos columnas iguales (50/50).
- [x] 10.2. Construir en `public/index.html` el modal `"Restablecer contrasena"` armonizado con la paleta del proyecto e incluyendo todos los elementos de la ventana nativa de AD.
- [x] 10.3. Implementar validacion en Vanilla JS para los campos del modal de contrasena.

---

## Parte 11: Integracion Frontend + Backend y Pruebas E2E con `henkia.pruebas`

### Lista de verificacion
- [x] 11.1. Conectar el clic en `"Cambiar Contrasena"` con `POST /api/user-status`.
- [x] 11.2. Conectar el envio del modal `"Restablecer contrasena"` (boton `"Aceptar"`) con `POST /api/reset-password`.
- [x] 11.3. Actualizar la seccion `-IncludeLiveHttpTests` de `tests/backend.Tests.ps1` para que TODAS las pruebas en vivo utilicen **UNICA Y EXCLUSIVAMENTE** la cuenta `henkia.pruebas`.

---
---

# Fase 3: Integracion del Modulo de Inhabilitacion Masiva de Usuarios por CSV

> **Nota de Arquitectura y Pruebas:** El motor de Active Directory en `scripts/ad-service.ps1` debe contener unicamente la logica pura de negocio (sin `OpenFileDialog`, sin `Out-GridView`, sin auto-reversion y sin bloqueo harcodeado de `henkia.pruebas`). Para las pruebas automatizadas en vivo (`tests/backend.Tests.ps1 -IncludeLiveHttpTests`), se seguira utilizando **UNICA Y EXCLUSIVAMENTE** la cuenta `henkia.pruebas` (revirtiendo su estado al finalizar el test).

---

## Parte 12: Planificacion y Documentacion de la Fase 3 (Inhabilitacion Masiva)

Analizar el script aislado `Test-Inhabilitaciones.ps1`, definir la arquitectura web de 2 pasos (`preview` y `execute`) y actualizar la documentacion del proyecto.

### Lista de verificacion
- [x] 12.1. Revisar `Test-Inhabilitaciones.ps1` y sus documentos asociados para extraer las reglas validadas de `Vacaciones` y `Paz y Salvo`.
- [x] 12.2. Resolver preguntas de diseno con el usuario (navegacion por pestanas Segmented Control, envio de CSV en JSON, checkboxes desmarcados por defecto en el modal de verificacion y limpieza de carpeta temporal al finalizar).
- [x] 12.3. Actualizar `AGENTS.md` y `docs/PLAN.md` con el plan detallado de las Partes 12 a 15.
- [x] 12.4. Obtener aprobacion del usuario para iniciar la Parte 13.

### Pruebas y Criterios de Exito
- **Prueba:** Revision de `AGENTS.md` y `docs/PLAN.md` por parte del usuario.
- **Criterio de exito:** El usuario aprueba iniciar la Parte 13.

---

## Parte 13: Motor de Active Directory y Endpoints Backend (`POST /api/masivo/preview` y `POST /api/masivo/execute`)

Migrar el motor puro de Active Directory desde `Test-Inhabilitaciones.ps1` hacia `scripts/ad-service.ps1` y exponer los dos nuevos endpoints en `scripts/server.ps1`.

### Lista de verificacion
- [x] 13.1. Implementar en `scripts/ad-service.ps1` la funcion `Invoke-BulkDisablePreview`:
  - Recibir el texto del archivo CSV (`CsvContent`).
  - Validar que no este vacio, detectar automaticamente el delimitador (`;` o `,`) en la primera linea y parsear los registros con `ConvertFrom-Csv`.
  - **Normalizacion critica de encabezados:** Aplicar `.Trim().ToUpperInvariant()` a los nombres de las propiedades de cada fila para tolerar espacios adicionales o minusculas (`"NOMBRE "`, `" NOMBRE"`, `" APELLIDO"`, `"APELLIDO "`, `"nombre"`, `"apellido"`). Validar que existan ambas columnas (`HTTP 400` si faltan).
  - Por cada fila con nombre o apellido no vacios, buscar en Active Directory cuentas activas (`Enabled -eq $true`):
    - Busqueda principal: `Enabled -eq $true -and GivenName -like "*$Nombre*" -and Surname -like "*$Apellido*"`.
    - Busqueda de respaldo: `Enabled -eq $true -and (Name -like "*$Nombre*$Apellido*" -or DisplayName -like "*$Nombre*$Apellido*" -or SamAccountName -like "*$Nombre*$Apellido*")`.
  - Omitir duplicados y retornar la lista de usuarios activos encontrados (`nombre`, `apellido`, `usuario`, `estado`, `descripcion`) junto con la lista de filas del CSV que no arrojaron coincidencias activas (`unmatchedRows`).
- [x] 13.2. Implementar en `scripts/ad-service.ps1` la funcion `Invoke-BulkDisableExecute`:
  - Recibir el tipo de proceso (`ProcessType`: `'Vacaciones'` o `'Paz y Salvo'`) y el arreglo de nombres de usuario confirmados (`Usernames`).
  - Por cada usuario seleccionado, consultar su estado actual en AD (`Get-ADUser -Identity <usuario> -Properties Enabled, Description, DistinguishedName, DisplayName`) y aplicar las reglas puras de negocio:
    - **Si es `'Vacaciones'`:** Ejecutar `Disable-ADAccount -Identity <usuario> -ErrorAction Stop`.
    - **Si es `'Paz y Salvo'`:**
      1. Ejecutar `Disable-ADAccount -Identity <usuario> -ErrorAction Stop`.
      2. Calcular la nueva descripcion anteponiendo `"(R) "` a la descripcion actual (sin duplicar si ya inicia con `(R)`) y ejecutar `Set-ADUser -Identity <usuario> -Description $NuevaDescripcion -ErrorAction Stop`.
      3. Mover el objeto en AD a la OU `OU=AL_INACTIVOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co` mediante `Move-ADObject -Identity <DistinguishedName> -TargetPath $OUInactivos -ErrorAction Stop`.
  - Retornar un resumen detallado con el total de cuentas procesadas exitosamente y el detalle por cada usuario.
- [x] 13.3. Implementar los controladores `Invoke-BulkPreviewApiController` e `Invoke-BulkExecuteApiController` en `scripts/ad-service.ps1` (validando sesion autorizada `HTTP 403`) y registrar en `scripts/server.ps1` las rutas:
  - `POST /api/masivo/preview`
  - `POST /api/masivo/execute`
- [x] 13.4. Agregar pruebas unitarias en `tests/backend.Tests.ps1` para validar:
  - Limpieza de encabezados CSV con espacios y minusculas (`" nombre "`, `"APELLIDO "` con delimitador `,` y `;`).
  - Filtrado de cuentas ya inhabilitadas en `Invoke-BulkDisablePreview`.
  - Regla de negocio `Vacaciones` (solo llama a `Disable-ADAccount`).
  - Regla de negocio `Paz y Salvo` (llama a `Disable-ADAccount`, `Set-ADUser -Description "(R) ..."` y `Move-ADObject` hacia `AL_INACTIVOS`).

### Pruebas y Criterios de Exito
- **Prueba:** Ejecucion de las pruebas unitarias en `tests/backend.Tests.ps1`.
- **Criterio de exito:** Todas las pruebas unitarias aprueban validando el parseo tolerante del CSV y la bifurcacion exacta entre `Vacaciones` y `Paz y Salvo`.

---

## Parte 14: Frontend (Navegacion por Pestanas, Vista de Inhabilitacion Masiva y Modal de Verificacion)

Actualizar `public/index.html` para incorporar el selector de modulo al inicio, la vista de carga de CSV y el Modal de Verificacion con checkboxes.

### Lista de verificacion
- [x] 14.1. Incorporar en la tarjeta principal de `public/index.html` un selector superior tipo pestanas (Segmented Control) que permita elegir que desea hacer el analista:
  - Pestana 1: `"Desbloqueo / Contraseña"` (muestra la vista individual actual).
  - Pestana 2: `"Inhabilitación Masiva"` (muestra la nueva vista por lotes CSV).
- [x] 14.2. Construir la vista `"Inhabilitación Masiva"` dentro de la tarjeta principal:
  - Selector `<select id="bulkProcessSelect">` con las opciones `"Vacaciones"` y `"Paz y Salvo"` (mostrando una breve nota dinamica de lo que hace cada proceso).
  - Selector de archivo `<input type="file" id="bulkCsvInput" accept=".csv">` estilizado con la paleta del proyecto.
  - Boton `"Analizar Archivo"` (`#analyzeCsvBtn`), habilitado cuando se haya seleccionado un archivo `.csv`.
- [x] 14.3. Construir el **Modal de Verificacion Masiva** (`#bulkVerifyModal`, reemplazo web de `Out-GridView`):
  - Encabezado mostrando el tipo de proceso seleccionado (`Vacaciones` o `Paz y Salvo`) y el conteo de cuentas encontradas.
  - Casilla superior `"Seleccionar todos"` y contador dinamico de usuarios seleccionados (`"X de Y seleccionados"`).
  - Tabla con scroll vertical mostrando las columnas: **Check**, **Nombre**, **Apellido**, **Usuario**, **Estado** y **Descripción**. Todos los checkboxes individuales inician **desmarcados por defecto**.
  - Seccion informativa opcional (visible cuando existan filas del CSV sin coincidencia activa en AD) listando los nombres no encontrados o ya inactivos.
  - Boton `"Ejecutar"` (habilitado solo cuando al menos un checkbox este marcado) y boton `"Cancelar"`.

### Pruebas y Criterios de Exito
- **Prueba:** Verificacion estructural y funcional de `public/index.html` (cambio de pestana entre vistas, controles de proceso y archivo `.csv`, tabla del modal de verificacion y checkboxes desmarcados por defecto).
- **Criterio de exito:** La interfaz alterna limpiamente entre ambos modulos, mantiene el diseno corporativo anonimo sin emojis y habilita `"Ejecutar"` solo al seleccionar al menos un usuario en el modal.

---

## Parte 15: Integracion E2E, Pruebas en Vivo con `henkia.pruebas` y Limpieza Final

Conectar el flujo completo entre el frontend y los endpoints masivos, ejecutar las pruebas E2E en vivo exclusivamente con `henkia.pruebas` (con reversion en el test) y limpiar la carpeta temporal `InhabilitarUsuarios/`.

### Lista de verificacion
- [x] 15.1. Conectar en `public/index.html` el boton `"Analizar Archivo"`: leer el contenido del `.csv` con `file.text()`, enviarlo a `POST /api/masivo/preview` y poblar el Modal de Verificacion (o mostrar el modal de aviso si no se encontraron cuentas activas).
- [x] 15.2. Conectar en `public/index.html` el boton `"Ejecutar"` del Modal de Verificacion: enviar los usuarios marcados con check y el tipo de proceso a `POST /api/masivo/execute`, cerrar el modal de verificacion y mostrar el resumen final en el modal de notificacion.
- [x] 15.3. Ampliar la seccion `-IncludeLiveHttpTests` de `tests/backend.Tests.ps1` utilizando **UNICA Y EXCLUSIVAMENTE** la cuenta `henkia.pruebas`:
  - Probar `POST /api/masivo/preview` enviando un CSV con encabezados con espacios (`" nombre , APELLIDO \nhenkia,pruebas"`) y verificar que localice a `henkia.pruebas`.
  - Probar `POST /api/masivo/execute` con `Vacaciones` sobre `henkia.pruebas`, verificar en AD que `Enabled` sea `$false`, y restaurar a `henkia.pruebas`.
  - Probar `POST /api/masivo/execute` con `Paz y Salvo` sobre `henkia.pruebas`, verificar en AD que `Enabled` sea `$false`, `Description` inicie con `(R) ` y su OU sea `AL_INACTIVOS`, y ejecutar en el bloque `finally` del test la restauracion completa de `henkia.pruebas` a su OU, descripcion y estado habilitado originales.
- [x] 15.4. Eliminar la carpeta temporal `InhabilitarUsuarios/` tras verificar que todas las pruebas pasen.

### Pruebas y Criterios de Exito
- **Prueba:** Ejecucion completa de `tests/backend.Tests.ps1 -IncludeLiveHttpTests` validando todas las pruebas unitarias y E2E en vivo, y verificacion del estado restaurado de `henkia.pruebas` en Active Directory.
- **Criterio de exito:** 100% de las pruebas aprobadas, `henkia.pruebas` restaurado en su OU y estado activo original, y carpeta temporal `InhabilitarUsuarios/` eliminada.

---
---

# Fase 4: Flexibilizacion de Formato de Usuario y Soporte Nativo de Archivos XLSX / CSV Multicapa

## Parte 16: Usuarios sin Punto Obligatorio y Lector Inteligente de Archivos CSV / XLSX

Permitir cuentas de dominio con o sin punto (`usuario` o `nombre.apellido`) en toda la aplicacion, e incorporar soporte nativo para archivos `.xlsx` y `.csv` complejos (con encabezados en filas intermedias y columnas duplicadas posteriores).

### Lista de verificacion
- [x] 16.1. Actualizar `Test-ValidUsernameFormat` en `scripts/ad-service.ps1` y `USERNAME_REGEX` en `public/index.html` para aceptar cualquier nombre de cuenta valido en Active Directory sin espacios (`^[a-zA-Z0-9._-]+$`), soportando tanto `nombre.apellido` como nombres unicos (`usuario`).
- [x] 16.2. Implementar en `scripts/ad-service.ps1` el extractor inteligente de tablas `Get-NombreApellidoRecordsFromMatrix`, el parser CSV RFC 4180 (`ConvertFrom-CsvToMatrix`, tolerante a celdas multilinea entre comillas) y el lector nativo OpenXML `.xlsx` (`ConvertFrom-XlsxBase64ToSheetsMatrix`, usando `System.IO.Compression.ZipArchive` y `[xml]` sin requerir Excel ni librerias externas):
  - Escanear las filas hasta localizar automaticamente la primera fila de encabezados que contenga tanto `'NOMBRE'` como `'APELLIDO'` (aplicando `.Trim().ToUpperInvariant()`).
  - Al recorrer las celdas de esa fila de izquierda a derecha, **detener la lectura de columnas inmediatamente al ubicar `'NOMBRE'` y `'APELLIDO'`**, ignorando todas las columnas a la derecha (evitando fallos por columnas repetidas como `VIATICOS` o `DIAS DE SUSPENSION`).
  - Extraer unicamente las columnas `NOMBRE` y `APELLIDO` de la tabla principal y detenerse al finalizar los registros de esa tabla.
- [x] 16.3. Actualizar `Invoke-BulkDisablePreview` e `Invoke-BulkPreviewApiController` en `scripts/ad-service.ps1` y la vista de carga en `public/index.html` (`accept=".csv,.xlsx"`) para admitir tanto texto CSV (`csvContent`) como archivos Excel en Base64 (`xlsxBase64`).
- [x] 16.4. Actualizar y ejecutar `tests/backend.Tests.ps1` para validar usuarios de un solo nombre (`recepcion`, `soporte`), archivos CSV con encabezados en la fila 5 y columnas duplicadas, y archivos `.xlsx` generados en memoria.

### Pruebas y Criterios de Exito
- **Prueba:** Ejecucion de `tests/backend.Tests.ps1` validando usuarios sin punto, parseo de CSV multicapa con columnas repetidas y parseo nativo de archivos `.xlsx`.
- **Criterio de exito:** Todas las pruebas automatizadas aprueban sin errores.
