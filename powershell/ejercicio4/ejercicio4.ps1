<#
.SYNOPSIS
    Monitorea un directorio en segundo plano y respalda archivos duplicados.

.DESCRIPTION
    Monitorea un directorio y todos sus subdirectorios en segundo plano como proceso demonio.
    Utiliza System.IO.FileSystemWatcher para detectar la creación de archivos.
    Si se detecta que un archivo nuevo tiene el mismo nombre y el mismo tamaño que otro
    archivo existente dentro del árbol del directorio monitoreado (criterio de duplicado del
    Ejercicio 3), registra el evento en un archivo 'duplicados.log' y genera un archivo comprimido
    ZIP con los archivos duplicados en la carpeta de salida.
    
    El nombre del archivo de backup tiene el formato 'yyyyMMdd-HHmmss.zip'.
    El script se ejecuta como demonio en segundo plano sin requerir comandos adicionales del usuario.
    Permite finalizar un demonio previamente iniciado para el directorio mediante el parámetro -kill.
    No permite ejecutar más de un demonio para el mismo directorio al mismo tiempo.

.PARAMETER directorio
    Ruta del directorio a monitorear (obligatorio). Acepta rutas relativas, absolutas o con espacios.

.PARAMETER salida
    Ruta del directorio donde se guardarán los archivos comprimidos de backup y el archivo 'duplicados.log'.
    Obligatorio al iniciar el monitoreo. No puede ubicarse dentro del directorio monitoreado.

.PARAMETER kill
    Flag (switch) para detener el proceso demonio que se encuentre monitoreando el directorio indicado.
    Solo puede utilizarse junto con -directorio.

.EXAMPLE
    Get-Help .\ejercicio4.ps1 -Detailed
    Muestra la ayuda detallada del script.

.EXAMPLE
    .\ejercicio4.ps1 -directorio .\monitor -salida .\salida
    Inicia el demonio de monitoreo en segundo plano.

.EXAMPLE
    .\ejercicio4.ps1 -directorio .\monitor -kill
    Detiene el demonio que está monitoreando el directorio especificado.

.NOTES
    Virtualización de Hardware - APL 1 - 2026 Q2 - Ejercicio 4
    Integrantes:
      - Almada, Keila Mariel - DNI: 46291918
      - Manghi Scheck, Santiago - DNI: 95054445
      - Rivera Mamani, Victor Leoncio - DNI: 44258557
      - Torres Moran, Maria Celeste - DNI: 44005719
#>

[CmdletBinding(DefaultParameterSetName = 'Monitorear')]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Ruta del directorio a monitorear.")]
    [Alias("d")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_)) {
            throw "El directorio '$_' no existe."
        }
        if (-not (Test-Path -LiteralPath $_ -PathType Container)) {
            throw "La ruta '$_' no corresponde a un directorio válido."
        }
        $true
    })]
    [string]$directorio,

    [Parameter(Mandatory = $true, ParameterSetName = 'Monitorear', HelpMessage = "Ruta del directorio donde se guardarán los backups y el log.")]
    [Alias("s")]
    [ValidateNotNullOrEmpty()]
    [string]$salida,

    [Parameter(Mandatory = $true, ParameterSetName = 'Detener', HelpMessage = "Indica que se debe detener el demonio previamente iniciado.")]
    [Alias("k")]
    [switch]$kill,

    # Parámetro de uso interno para la ejecución del proceso en segundo plano
    [Parameter(Mandatory = $false, DontShow = $true)]
    [switch]$ModoDemonio
)

# -----------------------------------------------------------------------------
# Funciones auxiliares
# -----------------------------------------------------------------------------

function Mostrar-MensajeError {
    param([string]$Mensaje)
    [Console]::ForegroundColor = [ConsoleColor]::Red
    [Console]::Error.WriteLine("Error: $Mensaje")
    [Console]::ResetColor()
    exit 1
}

