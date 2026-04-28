#!/usr/bin/env python3
"""
M8 MCP Integration Test Suite
Exercises every new tool added in M8 against the running odin-lint-mcp server.
"""

import json
import os
import subprocess
import sys
import time

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REPO_ROOT   = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER_BIN  = os.path.join(REPO_ROOT, "artifacts", "macos-arm64", "olt-mcp")
FAIL_FIXTURE = os.path.join(REPO_ROOT, "tests", "C002_COR_POINTER", "c002_fixture_fail.odin")
PASS_FIXTURE = os.path.join(REPO_ROOT, "tests", "C001_COR_MEMORY",  "c001_pass.odin")
TEST_DIR     = os.path.join(REPO_ROOT, "tests", "C001_COR_MEMORY")
SRC_DIR      = os.path.join(REPO_ROOT, "src", "core")
SYMBOLS_JSON = os.path.join(REPO_ROOT, ".codegraph", "symbols.json")

# ---------------------------------------------------------------------------
# MCP wire protocol helpers
# ---------------------------------------------------------------------------

def _frame(msg: dict) -> bytes:
    body = json.dumps(msg).encode()
    header = f"Content-Length: {len(body)}\r\n\r\n".encode()
    return header + body

def _read_response(proc: subprocess.Popen) -> dict:
    """Read one Content-Length-framed JSON-RPC response from the server."""
    header = b""
    while not header.endswith(b"\r\n\r\n"):
        ch = proc.stdout.read(1)
        if not ch:
            raise EOFError("server closed stdout while reading header")
        header += ch

    content_length = 0
    for line in header.split(b"\r\n"):
        if line.lower().startswith(b"content-length:"):
            content_length = int(line.split(b":")[1].strip())

    if content_length == 0:
        raise ValueError("missing or zero Content-Length")

    body = proc.stdout.read(content_length)
    return json.loads(body)


class MCPClient:
    """Minimal synchronous MCP client that wraps a subprocess."""

    def __init__(self, binary: str):
        self._proc = subprocess.Popen(
            [binary],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            cwd=REPO_ROOT,
        )
        self._id = 0
        self._handshake()

    def _handshake(self):
        resp = self.call("initialize", {
            "protocolVersion": "2024-11-05",
            "clientInfo": {"name": "m8-test", "version": "1.0"},
            "capabilities": {},
        })
        assert "result" in resp, f"initialize failed: {resp}"
        # send initialized notification (no response expected)
        self._proc.stdin.write(_frame({"jsonrpc": "2.0", "method": "initialized", "params": {}}))
        self._proc.stdin.flush()

    def call(self, method: str, params: dict) -> dict:
        self._id += 1
        msg = {"jsonrpc": "2.0", "id": self._id, "method": method, "params": params}
        self._proc.stdin.write(_frame(msg))
        self._proc.stdin.flush()
        return _read_response(self._proc)

    def tool(self, name: str, args: dict) -> dict:
        """Call a tool and return the parsed result dict (or raise on error)."""
        resp = self.call("tools/call", {"name": name, "arguments": args})
        assert "result" in resp, f"RPC error calling {name}: {resp}"
        text = resp["result"]["content"][0]["text"]
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            # Tool returned a plain-text error — wrap it so callers can inspect it
            return {"_raw": text, "_json_error": True}

    def close(self):
        try:
            self._proc.stdin.close()
            self._proc.wait(timeout=5)
        except Exception:
            self._proc.kill()


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

PASS = 0
FAIL = 0

def check(label: str, condition: bool, detail: str = ""):
    global PASS, FAIL
    if condition:
        print(f"  ✅ PASS: {label}")
        PASS += 1
    else:
        print(f"  ❌ FAIL: {label}{' — ' + detail if detail else ''}")
        FAIL += 1

def section(title: str):
    print(f"\n── {title} ──")


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_error_class_in_lint_file(client: MCPClient):
    section("Gap 1 — error_class in lint_file output")
    result = client.tool("lint_file", {"path": FAIL_FIXTURE})
    check("lint_file returns a list", isinstance(result, list))
    if result:
        d = result[0]
        check("diagnostic has error_class field",    "error_class" in d)
        check("diagnostic has rule_id field",         "rule_id" in d)
        check("error_class is non-empty string",      isinstance(d.get("error_class"), str) and d["error_class"] != "")
        check("error_class matches known taxonomy",
              d["error_class"] in {
                  "correctness_memory_leak", "correctness_double_free", "ffi_resource_leak",
                  "migration_deprecated_import", "migration_deprecated_fmt",
                  "style_naming_proc", "style_naming_type", "correctness_context_integrity",
              },
              f"got '{d.get('error_class')}'")
        # C001 violation in fail fixture → correctness_memory_leak
        c001 = next((x for x in result if x.get("rule_id") == "C001"), None)
        check("C001 maps to correctness_memory_leak",
              c001 is not None and c001.get("error_class") == "correctness_memory_leak")
        c002 = next((x for x in result if x.get("rule_id") == "C002"), None)
        check("C002 maps to correctness_double_free",
              c002 is not None and c002.get("error_class") == "correctness_double_free")


