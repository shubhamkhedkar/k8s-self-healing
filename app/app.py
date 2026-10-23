"""Tiny Flask app with health endpoints and failure switches for a self-healing demo."""
import os
import socket
import threading
import time

from flask import Flask, jsonify

app = Flask(__name__)

START_TIME = time.time()
STARTUP_DELAY = int(os.environ.get("STARTUP_DELAY_SECONDS", "10"))
state = {"healthy": True, "ready": True}


def started() -> bool:
    return time.time() - START_TIME >= STARTUP_DELAY


@app.get("/")
def index():
    return jsonify(message="Hello from the self-healing demo",
                   pod=socket.gethostname(),
                   uptime_seconds=round(time.time() - START_TIME, 1))


@app.get("/startupz")
def startupz():
    # Startup probe: fails until the simulated warm-up is done.
    if started():
        return jsonify(status="started"), 200
    return jsonify(status="starting"), 503


@app.get("/healthz")
def healthz():
    # Liveness probe: if this fails, the kubelet restarts the container.
    if state["healthy"]:
        return jsonify(status="ok"), 200
    return jsonify(status="unhealthy"), 500


@app.get("/readyz")
def readyz():
    # Readiness probe: if this fails, the pod is removed from Service endpoints.
    if started() and state["ready"]:
        return jsonify(status="ready"), 200
    return jsonify(status="not-ready"), 503


@app.post("/fail/liveness")
def fail_liveness():
    state["healthy"] = False
    return jsonify(result="liveness will now fail; expect a container restart"), 200


@app.post("/fail/readiness")
def fail_readiness():
    state["ready"] = False
    return jsonify(result="readiness will now fail; pod leaves the Service"), 200


@app.post("/recover/readiness")
def recover_readiness():
    state["ready"] = True
    return jsonify(result="readiness restored"), 200


@app.post("/crash")
def crash():
    # Hard-exit the process shortly after responding, simulating a crash.
    threading.Timer(0.5, lambda: os._exit(1)).start()
    return jsonify(result="crashing in 0.5s; expect restartPolicy to kick in"), 200


@app.get("/burn")
def burn():
    # Burn CPU for a few seconds to trigger the HorizontalPodAutoscaler.
    end = time.time() + 5
    x = 0
    while time.time() < end:
        x += 1
    return jsonify(result="burned cpu", iterations=x), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
