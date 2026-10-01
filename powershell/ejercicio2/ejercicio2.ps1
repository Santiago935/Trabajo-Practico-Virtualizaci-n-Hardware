<#
.SYNOPSIS
    Realiza el producto escalar o la trasposicion de una matriz numerica.

.DESCRIPTION
    Operaciones disponibles (mutuamente excluyentes):
      1. Producto escalar: Multiplica cada elemento de la matriz por un numero entero.
      2. Trasposicion: Intercambia filas por columnas (dimension M x N -> N x M).

    El resultado se guarda en un nuevo archivo denominado 'salida.<nombreArchivoEntrada>'
    ubicado exactamente en el mismo directorio donde se encuentra el archivo de la matriz original.

.PARAMETER matriz
    Ruta del archivo de texto plano que contiene la matriz a procesar.
    Se aceptan rutas relativas, absolutas y con espacios.

.PARAMETER producto
    Valor entero que se utilizara para realizar el producto escalar.
    No se puede usar conjuntamente con el parametro -trasponer.

.PARAMETER trasponer
    Indica que se debe realizar la operacion de trasposicion sobre la matriz.
    No se puede usar conjuntamente con el parametro -producto.

.PARAMETER separador
    Caracter unico utilizado como separador de columnas.
    No puede ser un digito numerico ni el simbolo menos ('-').

.EXAMPLE
    Get-Help .\ejercicio2.ps1 -Detailed
    Muestra la documentacion y modo de uso detallado del script.

.EXAMPLE
    .\ejercicio2.ps1 -matriz ".\pruebas\matriz_consigna.txt" -producto 2 -separador "|"
    Multiplica todos los elementos de la matriz por 2 y genera salida.matriz_consigna.txt.

.EXAMPLE
    .\ejercicio2.ps1 -matriz ".\pruebas\matriz_consigna.txt" -trasponer -separador "|"
    Traspone la matriz intercambiando filas por columnas y genera salida.matriz_consigna.txt.

.EXAMPLE
    .\ejercicio2.ps1 -matriz "C:\datos\matriz con espacios.txt" -trasponer -separador ";"
    Demuestra el uso de rutas con espacios y separador punto y coma.

.NOTES
# INTEGRANTES DEL GRUPO:
# - Almada, Keila Mariel - DNI: 46291918
# - Manghi Scheck, Santiago - DNI: 95054445
# - Rivera Mamani, Victor Leoncio - DNI: 44258557
# - Torres Moran, Maria Celeste - DNI: 44005719
#>

[CmdletBinding(DefaultParameterSetName = 'Producto')]
param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Producto', HelpMessage = 'Ruta del archivo de la matriz')]
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'Trasponer', HelpMessage = 'Ruta del archivo de la matriz')]
    [Alias('m')]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
            throw "El archivo de matriz especificado no existe o no es un archivo regular: '$_'"
        }
        $true
    })]
    [string]$matriz,

    [Parameter(Mandatory = $true, ParameterSetName = 'Producto', HelpMessage = 'Valor entero para el producto escalar')]
    [Alias('p')]
    [int]$producto,

    [Parameter(Mandatory = $true, ParameterSetName = 'Trasponer', HelpMessage = 'Indica que se debe trasponer la matriz')]
    [Alias('t')]
    [switch]$trasponer,

    [Parameter(Mandatory = $true, ParameterSetName = 'Producto', HelpMessage = 'Caracter separador de columnas')]
    [Parameter(Mandatory = $true, ParameterSetName = 'Trasponer', HelpMessage = 'Caracter separador de columnas')]
    [Alias('s')]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        if ($_.Length -ne 1) {
            throw "El separador debe ser exactamente un unico caracter."
        }
        if ($_ -eq '-') {
            throw "El caracter '-' no puede utilizarse como separador (se confunde con numeros negativos)."
        }
        if ($_ -match '^[0-9]$') {
            throw "Un digito numerico no puede utilizarse como separador de columnas."
        }
        $true
    })]
    [string]$separador
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# FUNCIONES MODULARES 
# =============================================================================

