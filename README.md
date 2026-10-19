# 🤖 opengame

> Prototipo de juego en Godot 4 donde todo se define en un RuleBook en JSON: cada acción, de caminar a lanzar un hechizo, es una *skill*.

**[▶ Ver el código](https://github.com/juliangdeveloper/opengame)** · prototipo, sin demo web por ahora

## Qué es
- `rulebook/` es la especificación del juego, independiente del motor: universo, sistemas (elementos, estados, stamina, progresión), skills, memorias de cada entidad, controles y escenas.
- El motor en Godot (`scripts/`, `scenes/`) lee el RuleBook y ejecuta las skills; ninguna acción está fija en el código.
- Los personajes y objetos son primitivas 3D con animación procedural, sin modelos ni rigs externos.
- La idea de fondo es que un LLM pueda crear y equilibrar skills como Dungeon Master. Esa primera versión, con su puente MCP, está guardada en [`_legacy/`](_legacy/).

## Cómo probarlo
- Abre la carpeta en **Godot 4.6** y ejecuta la escena principal (`scenes/play.tscn`).
- Teclado y mouse: `WASD` caminar, mouse para la cámara, `Space` saltar, `Shift` correr, clic izquierdo/derecho y `1`–`6` para las skills, `Q` proyectil. También tiene mapeo para gamepad (ver `rulebook/controls/default_bindings.json`).

## Stack
Godot 4.6 (GDScript) y especificación del juego en JSON.

---

Más proyectos: https://juliangdeveloper.github.io/
