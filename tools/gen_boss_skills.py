#!/usr/bin/env python3
"""gen_boss_skills.py — Genera .tres files para las nuevas skills del boss system.

Output: data/skills/<skill_id>.tres

Cada skill es data-driven: misma estructura que las existentes. El BossEnemy
las carga y castea exactamente igual que el player.
"""

import os
import json
from pathlib import Path

PROJECT = Path("/mnt/c/Users/Rog/Workspace/01_PROYECTOS/mcp-souls-game")
OUT_DIR = PROJECT / "data" / "skills"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ExtResource común (script class)
SCRIPT_EXT = '[ext_resource type="Script" path="res://scripts/skill/skill_resource.gd" id="1"]'

# Header + ext resource (común a todos)
HEADER = """[gd_resource type="Resource" script_class="SkillResource" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/skill/skill_resource.gd" id="1"]

[resource]
script = ExtResource("1")
"""


def tres(v):
    """Formatea un valor Python como literal .tres (Godot-style)."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        if isinstance(v, float) and v.is_integer():
            return str(int(v))
        return str(v)
    if isinstance(v, str):
        # Godot string literal con escape
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list):
        if not v:
            return "[]"
        items = [tres(x) for x in v]
        return "[" + ", ".join(items) + "]"
    if isinstance(v, dict):
        if not v:
            return "{}"
        items = [f'"{k}": {tres(val)}' for k, val in v.items()]
        return "{" + ", ".join(items) + "}"
    return str(v)


def write_skill(skill_id, name, description, flavor_text, category, skill_type,
                target_resolver, designed_max, atoms, costs, vfx=None, icon_hint=""):
    """Genera un archivo .tres con la skill completa."""
    lines = [HEADER]
    lines.append(f'id = &"{skill_id}"')
    lines.append(f'name = "{name}"')
    lines.append(f'description = "{description.replace(chr(34), chr(92) + chr(34))}"')
    lines.append(f'flavor_text = "{flavor_text}"')
    lines.append(f'category = &"{category}"')
    lines.append(f'type = &"{skill_type}"')
    lines.append(f'target_resolver = {tres(target_resolver)}')
    lines.append(f'designed_max = {tres(designed_max)}')
    lines.append(f'atoms = {tres(atoms)}')
    lines.append(f'combo_triggers = []')
    lines.append(f'costs = {tres(costs)}')
    lines.append(f'vfx = {tres(vfx or {})}')
    lines.append(f'icon_hint = "{icon_hint}"')
    content = "\n".join(lines) + "\n"
    out_path = OUT_DIR / f"{skill_id}.tres"
    out_path.write_text(content, encoding="utf-8")
    print(f"  wrote {skill_id}.tres")


# =============================================================================
# SKILLS — definidas como dicts
# =============================================================================
SKILLS = [
    # === ELEMENTALES RANGO (kamehameha-style beam) ===
    {
        "id": "lightning_bolt_001",
        "name": "Lightning Bolt",
        "description": "Un rayo rápido de electricidad.",
        "flavor_text": "¡ZAP!",
        "category": "ranged_projectile",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 60.0, "cooldown": 1.5, "stamina": 18.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 60.0, "radius": 1.8, "damage_type": "energy",
                       "element": "lightning", "applies_status": "stun",
                       "status_chance": 0.3, "status_duration": 1.0, "falloff": "linear"},
            "hitbox": {"shape": "sphere", "size": [1.8, 1.8, 1.8], "position": "at_target",
                       "color": [0.7, 0.9, 1.0, 0.9], "emission": 6.0, "duration": 0.3},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 18.0, "cooldown": 1.5}
    },
    {
        "id": "fireball_001",
        "name": "Fireball",
        "description": "Bola de fuego que inflige daño y aplica quemadura.",
        "flavor_text": "Arde.",
        "category": "ranged_projectile",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 55.0, "cooldown": 1.5, "stamina": 16.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 55.0, "radius": 2.0, "damage_type": "fire",
                       "element": "fire", "applies_status": "burn",
                       "status_chance": 0.6, "status_duration": 3.0, "falloff": "linear"},
            "hitbox": {"shape": "sphere", "size": [2.0, 2.0, 2.0], "position": "at_target",
                       "color": [1.0, 0.5, 0.1, 0.9], "emission": 5.0, "duration": 0.4},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 16.0, "cooldown": 1.5}
    },
    {
        "id": "ice_lance_001",
        "name": "Ice Lance",
        "description": "Lanza de hielo piercing. Ralentiza al impactar.",
        "flavor_text": "Frío mortal.",
        "category": "ranged_projectile",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 50.0, "cooldown": 1.8, "stamina": 18.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 50.0, "radius": 1.5, "damage_type": "energy",
                       "element": "water", "applies_status": "slow",
                       "status_chance": 0.7, "status_duration": 2.5, "falloff": "linear"},
            "hitbox": {"shape": "sphere", "size": [1.5, 1.5, 1.5], "position": "at_target",
                       "color": [0.6, 0.85, 1.0, 0.85], "emission": 4.0, "duration": 0.35},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 18.0, "cooldown": 1.8}
    },
    {
        "id": "dark_bolt_001",
        "name": "Dark Bolt",
        "description": "Rayo de energía oscura. Daño puro.",
        "flavor_text": "La oscuridad consume.",
        "category": "ranged_projectile",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 45.0, "cooldown": 1.2, "stamina": 14.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 45.0, "radius": 1.6, "damage_type": "energy",
                       "element": "dark", "falloff": "linear"},
            "hitbox": {"shape": "sphere", "size": [1.6, 1.6, 1.6], "position": "at_target",
                       "color": [0.3, 0.0, 0.5, 0.9], "emission": 5.0, "duration": 0.3},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 14.0, "cooldown": 1.2}
    },
    {
        "id": "holy_smite_001",
        "name": "Holy Smite",
        "description": "Rayo sagrado. Quema undead y dark-aligned.",
        "flavor_text": "Luz divina.",
        "category": "ranged_projectile",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 65.0, "cooldown": 2.0, "stamina": 20.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 65.0, "radius": 1.6, "damage_type": "energy",
                       "element": "light", "falloff": "linear"},
            "hitbox": {"shape": "sphere", "size": [1.6, 1.6, 1.6], "position": "at_target",
                       "color": [1.0, 0.95, 0.5, 0.95], "emission": 7.0, "duration": 0.35},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 20.0, "cooldown": 2.0}
    },

    # === BUFFS / DEBUFFS / STATUS ===
    {
        "id": "stone_skin_001",
        "name": "Stone Skin",
        "description": "Piel petrea: +50% defensa por 6s.",
        "flavor_text": "Piedra.",
        "category": "buff",
        "type": "control",
        "target_resolver": {"kind": "self", "params": {}},
        "designed_max": {"duration": 6.0, "cooldown": 12.0, "stamina": 25.0, "shield_amount": 100.0},
        "atoms": [{
            "type": "shield",
            "params": {"shield_amount": 100.0, "duration": 6.0, "element": "earth"},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 25.0, "cooldown": 12.0}
    },
    {
        "id": "battle_cry_001",
        "name": "Battle Cry",
        "description": "Grito de guerra: +30% daño por 8s.",
        "flavor_text": "¡GUERRA!",
        "category": "buff",
        "type": "control",
        "target_resolver": {"kind": "self", "params": {}},
        "designed_max": {"duration": 8.0, "cooldown": 15.0, "stamina": 20.0},
        "atoms": [{
            "type": "buff",
            "params": {"stat": "damage_mult", "value": 1.3, "kind": "multiply", "duration": 8.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 20.0, "cooldown": 15.0}
    },
    {
        "id": "venom_pump_001",
        "name": "Venom Pump",
        "description": "Bombea veneno: +100% daño físico por 10s. STACKABLE 2 veces.",
        "flavor_text": "VENOM.",
        "category": "buff",
        "type": "control",
        "target_resolver": {"kind": "self", "params": {}},
        "designed_max": {"duration": 10.0, "cooldown": 20.0, "stamina": 30.0},
        "atoms": [{
            "type": "buff",
            "params": {"stat": "damage_mult", "value": 2.0, "kind": "multiply", "duration": 10.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 30.0, "cooldown": 20.0}
    },
    {
        "id": "break_defense_001",
        "name": "Break Defense",
        "description": "Quita toda la defensa del objetivo y lo aturde 1.5s.",
        "flavor_text": "¡ROMPER!",
        "category": "debuff",
        "type": "control",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"duration": 1.5, "cooldown": 14.0, "stamina": 20.0},
        "atoms": [{
            "type": "status",
            "params": {"kind": "stun", "duration": 1.5, "magnitude": 1.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 20.0, "cooldown": 14.0}
    },
    {
        "id": "petrify_gaze_001",
        "name": "Petrify Gaze",
        "description": "Mirada petrificante. STUN 2.5s si el target está de frente.",
        "flavor_text": "No me mires.",
        "category": "debuff",
        "type": "control",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"duration": 2.5, "cooldown": 12.0, "stamina": 18.0},
        "atoms": [{
            "type": "status",
            "params": {"kind": "stun", "duration": 2.5, "magnitude": 1.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 18.0, "cooldown": 12.0}
    },
    {
        "id": "fear_aura_001",
        "name": "Fear Aura",
        "description": "Aura de miedo: reduce daño del objetivo 30% por 5s.",
        "flavor_text": "Terror.",
        "category": "debuff",
        "type": "control",
        "target_resolver": {"kind": "player_aoe", "params": {"radius": 8.0}},
        "designed_max": {"duration": 5.0, "cooldown": 14.0, "stamina": 20.0},
        "atoms": [{
            "type": "status",
            "params": {"kind": "weaken", "duration": 5.0, "magnitude": 0.7},
            "applies_to_target": "all_in_aoe"
        }],
        "costs": {"stamina": 20.0, "cooldown": 14.0}
    },
    {
        "id": "candy_beam_001",
        "name": "Candy Beam",
        "description": "Transforma al objetivo en caramelo: STUN 2s.",
        "flavor_text": "Candy.",
        "category": "debuff",
        "type": "control",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"duration": 2.0, "cooldown": 11.0, "stamina": 18.0},
        "atoms": [{
            "type": "status",
            "params": {"kind": "stun", "duration": 2.0, "magnitude": 1.0},
            "applies_to_target": "primary"
        },{
            "type": "hit",
            "params": {"amount": 25.0, "damage_type": "energy", "element": "arcane", "knockback": 0.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 18.0, "cooldown": 11.0}
    },
    {
        "id": "mind_break_001",
        "name": "Mind Break",
        "description": "Quiebre mental: SHATTER al objetivo. Quita todos los buffs, aplica FEAR 4s.",
        "flavor_text": "Romper.",
        "category": "debuff",
        "type": "control",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"duration": 4.0, "cooldown": 16.0, "stamina": 22.0},
        "atoms": [{
            "type": "status",
            "params": {"kind": "fear", "duration": 4.0, "magnitude": 1.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 22.0, "cooldown": 16.0}
    },
    {
        "id": "lich_form_001",
        "name": "Lich Form",
        "description": "El caster entra en forma lich. Inmune a daño durante 5s.",
        "flavor_text": "Soy inmortal.",
        "category": "buff",
        "type": "control",
        "target_resolver": {"kind": "self", "params": {}},
        "designed_max": {"duration": 5.0, "cooldown": 30.0, "stamina": 35.0, "shield_amount": 999.0},
        "atoms": [{
            "type": "shield",
            "params": {"shield_amount": 9999.0, "duration": 5.0, "element": "dark"},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 35.0, "cooldown": 30.0}
    },

    # === DOTS / STATUS DAMAGE ===
    {
        "id": "poison_dart_001",
        "name": "Poison Dart",
        "description": "Dardo envenenado. DoT poison 5s + daño inicial.",
        "flavor_text": "¿Qué te picó?",
        "category": "ranged_projectile",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 20.0, "dpt": 8.0, "duration": 5.0,
                          "cooldown": 3.0, "stamina": 12.0},
        "atoms": [{
            "type": "hit",
            "params": {"amount": 20.0, "damage_type": "physical", "element": "dark",
                       "knockback": 0.5, "applies_status": "poison",
                       "status_chance": 1.0, "status_duration": 5.0},
            "applies_to_target": "primary"
        },{
            "type": "dot",
            "params": {"dpt": 8.0, "duration": 5.0, "tick_interval": 1.0,
                       "element": "dark", "applies_status": "poison",
                       "status_chance": 1.0, "status_duration": 5.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 12.0, "cooldown": 3.0}
    },
    {
        "id": "venomous_bite_001",
        "name": "Venomous Bite",
        "description": "Mordida venenosa melee. Daño + poison DoT.",
        "flavor_text": "Muerde.",
        "category": "melee_swing",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 30.0, "dpt": 5.0, "duration": 4.0,
                          "cooldown": 2.5, "stamina": 10.0},
        "atoms": [{
            "type": "hit",
            "params": {"amount": 30.0, "damage_type": "physical", "element": "dark",
                       "knockback": 0.0, "applies_status": "poison",
                       "status_chance": 1.0, "status_duration": 4.0},
            "applies_to_target": "primary"
        },{
            "type": "dot",
            "params": {"dpt": 5.0, "duration": 4.0, "tick_interval": 1.0, "element": "dark"},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 10.0, "cooldown": 2.5}
    },
    {
        "id": "crucio_001",
        "name": "Crucio",
        "description": "Maldición de dolor. DoT damage + fear.",
        "flavor_text": "Siente mi dolor.",
        "category": "dot",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"dpt": 10.0, "duration": 4.0, "cooldown": 10.0, "stamina": 20.0},
        "atoms": [{
            "type": "dot",
            "params": {"dpt": 10.0, "duration": 4.0, "tick_interval": 1.0,
                       "element": "dark", "applies_status": "fear",
                       "status_chance": 1.0, "status_duration": 4.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 20.0, "cooldown": 10.0}
    },
    {
        "id": "soul_drain_001",
        "name": "Soul Drain",
        "description": "Drena vida: hace 35 de daño y CURA 50% al caster.",
        "flavor_text": "Tu alma es mía.",
        "category": "lifesteal",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 35.0, "heal_amount": 17.5, "cooldown": 4.0, "stamina": 22.0},
        "atoms": [{
            "type": "hit",
            "params": {"amount": 35.0, "damage_type": "energy", "element": "dark", "knockback": 0.0},
            "applies_to_target": "primary"
        },{
            "type": "heal",
            "params": {"amount": 17.5},
            "applies_to_target": "primary"  # heal se aplica al caster via lifesteal
        }],
        "costs": {"stamina": 22.0, "cooldown": 4.0}
    },

    # === MOVEMENT / TACTICAL ===
    {
        "id": "arrogant_dodge_001",
        "name": "Arrogant Dodge",
        "description": "Esquiva hacia atrás con i-frames. Counter listo.",
        "flavor_text": "¿Eso es todo?",
        "category": "tactical",
        "type": "control",
        "target_resolver": {"kind": "self", "params": {}},
        "designed_max": {"distance": 5.0, "duration": 0.4, "cooldown": 6.0, "stamina": 10.0},
        "atoms": [{
            "type": "move",
            "params": {"kind": "dash", "distance": 5.0, "duration": 0.4,
                       "target_relative": "backward", "i_frames": True, "blink": True},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 10.0, "cooldown": 6.0}
    },
    {
        "id": "smoke_bomb_001",
        "name": "Smoke Bomb",
        "description": "Bomba de humo. Invisibilidad 3s + teleport corto.",
        "flavor_text": "¡POOF!",
        "category": "tactical",
        "type": "control",
        "target_resolver": {"kind": "self", "params": {}},
        "designed_max": {"distance": 8.0, "duration": 3.0, "cooldown": 12.0, "stamina": 18.0},
        "atoms": [{
            "type": "move",
            "params": {"kind": "teleport", "distance": 8.0, "duration": 0.0,
                       "target_relative": "backward", "i_frames": True, "blink": True},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 18.0, "cooldown": 12.0}
    },
    {
        "id": "flight_001",
        "name": "Flight",
        "description": "Vuela. El caster no puede ser target de melee por 4s.",
        "flavor_text": "¡Arriba!",
        "category": "tactical",
        "type": "control",
        "target_resolver": {"kind": "self", "params": {}},
        "designed_max": {"distance": 3.0, "duration": 4.0, "cooldown": 18.0, "stamina": 25.0},
        "atoms": [{
            "type": "move",
            "params": {"kind": "launch", "distance": 3.0, "duration": 0.5,
                       "target_relative": "self", "i_frames": True},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 25.0, "cooldown": 18.0}
    },
    {
        "id": "charging_tackle_001",
        "name": "Charging Tackle",
        "description": "Carga frontal: avanza 8m e inflige daño al impacto.",
        "flavor_text": "¡CARGAAA!",
        "category": "dash",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 60.0, "distance": 8.0, "duration": 0.5,
                          "cooldown": 5.0, "stamina": 20.0},
        "atoms": [{
            "type": "move",
            "params": {"kind": "dash", "distance": 8.0, "duration": 0.5,
                       "target_relative": "forward"},
            "applies_to_target": "primary"
        },{
            "type": "hit",
            "params": {"amount": 60.0, "damage_type": "physical", "element": "physical", "knockback": 4.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 20.0, "cooldown": 5.0}
    },
    {
        "id": "tail_lash_001",
        "name": "Tail Lash",
        "description": "Azote con cola: hit + push back.",
        "flavor_text": "¡FUA!",
        "category": "melee_swing",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 35.0, "cooldown": 2.0, "stamina": 12.0},
        "atoms": [{
            "type": "move",
            "params": {"kind": "dash", "distance": 2.0, "duration": 0.2,
                       "target_relative": "forward"},
            "applies_to_target": "primary"
        },{
            "type": "hit",
            "params": {"amount": 35.0, "damage_type": "physical", "element": "physical", "knockback": 5.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 12.0, "cooldown": 2.0}
    },

    # === AOE / ZONES ===
    {
        "id": "ground_pound_001",
        "name": "Ground Pound",
        "description": "Salta y golpea el suelo. AoE físico grande.",
        "flavor_text": "¡BOOM!",
        "category": "aoe_burst",
        "type": "damage",
        "target_resolver": {"kind": "player_aoe", "params": {"radius": 5.0}},
        "designed_max": {"amount": 80.0, "radius": 5.0, "cooldown": 8.0, "stamina": 30.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 80.0, "radius": 5.0, "damage_type": "physical",
                       "element": "physical", "falloff": "linear", "knockback": 6.0},
            "hitbox": {"shape": "sphere", "size": [5.0, 1.0, 5.0], "position": "in_front_of_caster",
                       "color": [0.7, 0.5, 0.3, 0.9], "emission": 4.0, "duration": 0.6},
            "applies_to_target": "all_in_aoe"
        }],
        "costs": {"stamina": 30.0, "cooldown": 8.0}
    },
    {
        "id": "firebreath_001",
        "name": "Fire Breath",
        "description": "Aliento de fuego en cono frontal.",
        "flavor_text": "Arde en el infierno.",
        "category": "cone_aoe",
        "type": "damage",
        "target_resolver": {"kind": "player_aoe", "params": {"radius": 6.0}},
        "designed_max": {"amount": 70.0, "radius": 6.0, "cooldown": 7.0, "stamina": 25.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 70.0, "radius": 6.0, "damage_type": "fire",
                       "element": "fire", "applies_status": "burn",
                       "status_chance": 0.7, "status_duration": 3.0, "falloff": "linear"},
            "hitbox": {"shape": "sphere", "size": [6.0, 2.0, 6.0], "position": "in_front_of_caster",
                       "color": [1.0, 0.4, 0.0, 0.95], "emission": 8.0, "duration": 0.7},
            "applies_to_target": "all_in_aoe"
        }],
        "costs": {"stamina": 25.0, "cooldown": 7.0}
    },
    {
        "id": "triangle_blast_001",
        "name": "Triangle Blast",
        "description": "Tres proyectiles de magia oscura en cono.",
        "flavor_text": "Trifuerza.",
        "category": "cone_aoe",
        "type": "damage",
        "target_resolver": {"kind": "player_aoe", "params": {"radius": 6.0}},
        "designed_max": {"amount": 50.0, "radius": 6.0, "cooldown": 6.0, "stamina": 22.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 50.0, "radius": 6.0, "damage_type": "energy",
                       "element": "dark", "falloff": "linear"},
            "hitbox": {"shape": "sphere", "size": [6.0, 2.0, 6.0], "position": "in_front_of_caster",
                       "color": [0.6, 0.0, 1.0, 0.9], "emission": 6.0, "duration": 0.5},
            "applies_to_target": "all_in_aoe"
        }],
        "costs": {"stamina": 22.0, "cooldown": 6.0}
    },
    {
        "id": "dark_spike_001",
        "name": "Dark Spike",
        "description": "Púas oscuras del suelo en zona fija.",
        "flavor_text": "Desde abajo.",
        "category": "zone",
        "type": "damage",
        "target_resolver": {"kind": "player_aoe", "params": {"radius": 4.0}},
        "designed_max": {"amount": 45.0, "radius": 4.0, "cooldown": 5.0, "stamina": 18.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 45.0, "radius": 4.0, "damage_type": "energy",
                       "element": "dark", "falloff": "linear"},
            "hitbox": {"shape": "sphere", "size": [4.0, 1.5, 4.0], "position": "in_front_of_caster",
                       "color": [0.3, 0.0, 0.5, 0.9], "emission": 3.0, "duration": 0.4},
            "applies_to_target": "all_in_aoe"
        }],
        "costs": {"stamina": 18.0, "cooldown": 5.0}
    },
    {
        "id": "massive_cleave_001",
        "name": "Massive Cleave",
        "description": "Cleave 360° masivo. Alto daño en área.",
        "flavor_text": "Dragonslayer.",
        "category": "aoe_burst",
        "type": "damage",
        "target_resolver": {"kind": "player_aoe", "params": {"radius": 4.0}},
        "designed_max": {"amount": 95.0, "radius": 4.0, "cooldown": 7.0, "stamina": 32.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 95.0, "radius": 4.0, "damage_type": "physical",
                       "element": "physical", "falloff": "linear", "knockback": 4.0},
            "hitbox": {"shape": "sphere", "size": [4.0, 1.5, 4.0], "position": "in_front_of_caster",
                       "color": [0.8, 0.0, 0.0, 0.9], "emission": 5.0, "duration": 0.5},
            "applies_to_target": "all_in_aoe"
        }],
        "costs": {"stamina": 32.0, "cooldown": 7.0}
    },
    {
        "id": "supernova_001",
        "name": "Supernova",
        "description": "Explosión cósmica AoE enorme. Daño masivo en radio 10m.",
        "flavor_text": "Una estrella muere.",
        "category": "ultimate",
        "type": "damage",
        "target_resolver": {"kind": "player_aoe", "params": {"radius": 10.0}},
        "designed_max": {"amount": 200.0, "radius": 10.0, "cooldown": 60.0, "stamina": 80.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 200.0, "radius": 10.0, "damage_type": "energy",
                       "element": "arcane", "falloff": "linear", "knockback": 8.0},
            "hitbox": {"shape": "sphere", "size": [10.0, 4.0, 10.0], "position": "in_front_of_caster",
                       "color": [1.0, 0.95, 0.9, 1.0], "emission": 12.0, "duration": 1.5},
            "applies_to_target": "all_in_aoe"
        }],
        "costs": {"stamina": 80.0, "cooldown": 60.0}
    },
    {
        "id": "exploding_card_001",
        "name": "Exploding Card",
        "description": "Carta explosiva: AoE pequeño + knockback.",
        "flavor_text": "¡BANG!",
        "category": "aoe_burst",
        "type": "damage",
        "target_resolver": {"kind": "player_aoe", "params": {"radius": 3.0}},
        "designed_max": {"amount": 50.0, "radius": 3.0, "cooldown": 4.0, "stamina": 15.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 50.0, "radius": 3.0, "damage_type": "fire",
                       "element": "fire", "falloff": "linear", "knockback": 3.0},
            "hitbox": {"shape": "sphere", "size": [3.0, 1.0, 3.0], "position": "in_front_of_caster",
                       "color": [1.0, 0.6, 0.0, 0.9], "emission": 4.0, "duration": 0.4},
            "applies_to_target": "all_in_aoe"
        }],
        "costs": {"stamina": 15.0, "cooldown": 4.0}
    },
    {
        "id": "avada_kedavra_001",
        "name": "Avada Kedavra",
        "description": "Maldición imperdonable. Damage masivo directo. 1.5s cast.",
        "flavor_text": "¡AVADA KEDAVRA!",
        "category": "ultimate",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 250.0, "charge_time": 1.5, "cooldown": 30.0, "stamina": 60.0},
        "atoms": [{
            "type": "hit",
            "params": {"amount": 250.0, "damage_type": "true", "element": "dark", "knockback": 0.0},
            "hitbox": {"shape": "sphere", "size": [1.5, 1.5, 1.5], "position": "at_target",
                       "color": [0.0, 1.0, 0.0, 1.0], "emission": 12.0, "duration": 0.6},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 60.0, "cooldown": 30.0, "charge_time": 1.5}
    },

    # === BEAMS (kamehameha-like) ===
    {
        "id": "photon_sterilizer_001",
        "name": "Photon Sterilizer",
        "description": "Rayo de fotones. Largo y poderoso.",
        "flavor_text": "Esterilización.",
        "category": "beam",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 100.0, "beam_length": 15.0, "radius": 1.5,
                          "cooldown": 8.0, "stamina": 30.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 100.0, "radius": 1.5, "damage_type": "energy",
                       "element": "light", "falloff": "linear"},
            "hitbox": {"shape": "beam", "size": [1.5, 1.5, 15.0], "position": "in_front_of_caster",
                       "distance_forward": 1.0, "color": [1.0, 1.0, 0.8, 0.95],
                       "emission": 8.0, "duration": 0.7},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 30.0, "cooldown": 8.0}
    },
    {
        "id": "vaporizing_eye_001",
        "name": "Vaporizing Eye",
        "description": "Ojo vaporizador: rayo líquido que atraviesa.",
        "flavor_text": "¡MRAAAAH!",
        "category": "beam",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 80.0, "beam_length": 12.0, "radius": 1.2,
                          "cooldown": 5.0, "stamina": 20.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 80.0, "radius": 1.2, "damage_type": "energy",
                       "element": "arcane", "falloff": "linear"},
            "hitbox": {"shape": "beam", "size": [1.2, 1.2, 12.0], "position": "in_front_of_caster",
                       "distance_forward": 1.0, "color": [0.6, 0.9, 1.0, 0.9],
                       "emission": 7.0, "duration": 0.5},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 20.0, "cooldown": 5.0}
    },
    {
        "id": "force_choke_001",
        "name": "Force Choke",
        "description": "Agarra al objetivo con la Fuerza. Daño + STUN 1s.",
        "flavor_text": "Tú me decepcionas.",
        "category": "control",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 40.0, "cooldown": 7.0, "stamina": 18.0},
        "atoms": [{
            "type": "hit",
            "params": {"amount": 40.0, "damage_type": "energy", "element": "dark",
                       "knockback": 0.0},
            "applies_to_target": "primary"
        },{
            "type": "status",
            "params": {"kind": "stun", "duration": 1.0, "magnitude": 1.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 18.0, "cooldown": 7.0}
    },

    # === MISC ===
    {
        "id": "knives_throw_001",
        "name": "Knives Throw",
        "description": "Lanza 5 cuchillos rápidos.",
        "flavor_text": "¡MUERE!",
        "category": "ranged_projectile",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 25.0, "cooldown": 3.0, "stamina": 12.0},
        "atoms": [{
            "type": "hit",
            "params": {"amount": 25.0, "damage_type": "physical", "element": "physical", "knockback": 0.5},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 12.0, "cooldown": 3.0}
    },
    {
        "id": "helm_splitter_001",
        "name": "Helm Splitter",
        "description": "Hachazo que parte el aire. Daño masivo single target.",
        "flavor_text": "¡DIVIDE!",
        "category": "melee_swing",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 90.0, "cooldown": 6.0, "stamina": 28.0},
        "atoms": [{
            "type": "hit",
            "params": {"amount": 90.0, "damage_type": "physical", "element": "fire", "knockback": 5.0},
            "hitbox": {"shape": "sphere", "size": [1.5, 1.5, 1.5], "position": "at_target",
                       "color": [1.0, 0.3, 0.0, 0.95], "emission": 6.0, "duration": 0.3},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 28.0, "cooldown": 6.0}
    },
    {
        "id": "blades_of_chaos_001",
        "name": "Blades of Chaos",
        "description": "Cadenas con cuchillas. Daño + bleed.",
        "flavor_text": "Aaaargh!",
        "category": "melee_swing",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 55.0, "dpt": 4.0, "duration": 4.0,
                          "cooldown": 4.0, "stamina": 18.0},
        "atoms": [{
            "type": "hit",
            "params": {"amount": 55.0, "damage_type": "physical", "element": "fire",
                       "knockback": 2.0, "applies_status": "bleed",
                       "status_chance": 0.8, "status_duration": 4.0},
            "applies_to_target": "primary"
        },{
            "type": "dot",
            "params": {"dpt": 4.0, "duration": 4.0, "tick_interval": 1.0, "element": "fire"},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 18.0, "cooldown": 4.0}
    },
    {
        "id": "cannon_arm_001",
        "name": "Cannon Arm",
        "description": "Brazo de cañón. Disparo explosivo.",
        "flavor_text": "¡BOOM!",
        "category": "ranged_projectile",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 75.0, "cooldown": 5.0, "stamina": 22.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 75.0, "radius": 2.0, "damage_type": "physical",
                       "element": "fire", "falloff": "linear", "knockback": 3.0},
            "hitbox": {"shape": "sphere", "size": [2.0, 2.0, 2.0], "position": "at_target",
                       "color": [1.0, 0.6, 0.0, 0.95], "emission": 5.0, "duration": 0.4},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 22.0, "cooldown": 5.0}
    },
    {
        "id": "dead_lights_001",
        "name": "Dead Lights",
        "description": "Las luces muertas. MASSIVE daño si target HP<10%.",
        "flavor_text": "Flotando... en el vacío...",
        "category": "ultimate",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 500.0, "cooldown": 60.0, "stamina": 80.0},
        "atoms": [{
            "type": "burst_aoe",
            "params": {"amount": 500.0, "radius": 3.0, "damage_type": "energy",
                       "element": "arcane", "falloff": "linear"},
            "hitbox": {"shape": "sphere", "size": [3.0, 3.0, 3.0], "position": "at_target",
                       "color": [1.0, 0.5, 0.8, 1.0], "emission": 15.0, "duration": 1.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 80.0, "cooldown": 60.0}
    },
    {
        "id": "za_warudo_001",
        "name": "Za Warudo",
        "description": "Detener el tiempo. El caster gana 3s de turnos extra. STUN al target.",
        "flavor_text": "¡Za Warudo!",
        "category": "ultimate",
        "type": "control",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"duration": 3.0, "cooldown": 20.0, "stamina": 40.0},
        "atoms": [{
            "type": "status",
            "params": {"kind": "stun", "duration": 3.0, "magnitude": 1.0},
            "applies_to_target": "primary"
        },{
            "type": "buff",
            "params": {"stat": "speed_mult", "value": 2.0, "kind": "multiply", "duration": 3.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 40.0, "cooldown": 20.0}
    },
    {
        "id": "regeneration_001",
        "name": "Regeneration",
        "description": "Regenera 5% HP/seg por 6s.",
        "flavor_text": "Recuperarse.",
        "category": "buff",
        "type": "control",
        "target_resolver": {"kind": "self", "params": {}},
        "designed_max": {"hot_per_tick": 5.0, "duration": 6.0, "tick_interval": 1.0,
                          "cooldown": 18.0, "stamina": 25.0},
        "atoms": [{
            "type": "hot",
            "params": {"hot_per_tick": 5.0, "duration": 6.0, "tick_interval": 1.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 25.0, "cooldown": 18.0}
    },
    {
        "id": "absorption_001",
        "name": "Absorption",
        "description": "Drena HP del objetivo (20) y se lo suma al caster.",
        "flavor_text": "Absorber.",
        "category": "lifesteal",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 20.0, "heal_amount": 20.0, "cooldown": 6.0, "stamina": 15.0},
        "atoms": [{
            "type": "hit",
            "params": {"amount": 20.0, "damage_type": "energy", "element": "dark", "knockback": 0.0},
            "applies_to_target": "primary"
        },{
            "type": "heal",
            "params": {"amount": 20.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 15.0, "cooldown": 6.0}
    },
    {
        "id": "dark_pact_001",
        "name": "Dark Pact",
        "description": "Sacrifica 30 HP propio por +50% daño 10s.",
        "flavor_text": "Pacto oscuro.",
        "category": "buff",
        "type": "control",
        "target_resolver": {"kind": "self", "params": {}},
        "designed_max": {"duration": 10.0, "cooldown": 25.0, "stamina": 0.0, "amount": 30.0},
        "atoms": [{
            "type": "hit",
            "params": {"amount": 30.0, "damage_type": "energy", "element": "dark", "knockback": 0.0},
            "applies_to_target": "primary"
        },{
            "type": "buff",
            "params": {"stat": "damage_mult", "value": 1.5, "kind": "multiply", "duration": 10.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 0.0, "cooldown": 25.0}
    },
    {
        "id": "nen_pulse_001",
        "name": "Nen Pulse",
        "description": "Pulso de aura Nen. Reflect 50% del daño recibido por 4s.",
        "flavor_text": "Pulso Nen.",
        "category": "buff",
        "type": "control",
        "target_resolver": {"kind": "self", "params": {}},
        "designed_max": {"duration": 4.0, "cooldown": 18.0, "stamina": 22.0, "shield_amount": 80.0},
        "atoms": [{
            "type": "shield",
            "params": {"shield_amount": 80.0, "duration": 4.0, "element": "arcane"},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 22.0, "cooldown": 18.0}
    },

    # === PERSISTENT ZONES ===
    {
        "id": "tornado_001",
        "name": "Tornado",
        "description": "Crea un tornado: zona de daño contínuo por 5s.",
        "flavor_text": "Remolino.",
        "category": "zone",
        "type": "damage",
        "target_resolver": {"kind": "player_aoe", "params": {"radius": 3.0}},
        "designed_max": {"dpt": 8.0, "duration": 5.0, "radius": 3.0, "tick_interval": 0.5,
                          "cooldown": 10.0, "stamina": 25.0},
        "atoms": [{
            "type": "persistent_zone",
            "params": {"dpt": 8.0, "duration": 5.0, "radius": 3.0,
                       "tick_interval": 0.5, "element": "air", "slow_inside": 0.3},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 25.0, "cooldown": 10.0}
    },
    {
        "id": "hurricane_001",
        "name": "Hurricane",
        "description": "Huracán: zona de daño contínuo y slow por 6s.",
        "flavor_text": "Huracán.",
        "category": "zone",
        "type": "damage",
        "target_resolver": {"kind": "player_aoe", "params": {"radius": 5.0}},
        "designed_max": {"dpt": 10.0, "duration": 6.0, "radius": 5.0, "tick_interval": 0.5,
                          "cooldown": 14.0, "stamina": 30.0},
        "atoms": [{
            "type": "persistent_zone",
            "params": {"dpt": 10.0, "duration": 6.0, "radius": 5.0,
                       "tick_interval": 0.5, "element": "air", "slow_inside": 0.5},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 30.0, "cooldown": 14.0}
    },
    {
        "id": "thorny_vine_001",
        "name": "Thorny Vine",
        "description": "Zona de vides espinosas. Daño + root 4s.",
        "flavor_text": "¡Vides!",
        "category": "zone",
        "type": "damage",
        "target_resolver": {"kind": "player_aoe", "params": {"radius": 3.0}},
        "designed_max": {"dpt": 7.0, "duration": 4.0, "radius": 3.0, "tick_interval": 1.0,
                          "cooldown": 10.0, "stamina": 22.0},
        "atoms": [{
            "type": "persistent_zone",
            "params": {"dpt": 7.0, "duration": 4.0, "radius": 3.0,
                       "tick_interval": 1.0, "element": "earth", "slow_inside": 0.7},
            "applies_to_target": "primary"
        },{
            "type": "status",
            "params": {"kind": "root", "duration": 4.0, "magnitude": 1.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 22.0, "cooldown": 10.0}
    },
    {
        "id": "death_call_001",
        "name": "Death Call",
        "description": "Invoca espíritus que atacan al objetivo durante 4s.",
        "flavor_text": "¡Vengan, almas!",
        "category": "summon",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"dpt": 12.0, "duration": 4.0, "tick_interval": 0.5,
                          "cooldown": 14.0, "stamina": 25.0},
        "atoms": [{
            "type": "dot",
            "params": {"dpt": 12.0, "duration": 4.0, "tick_interval": 0.5, "element": "dark"},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 25.0, "cooldown": 14.0}
    },
    {
        "id": "summon_minion_001",
        "name": "Summon Minion",
        "description": "Invoca un esbirro menor. (placeholder: buff de stats)",
        "flavor_text": "¡Levántate!",
        "category": "summon",
        "type": "control",
        "target_resolver": {"kind": "self", "params": {}},
        "designed_max": {"duration": 20.0, "cooldown": 30.0, "stamina": 30.0, "shield_amount": 50.0},
        "atoms": [{
            "type": "shield",
            "params": {"shield_amount": 50.0, "duration": 20.0, "element": "dark"},
            "applies_to_target": "primary"
        },{
            "type": "buff",
            "params": {"stat": "damage_mult", "value": 1.2, "kind": "multiply", "duration": 20.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 30.0, "cooldown": 30.0}
    },
    {
        "id": "mirror_image_001",
        "name": "Mirror Image",
        "description": "Crea un decoy. (placeholder: i-frames 1s)",
        "flavor_text": "¿Cuál es el real?",
        "category": "tactical",
        "type": "control",
        "target_resolver": {"kind": "self", "params": {}},
        "designed_max": {"duration": 4.0, "cooldown": 18.0, "stamina": 20.0},
        "atoms": [{
            "type": "move",
            "params": {"kind": "teleport", "distance": 4.0, "duration": 0.0,
                       "target_relative": "backward", "i_frames": True, "blink": True},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 20.0, "cooldown": 18.0}
    },
    {
        "id": "chain_lightning_001",
        "name": "Chain Lightning",
        "description": "Rayo que salta al target. (placeholder: hit + stun)",
        "flavor_text": "Salta.",
        "category": "chain",
        "type": "damage",
        "target_resolver": {"kind": "player", "params": {}},
        "designed_max": {"amount": 70.0, "cooldown": 5.0, "stamina": 18.0},
        "atoms": [{
            "type": "hit",
            "params": {"amount": 70.0, "damage_type": "energy", "element": "lightning",
                       "knockback": 1.0, "applies_status": "stun",
                       "status_chance": 0.4, "status_duration": 1.0},
            "applies_to_target": "primary"
        }],
        "costs": {"stamina": 18.0, "cooldown": 5.0}
    },
]

# === Generar ===
print(f"Generating {len(SKILLS)} skills to {OUT_DIR}/...")
for s in SKILLS:
    write_skill(
        skill_id=s["id"],
        name=s["name"],
        description=s["description"],
        flavor_text=s.get("flavor_text", ""),
        category=s["category"],
        skill_type=s["type"],
        target_resolver=s["target_resolver"],
        designed_max=s["designed_max"],
        atoms=s["atoms"],
        costs=s["costs"],
        vfx=s.get("vfx"),
        icon_hint=s.get("icon_hint", ""),
    )
print(f"Done. {len(SKILLS)} skills created.")