function Notificar-Error {
    param([string]$Mensaje)
    [Console]::Error.WriteLine("Error: $Mensaje")
    exit 1
}

function Obtener-DirectorioTemporal {
    <#
    .SYNOPSIS
        Garantiza la obtencion o creacion de un directorio temporal, priorizando /tmp.
    #>
    $dirTmp = "/tmp"
    if (-not (Test-Path -LiteralPath $dirTmp)) {
        try {
            New-Item -ItemType Directory -Path $dirTmp -Force -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            $dirTmp = [System.IO.Path]::GetTempPath()
        }
    }
    return $dirTmp
}

function Validar-Y-CargarMatriz {
    <#
    .SYNOPSIS
        Carga la matriz validando estructura, formato y valores numericos.
    #>
    param(
        [string]$RutaArchivo,
        [string]$Delimitador
    )

    $item = Get-Item -LiteralPath $RutaArchivo
    if ($item.Length -eq 0) {
        throw "El archivo de la matriz esta vacio."
    }

    $lineas = @(Get-Content -LiteralPath $RutaArchivo)
    if ($lineas.Count -eq 0) {
        throw "El archivo de la matriz no contiene lineas procesables."
    }

    $filasMatriz = [System.Collections.Generic.List[object]]::new()
    $cantColumnasEsperada = -1
    $numFila = 0

    foreach ($linea in $lineas) {
        $numFila++
        $lineaTrimeada = $linea.Trim()

        if ([string]::IsNullOrEmpty($lineaTrimeada)) {
            throw "El archivo contiene una fila vacia en la linea $numFila. La matriz es invalida."
        }

        if ($linea.StartsWith($Delimitador)) {
            throw "La fila $numFila comienza con el separador, indicando una columna vacia inicial."
        }

        if ($linea.EndsWith($Delimitador)) {
            throw "La fila $numFila termina con el separador, indicando una columna vacia final."
        }

        # Separar por el caracter delimitador
        $elementos = $linea.Split([char]$Delimitador)
        $numCols = $elementos.Count

        if ($numCols -eq 0) {
            throw "No se encontraron columnas en la fila $numFila."
        }

        if ($cantColumnasEsperada -eq -1) {
            $cantColumnasEsperada = $numCols
        }
        elseif ($numCols -ne $cantColumnasEsperada) {
            throw "La matriz es invalida: la fila $numFila tiene $numCols columna(s) y se esperaban $cantColumnasEsperada."
        }

        $filaValores = [System.Collections.Generic.List[double]]::new()

        for ($c = 0; $c -lt $numCols; $c++) {
            $valorTexto = $elementos[$c].Trim()

            if ([string]::IsNullOrEmpty($valorTexto)) {
                throw "La matriz contiene un valor vacio en la fila $numFila, columna $($c + 1)."
            }

            # Validacion de formato numerico (enteros y decimales con punto, positivos o negativos)
            if ($valorTexto -notmatch '^-?([0-9]+(\.[0-9]+)?|\.[0-9]+)$') {
                throw "La matriz contiene un valor no numerico '$($elementos[$c])' en la fila $numFila, columna $($c + 1)."
            }

            $numDouble = [double]::Parse($valorTexto, [System.Globalization.CultureInfo]::InvariantCulture)
            $filaValores.Add($numDouble)
        }

        $filasMatriz.Add($filaValores)
    }

    if ($filasMatriz.Count -eq 0) {
        throw "El archivo no contiene filas procesables."
    }

    return [PSCustomObject]@{
        Filas = $filasMatriz.Count
        Columnas = $cantColumnasEsperada
        Datos = $filasMatriz
    }
}

