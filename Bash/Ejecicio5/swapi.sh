#!/bin/bash

# EJERCICIO 5
# - Manghi Scheck Santiago

#FORMATO:
#$ ./swapi.sh --people “1,2” --film “1,2"

#-----------------------------<VARIABLES>-----------------------------
archivo_cache="archivo_cache.json"
declare -a nombres=()
declare -i id
clear_cache=false

#-----------------------------<FUNCIONES>-----------------------------

ayuda(){
cat <<'EOF'
NOMBRE
    swapi.sh - Buscador de información de personajes o peliculas de Star Wars

SINOPSIS
    swapi.sh [-p personaje(s) | -f pelicula(s)] [-clear] [-h]

DESCRIPCIÓN
    Consulta información de personajes o películas de Star Wars utilizando la API y almacena
    los resultados en un archivo cache.json para evitar consultas repetidas. El archivo
    puede eliminarse mediante el comando -clear.

PARÁMETROS OBLIGATORIOS
    -p, --people
        id(s) de los personajes a buscar. Múltiples nombres se separan por comas.
        Ejemplo: "1,2,3"
    -f, --film
        ID(s) de las películas a buscar. Múltiples IDs se separan por comas.
        Ejemplo: "1,2,3"


PARÁMETROS OPCIONALES
    -c, --clear
        Elimina el archivo cache.json si existe.
    -h, --help
        Muestra esta ayuda y sale.

EJEMPLOS
    ./swapi.sh -p 1 -f 1
    ./swapi.sh --people 2,3 --film 1,2
    ./swapi.sh -clear
EOF
}

# Consulta API
consultar_api() {
    local tipo="$1"
    local id="$2"
    local resultado
    local url="https://www.swapi.tech/api/$tipo/$id"
    local resultadoAPI
    resultadoAPI=$(curl -s -f "$url")
    local curl_exit_code=$?
    
    if [[ $curl_exit_code -ne 0 ]] || [[ -z "$resultadoAPI" ]]; then
        echo "Error: No se pudo conectar a la API" >&2
        return 1
    fi
    
    echo "$resultadoAPI" | jq '.result'
}

# Guarda en caché
guardar_cache() {
    local nombre="$1"
    local datos="$2"
    local tmp
    tmp=$(mktemp)
    if ! jq empty "$archivo_cache" &>/dev/null; then
        echo "{}" > "$archivo_cache"
    fi

    jq --arg nombre "$nombre" --argjson datos "$datos" \
'. + {($nombre): $datos}' "$archivo_cache" > "$tmp" && mv "$tmp" "$archivo_cache"
}

#consultar_cache
consultar_cache() {
    local nombre="$1"
    local resultado
    resultado=$(jq -r --arg n "$nombre" '.[$n] // empty' "$archivo_cache" 2>/dev/null)
    [[ -n "$resultado" ]] && echo "$resultado" && return 0
    return 1
}




#-----------------------------<PROGRAMA>-----------------------------

# Crear archivo de caché si no existe
[[ ! -f "$archivo_cache" ]] && echo "{}" > "$archivo_cache"

# Parsear parámetros
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--people)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: -p requiere un valor." >&2; exit 1
            fi
            IFS=',' read -r -a nombres <<< "$2"
            shift 2 ;;
        -f|--film)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: -f requiere un valor." >&2; exit 1
            fi
            IFS=',' read -r -a ids <<< "$2"
            shift 2 ;;
        -c|--clear)
            clear_cache=true
            shift ;;
        -h|--help)
            ayuda; exit 0 ;;
        *)
            echo "Error: Opción desconocida '$1'. Use -h para ayuda." >&2
            exit 1 ;;
    esac
done

# Validaciones
if [[ "$clear_cache" == true ]]; then
    if [[ ${#nombres[@]} -gt 0 ]] || [[ ${#ids[@]} -gt 0 ]]; then
        echo "Error: -clear no puede combinarse con -p o -f." >&2
        exit 1
    fi
    if [[ -f "$archivo_cache" ]]; then
        rm "$archivo_cache"
        echo "Caché eliminado: $(realpath "$archivo_cache" 2>/dev/null || echo "$archivo_cache")"
    else
        echo "No existe archivo de caché."
    fi
    exit 0
fi

if [[ ${#nombres[@]} -eq 0 ]] && [[ ${#ids[@]} -eq 0 ]]; then
    echo "Error: Debe ingresar al menos un id de personaje con -p o un id de pelicula con -f" >&2
    exit 1
fi

#main

for nombre in "${nombres[@]}"; do
    nombre=$(echo "$nombre" | xargs)

    if ! [[ "$nombre" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: El id del personaje '$nombre' solo puede contener numeros." >&2
        continue
    fi

  # Extraigo los campos y los imprimo

if resultado=$(consultar_cache "people_$nombre"); then
    echo "Datos desde caché:"
else
    echo "Consultando API para '$nombre'..."
    if resultado=$(consultar_api "people" "$nombre"); then
        guardar_cache "people_$nombre" "$resultado"
    else
        continue
    fi
fi

id=$(echo "$resultado" | jq -r '.uid')
nombre=$(echo "$resultado" | jq -r '.properties.name')
gender=$(echo "$resultado" | jq -r '.properties.gender')
height=$(echo "$resultado" | jq -r '.properties.height')
mass=$(echo "$resultado" | jq -r '.properties.mass')
birth_year=$(echo "$resultado" | jq -r '.properties.birth_year')

echo "  Nombre: $nombre"
echo "  ID: $id"
echo "  Gender: $gender"
echo "  Height: $height"
echo "  Mass: $mass"
echo "  Birth Year: $birth_year"

done


  # CASO PELICULA

for id in "${ids[@]}"; do
    id=$(echo "$id" | xargs)

    if ! [[ "$id" =~ ^[0-9]+$ ]]; then
        echo "Error: El ID '$id' no es un número válido." >&2
        continue
    fi

    # CASO PELICULA
    if resultado=$(consultar_cache "film_$id"); then
        echo "Datos desde caché:"
    else
        echo "Consultando API para '$id'..."
        if resultado=$(consultar_api "films" "$id"); then
            guardar_cache "film_$id" "$resultado"
        else
            continue
        fi
    fi

    id=$(echo "$resultado" | jq -r '.uid')
    titulo=$(echo "$resultado" | jq -r '.properties.title')
    director=$(echo "$resultado" | jq -r '.properties.director')
    productor=$(echo "$resultado" | jq -r '.properties.producer')
    estreno=$(echo "$resultado" | jq -r '.properties.release_date')

    echo "  ID: $id"
    echo "  Título: $titulo"
    echo "  Director: $director"
    echo "  Productor: $productor"
    echo "  Fecha de estreno: $estreno"
done




