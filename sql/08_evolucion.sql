-- Ejercicio 8: incorporacion de 2025 y evolucion 2024-2026.
-- Fuente: vistas `viajes` / `viajes_validos` sobre todos los Parquet descargados.
-- 2026 solo tiene los meses publicados, por eso las comparaciones anuales usan
-- los mismos meses en los tres anios (enero hasta el ultimo mes publicado del
-- anio mas reciente). Resultados en notebooks/08_analisis_completo.ipynb.

-- name: 8.2_archivos_por_anio
-- Objetivo: verificar los archivos de cada tipo y anio despues de agregar 2025.
-- Fuente: nombres de archivo de data/raw/*/*/*.parquet (glob).
SELECT regexp_extract(file, 'raw/(\w+)/', 1)                         AS tipo_taxi,
       CAST(regexp_extract(file, 'raw/\w+/(\d{4})/', 1) AS INTEGER)  AS anio,
       count(*)                                                      AS archivos,
       min(regexp_extract(file, '(\d{4}-\d{2})\.parquet$', 1))       AS primer_mes,
       max(regexp_extract(file, '(\d{4}-\d{2})\.parquet$', 1))       AS ultimo_mes
FROM glob('data/raw/*/*/*.parquet')
GROUP BY ALL
ORDER BY tipo_taxi, anio;

-- name: 8.2_registros_por_anio
-- Objetivo: registros por tipo y anio segun los metadatos de cada archivo.
-- Fuente: metadatos de data/raw/*/*/*.parquet (parquet_file_metadata).
SELECT regexp_extract(file_name, 'raw/(\w+)/', 1)                        AS tipo_taxi,
       CAST(regexp_extract(file_name, 'raw/\w+/(\d{4})/', 1) AS INTEGER) AS anio,
       count(*)                                                          AS archivos,
       sum(num_rows)::BIGINT                                             AS registros
FROM parquet_file_metadata('data/raw/*/*/*.parquet')
GROUP BY ALL
ORDER BY tipo_taxi, anio;

-- name: 8.5_indicadores_anuales
-- Objetivo: valor de los indicadores principales por anio y tipo, en los meses comparables.
-- Fuente: vista `viajes_validos`.
SELECT anio,
       tipo_taxi,
       count(*)                                                              AS viajes,
       round(count(*) / count(DISTINCT CAST(pickup_datetime AS DATE)))       AS viajes_por_dia,
       round(avg(total_amount), 2)                                           AS ticket_promedio_usd,
       round(sum(fare_amount) / sum(trip_distance), 2)                       AS tarifa_por_milla,
       round(median(trip_distance), 2)                                       AS distancia_mediana_mi,
       round(median(duracion_min), 1)                                        AS duracion_mediana_min,
       round(median(velocidad_mph), 2)                                       AS velocidad_mediana_mph,
       round(100.0 * count_if(forma_pago = 'Tarjeta') / count(*), 1)         AS pct_tarjeta,
       round(100.0 * count_if(forma_pago = 'Efectivo') / count(*), 1)        AS pct_efectivo,
       round(100.0 * count_if(forma_pago = 'Flex fare / sin dato') / count(*), 1) AS pct_flex_sin_dato,
       round(100.0 * count_if(PULocationID IN (1, 132, 138) OR DOLocationID IN (1, 132, 138))
             / count(*), 2)                                                  AS pct_aeropuerto,
       round(100.0 * count_if(cbd_congestion_fee > 0) / count(*), 1)        AS pct_con_cargo_cbd
FROM viajes_validos
WHERE mes <= (SELECT max(mes) FROM viajes WHERE anio = (SELECT max(anio) FROM viajes))
GROUP BY anio, tipo_taxi
ORDER BY tipo_taxi, anio;

