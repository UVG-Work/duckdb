#!/usr/bin/env python3
"""Materializa todos los Parquet descargados en data/processed/taxi.duckdb.

Crea la tabla `viajes` (mismo contenido que la vista de sql/00_vistas.sql) y
la vista `viajes_validos` (sql/01_limpieza.sql). Es la base que usa Metabase.
Se reconstruye completa en cada ejecucion, de modo que incluye cualquier anio
nuevo descargado.

Metabase mantiene abierto el archivo, por lo que debe detenerse antes:
    docker compose stop metabase
    docker compose exec lab python scripts/materializar.py
    docker compose start metabase
"""

from lab import DB, RAIZ, conectar_tabla, materializar

if __name__ == "__main__":
    segundos = materializar()
    con = conectar_tabla()
    print(f"{DB.relative_to(RAIZ)} creada en {segundos:.1f} s")
    print(con.sql("SELECT anio, tipo_taxi, count(*) AS registros FROM viajes GROUP BY ALL ORDER BY ALL"))