def test_lint_workspace(client: MCPClient):
    section("Gap 4 — lint_workspace")
    result = client.tool("lint_workspace", {"path": TEST_DIR})
    check("lint_workspace returns a list",         isinstance(result, list))
    check("lint_workspace finds at least 1 diag",  len(result) > 0,
          f"got {len(result)} diagnostics")
    if result:
        d = result[0]
        check("workspace diag has file field",       "file" in d)
        check("workspace diag has error_class",      "error_class" in d)
        check("workspace diag has rule_id",          "rule_id" in d)
        check("workspace diag has line",             "line" in d)
        # All results should come from files inside TEST_DIR
        all_in_dir = all(r.get("file", "").startswith(TEST_DIR) for r in result)
        check("all diagnostics are inside the target dir", all_in_dir)

    # Rule filter: only C001
    result_filtered = client.tool("lint_workspace", {"path": TEST_DIR, "rules": "C001"})
    only_c001 = all(r.get("rule_id") == "C001" for r in result_filtered)
    check("rule filter restricts to C001 only",    only_c001,
          f"found other rules: {set(r.get('rule_id') for r in result_filtered) - {'C001'}}")


def test_list_rules(client: MCPClient):
    section("Gap 5 — list_rules")
    result = client.tool("list_rules", {})
    check("list_rules returns object with 'rules' key", isinstance(result, dict) and "rules" in result)
    rules = result.get("rules", [])
    check("at least 10 rules returned", len(rules) >= 10, f"got {len(rules)}")

    # Required fields on every rule
    required_fields = {"id", "tier", "error_class", "description", "fix_hint", "enabled_by_default"}
    all_have_fields = all(required_fields <= set(r.keys()) for r in rules)
    check("every rule has all required fields", all_have_fields)

    ids = [r["id"] for r in rules]
    for expected_id in ["C001", "C002", "C003", "C007", "C011", "C101", "B001"]:
        check(f"rule {expected_id} is present", expected_id in ids)

    # enabled_by_default is bool
    all_bool = all(isinstance(r.get("enabled_by_default"), bool) for r in rules)
    check("enabled_by_default is always bool", all_bool)

    # opt-in rules are correctly marked disabled
    c019 = next((r for r in rules if r["id"] == "C019"), None)
    check("C019 is marked enabled_by_default=false",
          c019 is not None and c019["enabled_by_default"] is False)

    c001 = next((r for r in rules if r["id"] == "C001"), None)
    check("C001 is marked enabled_by_default=true",
          c001 is not None and c001["enabled_by_default"] is True)

    # M9: C201 must be present
    c201 = next((r for r in rules if r["id"] == "C201"), None)
    check("C201 is present in catalog",
          c201 is not None,
          f"ids: {ids}")
    check("C201 error_class is correctness_unchecked_result",
          c201 is not None and c201.get("error_class") == "correctness_unchecked_result",
          f"got: {c201.get('error_class') if c201 else 'missing'}")
    check("C201 is marked enabled_by_default=true",
          c201 is not None and c201["enabled_by_default"] is True)


def test_schema_version_in_symbols_json(client: MCPClient):
    section("Gap 3 — schema_version in symbols.json")
    # Run export_symbols on the src/core directory to generate symbols.json
    result = client.tool("export_symbols", {"path": SRC_DIR})
    check("export_symbols returns valid JSON",  not result.get("_json_error"), f"raw: {result.get('_raw','')[:120]}")
    check("export_symbols reports nodes > 0",   result.get("nodes", 0) > 0, f"result: {result}")

    # Read the produced symbols.json
    if not os.path.exists(SYMBOLS_JSON):
        check("symbols.json was created", False, f"not found at {SYMBOLS_JSON}")
        return
    with open(SYMBOLS_JSON) as f:
        symbols = json.load(f)
    check("symbols.json has schema_version key",  "schema_version" in symbols,
          f"keys: {list(symbols.keys())}")
    check("schema_version is odin-lint-symbols/1.1",
          symbols.get("schema_version") == "odin-lint-symbols/1.1",
          f"got: {symbols.get('schema_version')}")
    check("old 'schema' key is gone",  "schema" not in symbols)


