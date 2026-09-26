#!/usr/bin/env bash
###############################################################################
# INTEGRANTES DEL GRUPO:
# - Almada, Keila Mariel - DNI: 46291918
# - Manghi Scheck, Santiago - DNI: 95054445
# - Rivera Mamani, Victor Leoncio - DNI: 44258557
# - Torres Moran, Maria Celeste - DNI: 44005719
###############################################################################

set -o pipefail

# Variable global para el archivo temporal creado en /tmp
TMP_SALIDA=""

# -----------------------------------------------------------------------------
# Función para limpieza segura de temporales (trap en éxito y error)
# -----------------------------------------------------------------------------
limpiar_temporales() {
    if [[ -n "$TMP_SALIDA" && -f "$TMP_SALIDA" ]]; then
        rm -f "$TMP_SALIDA" 2>/dev/null
    fi
}

# Configuración del trap para garantizar la eliminación de temporales
trap limpiar_temporales EXIT INT TERM HUP

# -----------------------------------------------------------------------------
# Función para mostrar errores al usuario
# -----------------------------------------------------------------------------
error_usuario() {
    echo "Error: $1" >&2
    exit 1
}

# -----------------------------------------------------------------------------
# Función de Ayuda (-h y --help)
# -----------------------------------------------------------------------------
mostrar_ayuda() {
    cat << EOF
===============================================================================
AYUDA - Ejercicio 2: Producto Escalar y Trasposición de Matrices
===============================================================================

DESCRIPCIÓN:
  Este script permite procesar una matriz numérica almacenada en un archivo de
  texto plano. Admite realizar dos operaciones (mutuamente excluyentes):
    1. Producto escalar: Multiplica cada elemento por un número entero.
    2. Trasposición: Intercambia filas por columnas (M x N -> N x M).

  El resultado se almacena en un archivo llamado 'salida.<nombreArchivoEntrada>'
  ubicado exactamente en el mismo directorio donde reside el archivo original.

SINTAXIS:
  $0 -m <ruta_matriz> -s <separador> -p <valor_entero>
  $0 -m <ruta_matriz> -s <separador> -t
  $0 -h | --help

PARÁMETROS (se admiten en cualquier orden):
  -m, --matriz <ruta>     Ruta (relativa, absoluta o con espacios) del archivo de matriz.
  -s, --separador <char>  Carácter único utilizado como separador de columnas.
                          No puede ser un dígito numérico ni el signo '-'.
  -p, --producto <entero> Valor entero para el producto escalar.
                          (No se puede combinar con -t o --trasponer).
  -t, --trasponer         Bandera que indica trasponer la matriz.
                          (No se puede combinar con -p o --producto).
  -h, --help              Muestra esta ayuda y finaliza.

EJEMPLOS:
  $0 -m "./matriz.txt" -s "|" -p 3
  $0 -m "/home/usuario/datos/matriz.txt" -s ";" -t
  $0 --matriz "matriz con espacios.txt" --separador "," --producto -2

===============================================================================
EOF
}

# -----------------------------------------------------------------------------
# Variables de parámetros
# -----------------------------------------------------------------------------
MATRIZ_PARAM=""
SEPARADOR_PARAM=""
PRODUCTO_PARAM=""
TIENE_PRODUCTO=0
TRASPONER_FLAG=0

