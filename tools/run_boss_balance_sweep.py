#!/usr/bin/env python3
"""
run_boss_balance_sweep.py — Correr todas las peleas 1v1 del roster de bosses.

Genera una matriz de NxN duelos (190 combinaciones únicas para 20 bosses).
Cada duelo corre en su propio proceso Godot headless. Los procesos se
lanzan en paralelo (POOL_SIZE workers).

Output:
  - /tmp/boss_duel_result.txt (de cada run individual)
  - /mnt/c/.../mcp-souls-game/data/contracts/boss_balance_sweep_<timestamp>/
      ├─ duel_<A>_vs_<B>.json  (resumen)
      └─ logs/
          └─ duel_<A>_vs_<B>.jsonl  (log completo)

Uso:
  python3 tools/run_boss_balance_sweep.py --duration 30 --workers 6
  python3 tools/run_boss_balance_sweep.py --duration 30 --bosses boss_frieza,boss_sauron
  python3 tools/run_boss_balance_sweep.py --duration 30 --limit 10  # solo 10 duelos
"""
import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
BOSSES_JSON = PROJECT_ROOT / "data" / "contracts" / "bosses.json"
GODOT_BIN = Path("/home/julian/.local/bin/godot")
SWEEP_ROOT = Path("/tmp/boss_sweeps")


def load_boss_ids() -> list[str]:
    with open(BOSSES_JSON) as f:
        data = json.load(f)
    return [b["id"] for b in data["bosses"]]


def make_pairs(boss_ids: list[str]) -> list[tuple[str, str]]:
    """Genera pares únicos (sin espejo, sin self-fight)."""
    pairs: list[tuple[str, str]] = []
    for i, a in enumerate(boss_ids):
        for b in boss_ids[i + 1:]:
            pairs.append((a, b))
    return pairs


