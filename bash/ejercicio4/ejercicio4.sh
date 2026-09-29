#!/bin/bash

mostrar_ayuda() {
    cat <<EOF
Uso:
  $0 -d <directorio> -s <salida>
  $0 -d <directorio> -k

Descripcion:
  Monitorea un directorio (y sus subdirectorios) en segundo plano. Cuando se
  crea un archivo con el mismo nombre y tamano que otro ya existente, se
  registra en un log y se archivan los duplicados en un .tar.gz.

Parametros:
  -d, --directorio   Ruta del directorio a monitorear.
  -s, --salida       Ruta del directorio donde se crean los backups y el log.
  -k, --kill         Detiene el demonio iniciado para el directorio indicado.
                     Solo se puede usar junto con -d / --directorio.
  -h, --help         Muestra esta ayuda.

Ejemplos:
  $0 -d ../monitor --salida ../salida
  $0 -d ../monitor --kill
EOF
}

error() {
    echo "Error: $1" >&2
    exit 1
}

archivo_pid() {
    echo "/tmp/demonio_$(printf '%s' "$1" | md5sum | cut -d' ' -f1).pid"
}

demonio_activo() {
    local pf="$1" pid
    [[ -f "$pf" ]] || return 1
    pid=$(<"$pf")
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null \
        && tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "${0##*/}"; then
        return 0
    fi
    rm -f "$pf"
    return 1
}

registrar() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$2/duplicados.log"
}

procesar_archivo() {
    local nuevo="$1" dir="$2" salida="$3"
    local nombre tam otro backup
    local -a archivos

    [[ -f "$nuevo" ]] || return 0
    nombre="${nuevo##*/}"
    tam=$(stat -c %s -- "$nuevo" 2>/dev/null) || return 0
    archivos=("$nuevo")

    while IFS= read -r -d '' otro; do
        if [[ "${otro##*/}" == "$nombre" && "$otro" != "$nuevo" ]]; then
            archivos+=("$otro")
        fi
    done < <(find "$dir" -type f -size "${tam}c" -print0 2>/dev/null)

    (( ${#archivos[@]} > 1 )) || return 0

    backup="$salida/$(date +%Y%m%d-%H%M%S).tar.gz"
    while [[ -e "$backup" ]]; do
        sleep 1
        backup="$salida/$(date +%Y%m%d-%H%M%S).tar.gz"
    done

    if tar -czf "$backup" "${archivos[@]}" 2>/dev/null; then
        registrar "Duplicado detectado: '$nombre' ($tam bytes). Archivos: ${archivos[*]}. Backup: $backup" "$salida"
    else
        rm -f "$backup"
        registrar "No se pudo generar el backup del duplicado '$nombre'" "$salida"
    fi
}

detener_demonio() {
    [[ -n "$INOTIFY_PID" ]] && kill "$INOTIFY_PID" 2>/dev/null
    rm -f "$PIDFILE"
    exit 0
}

monitorear() {
    local dir="$1" salida="$2" pf="$3" archivo

    trap '' HUP
    trap 'detener_demonio' TERM INT
    trap 'rm -f "$pf"' EXIT

    exec 3< <(inotifywait -m -r -q -e close_write -e moved_to --format '%w%f' "$dir" 2>/dev/null)
    INOTIFY_PID=$!

    registrar "Demonio iniciado sobre '$dir'" "$salida"

    while IFS= read -r -u 3 archivo; do
        procesar_archivo "$archivo" "$dir" "$salida"
    done

    registrar "Demonio finalizado sobre '$dir'" "$salida"
}

DIRECTORIO=""
SALIDA=""
KILL=0

if ! OPCIONES=$(getopt -o d:s:kh --long directorio:,salida:,kill,help -n "$0" -- "$@" 2>/dev/null); then
    error "Parametros invalidos. Use -h o --help para ver la ayuda."
fi
eval set -- "$OPCIONES"

while true; do
    case "$1" in
        -d|--directorio) DIRECTORIO="$2"; shift 2 ;;
        -s|--salida) SALIDA="$2"; shift 2 ;;
        -k|--kill) KILL=1; shift ;;
        -h|--help) mostrar_ayuda; exit 0 ;;
        --) shift; break ;;
        *) error "Parametro desconocido: $1" ;;
    esac
done

[[ $# -eq 0 ]] || error "Argumentos inesperados: $*. Use -h o --help para ver la ayuda."
[[ -n "$DIRECTORIO" ]] || error "Debe indicar el directorio a monitorear con -d / --directorio."
[[ -d "$DIRECTORIO" ]] || error "El directorio '$DIRECTORIO' no existe o no es un directorio."

DIRECTORIO=$(realpath -- "$DIRECTORIO") || error "No se pudo resolver la ruta del directorio."
PIDFILE=$(archivo_pid "$DIRECTORIO")

if (( KILL )); then
    [[ -z "$SALIDA" ]] || error "El parametro -k / --kill solo se puede usar junto con -d / --directorio."

    demonio_activo "$PIDFILE" || error "No hay ningun demonio en ejecucion para el directorio '$DIRECTORIO'."

    PID=$(<"$PIDFILE")
    kill "$PID" 2>/dev/null || error "No se pudo detener el demonio (PID $PID)."

    for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.5
    done

    if kill -0 "$PID" 2>/dev/null; then
        error "El demonio (PID $PID) no respondio a la orden de detenerse."
    fi

    rm -f "$PIDFILE"
    echo "Demonio detenido para el directorio '$DIRECTORIO'."
    exit 0
fi

[[ -n "$SALIDA" ]] || error "Debe indicar el directorio de salida con -s / --salida."

command -v inotifywait >/dev/null 2>&1 || error "Falta la herramienta inotify-tools. Instalela con: sudo apt install inotify-tools"

mkdir -p -- "$SALIDA" 2>/dev/null || error "No se pudo crear el directorio de salida '$SALIDA'."
SALIDA=$(realpath -- "$SALIDA") || error "No se pudo resolver la ruta del directorio de salida."
[[ -w "$SALIDA" ]] || error "No hay permisos de escritura en el directorio de salida '$SALIDA'."

if [[ "$SALIDA" == "$DIRECTORIO" || "$SALIDA" == "$DIRECTORIO"/* ]]; then
    error "El directorio de salida no puede estar dentro del directorio monitoreado."
fi

if demonio_activo "$PIDFILE"; then
    error "Ya existe un demonio en ejecucion para el directorio '$DIRECTORIO'."
fi

monitorear "$DIRECTORIO" "$SALIDA" "$PIDFILE" </dev/null >/dev/null 2>&1 &
PID=$!
echo "$PID" > "$PIDFILE"
disown "$PID"

sleep 1
if ! kill -0 "$PID" 2>/dev/null; then
    rm -f "$PIDFILE"
    error "No se pudo iniciar el demonio."
fi

echo "Demonio iniciado para el directorio '$DIRECTORIO' (PID $PID)."
exit 0