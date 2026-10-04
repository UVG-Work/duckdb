-- Ejercicio 4: analisis exploratorio de 2026.
-- Fuente: vista `viajes_validos` (sql/01_limpieza.sql) sobre los Parquet; la
-- ultima consulta usa `viajes` porque busca justamente registros inconsistentes.
-- El filtro anio = 2026 fija el alcance del ejercicio aunque existan otros anios.
-- Preguntas, resultados e interpretacion en notebooks/04_analisis_exploratorio.ipynb.

-- name: 4.P1_viajes_por_mes
-- Pregunta 1: como varia la cantidad de viajes por mes y tipo de taxi?
PIVOT (SELECT mes, tipo_taxi FROM viajes_validos WHERE anio = 2026)
ON tipo_taxi USING count(*)
GROUP BY mes
ORDER BY mes;

-- name: 4.P2_dia_hora
-- Pregunta 2: en que dias de la semana y horas se concentra la demanda?
-- Promedio de viajes por hora calendario (dia de la semana x hora), ambos tipos.
SELECT isodow(pickup_datetime)                              AS dia_semana,  -- 1 = lunes
       hour(pickup_datetime)                                AS hora,
       count(*) / count(DISTINCT CAST(pickup_datetime AS DATE)) AS viajes_promedio
FROM viajes_validos
WHERE anio = 2026
GROUP BY ALL
ORDER BY dia_semana, hora;

-- name: 4.P3_caracteristicas
-- Pregunta 3: cual es la distancia, duracion, velocidad y ocupacion tipica de un viaje?
SELECT tipo_taxi,
       count(*)                                         AS viajes,
       round(quantile_cont(trip_distance, 0.25), 2)     AS distancia_p25_mi,
       round(quantile_cont(trip_distance, 0.50), 2)     AS distancia_p50_mi,
       round(quantile_cont(trip_distance, 0.75), 2)     AS distancia_p75_mi,
       round(quantile_cont(duracion_min, 0.50), 1)      AS duracion_p50_min,
       round(quantile_cont(velocidad_mph, 0.50), 1)     AS velocidad_p50_mph,
       round(avg(passenger_count), 2)                   AS pasajeros_promedio,
       round(100.0 * count_if(passenger_count = 1) / count(passenger_count), 1) AS pct_un_pasajero
FROM viajes_validos
WHERE anio = 2026
GROUP BY tipo_taxi
ORDER BY tipo_taxi;

-- name: 4.P4_amarillo_vs_verde
-- Pregunta 4: en que se diferencian los viajes de taxis amarillos y verdes?
SELECT tipo_taxi,
       count(*)                                                       AS viajes,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2)             AS pct_viajes,
       round(avg(trip_distance), 2)                                   AS distancia_prom_mi,
       round(avg(fare_amount), 2)                                     AS tarifa_prom,
       round(avg(total_amount), 2)                                    AS total_prom,
       round(sum(fare_amount) / sum(trip_distance), 2)                AS tarifa_por_milla,
       round(100.0 * count_if(RatecodeID IN (2, 3)) / count(*), 2)    AS pct_tarifa_aeropuerto,
       round(100.0 * count_if(cbd_congestion_fee > 0) / count(*), 2)  AS pct_cobro_cbd,
       round(100.0 * count_if(trip_type = 2) / count(*), 2)           AS pct_despachados
FROM viajes_validos
WHERE anio = 2026
GROUP BY tipo_taxi
ORDER BY tipo_taxi;

-- name: 4.P5_zonas_origen
-- Pregunta 5: desde que zonas (PULocationID, TLC Taxi Zones) se originan los viajes de cada tipo?
SELECT tipo_taxi,
       PULocationID                                                         AS zona_origen,
       count(*)                                                             AS viajes,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY tipo_taxi), 2) AS pct_del_tipo
FROM viajes_validos
WHERE anio = 2026
GROUP BY tipo_taxi, PULocationID
QUALIFY row_number() OVER (PARTITION BY tipo_taxi ORDER BY count(*) DESC) <= 5
ORDER BY tipo_taxi, viajes DESC;

-- name: 4.P6_forma_pago
-- Pregunta 6: como pagan los pasajeros y como cambia la propina segun la forma de pago?
SELECT tipo_taxi,
       forma_pago,
       count(*)                                                                 AS viajes,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY tipo_taxi), 2) AS pct_del_tipo,
       round(avg(tip_amount), 2)                                                AS propina_prom,
       round(100.0 * sum(tip_amount) / sum(fare_amount), 1)                     AS propina_pct_tarifa
FROM viajes_validos
WHERE anio = 2026
GROUP BY tipo_taxi, forma_pago
ORDER BY tipo_taxi, viajes DESC;

