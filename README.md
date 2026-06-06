# MCP Souls Game

Juego 3rd person souls-like donde un MCP propio del juego permite a un asistente personal
del jugador (Hermes u otro) **crear entidades en el mundo en tiempo real** vía LLM.

## Stack
- Godot 4.6 (motor, souls-like base)
- Python (MCP server + FastAPI bridge)
- Blender 4.5 (generación procedural de assets)

## Estructura
```
mcp-souls-game/
├── project.godot          # config del proyecto
├── scenes/                # .tscn (test_world, player, etc.)
├── scripts/               # .gd (player controller, IA, etc.)
├── assets/
│   ├── meshes/            # .glb/.gltf importados
│   └── materials/         # .tres materiales
└── addons/                # plugins Godot (godot-mcp, etc.)
```

## Fases
1. ✅ Setup tooling (Godot+Blender en WSL)
2. 🔄 Prototipo souls-like 3rd person (esta fase)
3. ⏳ Servidor MCP + FastAPI bridge
4. ⏳ Integración LLM↔MCP↔juego
