#!/usr/bin/env python3
"""Crea (o actualiza) en Metabase el tablero de indicadores del Ejercicio 7.

Mediante la API de Metabase:
  1. completa la configuracion inicial (usuario administrador) si hace falta;
  2. registra data/processed/taxi.duckdb como base DuckDB de solo lectura;
  3. crea una pregunta SQL por cada consulta de sql/07_indicadores.sql;
  4. las organiza en el tablero "Taxis NYC - Indicadores" y le crea un
     enlace publico (solo accesible desde esta maquina, ver docker-compose.yml).
Si el tablero ya existe, reemplaza sus preguntas por las actuales (las
anteriores se archivan), por lo que puede ejecutarse de nuevo despues de
agregar datos o cambiar las consultas.

Requiere haber ejecutado antes scripts/materializar.py.

Uso (dentro del contenedor lab, con Metabase levantado):
    python scripts/metabase_dashboard.py
Credenciales de Metabase: variables MB_EMAIL y MB_PASSWORD
(por defecto admin@example.com / Lab8-DuckDB-2026).
"""

import os
import re
import sys
import time

import requests

from lab import consultas

URL = os.environ.get("MB_URL", "http://metabase:3000")
EMAIL = os.environ.get("MB_EMAIL", "admin@example.com")
PASSWORD = os.environ.get("MB_PASSWORD", "Lab8-DuckDB-2026")
BASE = "Taxis NYC (DuckDB)"
RUTA_DB = "/workspace/data/processed/taxi.duckdb"   # ruta dentro del contenedor de Metabase
TABLERO = "Taxis NYC - Indicadores"


def grafico(dimensiones: list, metricas: list, apilado: str | None = None) -> dict:
    ajustes = {"graph.dimensions": dimensiones, "graph.metrics": metricas}
    if apilado:
        ajustes["stackable.stack_type"] = apilado
    return ajustes


# consulta -> (titulo, visualizacion, ajustes, (columna, fila, ancho, alto) en la grilla de 24 columnas)
TARJETAS = {
    "K1_viajes": ("Viajes validos", "scalar", {}, (0, 0, 8, 3)),
    "K2_ingreso": ("Ingreso total (millones USD)", "scalar", {}, (8, 0, 8, 3)),
    "K3_ticket": ("Ticket promedio (USD)", "scalar", {}, (16, 0, 8, 3)),
    "I1_viajes_mensuales": ("I1 Viajes por mes (verdes en el eje derecho)",
                            "line", grafico(["periodo", "tipo_taxi"], ["viajes"])
                            | {"series_settings": {"green": {"axis": "right"}}}, (0, 3, 12, 6)),
    "I2_participacion_verdes": ("I2 Participacion de taxis verdes (%)",
                                "line", grafico(["periodo"], ["pct_verdes"]), (12, 3, 12, 6)),
    "I3_ticket_promedio": ("I3 Ticket promedio por viaje (USD)",
                           "line", grafico(["periodo", "tipo_taxi"], ["ticket_promedio_usd"]), (0, 9, 12, 6)),
    "I6_propina_tarjeta": ("I6 Propina con tarjeta (% de la tarifa)",
                           "line", grafico(["periodo", "tipo_taxi"], ["propina_pct_tarifa"]), (12, 9, 12, 6)),
    "I4_composicion_cobro": ("I4 Composicion de lo cobrado",
                             "bar", grafico(["anio", "componente"], ["usd"], "normalized"), (0, 15, 12, 6)),
    "I5_forma_pago": ("I5 Forma de pago",
                      "bar", grafico(["anio", "forma_pago"], ["viajes"], "normalized"), (12, 15, 12, 6)),
    "I7_demanda_hora": ("I7 Viajes promedio por hora",
                        "line", grafico(["hora", "tipo_dia"], ["viajes_promedio"]), (0, 21, 12, 6)),
    "I8_velocidad_hora": ("I8 Velocidad mediana por hora (mph)",
                          "line", grafico(["hora", "anio"], ["velocidad_mediana_mph"]), (12, 21, 12, 6)),
    "I9_aeropuertos": ("I9 Viajes de/hacia aeropuertos (%)",
                       "line", grafico(["periodo", "tipo_taxi"], ["pct_aeropuerto"]), (0, 27, 12, 6)),
    "I10_calidad": ("I10 Calidad de los registros (%)",
                    "line", grafico(["periodo"], ["pct_validos", "pct_sin_passenger_count"]), (12, 27, 12, 6)),
}

