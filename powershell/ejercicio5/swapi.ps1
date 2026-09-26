#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Buscador de informacion de personajes y peliculas de Star Wars

.DESCRIPTION
    Consulta informacion de personajes y peliculas de Star Wars utilizando la API de Star Wars.
    Almacena los resultados en un archivo cache del cual puede ser eliminado.
    La busqueda se puede realizar por id de personaje o pelicula

.PARAMETER people
        Id de los personajes a buscar. Multiples IDs se separan por comas.

.PARAMETER film
        Id de las películas a buscar. Multiples IDs se separan por comas.

.PARAMETER clear
    Elimina el archivo de cache si existe.

.PARAMETER help
    Muestra esta ayuda y sale.

.EXAMPLE
     ./swapi.ps1 -people 1,2 -films 1,2

#>

# EJERCICIO 5
# - Santiago Manghi Scheck


Param(
    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)] [string[]]$people,
    [Parameter(Mandatory=$false)] [string[]]$film,
    [Parameter(Mandatory=$false)] [switch]$clear,
    [Parameter(Mandatory=$false)] [switch]$help
)

# -----------------------------<FUNCIONES>-----------------------------


function guardarCache {
    # Cargar cache existente o crear nuevo
        param($cacheHashtable)
        $cacheHashtable | ConvertTo-Json -Depth 10 | Set-Content $archivoCache -Encoding UTF8
    
}


function consultarCache {
    if (Test-Path $archivoCache) {
        try {
            $json = Get-Content $archivoCache -Raw
            if ([string]::IsNullOrWhiteSpace($json)) { return @{} }
            $objeto = $json | ConvertFrom-Json
            $tabla = @{}
            foreach ($prop in $objeto.PSObject.Properties) {
                $tabla[$prop.Name] = $prop.Value
            }
            return $tabla
        } catch { }
    }
    return @{}
}

function mostrarPersonaje {
    param($pj)
    Write-Host "Character info:" -ForegroundColor Cyan
    Write-Host "Id: $($pj.id)"
    Write-Host "Name: $($pj.name)"
    Write-Host "Gender: $($pj.gender)"
    Write-Host "Height: $($pj.height)"
    Write-Host "Mass: $($pj.mass)"
    Write-Host "Birth Year: $($pj.birth_year)"
    Write-Host "-------------------------"
}

function mostrarPelicula {
    param($pel)
    Write-Host "Film info:" -ForegroundColor Cyan
    Write-Host "Id: $($pel.id)"
    Write-Host "Titulo: $($pel.title)"
    Write-Host "Director: $($pel.director)"
    Write-Host "Productor: $($pel.producer)"
    Write-Host "Fecha de estreno: $($pel.release_date)"
    Write-Host "-------------------------"
}

function procesarBusqueda {
    param([string]$claveCache, [string]$url, [string]$tipo)

    if ($cache.ContainsKey($claveCache)) {
        Write-Host "Obteniendo datos desde CACHE para: $claveCache" -ForegroundColor DarkGray
        $datos = $cache[$claveCache]
    } else {
        try {
            $datos = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
            # Guardamos en caché
            $cache[$claveCache] = $datos
            guardarCache $cache
        } catch {
            Write-Host "Error: No se encontraron resultados o hubo un fallo en la API para la consulta '$claveCache'." -ForegroundColor Red
            return $false
        }
    }

    # La API devuelve una lista en 'results'
    if ($datos.result) { $datos = $datos.result }
    if ($datos.results) {
        $datos = $datos.results | ForEach-Object {
            if ($_.properties) {
                $_.properties | Add-Member -NotePropertyName id -NotePropertyValue $_.uid -PassThru -Force
            } else {
                $_
            }
        }
    } elseif ($datos.properties) {
        $datos = $datos.properties | Add-Member -NotePropertyName id -NotePropertyValue $datos.uid -PassThru -Force
    }

    foreach ($item in @($datos)) {
        if ($tipo -eq "personaje") {
            mostrarPersonaje $item
        } else {
            mostrarPelicula $item
        }
    }

    return $true
}

# -----------------------------<PROGRAMA PRINCIPAL>-----------------------------

if ($help) {
    Get-Help $MyInvocation.MyCommand.Path -Full
    exit 0
}

$archivoCache = "archivo_cache.json"

# Eliminar el archivo de cache si se especifica el parámetro -clear
if ($clear) {
    if ($people -or $film) {
        Write-Host "Error: No se puede utilizar -clear junto con los parámetros -people o -films." -ForegroundColor Red
        exit 1
    }
    if (Test-Path $archivoCache) {
        Remove-Item $archivoCache
        Write-Host "Cache limpiado exitosamente." -ForegroundColor Green
    } else {
        Write-Host "No hay archivo de cache para limpiar." -ForegroundColor Yellow
    }
    exit 0
}

# Crear archivo de caché si no existe
if (-not (Test-Path $archivoCache)) {
    "{}" | Set-Content $archivoCache -Encoding UTF8
}

# Validaciones
if (-not $people -and -not $film) {
    Write-Host "Error: Debe ingresar al menos un parámetro de búsqueda (-people o -film)." -ForegroundColor Red
    exit 1
}

$cache = consultarCache
$elementosProcesados = 0

try {
    if ($people) {
        $ids = ($people -join ',') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($i in $ids) {
            $url = "https://www.swapi.tech/api/people/$i"
            if (procesarBusqueda -claveCache "people $i" -url $url -tipo "personaje") {
                $elementosProcesados++
            }
        }
    }

       if ($film) {
        $ids = ($film -join ',') -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        foreach ($i in $ids) {
            $url = "https://www.swapi.tech/api/films/$i"
            if (procesarBusqueda -claveCache "film $i" -url $url -tipo "pelicula") {
                $elementosProcesados++
            }
        }
    }
} catch {
    Write-Host "Error inesperado: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Determinar código de salida basado en si se procesó al menos un personaje exitosamente
if ($elementosProcesados -gt 0) {
    exit 0
} else {
    exit 1
}