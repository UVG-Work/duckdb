-- Ejercicio 6: consultas representativas del analisis usadas en el benchmark.
-- Se ejecutan sin cambios sobre las dos estrategias (scripts/benchmark.py):
--   * Parquet directo: `viajes` es una vista sobre read_parquet (sql/00_vistas.sql);
--   * tabla DuckDB:    `viajes` es una tabla materializada con el mismo contenido.
-- En ambos casos `viajes_validos` es la vista de sql/01_limpieza.sql.
-- No filtran por anio: cada consulta recorre todos los datos de la escala medida.

-- name: B1_conteo
-- Conteo de registros (en Parquet puede responderse con los metadatos).
SELECT count(*) FROM viajes;

-- name: B2_viajes_por_mes
-- Serie mensual por tipo de taxi (Ejercicio 4, pregunta 1).
SELECT anio, mes, tipo_taxi, count(*) AS viajes
FROM viajes_validos
GROUP BY ALL
ORDER BY ALL;

-- name: B3_dia_hora
-- Demanda por dia de la semana y hora (Ejercicio 4, pregunta 2).
SELECT isodow(pickup_datetime) AS dia_semana, hour(pickup_datetime) AS hora, count(*) AS viajes
FROM viajes_validos
GROUP BY ALL
ORDER BY ALL;

-- name: B4_forma_pago
-- Forma de pago y propina (Ejercicio 4, pregunta 6).
SELECT tipo_taxi, forma_pago, count(*) AS viajes,
       avg(tip_amount) AS propina_prom,
       sum(tip_amount) / sum(fare_amount) AS propina_sobre_tarifa
FROM viajes_validos
GROUP BY ALL
ORDER BY ALL;

-- name: B5_percentiles
-- Percentiles exactos de distancia y duracion (Ejercicio 4, pregunta 3).
SELECT tipo_taxi,
       quantile_cont(trip_distance, [0.25, 0.5, 0.75]) AS distancia,
       quantile_cont(duracion_min, [0.25, 0.5, 0.75])  AS duracion
FROM viajes_validos
GROUP BY ALL
ORDER BY ALL;

-- name: B6_zonas_top
-- Cinco zonas de origen con mas viajes por tipo (Ejercicio 4, pregunta 5).
SELECT tipo_taxi, PULocationID, count(*) AS viajes
FROM viajes_validos
GROUP BY tipo_taxi, PULocationID
QUALIFY row_number() OVER (PARTITION BY tipo_taxi ORDER BY count(*) DESC) <= 5
ORDER BY tipo_taxi, viajes DESC;

-- name: B7_filtro_selectivo
-- Consulta selectiva: viajes desde JFK (zona 132) en la primera semana de cada mes.
SELECT anio, mes, count(*) AS viajes, avg(total_amount) AS total_prom
FROM viajes
WHERE PULocationID = 132
  AND day(pickup_datetime) <= 7
GROUP BY ALL
ORDER BY ALL;
