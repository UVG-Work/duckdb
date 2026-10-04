-- Vista `viajes_validos`: viajes de `viajes` que pasan las reglas de calidad
-- definidas a partir de la exploracion del Ejercicio 3
-- (notebooks/03_exploracion.ipynb, seccion 3.6).
--
-- Fuente: la vista/tabla `viajes` (Parquet directo o tabla materializada).
--
-- Reglas (se excluye el registro si no cumple alguna):
--   * la fecha de inicio pertenece al anio y mes del archivo de origen
--     (hay registros con fechas de 2001, 2008, etc.);
--   * la duracion es positiva y de a lo sumo 3 horas;
--   * la distancia es mayor que 0 y de a lo sumo 100 millas;
--   * la tarifa y el total son positivos;
--   * la velocidad promedio no supera 80 mph (distancia/duracion imposibles).
-- passenger_count NULL NO se excluye: afecta a ~25% de los registros
-- recientes y el resto de columnas del viaje es valido.
--
-- Columnas derivadas: duracion_min, velocidad_mph y forma_pago (etiqueta del
-- codigo payment_type segun el diccionario de datos de la TLC).
CREATE OR REPLACE VIEW viajes_validos AS
SELECT
    *,
    date_diff('second', pickup_datetime, dropoff_datetime) / 60.0 AS duracion_min,
    trip_distance / (date_diff('second', pickup_datetime, dropoff_datetime) / 3600.0) AS velocidad_mph,
    CASE payment_type
        WHEN 0 THEN 'Flex fare / sin dato'
        WHEN 1 THEN 'Tarjeta'
        WHEN 2 THEN 'Efectivo'
        WHEN 3 THEN 'Sin cargo'
        WHEN 4 THEN 'Disputa'
        ELSE 'Desconocido'
    END AS forma_pago
FROM viajes
WHERE year(pickup_datetime) = anio
  AND month(pickup_datetime) = mes
  AND dropoff_datetime > pickup_datetime
  AND dropoff_datetime <= pickup_datetime + INTERVAL 3 HOUR
  AND trip_distance > 0
  AND trip_distance <= 100
  AND fare_amount > 0
  AND total_amount > 0
  AND trip_distance / (date_diff('second', pickup_datetime, dropoff_datetime) / 3600.0) <= 80;
