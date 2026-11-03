## Il tavolo in 3D: i due tabelloni del campo (dentro e fuori), le miniature dei personaggi,
## il segnalatore della fase, i danni su Caldaia e Porta, i mazzi e la neve che cade.
## Si gira trascinando col mouse (o col dito), si avvicina con la rotella.
class_name Plancia3D
extends Node3D

signal spazio_cliccato(spazio: String)

var cam: Camera3D
var perno: Node3D
var yaw := 0.0
var pitch := -64.0
var dist := 7.0
var trascina := false
var mini := {}          # pg -> Node3D
var segnalino: Node3D
var danni_caldaia: Array = []
var danni_porta: Array = []
var mazzi := {}         # nome -> MeshInstance3D (pila di carte)
var falo: MeshInstance3D
var evento_mesh: MeshInstance3D
var neve: GPUParticles3D
var pavimento: MeshInstance3D
var aree := {}          # spazio -> Area3D
var luce: DirectionalLight3D
var fase_corrente := 0

## I due tabelloni: "fuori" a sinistra, "dentro" a destra. Dimensioni del tabellone nel mondo.
const LARGO := 3.12
const PROFONDO := 3.49
const CENTRO_FUORI := Vector3(-1.62, 0, 0)
const CENTRO_DENTRO := Vector3(1.62, 0, 0)
## Punti notevoli in coordinate dell'illustrazione del tabellone (0..1, origine in alto a sinistra).
const UV_FUORI := {"fase1": Vector2(0.2, 0.64), "fase2": Vector2(0.5, 0.64), "fase3": Vector2(0.8, 0.64),
	"mazzo_fase1": Vector2(0.2, 0.425), "mazzo_fase2": Vector2(0.5, 0.425), "mazzo_fase3": Vector2(0.8, 0.425),
	"elicottero": Vector2(0.86, 0.13), "vulnerabili": Vector2(0.56, 0.13), "scarti_fase": Vector2(0.19, 0.13),
	"porta": Vector2(0.1, 0.945), "turni": Vector2(0.09, 0.775), "mazzo_vulnerabili": Vector2(0.56, 0.13)}
const UV_DENTRO := {"officina": Vector2(0.25, 0.735), "magazzino": Vector2(0.755, 0.735),
	"mazzo_officina": Vector2(0.25, 0.495), "mazzo_magazzino": Vector2(0.755, 0.495),
	"scarti": Vector2(0.25, 0.13), "falo": Vector2(0.755, 0.13), "caldaia": Vector2(0.1, 0.945),
	"mazzo_eventi": Vector2(1.12, 0.3), "evento": Vector2(1.12, 0.62)}

static func punto(nome: String) -> Vector3:
	if UV_FUORI.has(nome):
		var u: Vector2 = UV_FUORI[nome]
		return CENTRO_FUORI + Vector3((u.x - 0.5) * LARGO, 0, (u.y - 0.5) * PROFONDO)
	if UV_DENTRO.has(nome):
		var u2: Vector2 = UV_DENTRO[nome]
		return CENTRO_DENTRO + Vector3((u2.x - 0.5) * LARGO, 0, (u2.y - 0.5) * PROFONDO)
	return Vector3.ZERO

func _ready() -> void:
	_ambiente()
	_tavolo()
	_tabelloni()
	_camera()

func _ambiente() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.05, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.65, 0.8)
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Color(0.12, 0.16, 0.24)
	e.fog_density = 0.035
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	luce = DirectionalLight3D.new()
	luce.rotation_degrees = Vector3(-55, 30, 0)
	luce.light_color = Color(0.92, 0.95, 1.0)
	luce.light_energy = 1.05
	luce.shadow_enabled = true
	add_child(luce)
	var lampada := OmniLight3D.new()
	lampada.position = Vector3(1.6, 1.6, 0.4)
	lampada.light_color = Color(1.0, 0.78, 0.5)
	lampada.light_energy = 0.9
	lampada.omni_range = 4.0
	add_child(lampada)

func _tavolo() -> void:
	pavimento = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(16, 16)
	pavimento.mesh = pm
	pavimento.position.y = -0.03
	add_child(pavimento)
	imposta_fase(1)
	# neve che cade sul tavolo
	neve = GPUParticles3D.new()
	neve.amount = 700
	neve.lifetime = 7.0
	neve.preprocess = 6.0
	neve.visibility_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 8, 16))
	var pr := ParticleProcessMaterial.new()
	pr.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pr.emission_box_extents = Vector3(6, 0.1, 5)
	pr.direction = Vector3(0.25, -1, 0.1)
	pr.spread = 12.0
	pr.initial_velocity_min = 0.35
	pr.initial_velocity_max = 0.7
	pr.gravity = Vector3(0, -0.15, 0)
	pr.scale_min = 0.6
	pr.scale_max = 1.4
	neve.process_material = pr
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.012)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.albedo_color = Color(0.95, 0.97, 1.0, 0.85)
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = qm
	neve.draw_pass_1 = q
	neve.position = Vector3(0, 3.2, 0)
	add_child(neve)

