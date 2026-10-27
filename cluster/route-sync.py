#!/usr/bin/env python3
"""Sync OpenShift Route objects to Ingress (nginx) so oc expose works on Kind."""
from __future__ import annotations

import json
import os
import ssl
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

TOKEN = open("/var/run/secrets/kubernetes.io/serviceaccount/token", encoding="utf-8").read().strip()
CA = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
HOST = os.environ["KUBERNETES_SERVICE_HOST"]
PORT = os.environ["KUBERNETES_SERVICE_PORT"]
DOMAIN = os.environ.get("ROUTE_DOMAIN", "apps.localtest.me")
INGRESS_CLASS = os.environ.get("INGRESS_CLASS", "nginx")
BASE = f"https://{HOST}:{PORT}"
MANAGED = "route-sync"

ctx = ssl.create_default_context(cafile=CA)


def log(msg: str) -> None:
    print(msg, flush=True)


def call(method: str, path: str, body=None, content_type: str = "application/json"):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    if body is not None:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw.decode()) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        try:
            parsed = json.loads(raw.decode()) if raw else {}
        except Exception:
            parsed = {"raw": raw.decode("utf-8", "replace")}
        return exc.code, parsed


def service_port(ns: str, name: str, target) -> dict | None:
    code, svc = call("GET", f"/api/v1/namespaces/{ns}/services/{name}")
    if code != 200:
        log(f"service {ns}/{name} not found ({code})")
        return None
    ports = svc.get("spec", {}).get("ports") or []
    if not ports:
        return None
    if target is None:
        port = ports[0]
    else:
        port = None
        for item in ports:
            if str(item.get("port")) == str(target) or str(item.get("targetPort")) == str(target) or item.get("name") == str(target):
                port = item
                break
        if port is None:
            port = ports[0]
    if port.get("name"):
        return {"name": port["name"]}
    return {"number": int(port["port"])}


def desired_host(route: dict) -> str:
    spec = route.get("spec") or {}
    host = spec.get("host")
    if host:
        return host
    meta = route["metadata"]
    return f"{meta['name']}-{meta['namespace']}.{DOMAIN}"


def ingress_name(route: dict) -> str:
    return f"route-{route['metadata']['name']}"


def ingress_body(route: dict, host: str, port: dict) -> dict:
    meta = route["metadata"]
    spec = route.get("spec") or {}
    path = spec.get("path") or "/"
    return {
        "apiVersion": "networking.k8s.io/v1",
        "kind": "Ingress",
        "metadata": {
            "name": ingress_name(route),
            "namespace": meta["namespace"],
            "labels": {
                "app.kubernetes.io/managed-by": MANAGED,
                "route.openshift.io/name": meta["name"],
            },
            "ownerReferences": [
                {
                    "apiVersion": "route.openshift.io/v1",
                    "kind": "Route",
                    "name": meta["name"],
                    "uid": meta["uid"],
                    "controller": True,
                    "blockOwnerDeletion": True,
                }
            ],
        },
        "spec": {
            "ingressClassName": INGRESS_CLASS,
            "rules": [
                {
                    "host": host,
                    "http": {
                        "paths": [
                            {
                                "path": path,
                                "pathType": "Prefix",
                                "backend": {
                                    "service": {
                                        "name": spec["to"]["name"],
                                        "port": port,
                                    }
                                },
                            }
                        ]
                    },
                }
            ],
        },
    }


def admit(route: dict, host: str) -> None:
    ns = route["metadata"]["namespace"]
    name = route["metadata"]["name"]
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    body = {
        "status": {
            "ingress": [
                {
                    "host": host,
                    "routerName": "nginx",
                    "wildcardPolicy": spec_wildcard(route),
                    "conditions": [
                        {
                            "type": "Admitted",
                            "status": "True",
                            "lastTransitionTime": now,
                        }
                    ],
                }
            ]
        }
    }
    code, resp = call(
        "PATCH",
        f"/apis/route.openshift.io/v1/namespaces/{ns}/routes/{name}/status",
        body,
        "application/merge-patch+json",
    )
    if code not in (200, 201):
        log(f"status patch {ns}/{name} -> {code} {resp}")


def spec_wildcard(route: dict) -> str:
    return (route.get("spec") or {}).get("wildcardPolicy") or "None"


def sync_once() -> None:
    code, data = call("GET", "/apis/route.openshift.io/v1/routes")
    if code != 200:
        log(f"list routes failed: {code} {data}")
        return
    for route in data.get("items") or []:
        meta = route["metadata"]
        spec = route.get("spec") or {}
        to = spec.get("to") or {}
        if to.get("kind", "Service") not in ("Service", ""):
            continue
        if to.get("weight") == 0:
            continue
        svc = to.get("name")
        if not svc:
            continue
        ns = meta["namespace"]
        name = meta["name"]
        target = (spec.get("port") or {}).get("targetPort")
        port = service_port(ns, svc, target)
        if port is None:
            continue
        host = desired_host(route)
        body = ingress_body(route, host, port)
        ing_name = ingress_name(route)
        get_code, existing = call("GET", f"/apis/networking.k8s.io/v1/namespaces/{ns}/ingresses/{ing_name}")
        if get_code == 404:
            post_code, post_resp = call("POST", f"/apis/networking.k8s.io/v1/namespaces/{ns}/ingresses", body)
            log(f"create ingress {ns}/{ing_name} host={host} -> {post_code}")
            if post_code not in (200, 201, 409):
                log(str(post_resp))
                continue
        elif get_code == 200:
            body["metadata"]["resourceVersion"] = existing["metadata"]["resourceVersion"]
            put_code, put_resp = call("PUT", f"/apis/networking.k8s.io/v1/namespaces/{ns}/ingresses/{ing_name}", body)
            if put_code not in (200, 201):
                log(f"update ingress {ns}/{ing_name} -> {put_code} {put_resp}")
        else:
            log(f"get ingress {ns}/{ing_name} -> {get_code}")
            continue
        current = (((route.get("status") or {}).get("ingress") or [{}])[0]).get("host")
        admitted = False
        for ing in (route.get("status") or {}).get("ingress") or []:
            for cond in ing.get("conditions") or []:
                if cond.get("type") == "Admitted" and cond.get("status") == "True":
                    admitted = True
        if current != host or not admitted:
            admit(route, host)


def main() -> None:
    log(f"route-sync watching routes, domain=*.{DOMAIN}")
    while True:
        try:
            sync_once()
        except Exception as exc:
            log(f"sync error: {exc}")
        time.sleep(5)


if __name__ == "__main__":
    main()
