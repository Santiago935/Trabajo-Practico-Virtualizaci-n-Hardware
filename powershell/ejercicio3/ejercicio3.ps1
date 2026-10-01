<#
.SYNOPSIS
    Busca archivos duplicados dentro de un directorio y sus subdirectorios.

.DESCRIPTION
    Recorre el directorio indicado (incluyendo todos sus subdirectorios) y
    considera que un archivo esta duplicado cuando existe otro con el MISMO
    NOMBRE y el MISMO TAMANO, sin importar su contenido.
    Por cada archivo duplicado muestra su nombre y, debajo, las rutas de los
    directorios donde fue encontrado.

.PARAMETER directorio
    Ruta del directorio a analizar (obligatorio). Acepta rutas relativas,
    absolutas o con espacios (entre comillas).

.EXAMPLE
    ./ejercicio3.ps1 -directorio ./lote_prueba

.EXAMPLE
    ./ejercicio3.ps1 -directorio "/home/user/mis documentos"

.NOTES
    Virtualizacion de Hardware - APL 1 - 2026 Q2 - Ejercicio 3
    Integrantes:
   - MANGHI SCHECK, SANTIAGO - 95054445
   - TORRES MORAN, MARIA CELESTE - 44005719
   - RIVERA MAMANI, VICTOR LEONCIO - 44258557
   - ALMADA, KEILA MARIEL - 46291918
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_)) {
            throw "La ruta '$_' no existe."
        }
        if (-not (Test-Path -LiteralPath $_ -PathType Container)) {
            throw "La ruta '$_' no es un directorio."
        }
        $true
    })]
    [string]$directorio
)

function Get-ArchivosDuplicados {
    param([string]$Ruta)

    # Array asociativo: clave "nombre|tamano" -> lista de directorios.
    # Se usa comparacion Ordinal (distingue mayusculas/minusculas) porque en
    # Linux "Foto.jpg" y "foto.jpg" son archivos distintos.
    $grupos = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::Ordinal)
    $nombres = @{}
    $orden = [System.Collections.Generic.List[string]]::new()

    $erroresLectura = $null
    $archivos = Get-ChildItem -LiteralPath $Ruta -Recurse -File -Force `
                    -ErrorAction SilentlyContinue -ErrorVariable erroresLectura

    if ($erroresLectura) {
        Write-Warning "Algunos subdirectorios no se pudieron leer (falta de permisos) y no fueron analizados."
    }

    foreach ($archivo in $archivos) {
        # "/" no puede formar parte de un nombre de archivo, asi que es un separador seguro
        $clave = "$($archivo.Name)/$($archivo.Length)"
        if (-not $grupos.ContainsKey($clave)) {
            $grupos[$clave] = [System.Collections.Generic.List[string]]::new()
            $nombres[$clave] = $archivo.Name
            $orden.Add($clave)
        }
        $grupos[$clave].Add($archivo.DirectoryName)
    }

    $encontrados = 0
    foreach ($clave in $orden) {
        if ($grupos[$clave].Count -gt 1) {
            if ($encontrados -gt 0) { Write-Output "" }
            Write-Output $nombres[$clave]
            $grupos[$clave] | ForEach-Object { Write-Output $_ }
            $encontrados++
        }
    }

    if ($encontrados -eq 0) {
        Write-Output "No se encontraron archivos duplicados."
    }
}

try {
    $rutaAbsoluta = (Resolve-Path -LiteralPath $directorio -ErrorAction Stop).ProviderPath
    Get-ArchivosDuplicados -Ruta $rutaAbsoluta
}
catch {
    Write-Error "No se pudo completar el analisis del directorio '$directorio'. Detalle: $($_.Exception.Message)"
    exit 1
}
finally {
    # Este script no genera archivos temporales; si en el futuro se agregan,
    # deben eliminarse aqui para no dejar archivos basura.
}