-- name: 4.P7_composicion_total
-- Pregunta 7: que parte de lo cobrado corresponde a tarifa, propina, peajes y recargos?
SELECT tipo_taxi,
       round(sum(total_amount) / 1e6, 1)                                         AS total_millones_usd,
       round(100.0 * sum(fare_amount) / sum(total_amount), 1)                    AS pct_tarifa,
       round(100.0 * sum(tip_amount) / sum(total_amount), 1)                     AS pct_propina,
       round(100.0 * sum(tolls_amount) / sum(total_amount), 1)                   AS pct_peajes,
       round(100.0 * sum(congestion_surcharge) / sum(total_amount), 1)           AS pct_congestion,
       round(100.0 * sum(cbd_congestion_fee) / sum(total_amount), 1)            AS pct_cbd,
       round(100.0 * coalesce(sum(Airport_fee), 0) / sum(total_amount), 1)       AS pct_aeropuerto,
       round(100.0 * sum(extra + mta_tax + improvement_surcharge) / sum(total_amount), 1) AS pct_otros
FROM viajes_validos
WHERE anio = 2026
GROUP BY tipo_taxi
ORDER BY tipo_taxi;

-- name: 4.P8_distribucion_distancia
-- Pregunta 8: como se distribuye la distancia de los viajes? (intervalos de 1 milla, ultimo abierto)
SELECT least(floor(trip_distance), 20)::INTEGER                                   AS milla_desde,
       tipo_taxi,
       count(*)                                                                    AS viajes,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY tipo_taxi), 2)    AS pct_del_tipo
FROM viajes_validos
WHERE anio = 2026
GROUP BY milla_desde, tipo_taxi
ORDER BY tipo_taxi, milla_desde;

-- name: 4.P8_distribucion_total
-- Pregunta 8: como se distribuye el monto total pagado? (intervalos de 5 USD, ultimo abierto)
SELECT least(floor(total_amount / 5) * 5, 150)::INTEGER                            AS usd_desde,
       tipo_taxi,
       count(*)                                                                    AS viajes,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY tipo_taxi), 2)    AS pct_del_tipo
FROM viajes_validos
WHERE anio = 2026
GROUP BY usd_desde, tipo_taxi
ORDER BY tipo_taxi, usd_desde;

-- name: 4.P9_atipicos_iqr
-- Pregunta 9: cuantos viajes validos tienen un total atipico segun la regla de Tukey (Q3 + 1.5 IQR)?
WITH cuartiles AS (
    SELECT tipo_taxi,
           quantile_cont(total_amount, 0.25) AS q1,
           quantile_cont(total_amount, 0.75) AS q3
    FROM viajes_validos
    WHERE anio = 2026
    GROUP BY tipo_taxi
)
SELECT v.tipo_taxi,
       round(q1, 2)                                                          AS q1,
       round(q3, 2)                                                          AS q3,
       round(q3 + 1.5 * (q3 - q1), 2)                                        AS limite_superior,
       count_if(total_amount > q3 + 1.5 * (q3 - q1))::BIGINT                 AS atipicos,
       round(100.0 * count_if(total_amount > q3 + 1.5 * (q3 - q1)) / count(*), 2) AS pct_atipicos,
       round(100.0 * count_if(total_amount > q3 + 1.5 * (q3 - q1) AND RatecodeID IN (2, 3, 4))
             / nullif(count_if(total_amount > q3 + 1.5 * (q3 - q1)), 0), 1)  AS pct_atipicos_aeropuerto_o_fuera_nyc
FROM viajes_validos v
JOIN cuartiles USING (tipo_taxi)
WHERE anio = 2026
GROUP BY ALL
ORDER BY v.tipo_taxi;

-- name: 4.P10_inconsistencias
-- Pregunta 10: que inconsistencias internas tienen los registros originales?
-- Fuente: vista `viajes` (sin limpiar), anio 2026.
SELECT tipo_taxi,
       count(*)                                                              AS registros,
       count_if(abs(total_amount - (fare_amount + extra + mta_tax + tip_amount + tolls_amount
                + improvement_surcharge + coalesce(congestion_surcharge, 0)
                + coalesce(Airport_fee, 0) + coalesce(cbd_congestion_fee, 0))) > 0.01)::BIGINT
                                                                             AS total_no_cuadra,
       count_if(trip_distance = 0 AND fare_amount > 0 AND PULocationID <> DOLocationID)::BIGINT
                                                                             AS distancia_cero_con_zonas_distintas,
       count_if(tip_amount > 0 AND payment_type = 2)::BIGINT                 AS propina_en_efectivo_registrada,
       count_if(RatecodeID = 99)::BIGINT                                     AS ratecode_desconocido
FROM viajes
WHERE anio = 2026
GROUP BY tipo_taxi
ORDER BY tipo_taxi;

-- name: 4.P10_detalle_por_proveedor
-- Pregunta 10 (detalle): de que proveedor y forma de pago vienen los totales que no cuadran?
-- diferencia = total_amount - suma de componentes. Fuente: vista `viajes`, amarillos 2026.
SELECT VendorID,
       payment_type,
       round(total_amount - (fare_amount + extra + mta_tax + tip_amount + tolls_amount
             + improvement_surcharge + coalesce(congestion_surcharge, 0)
             + coalesce(Airport_fee, 0) + coalesce(cbd_congestion_fee, 0)), 2) AS diferencia,
       round(avg(extra), 2)                                                     AS extra_prom,
       count(*)                                                                 AS registros
FROM viajes
WHERE anio = 2026 AND tipo_taxi = 'yellow'
GROUP BY ALL
ORDER BY registros DESC
LIMIT 8;
