# 🤖 opengame

> Prototipo de juego en Godot 4 diseñado desde un RuleBook en JSON: cada acción, de caminar a lanzar un proyectil, es una *skill*.

**[▶ Ver el código](https://github.com/juliangdeveloper/opengame)** · prototipo, sin demo web por ahora

## Qué es
- `rulebook/` es la especificación del juego, independiente del motor: universo, sistemas (elementos, estados, stamina, progresión), skills, memorias de cada entidad, controles y escenas.
- En Godot (`scripts/`, `scenes/`), cada acción del jugador es una skill hecha de átomos (aparecer, moverse, empujar, dañar) y definida como recurso en `data/skills/`; el mundo se carga desde `rulebook/scenes/`.
- Los personajes y objetos son primitivas 3D con animación procedural, sin modelos ni rigs externos.
- La idea de fondo es que un LLM pueda crear y equilibrar skills como Dungeon Master. Esa primera versión, con su puente MCP, está guardada en [`_legacy/`](_legacy/).

## Cómo probarlo
- Abre la carpeta en **Godot 4.6** y ejecuta la escena principal (`scenes/play.tscn`).
- Teclado y mouse: `WASD` caminar, mouse para la cámara (`Esc` libera el cursor), `Space` saltar, `F` golpe y `Q` proyectil. También funciona con gamepad.

## Stack
Godot 4.6 (GDScript) y especificación del juego en JSON.

---

Más proyectos: https://juliangdeveloper.github.io/

Hecho con ❤️ y 🗡️
