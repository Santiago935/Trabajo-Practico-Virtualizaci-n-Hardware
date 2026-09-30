<#
.SYNOPSIS
    Consulta información de personajes y películas de Star Wars (SWAPI).

.DESCRIPTION
    Consulta información básica de personajes y películas utilizando la API pública swapi.tech.
    Almacena los resultados en un archivo de caché local (archivo_cache.json) para optimizar
    consultas repetidas.
    Los parámetros -people y -film aceptan arrays nativos de PowerShell (separados por coma).

.PARAMETER people
    Id o ids de los personajes a buscar (tipo array, ej: -people 1,2).

.PARAMETER film
    Id o ids de las películas a buscar (tipo array, ej: -film 1,2).

.PARAMETER clear
    Elimina el archivo de caché local si existe.

.EXAMPLE
    Get-Help .\ejercicio5.ps1 -Detailed

.EXAMPLE
    .\ejercicio5.ps1 -people 1,2 -film 1,2

.EXAMPLE
    .\ejercicio5.ps1 -people 1

.EXAMPLE
    .\ejercicio5.ps1 -film 1

.EXAMPLE
    .\ejercicio5.ps1 -clear

.NOTES
    Virtualización de Hardware - APL 1 - 2026 Q2 - Ejercicio 5
    Integrantes del grupo:
      - Almada, Keila Mariel - DNI: 46291918
      - Manghi Scheck, Santiago - DNI: 95054445
      - Rivera Mamani, Victor Leoncio - DNI: 44258557
      - Torres Moran, Maria Celeste - DNI: 44005719
#>

[CmdletBinding(DefaultParameterSetName = 'Consultar')]
param(
    [Parameter(Mandatory = $false, ParameterSetName = 'Consultar', HelpMessage = 'Id o ids de los personajes a buscar.')]
    [Alias('p')]
    [string[]]$people,

    [Parameter(Mandatory = $false, ParameterSetName = 'Consultar', HelpMessage = 'Id o ids de las películas a buscar.')]
    [Alias('f')]
    [string[]]$film,

    [Parameter(Mandatory = $true, ParameterSetName = 'LimpiarCache', HelpMessage = 'Elimina el archivo de caché local.')]
    [Alias('c')]
    [switch]$clear
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Ruta del archivo de caché local en el mismo directorio del script
$scriptDir = Split-Path -Parent $PSCommandPath
if (-not $scriptDir) { $scriptDir = "." }
$archivoCache = Join-Path $scriptDir "archivo_cache.json"

# =============================================================================
# FUNCIONES DE CACHÉ
# =============================================================================

function Obtener-Cache {
    if (Test-Path -LiteralPath $archivoCache -PathType Leaf) {
        try {
            $contenido = Get-Content -LiteralPath $archivoCache -Raw -Encoding UTF8 -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($contenido)) {
                $obj = $contenido | ConvertFrom-Json -ErrorAction Stop
                $tabla = [ordered]@{}
                foreach ($prop in $obj.PSObject.Properties) {
                    $tabla[$prop.Name] = $prop.Value
                }
                return $tabla
            }
        }
        catch {
            # Si el archivo está corrupto, se reinicializará
        }
    }
    return [ordered]@{}
}

function Guardar-Cache {
    param([hashtable]$TablaCache)
    try {
        $json = $TablaCache | ConvertTo-Json -Depth 10
        Set-Content -LiteralPath $archivoCache -Value $json -Encoding UTF8 -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "No se pudo actualizar el archivo de caché local."
    }
}

# =============================================================================
# FUNCIONES DE FORMATO DE SALIDA
# =============================================================================

function Mostrar-Personaje {
    param($item)
    $prop = $item.properties
    $uid = if ($item.uid) { $item.uid } elseif ($prop.id) { $prop.id } else { "" }
    Write-Output "Id: $uid"
    Write-Output "Name: $($prop.name)"
    Write-Output "Gender: $($prop.gender)"
    Write-Output "Height: $($prop.height)"
    Write-Output "Mass: $($prop.mass)"
    Write-Output "Birth Year: $($prop.birth_year)"
}

function Mostrar-Pelicula {
    param($item)
    $prop = $item.properties
    Write-Output "Title: $($prop.title)"
    Write-Output "Episode id: $($prop.episode_id)"
    Write-Output "Release date: $($prop.release_date)"
    Write-Output "Opening crawl: $($prop.opening_crawl)"
}

# =============================================================================
# CONSULTA A LA API / CACHÉ
# =============================================================================