def run_single_duel(
    boss_a: str,
    boss_b: str,
    duration: float,
    sweep_dir: str,
    log_to_stdout: bool = False,
) -> dict:
    """Lanza un proceso Godot para correr un solo duelo. Lee /tmp/boss_duel_result.txt."""
    run_id = f"duel_{boss_a}_vs_{boss_b}"
    env = os.environ.copy()
    env["BOSS_A"] = boss_a
    env["BOSS_B"] = boss_b
    env["SIM_DURATION"] = str(duration)
    env["RUN_ID"] = run_id
    cmd = [
        str(GODOT_BIN),
        "--headless",
        "--path", str(PROJECT_ROOT),
        "--script", "tests/test_boss_duel.gd",
    ]
    t0 = time.time()
    try:
        proc = subprocess.run(
            cmd, env=env, cwd=PROJECT_ROOT,
            capture_output=True, text=True, timeout=duration + 60,
        )
        elapsed = time.time() - t0
        # Leer resultado
        result_path = Path("/tmp/boss_duel_result.txt")
        if not result_path.exists():
            return {
                "boss_a": boss_a, "boss_b": boss_b,
                "error": "no result file",
                "elapsed_sec": elapsed,
                "stdout_tail": proc.stdout[-500:],
                "stderr_tail": proc.stderr[-500:],
            }
        with open(result_path) as rf:
            try:
                res = json.load(rf)
            except json.JSONDecodeError:
                return {
                    "boss_a": boss_a, "boss_b": boss_b,
                    "error": "invalid result json",
                    "result_path_content": result_path.read_text(),
                    "elapsed_sec": elapsed,
                }
        # Copiar el log completo al sweep_dir
        log_src = Path("/home/julian/.local/share/godot/app_userdata/MCP Souls Game") / f"combat_log_{run_id}.jsonl"
        if log_src.exists():
            log_dst_dir = Path(sweep_dir) / "logs"
            log_dst_dir.mkdir(parents=True, exist_ok=True)
            log_dst = log_dst_dir / f"{run_id}.jsonl"
            log_dst.write_bytes(log_src.read_bytes())
            res["log_local_path"] = str(log_dst)
        # Guardar resumen
        summary_dst = Path(sweep_dir) / f"{run_id}.json"
        summary_dst.write_text(json.dumps(res, indent=2))
        res["summary_local_path"] = str(summary_dst)
        res["elapsed_sec"] = round(elapsed, 1)
        if log_to_stdout:
            print(f"  [done] {run_id}: {res.get('winner','?')} ({res.get('events_logged',0)} events, {elapsed:.1f}s)")
        return res
    except subprocess.TimeoutExpired:
        return {
            "boss_a": boss_a, "boss_b": boss_b,
            "error": "timeout",
            "elapsed_sec": time.time() - t0,
        }
    except Exception as e:
        return {
            "boss_a": boss_a, "boss_b": boss_b,
            "error": str(e),
            "elapsed_sec": time.time() - t0,
        }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--duration", type=float, default=30.0, help="Duel length in seconds")
    ap.add_argument("--workers", type=int, default=4, help="Parallel godot processes")
    ap.add_argument("--limit", type=int, default=0, help="Limit number of duels (0=all)")
    ap.add_argument("--bosses", type=str, default="", help="Comma-separated boss IDs to use (default=all)")
    ap.add_argument("--outdir", type=str, default="", help="Output dir (default auto-named)")
    args = ap.parse_args()

    # Sweep dir
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    sweep_dir = args.outdir or str(SWEEP_ROOT / f"sweep_{ts}")
    Path(sweep_dir).mkdir(parents=True, exist_ok=True)
    print(f"[sweep] output: {sweep_dir}")

    # Bosses
    if args.bosses:
        boss_ids = [b.strip() for b in args.bosses.split(",")]
    else:
        boss_ids = load_boss_ids()
    print(f"[sweep] {len(boss_ids)} bosses loaded")

    # Pares
    pairs = make_pairs(boss_ids)
    if args.limit and args.limit > 0:
        pairs = pairs[:args.limit]
    print(f"[sweep] {len(pairs)} duels to run, {args.workers} workers, {args.duration}s each")
    est_min = (len(pairs) / args.workers) * (args.duration + 8) / 60
    print(f"[sweep] estimated time: ~{est_min:.1f} min")

    # Run
    results: list[dict] = []
    t0 = time.time()
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        future_to_pair = {
            pool.submit(run_single_duel, a, b, args.duration, sweep_dir, False): (a, b)
            for a, b in pairs
        }
        done = 0
        for fut in as_completed(future_to_pair):
            res = fut.result()
            results.append(res)
            done += 1
            a, b = future_to_pair[fut]
            elapsed = res.get("elapsed_sec", 0)
            if "error" in res:
                print(f"  [{done}/{len(pairs)}] {a} vs {b}: ERROR {res['error']} ({elapsed}s)")
            else:
                winner = res.get("winner", "?")
                events = res.get("events_logged", 0)
                print(f"  [{done}/{len(pairs)}] {a} vs {b}: winner={winner} events={events} ({elapsed}s)")

    total_elapsed = time.time() - t0
    print(f"\n[sweep] DONE: {len(results)} duels in {total_elapsed/60:.1f} min")

    # Aggregate
    by_boss: dict[str, dict] = {b: {"wins": 0, "losses": 0, "draws": 0, "total_dmg_dealt": 0.0, "fights": 0} for b in boss_ids}
    for r in results:
        if "error" in r:
            continue
        a, b = r.get("boss_a", "?"), r.get("boss_b", "?")
        winner = r.get("winner", "draw")
        if a in by_boss:
            by_boss[a]["fights"] += 1
            if winner == a: by_boss[a]["wins"] += 1
            elif winner == b: by_boss[a]["losses"] += 1
            else: by_boss[a]["draws"] += 1
        if b in by_boss:
            by_boss[b]["fights"] += 1
            if winner == b: by_boss[b]["wins"] += 1
            elif winner == a: by_boss[b]["losses"] += 1
            else: by_boss[b]["draws"] += 1

    # Write aggregate
    summary: dict = {
        "timestamp": ts,
        "duration_sec": args.duration,
        "duels_total": len(pairs),
        "duels_completed": len([r for r in results if "error" not in r]),
        "duels_failed": len([r for r in results if "error" in r]),
        "wall_time_min": round(total_elapsed / 60, 2),
        "bosses": boss_ids,
        "by_boss": by_boss,
        "results": results,
    }
    summary_path = Path(sweep_dir) / "aggregate.json"
    summary_path.write_text(json.dumps(summary, indent=2))
    print(f"[sweep] aggregate written: {summary_path}")

    # Print table
    print("\n=== Win rates ===")
    print(f"{'boss':<20} {'fights':>7} {'wins':>6} {'losses':>7} {'draws':>6} {'winrate':>8}")
    for b, stats in sorted(by_boss.items(), key=lambda x: -x[1]["wins"] / max(1, x[1]["fights"])):
        wr = stats["wins"] / max(1, stats["fights"])
        print(f"{b:<20} {stats['fights']:>7} {stats['wins']:>6} {stats['losses']:>7} {stats['draws']:>6} {wr*100:>7.1f}%")


if __name__ == "__main__":
    main()
