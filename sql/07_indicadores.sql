-- Ejercicio 7: indicadores del tablero de Metabase.
-- Fuente: data/processed/taxi.duckdb (tabla `viajes` y vista `viajes_validos`),
-- conectada a Metabase en modo solo lectura. scripts/metabase_dashboard.py crea
-- una pregunta de Metabase por cada consulta de este archivo.
-- Ninguna consulta fija anios: al materializar un anio nuevo, el tablero lo
-- incluye sin cambios. Justificacion e interpretacion en docs/ejercicio7.md.

-- name: K1_viajes
-- Pregunta: cuantos viajes validos hay en el periodo disponible?
SELECT count(*) AS viajes
FROM viajes_validos;

-- name: K2_ingreso
-- Pregunta: cuanto dinero se cobro en total (millones de USD)?
SELECT round(sum(total_amount) / 1e6, 1) AS millones_usd
FROM viajes_validos;

-- name: K3_ticket
-- Pregunta: cuanto paga en promedio un pasajero por viaje?
SELECT round(avg(total_amount), 2) AS ticket_promedio_usd
FROM viajes_validos;

-- name: I1_viajes_mensuales
-- Pregunta 1: como evoluciona la cantidad de viajes por mes y tipo de taxi?
SELECT make_date(anio, mes, 1) AS periodo,
       tipo_taxi,
       count(*)                AS viajes
FROM viajes_validos
GROUP BY ALL
ORDER BY ALL;

-- name: I2_participacion_verdes
-- Pregunta 2: que participacion tienen los taxis verdes y esta cambiando?
SELECT make_date(anio, mes, 1)                                      AS periodo,
       round(100.0 * count_if(tipo_taxi = 'green') / count(*), 2)   AS pct_verdes
FROM viajes_validos
GROUP BY ALL
ORDER BY ALL;

-- name: I3_ticket_promedio
-- Pregunta 3: cuanto paga en promedio un pasajero por viaje y como evoluciona?
SELECT make_date(anio, mes, 1)       AS periodo,
       tipo_taxi,
       round(avg(total_amount), 2)   AS ticket_promedio_usd
FROM viajes_validos
GROUP BY ALL
ORDER BY ALL;

-- name: I4_composicion_cobro
-- Pregunta 4: que parte de lo cobrado son recargos (congestion, CBD, aeropuerto) frente a tarifa y propina?
UNPIVOT (
    SELECT CAST(anio AS VARCHAR)                         AS anio,
           sum(fare_amount)                              AS "Tarifa",
           sum(tip_amount)                               AS "Propina",
           sum(tolls_amount)                             AS "Peajes",
           sum(congestion_surcharge)                     AS "Recargo congestion",
           sum(cbd_congestion_fee)                       AS "Cargo CBD",
           sum(Airport_fee)                              AS "Cargo aeropuerto",
           sum(extra + mta_tax + improvement_surcharge)  AS "Otros recargos"
    FROM viajes_validos
    GROUP BY anio
)
ON COLUMNS(* EXCLUDE (anio))
INTO NAME componente VALUE usd
ORDER BY anio;

-- name: I5_forma_pago
-- Pregunta 5: como se reparten las formas de pago y como cambian entre anios?
SELECT CAST(anio AS VARCHAR) AS anio,
       forma_pago,
       count(*)              AS viajes
FROM viajes_validos
GROUP BY ALL
ORDER BY ALL;

-- name: I6_propina_tarjeta
-- Pregunta 6: que porcentaje de la tarifa dejan de propina quienes pagan con tarjeta?
SELECT make_date(anio, mes, 1)                                AS periodo,
       tipo_taxi,
       round(100.0 * sum(tip_amount) / sum(fare_amount), 2)   AS propina_pct_tarifa
FROM viajes_validos
WHERE forma_pago = 'Tarjeta'
GROUP BY ALL
ORDER BY ALL;

-- name: I7_demanda_hora
-- Pregunta 7: a que horas se concentra la demanda en dias laborables y en fines de semana?
SELECT hour(pickup_datetime)                                                      AS hora,
       CASE WHEN isodow(pickup_datetime) >= 6 THEN 'Fin de semana' ELSE 'Laborable' END AS tipo_dia,
       round(count(*) / count(DISTINCT CAST(pickup_datetime AS DATE)))           AS viajes_promedio
FROM viajes_validos
GROUP BY ALL
ORDER BY ALL;

-- name: I8_velocidad_hora
-- Pregunta 8: como cambia la velocidad de los viajes a lo largo del dia y entre anios?
SELECT hour(pickup_datetime)            AS hora,
       CAST(anio AS VARCHAR)            AS anio,
       round(median(velocidad_mph), 2)  AS velocidad_mediana_mph
FROM viajes_validos
GROUP BY ALL
ORDER BY ALL;

-- name: I9_aeropuertos
-- Pregunta 9: que proporcion de los viajes empieza o termina en un aeropuerto?
-- Zonas 1 (Newark), 132 (JFK) y 138 (LaGuardia) del TLC Taxi Zone Lookup.
SELECT make_date(anio, mes, 1)  AS periodo,
       tipo_taxi,
       round(100.0 * count_if(PULocationID IN (1, 132, 138) OR DOLocationID IN (1, 132, 138))
             / count(*), 2)     AS pct_aeropuerto
FROM viajes_validos
GROUP BY ALL
ORDER BY ALL;

-- name: I10_calidad
-- Pregunta 10: que proporcion de los registros publicados es utilizable y cuantos llegan incompletos?
SELECT make_date(t.anio, t.mes, 1)                          AS periodo,
       round(100.0 * v.validos / t.registros, 2)            AS pct_validos,
       round(100.0 * t.sin_pasajeros / t.registros, 2)      AS pct_sin_passenger_count
FROM (SELECT anio, mes, count(*) AS registros, count(*) - count(passenger_count) AS sin_pasajeros
      FROM viajes GROUP BY anio, mes) t
JOIN (SELECT anio, mes, count(*) AS validos
      FROM viajes_validos GROUP BY anio, mes) v USING (anio, mes)
ORDER BY periodo;
