<#
.SYNOPSIS
    Valida jugadas de loteria de varias agencias e informa las que tuvieron 5, 4 o 3 aciertos.

.DESCRIPTION
    Procesa todos los archivos CSV de un directorio (uno por agencia). Cada archivo contiene,
    por linea, el numero de jugada y los 5 numeros jugados (0 a 99). Compara cada jugada contra
    los numeros ganadores (leidos de "ganadores.csv", ubicado dentro del mismo directorio
    indicado con -directorio) e informa en formato JSON las jugadas con 5, 4 o 3 aciertos, ya
    sea por pantalla o en un archivo de salida.

.PARAMETER directorio
    Ruta del directorio que contiene los archivos CSV de jugadas a procesar (relativa o absoluta,
    puede contener espacios).

.PARAMETER archivo
    Ruta completa del archivo JSON de salida (incluye el nombre del archivo). No se puede usar
    junto con -pantalla.

.PARAMETER pantalla
    Muestra el resultado por pantalla en lugar de generar un archivo. No se puede usar junto con
    -archivo.

.EXAMPLE
    ./ejercicio1.ps1 -directorio ./lote_prueba -pantalla

.EXAMPLE
    ./ejercicio1.ps1 -directorio "C:\jugadas semana" -archivo ./resultado.json

.NOTES
    Virtualizacion de Hardware - APL 1 - 2026 Q2
    Integrantes del grupo:
       - Almada, Keila Mariel - DNI: 46291918
       - Manghi Scheck, Santiago - DNI: 95054445
       - Rivera Mamani, Victor Leoncio - DNI: 44258557
       - Torres Moran, Maria Celeste - DNI: 44005719
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Ruta del directorio con los archivos CSV a procesar.")]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_ -PathType Container)) {
            throw "El directorio '$_' no existe o no es un directorio."
        }
        return $true
    })]
    [string]$directorio,

    [Parameter(Mandatory = $true, ParameterSetName = 'Archivo',
        HelpMessage = "Ruta completa del archivo JSON de salida.")]
    [ValidateScript({
        if (Test-Path -LiteralPath $_ -PathType Container) {
            throw "'$_' es un directorio; indique la ruta completa del archivo JSON."
        }
        if (Test-Path -LiteralPath $_) {
            throw "El archivo '$_' ya existe. Indique otro nombre para no sobrescribirlo."
        }
        $carpeta = Split-Path -Path $_ -Parent
        if ([string]::IsNullOrEmpty($carpeta)) { $carpeta = "." }
        if (-not (Test-Path -LiteralPath $carpeta -PathType Container)) {
            throw "El directorio de salida '$carpeta' no existe."
        }
        return $true
    })]
    [string]$archivo,

    [Parameter(Mandatory = $true, ParameterSetName = 'Pantalla',
        HelpMessage = "Muestra el resultado por pantalla en lugar de generar un archivo.")]
    [switch]$pantalla
)

function Mostrar-ErrorYSalir {
    param([string]$Mensaje)
    Write-Error "Error: $Mensaje"
    exit 1
}

$archivoGanadores = Join-Path $directorio "ganadores.csv"
$tempFile = $null

try {
    # ---------- Numeros ganadores ----------
    if (-not (Test-Path -LiteralPath $archivoGanadores -PathType Leaf)) {
        Mostrar-ErrorYSalir "No se encontro el archivo de numeros ganadores '$archivoGanadores'."
    }

    $lineaGanadores = Get-Content -LiteralPath $archivoGanadores |
        Where-Object { $_.Trim() -ne "" } | Select-Object -First 1

    if (-not $lineaGanadores -or $lineaGanadores.Trim() -notmatch '^(\d{1,2},){4}\d{1,2}$') {
        Mostrar-ErrorYSalir "El archivo de ganadores debe tener 5 numeros del 0 al 99 separados por coma."
    }
    $numerosGanadores = $lineaGanadores.Trim().Split(",") | ForEach-Object { [int]$_ }

    # ---------- Archivos CSV a procesar (excluye el de ganadores si esta en el mismo dir) ----------
    $rutaGanadores = (Resolve-Path -LiteralPath $archivoGanadores).Path
    $archivosCsv = Get-ChildItem -LiteralPath $directorio -Filter "*.csv" -File |
        Where-Object { $_.FullName -ne $rutaGanadores }

    if (-not $archivosCsv -or $archivosCsv.Count -eq 0) {
        Mostrar-ErrorYSalir "No se encontraron archivos CSV en '$directorio'."
    }

    # ---------- Procesamiento ----------
    $cinco  = [System.Collections.Generic.List[object]]::new()
    $cuatro = [System.Collections.Generic.List[object]]::new()
    $tres   = [System.Collections.Generic.List[object]]::new()

    foreach ($csv in $archivosCsv) {
        $agencia = [System.IO.Path]::GetFileNameWithoutExtension($csv.Name)
        $numLinea = 0

        foreach ($linea in (Get-Content -LiteralPath $csv.FullName)) {
            $numLinea++
            $limpia = ($linea -replace '[\s]', '')
            if ([string]::IsNullOrWhiteSpace($limpia)) { continue }

            $campos = $limpia.Split(",")
            $valida = ($campos.Count -eq 6)
            if ($valida) {
                foreach ($c in $campos) {
                    if ($c -notmatch '^\d+$') { $valida = $false; break }
                }
            }
            if ($valida) {
                for ($i = 1; $i -le 5; $i++) {
                    if ([int]$campos[$i] -gt 99) { $valida = $false; break }
                }
            }
            if (-not $valida) {
                Write-Warning "Linea invalida ignorada ($($csv.Name), linea $numLinea)"
                continue
            }

            $numerosJugada = $campos[1..5] | ForEach-Object { [int]$_ } | Select-Object -Unique
            $aciertos = 0
            foreach ($n in $numerosJugada) {
                if ($numerosGanadores -contains $n) { $aciertos++ }
            }

            if ($aciertos -ge 3) {
                $item = [ordered]@{ agencia = $agencia; jugada = $campos[0] }
                switch ($aciertos) {
                    5 { $cinco.Add($item)  | Out-Null }
                    4 { $cuatro.Add($item) | Out-Null }
                    3 { $tres.Add($item)   | Out-Null }
                }
            }
        }
    }

    $resultado = [ordered]@{
        "5_aciertos" = $cinco.ToArray()
        "4_aciertos" = $cuatro.ToArray()
        "3_aciertos" = $tres.ToArray()
    }
    $json = $resultado | ConvertTo-Json -Depth 5

    # ---------- Salida ----------
    if ($PSCmdlet.ParameterSetName -eq 'Pantalla') {
        Write-Output $json
    }
    else {
        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) ("ejercicio1_" + [guid]::NewGuid().ToString() + ".json")
        Set-Content -LiteralPath $tempFile -Value $json -Encoding UTF8
        Copy-Item -LiteralPath $tempFile -Destination $archivo -ErrorAction Stop
        Write-Output "Resultado guardado en: $archivo"
    }
}
catch {
    Mostrar-ErrorYSalir $_.Exception.Message
}
finally {
    if ($tempFile -and (Test-Path -LiteralPath $tempFile)) {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}