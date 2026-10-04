# Ejercicio 6 — Parquet versus tablas DuckDB

Código: [`scripts/benchmark.py`](../scripts/benchmark.py), [`scripts/materializar.py`](../scripts/materializar.py) y [`scripts/lab.py`](../scripts/lab.py). Consultas: [`sql/06_benchmark.sql`](../sql/06_benchmark.sql). Resultados: [`benchmark.csv`](benchmark.csv).

## 6.1 Consulta directa de los Parquet

`conectar_parquet()` abre DuckDB en memoria y crea dos vistas: `viajes` ([`sql/00_vistas.sql`](../sql/00_vistas.sql)) sobre `read_parquet('data/raw/<tipo>/*/*.parquet', union_by_name = true)`, y `viajes_validos` ([`sql/01_limpieza.sql`](../sql/01_limpieza.sql)) encima de ella. No se copia ningún dato: cada consulta lee los archivos.

## 6.2 Tabla materializada

`materializar()` crea una base DuckDB con la tabla `viajes` a partir de **la misma vista**, y vuelve a crear `viajes_validos` sobre la tabla:

```sql
ATTACH 'data/processed/taxi.duckdb' AS db;
CREATE TABLE db.viajes AS SELECT * FROM viajes;   -- viajes = vista sobre los Parquet
USE db;
-- sql/01_limpieza.sql: CREATE OR REPLACE VIEW viajes_validos AS SELECT ... FROM viajes ...
```

Para los tres años descargados (`python scripts/materializar.py`) resulta `data/processed/taxi.duckdb` con 121,184,384 filas y 3,283 MiB, creada en ~31 s. Esa es la base que usa Metabase.

## 6.3 Consultas representativas

| Consulta | Representa | Tipo de carga |
|---|---|---|
| `B1_conteo` | tamaño del conjunto | metadatos |
| `B2_viajes_por_mes` | serie mensual (Ej. 4 P1, Ej. 7 I1) | agregación de baja cardinalidad |
| `B3_dia_hora` | demanda por día y hora (Ej. 4 P2, Ej. 7 I7) | agregación con funciones de fecha |
| `B4_forma_pago` | forma de pago y propina (Ej. 4 P6, Ej. 7 I5–I6) | agregación de varias columnas numéricas |
| `B5_percentiles` | percentiles exactos (Ej. 4 P3) | cálculo intensivo en CPU (ordenamiento) |
| `B6_zonas_top` | zonas principales (Ej. 4 P5) | agregación de alta cardinalidad + ventana |
| `B7_filtro_selectivo` | viajes desde JFK la primera semana de cada mes | filtro que conserva ~1% de las filas |

## 6.4 Mismas consultas en ambas estrategias

Las consultas de `sql/06_benchmark.sql` se ejecutan **sin modificar** con las dos conexiones. En la conexión Parquet, `viajes` es la vista sobre los archivos; en la base materializada, `viajes` es la tabla. Como la tabla se creó con `SELECT * FROM` esa misma vista, tiene las mismas filas y columnas, y `viajes_validos` es la misma vista en ambos casos. La comparación es válida porque lo único que cambia es la estrategia de acceso.

## 6.5–6.6 Tiempos y escalas de datos

`benchmark.py` repite el proceso para tres escalas, definidas por los archivos que se leen:

| Escala | Archivos | Registros | Parquet | Tabla DuckDB | Tiempo de materialización |
|---|---|---:|---:|---:|---:|
| 1 mes (2026-01) | 2 | 3,765,161 | 62 MiB | 101 MiB | 2.1 s |
| 1 año (2024) | 24 | 41,829,938 | 676 MiB | 1,119 MiB | 11.0 s |
| todos los años (2024–2026) | 64 | 121,184,384 | 1,977 MiB | 3,280 MiB | 30.0 s |

Cada consulta se ejecuta 5 veces por estrategia y se registra la **mediana**, para reducir el efecto de la primera lectura (caché del sistema operativo) y de variaciones puntuales. Ambiente: contenedor `lab`, DuckDB 1.5.5, 32 hilos, `memory_limit` de 6 GB, datos en una carpeta del host montada en Docker Desktop (Windows 11).

## 6.7 Resultados

Tiempos en segundos (mediana de 5 ejecuciones) y aceleración = Parquet / tabla:

