# Ejercicio 9 — Discusión

## 9.1 ¿Qué características de DuckDB resultaron más útiles?

* **`read_parquet` con globs y `union_by_name`.** Una sola vista lee los 64 archivos de tres años aunque sus esquemas no coincidan (`cbd_congestion_fee` aparece en 2025 y `request_source` a mitad de 2026). Con `filename = true` el año y el mes salen del archivo de origen.
* **Funciones de metadatos.** `parquet_file_metadata`, `parquet_schema` y `glob` contaron registros, detectaron cambios de esquema y verificaron la integridad de los archivos en milisegundos, sin leer los datos.
* **Motor embebido.** No hay servidor que administrar: el mismo motor corre en los notebooks, en los scripts y dentro de Metabase (driver), y entrega a pandas solo los resultados ya agregados.
* **Extensiones de SQL que acortan las consultas:** `GROUP BY ALL`, `QUALIFY`, `PIVOT`/`UNPIVOT`, `COLUMNS(*)`, `* RENAME`, `UNION ALL BY NAME`, `count_if`, `median`/`quantile_cont`.
* **Ejecución en paralelo y fuera de memoria.** Agregar 121 millones de filas tomó 1–5 s sobre Parquet usando todos los núcleos, y con `memory_limit` DuckDB usa disco temporal en lugar de fallar.
* **`ATTACH` + `CREATE TABLE AS`.** Materializar los tres años en una base DuckDB fue una sola sentencia (30 s).

## 9.2 Ventajas y limitaciones de consultar directamente los Parquet

**Ventajas**

* No hay paso de carga: un archivo recién descargado ya forma parte del análisis.
* No se duplican datos: los Parquet ocupan 1,977 MiB frente a 3,280 MiB de la base DuckDB equivalente.
* Formato columnar con estadísticas: solo se leen las columnas usadas y un `count(*)` se responde con los metadatos (0.23 s para 121 millones de filas).
* El análisis es portátil: cualquier herramienta que lea Parquet (pandas, Spark, Polars) puede usar los mismos archivos.

**Limitaciones**

* Cada consulta vuelve a leer y descomprimir los archivos, y las columnas derivadas (año y mes desde el nombre del archivo, duración, velocidad) se recalculan cada vez. En el benchmark, las agregaciones fueron 5–6 veces más lentas que sobre la tabla y el filtro selectivo hasta 49 veces más lento.
* Hay que manejar explícitamente la heterogeneidad entre archivos (`union_by_name`, nombres distintos de columnas entre amarillos y verdes).
* Las rutas relativas dependen del directorio de trabajo; se resolvió con `file_search_path`. Por la misma razón una vista sobre Parquet guardada en la base no sirve para Metabase, que corre con otro directorio de trabajo.
* No hay índices ni estadísticas más finas que las de cada *row group* del archivo original.

## 9.3 Ventajas y limitaciones de las tablas materializadas

**Ventajas**

* Consultas mucho más rápidas: 5–6 veces en agregaciones sobre los tres años y hasta 49 veces en consultas selectivas, gracias al formato nativo y a sus estadísticas (*zonemaps*).
* Tiempos de respuesta interactivos para el tablero: cada pregunta de Metabase responde en menos de 3 s sobre 121 millones de filas.
* Un archivo autocontenido que se puede conectar a herramientas externas sin depender de rutas a los Parquet.

**Limitaciones**

* Costo de construcción: 30 s para los tres años, que se pagan otra vez cada vez que llegan datos (el script reconstruye la tabla completa).
* Ocupa más disco que los Parquet (3,280 vs 1,977 MiB) y es una segunda copia de los datos que puede quedar desactualizada.
* Un solo proceso puede escribir a la vez: Metabase tiene que detenerse mientras se reconstruye la base, y dos procesos de DuckDB (Metabase y el contenedor `lab`) compitieron por la memoria de la máquina virtual de Docker hasta que se limitó la de cada uno.
* No acelera todo por igual: los percentiles exactos (B5) mejoraron solo 1.2–1.5 veces, porque el costo está en ordenar los datos y no en leerlos.

## 9.4 Ventajas frente a cargar todo con pandas

* **Memoria:** pandas necesita todo el conjunto en RAM. 121 millones de filas por ~22 columnas superan los 20 GB en memoria, más que los 16 GB de la máquina virtual de Docker. DuckDB procesa por bloques y solo devuelve resultados agregados de pocas filas.
* **Lectura selectiva:** DuckDB lee solo las columnas y *row groups* que cada consulta necesita; `pandas.read_parquet` lee los archivos completos.
* **Paralelismo:** DuckDB usa todos los núcleos (32 en la máquina usada); la mayoría de las operaciones de pandas usa uno.
* **Esquemas heterogéneos:** `union_by_name` resuelve en una línea lo que en pandas requiere leer archivo por archivo, alinear columnas y unificar tipos.
* **Consultas declarativas y reutilizables:** el mismo SQL sirve para los notebooks, el benchmark y Metabase.

