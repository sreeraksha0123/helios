#!/usr/bin/env python3
"""
Self-Healing Application with Health Endpoints
"""

from flask import Flask, jsonify, request
import os
import time
import logging
import random
from datetime import datetime

app = Flask(__name__)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Application state
app_state = {
    "healthy": True,
    "ready": True,
    "started": False,
    "startup_time": time.time(),
    "request_count": 0,
    "error_count": 0,
    "last_error": None
}

# Simulate slow startup
STARTUP_DELAY = int(os.getenv('STARTUP_DELAY', '10'))
app_state["startup_complete_at"] = time.time() + STARTUP_DELAY


@app.route('/')
def index():
    """Main endpoint"""
    app_state["request_count"] += 1
    
    # Simulate occasional errors
    if random.random() < 0.05:  # 5% error rate
        app_state["error_count"] += 1
        app_state["last_error"] = datetime.utcnow().isoformat()
        return jsonify({"error": "Simulated error"}), 500
    
    return jsonify({
        "message": "Self-Healing Application",
        "version": "1.0.0",
        "pod": os.getenv('POD_NAME', 'unknown'),
        "namespace": os.getenv('POD_NAMESPACE', 'unknown'),
        "uptime": int(time.time() - app_state["startup_time"]),
        "requests": app_state["request_count"]
    })


@app.route('/health')
def health():
    """
    Health endpoint for general health checks
    Returns 200 if application is functioning
    """
    if not app_state["healthy"]:
        logger.warning("Health check failed - application is unhealthy")
        return jsonify({
            "status": "unhealthy",
            "timestamp": datetime.utcnow().isoformat()
        }), 503
    
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "uptime": int(time.time() - app_state["startup_time"])
    })


@app.route('/ready')
def ready():
    """
    Readiness endpoint
    Returns 200 when application is ready to serve traffic
    """
    if not app_state["ready"]:
        logger.warning("Readiness check failed - application is not ready")
        return jsonify({
            "status": "not ready",
            "timestamp": datetime.utcnow().isoformat()
        }), 503
    
    return jsonify({
        "status": "ready",
        "timestamp": datetime.utcnow().isoformat()
    })


@app.route('/startup')
def startup():
    """
    Startup endpoint
    Returns 200 when application has completed initialization
    Used by startup probes
    """
    current_time = time.time()
    
    if current_time < app_state["startup_complete_at"]:
        remaining = int(app_state["startup_complete_at"] - current_time)
        logger.info(f"Startup probe - still initializing ({remaining}s remaining)")
        return jsonify({
            "status": "starting",
            "remaining_seconds": remaining,
            "timestamp": datetime.utcnow().isoformat()
        }), 503
    
    if not app_state["started"]:
        app_state["started"] = True
        logger.info("Application startup complete")
    
    return jsonify({
        "status": "started",
        "timestamp": datetime.utcnow().isoformat()
    })


@app.route('/live')
def live():
    """
    Liveness endpoint
    Returns 200 if the application process is running
    Kubernetes will restart the container if this fails
    """
    # Check if process is alive (this would catch deadlocks, infinite loops, etc.)
    return jsonify({
        "status": "alive",
        "timestamp": datetime.utcnow().isoformat(),
        "pid": os.getpid()
    })


@app.route('/metrics')
def metrics():
    """
    Metrics endpoint (Prometheus format)
    """
    uptime = int(time.time() - app_state["startup_time"])
    
    metrics_text = f"""# HELP app_requests_total Total number of requests
# TYPE app_requests_total counter
app_requests_total {app_state["request_count"]}

# HELP app_errors_total Total number of errors
# TYPE app_errors_total counter
app_errors_total {app_state["error_count"]}

# HELP app_uptime_seconds Application uptime in seconds
# TYPE app_uptime_seconds gauge
app_uptime_seconds {uptime}

# HELP app_healthy Application health status (1=healthy, 0=unhealthy)
# TYPE app_healthy gauge
app_healthy {1 if app_state["healthy"] else 0}

# HELP app_ready Application readiness status (1=ready, 0=not ready)
# TYPE app_ready gauge
app_ready {1 if app_state["ready"] else 0}
"""
    
    return metrics_text, 200, {'Content-Type': 'text/plain; charset=utf-8'}


@app.route('/admin/set-unhealthy', methods=['POST'])
def set_unhealthy():
    """Admin endpoint to simulate unhealthy state"""
    app_state["healthy"] = False
    logger.warning("Application set to unhealthy state")
    return jsonify({"message": "Application is now unhealthy"})


@app.route('/admin/set-healthy', methods=['POST'])
def set_healthy():
    """Admin endpoint to restore healthy state"""
    app_state["healthy"] = True
    logger.info("Application set to healthy state")
    return jsonify({"message": "Application is now healthy"})


@app.route('/admin/set-not-ready', methods=['POST'])
def set_not_ready():
    """Admin endpoint to simulate not ready state"""
    app_state["ready"] = False
    logger.warning("Application set to not ready state")
    return jsonify({"message": "Application is now not ready"})


@app.route('/admin/set-ready', methods=['POST'])
def set_ready():
    """Admin endpoint to restore ready state"""
    app_state["ready"] = True
    logger.info("Application set to ready state")
    return jsonify({"message": "Application is now ready"})


@app.route('/admin/crash', methods=['POST'])
def crash():
    """Admin endpoint to simulate application crash"""
    logger.error("Application crash initiated")
    os._exit(1)


@app.route('/status')
def status():
    """Detailed status endpoint"""
    return jsonify({
        "pod": {
            "name": os.getenv('POD_NAME', 'unknown'),
            "namespace": os.getenv('POD_NAMESPACE', 'unknown'),
            "ip": os.getenv('POD_IP', 'unknown')
        },
        "application": {
            "healthy": app_state["healthy"],
            "ready": app_state["ready"],
            "started": app_state["started"],
            "uptime": int(time.time() - app_state["startup_time"])
        },
        "metrics": {
            "requests": app_state["request_count"],
            "errors": app_state["error_count"],
            "last_error": app_state["last_error"]
        },
        "timestamp": datetime.utcnow().isoformat()
    })


if __name__ == '__main__':
    port = int(os.getenv('PORT', '8080'))
    logger.info(f"Starting self-healing application on port {port}")
    logger.info(f"Startup delay: {STARTUP_DELAY} seconds")
    
    app.run(
        host='0.0.0.0',
        port=port,
        debug=False
    )
