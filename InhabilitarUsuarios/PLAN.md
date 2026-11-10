# Plan de Implementación - PoC Inhabilitación Masiva de Usuarios (AD)

## Estructura del Proyecto

El proyecto utiliza una estructura plana y directa en la raíz del repositorio:

```text
InhabilitarUsuarios/
├── AGENTS.md                   # Reglas de negocio, limitaciones y estándares del proyecto
├── PLAN.md                     # Este documento de planificación y seguimiento
├── Test-Inhabilitaciones.ps1   # Script principal de PowerShell (flujo completo + auto-reversión)
└── usuarios.csv                # Datos de prueba exclusivos con el usuario henkia.pruebas
```

---

## Parte 1: Planificación

Enriquecer este documento para planificar cada una de las partes en detalle, con subpasos enumerados en una lista de verificación que el agente deberá marcar, e incluyendo pruebas y criterios de éxito para cada uno. Asegurar que el usuario revise y apruebe el plan antes de pasar a la ejecución.

### Subpasos
- [x] **1.1.** Revisar y analizar los requisitos de negocio y restricciones técnicas en `AGENTS.md` y `PLAN.md`.
- [x] **1.2.** Resolver dudas de alcance con el usuario (estructura del proyecto, lectura exclusiva de `.csv` con `Import-Csv`, formato del prefijo `(R) `, y lógica de búsqueda difusa).
- [x] **1.3.** Definir y documentar la estructura de archivos del proyecto en `AGENTS.md` y `PLAN.md`.
- [x] **1.4.** Desglosar las Partes 2 a 6 con subpasos numerados, pruebas de verificación y criterios de éxito.
- [x] **1.5.** Obtener la revisión y aprobación explícita del usuario sobre este `PLAN.md`.

### Pruebas y Criterios de Éxito
* **Prueba:** Verificar que `PLAN.md` y `AGENTS.md` estén alineados sin contradicciones y cubran todas las reglas de negocio (omitiendo `.xlsx` y dejando únicamente `.csv`).
* **Criterio de éxito:** El usuario aprueba el plan enriquecido para ejecutar las siguientes partes.

---

## Parte 2: Estructura, Base y Selección

Crear el archivo `Test-Inhabilitaciones.ps1` para las pruebas y el archivo de prueba `usuarios.csv` con las columnas `NOMBRE` y `APELLIDO` (siendo el nombre `henkia` y el apellido `pruebas`). Mostrar en consola un menú interactivo que permita elegir entre `1. Vacaciones` o `2. Paz y Salvo`, y luego abrir una ventana nativa `[System.Windows.Forms.OpenFileDialog]` para seleccionar el archivo `.csv` y leerlo con `Import-Csv`.

### Subpasos
- [x] **2.1.** Crear el archivo `usuarios.csv` en la raíz del proyecto con las columnas `NOMBRE,APELLIDO` y una única fila: `henkia,pruebas`.
- [x] **2.2.** Cargar el ensamblado `System.Windows.Forms` y verificar disponibilidad del módulo `ActiveDirectory` en el entorno local.
- [x] **2.3.** Implementar el menú interactivo en consola para seleccionar el tipo de proceso (`1. Vacaciones` o `2. Paz y Salvo`).
- [x] **2.4.** Desplegar `[System.Windows.Forms.OpenFileDialog]` luego de elegir la opción 1 o 2 para que el analista busque y seleccione manualmente su archivo `.csv`.
- [x] **2.5.** Implementar el bloque de carga del archivo `.csv` con `Try/Catch` usando exclusivamente `Import-Csv` (detectando delimitador `,` o `;` automáticamente y validando que existan las columnas `NOMBRE` y `APELLIDO`).

### Pruebas y Criterios de Éxito
* **Prueba:** Ejecutar el script, elegir una opción del menú y seleccionar `usuarios.csv` desde el cuadro de diálogo de Windows.
* **Criterio de éxito:** El script identifica correctamente la opción seleccionada, abre el selector de archivos, carga el `.csv` seleccionado extrayendo `NOMBRE` y `APELLIDO`, y muestra mensajes claros en consola sin errores.

---

## Parte 3: Lógica de Búsqueda y Filtrado (AD)

Recorrer cada fila del archivo CSV usando `Get-ADUser` para buscar coincidencias difusas con el nombre y apellido dados. Excluir los usuarios que ya se encuentren inhabilitados (`Enabled -eq $false`), guardar los metadatos técnicos internamente (como la ruta OU original para reversión) y construir la lista de vista con las columnas solicitadas.

