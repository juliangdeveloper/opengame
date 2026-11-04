import { APP_VERSION, SECCIONES, TEXT } from "./config.js";
import { publicarMeta } from "./meta.js";

const OCULTOS = {
  atoms: true,
  params: true,
  engine_mapping: true,
  godot_data_mapping: true,
  engine_contract: true,
  skill_flow: true,
  atom_types: true,
  skill_flow_syntax: true,
  memory_file: true,
  controller: true,
  input_device_schema: true,
  position: true,
  rotation: true,
  environment: true
};

const ETIQUETA = {
  premise: "Premisa",
  description: "Descripción",
  setting: "Escenario",
  the_guide: "El Guía",
  player_origin: "Origen",
  genre: "Género",
  name: "Nombre",
  title: "Título",
  nature: "Naturaleza",
  role: "Papel",
  personality: "Carácter",
  visual_hint: "Presencia",
  mechanical_role: "En el sistema",
  rules_of_reality: "Reglas de la realidad",
  era: "Época",
  previous_life: "Vida anterior",
  rebirth_moment: "El despertar",
  initial_state: "Al nacer",
  design_principles: "Principios",
  structure: "Partes",
  elements: "Elementos",
  attributes: "Atributos",
  elemental_statuses: "Estados elementales",
  classic_statuses: "Estados",
  world_physics: "Gravedad",
  movement_rules: "Movimiento",
  combat_rules: "Combate",
  time_scale: "Tiempo",
  display_name: "Nombre",
  behavior: "Conducta",
  stats: "Cifras",
  visual: "Aspecto",
  innate_skills: "Skills de nacimiento",
  learned_skills: "Skills aprendidas",
  examples: "Ejemplos",
  base_properties: "Propiedades",
  rule: "Regla",
  formula: "Fórmula",
  formulas: "Fórmulas",
  bindings: "Controles",
  default_gamepad: "Mando",
  default_keyboard: "Teclado"
};

function texto(valor) {
  if (valor == null) return "";
  if (typeof valor === "string") return valor.trim();
  if (typeof valor === "number" || typeof valor === "boolean") return String(valor);
  return "";
}

function etiqueta(clave) {
  return ETIQUETA[clave] || clave.replace(/_/g, " ");
}

function el(tag, clase, contenido) {
  const n = document.createElement(tag);
  if (clase) n.className = clase;
  if (contenido) n.textContent = contenido;
  return n;
}

function esSkill(item) {
  return !!(item && typeof item === "object" && !Array.isArray(item) && typeof item.name === "string" && typeof item.id === "string");
}

function tarjetaSkill(skill) {
  const art = el("article", "ficha");
  art.appendChild(el("h3", "", skill.name));
  if (texto(skill.description)) art.appendChild(el("p", "", skill.description));
  if (texto(skill.lore)) art.appendChild(el("p", "lore", skill.lore));
  const datos = [];
  if (typeof skill.stamina_cost === "number") datos.push("aguante " + skill.stamina_cost);
  if (typeof skill.cooldown === "number" && skill.cooldown > 0) datos.push("espera " + skill.cooldown);
  if (skill.is_innate === true) datos.push("innata");
  if (datos.length) art.appendChild(el("p", "meta", datos.join(" · ")));
  return art;
}

const YA = { premise: true, description: true, lore: true, rule: true, name: true, title: true, display_name: true, system: true, concept: true, strong_vs: true, weak_vs: true };

function filas(obj) {
  const dl = el("dl", "pares");
  Object.keys(obj).forEach(function (clave) {
    if (OCULTOS[clave] || YA[clave]) return;
    const valor = obj[clave];
    const plano = texto(valor);
    if (!plano) return;
    dl.appendChild(el("dt", "", etiqueta(clave)));
    const dd = el("dd");
    if (clave === "color" && /^#[0-9a-fA-F]{6}$/.test(plano)) {
      const m = el("span", "muestra");
      m.style.background = plano;
      dd.appendChild(m);
    }
    dd.appendChild(document.createTextNode(plano));
    dl.appendChild(dd);
  });
  return dl.childNodes.length ? dl : null;
}

