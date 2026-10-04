# Ejercicio 1 — Preparación del ambiente

## Estructura del proyecto

| Ruta | Propósito |
|---|---|
| `data/raw/` | Datos originales tal como los publica la TLC, organizados como `<tipo>/<anio>/<archivo>.parquet`. Nunca se modifican: son la fuente de todo el análisis. |
| `data/processed/` | Datos derivados que se pueden regenerar a partir de `raw/`. Aquí está la base materializada `taxi.duckdb` (Ejercicio 6) que lee Metabase. |
| `notebooks/` | Notebooks de Jupyter que ejecutan las consultas, muestran resultados y gráficos e interpretan cada ejercicio de análisis (3, 4, 5 y 8). |
| `scripts/` | Código reutilizable que se ejecuta desde la terminal: descarga de datos, materialización, benchmark y creación del tablero. |
| `sql/` | Consultas SQL del proyecto, documentadas (objetivo y fuente) y separadas por ejercicio. Son la única copia de cada consulta: notebooks y scripts las leen desde aquí. |
| `docs/` | Documentación escrita (este archivo y los de los Ejercicios 2, 6, 7 y 9), resultados del benchmark y evidencia del tablero. |
| `Dockerfile` | Imagen del ambiente de análisis: Python 3.11 con DuckDB, JupyterLab, pandas, pyarrow, matplotlib y requests. |
| `metabase.Dockerfile` | Imagen de Metabase con el driver de DuckDB, sobre Debian, porque el driver necesita glibc. |
| `docker-compose.yml` | Define y conecta los dos servicios (`lab` y `metabase`), sus puertos y los directorios montados. |
| `requirements.txt` | Versiones exactas de las librerías de Python. `duckdb` va alineada con la versión del driver de Metabase. |
| `.gitignore` | Excluye del repositorio los datos (`data/raw/**`, `data/processed/**`) y los archivos temporales. |

Los directorios `data/`, `notebooks/`, `scripts/`, `sql/` y `docs/` están montados dentro del contenedor `lab` en `/workspace/...`. Todo lo que se genera en el contenedor queda en la carpeta del proyecto, y lo que se edita fuera del contenedor se ve dentro sin reconstruir la imagen. Metabase monta solo `data/`, en la misma ruta (`/workspace/data`).

## 1.1 Fork del repositorio

El laboratorio se desarrolla sobre un fork de <https://github.com/menene/duckdb> (botón *Fork* en GitHub). El repositorio del docente se agrega como remoto `upstream` para recibir correcciones:

```bash
git remote add upstream https://github.com/menene/duckdb.git
git fetch upstream
```

## 1.2 Clonar y levantar el ambiente

```bash
git clone <url-del-fork> lab8-duckdb
cd lab8-duckdb
docker compose up --build -d
```

La primera construcción descarga las imágenes base, Metabase y las librerías de Python, y tarda varios minutos.

## 1.3 Verificación de los servicios

| Verificación | Comando | Resultado obtenido |
|---|---|---|
| Contenedores en ejecución | `docker compose ps` | `lab8-lab` y `lab8-metabase` en estado `Up` |
| JupyterLab responde | `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8888/lab` | `200` |
| Metabase responde | `curl -s http://127.0.0.1:3000/api/health` | `{"status":"ok"}` |
| Metabase tiene el driver de DuckDB | `curl -s http://127.0.0.1:3000/api/session/properties` (campo `engines`) | incluye `duckdb` |
| DuckDB disponible en `lab` | `docker compose exec lab python -c "import duckdb; print(duckdb.__version__)"` | `1.5.5` |
| Acceso a internet desde `lab` | `docker compose exec lab python scripts/download_data.py --anio 2026` | descarga los archivos (Ejercicio 2) |

## 1.4 Herramientas disponibles en el ambiente

**Servicio `lab`** (imagen `python:3.11.14-slim`, Debian 13), en <http://localhost:8888>:

| Herramienta | Versión | Uso en el laboratorio |
|---|---|---|
| Python | 3.11.14 | scripts y notebooks |
| DuckDB (paquete de Python) | 1.5.5 | motor SQL sobre Parquet y base materializada |
| JupyterLab / nbconvert | 4.6.4 / 7.17.1 | notebooks interactivos y su ejecución desde terminal |
| pandas | 3.0.6 | recibir los resultados agregados de DuckDB |
| pyarrow | 25.0.1 | intercambio columnar entre DuckDB y pandas |
| matplotlib | 3.11.2 | gráficos de los notebooks |
| requests | 2.34.2 | descarga de datos y API de Metabase |
| curl | — | pruebas rápidas de red |

No incluye la CLI de DuckDB; DuckDB se usa desde Python.

**Servicio `metabase`** (Java 21, Eclipse Temurin sobre Debian), en <http://localhost:3000>:

| Herramienta | Versión | Uso |
|---|---|---|
| Metabase | v0.63.19 | tablero de indicadores (Ejercicio 7) |
| Driver DuckDB para Metabase | 1.5.5.0 | conecta Metabase con `data/processed/taxi.duckdb` |

Los puertos están publicados solo en `127.0.0.1`, así que los servicios no quedan expuestos a la red. La configuración interna de Metabase (usuarios, preguntas, tableros) se guarda en el volumen de Docker `metabase-data`.

## 1.5 Procedimiento documentado

El procedimiento para levantar el ambiente está en la sección [Cómo levantar el ambiente](../README.md#como-levantar-el-ambiente) del README.

## 1.6 ¿Por qué es importante un ambiente reproducible?

* **Mismos resultados en cualquier máquina.** Las versiones exactas (Python 3.11.14, DuckDB 1.5.5, Metabase v0.63.19) están fijadas en el código. Un cambio de versión puede alterar resultados (por ejemplo, el redondeo de `quantile_cont` o el tipo que DuckDB asigna a una columna) o romper la compatibilidad entre DuckDB y el driver de Metabase, que deben coincidir.
* **El análisis se puede auditar.** Cualquier persona puede levantar el ambiente, descargar los datos y volver a ejecutar las consultas para comprobar cada número del informe.
* **Sin “en mi máquina funciona”.** Los tres integrantes trabajan con el mismo sistema operativo, librerías y rutas (`/workspace/...`), sin importar si usan Windows, macOS o Linux.
* **Los datos crecen.** El ambiente debe poder volver a ejecutarse dentro de meses, cuando la TLC publique nuevos archivos, y producir resultados comparables con los de hoy.
* **Aislamiento.** Las dependencias del proyecto no interfieren con otras instalaciones del equipo, y el ambiente se puede borrar y recrear con un solo comando.