| Consulta | 1 mes: Parquet | 1 mes: tabla | 1 mes: × | 1 año: Parquet | 1 año: tabla | 1 año: × | 3 años: Parquet | 3 años: tabla | 3 años: × |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| B1_conteo | 0.041 | 0.0005 | 85 | 0.085 | 0.0006 | 155 | 0.231 | 0.0007 | 343 |
| B2_viajes_por_mes | 0.282 | 0.032 | 8.8 | 1.445 | 0.295 | 4.9 | 4.330 | 0.749 | 5.8 |
| B3_dia_hora | 0.284 | 0.026 | 10.9 | 1.548 | 0.251 | 6.2 | 4.348 | 0.779 | 5.6 |
| B4_forma_pago | 0.355 | 0.043 | 8.2 | 1.709 | 0.340 | 5.0 | 4.943 | 0.855 | 5.8 |
| B5_percentiles | 0.779 | 0.505 | 1.5 | 6.162 | 4.905 | 1.3 | 21.119 | 17.251 | 1.2 |
| B6_zonas_top | 0.314 | 0.034 | 9.1 | 1.609 | 0.278 | 5.8 | 4.763 | 0.795 | 6.0 |
| B7_filtro_selectivo | 0.128 | 0.004 | 32.2 | 0.741 | 0.019 | 40.0 | 2.205 | 0.045 | 49.3 |

## 6.8 Consultas del benchmark

Están documentadas en [`sql/06_benchmark.sql`](../sql/06_benchmark.sql), con lo que representa cada una (tabla de 6.3). Se ejecutan sobre `viajes` (B1, B7) y `viajes_validos` (B2–B6), sin filtros de año, para que cada escala recorra todos sus datos.

## 6.9 Análisis de los resultados

* **La tabla fue más rápida en todas las consultas y escalas,** pero la ganancia depende del tipo de consulta.
* **Agregaciones (B2, B3, B4, B6): 5–6 veces más rápidas en la tabla con 1 y 3 años.** Con Parquet, cada consulta descomprime ZSTD y decodifica las columnas de todos los archivos, y además recalcula `anio` y `mes` a partir del nombre de archivo de cada fila (con una expresión regular). La tabla guarda esos datos ya decodificados, con compresión ligera, y con `anio`/`mes` como columnas. Con 1 mes la ganancia es mayor (8–11 veces) porque pesan los costos fijos de abrir archivos y leer metadatos, aunque en tiempo absoluto ambas estrategias responden en menos de 0.4 s.
* **Conteo (B1):** la tabla lo responde desde sus propios metadatos en menos de 1 ms. Con Parquet hay que leer el pie de cada archivo, así que el tiempo crece con la **cantidad de archivos** (2 → 24 → 64) más que con las filas.
* **Percentiles exactos (B5): solo 1.2–1.5 veces.** El costo está en ordenar/seleccionar ~120 millones de valores, que es igual en ambas estrategias. Materializar acelera la lectura, no el cómputo.
* **Filtro selectivo (B7): 32 → 40 → 49 veces, la mayor diferencia, y crece con el volumen.** En la tabla, DuckDB evalúa el filtro `PULocationID = 132` sobre la columna comprimida y solo lee el resto de columnas para las filas que lo cumplen. En los Parquet de la TLC cada *row group* tiene ~930 mil filas de un mes completo y contiene todas las zonas, así que sus estadísticas mínimo/máximo no permiten saltar nada y hay que descomprimir las columnas completas.
* **Escalamiento:** ambas estrategias crecen aproximadamente lineal con el volumen (de 1 año a 3 años, 2.9 veces más filas: B2 tarda 3.0 veces más en Parquet y 2.5 veces más en la tabla).
* **Costo de materializar:** 2.1 s, 11 s y 30 s. Con los tres años, cada agregación ahorra ~3.6 s, así que la tabla se amortiza después de ~8–9 consultas. Una sola carga del tablero (13 preguntas) ya la justifica.
* **Espacio:** la tabla ocupa 1.66 veces más que los Parquet (3,280 vs 1,977 MiB). Los archivos de la TLC usan ZSTD, que comprime más; DuckDB usa compresiones ligeras pensadas para leer rápido.

## 6.10 ¿Cuándo usar cada estrategia?

**Consultar directamente los Parquet** conviene cuando:

* se exploran datos recién llegados o se hacen consultas puntuales; no vale la pena pagar el tiempo de carga ni duplicar el almacenamiento;
* los archivos cambian o crecen seguido (como aquí, un mes nuevo cada mes) y se necesita consultarlos de inmediato;
* el espacio en disco es una restricción, o los datos deben seguir siendo legibles por otras herramientas (pandas, Spark, otros equipos);
* los datos se leen una sola vez para producir algo más pequeño (por ejemplo, para construir tablas agregadas).

**Materializar una tabla DuckDB** conviene cuando:

* las mismas consultas se repiten muchas veces, como en un tablero o una herramienta de BI. Aquí Metabase ejecuta 13 consultas en cada carga;
* se necesita latencia interactiva o hay consultas selectivas (filtros por zona, fecha o tipo), donde la diferencia llega a 49 veces;
* conviene calcular una sola vez columnas derivadas o limpiezas costosas;
* los datos son estables entre cargas, de modo que el costo de reconstruir la tabla se amortiza.

En este proyecto se combinaron ambas: los Parquet son la fuente de verdad y se usan para explorar, validar y analizar (notebooks), mientras que la tabla materializada alimenta el tablero y se regenera con un comando cuando llegan datos nuevos.
