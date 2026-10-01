#!/bin/bash
# ==============================================================
#  Virtualizacion de Hardware - APL 1 - 2026 Q2
#  Ejercicio 5 - Consulta de Star Wars (SWAPI)
#
#  Integrantes del grupo:
#    - Almada, Keila Mariel - DNI: 46291918
#    - Manghi Scheck, Santiago - DNI: 95054445
#    - Rivera Mamani, Victor Leoncio - DNI: 44258557
#    - Torres Moran, Maria Celeste - DNI: 44005719
# ==============================================================

DIR_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVO_CACHE="$DIR_SCRIPT/archivo_cache.json"
TMP_JSON=""

limpiar_temporales() {
    [[ -n "$TMP_JSON" && -f "$TMP_JSON" ]] && rm -f "$TMP_JSON"
}
trap limpiar_temporales EXIT INT TERM

mostrar_ayuda() {
    cat << EOF
Uso:
  $(basename "$0") -p <ids_personajes> [-f <ids_peliculas>]
  $(basename "$0") -f <ids_peliculas> [-p <ids_personajes>]
  $(basename "$0") -c | --clear
  $(basename "$0") -h | --help

Descripcion:
  Consulta informacion de personajes y peliculas de Star Wars utilizando la
  API swapi.tech. Almacena en cache local (archivo_cache.json) los resultados
  para optimizar consultas sucesivas.

Parametros:
  -p, --people <id,id,...>  Id o ids de los personajes a buscar (separados por coma).
  -f, --film <id,id,...>    Id o ids de las peliculas a buscar (separados por coma).
  -c, --clear               Elimina el archivo de cache local.
  -h, --help                Muestra esta ayuda.

Ejemplos:
  $(basename "$0") -p "1,2" -f "1,2"
  $(basename "$0") --people 1 --film 1
  $(basename "$0") -p 1,2
  $(basename "$0") -c
EOF
}

error_usuario() {
    echo "Error: $1" >&2
    exit 1
}

# Parsear ayuda de inmediato si se solicita
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        mostrar_ayuda
        exit 0
    fi
done

# Verificacion de dependencias requeridas
if ! command -v curl &>/dev/null; then
    error_usuario "Se requiere la herramienta 'curl' para realizar consultas HTTP."
fi

if ! command -v jq &>/dev/null; then
    error_usuario "Se requiere la herramienta 'jq' para procesar los datos JSON. Puede instalarla con: sudo apt install jq"
fi

# Inicializar cache si no existe o esta vacio
if [[ ! -f "$ARCHIVO_CACHE" || ! -s "$ARCHIVO_CACHE" ]]; then
    echo "{}" > "$ARCHIVO_CACHE" 2>/dev/null || true
fi

consultar_cache() {
    local clave="$1"
    if [[ -f "$ARCHIVO_CACHE" ]] && jq -e --arg k "$clave" '.[$k] // empty' "$ARCHIVO_CACHE" &>/dev/null; then
        jq -r --arg k "$clave" '.[$k]' "$ARCHIVO_CACHE"
        return 0
    fi
    return 1
}

guardar_cache() {
    local clave="$1"
    local json_datos="$2"
    TMP_JSON=$(mktemp /tmp/swapi_cache_XXXXXX.json 2>/dev/null || mktemp "${TMPDIR:-/tmp}/swapi_cache_XXXXXX.json") || return 1
    if ! jq empty "$ARCHIVO_CACHE" 2>/dev/null; then
        echo "{}" > "$ARCHIVO_CACHE"
    fi
    if jq --arg k "$clave" --argjson d "$json_datos" '. + {($k): $d}' "$ARCHIVO_CACHE" > "$TMP_JSON" 2>/dev/null; then
        mv "$TMP_JSON" "$ARCHIVO_CACHE"
        TMP_JSON=""
    else
        rm -f "$TMP_JSON"
        TMP_JSON=""
    fi
}

consultar_api() {
    local tipo="$1"   # "people" o "films"
    local id="$2"
    local clave="${tipo}_${id}"
    local cached
    if cached=$(consultar_cache "$clave"); then
        echo "$cached"
        return 0
    fi

    local url="https://www.swapi.tech/api/$tipo/$id"
    local resp http_code body
    resp=$(curl -s -w "\n%{http_code}" --max-time 15 "$url" 2>/dev/null)
    local exit_curl=$?

    if [[ $exit_curl -ne 0 ]]; then
        echo "Error: No se pudo conectar a la API de Star Wars ($url)." >&2
        return 1
    fi

    http_code=$(echo "$resp" | tail -n1)
    body=$(echo "$resp" | sed '$d')

    if [[ "$http_code" -eq 404 ]]; then
        echo "Error: No se encontro $tipo con ID '$id' (404 Not Found)." >&2
        return 1
    elif [[ "$http_code" -ne 200 ]]; then
        echo "Error: La API respondio con codigo de estado HTTP $http_code para $tipo con ID '$id'." >&2
        return 1
    fi

    local resultado
    resultado=$(echo "$body" | jq -e '.result' 2>/dev/null)
    if [[ $? -ne 0 || -z "$resultado" || "$resultado" == "null" ]]; then
        echo "Error: La respuesta de la API no contiene un resultado valido para $tipo con ID '$id'." >&2
        return 1
    fi

    guardar_cache "$clave" "$resultado"
    echo "$resultado"
    return 0
}

