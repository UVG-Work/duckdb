-- Ejercicio 5: validacion de la incorporacion de 2024.
-- Resultados en notebooks/05_incorporacion_2024.ipynb.

-- name: 5.5_archivos_por_anio
-- Objetivo: verificar que archivos hay por tipo de taxi y anio (2026 debe conservarse, 2024 debe estar completo).
-- Fuente: nombres de archivo de data/raw/*/*/*.parquet (glob).
SELECT regexp_extract(file, 'raw/(\w+)/', 1)                         AS tipo_taxi,
       CAST(regexp_extract(file, 'raw/\w+/(\d{4})/', 1) AS INTEGER)  AS anio,
       count(*)                                                      AS archivos,
       min(regexp_extract(file, '(\d{4}-\d{2})\.parquet$', 1))       AS primer_mes,
       max(regexp_extract(file, '(\d{4}-\d{2})\.parquet$', 1))       AS ultimo_mes
FROM glob('data/raw/*/*/*.parquet')
WHERE anio IN (2024, 2026)
GROUP BY ALL
ORDER BY tipo_taxi, anio;

-- name: 5.5_archivos_legibles
-- Objetivo: comprobar que cada archivo de 2024 es un Parquet legible y con registros.
-- Un archivo truncado no tiene pie (footer) valido y esta consulta fallaria.
-- Fuente: metadatos de data/raw/*/2024/*.parquet (parquet_file_metadata).
SELECT regexp_extract(file_name, 'raw/(\w+)/', 1)  AS tipo_taxi,
       count(*)                                    AS archivos_legibles,
       min(num_rows)                               AS registros_min_por_archivo,
       sum(num_rows)::BIGINT                       AS registros
FROM parquet_file_metadata('data/raw/*/2024/*.parquet')
GROUP BY tipo_taxi
ORDER BY tipo_taxi;

-- name: 5.6_resumen_por_anio
-- Objetivo: consultar 2024 y 2026 juntos con la misma vista, sin cambios en ella.
-- Fuente: vista `viajes_validos` sobre data/raw/*/{2024,2026}/*.parquet.
SELECT anio,
       tipo_taxi,
       count(DISTINCT mes)                                   AS meses,
       count(*)                                              AS viajes,
       round(avg(trip_distance), 2)                          AS distancia_prom_mi,
       round(avg(total_amount), 2)                           AS total_prom,
       round(100.0 * count_if(forma_pago = 'Tarjeta') / count(*), 1) AS pct_tarjeta
FROM viajes_validos
WHERE anio IN (2024, 2026)
GROUP BY anio, tipo_taxi
ORDER BY tipo_taxi, anio;

-- name: 5.6_mismo_mes_2024_vs_2026
-- Objetivo: comparar los meses que existen en ambos anios (enero-agosto).
-- Fuente: vista `viajes_validos`, anios 2024 y 2026.
SELECT tipo_taxi,
       mes,
       count_if(anio = 2024)::BIGINT                         AS viajes_2024,
       count_if(anio = 2026)::BIGINT                         AS viajes_2026,
       round(100.0 * (viajes_2026 - viajes_2024) / viajes_2024, 1) AS variacion_pct
FROM viajes_validos
WHERE anio IN (2024, 2026)
  AND mes IN (SELECT DISTINCT mes FROM viajes WHERE anio = 2026)
GROUP BY tipo_taxi, mes
ORDER BY tipo_taxi, mes;

-- name: 5.6_columnas_por_anio
-- Objetivo: ver como union_by_name resuelve las diferencias de esquema entre anios.
-- Fuente: vista `viajes`, anios 2024 y 2026.
SELECT anio,
       tipo_taxi,
       count(*)                                                     AS registros,
       round(100.0 * count(cbd_congestion_fee) / count(*), 1)       AS pct_con_cbd_congestion_fee,
       round(100.0 * count(request_source) / count(*), 1)           AS pct_con_request_source,
       round(100.0 * count(passenger_count) / count(*), 1)          AS pct_con_passenger_count
FROM viajes
WHERE anio IN (2024, 2026)
GROUP BY anio, tipo_taxi
ORDER BY tipo_taxi, anio;