func imposta_fase(f: int) -> void:
	if f == fase_corrente:
		return
	fase_corrente = f
	var mat := StandardMaterial3D.new()
	var tex: Texture2D = load("res://assets/3d/pavimento_%d.webp" % clamp(f, 1, 3))
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(3, 3, 3)
	mat.albedo_color = Color(0.32, 0.36, 0.45)
	mat.roughness = 0.9
	pavimento.material_override = mat

func _carica(path: String) -> Node3D:
	var scena: PackedScene = load(path)
	return scena.instantiate()

func _tabellone(tex: String, centro: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(LARGO, PROFONDO)
	mi.mesh = pm
	var mt := StandardMaterial3D.new()
	mt.albedo_texture = load(tex)
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mt.alpha_scissor_threshold = 0.5
	mt.roughness = 0.75
	mt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = mt
	mi.position = centro
	add_child(mi)
	# spessore del cartone
	var sotto := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(LARGO, 0.03, PROFONDO * 0.86)
	sotto.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.08, 0.09, 0.12)
	sotto.material_override = sm
	sotto.position = centro + Vector3(0, -0.016, -PROFONDO * 0.07)
	add_child(sotto)

func _tabelloni() -> void:
	_tabellone("res://assets/3d/tabellone_fuori.webp", CENTRO_FUORI)
	_tabellone("res://assets/3d/tabellone_dentro.webp", CENTRO_DENTRO)
	for sp in ["officina", "magazzino", "fase1", "fase2", "fase3", "elicottero"]:
		var a := Area3D.new()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.7, 0.2, 1.0)
		cs.shape = bx
		a.add_child(cs)
		a.position = punto(sp) + Vector3(0, 0.05, 0)
		a.input_event.connect(_on_area.bind(sp))
		add_child(a)
		aree[sp] = a
	# segnalino della fase
	segnalino = Node3D.new()
	var sg := _carica("res://assets/3d/segnalino_fase.glb")
	sg.scale = Vector3.ONE * 0.55
	sg.position.y = 0.17 * 0.55
	var smt := StandardMaterial3D.new()
	smt.albedo_color = Color(0.85, 0.12, 0.1)
	smt.metallic = 0.3
	_materiale(sg, smt)
	segnalino.add_child(sg)
	add_child(segnalino)
	# pile di carte sui mazzi, con il dorso vero delle carte
	for nm in ["officina", "magazzino", "fase1", "fase2", "fase3", "vulnerabili", "eventi"]:
		var pila := Node3D.new()
		var lato := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.4, 1.0, 0.55)
		lato.mesh = b
		var ml := StandardMaterial3D.new()
		ml.albedo_color = Color(0.82, 0.84, 0.86)
		lato.material_override = ml
		lato.position.y = 0.5
		pila.add_child(lato)
		var top := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.4, 0.55)
		top.mesh = pm
		var mt := StandardMaterial3D.new()
		mt.albedo_texture = load("res://assets/carte/retro_%s.webp" % nm)
		top.material_override = mt
		top.position.y = 1.001
		pila.add_child(top)
		pila.position = _pos_mazzo(nm)
		add_child(pila)
		mazzi[nm] = pila
	# l'evento del campo scoperto, accanto al mazzo degli eventi
	evento_mesh = MeshInstance3D.new()
	var em := PlaneMesh.new()
	em.size = Vector2(0.62, 0.62 * 0.625 / 0.733 * 1.0)
	evento_mesh.mesh = em
	evento_mesh.position = punto("evento") + Vector3(0, 0.012, 0)
	evento_mesh.visible = false
	add_child(evento_mesh)
	for k in 6:
		danni_caldaia.append(_cubetto(Color(0.85, 0.08, 0.06)))
		danni_porta.append(_cubetto(Color(0.85, 0.08, 0.06)))
	falo = MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.38, 0.01, 0.52)
	falo.mesh = fb
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.55, 0.15)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.4, 0.05)
	fm.emission_energy_multiplier = 0.0
	falo.material_override = fm
	falo.position = punto("falo") + Vector3(0, 0.01, 0)
	add_child(falo)

