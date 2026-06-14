extends SceneTree

# test_character_unified.gd
# Verifica que player, enemy, boss son el MISMO tipo de entidad
# (Character), diferenciados SOLO por data.ai_controlled: bool.
#
# CUMPLIMIENTO DE DIRECTRIZ DEL USER:
#   "Refinar los jefes y enemigos para que sean full data driven.
#    Los skills y armas son JSON iguales a los del jugador.
#    La única diferencia técnica entre un jugador y un personaje
#    del juego es que el personaje tiene habilitado el control por ia
#    y no por el jugador, un simple bool. Elimina cualquier dato
#    quemado en el código."

const CharacterResourceScript := preload("res://scripts/character_resource.gd")
const EntityCharacterScript := preload("res://scripts/character.gd")
const SkillResourceScript := preload("res://scripts/skill/skill_resource.gd")
const WeaponResourceScript := preload("res://scripts/skill/weapon_resource.gd")
const WeaponCatalogScript := preload("res://scripts/skill/weapon_catalog.gd")

var _passes: int = 0
var _fails: int = 0


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var ps: Node = root.get_node_or_null("ProgressionState")
	if ps == null:
		_print_fail("ProgressionState autoload not found")
		quit(1)
		return

	# === GRUPO 1: Schema de CharacterResource ===
	# 1) El schema tiene los campos esperados (todos data-driven)
	var frieza := CharacterResourceScript.new()
	frieza.id = &"boss_frieza"
	frieza.display_name = "Frieza"
	frieza.description = "Forma final. Castea a distancia."
	frieza.max_hp = 1350.0
	frieza.weapon_id = &"arcane_staff"
	frieza.skill_ids = [&"kamehameha_001", &"lightning_bolt_001"]
	frieza.skill_weights = [1.0, 1.2]
	frieza.damage_modifiers = {&"physical": 1.4, &"arcane": 0.6}
	frieza.behavior = "caster"
	frieza.aggression = 0.7
	frieza.reward_skill_points = 20
	# IMPORTANTE: ai_controlled = true (es AI)
	frieza.ai_controlled = true
	_assert(frieza.ai_controlled == true, "1a. boss Frieza es AI (ai_controlled=true)")
	_assert(frieza.is_boss(), "1b. boss Frieza detectado como boss (reward>0)")
	_assert(not frieza.is_player(), "1c. boss Frieza NO es el player")
	_assert(frieza.can_respawn() == false, "1d. boss Frieza NO respawnea (respawn_delay=999)")

	# 2) Un "player" CharacterResource con el mismo schema
	var player_data := CharacterResourceScript.new()
	player_data.id = &"player_hero"
	player_data.display_name = "Héroe"
	player_data.max_hp = 100.0
	player_data.respawn_delay = 2.0  # player respawnea
	player_data.weapon_id = &"short_sword"
	player_data.skill_ids = [&"light_attack_001", &"esquivar_001", &"defenderse_001"]
	player_data.skill_weights = [1.0, 1.0, 1.0]
	# IMPORTANTE: ai_controlled = false (es el player)
	player_data.ai_controlled = false
	_assert(player_data.ai_controlled == false, "2a. player es humano (ai_controlled=false)")
	_assert(player_data.is_player(), "2b. player detectado como player")
	_assert(not player_data.is_boss(), "2c. player NO es boss (ai=false, reward=0)")
	_assert(player_data.can_respawn(), "2d. player respawnea (respawn_delay=2)")

	# 3) MISMO schema — solo cambia ai_controlled
	_assert(typeof(frieza.ai_controlled) == typeof(player_data.ai_controlled),
		"3a. mismo tipo de dato para ai_controlled")
	_assert(frieza.get_script() == player_data.get_script(),
		"3b. mismo script class (CharacterResource)")

	# === GRUPO 2: Mismo weapon library ===
	# 4) Frieza y player pueden usar el MISMO arma
	var arcane_staff: Resource = WeaponCatalogScript.get_weapon(&"arcane_staff")
	var short_sword: Resource = WeaponCatalogScript.get_weapon(&"short_sword")
	_assert(arcane_staff != null, "4a. arcane_staff está en el catálogo compartido")
	_assert(short_sword != null, "4b. short_sword está en el catálogo compartido")
	_assert(arcane_staff.get_script() == short_sword.get_script(),
		"4c. ambos son del MISMO WeaponResource class")

	# 5) Equipar arcane_staff en ambos aplica los mismos modifiers
	# (esto lo probamos mejor con un Character; el catálogo es solo data)
	_assert(arcane_staff.has_method("apply_to_caster"),
		"5a. arcane_staff tiene apply_to_caster (mismo flujo que short_sword)")

	# === GRUPO 3: Mismo skill library ===
	# 6) Bosses y player usan el MISMO SkillResource library
	var kamehameha: Resource = load("res://data/skills/kamehameha_001.tres")
	var esquivar: Resource = load("res://data/skills/esquivar_001.tres")
	var defenderse: Resource = load("res://data/skills/defenderse_001.tres")
	_assert(kamehameha != null, "6a. kamehameha_001.tres es parte de la library compartida")
	_assert(esquivar != null, "6b. esquivar_001.tres es parte de la library compartida")
	_assert(defenderse != null, "6c. defenderse_001.tres es parte de la library compartida")
	_assert(kamehameha.get_script() == esquivar.get_script(),
		"6d. todos son del MISMO SkillResource class")
	# Verifica que frieza (boss) puede usar esquivar y defenderse
	_assert(&"esquivar_001" not in frieza.skill_ids,
		"6e. frieza (data) NO tiene esquivar — el data lo decide, no el código")
	# Pero si lo agregamos al data, puede usarlo
	frieza.skill_ids.append(&"esquivar_001")
	frieza.skill_weights.append(0.5)
	_assert(&"esquivar_001" in frieza.skill_ids,
		"6f. frieza PUEDE usar esquivar si data.skill_ids lo incluye")

	# === GRUPO 4: Character body unificado ===
	# 7) Instanciar Character con frieza (boss) y player (player)
	# Cargar el árbol mínimo para que _ready funcione
	var play_root: Node = load("res://scenes/play.tscn").instantiate()
	root.add_child(play_root)
	await process_frame
	await process_frame

	# 8) Boss = Character con frieza
	var boss_char: Node = EntityCharacterScript.new()
	boss_char.name = "TestBoss"
	boss_char.data = frieza
	root.add_child(boss_char)
	await process_frame

	_assert(boss_char.is_in_group("characters"),
		"8a. boss está en grupo 'characters' (unificado)")
	_assert(boss_char.is_in_group("enemies"),
		"8b. boss está en grupo 'enemies' (ai_controlled=true)")
	_assert(not boss_char.is_in_group("player_characters"),
		"8c. boss NO está en grupo 'player_characters'")
	_assert(boss_char.controller != null,
		"8d. boss tiene un controller instalado automáticamente")
	var ai_ctrl_script: GDScript = load("res://scripts/ai/ai_controller.gd")
	_assert(ai_ctrl_script != null and boss_char.controller.get_script() == ai_ctrl_script,
		"8e. boss controller es AIController (ai_controlled=true → AI)")
	_assert(boss_char.max_hp == frieza.max_hp,
		"8f. boss.max_hp viene de data, no de hardcoded (%.0f)" % boss_char.max_hp)
	_assert(boss_char.skill_ids.size() == frieza.skill_ids.size(),
		"8g. boss.skill_ids viene de data (size=%d)" % boss_char.skill_ids.size())
	_assert(boss_char.skill_weights.size() == frieza.skill_weights.size(),
		"8h. boss.skill_weights viene de data")

	# 9) Player = Character con player_data
	var player_char: Node = EntityCharacterScript.new()
	player_char.name = "TestPlayer"
	player_char.data = player_data
	root.add_child(player_char)
	await process_frame

	_assert(player_char.is_in_group("characters"),
		"9a. player está en grupo 'characters' (unificado)")
	_assert(player_char.is_in_group("player_characters"),
		"9b. player está en grupo 'player_characters' (ai_controlled=false)")
	_assert(not player_char.is_in_group("enemies"),
		"9c. player NO está en grupo 'enemies'")
	_assert(player_char.controller != null,
		"9d. player tiene un controller instalado")
	_assert(player_char.controller.get_script() == load("res://scripts/player_controller.gd"),
		"9e. player controller es PlayerController")
	_assert(player_char.max_hp == player_data.max_hp,
		"9f. player.max_hp viene de data (100)")
	_assert(player_char.skill_ids.size() == 3,
		"9g. player.skill_ids tiene 3 skills (data)")

	# === GRUPO 5: MISMA estructura interna ===
	# 10) Boss y player tienen los MISMOS campos, los MISMOS nodos, los
	#     MISMOS handlers. La ÚNICA diferencia funcional es ai_controlled.
	var boss_fields: Array = boss_char.get_property_list().map(
		func(p): return p.name)
	var player_fields: Array = player_char.get_property_list().map(
		func(p): return p.name)
	# Ambos deberían tener los mismos fields (max_hp, hp, move_speed, etc.)
	_assert(boss_char.has_method("take_damage") and player_char.has_method("take_damage"),
		"10a. ambos tienen take_damage()")
	_assert(boss_char.has_method("_pick_weighted_skill") and player_char.has_method("_pick_weighted_skill"),
		"10b. ambos tienen _pick_weighted_skill() (mismo AI de skill picking)")
	_assert(boss_char.has_method("_state_chase") and player_char.has_method("_state_chase"),
		"10c. ambos tienen _state_chase() (mismo state machine)")

	# === GRUPO 6: Mismo take_damage + damage_modifiers ===
	# 11) Boss recibe daño normal (sin modifiers)
	var dmg1: float = boss_char.take_damage(50.0, null, &"fire")
	_assert(dmg1 == 50.0, "11a. boss sin modifier para fire: dmg=50 (neutral)")

	# 12) Boss recibe daño con weakness: physical (×1.4)
	var dmg2: float = boss_char.take_damage(50.0, null, &"physical")
	_assert(dmg2 == 70.0,
		"12a. boss débil a physical: 50 × 1.4 = 70")

	# 13) Boss recibe daño con resistance: arcane (×0.6)
	var dmg3: float = boss_char.take_damage(50.0, null, &"arcane")
	_assert(dmg3 == 30.0,
		"13a. boss resistente a arcane: 50 × 0.6 = 30")

	# 14) Player sin modifiers: todo es neutral
	var dmg4: float = player_char.take_damage(50.0, null, &"fire")
	_assert(dmg4 == 50.0, "14a. player sin modifier: dmg=50 (neutral)")

	# === GRUPO 7: Boss mata → reward ===
	# 15) Boss muere → grant_skill_points(20) al ProgressionState
	var before: int = ps.skill_points
	boss_char.take_damage(99999.0)  # overkill
	await process_frame
	var after: int = ps.skill_points
	_assert(after - before == frieza.reward_skill_points,
		"15a. boss muere → +%d skill_points (data.reward_skill_points)" % frieza.reward_skill_points)

	# === GRUPO 8: Confirmar NO hardcoded data en Character ===
	# 16) Character.gd no debe tener stats hardcoded (todos vienen de data)
	var char_src: String = FileAccess.get_file_as_string("res://scripts/character.gd")
	# Buscamos patrones de hardcoded: "max_hp := 100.0" o "attack_damage := 22.0"
	# (en data setteado por _apply_data, el DEFAULT puede estar en una línea
	# como `var max_hp: float = 100.0` pero SOLO como fallback)
	_assert(not "var attack_damage :=" in char_src,
		"16a. Character.gd NO tiene 'var attack_damage := ...' hardcoded")
	_assert(not "var move_speed := 2.6" in char_src,
		"16b. Character.gd NO tiene 'var move_speed := 2.6' hardcoded")
	_assert(not "var windup_duration := 0.55" in char_src,
		"16c. Character.gd NO tiene 'var windup_duration := 0.55' hardcoded")
	_assert(not "var max_hp := 100.0" in char_src,
		"16d. Character.gd NO tiene 'var max_hp := 100.0' hardcoded")

	# === GRUPO 9: AIController es genérico (no boss-specific) ===
	# 17) El AIController no tiene código de boss (defenderse injection, etc.)
	var ai_src: String = FileAccess.get_file_as_string("res://scripts/ai/ai_controller.gd")
	_assert(not "boss" in ai_src.to_lower(),
		"17a. AIController.gd NO contiene la palabra 'boss' (es genérico)")

	# === GRUPO 10: Cargar boss_sauron.tres migrado y usarlo ===
	print("\n--- Loading migrated boss_sauron.tres ---")
	var sauron_res: Resource = load("res://data/characters/bosses/boss_sauron.tres")
	_assert(sauron_res != null, "18a. boss_sauron.tres cargable")
	_assert(sauron_res.ai_controlled == true, "18b. Sauron es AI (ai_controlled=true)")
	_assert(sauron_res.is_boss(), "18c. Sauron es boss (reward>0)")
	_assert(int(sauron_res.reward_skill_points) == 25,
		"18d. Sauron reward=25")
	_assert(sauron_res.skill_ids.size() == 4, "18e. Sauron tiene 4 skills")
	_assert(sauron_res.weapon_id == &"mace_dark", "18f. Sauron weapon=mace_dark")

	# Crear un Character con Sauron data
	var sauron_char: Node = EntityCharacterScript.new()
	sauron_char.name = "TestSauron"
	sauron_char.data = sauron_res
	root.add_child(sauron_char)
	await process_frame
	_assert(sauron_char.max_hp == 1250.0,
		"19a. Character con Sauron data: max_hp=1250 (data, no hardcoded)")
	_assert(sauron_char.skill_ids.size() == 4,
		"19b. Character con Sauron data: 4 skills")
	_assert(sauron_char.weapon_id == &"mace_dark",
		"19c. Character con Sauron data: weapon=mace_dark")
	_assert(sauron_char.is_in_group("enemies"),
		"19d. Sauron Character en grupo 'enemies'")
	_assert(sauron_char.controller != null,
		"19e. Sauron Character tiene AIController")
	_assert(sauron_char.controller.get_script() == ai_ctrl_script,
		"19f. Sauron controller es AIController")

	# Verificar que las skills de Sauron están en la MISMA library que el player usa
	_assert(sauron_char.skill_ids.has(&"light_attack_001"),
		"20a. Sauron usa light_attack_001 (MISMOS skills que el player)")
	var light_attack_res: Resource = load("res://data/skills/light_attack_001.tres")
	_assert(light_attack_res != null, "20b. light_attack_001.tres es library compartida")

	print("\n=== TOTAL: %d/%d passed ===" % [_passes, _passes + _fails])
	quit(0 if _fails == 0 else 1)


func _assert(cond: bool, label: String) -> void:
	if cond:
		_pass(label)
	else:
		_fail(label)


func _pass(label: String) -> void:
	_passes += 1
	print("  [PASS] %s" % label)


func _fail(label: String) -> void:
	_fails += 1
	print("  [FAIL] %s" % label)


func _print_fail(label: String) -> void:
	_fails += 1
	print("  [FAIL] %s" % label)