### Subpasos
- [x] **3.1.** Inicializar el arreglo `$UsuariosVista = @()` y el diccionario interno `$MetadatosUsuariosAD = @{}`.
- [x] **3.2.** Recorrer cada fila del CSV validando que `NOMBRE` y `APELLIDO` no sean nulos o vacíos.
- [x] **3.3.** Ejecutar búsqueda difusa en Active Directory con `Try/Catch` solicitando las propiedades `SamAccountName`, `Name`, `DisplayName`, `GivenName`, `Surname`, `Enabled`, `Description` y `DistinguishedName`:
  * **Paso A (Principal):** Buscar cuentas activas (`Enabled -eq $true`) donde `GivenName -like "*$Nombre*" -and Surname -like "*$Apellido*"`.
  * **Paso B (Respaldo):** Si el Paso A no arroja resultados, buscar cuentas activas donde `Name -like "*$Nombre*$Apellido*" -or DisplayName -like "*$Nombre*$Apellido*" -or SamAccountName -like "*$Nombre*$Apellido*"`.
- [x] **3.4.** Extraer y respaldar internamente la ruta de la OU original (`OUOriginal`) y descripción original (`DescriptionOriginal`) asociadas al `SamAccountName`.
- [x] **3.5.** Agregar cada coincidencia activa a `$UsuariosVista` con las 5 columnas de presentación: `Nombre`, `Apellido`, `Usuario`, `Estado` y `Descripción`.

### Pruebas y Criterios de Éxito
* **Prueba:** Ejecutar la búsqueda en el dominio contra el registro `henkia` / `pruebas` del archivo `usuarios.csv`.
* **Criterio de éxito:** El script localiza únicamente la cuenta activa `henkia.pruebas`, conserva internamente su `DescriptionOriginal` y `OUOriginal`, y prepara el objeto de vista con las 5 columnas limpias.

---

## Parte 4: Interfaz de Confirmación (Staging)

Pasar el arreglo de usuarios encontrados a `Out-GridView -PassThru -Title "Confirme usuarios para inhabilitar"` y almacenar la selección del analista en la variable `$UsuariosConfirmados`. Detener la ejecución de forma segura si no se selecciona ningún usuario o si no hubo coincidencias en la búsqueda.

### Subpasos
- [x] **4.1.** Validar si `$UsuariosVista` contiene al menos un registro; si está vacío, mostrar mensaje informativo en consola.
- [x] **4.2.** Invocar `$UsuariosConfirmados = @($UsuariosVista | Out-GridView -PassThru -Title "Confirme usuarios para inhabilitar")` mostrando únicamente `Nombre`, `Apellido`, `Usuario`, `Estado` y `Descripción`.
- [x] **4.3.** Verificar si `$UsuariosConfirmados` está vacío (el analista cerró la ventana o presionó Cancelar sin seleccionar filas). En ese caso, registrar en consola que la operación fue cancelada por el usuario sin realizar cambios en AD.

### Pruebas y Criterios de Éxito
* **Prueba:** Ejecutar el flujo hasta `Out-GridView`, seleccionando a `henkia.pruebas` y haciendo clic en "Aceptar" (OK).
* **Criterio de éxito:** La ventana `Out-GridView` muestra únicamente las 5 columnas requeridas, filtra solo los usuarios seleccionados en `$UsuariosConfirmados` y descarta los no seleccionados.

---

## Parte 5: Ejecución de Reglas de Negocio (Bifurcación)

Por cada usuario en `$UsuariosConfirmados`, aplicar una estructura condicional según la elección de la Parte 2:
* **Vacaciones:** Solo inhabilitar la cuenta (`Disable-ADAccount`).
* **Paz y Salvo:** Inhabilitar la cuenta (`Disable-ADAccount`), agregar el prefijo `(R) ` al inicio de la descripción (ej. `Supervisor Tipo C - MET_GAN` -> `(R) Supervisor Tipo C - MET_GAN`) evitando duplicarlo si ya lo tiene, y mover el usuario a la OU de inactivos `OU=AL_INACTIVOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co`.
Mostrar en consola el resultado exitoso de cada paso o el detalle exacto de dónde falló.

### Subpasos
- [x] **5.1.** Definir la constante `$OUInactivos = "OU=AL_INACTIVOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co"`.
- [x] **5.2.** Implementar una salvaguarda de seguridad durante la PoC para asegurar que solo se procese la cuenta de prueba autorizada (`henkia.pruebas`), evitando cualquier modificación accidental a cuentas reales.
- [x] **5.3.** Si el proceso es **Vacaciones (Opción 1)**:
  * Dentro de un bloque `Try/Catch`, ejecutar `Disable-ADAccount -Identity $Cuenta -ErrorAction Stop`.
  * Mostrar confirmación en consola de cuenta inhabilitada por Vacaciones.