function Obtener-RutaArchivoPid {
    param([string]$RutaDir)
    # Genera una ruta única para el archivo PID basada en el hash MD5 de la ruta absoluta normalizada
    $rutaNormalizada = [System.IO.Path]::GetFullPath($RutaDir).TrimEnd('\', '/').ToLowerInvariant()
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($rutaNormalizada)
    $hash = ($md5.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
    
    # Se utiliza /tmp en Linux/macOS o la carpeta temporal del sistema en Windows
    $tempDir = [System.IO.Path]::GetTempPath()
    return (Join-Path $tempDir "demonio_$hash.pid")
}

function Test-DemonioEnEjecucion {
    param([string]$RutaPidFile)

    if (-not (Test-Path -LiteralPath $RutaPidFile -PathType Leaf)) {
        return $false
    }

    try {
        $pidTexto = (Get-Content -LiteralPath $RutaPidFile -Raw -ErrorAction Stop).Trim()
        if ($pidTexto -match '^\d+$') {
            $p = Get-Process -Id ([int]$pidTexto) -ErrorAction SilentlyContinue
            if ($p -and -not $p.HasExited) {
                return $true
            }
        }
    }
    catch {}

    # Si el archivo existía pero el proceso ya finalizó, se elimina el archivo huérfano
    Remove-Item -LiteralPath $RutaPidFile -Force -ErrorAction SilentlyContinue
    return $false
}

function Registrar-EventoLog {
    param(
        [string]$Mensaje,
        [string]$DirSalida
    )
    try {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $logPath = Join-Path $DirSalida "duplicados.log"
        $linea = "$timestamp - $Mensaje"
        Add-Content -LiteralPath $logPath -Value $linea -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Si no se puede escribir el log, no detener el demonio
    }
}

function Procesar-ArchivoCandidato {
    param(
        [string]$RutaArchivo,
        [string]$DirMonitoreado,
        [string]$DirSalida
    )

    if (-not (Test-Path -LiteralPath $RutaArchivo -PathType Leaf)) {
        return
    }

    # Esperar hasta que el archivo termine de escribirse y pueda abrirse para lectura
    $archivoItem = $null
    for ($intento = 0; $intento -lt 10; $intento++) {
        try {
            $archivoItem = Get-Item -LiteralPath $RutaArchivo -Force -ErrorAction Stop
            $fs = [System.IO.File]::Open($RutaArchivo, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $fs.Close()
            break
        }
        catch {
            Start-Sleep -Milliseconds 300
        }
    }

    if (-not $archivoItem) { return }

    $nombreArchivo = $archivoItem.Name
    $tamanoArchivo = $archivoItem.Length

    # Buscar duplicados en el directorio monitoreado (mismo nombre y tamaño, distinto path)
    $duplicados = [System.Collections.Generic.List[string]]::new()
    $duplicados.Add($archivoItem.FullName)

    $otros = Get-ChildItem -LiteralPath $DirMonitoreado -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -ne $archivoItem.FullName -and
            $_.Name -eq $nombreArchivo -and
            $_.Length -eq $tamanoArchivo
        }

    foreach ($otro in $otros) {
        $duplicados.Add($otro.FullName)
    }

    # Si hay 2 o más archivos con el mismo nombre y tamaño, es un duplicado
    if ($duplicados.Count -gt 1) {
        $timestampBackup = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $nombreZip = "$timestampBackup.zip"
        $rutaZip = Join-Path $DirSalida $nombreZip

        while (Test-Path -LiteralPath $rutaZip) {
            Start-Sleep -Seconds 1
            $timestampBackup = (Get-Date).ToString("yyyyMMdd-HHmmss")
            $nombreZip = "$timestampBackup.zip"
            $rutaZip = Join-Path $DirSalida $nombreZip
        }

        $exitoZip = $false
        try {
            Compress-Archive -LiteralPath $duplicados.ToArray() -DestinationPath $rutaZip -Force -ErrorAction Stop
            $exitoZip = $true
        }
        catch {
            # Si falla Compress-Archive, intentar eliminar el archivo zip parcial si quedó creado
            if (Test-Path -LiteralPath $rutaZip) {
                Remove-Item -LiteralPath $rutaZip -Force -ErrorAction SilentlyContinue
            }
        }

        if ($exitoZip) {
            $listaDuplicadosStr = ($duplicados | ForEach-Object { "$_" }) -join ", "
            Registrar-EventoLog "Duplicado detectado: '$nombreArchivo' ($tamanoArchivo bytes). Archivos: $listaDuplicadosStr. Backup: $rutaZip" $DirSalida
        }
        else {
            Registrar-EventoLog "No se pudo generar el backup del duplicado '$nombreArchivo'" $DirSalida
        }
    }
}

function Iniciar-BucleDemonio {
    param(
        [string]$DirMonitoreado,
        [string]$DirSalida,
        [string]$RutaPidFile
    )

    # Registrar el PID actual en el archivo de control
    Set-Content -LiteralPath $RutaPidFile -Value "$PID" -Force -Encoding ASCII

    Registrar-EventoLog "Demonio iniciado sobre '$DirMonitoreado'" $DirSalida

    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = $DirMonitoreado
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size
    $watcher.EnableRaisingEvents = $true

    try {
        while ($true) {
            # Esperar eventos con un timeout de 1000 ms para poder responder a la eliminación del PID file o señales de corte
            $cambio = $watcher.WaitForChanged([System.IO.WatcherChangeTypes]::Created -bor [System.IO.WatcherChangeTypes]::Renamed, 1000)

            if (-not (Test-Path -LiteralPath $RutaPidFile)) {
                # Si el archivo PID fue eliminado por una orden externa, finalizamos el demonio
                break
            }

            if ($cambio.TimedOut) {
                continue
            }

            if ($cambio.Name) {
                $rutaCompleta = Join-Path $DirMonitoreado $cambio.Name
                Procesar-ArchivoCandidato -RutaArchivo $rutaCompleta -DirMonitoreado $DirMonitoreado -DirSalida $DirSalida
            }
        }
    }
    finally {
        Registrar-EventoLog "Demonio finalizado sobre '$DirMonitoreado'" $DirSalida
        if ($watcher) {
            $watcher.EnableRaisingEvents = $false
            $watcher.Dispose()
        }
        if (Test-Path -LiteralPath $RutaPidFile) {
            Remove-Item -LiteralPath $RutaPidFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# -----------------------------------------------------------------------------
# Flujo Principal
# -----------------------------------------------------------------------------

try {
    $directorioAbsoluto = (Resolve-Path -LiteralPath $directorio -ErrorAction Stop).ProviderPath
}
catch {
    Mostrar-MensajeError "No se pudo resolver la ruta del directorio a monitorear: '$directorio'."
}

$archivoPid = Obtener-RutaArchivoPid -RutaDir $directorioAbsoluto

# --- Caso 1: Detener demonio (-kill) ---
if ($kill) {
    if (-not (Test-DemonioEnEjecucion -RutaPidFile $archivoPid)) {
        Mostrar-MensajeError "No hay ningún demonio en ejecución para el directorio '$directorioAbsoluto'."
    }

    try {
        $pidDemonio = [int]((Get-Content -LiteralPath $archivoPid -Raw -ErrorAction Stop).Trim())
        Stop-Process -Id $pidDemonio -Force -ErrorAction SilentlyContinue
    }
    catch {
        Mostrar-MensajeError "No se pudo detener el proceso del demonio (PID $pidDemonio)."
    }

    # Esperar a que el proceso termine
    for ($i = 0; $i -lt 10; $i++) {
        $proc = Get-Process -Id $pidDemonio -ErrorAction SilentlyContinue
        if (-not $proc -or $proc.HasExited) { break }
        Start-Sleep -Milliseconds 500
    }

    if (Test-Path -LiteralPath $archivoPid) {
        Remove-Item -LiteralPath $archivoPid -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Demonio detenido para el directorio '$directorioAbsoluto'."
    exit 0
}

# --- Caso 2: Proceso en segundo plano (ModoDemonio) ---
if ($ModoDemonio) {
    $salidaAbsoluta = [System.IO.Path]::GetFullPath($salida)
    Iniciar-BucleDemonio -DirMonitoreado $directorioAbsoluto -DirSalida $salidaAbsoluta -RutaPidFile $archivoPid
    exit 0
}

# --- Caso 3: Lanzar demonio en segundo plano (Invocación por el usuario) ---
if ([string]::IsNullOrWhiteSpace($salida)) {
    Mostrar-MensajeError "Debe indicar el directorio de salida con -salida."
}

# Crear o validar el directorio de salida
if (-not (Test-Path -LiteralPath $salida)) {
    try {
        $nuevoDir = New-Item -ItemType Directory -Path $salida -Force -ErrorAction Stop
        $salidaAbsoluta = $nuevoDir.FullName
    }
    catch {
        Mostrar-MensajeError "No se pudo crear el directorio de salida '$salida'. Verifique los permisos."
    }
}
else {
    if (-not (Test-Path -LiteralPath $salida -PathType Container)) {
        Mostrar-MensajeError "La ruta de salida '$salida' existe pero no es un directorio."
    }
    $salidaAbsoluta = (Resolve-Path -LiteralPath $salida -ErrorAction Stop).ProviderPath
}

# Validar permisos de escritura en la carpeta de salida
$archivoTest = Join-Path $salidaAbsoluta (".permiso_test_" + [System.Guid]::NewGuid().ToString())
try {
    Set-Content -LiteralPath $archivoTest -Value "test" -Force -ErrorAction Stop
    Remove-Item -LiteralPath $archivoTest -Force -ErrorAction SilentlyContinue
}
catch {
    Mostrar-MensajeError "No se tienen permisos de escritura en el directorio de salida '$salidaAbsoluta'."
}

# Validar que el directorio de salida no esté dentro del directorio monitoreado ni sea el mismo
$dirMonitoreadoNorm = $directorioAbsoluto.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
$dirSalidaNorm = $salidaAbsoluta.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

if ($dirSalidaNorm.StartsWith($dirMonitoreadoNorm, [System.StringComparison]::OrdinalIgnoreCase) -or
    $salidaAbsoluta.Equals($directorioAbsoluto, [System.StringComparison]::OrdinalIgnoreCase)) {
    Mostrar-MensajeError "El directorio de salida no puede estar dentro del directorio monitoreado."
}

# Validar si ya existe un demonio activo para este directorio
if (Test-DemonioEnEjecucion -RutaPidFile $archivoPid) {
    Mostrar-MensajeError "Ya existe un demonio en ejecución para el directorio '$directorioAbsoluto'."
}

# Determinar ejecutable y ruta absoluta del script actual
$scriptActual = $PSCommandPath
if (-not $scriptActual) {
    $scriptActual = $MyInvocation.MyCommand.Path
}
if (-not $scriptActual) {
    $scriptActual = $MyInvocation.MyCommand.Definition
}
$scriptActualAbsoluto = (Resolve-Path -LiteralPath $scriptActual -ErrorAction Stop).ProviderPath
$workingDir = Split-Path -Path $scriptActualAbsoluto -Parent

$ejecutablePs = (Get-Process -Id $PID).Path
if (-not $ejecutablePs) {
    $ejecutablePs = "powershell.exe"
}

$cmdLine = "`"$ejecutablePs`" -NonInteractive -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptActualAbsoluto`" -directorio `"$directorioAbsoluto`" -salida `"$salidaAbsoluta`" -ModoDemonio"

try {
    $procesoId = $null
    try {
        $resultadoWmi = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine } -ErrorAction Stop
        if ($resultadoWmi.ReturnValue -eq 0 -and $resultadoWmi.ProcessId) {
            $procesoId = [int]$resultadoWmi.ProcessId
        }
    }
    catch {
        # Si WMI no está disponible, se utiliza Start-Process
    }

    if (-not $procesoId) {
        $argumentos = "-NonInteractive -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptActualAbsoluto`" -directorio `"$directorioAbsoluto`" -salida `"$salidaAbsoluta`" -ModoDemonio"
        $proc = Start-Process -FilePath $ejecutablePs -ArgumentList $argumentos -WorkingDirectory $workingDir -WindowStyle Hidden -PassThru -ErrorAction Stop
        $procesoId = $proc.Id
    }

    # Escribir el PID para registrar el estado
    Set-Content -LiteralPath $archivoPid -Value "$procesoId" -Force -Encoding ASCII

    Start-Sleep -Milliseconds 800

    $procVerif = Get-Process -Id $procesoId -ErrorAction SilentlyContinue
    if (-not $procVerif -or $procVerif.HasExited) {
        if (Test-Path -LiteralPath $archivoPid) {
            Remove-Item -LiteralPath $archivoPid -Force -ErrorAction SilentlyContinue
        }
        Mostrar-MensajeError "No se pudo iniciar el demonio en segundo plano."
    }

    Write-Host "Demonio iniciado para el directorio '$directorioAbsoluto' (PID $procesoId)."
    exit 0
}
catch {
    if (Test-Path -LiteralPath $archivoPid) {
        Remove-Item -LiteralPath $archivoPid -Force -ErrorAction SilentlyContinue
    }
    Mostrar-MensajeError "Ocurrió un fallo al intentar iniciar el demonio: $($_.Exception.Message)"
}