# --------------------------------------------------------------
# Parseo de parametros (cualquier orden)
# --------------------------------------------------------------
PEOPLE_RAW=""
FILM_RAW=""
CLEAR_FLAG=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            mostrar_ayuda
            exit 0
            ;;
        -p|--people)
            [[ $# -ge 2 ]] || error_usuario "El parametro '$1' requiere una lista de IDs."
            PEOPLE_RAW="$2"
            shift 2
            ;;
        -f|--film)
            [[ $# -ge 2 ]] || error_usuario "El parametro '$1' requiere una lista de IDs."
            FILM_RAW="$2"
            shift 2
            ;;
        -c|--clear)
            CLEAR_FLAG=1
            shift
            ;;
        *)
            error_usuario "Opcion no reconocida: '$1'. Utilice -h o --help para ver la ayuda."
            ;;
    esac
done

if [[ $CLEAR_FLAG -eq 1 ]]; then
    if [[ -n "$PEOPLE_RAW" || -n "$FILM_RAW" ]]; then
        error_usuario "El parametro -c / --clear no puede combinarse con -p o -f."
    fi
    if [[ -f "$ARCHIVO_CACHE" ]]; then
        rm -f "$ARCHIVO_CACHE"
        echo "El archivo de cache local ha sido eliminado."
    else
        echo "No existe archivo de cache local para eliminar."
    fi
    exit 0
fi

if [[ -z "$PEOPLE_RAW" && -z "$FILM_RAW" ]]; then
    error_usuario "Debe indicar al menos un parametro de busqueda: -p/--people o -f/--film."
fi

# --------------------------------------------------------------
# Procesamiento de busquedas
# --------------------------------------------------------------
declare -a PERSONAJES_JSON=()
declare -a PELICULAS_JSON=()
HUBO_ERROR=0

if [[ -n "$PEOPLE_RAW" ]]; then
    IFS=',' read -ra IDS_PEOPLE <<< "$PEOPLE_RAW"
    for item in "${IDS_PEOPLE[@]}"; do
        # Trim de espacios
        id=$(echo "$item" | xargs)
        [[ -z "$id" ]] && continue

        if [[ ! "$id" =~ ^[0-9]+$ ]] || [[ "$id" -le 0 ]]; then
            echo "Error: El ID de personaje '$id' no es valido. Debe ser un numero entero positivo." >&2
            HUBO_ERROR=1
            continue
        fi

        datos=$(consultar_api "people" "$id")
        if [[ $? -eq 0 && -n "$datos" ]]; then
            PERSONAJES_JSON+=("$datos")
        else
            HUBO_ERROR=1
        fi
    done
fi

if [[ -n "$FILM_RAW" ]]; then
    IFS=',' read -ra IDS_FILM <<< "$FILM_RAW"
    for item in "${IDS_FILM[@]}"; do
        id=$(echo "$item" | xargs)
        [[ -z "$id" ]] && continue

        if [[ ! "$id" =~ ^[0-9]+$ ]] || [[ "$id" -le 0 ]]; then
            echo "Error: El ID de pelicula '$id' no es valido. Debe ser un numero entero positivo." >&2
            HUBO_ERROR=1
            continue
        fi

        datos=$(consultar_api "films" "$id")
        if [[ $? -eq 0 && -n "$datos" ]]; then
            PELICULAS_JSON+=("$datos")
        else
            HUBO_ERROR=1
        fi
    done
fi

# --------------------------------------------------------------
# Salida por pantalla en el formato exacto de la consigna
# --------------------------------------------------------------
if [[ ${#PERSONAJES_JSON[@]} -gt 0 ]]; then
    echo "Personajes:"
    idx=0
    for pj in "${PERSONAJES_JSON[@]}"; do
        [[ $idx -gt 0 ]] && echo ""
        uid=$(echo "$pj" | jq -r '.uid // empty')
        name=$(echo "$pj" | jq -r '.properties.name // empty')
        gender=$(echo "$pj" | jq -r '.properties.gender // empty')
        height=$(echo "$pj" | jq -r '.properties.height // empty')
        mass=$(echo "$pj" | jq -r '.properties.mass // empty')
        birth_year=$(echo "$pj" | jq -r '.properties.birth_year // empty')

        echo "Id: $uid"
        echo "Name: $name"
        echo "Gender: $gender"
        echo "Height: $height"
        echo "Mass: $mass"
        echo "Birth Year: $birth_year"
        ((idx++))
    done
fi

if [[ ${#PELICULAS_JSON[@]} -gt 0 ]]; then
    [[ ${#PERSONAJES_JSON[@]} -gt 0 ]] && echo ""
    echo "Peliculas:"
    idx=0
    for pel in "${PELICULAS_JSON[@]}"; do
        [[ $idx -gt 0 ]] && echo ""
        title=$(echo "$pel" | jq -r '.properties.title // empty')
        episode_id=$(echo "$pel" | jq -r '.properties.episode_id // empty')
        release_date=$(echo "$pel" | jq -r '.properties.release_date // empty')
        opening_crawl=$(echo "$pel" | jq -r '.properties.opening_crawl // empty')

        echo "Title: $title"
        echo "Episode id: $episode_id"
        echo "Release date: $release_date"
        echo "Opening crawl: $opening_crawl"
        ((idx++))
    done
fi

if [[ ${#PERSONAJES_JSON[@]} -eq 0 && ${#PELICULAS_JSON[@]} -eq 0 && $HUBO_ERROR -eq 1 ]]; then
    exit 1
fi

exit 0