- [x] **5.4.** Si el proceso es **Paz y Salvo (Opción 2)**:
  * **Paso 1 (Inhabilitar):** Ejecutar `Disable-ADAccount -Identity $Cuenta -ErrorAction Stop` dentro de su propio `Try/Catch` y registrar en consola.
  * **Paso 2 (Descripción):** Calcular la nueva descripción anteponiendo `"(R) "` a `$InfoTecnica.DescriptionOriginal` (si aún no inicia con `(R)`). Ejecutar `Set-ADUser -Identity $Cuenta -Description $NuevaDescripcion -ErrorAction Stop` y registrar en consola.
  * **Paso 3 (Mover OU):** Obtener el `DistinguishedName` actual del usuario y ejecutar `Move-ADObject -Identity $DNActual -TargetPath $OUInactivos -ErrorAction Stop` y registrar en consola.
- [x] **5.5.** En caso de error en cualquiera de las operaciones de AD, capturar la excepción en el `Catch` indicando claramente el usuario, la operación específica que falló (`Inhabilitar`, `Actualizar Descripción` o `Mover a OU Inactivos`) y el mensaje de error técnico.

### Pruebas y Criterios de Éxito
* **Prueba:** Verificar en Active Directory con `Get-ADUser -Identity henkia.pruebas -Properties Enabled, Description, DistinguishedName` el estado posterior a cada flujo.
* **Criterio de éxito:**
  * En **Vacaciones**: `Enabled` pasa a `$false`, `Description` y `DistinguishedName` permanecen intactos.
  * En **Paz y Salvo**: `Enabled` pasa a `$false`, `Description` inicia con `(R) `, y `DistinguishedName` refleja la ruta `OU=AL_INACTIVOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co`.

---

## Parte 6: Pruebas con "henkia.pruebas", Auto-Reversión y Bucle de Continuidad

Ejecutar el script seleccionando "Vacaciones" y luego "Paz y Salvo" con el usuario de pruebas `henkia.pruebas`. Incluir un bloque de código al final del proceso que deshaga cualquier cambio realizado a `henkia.pruebas` (re-habilitar la cuenta, restaurar su descripción original y devolverlo a su Unidad Organizativa original) y preguntar al analista si desea procesar más usuarios antes de cerrar.

### Subpasos
- [x] **6.1.** Antes de modificar a `henkia.pruebas`, respaldar en memoria su estado inicial: `SamAccountName`, `DescriptionOriginal` y `OUOriginal`.
- [x] **6.2.** Implementar al final de `Test-Inhabilitaciones.ps1` el bloque/función de **Auto-Reversión** (`Invoke-ReversionHenkiaPruebas`) para `henkia.pruebas`:
  * Re-habilitar la cuenta con `Enable-ADAccount -Identity "henkia.pruebas"`.
  * Restaurar la descripción original (quitando el prefijo `(R) `) con `Set-ADUser`.
  * Si el usuario fue movido a `AL_INACTIVOS`, moverlo de vuelta a su `$OUOriginal` usando `Move-ADObject`.
  * Consultar nuevamente `Get-ADUser` y mostrar en consola el estado restaurado como evidencia.
- [x] **6.3.** Ejecutar **Prueba Completa 1 (Vacaciones)** con `henkia.pruebas`, verificar que quede inhabilitado, y ejecutar la Auto-Reversión verificando que vuelva a su estado original.
- [x] **6.4.** Ejecutar **Prueba Completa 2 (Paz y Salvo)** con `henkia.pruebas`, verificar inhabilitación, cambio de descripción con `(R) ` y movimiento a `OU=AL_INACTIVOS,...`, y ejecutar la Auto-Reversión verificando que vuelva a su OU, descripción y estado activo original.
- [x] **6.5.** Implementar bucle principal para preguntar al analista si desea inhabilitar a más usuarios (`S/N`) antes de finalizar el script.

### Pruebas y Criterios de Éxito
* **Prueba:** Ejecución de extremo a extremo de ambos escenarios (Vacaciones y Paz y Salvo) seguidos de su respectiva reversión, validando con `Get-ADUser` antes, durante y después.
* **Criterio de éxito:** Ambos flujos cumplen el 100% de las reglas de negocio y, tras ejecutar el bloque de auto-reversión, la cuenta `henkia.pruebas` queda habilitada (`Enabled = True`), con su descripción original sin `(R) ` y ubicada exactamente en su OU original.
