"""Funciones compartidas por los notebooks y scripts del laboratorio."""

import re
import time
from pathlib import Path

import duckdb

RAIZ = Path(__file__).resolve().parent.parent
SQL = RAIZ / "sql"
TODOS = "*/*.parquet"   # patron de 00_vistas.sql: todos los anios y meses
DB = RAIZ / "data/processed/taxi.duckdb"
# DuckDB asume por defecto que puede usar el 80% de la RAM, pero la maquina
# virtual de Docker la comparte con Metabase (que tiene su propio DuckDB).
# Con este limite DuckDB usa disco temporal en vez de fallar por memoria.
MEMORIA = "6GB"


def consultas(archivo: str) -> dict[str, str]:
    """Consultas de sql/<archivo>, indexadas por su linea `-- name: <nombre>`."""
    texto = (SQL / archivo).read_text(encoding="utf-8")
    partes = re.split(r"^-- name: (\S+)\s*$", texto, flags=re.M)
    return {nombre: cuerpo.strip() for nombre, cuerpo in zip(partes[1::2], partes[2::2])}


def mostrar(con: duckdb.DuckDBPyConnection, sql: str):
    """Imprime `sql` y devuelve su resultado como DataFrame (uso en notebooks)."""
    print(sql)
    return con.sql(sql).df()


def conectar_parquet(patron: str = TODOS) -> duckdb.DuckDBPyConnection:
    """Conexion en memoria con las vistas `viajes` y `viajes_validos` sobre los Parquet.

    `patron` reemplaza a */*.parquet en 00_vistas.sql para leer solo una parte
    de los archivos, p. ej. "2026/*.parquet" o "2026/*_2026-01.parquet".
    """
    con = duckdb.connect(config={"memory_limit": MEMORIA})
    con.execute(f"SET file_search_path = '{RAIZ}'")   # rutas data/... relativas a la raiz
    con.execute((SQL / "00_vistas.sql").read_text(encoding="utf-8").replace(TODOS, patron))
    con.execute((SQL / "01_limpieza.sql").read_text(encoding="utf-8"))
    return con


def conectar_tabla(ruta_db: Path = DB) -> duckdb.DuckDBPyConnection:
    """Conexion de solo lectura a una base materializada (tabla `viajes`)."""
    return duckdb.connect(str(ruta_db), read_only=True, config={"memory_limit": MEMORIA})


def materializar(ruta_db: Path = DB, patron: str = TODOS) -> float:
    """Crea `ruta_db` con la tabla `viajes` y la vista `viajes_validos`.

    La tabla contiene exactamente lo que devuelve la vista Parquet `viajes`, de
    modo que las mismas consultas sirven para ambas estrategias. Devuelve los
    segundos que tardo la creacion de la tabla.
    """
    ruta_db.unlink(missing_ok=True)
    con = conectar_parquet(patron)
    con.execute(f"ATTACH '{ruta_db}' AS db")
    inicio = time.perf_counter()
    con.execute("CREATE TABLE db.viajes AS SELECT * FROM viajes")
    segundos = time.perf_counter() - inicio
    con.execute("USE db")
    con.execute((SQL / "01_limpieza.sql").read_text(encoding="utf-8"))
    con.close()
    return segundos
