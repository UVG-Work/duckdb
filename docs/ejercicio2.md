# Ejercicio 2 — Desarrollo del sistema de descarga

Script: [`scripts/download_data.py`](../scripts/download_data.py).

## 2.1 Análisis del script proporcionado

El script del docente ya resolvía bien la mecánica de la descarga, así que esa parte se conservó tal cual:

* consulta al servidor con `HEAD` si cada mes está publicado, en lugar de suponerlo (la TLC publica con semanas de atraso);
* omite los archivos que ya existen localmente y no están vacíos;
* descarga por bloques sobre un archivo temporal `.part` y solo lo renombra al terminar, para no dejar archivos a medias;
* reintenta hasta 3 veces por archivo y muestra un resumen con descargados, omitidos, no publicados y fallidos.

Lo incompleto era el **alcance**: el año estaba fijo en la constante `ANIO = 2026`, que se usaba en `construir_nombre`, `construir_url`, `ruta_destino`, en el ciclo de `descargar` y en los textos de ayuda. Con eso solo se podía obtener 2026, y los Ejercicios 5 y 8 piden 2024 y 2025 sin rehacer el script. Esas eran las partes a modificar.

## 2.2 Modificaciones

| Antes | Después |
|---|---|
| `ANIO = 2026` | `ANIOS = (2024, 2025, 2026)`: años por defecto |
| `construir_nombre(tipo, mes)`, `construir_url(tipo, mes)`, `ruta_destino(tipo, mes)` | reciben también `anio` |
| `descargar(tipo)` recorría los 12 meses de 2026 | `descargar(tipo, anio)` recorre los 12 meses del año indicado |
| `main()` recorría solo los tipos de taxi | recorre años × tipos y acumula un único resumen |
| sin argumento de año | `--anio` acepta uno o varios años (`--anio 2026`, `--anio 2024 2026`) |
| docstring y `--help` hablaban solo de 2026 | describen el uso con años |

Uso:

```bash
docker compose exec lab python scripts/download_data.py                  # 2024, 2025 y 2026
docker compose exec lab python scripts/download_data.py --anio 2026      # solo 2026 (Ejercicio 2)
docker compose exec lab python scripts/download_data.py --taxi green --anio 2025
```

Para obtener los datos que pide este ejercicio (amarillos y verdes de 2026) se ejecutó `--anio 2026`. Los años 2024 y 2025 se incorporaron en los Ejercicios 5 y 8.

## 2.3 Dónde se guardan los archivos

`ruta_destino` arma `data/raw/<tipo>/<anio>/<nombre original>`, por ejemplo `data/raw/yellow/2026/yellow_tripdata_2026-01.parquet`, que es la estructura definida por el repositorio. Dentro del contenedor la ruta es relativa a `/workspace`, que corresponde a la carpeta del proyecto, y `.gitignore` impide subir esos archivos a Git.

## 2.4 No se vuelve a descargar un archivo existente

Antes de consultar el servidor, `descargar` comprueba `destino.exists() and destino.stat().st_size > 0`. Si se cumple, imprime `ya existe, se omite` y pasa al siguiente mes. No se hace ninguna petición por ese archivo.

## 2.5 Ejecución y verificación

Primera ejecución (`--anio 2026`), resumida:

```text
=== YELLOW 2026 ===
  2026-01  listo (61.2 MiB) -> data/raw/yellow/2026/yellow_tripdata_2026-01.parquet
  ...                                  (2026-01 a 2026-08, 56.0 a 66.5 MiB cada uno)
  2026-09  aun no publicado por la TLC
  ...                                  (2026-09 a 2026-12)
=== GREEN 2026 ===
  2026-01  listo (968.4 KiB) -> data/raw/green/2026/green_tripdata_2026-01.parquet
  ...                                  (2026-01 a 2026-08, 0.9 a 1.1 MiB cada uno)
  2026-09  aun no publicado por la TLC
  ...
RESUMEN
  descargados   : 16
  ya existian   : 0
  no publicados : 8
      yellow 2026-09, yellow 2026-10, yellow 2026-11, yellow 2026-12, green 2026-09, ...
  fallidos      : 0
```

Segunda ejecución inmediata, con el mismo comando:

```text
RESUMEN
  descargados   : 0
  ya existian   : 16
  no publicados : 8
  fallidos      : 0
```

## 2.6 Documentación de los cambios

Los cambios están descritos en 2.2 y en el docstring del script (`python scripts/download_data.py --help`). Las instrucciones de uso están en la sección [Cómo descargar los datos](../README.md#como-descargar-los-datos) del README.

## 2.7 ¿Cómo se determinó que el conjunto descargado está completo?

Se comprobaron cuatro cosas:

1. **Cobertura de meses.** El resumen cuenta los 12 meses de cada tipo: 8 descargados + 4 no publicados, 0 fallidos. Los meses que faltan son los últimos del año (septiembre–diciembre), y el servidor responde `403` para ellos, que es lo que devuelve CloudFront cuando el archivo no existe. No hay huecos intermedios: la consulta `3.1_archivos` (Ejercicio 3) muestra 8 archivos consecutivos por tipo, de 2026-01 a 2026-08.
2. **Tamaño idéntico al publicado.** Se comparó el tamaño local de cada archivo con el `Content-Length` que informa el servidor:

   ```bash
   docker compose exec lab python -c "
   import requests; from pathlib import Path
   for p in sorted(Path('data/raw').glob('*/*/*.parquet')):
       r = requests.head('https://d37ci6vzurychx.cloudfront.net/trip-data/' + p.name)
       print(p.name, int(r.headers['Content-Length']) == p.stat().st_size)"
   ```

   La verificación se ejecutó sobre los 64 archivos descargados en el laboratorio (incluidos los 16 de 2026) y todos coinciden byte a byte.
3. **Archivos legibles.** Un Parquet guarda su esquema y número de filas en el pie, al final del archivo, así que uno truncado no se puede abrir. DuckDB leyó los metadatos de los 16 archivos (`3.2_registros_por_archivo`) y la suma de `num_rows` (30,040,469) coincide con el conteo de filas (`3.2_registros_total`).
4. **Volúmenes plausibles.** Cada mes tiene entre 3.3 y 4.1 millones de viajes amarillos y entre 37 y 45 mil verdes, sin meses vacíos ni anormalmente pequeños.

Además, el diseño del script evita que un archivo incompleto quede con nombre final: la descarga se escribe en `.part` y solo se renombra cuando terminó sin errores.
