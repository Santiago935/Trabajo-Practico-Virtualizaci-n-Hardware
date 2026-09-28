# Trabajo Práctico – Virtualización de Hardware (APL 1)

Universidad Nacional de La Matanza (UNLaM) — Departamento de Ingeniería e Investigaciones Tecnológicas
Cátedra de Virtualización de Hardware (3654) — 2026, segundo cuatrimestre

Actividad Práctica de Laboratorio N° 1: automatización de tareas con **Bash** y **PowerShell**. Cada ejercicio está resuelto en ambos lenguajes, con scripts equivalentes en comportamiento y parámetros.

## Integrantes

- Almada, Keila Mariel
- Manghi Scheck, Santiago
- Rivera Mamani, Victor Leoncio
- Torres Moran, Maria Celeste

## Estructura del repositorio

```
bash/
  ejercicio1/
  ejercicio2/
  ejercicio3/
  ejercicio4/
  ejercicio5/
powershell/
  ejercicio1/
  ejercicio2/
  ejercicio3/
  ejercicio4/
  ejercicio5/
```

Cada carpeta `ejercicioN` contiene el script correspondiente y, cuando el ejercicio recibe un archivo o directorio como parámetro, una carpeta `pruebas/` (o `lote_prueba/`) con casos de prueba válidos e inválidos.

## Estado de los ejercicios

| Ejercicio | Bash | PowerShell | Descripción |
|---|---|---|---|
| 1 | ⬜ Pendiente | ⬜ Pendiente | Validación de jugadas de lotería a partir de archivos CSV por agencia, comparando contra los números ganadores y generando un resultado en JSON (por pantalla o archivo). |
| 2 | ✅ | ✅ | Producto escalar y trasposición de matrices numéricas leídas desde un archivo de texto plano, con separador configurable. |
| 3 | ✅ | ✅ | Búsqueda de archivos duplicados dentro de un directorio y sus subdirectorios (mismo nombre y mismo tamaño, sin importar el contenido). |
| 4 | ⬜ Pendiente | ⬜ Pendiente | Demonio que monitorea un directorio y, al detectar un archivo duplicado (mismo criterio del ejercicio 3), genera un log y arma un backup comprimido. |
| 5 | ✅ | ✅ | Consulta de personajes y películas de Star Wars contra la API [swapi.tech](https://swapi.tech), con cache local de resultados. |

## Cómo ejecutar los scripts

Todos los scripts de Bash muestran ayuda con `-h` / `--help`:

```bash
./ejercicio3.sh --help
```

Todos los scripts de PowerShell muestran ayuda con `Get-Help`:

```powershell
Get-Help ./ejercicio3.ps1 -Detailed
```

### Ejemplos

**Ejercicio 2 — Producto escalar / trasposición de matrices**
```bash
./ejercicio2.sh -m ./pruebas/matriz_consigna.txt -p 2 -s "|"
./ejercicio2.sh -m ./pruebas/matriz_consigna.txt -t -s "|"
```
```powershell
./ejercicio2.ps1 -matriz .\pruebas\matriz_consigna.txt -producto 2 -separador "|"
./ejercicio2.ps1 -matriz .\pruebas\matriz_consigna.txt -trasponer -separador "|"
```

**Ejercicio 3 — Archivos duplicados**
```bash
./ejercicio3.sh -d ./lote_prueba
```
```powershell
./ejercicio3.ps1 -directorio ./lote_prueba
```

**Ejercicio 5 — Consulta a SWAPI**
```bash
./swapi.sh --people "1,2" --film "1,2"
```
```powershell
./swapi.ps1 -people 1,2 -film 1,2
```

## Criterios generales aplicados

- Manejo de parámetros en cualquier orden, con validación de obligatoriedad y de combinaciones inválidas.
- Aceptación de rutas relativas, absolutas y con espacios.
- Manejo de errores con mensajes claros orientados a un usuario sin conocimientos técnicos.
- Limpieza de archivos temporales al finalizar (`trap` en Bash, `try/catch/finally` en PowerShell), tanto en ejecución exitosa como por error.

## Entrega

El código fuente de cada ejercicio se entrega resuelto en Bash y en PowerShell, junto con los lotes de prueba correspondientes, siguiendo la estructura de carpetas exigida por la cátedra.