function pintar(dato, profundidad) {
  const caja = document.createDocumentFragment();
  if (dato == null || profundidad > 5) return caja;
  if (typeof dato === "string" || typeof dato === "number" || typeof dato === "boolean") {
    const t = texto(dato);
    if (t) caja.appendChild(el("p", "", t));
    return caja;
  }
  if (Array.isArray(dato)) {
    if (dato.every(esSkill)) {
      dato.forEach(function (skill) { caja.appendChild(tarjetaSkill(skill)); });
      return caja;
    }
    if (dato.every(function (item) { return typeof item === "string" || typeof item === "number"; })) {
      const ul = el("ul");
      dato.forEach(function (item) { ul.appendChild(el("li", "", texto(item))); });
      caja.appendChild(ul);
      return caja;
    }
    dato.forEach(function (item) { caja.appendChild(pintar(item, profundidad + 1)); });
    return caja;
  }
  if (typeof dato !== "object") return caja;
  const titulo = texto(dato.display_name) || texto(dato.name) || texto(dato.title) || texto(dato.system) || texto(dato.concept);
  if (titulo && profundidad > 0) caja.appendChild(el("h3", "", titulo));
  ["premise", "description", "lore", "rule"].forEach(function (clave) {
    const t = texto(dato[clave]);
    if (t) caja.appendChild(el("p", clave === "lore" ? "lore" : "", t));
  });
  if (Array.isArray(dato.strong_vs) || Array.isArray(dato.weak_vs)) {
    const p = el("p", "meta");
    if (dato.strong_vs && dato.strong_vs.length) p.appendChild(document.createTextNode(TEXT.fuerte + " " + dato.strong_vs.join(", ") + ". "));
    if (dato.weak_vs && dato.weak_vs.length) p.appendChild(document.createTextNode(TEXT.debil + " " + dato.weak_vs.join(", ") + "."));
    if (p.textContent) caja.appendChild(p);
  }
  const planos = filas(dato);
  if (planos) caja.appendChild(planos);
  Object.keys(dato).forEach(function (clave) {
    if (OCULTOS[clave]) return;
    const valor = dato[clave];
    if (valor == null || typeof valor === "string" || typeof valor === "number" || typeof valor === "boolean") return;
    if (clave === "premise" || clave === "description" || clave === "lore" || clave === "rule") return;
    if (clave === "strong_vs" || clave === "weak_vs") return;
    const bloque = el("section", "bloque");
    bloque.appendChild(el("h3", "", etiqueta(clave)));
    bloque.appendChild(pintar(valor, profundidad + 1));
    if (bloque.childNodes.length > 1) caja.appendChild(bloque);
  });
  return caja;
}

function nav(activa) {
  const barra = document.getElementById("secciones");
  barra.replaceChildren();
  SECCIONES.forEach(function (sec) {
    const b = el("button", activa === sec.id ? "on" : "", sec.titulo);
    b.type = "button";
    b.setAttribute("aria-pressed", activa === sec.id ? "true" : "false");
    b.addEventListener("click", function () { abrir(sec.id); });
    barra.appendChild(b);
  });
}

function abrir(id) {
  const sec = SECCIONES.find(function (item) { return item.id === id; }) || SECCIONES[0];
  nav(sec.id);
  const hoja = document.getElementById("hoja");
  hoja.replaceChildren(el("h2", "", sec.titulo), el("p", "cargando", "…"));
  location.hash = sec.id;
  Promise.all(sec.archivos.map(function (ruta) {
    return fetch(ruta).then(function (res) {
      if (!res.ok) throw new Error(ruta);
      return res.json();
    });
  })).then(function (datos) {
    hoja.replaceChildren(el("h2", "", sec.titulo));
    datos.forEach(function (dato) { hoja.appendChild(pintar(dato, 0)); });
    if (hoja.childNodes.length < 2) hoja.appendChild(el("p", "", TEXT.vacio));
    hoja.scrollTop = 0;
  }).catch(function () {
    hoja.replaceChildren(el("h2", "", sec.titulo), el("p", "", TEXT.error));
  });
}

function inicio() {
  document.getElementById("version").textContent = TEXT.marca + " v" + APP_VERSION;
  publicarMeta();
  const pedido = (location.hash || "").replace(/^#/, "");
  abrir(SECCIONES.some(function (sec) { return sec.id === pedido; }) ? pedido : SECCIONES[0].id);
}

inicio();

if (!new URLSearchParams(location.search).has("nosw") && "serviceWorker" in navigator) {
  navigator.serviceWorker.register("./sw.js").catch(function () {});
}
