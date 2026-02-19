import os

import psycopg2
from fastapi import FastAPI

app = FastAPI()

DB_HOST = os.getenv("DB_HOST", "192.168.100.20")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "fastapi_db")
DB_USER = os.getenv("DB_USER", "fastapi_user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "fastapi_pass")


def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
    )


@app.get("/")
def read_root():
    return {"message": "HILLEL DevOps cource. Homework 16. FastAPI application."}


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.get("/pg_roles")
def get_pg_roles():
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin "
            "FROM pg_roles ORDER BY rolname"
        )
        columns = [desc[0] for desc in cur.description]
        rows = [dict(zip(columns, row)) for row in cur.fetchall()]
        cur.close()
        return {"pg_roles": rows}
    finally:
        conn.close()


@app.get("/pg_stats")
def get_pg_stats():
    conn = get_db_connection()
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT datname, numbackends, xact_commit, xact_rollback, "
            "blks_read, blks_hit, tup_returned, tup_fetched "
            "FROM pg_stat_database WHERE datname IS NOT NULL ORDER BY datname"
        )
        columns = [desc[0] for desc in cur.description]
        rows = [dict(zip(columns, row)) for row in cur.fetchall()]
        cur.close()
        return {"pg_stats": rows}
    finally:
        conn.close()
