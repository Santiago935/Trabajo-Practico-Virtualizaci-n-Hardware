#!/bin/bash
#
# ==============================================================
#  Virtualizacion de Hardware - APL 1 - 2026 Q2
#  Ejercicio 1 - Validacion de jugadas de loteria
#
#  Integrantes del grupo:
#    - Almada, Keila Mariel - DNI: 46291918
#    - Manghi Scheck, Santiago - DNI: 95054445
#    - Rivera Mamani, Victor Leoncio - DNI: 44258557
#    - Torres Moran, Maria Celeste - DNI: 44005719
# ==============================================================

# Archivo con los 5 numeros ganadores (CSV, una sola linea).
# Por defecto: "ganadores.csv" junto al script.

ARCHIVO_GANADORES=""
 
TMP_SALIDA=""
 
ayuda() {
    cat << AYUDA
Uso: $(basename "$0") -d <directorio> ( -a <archivo.json> | -p )
 
Procesa las jugadas de loteria de todas las agencias (un CSV por agencia)
y informa en formato JSON las jugadas con 5, 4 y 3 aciertos.
 
Parametros:
  -d, --directorio  Ruta del directorio con los archivos CSV a procesar. (obligatorio)
  -a, --archivo     Ruta completa del archivo JSON de salida.
                    No se puede usar junto con -p / --pantalla.
  -p, --pantalla    Muestra el resultado por pantalla (no genera archivo).
                    No se puede usar junto con -a / --archivo.
  -h, --help        Muestra esta ayuda.
 
Debe indicarse exactamente una forma de salida: -a o -p.
 
Numeros ganadores:
  Se leen del archivo "ganadores.csv" ubicado dentro del directorio
  indicado con -d / --directorio.
 
Ejemplos:
  $(basename "$0") -d ./lote_prueba -p
  $(basename "$0") --directorio "/tmp/mis jugadas" --archivo ./salida.json
AYUDA
}
 
error() {
    echo "Error: $1" >&2
    echo "Use -h o --help para ver la ayuda." >&2
    exit 1
}
 
# Limpieza de temporales: se ejecuta siempre (exito, error o Ctrl+C)
limpiar() {
    [[ -n "$TMP_SALIDA" && -f "$TMP_SALIDA" ]] && rm -f "$TMP_SALIDA"
}
trap limpiar EXIT
trap 'exit 130' INT TERM
 
# ---------- Lectura de parametros (cualquier orden) ----------
OPCIONES=$(getopt -o d:a:ph --long directorio:,archivo:,pantalla,help -n "$(basename "$0")" -- "$@") \
    || { echo "Use -h o --help para ver la ayuda." >&2; exit 1; }
eval set -- "$OPCIONES"
 
DIRECTORIO=""
ARCHIVO=""
PANTALLA=0
 
while true; do
    case "$1" in
        -d|--directorio) DIRECTORIO="$2"; shift 2 ;;
        -a|--archivo)    ARCHIVO="$2"; shift 2 ;;
        -p|--pantalla)   PANTALLA=1; shift ;;
        -h|--help)       ayuda; exit 0 ;;
        --)              shift; break ;;
        *)               error "Parametro inesperado: $1" ;;
    esac
done
 
# ---------- Validaciones ----------
[[ -z "$DIRECTORIO" ]] && error "Falta el parametro obligatorio -d / --directorio."
[[ -n "$ARCHIVO" && $PANTALLA -eq 1 ]] && error "No se pueden usar -a / --archivo y -p / --pantalla a la vez."
[[ -z "$ARCHIVO" && $PANTALLA -eq 0 ]] && error "Debe indicar una salida: -a / --archivo o -p / --pantalla."
 
[[ -d "$DIRECTORIO" ]] || error "El directorio '$DIRECTORIO' no existe o no es un directorio."
[[ -r "$DIRECTORIO" ]] || error "No se tienen permisos para leer el directorio '$DIRECTORIO'."
 
ARCHIVO_GANADORES="$DIRECTORIO/ganadores.csv"
 
if [[ -n "$ARCHIVO" ]]; then
    [[ -d "$ARCHIVO" ]] && error "'$ARCHIVO' es un directorio; indique la ruta completa del archivo JSON."
    [[ -e "$ARCHIVO" ]] && error "El archivo '$ARCHIVO' ya existe. Indique otro nombre para no sobrescribirlo."
    DIR_SALIDA=$(dirname "$ARCHIVO")
    [[ -d "$DIR_SALIDA" ]] || error "El directorio de salida '$DIR_SALIDA' no existe."
    [[ -w "$DIR_SALIDA" ]] || error "No se tienen permisos para escribir en '$DIR_SALIDA'."
