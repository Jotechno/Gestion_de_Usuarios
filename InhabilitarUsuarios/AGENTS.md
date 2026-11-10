# Aplicación para inhabilitar usuarios - PoC Masivo (Script Aislado)

## Requisitos de Negocio

Este proyecto es una Prueba de Concepto (PoC) aislada, creada exclusivamente para la Mesa de Ayuda (Soporte IT). Su objetivo es automatizar las inhabilitaciones masivas tanto por "Paz y Salvo" como por "Vacaciones".
* **Selección de Proceso:** Al iniciar el script, se debe preguntar interactivamente al analista (vía consola) qué tipo de proceso desea ejecutar: "Paz y Salvo" o "Vacaciones".
* **Lectura de Archivo:** Luego de elegir el proceso, se abre una ventana nativa de Windows (`[System.Windows.Forms.OpenFileDialog]`) para que el analista seleccione manualmente su archivo `.csv` (leído con el comando nativo `Import-Csv`, omitiendo soporte o instalación para `.xlsx`), el cual incluye las columnas "NOMBRE" y "APELLIDO".
* **Búsqueda Inteligente:** El sistema busca en el Directorio Activo coincidencias usando el nombre y apellido, omitiendo automáticamente las cuentas que ya se encuentran inhabilitadas (`Enabled -eq $false`).
* **Confirmación Segura:** Antes de modificar el Active Directory, el script despliega una ventana nativa interactiva (`Out-GridView`) mostrando únicamente las columnas **"Nombre"**, **"Apellido"**, **"Usuario"**, **"Estado"** y **"Descripción"**. El analista selecciona manualmente qué usuarios procesar (con Clic o `Ctrl + Clic`). Los no seleccionados se descartan.
* **Reglas de Negocio:**
  * **Si eligió Vacaciones:** Solo se inhabilita la cuenta (`Disable-ADAccount`). No se mueve ni se cambia la descripción.
  * **Si eligió Paz y Salvo:** 
    1. Se inhabilita la cuenta (`Disable-ADAccount`).
    2. Se modifica la descripción agregando "(R) " al inicio (Ej: `(R) Auxiliar Logistica`).
    3. Se mueve el objeto a inactivos (`Move-ADObject`). Ruta destino: `OU=AL_INACTIVOS,OU=USUARIOS,OU=E_ALIAR,DC=aliar,DC=com,DC=co`.
* **Continuidad de Ejecución:** Al finalizar el proceso (y la reversión de prueba si aplica), el script pregunta en consola si el analista desea inhabilitar a más usuarios antes de cerrar.

## Estructura del Proyecto

Se mantiene una estructura plana y minimalista en la raíz del proyecto para evitar sobre-ingeniería:

```text
InhabilitarUsuarios/
├── AGENTS.md                   # Reglas de negocio, limitaciones y estándares del proyecto
├── PLAN.md                     # Plan detallado de implementación, pruebas y criterios de éxito
├── Test-Inhabilitaciones.ps1   # Script principal de PowerShell (flujo interactivo y auto-reversión)
└── usuarios.csv                # Archivo de entrada de prueba (contiene únicamente a henkia.pruebas)
```

## Limitaciones

* **CERO ENTORNO WEB:** Este es un script nativo de consola. No generar HTML, CSS, JavaScript, ni levantar servidores HTTP. 
* El entorno de ejecución será un equipo local de la Mesa de Ayuda unido al dominio de Aliar utilizando PowerShell.
* CERO INSTALACIONES EXTERNAS: No se puede instalar Node.js, Python, módulos externos para Excel (`.xlsx`), ni servidores web de terceros (Apache, Nginx). Tampoco se requiere instalar IDEs (se puede desarrollar con PowerShell ISE o Bloc de Notas).

## Decisiones Técnicas

* **Lenguaje:** Windows PowerShell (nativo).
* **Módulos y Ensamblados:** `ActiveDirectory` (comandos `Get-ADUser`, `Disable-ADAccount`, `Set-ADUser`, `Move-ADObject`), ensamblado nativo `System.Windows.Forms` (`OpenFileDialog`) y comando nativo `Import-Csv` para lectura exclusiva de archivos `.csv`.
* **Interfaz de Confirmación:** Uso de `Out-GridView -PassThru -Title "Confirme usuarios para inhabilitar"` con vista limpia de 5 columnas (`Nombre`, `Apellido`, `Usuario`, `Estado`, `Descripción`).
* **Regla Estricta de Pruebas (CRÍTICA):** ESTÁ ESTRICTAMENTE PROHIBIDO usar usuarios reales. Solo se usará la cuenta `henkia.pruebas`. 
  * **Auto-Reversión:** El código de prueba debe incluir un bloque final que deshaga los cambios hechos a `henkia.pruebas` (re-habilitar, quitar "(R) " si aplica, y devolver a su OU original) para dejarlo listo para la siguiente prueba.

## Estándares de Codificación

1. Escribir código PowerShell robusto con `Try/Catch`.
2. Mantenerlo simple - NUNCA sobre-ingenierizar. 
3. Ser conciso y mantener comentarios útiles. Cero emojis.
4. Mostrar salidas en consola para llevar un log claro.
5. Cuando encuentres problemas, siempre identifica la causa raíz antes de intentar una solución. No adivines. Prueba con evidencia, luego corrige la causa raíz.
