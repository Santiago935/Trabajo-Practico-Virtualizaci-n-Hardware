#!/bin/bash
#########################################################################
# Virtualizacion de Hardware - APL 1 - 2026 Q2 - Ejercicio 3
# Integrantes:
#   - MANGHI SCHECK, SANTIAGO - 95054445
#   - TORRES MORAN, MARIA CELESTE - 44005719
#   - RIVERA MAMANI, VICTOR LEONCIO - 44258557
#   - ALMADA, KEILA MARIEL - 46291918
#########################################################################

# Archivos temporales (se crean en /tmp y se borran siempre al salir)
ARCHIVO_LS=""
ARCHIVO_ERRORES=""

limpiar_temporales() {
    rm -f -- "$ARCHIVO_LS" "$ARCHIVO_ERRORES"
}
# EXIT cubre la salida normal y por error; INT/TERM cubren Ctrl+C y kill
trap limpiar_temporales EXIT
trap 'echo; echo "Ejecucion cancelada por el usuario." >&2; exit 130' INT TERM

mostrar_ayuda() {
    cat << AYUDA
USO:
    $(basename "$0") -d <directorio>
    $(basename "$0") --directorio <directorio>
    $(basename "$0") -h | --help

DESCRIPCION:
    Busca archivos duplicados dentro de un directorio y todos sus
    subdirectorios. Un archivo se considera duplicado cuando existe otro
    con el MISMO NOMBRE y el MISMO TAMANO, sin importar su contenido.

    Por cada archivo duplicado se muestra su nombre y, debajo, las rutas
    de los directorios donde fue encontrado.

PARAMETROS:
    -d, --directorio   Ruta del directorio a analizar (obligatorio).
                       Acepta rutas relativas, absolutas o con espacios
                       (en ese caso, escribirla entre comillas).
    -h, --help         Muestra esta ayuda.

EJEMPLOS:
    $(basename "$0") -d ./lote_prueba
    $(basename "$0") --directorio "/home/user/mis documentos"
AYUDA
}

error() {
    echo "Error: $1" >&2
    echo "Para ver como usar el script ejecute: $(basename "$0") --help" >&2
    exit 1
}

procesar_parametros() {
    DIRECTORIO=""
    if [[ $# -eq 0 ]]; then
        error "No se indico ningun parametro."
    fi
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--directorio)
                if [[ -z "${2:-}" || "$2" == -* && ! -d "$2" ]]; then
                    error "Falta indicar la ruta del directorio despues de '$1'."
                fi
                if [[ -n "$DIRECTORIO" ]]; then
                    error "El parametro de directorio se indico mas de una vez."
                fi
                DIRECTORIO="$2"
                shift 2
                ;;
            -h|--help)
                mostrar_ayuda
                exit 0
                ;;
            *)
                error "El parametro '$1' no es valido."
                ;;
        esac
    done
    if [[ -z "$DIRECTORIO" ]]; then
        error "El parametro -d / --directorio es obligatorio."
    fi
}

validar_directorio() {
    if [[ ! -e "$DIRECTORIO" ]]; then
        error "La ruta '$DIRECTORIO' no existe."
    fi
    if [[ ! -d "$DIRECTORIO" ]]; then
        error "La ruta '$DIRECTORIO' no es un directorio."
    fi
    if [[ ! -r "$DIRECTORIO" || ! -x "$DIRECTORIO" ]]; then
        error "No tiene permisos para leer el directorio '$DIRECTORIO'."
    fi
    # Pasamos a ruta absoluta para que la salida muestre rutas completas
    DIRECTORIO=$(realpath -- "$DIRECTORIO") \
        || error "No se pudo obtener la ruta completa de '$DIRECTORIO'."
}

listar_archivos() {
    ARCHIVO_LS=$(mktemp /tmp/ejercicio3_ls.XXXXXX) \
        || error "No se pudo crear un archivo temporal en /tmp."
    ARCHIVO_ERRORES=$(mktemp /tmp/ejercicio3_err.XXXXXX) \
        || error "No se pudo crear un archivo temporal en /tmp."

    # -l  formato largo (trae el tamano)      -R  recursivo
    # -A  incluye ocultos (sin . y ..)         -n  UID/GID numericos
    # --time-style=long-iso  fecha con formato fijo (2 campos)
    # --quoting-style=literal  nombres sin comillas ni escapes
    LC_ALL=C ls -lRAn --time-style=long-iso --quoting-style=literal \
        -- "$DIRECTORIO" > "$ARCHIVO_LS" 2> "$ARCHIVO_ERRORES"
    local codigo=$?

    if [[ $codigo -eq 2 ]]; then
        error "No se pudo leer el directorio '$DIRECTORIO'."
    elif [[ $codigo -eq 1 || -s "$ARCHIVO_ERRORES" ]]; then
        echo "Aviso: algunos subdirectorios no se pudieron leer (falta de permisos) y no fueron analizados." >&2
    fi
}

buscar_duplicados() {
    awk '
    # Linea de encabezado de directorio: "/ruta/absoluta:"
    substr($0, 1, 1) == "/" && substr($0, length($0), 1) == ":" {
        dir_actual = substr($0, 1, length($0) - 1)
        next
    }
    # Solo archivos regulares (la linea empieza con "-")
    substr($0, 1, 1) == "-" {
        tamanio = $5
        nombre = $0
        # Se quitan los 7 primeros campos (permisos, links, uid, gid,
        # tamano, fecha, hora) y queda el nombre completo, aunque tenga espacios
        sub(/^[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ /, "", nombre)

        clave = nombre SUBSEP tamanio          # array asociativo nombre+tamano
        if (!(clave in cantidad)) {
            orden[++total] = clave             # recordamos el orden de aparicion
            nombres[clave] = nombre
        }
        cantidad[clave]++
        rutas[clave] = rutas[clave] dir_actual "\n"
    }
    END {
        encontrados = 0
        for (i = 1; i <= total; i++) {
            clave = orden[i]
            if (cantidad[clave] > 1) {
                if (encontrados > 0) print ""
                print nombres[clave]
                printf "%s", rutas[clave]
                encontrados++
            }
        }
        if (encontrados == 0)
            print "No se encontraron archivos duplicados."
    }
    ' "$ARCHIVO_LS" || error "Ocurrio un problema al procesar la lista de archivos."
}

main() {
    procesar_parametros "$@"
    validar_directorio
    listar_archivos
    buscar_duplicados
}

main "$@"