fi
 
[[ -f "$ARCHIVO_GANADORES" && -r "$ARCHIVO_GANADORES" ]] \
    || error "No se encontro el archivo de numeros ganadores '$ARCHIVO_GANADORES'."
 
# Numeros ganadores: primera linea no vacia, 5 valores entre 0 y 99
GANADORES_LINEA=$(tr -d '\r ' < "$ARCHIVO_GANADORES" | grep -m1 -v '^$')
if ! [[ "$GANADORES_LINEA" =~ ^([0-9]{1,2},){4}[0-9]{1,2}$ ]]; then
    error "El archivo de ganadores debe tener 5 numeros del 0 al 99 separados por coma."
fi
 
# Lista de CSV a procesar (se excluye el archivo de ganadores si esta en el mismo directorio)
RUTA_GAN=$(realpath "$ARCHIVO_GANADORES")
ARCHIVOS=()
while IFS= read -r -d '' f; do
    [[ "$(realpath "$f")" == "$RUTA_GAN" ]] && continue
    ARCHIVOS+=("$f")
done < <(find "$DIRECTORIO" -maxdepth 1 -type f -iname '*.csv' -print0 | sort -z)
 
[[ ${#ARCHIVOS[@]} -eq 0 ]] && error "No se encontraron archivos CSV en '$DIRECTORIO'."
 
# ---------- Procesamiento con AWK ----------
procesar() {
    awk -v ganadores="$GANADORES_LINEA" '
    function esc(s,   i, c, out) {          # escape minimo para JSON
        out = ""
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c == "\\")      out = out "\\\\"
            else if (c == "\"") out = out "\\\""
            else                out = out c
        }
        return out
    }
    BEGIN {
        FS = ","
        n = split(ganadores, arr, ",")
        for (i = 1; i <= n; i++) gan[arr[i] + 0] = 1
    }
    FNR == 1 {                               # nuevo archivo -> agencia
        agencia = FILENAME
        sub(/.*\//, "", agencia)
        sub(/\.[cC][sS][vV]$/, "", agencia)
        agencia = esc(agencia)
    }
    {
        gsub(/[ \t\r]/, "")                  # limpia espacios y CRLF (re-parte los campos)
        if ($0 == "") next
 
        valida = (NF == 6)
        for (i = 1; valida && i <= 6; i++) {
            if ($i !~ /^[0-9]+$/) valida = 0
            else if (i > 1 && $i + 0 > 99) valida = 0
        }
        if (!valida) {
            printf "Aviso: linea invalida ignorada (%s, linea %d)\n", FILENAME, FNR > "/dev/stderr"
            next
        }
 
        delete visto; c = 0
        for (i = 2; i <= 6; i++) {
            v = $i + 0
            if (!(v in visto)) { visto[v] = 1; if (v in gan) c++ }
        }
        if (c >= 3) {
            k = ++total[c]
            ag[c, k] = agencia
            id[c, k] = $1
        }
    }
    END {
        print "{"
        for (c = 5; c >= 3; c--) {
            printf "  \"%d_aciertos\": ", c
            if (total[c] == 0) printf "[]"
            else {
                print "["
                for (k = 1; k <= total[c]; k++) {
                    print "    {"
                    printf "      \"agencia\": \"%s\",\n", ag[c, k]
                    printf "      \"jugada\": \"%s\"\n", id[c, k]
                    printf "    }%s\n", (k < total[c] ? "," : "")
                }
                printf "  ]"
            }
            print (c > 3 ? "," : "")
        }
        print "}"
    }' "${ARCHIVOS[@]}"
}
 
# ---------- Salida ----------
if [[ $PANTALLA -eq 1 ]]; then
    procesar || error "Ocurrio un problema al procesar los archivos de jugadas."
else
    TMP_SALIDA=$(mktemp /tmp/ejercicio1.XXXXXX) || error "No se pudo crear un archivo temporal."
    procesar > "$TMP_SALIDA" || error "Ocurrio un problema al procesar los archivos de jugadas."
    cp "$TMP_SALIDA" "$ARCHIVO" || error "No se pudo escribir el archivo de salida '$ARCHIVO'."
    echo "Resultado guardado en: $ARCHIVO"
fi