pandas sigue siendo útil para lo que hace bien: recibir resultados pequeños, transformarlos para mostrarlos y graficarlos.

## 9.5 Características del sistema que permiten incorporar datos con cambios mínimos

1. El año es un parámetro del script de descarga, que además es idempotente (omite lo existente y reporta lo no publicado).
2. La convención de rutas `data/raw/<tipo>/<anio>/` permite deducir tipo y año sin mantener catálogos.
3. Las vistas leen con globs, así que un archivo nuevo entra al análisis sin cambiar ninguna consulta.
4. `union_by_name` tolera columnas nuevas o ausentes.
5. Las capas `viajes` → `viajes_validos` → consultas separan la lectura, la limpieza y el análisis.
6. Las consultas del tablero agrupan por `anio`/`mes` sin años fijos, y las comparaciones anuales calculan los meses comparables a partir de los datos.
7. La materialización y el tablero se regeneran con un comando cada uno (`materializar.py`, `metabase_dashboard.py`).

Al agregar 2025 solo cambió la lista de años por defecto del script de descarga; ninguna consulta ni visualización se modificó.

## 9.6 ¿Qué debería automatizarse en producción?

* **Descarga programada** (por ejemplo, mensual con cron o un orquestador) que detecte los meses recién publicados por la TLC.
* **Validación automática de cada archivo nuevo:** tamaño igual al `Content-Length`, Parquet legible, número de filas dentro de un rango esperado, alerta ante columnas nuevas o con otro tipo (como `request_source`).
* **Monitoreo de calidad:** registrar en cada carga los indicadores de calidad (porcentaje válido, porcentaje sin `passenger_count`, totales que no cuadran) y alertar si cambian bruscamente, como pasó con los pagos `payment_type = 0`.
* **Materialización incremental:** insertar solo los archivos nuevos en lugar de reconstruir todo, construyendo la base en un archivo nuevo y reemplazándola de forma atómica para que Metabase no tenga que detenerse.
* **Regeneración de resultados:** ejecutar los notebooks (`nbconvert`) y el script del tablero después de cada carga, y el benchmark ante cambios de versión de DuckDB.

## 9.7 Decisiones de diseño importantes para la reproducibilidad

* **Ambiente en Docker con versiones fijas** (Python, DuckDB, Metabase y su driver alineados).
* **Los datos no se versionan; se versiona cómo obtenerlos.** El script descarga desde la fuente oficial y `.gitignore` excluye `data/`.
* **Cada consulta existe una sola vez,** en `sql/`, documentada con su objetivo y fuente. Notebooks, benchmark y tablero la leen desde ahí, así que lo documentado es exactamente lo que se ejecuta.
* **El tablero se crea con código** (API de Metabase) y no a mano, por lo que se puede recrear desde cero.
* **Alcances explícitos:** las consultas de cada ejercicio fijan el año que analizan (por ejemplo `anio = 2026` en el Ejercicio 4), así que sus resultados no cambian cuando se agregan datos. Las comparaciones entre años usan los mismos meses.
* **Resultados deterministas:** muestreo con semilla (`REPEATABLE`), percentiles exactos y orden explícito en todas las consultas.
* **Notebooks ejecutables de principio a fin** desde la terminal y guardados con sus resultados.

## 9.8 ¿Qué se aprendió que no habría sido evidente con datos pequeños?

* **Los problemas raros dejan de ser raros.** Un 0.01% de valores absurdos (distancias de 300,000 millas, fechas de 2001) son miles de registros. Sin reglas de limpieza explícitas dominan los máximos y distorsionan los promedios.
* **Los esquemas cambian con el tiempo.** Con un solo mes no se ve que `request_source` aparece a mitad de 2026 ni que `cbd_congestion_fee` no existe en 2024. Leer muchos archivos obliga a decidir cómo unir esquemas distintos.
* **Las tendencias de calidad solo se ven a lo largo del tiempo:** la proporción de registros sin forma de pago se triplicó en tres años.
* **El formato y la estrategia de acceso importan.** La misma consulta pasa de 4.3 s a 0.7 s según se lea Parquet o una tabla, y algunas operaciones (percentiles exactos) siguen siendo caras de cualquier forma.
* **Memoria y concurrencia son restricciones reales.** Dos procesos de DuckDB que por defecto asumen el 80% de la RAM agotaron la máquina virtual de Docker; hubo que fijar límites explícitos. Además, un archivo DuckDB admite un solo escritor.
* **Los años incompletos engañan.** Comparar 2026 (8 meses) con años completos exagera las caídas; hay que comparar los mismos meses.
* **Medianas y percentiles por encima de medias.** Con colas largas (viajes al aeropuerto, tarifas negociadas) la media no representa el viaje típico.
