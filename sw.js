const CACHE = "opengame-v0.1.2";
const ASSETS = [
  "./",
  "./index.html",
  "./css/styles.css?v=0.1.2",
  "./js/config.js",
  "./js/meta.js",
  "./js/app.js?v=0.1.2",
  "./manifest.json?v=0.1.2",
  "./favicon.svg",
  "./rulebook/rulebook.json",
  "./rulebook/universe/lore.json",
  "./rulebook/universe/physics.json",
  "./rulebook/entities/player.json",
  "./rulebook/entities/npcs/guide.json",
  "./rulebook/entities/objects/game_objects.json",
  "./rulebook/systems/elements.json",
  "./rulebook/systems/progression.json",
  "./rulebook/systems/status_effects.json",
  "./rulebook/systems/stamina.json",
  "./rulebook/systems/weight.json",
  "./rulebook/systems/effect_resistance.json",
  "./rulebook/skills/guide/guide.json",
  "./rulebook/skills/movement/locomotion.json",
  "./rulebook/skills/combat/melee.json",
  "./rulebook/skills/magic/elemental.json",
  "./rulebook/skills/control/camera.json",
  "./rulebook/memories/memory_system.json",
  "./rulebook/memories/player_memory.json",
  "./rulebook/memories/templates/goblin_warrior.json",
  "./rulebook/memories/templates/guide_npc.json",
  "./rulebook/memories/templates/npc_template.json",
  "./rulebook/controls/default_bindings.json",
  "./rulebook/scenes/test_world.json"
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  event.respondWith(
    fetch(event.request).then((response) => {
      if (response.ok) {
        const copy = response.clone();
        caches.open(CACHE).then((cache) => cache.put(event.request, copy)).catch(() => {});
      }
      return response;
    }).catch(() => caches.match(event.request).then((hit) => hit || caches.match("./index.html")))
  );
});
