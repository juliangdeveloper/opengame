import { APP_ID, APP_VERSION, PROYECTO } from "./config.js";

const CLAVE = "meta.v1." + APP_ID;

function aportesValidos(lista) {
  if (!Array.isArray(lista)) return null;
  const out = [];
  const seen = {};
  for (let i = 0; i < lista.length; i++) {
    const it = lista[i];
    if (!it || typeof it !== "object" || Array.isArray(it)) return null;
    const id = it.id;
    const fuente = it.fuente;
    const aporte = it.aporte;
    if (typeof id !== "string" || !/^[a-z][a-z0-9]*$/.test(id)) return null;
    if (fuente !== "creacion" && fuente !== "uso") return null;
    if (!Number.isInteger(aporte) || aporte < 1 || aporte > 3) return null;
    const key = id + "\n" + fuente;
    if (seen[key]) return null;
    if (Object.keys(it).length !== 3) return null;
    seen[key] = true;
    out.push({ id, aporte, fuente });
  }
  return out;
}

function bloque(p) {
  if (!p || typeof p.objetivo !== "string" || !p.objetivo.trim()) return null;
  if (p.fase !== 2 || p.fase_estado !== 1 || p.fases_completadas !== 1) return null;
  const out = {
    objetivo: p.objetivo,
    fase: p.fase,
    fase_estado: p.fase_estado,
    fases_completadas: p.fases_completadas,
    tipo: p.tipo
  };
  if (p.bloqueada === true) out.bloqueada = true;
  if (p.aportes !== undefined) {
    const aportes = aportesValidos(p.aportes);
    if (!aportes) return null;
    out.aportes = aportes;
  }
  return out;
}

export function publicarMeta() {
  const proyecto = bloque(PROYECTO);
  if (!proyecto) return null;
  let previo = null;
  try {
    previo = JSON.parse(localStorage.getItem(CLAVE) || "null");
  } catch {
    previo = null;
  }
  const record = {
    v: 1,
    slug: APP_ID,
    version: APP_VERSION,
    updatedAt: new Date().toISOString(),
    stats: previo && previo.stats && typeof previo.stats === "object" ? previo.stats : {},
    logros: Array.isArray(previo && previo.logros) ? previo.logros : [],
    hitos: previo && previo.hitos && typeof previo.hitos === "object" ? previo.hitos : {},
    proyecto
  };
  try {
    localStorage.setItem(CLAVE, JSON.stringify(record));
  } catch {
    return record;
  }
  try {
    if (window.parent && window.parent !== window) {
      window.parent.postMessage({ type: "meta", key: CLAVE, data: record }, location.origin);
    }
  } catch {
  }
  return record;
}