function Consultar-Elemento {
    param(
        [string]$Tipo,       # 'people' o 'films'
        [string]$Id,
        [ref]$TablaCache
    )

    $claveCache = "${Tipo}_${Id}"
    if ($TablaCache.Value.Contains($claveCache)) {
        return $TablaCache.Value[$claveCache]
    }

    $url = "https://www.swapi.tech/api/$Tipo/$Id"
    try {
        $resp = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 15 -ErrorAction Stop
        if ($resp -and $resp.result) {
            $resultado = $resp.result
            $TablaCache.Value[$claveCache] = $resultado
            Guardar-Cache -TablaCache $TablaCache.Value
            return $resultado
        }
        else {
            [Console]::Error.WriteLine("Error: La API no devolvió un resultado válido para $Tipo con ID '$Id'.")
            return $null
        }
    }
    catch {
        $mensajeHttp = $_.Exception.Message
        if ($mensajeHttp -match "404") {
            [Console]::Error.WriteLine("Error: No se encontró $Tipo con ID '$Id' (404 Not Found).")
        }
        else {
            [Console]::Error.WriteLine("Error al consultar la API para $Tipo con ID '$Id': $mensajeHttp")
        }
        return $null
    }
}

# =============================================================================
# FLUJO PRINCIPAL
# =============================================================================

# Caso 1: Limpieza de caché
if ($PSCmdlet.ParameterSetName -eq 'LimpiarCache') {
    if (Test-Path -LiteralPath $archivoCache) {
        Remove-Item -LiteralPath $archivoCache -Force -ErrorAction Stop
        Write-Output "El archivo de caché local ha sido eliminado."
    }
    else {
        Write-Output "No existe archivo de caché local para eliminar."
    }
    exit 0
}

# Caso 2: Validación de parámetros obligatorios en modo consulta
if (-not $people -and -not $film) {
    [Console]::Error.WriteLine("Error: Debe ingresar al menos un parámetro de búsqueda (-people o -film).")
    exit 1
}

$cacheRef = [ref](Obtener-Cache)
$resultadosPersonajes = [System.Collections.Generic.List[object]]::new()
$resultadosPeliculas   = [System.Collections.Generic.List[object]]::new()
$huboError = $false

# Procesar personajes (se itera directamente el array, SIN .split)
if ($people) {
    foreach ($item in $people) {
        $idStr = "$item".Trim()
        if ([string]::IsNullOrEmpty($idStr)) { continue }

        if ($idStr -notmatch '^\d+$' -or [int64]$idStr -le 0) {
            [Console]::Error.WriteLine("Error: El ID de personaje '$idStr' no es válido. Debe ser un número entero positivo.")
            $huboError = $true
            continue
        }

        $res = Consultar-Elemento -Tipo 'people' -Id $idStr -TablaCache $cacheRef
        if ($res) {
            $resultadosPersonajes.Add($res)
        }
        else {
            $huboError = $true
        }
    }
}

# Procesar películas (se itera directamente el array, SIN .split)
if ($film) {
    foreach ($item in $film) {
        $idStr = "$item".Trim()
        if ([string]::IsNullOrEmpty($idStr)) { continue }

        if ($idStr -notmatch '^\d+$' -or [int64]$idStr -le 0) {
            [Console]::Error.WriteLine("Error: El ID de película '$idStr' no es válido. Debe ser un número entero positivo.")
            $huboError = $true
            continue
        }

        $res = Consultar-Elemento -Tipo 'films' -Id $idStr -TablaCache $cacheRef
        if ($res) {
            $resultadosPeliculas.Add($res)
        }
        else {
            $huboError = $true
        }
    }
}

# Mostrar resultados respetando el formato exigido
if ($resultadosPersonajes.Count -gt 0) {
    Write-Output "Personajes:"
    for ($i = 0; $i -lt $resultadosPersonajes.Count; $i++) {
        if ($i -gt 0) { Write-Output "" }
        Mostrar-Personaje $resultadosPersonajes[$i]
    }
}

if ($resultadosPeliculas.Count -gt 0) {
    if ($resultadosPersonajes.Count -gt 0) { Write-Output "" }
    Write-Output "Películas:"
    for ($i = 0; $i -lt $resultadosPeliculas.Count; $i++) {
        if ($i -gt 0) { Write-Output "" }
        Mostrar-Pelicula $resultadosPeliculas[$i]
    }
}

if ($resultadosPersonajes.Count -eq 0 -and $resultadosPeliculas.Count -eq 0 -and $huboError) {
    exit 1
}

exit 0
