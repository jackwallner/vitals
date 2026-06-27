#!/usr/bin/env python3
"""Minimal Astro MCP client for setup scripts."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from typing import Any

DEFAULT_MCP_URL = "http://127.0.0.1:8089/mcp"
DEFAULT_TIMEOUT = 120
ADD_KEYWORDS_TIMEOUT = 300


def call(
    mcp_url: str,
    tool: str,
    arguments: dict[str, Any],
    req_id: int = 1,
    timeout: int = DEFAULT_TIMEOUT,
) -> Any:
    payload = {
        "jsonrpc": "2.0",
        "id": req_id,
        "method": "tools/call",
        "params": {"name": tool, "arguments": arguments},
    }
    req = urllib.request.Request(
        mcp_url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = json.loads(resp.read())
    if "error" in body:
        raise RuntimeError(body["error"])
    content = body["result"]["content"][0]["text"]
    return json.loads(content) if content.strip().startswith(("[", "{")) else content


def ping(mcp_url: str = DEFAULT_MCP_URL) -> bool:
    try:
        payload = {
            "jsonrpc": "2.0",
            "id": 0,
            "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "astro_mcp.py", "version": "1.0"},
            },
        }
        req = urllib.request.Request(
            mcp_url,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status == 200
    except (urllib.error.URLError, TimeoutError, OSError):
        return False


def list_apps(mcp_url: str = DEFAULT_MCP_URL) -> list[dict[str, Any]]:
    return call(mcp_url, "list_apps", {})


def find_app_id(apps: list[dict[str, Any]], app_name: str) -> str | None:
    name_lower = app_name.lower()
    for app in apps:
        if app.get("name", "").lower() == name_lower:
            return str(app["appId"])
    for app in apps:
        if name_lower in app.get("name", "").lower() or app.get("name", "").lower() in name_lower:
            return str(app["appId"])
    return None


def _batch_added(result: Any) -> int:
    if isinstance(result, dict):
        if "results" in result:
            return sum(
                1
                for r in result["results"]
                if isinstance(r, dict) and r.get("success") and not r.get("skipped")
            )
        if "added" in result:
            return int(result.get("added") or 0)
        if "batches" in result:
            return sum(_batch_added(b) for b in result["batches"])
    return 0


def add_keywords(
    mcp_url: str,
    app_id: str,
    store: str,
    keywords: list[str],
    *,
    timeout: int = ADD_KEYWORDS_TIMEOUT,
    retries: int = 3,
) -> dict[str, Any]:
    """Add keywords with retries; falls back to one-by-one if a batch fails."""
    results: list[Any] = []
    added_total = 0
    batch_size = 3

    for i in range(0, len(keywords), batch_size):
        batch = keywords[i : i + batch_size]
        last_err: Exception | None = None
        for attempt in range(retries):
            try:
                r = call(
                    mcp_url,
                    "add_keywords",
                    {"appId": app_id, "store": store, "keywords": batch},
                    req_id=100 + i + attempt,
                    timeout=timeout,
                )
                results.append(r)
                added_total += _batch_added(r)
                last_err = None
                break
            except (urllib.error.HTTPError, TimeoutError, OSError, RuntimeError) as e:
                last_err = e
                time.sleep(8 * (attempt + 1))

        if last_err is not None:
            for kw in batch:
                for attempt in range(retries):
                    try:
                        r = call(
                            mcp_url,
                            "add_keywords",
                            {"appId": app_id, "store": store, "keywords": [kw]},
                            req_id=500 + i + attempt,
                            timeout=timeout,
                        )
                        results.append(r)
                        added_total += _batch_added(r)
                        break
                    except (urllib.error.HTTPError, TimeoutError, OSError, RuntimeError):
                        time.sleep(5 * (attempt + 1))
                time.sleep(1.0)

    return {"batches": results, "added": added_total}


def remove_keywords(
    mcp_url: str,
    app_id: str,
    store: str,
    keywords: list[str],
) -> dict[str, Any]:
    results: list[Any] = []
    for i in range(0, len(keywords), 100):
        batch = keywords[i : i + 100]
        results.append(
            call(
                mcp_url,
                "remove_keywords",
                {"appId": app_id, "store": store, "keywords": batch},
                req_id=200 + i,
                timeout=ADD_KEYWORDS_TIMEOUT,
            )
        )
    return {"batches": results}


def ensure_tag(mcp_url: str, name: str, color: str) -> None:
    try:
        call(mcp_url, "manage_tag", {"action": "create", "name": name, "color": color})
    except RuntimeError:
        pass


def tag_keyword(mcp_url: str, app_id: str, store: str, keyword: str, tag: str) -> None:
    call(
        mcp_url,
        "set_keyword_tag",
        {"appId": app_id, "store": store, "keyword": keyword, "tag": tag, "action": "add"},
    )
    time.sleep(0.4)
