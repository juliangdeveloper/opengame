export const APP_ID = "opengame";
export const APP_VERSION = "0.1.2";
export const PROYECTO = Object.freeze({
  objetivo: "El juego es este rulebook: cada acción del mundo tejido es una skill, y el Guía entrega las siguientes.",
  fase: 2,
  fase_estado: 1,
  fases_completadas: 1,
  tipo: "proyecto",
  aportes: Object.freeze([
    Object.freeze({ stat: "Programación", exp: 3, fuente: "creacion" }),
    Object.freeze({ stat: "Diseño", exp: 21, fuente: "creacion" }),
    Object.freeze({ stat: "Narrativa", exp: 1, fuente: "creacion" })
  ])
});

export const SECCIONES = Object.freeze([
  Object.freeze({ id: "documento", titulo: "El rulebook", archivos: Object.freeze(["rulebook/rulebook.json"]) }),
  Object.freeze({ id: "universo", titulo: "Universo", archivos: Object.freeze(["rulebook/universe/lore.json"]) }),
  Object.freeze({ id: "fisica", titulo: "Física", archivos: Object.freeze(["rulebook/universe/physics.json"]) }),
  Object.freeze({ id: "personajes", titulo: "Personajes", archivos: Object.freeze([
    "rulebook/entities/player.json",
    "rulebook/entities/npcs/guide.json",
    "rulebook/memories/templates/goblin_warrior.json"
  ]) }),
  Object.freeze({ id: "objetos", titulo: "Objetos", archivos: Object.freeze(["rulebook/entities/objects/game_objects.json"]) }),
  Object.freeze({ id: "elementos", titulo: "Elementos", archivos: Object.freeze(["rulebook/systems/elements.json"]) }),
  Object.freeze({ id: "progresion", titulo: "Progresión", archivos: Object.freeze(["rulebook/systems/progression.json"]) }),
  Object.freeze({ id: "estados", titulo: "Estados", archivos: Object.freeze(["rulebook/systems/status_effects.json"]) }),
  Object.freeze({ id: "aguante", titulo: "Aguante", archivos: Object.freeze(["rulebook/systems/stamina.json"]) }),
  Object.freeze({ id: "peso", titulo: "Peso", archivos: Object.freeze([
    "rulebook/systems/weight.json",
    "rulebook/systems/effect_resistance.json"
  ]) }),
  Object.freeze({ id: "skills", titulo: "Skills", archivos: Object.freeze([
    "rulebook/skills/guide/guide.json",
    "rulebook/skills/movement/locomotion.json",
    "rulebook/skills/combat/melee.json",
    "rulebook/skills/magic/elemental.json",
    "rulebook/skills/control/camera.json"
  ]) }),
  Object.freeze({ id: "memorias", titulo: "Memorias", archivos: Object.freeze([
    "rulebook/memories/memory_system.json",
    "rulebook/memories/player_memory.json",
    "rulebook/memories/templates/guide_npc.json",
    "rulebook/memories/templates/npc_template.json"
  ]) }),
  Object.freeze({ id: "controles", titulo: "Controles", archivos: Object.freeze(["rulebook/controls/default_bindings.json"]) }),
  Object.freeze({ id: "escena", titulo: "Escena", archivos: Object.freeze(["rulebook/scenes/test_world.json"]) })
]);

export const TEXT = Object.freeze({
  marca: "opengame",
  vacio: "Esta parte del rulebook no trae texto.",
  error: "No se pudo leer el rulebook.",
  fuerte: "Fuerte contra",
  debil: "Débil contra"
});
