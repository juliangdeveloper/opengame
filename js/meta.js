import { APP_ID, APP_VERSION, PROYECTO } from "./config.js";

const CLAVE = "meta.v1." + APP_ID;

function bloque(p) {
  if (!p || typeof p.objetivo !== "string" || !p.objetivo.trim()) return null;
  if (p.fase !== 2 || p.fase_estado !== 1 || p.fases_completadas !== 1) return null;
  return {
    objetivo: p.objetivo,
    fase: p.fase,
    fase_estado: p.fase_estado,
    fases_completadas: p.fases_completadas,
    tipo: p.tipo
  };
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