func _materiale(n: Node, mt: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = mt
	for c in n.get_children():
		_materiale(c, mt)

func _pos_mazzo(nm: String) -> Vector3:
	return punto("mazzo_" + nm) + Vector3(0, 0.002, 0)

func _cubetto(c: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.09, 0.09, 0.09)
	m.mesh = b
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.roughness = 0.4
	m.material_override = mt
	m.visible = false
	add_child(m)
	return m

func _camera() -> void:
	perno = Node3D.new()
	add_child(perno)
	cam = Camera3D.new()
	cam.fov = 46
	perno.add_child(cam)
	_aggiorna_camera()

func _aggiorna_camera() -> void:
	perno.rotation_degrees = Vector3(pitch, yaw, 0)
	cam.position = Vector3(0, 0, dist)
	perno.position = Vector3(0.45, 0, 0.3)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT or ev.button_index == MOUSE_BUTTON_RIGHT:
			trascina = ev.pressed
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			dist = max(2.6, dist - 0.35)
			_aggiorna_camera()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			dist = min(10.0, dist + 0.35)
			_aggiorna_camera()
	elif ev is InputEventMouseMotion and trascina:
		yaw -= ev.relative.x * 0.3
		pitch = clamp(pitch - ev.relative.y * 0.25, -88.0, -18.0)
		_aggiorna_camera()
	elif ev is InputEventMagnifyGesture:
		dist = clamp(dist / ev.factor, 2.6, 10.0)
		_aggiorna_camera()

func ruota(dx: float, dy: float) -> void:
	yaw -= dx
	pitch = clamp(pitch - dy, -88.0, -18.0)
	_aggiorna_camera()

func zoom(d: float) -> void:
	dist = clamp(dist + d, 2.6, 10.0)
	_aggiorna_camera()

func _on_area(_cam, ev, _pos, _n, _idx, sp: String) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		spazio_cliccato.emit(sp)

## Aggiorna il tavolo dallo stato del motore.
func aggiorna(m: Motore) -> void:
	var s := m.s
	imposta_fase(m.fase())
	# miniature: si raggruppano sullo spazio, un po' sparse
	var per_spazio := {}
	for i in s["ordine"]:
		var g: Dictionary = s["giocatori"][i]
		var pg: String = g["pg"]
		if not mini.has(pg):
			var n := Node3D.new()
			var fig := _carica("res://assets/3d/mini_%s.glb" % pg)
			fig.scale = Vector3.ONE * 0.95
			fig.position.y = 0.26 * 0.95
			n.add_child(fig)
			var mt := StandardMaterial3D.new()
			mt.albedo_color = Dati.PG[pg]["colore"]
			mt.roughness = 0.55
			_materiale(n, mt)
			add_child(n)
			mini[pg] = n
		var nodo: Node3D = mini[pg]
		var sp: String = g["pos"] if g["pos"] != "" else "officina"
		if s["stadio"] == "fine" and g["bordo"]:
			sp = "elicottero"
		if g["morto"]:
			nodo.visible = true
			nodo.rotation_degrees = Vector3(0, 0, 90)
		else:
			nodo.rotation_degrees = Vector3(0, 180 + 25 * (i % 3), 0)
		var k: int = per_spazio.get(sp, 0)
		per_spazio[sp] = k + 1
		var base: Vector3 = punto(sp)
		var off := Vector3((k % 4) * 0.22 - 0.33, 0.0, (k / 4) * 0.24 - 0.05)
		var dest := base + off
		if nodo.position.distance_to(dest) > 0.01:
			var tw := create_tween()
			tw.tween_property(nodo, "position", dest, 0.45).set_trans(Tween.TRANS_SINE)
	# segnalino della fase sul tracciato dei turni
	var t: int = max(0, s["turno"])
	var tot: int = s["turni"].size()
	var per_fase := tot / 3
	var f := int(t / per_fase)
	var dentro_fase := t % per_fase
	# il tracciato dei turni corre lungo il bordo inferiore del tabellone "fuori"
	var u := 0.115 + f * 0.3 + (dentro_fase + (1 if per_fase == 5 else 0)) * 0.047
	segnalino.position = CENTRO_FUORI + Vector3((u - 0.5) * LARGO, 0.02, (0.775 - 0.5) * PROFONDO)
	# danni
	for k in danni_caldaia.size():
		danni_caldaia[k].visible = k < s["caldaia"]
		danni_caldaia[k].position = punto("caldaia") + Vector3(0.25 + k * 0.13, 0.05, 0)
	for k in danni_porta.size():
		danni_porta[k].visible = k < s["porta"]
		danni_porta[k].position = punto("porta") + Vector3(0.25 + k * 0.13, 0.05, 0)
	# altezza delle pile
	for nm in mazzi:
		var n2: int = s["mazzi"][nm].size()
		var pila: Node3D = mazzi[nm]
		pila.visible = n2 > 0
		pila.scale = Vector3(1, max(0.004, n2 * 0.0035), 1)
	if s["evento"].is_empty():
		evento_mesh.visible = false
	else:
		evento_mesh.visible = true
		var mt2 := StandardMaterial3D.new()
		mt2.albedo_texture = load("res://assets/carte/%s.webp" % s["evento"]["img"])
		evento_mesh.material_override = mt2
	var acceso: float = clamp(s["falo"].size() / 5.0, 0.0, 1.0)
	falo.visible = s["falo"].size() > 0
	(falo.material_override as StandardMaterial3D).emission_energy_multiplier = acceso * 1.2
	falo.scale = Vector3(1, 1 + s["falo"].size() * 2, 1)
