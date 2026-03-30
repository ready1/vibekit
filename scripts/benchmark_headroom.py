#!/usr/bin/env python3
"""
benchmark_headroom.py — Measure headroom SmartCrusher token reduction.

Tests four payload types that represent real agent workloads:
  1. JSON tool output   — search/grep results, API responses
  2. Log stream         — application or server logs
  3. Code output        — file reads from a codebase
  4. RAG payload        — retrieved document chunks

Usage:
    python3 scripts/benchmark_headroom.py
    python3 scripts/benchmark_headroom.py --runs 5    # average over 5 runs
    python3 scripts/benchmark_headroom.py --json       # machine-readable output
"""

import argparse
import json
import statistics
import sys
import time

try:
    import tiktoken
except ImportError:
    sys.exit("Missing dependency: pip install tiktoken")

try:
    from headroom import SmartCrusher, SmartCrusherConfig
except ImportError:
    sys.exit("Missing dependency: pip install headroom-ai")


# ── Token counter ─────────────────────────────────────────────────────────────

_enc = tiktoken.get_encoding("cl100k_base")

def count_tokens(text: str) -> int:
    return len(_enc.encode(str(text)))


# ── Payload factories ─────────────────────────────────────────────────────────

def make_json_tool_output(n: int = 100) -> str:
    """Simulate a tool call returning N search/grep results."""
    return json.dumps([
        {
            "file": f"src/module_{i}.py",
            "line": i * 3,
            "content": f"def function_{i}(x, y, z):\n    result = x + y + z\n    return result * {i}",
            "imports": ["os", "sys", "json"],
            "class": f"Module{i}",
            "tests": [f"test_{i}_a", f"test_{i}_b"],
        }
        for i in range(n)
    ], indent=2)


def make_log_stream(n: int = 500) -> str:
    """Simulate N lines of application logs."""
    return "\n".join(
        f"2026-03-30 12:{i % 60:02d}:{i % 60:02d} INFO  [app.service] "
        f"request={i} user=user_{i % 10} status=200 latency={i % 50 + 5}ms bytes={i * 100}"
        for i in range(n)
    )


def make_code_output(n: int = 50) -> str:
    """Simulate reading a file with N functions."""
    return "\n".join(
        f"def compute_{i}(a, b, c, d):\n"
        f"    \"\"\"\n"
        f"    Compute result for step {i}.\n"
        f"    Args: a, b, c, d — numeric inputs\n"
        f"    \"\"\"\n"
        f"    x = a * b + c\n"
        f"    y = x / (d + 1)\n"
        f"    return round(y, 2)\n"
        for i in range(n)
    )


def make_rag_payload(n: int = 40) -> str:
    """Simulate N retrieved RAG document chunks."""
    return "\n\n".join(
        f"[Document {i} | score=0.{90 - i % 10}]\n"
        f"This document covers topic {i} in depth. Key points: point A, point B, point C. "
        f"Additional context: {' '.join(f'word_{j}' for j in range(30))}"
        for i in range(n)
    )


PAYLOADS = {
    "JSON tool output (100 items)": make_json_tool_output(100),
    "Log stream (500 lines)":       make_log_stream(500),
    "Code (50 functions)":          make_code_output(50),
    "RAG payload (40 docs)":        make_rag_payload(40),
}


# ── Benchmark ─────────────────────────────────────────────────────────────────

def run_benchmark(runs: int = 1) -> list[dict]:
    sc = SmartCrusher(SmartCrusherConfig())
    results = []

    for name, payload in PAYLOADS.items():
        raw_tokens = count_tokens(payload)
        timings = []

        for _ in range(runs):
            t0 = time.perf_counter()
            crush_result = sc.crush(payload)
            timings.append((time.perf_counter() - t0) * 1000)

        compressed = crush_result.compressed if crush_result.was_modified else payload
        comp_tokens = count_tokens(compressed)
        reduction = (1 - comp_tokens / raw_tokens) * 100 if raw_tokens > 0 else 0.0

        results.append({
            "payload":     name,
            "raw_tokens":  raw_tokens,
            "comp_tokens": comp_tokens,
            "reduction":   round(reduction, 1),
            "modified":    crush_result.was_modified,
            "strategy":    crush_result.strategy,
            "ms_avg":      round(statistics.mean(timings), 1),
            "ms_min":      round(min(timings), 1),
            "ms_max":      round(max(timings), 1),
        })

    return results


# ── Output ────────────────────────────────────────────────────────────────────

def print_table(results: list[dict]) -> None:
    print("\n=== headroom SmartCrusher Benchmark ===\n")
    hdr = f"{'Payload':<35} {'Raw tokens':>11} {'Comp tokens':>12} {'Reduction':>10} {'Avg ms':>8} {'Strategy'}"
    print(hdr)
    print("-" * len(hdr))

    for r in results:
        print(
            f"{r['payload']:<35} "
            f"{r['raw_tokens']:>11,} "
            f"{r['comp_tokens']:>12,} "
            f"{r['reduction']:>9.1f}% "
            f"{r['ms_avg']:>7.1f}  "
            f"{r['strategy']}"
        )

    reductions = [r["reduction"] for r in results]
    print(f"\nAverage reduction across all payloads: {statistics.mean(reductions):.1f}%")
    print(
        "\nNote: SmartCrusher targets JSON arrays. "
        "Non-JSON payloads (logs, code, text) pass through unchanged."
    )


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark headroom SmartCrusher")
    parser.add_argument("--runs", type=int, default=1, help="Number of timed runs to average (default: 1)")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    args = parser.parse_args()

    results = run_benchmark(runs=args.runs)

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print_table(results)


if __name__ == "__main__":
    main()
