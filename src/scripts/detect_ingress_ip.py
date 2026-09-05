#!/usr/bin/env python3
"""Resolve the OCI Native IngressClass's actual Load Balancer address.

Ingress status can retain an old controller's address during a migration.
The class annotation identifies the authoritative OCI Load Balancer instead.
"""
import json
import os
import subprocess
import time

MAX_ATTEMPTS = 30
ENV = dict(os.environ, SUPPRESS_LABEL_WARNING="True", PYTHONWARNINGS="ignore")


def read_json(command):
    result = subprocess.run(command, env=ENV, capture_output=True, text=True)
    return json.loads(result.stdout) if result.returncode == 0 else {}


for attempt in range(MAX_ATTEMPTS):
    ingress_class = read_json(["kubectl", "get", "ingressclass", "oci-native", "-o", "json"])
    lb_id = ingress_class.get("metadata", {}).get("annotations", {}).get(
        "oci-native-ingress.oraclecloud.com/id"
    )
    if lb_id:
        lb = read_json(["oci", "lb", "load-balancer", "get", "--load-balancer-id", lb_id])
        for address in lb.get("data", {}).get("ip-addresses", []):
            if address.get("is-public") and address.get("ip-address"):
                print(json.dumps({"ip": address["ip-address"]}))
                raise SystemExit(0)
    time.sleep(10)

print(json.dumps({"error": "OCI Native Load Balancer IP not assigned after 30 attempts"}))
raise SystemExit(1)
