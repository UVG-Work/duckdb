-- Ejercicio 3: exploracion inicial consultando directamente los Parquet de 2026.
-- Ninguna consulta importa datos a una tabla: todas leen los archivos.
-- Las rutas son relativas a la raiz del proyecto. Resultados y decisiones en
-- notebooks/03_exploracion.ipynb.

-- name: 3.1_archivos
-- Objetivo: cantidad de archivos Parquet disponibles por tipo de taxi y meses cubiertos.
-- Fuente: nombres de archivo de data/raw/*/2026/*.parquet (glob, no lee datos).
SELECT regexp_extract(file, 'raw/(\w+)/', 1)                    AS tipo_taxi,
       count(*)                                                 AS archivos,
       min(regexp_extract(file, '(\d{4}-\d{2})\.parquet$', 1))  AS primer_mes,
       max(regexp_extract(file, '(\d{4}-\d{2})\.parquet$', 1))  AS ultimo_mes
FROM glob('data/raw/*/2026/*.parquet')
GROUP BY tipo_taxi
ORDER BY tipo_taxi;

-- name: 3.2_registros_por_archivo
-- Objetivo: registros de cada archivo, leidos del pie (metadatos) del Parquet sin escanear los datos.
-- Fuente: data/raw/*/2026/*.parquet (parquet_file_metadata).
SELECT regexp_extract(file_name, '(\w+_tripdata_\d{4}-\d{2})', 1) AS archivo,
       num_rows                                                 AS registros,
       num_row_groups                                           AS row_groups
FROM parquet_file_metadata('data/raw/*/2026/*.parquet')
ORDER BY archivo;

-- name: 3.2_registros_total
-- Objetivo: total de registros por tipo de taxi contando las filas de los archivos.
-- Fuente: data/raw/yellow/2026/*.parquet y data/raw/green/2026/*.parquet.
SELECT 'yellow' AS tipo_taxi, count(*) AS registros
FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
UNION ALL
SELECT 'green', count(*)
FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true);

-- name: 3.3_columnas_yellow
-- Objetivo: columnas y tipos de datos de los archivos de taxis amarillos.
-- Fuente: data/raw/yellow/2026/*.parquet.
DESCRIBE SELECT * FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true);

-- name: 3.3_columnas_green
-- Objetivo: columnas y tipos de datos de los archivos de taxis verdes.
-- Fuente: data/raw/green/2026/*.parquet.
DESCRIBE SELECT * FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true);

-- name: 3.4_esquema_por_archivo
-- Objetivo: detectar columnas que no estan en todos los archivos o cuyo tipo fisico cambia entre archivos.
-- Fuente: esquema de cada archivo de data/raw/*/2026/*.parquet (parquet_schema).
WITH esquema AS (
    SELECT regexp_extract(file_name, 'raw/(\w+)/', 1)                AS tipo_taxi,
           regexp_extract(file_name, '(\d{4}-\d{2})\.parquet$', 1)   AS mes,
           name                                                      AS columna,
           type                                                      AS tipo_fisico
    FROM parquet_schema('data/raw/*/2026/*.parquet')
    WHERE num_children IS NULL      -- excluye el nodo raiz del esquema
)
SELECT tipo_taxi,
       columna,
       count(*)                            AS archivos_con_columna,
       count(DISTINCT tipo_fisico)         AS tipos_fisicos,
       min(mes)                            AS desde
FROM esquema
GROUP BY tipo_taxi, columna
QUALIFY archivos_con_columna < max(archivos_con_columna) OVER (PARTITION BY tipo_taxi)
     OR tipos_fisicos > 1
ORDER BY tipo_taxi, columna;

-- name: 3.5_muestra_yellow
-- Objetivo: muestra aleatoria de registros de taxis amarillos.
-- Fuente: data/raw/yellow/2026/*.parquet.
SELECT *
FROM read_parquet('data/raw/yellow/2026/*.parquet', union_by_name = true)
USING SAMPLE reservoir(5 ROWS) REPEATABLE (42);

-- name: 3.5_muestra_green
-- Objetivo: muestra aleatoria de registros de taxis verdes.
-- Fuente: data/raw/green/2026/*.parquet.
SELECT *
FROM read_parquet('data/raw/green/2026/*.parquet', union_by_name = true)
USING SAMPLE reservoir(5 ROWS) REPEATABLE (42);

-- name: 3.6_nulos
-- Objetivo: porcentaje de valores nulos por columna y tipo de taxi.
-- Fuente: vista `viajes` (sql/00_vistas.sql), es decir, los Parquet de 2026.
SELECT tipo_taxi,
       round(100.0 * count_if(COLUMNS(* EXCLUDE (tipo_taxi, anio, mes)) IS NULL) / count(*), 2)
FROM viajes
WHERE anio = 2026
GROUP BY tipo_taxi
ORDER BY tipo_taxi;

-- name: 3.6_incompletos_por_pago
-- Objetivo: verificar si los nulos se concentran en un grupo de registros (codigo de pago).
-- Fuente: vista `viajes`, anio 2026.
SELECT tipo_taxi,
       payment_type,
       count(*)                                   AS registros,
       count(*) - count(passenger_count)          AS sin_passenger_count,
       count(*) - count(RatecodeID)               AS sin_ratecode,
       count(*) - count(congestion_surcharge)     AS sin_congestion_surcharge,
       round(avg(tip_amount), 2)                  AS propina_promedio
FROM viajes
WHERE anio = 2026
GROUP BY ALL
ORDER BY tipo_taxi, payment_type;

-- name: 3.6_rangos
-- Objetivo: rangos y percentiles extremos de fechas, distancias, duraciones y montos.
-- Fuente: vista `viajes`, anio 2026.
SELECT tipo_taxi,
       min(pickup_datetime)                                                AS pickup_min,
       max(pickup_datetime)                                                AS pickup_max,
       min(trip_distance)                                                  AS distancia_min,
       quantile_cont(trip_distance, 0.5)                                   AS distancia_p50,
       quantile_cont(trip_distance, 0.999)                                 AS distancia_p999,
       max(trip_distance)                                                  AS distancia_max,
       quantile_cont(date_diff('second', pickup_datetime, dropoff_datetime) / 60, 0.999)
                                                                           AS duracion_min_p999,
       min(fare_amount)                                                    AS tarifa_min,
       quantile_cont(fare_amount, 0.5)                                     AS tarifa_p50,
       max(fare_amount)                                                    AS tarifa_max,
       max(passenger_count)                                                AS pasajeros_max
FROM viajes
WHERE anio = 2026
GROUP BY tipo_taxi
ORDER BY tipo_taxi;

-- name: 3.6_problemas
-- Objetivo: cuantificar cada problema de calidad detectado.
-- Fuente: vista `viajes`, anio 2026.
SELECT tipo_taxi,
       count(*)                                                                      AS registros,
       count_if(year(pickup_datetime) <> anio OR month(pickup_datetime) <> mes)::BIGINT AS fecha_fuera_del_mes,
       count_if(dropoff_datetime <= pickup_datetime)::BIGINT                         AS duracion_no_positiva,
       count_if(dropoff_datetime > pickup_datetime + INTERVAL 3 HOUR)::BIGINT        AS duracion_mayor_3h,
       count_if(trip_distance = 0)::BIGINT                                           AS distancia_cero,
       count_if(trip_distance > 100)::BIGINT                                         AS distancia_mayor_100mi,
       count_if(fare_amount < 0 OR total_amount < 0)::BIGINT                         AS montos_negativos,
       count_if(fare_amount = 0)::BIGINT                                             AS tarifa_cero,
       count_if(passenger_count = 0)::BIGINT                                         AS pasajeros_cero,
       count_if(PULocationID IN (264, 265) OR DOLocationID IN (264, 265))::BIGINT    AS zona_desconocida
FROM viajes
WHERE anio = 2026
GROUP BY tipo_taxi
ORDER BY tipo_taxi;

-- name: 3.6_efecto_limpieza
-- Objetivo: registros que conserva la vista viajes_validos (sql/01_limpieza.sql).
-- Fuente: vistas `viajes` y `viajes_validos`, anio 2026.
SELECT v.tipo_taxi,
       v.registros,
       l.validos,
       round(100.0 * l.validos / v.registros, 2) AS pct_validos
FROM (SELECT tipo_taxi, count(*) AS registros FROM viajes WHERE anio = 2026 GROUP BY ALL) v
JOIN (SELECT tipo_taxi, count(*) AS validos FROM viajes_validos WHERE anio = 2026 GROUP BY ALL) l
  USING (tipo_taxi)
ORDER BY v.tipo_taxi;