# -----------------------------------------------------------------------------
# Parseo de los parámetros 
# -----------------------------------------------------------------------------
parsear_parametros() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                mostrar_ayuda
                exit 0
                ;;
            -m|--matriz)
                [[ $# -ge 2 ]] || error_usuario "El parámetro '$1' requiere especificar la ruta del archivo de la matriz."
                MATRIZ_PARAM="$2"
                shift 2
                ;;
            -s|--separador)
                [[ $# -ge 2 ]] || error_usuario "El parámetro '$1' requiere especificar un carácter separador."
                SEPARADOR_PARAM="$2"
                shift 2
                ;;
            -p|--producto)
                [[ $# -ge 2 ]] || error_usuario "El parámetro '$1' requiere especificar un valor entero."
                PRODUCTO_PARAM="$2"
                TIENE_PRODUCTO=1
                shift 2
                ;;
            -t|--trasponer)
                TRASPONER_FLAG=1
                shift
                ;;
            *)
                error_usuario "Parámetro no reconocido: '$1'. Utilice -h o --help para consultar las opciones disponibles."
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Validación de los parámetros
# -----------------------------------------------------------------------------
validar_parametros() {
    # 1. Validar parámetros obligatorios
    [[ -n "$MATRIZ_PARAM" ]] || error_usuario "Falta el parámetro obligatorio del archivo de matriz (-m / --matriz)."
    [[ -n "$SEPARADOR_PARAM" ]] || error_usuario "Falta el parámetro obligatorio del separador (-s / --separador)."

    # 2. Validar que se haya indicado una y solo una operación
    if [[ "$TIENE_PRODUCTO" -eq 1 && "$TRASPONER_FLAG" -eq 1 ]]; then
        error_usuario "No se pueden utilizar simultáneamente el producto escalar (-p/--producto) y la trasposición (-t/--trasponer)."
    fi

    if [[ "$TIENE_PRODUCTO" -eq 0 && "$TRASPONER_FLAG" -eq 0 ]]; then
        error_usuario "Debe indicar una operación obligatoria: producto escalar (-p/--producto) o trasposición (-t/--trasponer)."
    fi

    # 3. Validar separador: exactamente 1 carácter, no dígito ni signo '-'
    if [[ "${#SEPARADOR_PARAM}" -ne 1 ]]; then
        error_usuario "El separador debe ser exactamente un único carácter."
    fi

    if [[ "$SEPARADOR_PARAM" == "-" ]]; then
        error_usuario "El carácter '-' no puede utilizarse como separador de columnas (se confunde con números negativos)."
    fi

    if [[ "$SEPARADOR_PARAM" =~ ^[0-9]$ ]]; then
        error_usuario "Un dígito numérico no puede utilizarse como separador de columnas."
    fi

    # 4. Validar valor del producto escalar (entero con o sin signo)
    if [[ "$TIENE_PRODUCTO" -eq 1 ]]; then
        if [[ ! "$PRODUCTO_PARAM" =~ ^[-+]?[0-9]+$ ]]; then
            error_usuario "El valor del producto escalar debe ser un número entero (positivo, negativo o cero)."
        fi
    fi

    # 5. Validar existencia y estado del archivo de matriz
    if [[ ! -e "$MATRIZ_PARAM" ]]; then
        error_usuario "El archivo de matriz especificado no existe: '$MATRIZ_PARAM'."
    fi

    if [[ -d "$MATRIZ_PARAM" ]]; then
        error_usuario "La ruta indicada corresponde a un directorio y no a un archivo: '$MATRIZ_PARAM'."
    fi

    if [[ ! -f "$MATRIZ_PARAM" ]]; then
        error_usuario "La ruta indicada no corresponde a un archivo regular válido: '$MATRIZ_PARAM'."
    fi

    if [[ ! -r "$MATRIZ_PARAM" ]]; then
        error_usuario "No se tienen permisos de lectura sobre el archivo: '$MATRIZ_PARAM'."
    fi

    if [[ ! -s "$MATRIZ_PARAM" ]]; then
        error_usuario "El archivo de matriz está vacío."
    fi
}

# -----------------------------------------------------------------------------
# Carga y Validación de la matriz desde el archivo
# -----------------------------------------------------------------------------
declare -a MATRIZ_DATOS
CANT_FILAS=0
CANT_COLUMNAS=0

cargar_y_validar_matriz() {
    local num_linea=0
    local linea=""

    while IFS= read -r linea || [[ -n "$linea" ]]; do
        ((num_linea++))

        # Validar filas completamente vacías o solo espacios en blanco
        local linea_trimeada="${linea#"${linea%%[![:space:]]*}"}"
        linea_trimeada="${linea_trimeada%"${linea_trimeada##*[![:space:]]}"}"

        if [[ -z "$linea_trimeada" ]]; then
            error_usuario "El archivo contiene una fila vacía en la línea $num_linea. La matriz es inválida."
        fi

        # Validar separador inicial o final (columna vacía al inicio o al final)
        if [[ "$linea" == "$SEPARADOR_PARAM"* ]]; then
            error_usuario "La fila $num_linea comienza con el separador, indicando una columna vacía inicial."
        fi
        if [[ "$linea" == *"$SEPARADOR_PARAM" ]]; then
            error_usuario "La fila $num_linea termina con el separador, indicando una columna vacía final."
        fi

        # Separar la fila usando el delimitador configurado
        local valores=()
        IFS="$SEPARADOR_PARAM" read -ra valores <<< "$linea"

        if [[ "${#valores[@]}" -eq 0 ]]; then
            error_usuario "No se encontraron columnas en la fila $num_linea."
        fi

        # La primera fila establece el número de columnas esperado
        if [[ "$CANT_COLUMNAS" -eq 0 ]]; then
            CANT_COLUMNAS=${#valores[@]}
        elif [[ "${#valores[@]}" -ne "$CANT_COLUMNAS" ]]; then
            error_usuario "La matriz es inválida: la fila $num_linea tiene ${#valores[@]} columna(s) y se esperaban $CANT_COLUMNAS."
        fi

        # Validar cada elemento numérico y almacenar en el array unidimensional
        local idx_col=0
        for val in "${valores[@]}"; do
            # Trim de posibles espacios alrededor del valor
            local v="${val#"${val%%[![:space:]]*}"}"
            v="${v%"${v##*[![:space:]]}"}"

            # Validar que no sea vacío
            if [[ -z "$v" ]]; then
                error_usuario "La matriz contiene un valor vacío en la fila $num_linea, columna $((idx_col + 1))."
            fi

            # Validar formato numérico (enteros o decimales con punto, positivos o negativos)
            if [[ ! "$v" =~ ^[-+]?([0-9]+(\.[0-9]+)?|\.[0-9]+)$ ]]; then
                error_usuario "La matriz contiene un valor no numérico '$val' en la fila $num_linea, columna $((idx_col + 1))."
            fi

            local pos=$((CANT_FILAS * CANT_COLUMNAS + idx_col))
            MATRIZ_DATOS[$pos]="$v"
            ((idx_col++))
        done

        ((CANT_FILAS++))
    done < "$MATRIZ_PARAM"

    if [[ "$CANT_FILAS" -eq 0 ]]; then
        error_usuario "El archivo no contiene filas procesables."
    fi
}

# -----------------------------------------------------------------------------
# Operación: Producto Escalar
# -----------------------------------------------------------------------------
calcular_producto_escalar() {
    local f c pos val resultado_val
    for ((f = 0; f < CANT_FILAS; f++)); do
        local fila_salida=""
        for ((c = 0; c < CANT_COLUMNAS; c++)); do
            pos=$((f * CANT_COLUMNAS + c))
            val="${MATRIZ_DATOS[$pos]}"

            # Cálculo numérico con awk para máxima precisión con decimales y formato limpio
            resultado_val=$(awk -v a="$val" -v b="$PRODUCTO_PARAM" 'BEGIN {
                res = a * b;
                printf "%.12g", res;
            }')

            if [[ "$c" -eq 0 ]]; then
                fila_salida="$resultado_val"
            else
                fila_salida="${fila_salida}${SEPARADOR_PARAM}${resultado_val}"
            fi
        done
        printf '%s\n' "$fila_salida" >> "$TMP_SALIDA"
    done
}

# -----------------------------------------------------------------------------
# Operación: Trasposición de Matrices 
# -----------------------------------------------------------------------------
calcular_trasposicion() {
    local f c pos val
    # Se itera primero por columnas y luego por filas para intercambiar dimensiones
    for ((c = 0; c < CANT_COLUMNAS; c++)); do
        local fila_salida=""
        for ((f = 0; f < CANT_FILAS; f++)); do
            pos=$((f * CANT_COLUMNAS + c))
            val="${MATRIZ_DATOS[$pos]}"

            if [[ "$f" -eq 0 ]]; then
                fila_salida="$val"
            else
                fila_salida="${fila_salida}${SEPARADOR_PARAM}${val}"
            fi
        done
        printf '%s\n' "$fila_salida" >> "$TMP_SALIDA"
    done
}

# -----------------------------------------------------------------------------
# Publicación del resultado en salida.<nombreArchivoEntrada>
# -----------------------------------------------------------------------------
publicar_resultado() {
    local dir_matriz nombre_matriz ruta_salida

    dir_matriz=$(dirname "$MATRIZ_PARAM")
    nombre_matriz=$(basename "$MATRIZ_PARAM")

    ruta_salida="${dir_matriz}/salida.${nombre_matriz}"

    if mv "$TMP_SALIDA" "$ruta_salida"; then
        echo "Operación realizada correctamente."
        echo "Archivo de salida generado: $ruta_salida"
    else
        error_usuario "No se pudo escribir el archivo de salida en '$ruta_salida'."
    fi
}

# -----------------------------------------------------------------------------
# Flujo Principal
# -----------------------------------------------------------------------------
main() {
    parsear_parametros "$@"
    validar_parametros

    # Creación del archivo de trabajo en el directorio temporal /tmp
    TMP_SALIDA=$(mktemp /tmp/ejercicio2_XXXXXX 2>/dev/null || mktemp "${TMPDIR:-/tmp}/ejercicio2_XXXXXX") || error_usuario "No se pudo crear el archivo temporal en /tmp."

    cargar_y_validar_matriz

    if [[ "$TIENE_PRODUCTO" -eq 1 ]]; then
        calcular_producto_escalar
    else
        calcular_trasposicion
    fi

    publicar_resultado
}

main "$@"