function Formatear-Numero {
    <#
    .SYNOPSIS
        Formatea un valor double preservando punto decimal y evitando ceros sobrantes.
    #>
    param([double]$Valor)

    if ([math]::Floor($Valor) -eq $Valor) {
        return ([int64]$Valor).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    else {
        return $Valor.ToString("0.###############", [System.Globalization.CultureInfo]::InvariantCulture)
    }
}

function Calcular-ProductoEscalar {
    <#
    .SYNOPSIS
        Multiplica cada elemento de la matriz por el entero escalar.
    #>
    param(
        [PSCustomObject]$MatrizObj,
        [int]$Escalar,
        [string]$Delimitador
    )

    $lineasResultado = [System.Collections.Generic.List[string]]::new()

    for ($f = 0; $f -lt $MatrizObj.Filas; $f++) {
        $elementosFila = [System.Collections.Generic.List[string]]::new()

        for ($c = 0; $c -lt $MatrizObj.Columnas; $c++) {
            $valOriginal = $MatrizObj.Datos[$f][$c]
            $valCalculado = $valOriginal * $Escalar
            $elementosFila.Add((Formatear-Numero -Valor $valCalculado))
        }

        $lineasResultado.Add(($elementosFila -join $Delimitador))
    }

    return $lineasResultado
}

function Calcular-Trasposicion {
    <#
    .SYNOPSIS
        Traspone la matriz intercambiando filas por columnas.
    #>
    param(
        [PSCustomObject]$MatrizObj,
        [string]$Delimitador
    )

    $lineasResultado = [System.Collections.Generic.List[string]]::new()

    for ($c = 0; $c -lt $MatrizObj.Columnas; $c++) {
        $elementosFila = [System.Collections.Generic.List[string]]::new()

        for ($f = 0; $f -lt $MatrizObj.Filas; $f++) {
            $valOriginal = $MatrizObj.Datos[$f][$c]
            $elementosFila.Add((Formatear-Numero -Valor $valOriginal))
        }

        $lineasResultado.Add(($elementosFila -join $Delimitador))
    }

    return $lineasResultado
}

# =============================================================================
# FLUJO PRINCIPAL
# =============================================================================

$archivoTemporal = $null

try {
    # Resolver la ruta absoluta de la matriz para soportar relativas, absolutas y con espacios
    $rutaMatriz = (Resolve-Path -LiteralPath $matriz).ProviderPath
    $directorioPadre = [System.IO.Path]::GetDirectoryName($rutaMatriz)
    $nombreArchivo = [System.IO.Path]::GetFileName($rutaMatriz)
    $rutaSalida = Join-Path -Path $directorioPadre -ChildPath "salida.$nombreArchivo"

    # Preparar archivo temporal en /tmp (para no dejar archivos basura)
    $dirTemporal = Obtener-DirectorioTemporal
    $nombreTemp = "ej2_" + [System.Guid]::NewGuid().ToString("N") + ".tmp"
    $archivoTemporal = Join-Path -Path $dirTemporal -ChildPath $nombreTemp

    # Cargar y validar la matriz
    $matrizCargada = Validar-Y-CargarMatriz -RutaArchivo $rutaMatriz -Delimitador $separador

    # Procesar operacion solicitada
    $resultadoLineas = $null
    if ($PSCmdlet.ParameterSetName -eq 'Producto') {
        $resultadoLineas = Calcular-ProductoEscalar -MatrizObj $matrizCargada -Escalar $producto -Delimitador $separador
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Trasponer') {
        $resultadoLineas = Calcular-Trasposicion -MatrizObj $matrizCargada -Delimitador $separador
    }

    # Escribir el resultado en el archivo temporal
    [System.IO.File]::WriteAllLines(
        $archivoTemporal,
        $resultadoLineas,
        [System.Text.UTF8Encoding]::new($false)
    )

    # Mover el archivo temporal al destino final
    Move-Item -LiteralPath $archivoTemporal -Destination $rutaSalida -Force
    $archivoTemporal = $null

    Write-Host "Operacion realizada correctamente." -ForegroundColor Green
    Write-Host "Archivo de salida generado: $rutaSalida"
}
catch {
    Notificar-Error -Mensaje $_.Exception.Message
}
finally {
    # Limpieza garantizada del archivo temporal tanto en exito como en fallo
    if ($null -ne $archivoTemporal -and (Test-Path -LiteralPath $archivoTemporal)) {
        Remove-Item -LiteralPath $archivoTemporal -Force -ErrorAction SilentlyContinue
    }
}