-- name: 8.5_variacion_anual
-- Objetivo: variacion porcentual de cada indicador respecto del anio anterior (meses comparables).
-- Fuente: vista `viajes_validos`.
WITH anual AS (
    SELECT anio,
           tipo_taxi,
           count(*) / count(DISTINCT CAST(pickup_datetime AS DATE))  AS viajes_por_dia,
           avg(total_amount)                                         AS ticket,
           sum(fare_amount) / sum(trip_distance)                     AS tarifa_por_milla,
           median(duracion_min)                                      AS duracion_mediana,
           median(velocidad_mph)                                     AS velocidad_mediana
    FROM viajes_validos
    WHERE mes <= (SELECT max(mes) FROM viajes WHERE anio = (SELECT max(anio) FROM viajes))
    GROUP BY anio, tipo_taxi
)
SELECT anio,
       tipo_taxi,
       round(100 * (viajes_por_dia    / lag(viajes_por_dia)    OVER w - 1), 1) AS var_viajes_por_dia,
       round(100 * (ticket            / lag(ticket)            OVER w - 1), 1) AS var_ticket,
       round(100 * (tarifa_por_milla  / lag(tarifa_por_milla)  OVER w - 1), 1) AS var_tarifa_por_milla,
       round(100 * (duracion_mediana  / lag(duracion_mediana)  OVER w - 1), 1) AS var_duracion,
       round(100 * (velocidad_mediana / lag(velocidad_mediana) OVER w - 1), 1) AS var_velocidad
FROM anual
WINDOW w AS (PARTITION BY tipo_taxi ORDER BY anio)
QUALIFY lag(anio) OVER w IS NOT NULL
ORDER BY tipo_taxi, anio;

-- name: 8.5_viajes_por_dia_mensual
-- Objetivo: viajes promedio por dia en cada mes, para superponer los tres anios.
-- Fuente: vista `viajes_validos`.
SELECT anio,
       mes,
       tipo_taxi,
       round(count(*) / count(DISTINCT CAST(pickup_datetime AS DATE))) AS viajes_por_dia
FROM viajes_validos
GROUP BY ALL
ORDER BY ALL;

-- name: 8.6_forma_pago_mensual
-- Objetivo: evolucion mensual de la forma de pago de los taxis amarillos.
-- Fuente: vista `viajes_validos`.
SELECT make_date(anio, mes, 1)                                                        AS periodo,
       round(100.0 * count_if(forma_pago = 'Tarjeta') / count(*), 1)                  AS pct_tarjeta,
       round(100.0 * count_if(forma_pago = 'Efectivo') / count(*), 1)                 AS pct_efectivo,
       round(100.0 * count_if(forma_pago = 'Flex fare / sin dato') / count(*), 1)     AS pct_flex_sin_dato
FROM viajes_validos
WHERE tipo_taxi = 'yellow'
GROUP BY ALL
ORDER BY ALL;

-- name: 8.6_cargo_cbd_mensual
-- Objetivo: desde cuando y en que proporcion de viajes se cobra el cargo por congestion de Manhattan (CBD).
-- Fuente: vista `viajes_validos`.
SELECT make_date(anio, mes, 1)                                            AS periodo,
       tipo_taxi,
       round(100.0 * count_if(cbd_congestion_fee > 0) / count(*), 1)    AS pct_con_cargo_cbd,
       round(avg(cbd_congestion_fee) FILTER (cbd_congestion_fee > 0), 2) AS cargo_cbd_usd
FROM viajes_validos
GROUP BY ALL
ORDER BY tipo_taxi, periodo;

-- name: 8.6_origen_solicitud
-- Objetivo: como se solicitan los viajes desde que existe la columna request_source (2026-06).
-- Fuente: vista `viajes`.
SELECT tipo_taxi,
       coalesce(request_source, 'NULL (sin dato)')                                  AS request_source,
       count(*)                                                                    AS viajes,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY tipo_taxi), 2)    AS pct_del_tipo
FROM viajes
WHERE make_date(anio, mes, 1) >= DATE '2026-06-01'
GROUP BY tipo_taxi, request_source
ORDER BY tipo_taxi, viajes DESC;
