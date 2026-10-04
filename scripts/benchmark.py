#!/usr/bin/env python3
"""Benchmark: consultas sobre Parquet directo vs tabla materializada en DuckDB.

Para cada escala de datos:
  1. abre una conexion en memoria con las vistas sobre esos Parquet;
  2. materializa los mismos archivos en data/processed/benchmark.duckdb
     (registrando cuanto tarda);
  3. ejecuta cada consulta de sql/06_benchmark.sql REPETICIONES veces con
     cada estrategia y registra la mediana del tiempo.

Resultados en docs/benchmark.csv. El archivo benchmark.duckdb se borra al final.

Uso:
    python scripts/benchmark.py
"""

import csv
import statistics
import time

import duckdb

from lab import RAIZ, TODOS, conectar_parquet, conectar_tabla, consultas, materializar

# nombre de la escala -> archivos dentro de data/raw/<tipo>/
ESCALAS = {
    "1 mes (2026-01)": "2026/*_2026-01.parquet",
    "1 anio (2024)": "2024/*.parquet",
    "todos los anios": TODOS,
}
REPETICIONES = 5
DB = RAIZ / "data/processed/benchmark.duckdb"
SALIDA = RAIZ / "docs/benchmark.csv"


def medir(con: duckdb.DuckDBPyConnection, sql: str) -> float:
    """Mediana en segundos de REPETICIONES ejecuciones completas de `sql`."""
    tiempos = []
    for _ in range(REPETICIONES):
        inicio = time.perf_counter()
        con.execute(sql).fetchall()
        tiempos.append(time.perf_counter() - inicio)
    return statistics.median(tiempos)


def main() -> None:
    filas = []
    for escala, patron in ESCALAS.items():
        print(f"\n=== {escala} ===")
        segundos_materializar = materializar(DB, patron)
        parquet = conectar_parquet(patron)
        tabla = conectar_tabla(DB)

        registros = tabla.sql("SELECT count(*) FROM viajes").fetchone()[0]
        mb_parquet = sum(p.stat().st_size for p in (RAIZ / "data/raw").glob(f"*/{patron}")) / 2**20
        mb_duckdb = DB.stat().st_size / 2**20
        print(f"  {registros:,} registros | Parquet {mb_parquet:,.0f} MiB | DuckDB {mb_duckdb:,.0f} MiB"
              f" | materializacion {segundos_materializar:.1f} s")

        for nombre, sql in consultas("06_benchmark.sql").items():
            t_parquet = medir(parquet, sql)
            t_tabla = medir(tabla, sql)
            print(f"  {nombre:<20} parquet {t_parquet:8.3f} s   tabla {t_tabla:8.3f} s"
                  f"   x{t_parquet / t_tabla:5.1f}")
            filas.append({
                "escala": escala,
                "registros": registros,
                "mib_parquet": round(mb_parquet, 1),
                "mib_duckdb": round(mb_duckdb, 1),
                "materializacion_s": round(segundos_materializar, 2),
                "consulta": nombre,
                "parquet_s": round(t_parquet, 4),
                "tabla_s": round(t_tabla, 4),
                "aceleracion": round(t_parquet / t_tabla, 2),
            })

        parquet.close()
        tabla.close()

    DB.unlink(missing_ok=True)
    with SALIDA.open("w", newline="", encoding="utf-8") as archivo:
        escritor = csv.DictWriter(archivo, fieldnames=filas[0].keys())
        escritor.writeheader()
        escritor.writerows(filas)
    print(f"\nResultados en {SALIDA.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
