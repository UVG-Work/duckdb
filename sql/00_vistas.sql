-- Vista `viajes`: une amarillos y verdes leyendo directamente los Parquet.
--
-- Fuente: data/raw/<tipo>/<anio>/*.parquet (todos los archivos descargados).
-- No importa datos: cada consulta sobre la vista lee los Parquet.
--
-- Transformaciones:
--   * El glob */*.parquet toma todos los anios y meses presentes, de modo que
--     un archivo nuevo se incorpora sin modificar esta consulta.
--   * union_by_name: los archivos no tienen el mismo esquema (por ejemplo,
--     request_source solo existe desde 2026-06); las columnas se alinean por
--     nombre y las ausentes quedan en NULL.
--   * Amarillos (tpep_) y verdes (lpep_) nombran distinto las fechas; se
--     renombran a pickup_datetime / dropoff_datetime para poder unirlos.
--   * tipo_taxi, anio y mes se derivan del archivo de origen.
CREATE OR REPLACE VIEW viajes AS
WITH crudo AS (
    SELECT 'yellow' AS tipo_taxi,
           * RENAME (tpep_pickup_datetime AS pickup_datetime,
                     tpep_dropoff_datetime AS dropoff_datetime)
    FROM read_parquet('data/raw/yellow/*/*.parquet', union_by_name = true, filename = true)
    UNION ALL BY NAME
    SELECT 'green' AS tipo_taxi,
           * RENAME (lpep_pickup_datetime AS pickup_datetime,
                     lpep_dropoff_datetime AS dropoff_datetime)
    FROM read_parquet('data/raw/green/*/*.parquet', union_by_name = true, filename = true)
)
SELECT
    * EXCLUDE (filename),
    CAST(regexp_extract(filename, '(\d{4})-\d{2}\.parquet$', 1) AS INTEGER) AS anio,
    CAST(regexp_extract(filename, '\d{4}-(\d{2})\.parquet$', 1) AS INTEGER) AS mes
FROM crudo;
