# Mission Schema

> JSON mínimo que el LLM Dungeon Master envía cuando quiere crear una
> misión. El juego se encarga de TODO lo demás: dificultad, enemigos,
> recompensas, balance, modifiers elementales. El LLM solo comunica
> **para qué es la misión** y el juego decide el resto.

---

## Principio

El LLM **no** diseña quests complejas. Solo dice:
- "enseña esta skill" o "enseña este arma"
- (opcional) qué tipo de encuentro quiere

El juego asigna:
- dificultad (la elige el jugador en el menú)
- cantidad y tipo de enemigos
- HP, time limit, damage modifiers
- recompensas (siempre skill points)

---

## Spec del LLM (request a `create_mission`)

```json
{
  "purpose": "teach_skill",
  "target_id": "kamehameha_001",
  "mission_type": "defeat_enemies",
  "title": "Aprende Kamehameha"
}
```

### Campos

| Campo | Requerido | Valores | Default | Descripción |
|---|---|---|---|---|
| `purpose` | sí | `teach_skill`, `teach_weapon` | — | Qué传授 la misión |
| `target_id` | sí | id de skill o weapon | — | ej: `kamehameha_001`, `short_sword` |
| `mission_type` | no | `defeat_enemies`, `1v1`, `timed`, `reach_destination`, `survive`, `cast_skill_n` | `defeat_enemies` | Tipo de encuentro |
| `title` | no | string | auto | Título legible para UI |

### Tipos de misión

| Tipo | Qué pide al jugador | Cuándo se completa |
|---|---|---|
| `defeat_enemies` | Derrotar N enemigos | Todos muertos |
| `1v1` | Derrotar 1 enemigo (boss-like) | El enemigo muere |
| `timed` | Derrotar N enemigos antes del time limit | Todos muertos dentro del tiempo |
| `reach_destination` | Llegar a una zona objetivo (con enemigos defensores) | Jugador entra la zona |
| `survive` | Sobrevivir N segundos con enemigos atacando | Timer llega a 0 con jugador vivo |
| `cast_skill_n` | Usar la skill objetivo N veces | Skill casteada N veces |

---

## Salida de `create_mission`

```json
{
  "mission_id": "mission_001",
  "state": "AVAILABLE",
  "title": "Aprende Kamehameha",
  "purpose": "teach_skill",
  "target_id": "kamehameha_001",
  "mission_type": "defeat_enemies",
  "difficulty_required": true
}
```

La misión queda en estado `AVAILABLE` (sin dificultad asignada).
El jugador la abre en el menú, escoge dificultad 1-5, y el juego
calcula enemigos + recompensas.

---

## Estado de la misión (state machine)

```
AVAILABLE   →  creada por LLM, sin dificultad
  ↓ jugador escoge dificultad
READY       →  dificultad asignada, balance calculado
  ↓ jugador click "Start"
ACTIVE      →  enemigos spawneados, objetivo corriendo
  ↓ objetivo cumplido
COMPLETED   →  recompensas otorgadas (skill points)
  ↓ o ↓
FAILED      →  jugador murió o se acabó el tiempo
ABANDONED   →  jugador renunció
```

Desde COMPLETED/FAILED/ABANDONED el jugador puede:
- **RETRY**: re-spawn con misma config
- **EDIT**: cambiar dificultad → vuelve a READY

---

## Validación

`MissionValidator.validate(spec)` aplica:

1. `purpose` ∈ {`teach_skill`, `teach_weapon`}
2. `target_id` existe en `data/skills/` o `data/weapons/`
3. `mission_type` ∈ {`defeat_enemies`, `1v1`, `timed`, `reach_destination`, `survive`, `cast_skill_n`}
4. `title` ≤ 80 chars si se proporciona

Si pasa → crea `MissionResource` y lo registra en `MissionManager`.

---

## Ejemplo: enseñar Kamehameha

LLM manda:
```json
{
  "purpose": "teach_skill",
  "target_id": "kamehameha_001",
  "mission_type": "1v1",
  "title": "Duelo con Saibaman"
}
```

Jugador escoge dificultad 3. Juego calcula:
- 1 Saibaman con HP × 1.2
- `damage_modifiers`: `fire: 1.8`, `water: 0.32`, `earth: 0.32`, ... (vulnerable a Kamehameha)
- Recompensa: 5 skill points, 1 proficiency
- Time limit: 180s

Jugador click Start → 1 Saibaman spawnea. Si usa Kamehameha (fire), hace daño completo. Si usa light_attack (physical), hace 0.32× daño. Si mata al Saibaman → +5 puntos.
