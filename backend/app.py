import os
from flask import Flask, jsonify, request
import psycopg2
from psycopg2.extras import RealDictCursor


app = Flask(__name__)


def database_config():
    return {
        "host": os.environ["DB_HOST"],
        "port": int(os.getenv("DB_PORT", "5432")),
        "dbname": os.environ["DB_NAME"],
        "user": os.environ["DB_USER"],
        "password": os.environ["DB_PASSWORD"],
    }


def get_connection():
    return psycopg2.connect(
        **database_config(),
        cursor_factory=RealDictCursor,
    )


def initialize_database():
    connection = get_connection()

    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS tasks (
                    id SERIAL PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    completed BOOLEAN NOT NULL DEFAULT FALSE,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                """
            )

        connection.commit()
    finally:
        connection.close()


@app.get("/health")
def health():
    try:
        connection = get_connection()

        with connection.cursor() as cursor:
            cursor.execute("SELECT 1;")
            cursor.fetchone()

        connection.close()

        return jsonify(
            {
                "status": "healthy",
                "database": "connected",
            }
        ), 200

    except Exception:
        app.logger.exception("Database health check failed")

        return jsonify(
            {
                "status": "unhealthy",
                "database": "disconnected",
            }
        ), 503


@app.get("/api/tasks")
def list_tasks():
    connection = get_connection()

    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT id, title, completed, created_at
                FROM tasks
                ORDER BY id DESC;
                """
            )

            tasks = cursor.fetchall()

        return jsonify(tasks), 200
    finally:
        connection.close()


@app.post("/api/tasks")
def create_task():
    payload = request.get_json(silent=True) or {}
    title = str(payload.get("title", "")).strip()

    if not title:
        return jsonify({"error": "Task title is required"}), 400

    if len(title) > 255:
        return jsonify({"error": "Task title is too long"}), 400

    connection = get_connection()

    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO tasks (title)
                VALUES (%s)
                RETURNING id, title, completed, created_at;
                """,
                (title,),
            )

            task = cursor.fetchone()

        connection.commit()
        return jsonify(task), 201
    finally:
        connection.close()


@app.patch("/api/tasks/<int:task_id>")
def update_task(task_id):
    payload = request.get_json(silent=True) or {}

    if "completed" not in payload:
        return jsonify({"error": "The completed value is required"}), 400

    completed = payload["completed"]

    if not isinstance(completed, bool):
        return jsonify({"error": "Completed must be true or false"}), 400

    connection = get_connection()

    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                UPDATE tasks
                SET completed = %s
                WHERE id = %s
                RETURNING id, title, completed, created_at;
                """,
                (completed, task_id),
            )

            task = cursor.fetchone()

        connection.commit()

        if task is None:
            return jsonify({"error": "Task not found"}), 404

        return jsonify(task), 200
    finally:
        connection.close()


@app.delete("/api/tasks/<int:task_id>")
def delete_task(task_id):
    connection = get_connection()

    try:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                DELETE FROM tasks
                WHERE id = %s
                RETURNING id;
                """,
                (task_id,),
            )

            deleted_task = cursor.fetchone()

        connection.commit()

        if deleted_task is None:
            return jsonify({"error": "Task not found"}), 404

        return jsonify({"message": "Task deleted"}), 200
    finally:
        connection.close()


initialize_database()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
