# Lab 8 - DuckDB

Repositorio base del laboratorio 8 del curso **CC3084 - Data Science**
(Universidad del Valle de Guatemala, Ciclo 2, 2026).

Este es el repositorio **proporcionado por el docente**. Contiene la estructura
del proyecto, el ambiente de ejecucion basado en Docker y un script que descarga
los datos de **2026**. Todo lo demas debe ser construido por cada equipo.


## Estructura

```text
duckdb/
|
+-- data/
|   +-- raw/
|   +-- processed/
|
+-- notebooks/
|
+-- scripts/
|
+-- sql/
|
+-- docs/
|
+-- Dockerfile
+-- metabase.Dockerfile
+-- docker-compose.yml
+-- README.md
```

## Requisitos

- Docker, con Docker Compose
- Git

La primera construccion del ambiente descarga varios cientos de MB y puede
tardar algunos minutos.

Considere el espacio en disco: las imagenes de Docker ocupan unos 3 GB y los
datos de los tres anios del laboratorio superan 1.5 GB, a los que se suma la
base materializada del Ejercicio 6. Se recomienda tener al menos 10 GB libres.

## Datos

El repositorio incluye `scripts/download_data.py`, que descarga los archivos de
2026 publicados por la TLC (`--help` muestra las opciones disponibles). Los
archivos se guardan en `data/raw/<tipo>/<anio>/`.

La TLC publica cada mes con varias semanas de atraso, por lo que los ultimos
meses de 2026 todavia no existen. El script consulta al servidor que meses estan
publicados, de modo que vuelve a ejecutarse sin problema conforme aparezcan
nuevos archivos.

Los datos descargados **no deben incluirse en el repositorio Git**. El archivo
`.gitignore` ya esta configurado para evitarlo.

Fuente de datos: NYC TLC Trip Record Data
<https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page>

Dentro de los contenedores, la carpeta `data/` del proyecto esta montada en
`/workspace/data`. Esa es la ruta que deben usar las herramientas que corren
dentro del ambiente, no la ruta de su computadora.

> **Nota sobre DuckDB:** un archivo `.duckdb` admite un solo proceso con permiso
> de escritura a la vez. Si conecta una herramienta externa a su base de datos,
> use el modo de solo lectura (`read_only`) en esa conexion; de lo contrario los
> demas procesos no podran abrir el archivo.

## Material a entregar

Al finalizar, su fork debe contener:

- el codigo fuente modificado y los scripts de descarga;
- las consultas SQL desarrolladas;
- el notebook o notebooks utilizados;
- la documentacion de las consultas;
- los scripts utilizados para los benchmarks;
- el codigo de los indicadores y visualizaciones;
- el tablero o la evidencia del tablero desarrollado;
- este `README.md`, completado segun la siguiente seccion.

Los archivos de datos descargados **no** deben incluirse.

---

# Documentacion del equipo

Las siguientes secciones deben ser completadas por cada equipo. El README final
debe permitir que una persona que no participo en el desarrollo pueda levantar el
ambiente, descargar los datos, ejecutar el analisis, reproducir los benchmarks y
generar los resultados principales.

## Integrantes

- Andres Mazariegos
- June Herrera
- Rodrigo Ajmac

## Donde esta cada ejercicio

