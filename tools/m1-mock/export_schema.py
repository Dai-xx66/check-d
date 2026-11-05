#!/usr/bin/env python3
"""Export the mock server's tools/list into docs/contracts/tools.candidate.json.

The exported file is a CANDIDATE schema: it mirrors what the mock implements so
the evidence runner can diff implementation against the published candidate.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "docs", "contracts", "tools.candidate.json"))


def main():
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    p = subprocess.Popen([sys.executable, os.path.join(HERE, "tool_server.py")],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         text=True, encoding="utf-8", env=env)
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                              "params": {"protocolVersion": "2024-11-05"}}) + "\n")
    p.stdin.flush()
    p.stdout.readline()
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}) + "\n")
    p.stdin.flush()
    tools = json.loads(p.stdout.readline())["result"]["tools"]
    p.stdin.close()
    p.wait(timeout=5)

    doc = {
        "$comment": "候选 Schema，未冻结；由 tools/m1-mock/export_schema.py 生成，"
                    "仅按 agent-api-v1.md v1 CANDIDATE 文本整理，等待 M0/B/C 评审确认。",
        "status": "candidate",
        "contract_version": "checkd.agent.v1",
        "source": "docs/contracts/agent-api-v1.md @ feat/m0-api-contract (503210c)",
        "extensions": ["request_approval", "get_approval_status"],
        "tools": tools,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    print(f"wrote {OUT}: {len(tools)} tools")


if __name__ == "__main__":
    main()