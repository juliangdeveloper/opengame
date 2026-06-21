#!/usr/bin/env python3
"""
analyze_boss_logs.py — Parsea logs de duelos y genera estadísticas por boss.

Input:
  - Aggregate JSON del sweep (run_boss_balance_sweep.py)
  - O una carpeta con duel_*.jsonl individuales

Output:
  - /tmp/boss_balance_report_<ts>.md con análisis completo

Métricas por boss:
  - fights, wins, losses, draws, winrate
  - avg_dmg_dealt_per_fight, avg_dmg_taken_per_fight
  - avg_dps (damage per second alive)
  - top_skills_used (frecuencia de skills casteadas)
  - defensive_actions (parry/dodge/defend usage)
  - avg_time_to_kill
  - survivability (HP final promedio / max_hp)

Anomalías:
  - Winrate > 70% (overpowered) o < 30% (underpowered)
  - HP max muy alto/bajo vs daño promedio
"""
import argparse
import json
import os
import sys
from collections import defaultdict, Counter
from datetime import datetime
from pathlib import Path
from statistics import mean, median, stdev


def _extract_boss_id(data: dict, role: str = "caster") -> str:
    """Extrae un boss_id desde un event payload.
    Acepta varias convenciones de keys y limpia prefijos Boss_ / Boss."""
    for k in [f"{role}_boss_id", "boss_id", role, "actor"]:
        v = data.get(k)
        if v and v != "?":
            s = str(v)
            # Limpiar prefijos tipo "Boss_boss_xxx" → "boss_xxx"
            if s.startswith("Boss_") or s.startswith("Boss"):
                s = s.replace("Boss_", "").replace("Boss", "")
            if s.startswith("boss_") or "_" in s and not s.startswith("boss"):
                return s
            return s
    return "?"