| Ejercicio | Documentacion y resultados | Codigo y consultas |
|---|---|---|
| 1. Preparacion del ambiente | [`docs/ejercicio1.md`](docs/ejercicio1.md) | `Dockerfile`, `docker-compose.yml` |
| 2. Sistema de descarga | [`docs/ejercicio2.md`](docs/ejercicio2.md) | [`scripts/download_data.py`](scripts/download_data.py) |
| 3. Consultas directas sobre Parquet | [`notebooks/03_exploracion.ipynb`](notebooks/03_exploracion.ipynb) | [`sql/03_exploracion.sql`](sql/03_exploracion.sql) |
| 4. Analisis exploratorio | [`notebooks/04_analisis_exploratorio.ipynb`](notebooks/04_analisis_exploratorio.ipynb) | [`sql/04_analisis_exploratorio.sql`](sql/04_analisis_exploratorio.sql) |
| 5. Incorporacion de 2024 | [`notebooks/05_incorporacion_2024.ipynb`](notebooks/05_incorporacion_2024.ipynb) | [`sql/05_incorporacion_2024.sql`](sql/05_incorporacion_2024.sql) |
| 6. Parquet vs tablas DuckDB | [`docs/ejercicio6.md`](docs/ejercicio6.md), [`docs/benchmark.csv`](docs/benchmark.csv) | [`scripts/benchmark.py`](scripts/benchmark.py), [`scripts/materializar.py`](scripts/materializar.py), [`sql/06_benchmark.sql`](sql/06_benchmark.sql) |
| 7. Indicadores y tablero | [`docs/ejercicio7.md`](docs/ejercicio7.md), [`docs/img/`](docs/img) | [`sql/07_indicadores.sql`](sql/07_indicadores.sql), [`scripts/metabase_dashboard.py`](scripts/metabase_dashboard.py) |
| 8. 2025 y analisis completo | [`notebooks/08_analisis_completo.ipynb`](notebooks/08_analisis_completo.ipynb) | [`sql/08_evolucion.sql`](sql/08_evolucion.sql) |
| 9. Discusion | [`docs/ejercicio9.md`](docs/ejercicio9.md) | — |

Piezas compartidas:

- [`sql/00_vistas.sql`](sql/00_vistas.sql): vista `viajes`, que une amarillos y verdes leyendo directamente todos los Parquet de `data/raw/`.
- [`sql/01_limpieza.sql`](sql/01_limpieza.sql): vista `viajes_validos`, con las reglas de calidad definidas en el Ejercicio 3.
- [`scripts/lab.py`](scripts/lab.py): funciones que usan notebooks y scripts (cargar las consultas de `sql/`, conectarse a los Parquet o a la tabla, materializar).

Cada consulta existe una sola vez, en `sql/`, bajo un comentario `-- name:` con su objetivo y
su fuente; los notebooks y scripts la leen desde ahi.

## Como levantar el ambiente

Requisitos: Docker con Docker Compose, Git, al menos 10 GB libres en disco y al menos
12 GB de RAM asignados a Docker (en Docker Desktop: *Settings > Resources*). Con menos
RAM, reducir `MEMORIA` en `scripts/lab.py` y `memory_limit` en `scripts/metabase_dashboard.py`.

```bash
git clone <url-del-fork> lab8-duckdb
cd lab8-duckdb
docker compose up --build -d
```

Verificar que los dos servicios esten arriba:

```bash
docker compose ps                                   # lab8-lab y lab8-metabase en estado Up
curl -s http://127.0.0.1:3000/api/health            # {"status":"ok"} (Metabase tarda ~1 min en iniciar)
```

- JupyterLab: <http://localhost:8888> (sin contrasena).
- Metabase: <http://localhost:3000>.

Todos los comandos del proyecto se ejecutan dentro del contenedor `lab` con
`docker compose exec lab ...`, desde la raiz del repositorio. Para detener el ambiente:
`docker compose down` (conserva la configuracion de Metabase; `docker compose down -v` la borra).

## Como descargar los datos

```bash
docker compose exec lab python scripts/download_data.py
```

Descarga los archivos de taxis amarillos y verdes de 2024, 2025 y 2026 desde la fuente
original de la TLC a `data/raw/<tipo>/<anio>/`. Opciones:

```bash
docker compose exec lab python scripts/download_data.py --anio 2026          # un anio
docker compose exec lab python scripts/download_data.py --anio 2024 2026     # varios anios
docker compose exec lab python scripts/download_data.py --taxi green         # un tipo
```

- Los archivos que ya existen no se vuelven a descargar, asi que el comando se puede repetir;
  los meses que la TLC aun no publica se reportan como `aun no publicado` y se descargan en
  una ejecucion posterior.