sesion = requests.Session()


def api(metodo: str, ruta: str, **kwargs):
    respuesta = sesion.request(metodo, f"{URL}/api/{ruta}", timeout=300, **kwargs)
    if not respuesta.ok:
        sys.exit(f"{metodo} /api/{ruta} -> {respuesta.status_code}: {respuesta.text[:500]}")
    return respuesta.json() if respuesta.content else None


def esperar_metabase() -> None:
    for _ in range(60):
        try:
            if sesion.get(f"{URL}/api/health", timeout=5).ok:
                return
        except requests.RequestException:
            pass
        time.sleep(5)
    sys.exit(f"Metabase no responde en {URL}")


def main() -> None:
    esperar_metabase()

    propiedades = api("GET", "session/properties")
    if not propiedades.get("has-user-setup"):
        api("POST", "setup", json={
            "token": propiedades["setup-token"],
            "user": {"email": EMAIL, "password": PASSWORD, "first_name": "Lab", "last_name": "8",
                     "site_name": "Lab 8 DuckDB"},
            "prefs": {"site_name": "Lab 8 DuckDB", "site_locale": "es", "allow_tracking": False},
        })
    sesion.headers["X-Metabase-Session"] = api(
        "POST", "session", json={"username": EMAIL, "password": PASSWORD})["id"]

    base = next((b for b in api("GET", "database")["data"] if b["name"] == BASE), None)
    datos_base = {
        "engine": "duckdb",
        "name": BASE,
        # memory_limit: Metabase comparte la maquina virtual de Docker con el contenedor lab
        "details": {"database_file": RUTA_DB, "read_only": True, "old_implicit_casting": True,
                    "memory_limit": "4GB"},
    }
    if base is None:
        base = api("POST", "database", json=datos_base)
    else:
        api("PUT", f"database/{base['id']}", json=datos_base)

    tablero = next((d for d in api("GET", "collection/root/items", params={"models": "dashboard"})["data"]
                    if d["name"] == TABLERO), None)
    if tablero is None:
        tablero = api("POST", "dashboard", json={
            "name": TABLERO,
            "description": "Indicadores de viajes de taxis amarillos y verdes de NYC (Lab 8 - DuckDB).",
        })
    anteriores = [t["card_id"] for t in api("GET", f"dashboard/{tablero['id']}")["dashcards"] if t["card_id"]]

    ids = {}
    for nombre, sql in consultas("07_indicadores.sql").items():
        titulo, visualizacion, ajustes, _ = TARJETAS[nombre]
        ids[nombre] = api("POST", "card", json={
            "name": titulo,
            "description": re.search(r"^-- Pregunta[^:]*: (.*)$", sql, re.M).group(1),
            "display": visualizacion,
            "visualization_settings": ajustes,
            "dataset_query": {"type": "native", "database": base["id"], "native": {"query": sql}},
        })["id"]
        print(f"  pregunta {ids[nombre]:>3}  {titulo}")

    api("PUT", f"dashboard/{tablero['id']}", json={"dashcards": [
        {"id": -i, "card_id": ids[nombre], "col": col, "row": fila, "size_x": ancho, "size_y": alto,
         "parameter_mappings": [], "visualization_settings": {}}
        for i, (nombre, (_, _, _, (col, fila, ancho, alto))) in enumerate(TARJETAS.items(), start=1)
    ]})
    for card_id in anteriores:   # las preguntas de una ejecucion previa se reemplazan
        api("PUT", f"card/{card_id}", json={"archived": True})

    api("PUT", "setting/enable-public-sharing", json={"value": True})
    uuid = api("POST", f"dashboard/{tablero['id']}/public_link")["uuid"]
    print(f"\nTablero:         http://localhost:3000/dashboard/{tablero['id']}")
    print(f"Enlace publico:  http://localhost:3000/public/dashboard/{uuid}")


if __name__ == "__main__":
    main()
