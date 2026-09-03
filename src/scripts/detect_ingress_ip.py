#!/usr/bin/env python3
"""Detect the public IP of the NGINX Ingress Controller LoadBalancer service."""
import json
import os
import subprocess
import time

NAMESPACE = "ingress-nginx"
SERVICE_NAME = "nginx-ingress-ingress-nginx-controller"
MAX_ATTEMPTS = 30

env = dict(os.environ, SUPPRESS_LABEL_WARNING="True", PYTHONWARNINGS="ignore")

for attempt in range(MAX_ATTEMPTS):
    result = subprocess.run(
        [
            "kubectl",
            "get",
            "svc",
            "-n", NAMESPACE,
            SERVICE_NAME,
            "-o", "jsonpath={.status.loadBalancer.ingress[0].ip}",
        ],
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0 and result.stdout.strip():
        ip = result.stdout.strip()
        print(json.dumps({"ip": ip}))
        exit(0)
    time.sleep(10)

print(json.dumps({"error": "LoadBalancer IP not assigned after {} attempts".format(MAX_ATTEMPTS)}))
exit(1)
