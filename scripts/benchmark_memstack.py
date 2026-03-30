#!/usr/bin/env python3
"""
benchmark_memstack.py — Measure memstack SQLite DB operation latency.

Tests four core operations:
  1. init      — create / reset the DB
  2. add-session  — write session records
  3. add-insight  — write text insights (the main memory unit)
  4. search    — keyword search across stored insights

Usage:
    python3 scripts/benchmark_memstack.py
    python3 scripts/benchmark_memstack.py --sessions 20 --insights 100
    python3 scripts/benchmark_memstack.py --json
"""

import argparse
import json
import os
import statistics
import subprocess
import sys
import time
from pathlib import Path

# ── Locate memstack ───────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).parent
ROOT_DIR   = SCRIPT_DIR.parent
MEMSTACK_DIR = ROOT_DIR / "memstack"

if not MEMSTACK_DIR.exists():
    sys.exit(
        f"memstack not found at {MEMSTACK_DIR}\n"
        "Run ./scripts/install.sh first."
    )

DB_SCRIPT = MEMSTACK_DIR / "db" / "memstack-db.py"
if not DB_SCRIPT.exists():
    sys.exit(f"DB script not found: {DB_SCRIPT}")


# ── DB helper ─────────────────────────────────────────────────────────────────

def ms_run(cmd: list[str]) -> dict:
    """Run a memstack-db.py command and return parsed JSON output."""
    result = subprocess.run(
        [sys.executable, str(DB_SCRIPT)] + cmd,
        capture_output=True,
        text=True,
        cwd=str(MEMSTACK_DIR),
    )
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {"error": result.stderr.strip() or result.stdout.strip()}


def time_op(fn, *args, **kwargs) -> tuple[any, float]:
    """Return (result, elapsed_ms)."""
    t0 = time.perf_counter()
    result = fn(*args, **kwargs)
    return result, (time.perf_counter() - t0) * 1000


# ── Benchmark ─────────────────────────────────────────────────────────────────

def run_benchmark(n_sessions: int = 10, n_insights: int = 50) -> dict:
    results = {}

    # 1. init
    _, ms = time_op(ms_run, ["init"])
    results["init"] = {"runs": 1, "total_ms": round(ms, 1), "avg_ms": round(ms, 1)}

    # 2. add-session
    timings = []
    for i in range(n_sessions):
        payload = json.dumps({
            "project": "benchmark",
            "name": f"session-{i}",
            "notes": (
                f"Session {i}: worked on auth module. "
                "JWT validation using RS256. Token expiry: 15min access, 7d refresh. "
                "Key decision: middleware-first validation."
            ),
        })
        _, ms = time_op(ms_run, ["add-session", payload])
        timings.append(ms)

    results["add_session"] = {
        "runs":     n_sessions,
        "total_ms": round(sum(timings), 1),
        "avg_ms":   round(statistics.mean(timings), 1),
        "min_ms":   round(min(timings), 1),
        "max_ms":   round(max(timings), 1),
    }

    # 3. add-insight
    timings = []
    for i in range(n_insights):
        payload = json.dumps({
            "project": "benchmark",
            "type":    "insight",
            "content": (
                f"Insight {i}: Always validate JWT on every request. "
                "RS256 is preferred over HS256 for distributed systems because "
                "it allows public-key verification without sharing secrets. "
                f"Token rotation interval: {15 + i % 30} minutes."
            ),
        })
        _, ms = time_op(ms_run, ["add-insight", payload])
        timings.append(ms)

    results["add_insight"] = {
        "runs":     n_insights,
        "total_ms": round(sum(timings), 1),
        "avg_ms":   round(statistics.mean(timings), 1),
        "min_ms":   round(min(timings), 1),
        "max_ms":   round(max(timings), 1),
    }

    # 4. search
    queries = ["authentication", "JWT token", "RS256 signing", "refresh interval", "middleware"]
    timings = []
    search_results = {}
    for q in queries:
        r, ms = time_op(ms_run, ["search", q])
        timings.append(ms)
        search_results[q] = r.get("count", 0)

    results["search"] = {
        "queries":   queries,
        "runs":      len(queries),
        "total_ms":  round(sum(timings), 1),
        "avg_ms":    round(statistics.mean(timings), 1),
        "min_ms":    round(min(timings), 1),
        "max_ms":    round(max(timings), 1),
        "hit_counts": search_results,
    }

    # 5. final stats
    stats, _ = time_op(ms_run, ["stats"])
    results["db_stats"] = stats

    return results


# ── Output ────────────────────────────────────────────────────────────────────

def print_table(results: dict, n_sessions: int, n_insights: int) -> None:
    print("\n=== memstack DB Benchmark ===\n")
    print(f"{'Operation':<25} {'Runs':>6} {'Total ms':>10} {'Avg ms':>8} {'Min ms':>8} {'Max ms':>8}")
    print("-" * 72)

    for key in ("init", "add_session", "add_insight", "search"):
        r = results[key]
        name = key.replace("_", "-")
        runs  = r["runs"]
        total = r["total_ms"]
        avg   = r["avg_ms"]
        lo    = r.get("min_ms", avg)
        hi    = r.get("max_ms", avg)
        print(f"{name:<25} {runs:>6} {total:>10.1f} {avg:>8.1f} {lo:>8.1f} {hi:>8.1f}")

    stats = results.get("db_stats", {})
    print(f"\nDB state after benchmark:")
    print(f"  sessions : {stats.get('sessions', '?')}")
    print(f"  insights : {stats.get('insights', '?')}")
    print(f"  DB size  : {stats.get('db_size_kb', '?')} KB")
    print(f"  DB path  : {stats.get('db_path', '?')}")

    search = results["search"]
    print(f"\nSearch hit counts:")
    for q, count in search["hit_counts"].items():
        print(f"  '{q}': {count} results")

    print(
        "\nNote: ~30ms of each avg latency is Python subprocess startup."
        "\nFor production use, import memstack-db directly (not subprocess)."
    )


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark memstack DB operations")
    parser.add_argument("--sessions", type=int, default=10, help="Number of sessions to insert (default: 10)")
    parser.add_argument("--insights", type=int, default=50, help="Number of insights to insert (default: 50)")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    args = parser.parse_args()

    results = run_benchmark(n_sessions=args.sessions, n_insights=args.insights)

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print_table(results, n_sessions=args.sessions, n_insights=args.insights)


if __name__ == "__main__":
    main()