- Para agregar un anio nuevo, pasarlo en `--anio` o agregarlo a `ANIOS` en el script.
- Los cambios hechos al script y la verificacion de que la descarga esta completa estan en
  [`docs/ejercicio2.md`](docs/ejercicio2.md).

## Como ejecutar el analisis

1. Materializar la base que usan el tablero y el notebook 08 (`data/processed/taxi.duckdb`).
   Metabase mantiene abierto ese archivo, por eso se detiene mientras se reconstruye:

   ```bash
   docker compose stop metabase
   docker compose exec lab python scripts/materializar.py
   docker compose start metabase
   ```

2. Ejecutar los notebooks, en orden. Desde JupyterLab (<http://localhost:8888>, carpeta
   `notebooks/`) o desde la terminal:

   ```bash
   docker compose exec lab jupyter nbconvert --to notebook --execute --inplace \
       notebooks/03_exploracion.ipynb notebooks/04_analisis_exploratorio.ipynb \
       notebooks/05_incorporacion_2024.ipynb notebooks/08_analisis_completo.ipynb
   ```

   Los notebooks consultan los Parquet directamente con DuckDB; no hace falta cargar nada antes.

3. Crear o actualizar el tablero de Metabase (Ejercicio 7):

   ```bash
   docker compose exec lab python scripts/metabase_dashboard.py
   ```

   El script hace la configuracion inicial de Metabase, registra la base DuckDB en modo
   solo lectura, crea las preguntas de [`sql/07_indicadores.sql`](sql/07_indicadores.sql)
   y arma el tablero *Taxis NYC - Indicadores*. Al final imprime su URL y un enlace publico
   (accesible solo desde la propia maquina). Usuario de Metabase: `admin@example.com` /
   `Lab8-DuckDB-2026`, configurables con las variables `MB_EMAIL` y `MB_PASSWORD`.
   Despues de descargar datos nuevos basta con repetir el paso 1: las consultas del tablero
   no fijan anios.

## Como reproducir los benchmarks

```bash
docker compose exec lab python scripts/benchmark.py
```

Para tres escalas de datos (un mes, un anio y todos los anios descargados), el script
materializa los mismos archivos en `data/processed/benchmark.duckdb` y ejecuta 5 veces cada
consulta de [`sql/06_benchmark.sql`](sql/06_benchmark.sql) sobre los Parquet y sobre la tabla.
Guarda la mediana de cada una en [`docs/benchmark.csv`](docs/benchmark.csv) y borra la base
temporal al terminar. Necesita ~3.5 GB libres adicionales y tarda unos 10 minutos. Para que
los tiempos sean comparables, no ejecutar otras consultas mientras corre. Resultados y
analisis en [`docs/ejercicio6.md`](docs/ejercicio6.md).

## Como generar los resultados principales

Secuencia completa desde cero:

```bash
docker compose up --build -d
docker compose exec lab python scripts/download_data.py
docker compose stop metabase
docker compose exec lab python scripts/materializar.py
docker compose start metabase
docker compose exec lab python scripts/metabase_dashboard.py
docker compose exec lab jupyter nbconvert --to notebook --execute --inplace \
    notebooks/03_exploracion.ipynb notebooks/04_analisis_exploratorio.ipynb \
    notebooks/05_incorporacion_2024.ipynb notebooks/08_analisis_completo.ipynb
docker compose exec lab python scripts/benchmark.py
```

| Resultado | Donde queda |
|---|---|
| Exploracion, analisis exploratorio, incorporacion de 2024 y evolucion 2024-2026 | notebooks ejecutados en `notebooks/` |
| Tablero de indicadores | Metabase, <http://localhost:3000> (capturas en [`docs/img/`](docs/img)) |
| Tiempos Parquet vs tabla | [`docs/benchmark.csv`](docs/benchmark.csv) |
| Base materializada | `data/processed/taxi.duckdb` (no se versiona) |

Los resultados de 2026 corresponden a los meses publicados al momento de la ejecucion
(enero a agosto de 2026, al 4 de octubre de 2026). Si la TLC publica mas meses, una nueva
ejecucion los incluye.