def parse_log_file(jsonl_path: Path) -> dict:
    """Parsea un combat_log JSONL. Devuelve stats agregados."""
    stats: dict = {
        "events_total": 0,
        "casts": [],       # (caster, skill_id, time)
        "hits": [],        # (caster, target, skill_id, amount, time)
        "damage_taken": [],  # (target, amount_final, hp_after, time)
        "deaths": [],      # (actor, killed_by, time)
        "ai_decisions": [],  # (boss_id, decision, skill, time)
        "parries": 0,
        "dodges": 0,
        "defends": 0,
    }
    if not jsonl_path.exists():
        return stats
    with open(jsonl_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            stats["events_total"] += 1
            ev = d.get("event", "")
            data = d.get("data", {})
            t = d.get("t", 0.0)
            if ev == "skill_cast":
                stats["casts"].append({
                    "caster": _extract_boss_id(data),
                    "skill": data.get("skill_id", ""),
                    "t": t,
                })
            elif ev == "skill_hit":
                stats["hits"].append({
                    "caster": _extract_boss_id(data, role="caster"),
                    "target": _extract_boss_id(data, role="target"),
                    "skill": data.get("skill_id", ""),
                    "amount": float(data.get("amount", 0.0)),
                    "t": t,
                })
            elif ev == "damage_taken":
                stats["damage_taken"].append({
                    "target": _extract_boss_id(data, role="target"),
                    "amount": float(data.get("amount_final", 0.0)),
                    "hp_after": float(data.get("hp", 0.0)),
                    "t": t,
                })
            elif ev == "death":
                stats["deaths"].append({
                    "actor": _extract_boss_id(data, role="actor"),
                    "t": t,
                })
            elif ev == "ai_decision":
                stats["ai_decisions"].append({
                    "boss_id": _extract_boss_id(data),
                    "decision": data.get("decision", ""),
                    "skill": data.get("chosen_skill", ""),
                    "t": t,
                })
    return stats


def per_boss_stats(logs: dict[str, dict]) -> dict[str, dict]:
    """Combina los stats de todos los duelos para un boss específico."""
    agg: dict[str, dict] = {}
    for duel_id, st in logs.items():
        a, b = duel_id.replace("duel_", "").split("_vs_")
        if a not in agg: agg[a] = empty_boss_stat(a)
        if b not in agg: agg[b] = empty_boss_stat(b)
        # Hits
        for h in st["hits"]:
            if h["caster"] in agg:
                agg[h["caster"]]["dmg_dealt"].append(h["amount"])
            if h["target"] in agg:
                agg[h["target"]]["dmg_taken"].append(h["amount"])
        # Damage taken (incluye DoTs)
        for d in st["damage_taken"]:
            if d["target"] in agg:
                agg[d["target"]]["dmg_taken_dot"].append(d["amount"])
        # Casts
        for c in st["casts"]:
            if c["caster"] in agg:
                agg[c["caster"]]["skill_casts"].append(c["skill"])
        # Deaths
        for dh in st["deaths"]:
            if dh["actor"] in agg:
                agg[dh["actor"]]["deaths"] += 1
        # AI decisions
        for ai in st["ai_decisions"]:
            if ai["boss_id"] in agg:
                agg[ai["boss_id"]]["ai_decisions"].append(ai["decision"])
                agg[ai["boss_id"]]["skills_decided"].append(ai["skill"])
    return agg


def empty_boss_stat(bid: str) -> dict:
    return {
        "boss_id": bid,
        "dmg_dealt": [],
        "dmg_taken": [],
        "dmg_taken_dot": [],
        "skill_casts": [],
        "ai_decisions": [],
        "skills_decided": [],
        "deaths": 0,
    }


def summarize(per_boss: dict[str, dict], boss_meta: dict[str, dict]) -> dict[str, dict]:
    """Convierte listas a métricas agregadas."""
    out: dict[str, dict] = {}
    for bid, st in per_boss.items():
        meta = boss_meta.get(bid, {})
        max_hp = float(meta.get("max_hp", 1))
        # Time alive (del sim) - esto lo determina el aggregate
        fights = max(1, st["dmg_dealt"].count(0) + len([1 for _ in st["skill_casts"]]))
        out[bid] = {
            "boss_id": bid,
            "max_hp": max_hp,
            "tier": meta.get("tier", "?"),
            "behavior": meta.get("behavior", "?"),
            "total_skill_casts": len(st["skill_casts"]),
            "unique_skills_used": len(set(st["skill_casts"])),
            "skill_cast_freq": Counter(st["skill_casts"]).most_common(10),
            "total_dmg_dealt": sum(st["dmg_dealt"]),
            "avg_dmg_per_hit": mean(st["dmg_dealt"]) if st["dmg_dealt"] else 0.0,
            "total_dmg_taken": sum(st["dmg_taken"]) + sum(st["dmg_taken_dot"]),
            "deaths": st["deaths"],
            "defensive_pct": (
                sum(1 for d in st["ai_decisions"] if d in ("PARRY", "DODGE", "DEFEND"))
                / max(1, len(st["ai_decisions"])) * 100
            ),
            "decision_dist": dict(Counter(st["ai_decisions"])),
        }
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sweep_dir", help="Carpeta con duel_*.jsonl + aggregate.json")
    ap.add_argument("--bosses-json", default="data/contracts/bosses.json")
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    sweep_dir = Path(args.sweep_dir)
    if not sweep_dir.is_dir():
        print(f"ERROR: not a directory: {sweep_dir}")
        sys.exit(1)

    # Load boss metadata
    with open(args.bosses_json) as f:
        bdata = json.load(f)
    boss_meta: dict[str, dict] = {}
    for b in bdata["bosses"]:
        boss_meta[b["id"]] = b

    # Parse all logs
    logs: dict[str, dict] = {}
    log_dir = sweep_dir / "logs"
    if log_dir.is_dir():
        for jl in sorted(log_dir.glob("duel_*.jsonl")):
            duel_id = jl.stem
            logs[duel_id] = parse_log_file(jl)
    print(f"[analyze] parsed {len(logs)} combat logs from {log_dir}")

    # Per-boss aggregation
    per_boss = per_boss_stats(logs)
    summary = summarize(per_boss, boss_meta)

    # Load aggregate for winrates
    agg_path = sweep_dir / "aggregate.json"
    winrates: dict[str, dict] = {}
    if agg_path.is_file():
        with open(agg_path) as f:
            agg = json.load(f)
        for bid, stats in agg.get("by_boss", {}).items():
            fights = max(1, stats["fights"])
            winrates[bid] = {
                "fights": stats["fights"],
                "wins": stats["wins"],
                "losses": stats["losses"],
                "draws": stats["draws"],
                "winrate": stats["wins"] / fights * 100 if fights > 0 else 0.0,
            }

    # Generate report
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_path = Path(args.out) if args.out else Path(f"/tmp/boss_balance_report_{ts}.md")
    with open(out_path, "w") as f:
        f.write(f"# Boss Balance Report\n\n")
        f.write(f"Generated: {ts}\n")
        f.write(f"Sweep dir: {sweep_dir}\n")
        f.write(f"Duels parsed: {len(logs)}\n\n")

        # Winrate table
        f.write("## Win rates (full roster)\n\n")
        f.write("| Boss | Fights | Wins | Losses | Draws | Winrate | Tier | Behavior |\n")
        f.write("|------|--------|------|--------|-------|---------|------|----------|\n")
        for bid, wr in sorted(winrates.items(), key=lambda x: -x[1]["winrate"]):
            bmeta = boss_meta.get(bid, {})
            tier = bmeta.get("tier", "?")
            behavior = bmeta.get("behavior", "?")
            f.write(f"| {bid} | {wr['fights']} | {wr['wins']} | {wr['losses']} | {wr['draws']} | {wr['winrate']:.1f}% | {tier} | {behavior} |\n")

        # Damage table
        f.write("\n## Damage metrics\n\n")
        f.write("| Boss | HP | Dmg Dealt (sum) | Dmg Taken (sum) | Avg/cast | Deaths | Defensive% |\n")
        f.write("|------|-----|-----------------|-----------------|----------|--------|------------|\n")
        for bid, s in sorted(summary.items(), key=lambda x: -x[1]["total_dmg_dealt"]):
            f.write(f"| {bid} | {s['max_hp']:.0f} | {s['total_dmg_dealt']:.0f} | {s['total_dmg_taken']:.0f} | {s['avg_dmg_per_hit']:.1f} | {s['deaths']} | {s['defensive_pct']:.1f}% |\n")

        # Outliers
        f.write("\n## Outliers\n\n")
        strong = [(b, w) for b, w in winrates.items() if w["winrate"] > 65 and w["fights"] > 5]
        weak = [(b, w) for b, w in winrates.items() if w["winrate"] < 35 and w["fights"] > 5]
        if strong:
            f.write("### Overpowered (winrate > 65%)\n\n")
            for b, w in strong:
                f.write(f"- **{b}**: {w['winrate']:.1f}% over {w['fights']} fights — consider nerf\n")
        if weak:
            f.write("\n### Underpowered (winrate < 35%)\n\n")
            for b, w in weak:
                f.write(f"- **{b}**: {w['winrate']:.1f}% over {w['fights']} fights — consider buff\n")

        # Skill usage distribution (does every boss use their skills?)
        f.write("\n## Skill diversity (unique skills used / 4 expected)\n\n")
        f.write("| Boss | Unique skills | Skill freq |\n")
        f.write("|------|---------------|------------|\n")
        for bid, s in sorted(summary.items(), key=lambda x: x[1]["unique_skills_used"]):
            freq_str = ", ".join(f"{sk}×{c}" for sk, c in s["skill_cast_freq"][:5])
            f.write(f"| {bid} | {s['unique_skills_used']} | {freq_str} |\n")

        # Save full data as JSON
        json_path = out_path.with_suffix(".json")
        with open(json_path, "w") as jf:
            json.dump({
                "summary": summary,
                "winrates": winrates,
                "boss_meta": {bid: {"max_hp": bm.get("max_hp"), "tier": bm.get("tier"), "behavior": bm.get("behavior")} for bid, bm in boss_meta.items()},
            }, jf, indent=2)
        f.write(f"\n\nFull JSON data: {json_path}\n")

    print(f"[analyze] report written: {out_path}")
    # Print key outliers to stdout
    print("\n=== Top 5 (overpowered) ===")
    for b, w in sorted(winrates.items(), key=lambda x: -x[1]["winrate"])[:5]:
        print(f"  {b}: {w['winrate']:.1f}%")
    print("\n=== Bottom 5 (underpowered) ===")
    for b, w in sorted(winrates.items(), key=lambda x: x[1]["winrate"])[:5]:
        print(f"  {b}: {w['winrate']:.1f}%")


if __name__ == "__main__":
    main()