def test_get_callers_callees(client: MCPClient):
    section("LSP parity — get_callers / get_callees")
    DB_PATH = os.path.join(REPO_ROOT, ".codegraph", "odin_lint_graph.db")

    # Confirm get_symbol works first (simpler lookup, same DB path)
    sym = client.tool("get_symbol", {"symbol": "dedupDiagnostics", "db_path": DB_PATH})
    check("get_symbol finds dedupDiagnostics",
          not sym.get("_json_error") and "name" in sym,
          f"raw: {sym.get('_raw','')[:80]}")

    # get_callers
    CALLEE_PROCS = ["dedupDiagnostics", "emit_or_collect", "run_query"]
    found_callers = False
    for proc_name in CALLEE_PROCS:
        result = client.tool("get_callers", {"proc_name": proc_name, "db_path": DB_PATH})
        if "caller_count" in result:
            check(f"get_callers({proc_name}) returns caller_count",  "caller_count" in result)
            check(f"get_callers({proc_name}) callers is a list",     isinstance(result.get("callers"), list))
            check(f"get_callers({proc_name}) has ≥1 caller",        result["caller_count"] > 0,
                  f"got {result['caller_count']}")
            if result["callers"]:
                c = result["callers"][0]
                for f in ["name", "file", "line"]:
                    check(f"caller entry has '{f}'", f in c)
            found_callers = True
            break
    if not found_callers:
        check("get_callers: found at least one known proc", False,
              f"tried: {CALLEE_PROCS}")

    # get_callees
    CALLER_PROCS = ["analyze_content", "c001Matcher", "naming_scm_run"]
    found_callees = False
    for proc_name in CALLER_PROCS:
        result = client.tool("get_callees", {"proc_name": proc_name, "db_path": DB_PATH})
        if "callee_count" in result:
            check(f"get_callees({proc_name}) returns callee_count",  "callee_count" in result)
            check(f"get_callees({proc_name}) callees is a list",     isinstance(result.get("callees"), list))
            if result["callees"]:
                c = result["callees"][0]
                for f in ["name", "file", "line"]:
                    check(f"callee entry has '{f}'", f in c)
            found_callees = True
            break
    if not found_callees:
        check("get_callees: found at least one known proc", False,
              f"tried: {CALLER_PROCS}")


def test_run_odin_check(client: MCPClient):
    section("Gap 2 (revised) — run_odin_check")
    # Run on a well-formed single-package directory
    result = client.tool("run_odin_check", {"path": SRC_DIR})
    check("run_odin_check returns 'ok' field",          "ok" in result)
    check("run_odin_check returns 'exit_code' field",   "exit_code" in result)
    check("run_odin_check returns 'error_count' field", "error_count" in result)
    check("run_odin_check returns 'diagnostics' list",  isinstance(result.get("diagnostics"), list))
    check("run_odin_check returns 'raw_output' string", isinstance(result.get("raw_output"), str))

    # Each diagnostic must have the required fields
    diags = result.get("diagnostics", [])
    if diags:
        d = diags[0]
        for field in ["file", "line", "column", "level", "message"]:
            check(f"odin_check diagnostic has '{field}'", field in d)
        check("level is error/warning/note",
              d.get("level") in {"error", "warning", "note"})

    # Run on a non-existent path — should return error response (tool returns is_error=true)
    bad = client.tool("run_odin_check", {"path": "/nonexistent/path"})
    check("run_odin_check handles bad path gracefully",
          isinstance(bad, dict),
          f"got: {bad}")

    # M9: odin_path parameter — explicit path to the odin binary
    import shutil
    odin_exe = shutil.which("odin")
    if odin_exe:
        result_with_path = client.tool("run_odin_check", {
            "path": SRC_DIR,
            "odin_path": odin_exe,
        })
        check("run_odin_check respects explicit odin_path",
              "ok" in result_with_path,
              f"got: {result_with_path}")
    else:
        check("run_odin_check odin_path param (odin not in PATH, skipped)", True)

    # M9: bogus odin_path — should fail gracefully (not crash)
    result_bad_path = client.tool("run_odin_check", {
        "path": SRC_DIR,
        "odin_path": "/nonexistent/odin",
    })
    check("run_odin_check handles bad odin_path gracefully",
          isinstance(result_bad_path, dict),
          f"got: {result_bad_path}")


def test_tools_list(client: MCPClient):
    section("tools/list — all M8 tools are registered")
    resp = client.call("tools/list", {})
    tool_names = {t["name"] for t in resp["result"]["tools"]}
    for expected in [
        "lint_file", "lint_snippet", "lint_fix", "run_lint_denoise",
        "lint_workspace", "list_rules", "run_odin_check",
        "get_symbol", "export_symbols", "get_dna_context",
        "get_impact_radius", "find_allocators", "find_all_references",
        "rename_symbol", "get_callers", "get_callees",
    ]:
        check(f"tool '{expected}' is registered", expected in tool_names)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if not os.path.exists(SERVER_BIN):
        print(f"❌ Server binary not found: {SERVER_BIN}")
        print("   Run ./scripts/build_mcp.sh first.")
        sys.exit(1)

    print("🧪 M8 MCP Integration Test Suite")
    print("=" * 50)

    client = MCPClient(SERVER_BIN)
    try:
        test_tools_list(client)
        test_error_class_in_lint_file(client)
        test_lint_workspace(client)
        test_list_rules(client)
        test_schema_version_in_symbols_json(client)
        test_get_callers_callees(client)
        test_run_odin_check(client)
    finally:
        client.close()

    print(f"\n{'=' * 50}")
    print(f"M8 MCP Test Summary")
    print(f"{'=' * 50}")
    print(f"Passed: {PASS}")
    print(f"Failed: {FAIL}")
    print()
    if FAIL == 0:
        print("🎉 All M8 MCP tests passed!")
        sys.exit(0)
    else:
        print(f"❌ {FAIL} test(s) failed.")
        sys.exit(1)


if __name__ == "__main__":
    main()
