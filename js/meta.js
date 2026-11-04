import { APP_ID, APP_VERSION, PROYECTO } from "./config.js";

const CLAVE = "meta.v1." + APP_ID;

const APORTE_STAT_MAX = 32;
const APORTE_EXP_MAX = 99;

function aportesValidos(lista) {
  if (!Array.isArray(lista)) return null;
  const out = [];
  const seen = {};
  for (let i = 0; i < lista.length; i++) {
    const it = lista[i];
    if (!it || typeof it !== "object" || Array.isArray(it)) return null;
    const stat = it.stat;
    const exp = it.exp;
    const fuente = it.fuente;
    if (typeof stat !== "string" || !stat.trim() || stat !== stat.trim() || Array.from(stat).length > APORTE_STAT_MAX) return null;
    if (fuente !== "creacion" && fuente !== "uso") return null;
    if (!(Number.isInteger(exp) && exp >= 1 && exp <= APORTE_EXP_MAX)) return null;
    const key = stat + "\n" + fuente;
    if (seen[key]) return null;
    if (Object.keys(it).length !== 3) return null;
    seen[key] = true;
    out.push({ stat: stat, exp: exp, fuente: fuente });
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
