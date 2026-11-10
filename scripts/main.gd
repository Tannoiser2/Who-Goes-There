## Who Goes There? - versione digitale (uso personale).
## Menu, partita contro l'IA, partita online (Firebase), salvataggi, interfaccia e tavolo 3D.
extends Node

const F_TITOLO := preload("res://assets/font/Bangers-Regular.ttf")
const F_TESTO := preload("res://assets/font/BarlowCondensed-Medium.ttf")
const F_GRASSETTO := preload("res://assets/font/BarlowCondensed-Bold.ttf")
const F_DIARIO := preload("res://assets/font/SpecialElite-Regular.ttf")

const C_NOTTE := Color(0.03, 0.05, 0.09, 0.92)
const C_GHIACCIO := Color(0.72, 0.86, 0.96)
const C_GELO := Color(0.42, 0.62, 0.8)
const C_SANGUE := Color(0.78, 0.07, 0.06)
const C_FUOCO := Color(1.0, 0.62, 0.2)
const C_TESTO := Color(0.9, 0.94, 0.98)
const C_SPENTO := Color(0.55, 0.62, 0.7)
const SALVA_LOCALE := "user://partita_whogoesthere.json"

var ui: CanvasLayer
var schermo: Control
var net: Rete
var m: Motore
var ia: IA
var plancia: Plancia3D
var vista: SubViewport

# partita
var in_partita := false
var online := false
var codice := ""
var mio_posto := 0          # posto online (0 = host); in locale 0
var nomi_posti := {}
var attesa := 0.0
var velocita := 1.0
var richiesta_mostrata := -1
var aspetto_rete := false
var ultimo_log := 0
var conoscenze_viste := {}
var salvataggio_in_corso := false
var ultimo_salvataggio := 0.0

# nodi dell'interfaccia di gioco
var top_info: Label
var top_evento: Label
var top_stato: HBoxContainer
var colonna_giocatori: VBoxContainer
var diario: RichTextLabel
var pannello_azioni: VBoxContainer
var titolo_azioni: Label
var mano_box: HBoxContainer
var stato_mio: Label
var tessere_mie: HBoxContainer
var dialogo: PanelContainer
var segreto_btn: Button
var segreto_lbl: Label
var gruppi_aperti := {}
var notifica: PanelContainer
var evento_box: CenterContainer
var cronaca: Label
var cronaca_tw: Tween
var evento_mostrato := ""

func _ready() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	net = Rete.new()
	add_child(net)
	get_tree().root.size_changed.connect(_ridimensiona)
	mostra_menu()

func _ridimensiona() -> void:
	pass

# ============================================================ elementi grafici

func stile(bg: Color, bordo := Color(0, 0, 0, 0), spessore := 0, raggio := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = bordo
	sb.set_border_width_all(spessore)
	sb.set_corner_radius_all(raggio)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb

func etichetta(testo: String, font: Font = F_TESTO, size := 17, col := C_TESTO) -> Label:
	var l := Label.new()
	l.text = testo
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func bottone(testo: String, cb: Callable, col := Color(0.12, 0.2, 0.3), size := 18) -> Button:
	var b := Button.new()
	b.text = testo
	b.add_theme_font_override("font", F_GRASSETTO)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", C_TESTO)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", stile(col, C_GELO * Color(1, 1, 1, 0.5), 1, 5))
	b.add_theme_stylebox_override("hover", stile(col.lightened(0.18), C_GHIACCIO, 1, 5))
	b.add_theme_stylebox_override("pressed", stile(col.darkened(0.2), C_GHIACCIO, 1, 5))
	b.add_theme_stylebox_override("disabled", stile(Color(0.1, 0.12, 0.15), Color(0, 0, 0, 0), 0, 5))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(cb)
	return b

func pannello(bg := C_NOTTE, bordo := Color(0.35, 0.55, 0.75, 0.6)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stile(bg, bordo, 1, 8))
	return p

func immagine(path: String, w: float, h: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.custom_minimum_size = Vector2(w, h)
	t.size = Vector2(w, h)
	return t

func pulisci() -> void:
	if schermo:
		schermo.queue_free()
	schermo = Control.new()
	schermo.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(schermo)
	dialogo = null
	notifica = null

const COLORI_CARTA := {"mat": Color(0.42, 0.3, 0.18), "viola": Color(0.52, 0.22, 0.58), "arancio": Color(0.8, 0.45, 0.08),
	"grigio": Color(0.24, 0.27, 0.31), "rosso": Color(0.66, 0.12, 0.1), "blu": Color(0.14, 0.32, 0.6), "verde": Color(0.2, 0.46, 0.2)}

## Una carta ricomposta: illustrazione originale, titolo e testo in italiano.
func carta(c: Dictionary, w := 124.0, mostra_testo := true) -> PanelContainer:
	var info: Dictionary = Dati.carte()["tipi"].get(c["t"], {})
	var col: Color = COLORI_CARTA.get(info.get("colore", "grigio"), COLORI_CARTA["grigio"])
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", stile(Color(0.06, 0.07, 0.09), col.lightened(0.25), 2, 7))
	p.custom_minimum_size = Vector2(w, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	p.add_child(v)
	var img := immagine("res://assets/carte/%s.webp" % c["img"], w - 16, (w - 16) * 0.72)
	v.add_child(img)
	var tit := etichetta(str(info.get("nome", c["t"])), F_TITOLO, 15 if w < 140 else 18, Color.WHITE)
	tit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tit.add_theme_constant_override("outline_size", 4)
	tit.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", stile(col, Color(0, 0, 0, 0), 0, 3))
	band.add_child(tit)
	v.add_child(band)
	if mostra_testo:
		var tx := etichetta(str(info.get("testo", "")), F_TESTO, 13 if w < 140 else 15, Color(0.88, 0.9, 0.93))
		tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tx.custom_minimum_size = Vector2(w - 16, 0)
		v.add_child(tx)
	return p

func barra(n: int, mx: int, col: Color, w := 9, h := 9) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	for k in mx:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(w, h)
		r.color = col if k < n else Color(0.18, 0.21, 0.26)
		hb.add_child(r)
	return hb

# ============================================================ menu

func mostra_menu() -> void:
	in_partita = false
	if plancia:
		plancia = null
	pulisci()
	var sfondo := ColorRect.new()
	sfondo.color = Color(0.02, 0.03, 0.05)
	sfondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	schermo.add_child(sfondo)
	var cop := immagine("res://assets/ui/copertina.webp", 10, 10)
	cop.set_anchors_preset(Control.PRESET_FULL_RECT)
	cop.modulate = Color(0.55, 0.62, 0.75)
	schermo.add_child(cop)
	var neve := _neve_2d()
	schermo.add_child(neve)
	var centro := HBoxContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	centro.alignment = BoxContainer.ALIGNMENT_CENTER
	schermo.add_child(centro)
	var colonna := VBoxContainer.new()
	colonna.alignment = BoxContainer.ALIGNMENT_CENTER
	colonna.add_theme_constant_override("separation", 10)
	centro.add_child(colonna)
	var t := etichetta("WHO GOES THERE?", F_TITOLO, 84, C_GHIACCIO)
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.1))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	colonna.add_child(t)
	var st := etichetta("Avamposto antartico. Qualcuno di voi non è più umano.", F_DIARIO, 20, Color(0.85, 0.3, 0.28))
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	colonna.add_child(st)
	var spazio := Control.new()
	spazio.custom_minimum_size = Vector2(0, 16)
	colonna.add_child(spazio)
	var box := pannello()
	box.custom_minimum_size = Vector2(430, 0)
	colonna.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	box.add_child(v)
	v.add_child(bottone("NUOVA PARTITA CONTRO L'IA", _menu_nuova, Color(0.14, 0.28, 0.42), 22))
	var continua := bottone("CONTINUA LA PARTITA SALVATA", _menu_continua, Color(0.12, 0.22, 0.3), 20)
	v.add_child(continua)
	v.add_child(bottone("GIOCA ONLINE CON GLI AMICI", _menu_online, Color(0.3, 0.14, 0.14), 20))
	v.add_child(bottone("REGOLE IN BREVE", _menu_regole, Color(0.12, 0.18, 0.24), 18))
	if OS.has_feature("web"):
		v.add_child(bottone("TORNA ALLA LUDOTECA", func(): JavaScriptBridge.eval("location.href = '../'"), Color(0.1, 0.13, 0.17), 16))
	var nota := etichetta("Versione digitale non ufficiale, per uso personale. Gioco di Certifiable Studios.", F_TESTO, 14, C_SPENTO)
	nota.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	colonna.add_child(nota)

func _neve_2d() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := CPUParticles2D.new()
	p.amount = 220
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(900, 10)
	p.position = Vector2(640, -20)
	p.direction = Vector2(0.3, 1)
	p.spread = 15.0
	p.gravity = Vector2(10, 40)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.0
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.92, 0.96, 1.0, 0.8))
	p.texture = ImageTexture.create_from_image(img)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	c.add_child(p)
	return c

var scelta_pg := "mcready"
var scelta_n := 5
var scelta_lunga := false
var scelta_facile := false

func _menu_nuova() -> void:
	pulisci()
	_sfondo_scuro()
	var box := pannello()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(900, 600)
	box.position = Vector2(-450, -300)
	schermo.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)
	v.add_child(etichetta("CHI SEI?", F_TITOLO, 40, C_GHIACCIO))
	v.add_child(etichetta("Scegli il tuo personaggio. Gli altri li guida l'IA: qualcuno, prima o poi, diventerà la Cosa.", F_TESTO, 18, C_SPENTO))
	var griglia := GridContainer.new()
	griglia.columns = 4
	griglia.add_theme_constant_override("h_separation", 10)
	griglia.add_theme_constant_override("v_separation", 10)
	v.add_child(griglia)
	var bottoni := {}
	for pg in Dati.ORDINE_PG:
		var info: Dictionary = Dati.PG[pg]
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(205, 150)
		b.add_theme_stylebox_override("normal", stile(Color(0.08, 0.1, 0.14), Color(0.25, 0.35, 0.45), 1, 6))
		b.add_theme_stylebox_override("pressed", stile(Color(0.12, 0.2, 0.3), C_GHIACCIO, 3, 6))
		b.add_theme_stylebox_override("hover", stile(Color(0.1, 0.15, 0.2), C_GELO, 2, 6))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 6
		hb.offset_top = 6
		b.add_child(hb)
		var img := immagine("res://assets/pg/%s.webp" % pg, 92, 92)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(img)
		var vv := VBoxContainer.new()
		vv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(vv)
		var nm := etichetta(info["nome"], F_TITOLO, 22, info["colore"].lightened(0.3))
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vv.add_child(nm)
		var tt := etichetta("%s\nGrado %d" % [info["titolo"], info["grado"]], F_TESTO, 14, C_TESTO)
		tt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vv.add_child(tt)
		var ab := etichetta(info["unico_nome"], F_GRASSETTO, 14, C_FUOCO)
		ab.custom_minimum_size = Vector2(100, 0)
		ab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vv.add_child(ab)
		b.tooltip_text = info["unico_testo"]
		b.button_pressed = pg == scelta_pg
		b.pressed.connect(func():
			scelta_pg = pg
			for k in bottoni:
				bottoni[k].button_pressed = k == pg)
		bottoni[pg] = b
		griglia.add_child(b)
	var riga := HBoxContainer.new()
	riga.add_theme_constant_override("separation", 8)
	v.add_child(riga)
	riga.add_child(etichetta("Sopravvissuti:", F_GRASSETTO, 20))
	var nb := {}
	for n in range(4, 9):
		var b2 := bottone(str(n), func():
			scelta_n = n
			for k in nb:
				nb[k].modulate = Color(1, 1, 1) if k == n else Color(0.6, 0.6, 0.6), Color(0.14, 0.24, 0.34), 20)
		b2.custom_minimum_size = Vector2(46, 38)
		b2.modulate = Color(1, 1, 1) if n == scelta_n else Color(0.6, 0.6, 0.6)
		nb[n] = b2
		riga.add_child(b2)
	var lunga := CheckBox.new()
	lunga.text = "Partita lunga (18 turni)"
	lunga.add_theme_font_override("font", F_TESTO)
	lunga.add_theme_font_size_override("font_size", 18)
	lunga.button_pressed = scelta_lunga
	lunga.toggled.connect(func(x): scelta_lunga = x)
	riga.add_child(lunga)
	var facile := CheckBox.new()
	facile.text = "Modalità clemente (eventi e Cosa: 1 Successo in meno)"
	facile.add_theme_font_override("font", F_TESTO)
	facile.add_theme_font_size_override("font_size", 18)
	facile.button_pressed = scelta_facile
	facile.toggled.connect(func(x): scelta_facile = x)
	v.add_child(facile)
	var riga2 := HBoxContainer.new()
	riga2.add_theme_constant_override("separation", 10)
	v.add_child(riga2)
	riga2.add_child(bottone("INDIETRO", mostra_menu, Color(0.15, 0.15, 0.18)))
	var vai := bottone("ENTRA NELL'AVAMPOSTO", _avvia_locale, Color(0.5, 0.12, 0.1), 22)
	vai.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	riga2.add_child(vai)

func _sfondo_scuro() -> void:
	var sfondo := ColorRect.new()
	sfondo.color = Color(0.02, 0.03, 0.05)
	sfondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	schermo.add_child(sfondo)
	var cop := immagine("res://assets/ui/copertina.webp", 10, 10)
	cop.set_anchors_preset(Control.PRESET_FULL_RECT)
	cop.modulate = Color(0.25, 0.3, 0.38)
	schermo.add_child(cop)
	schermo.add_child(_neve_2d())

func _scegli_pg(mio: String, n: int, seed: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var altri: Array = Dati.ORDINE_PG.duplicate()
	altri.erase(mio)
	for k in range(altri.size() - 1, 0, -1):
		var j := r.randi_range(0, k)
		var t = altri[k]
		altri[k] = altri[j]
		altri[j] = t
	var out := [mio]
	out.append_array(altri.slice(0, n - 1))
	return out

func _avvia_locale() -> void:
	var seed := int(Time.get_unix_time_from_system()) % 1000000 + randi() % 1000
	var pgs := _scegli_pg(scelta_pg, scelta_n, seed)
	var seats := [0]
	for k in range(1, pgs.size()):
		seats.append(-1)
	online = false
	mio_posto = 0
	m = Motore.new()
	m.nuova({"pg": pgs, "seat": seats, "seed": seed, "lunga": scelta_lunga, "facile": scelta_facile})
	ia = IA.new(m)
	_apri_partita()

func _menu_continua() -> void:
	var stato := {}
	if FileAccess.file_exists(SALVA_LOCALE):
		var f := FileAccess.open(SALVA_LOCALE, FileAccess.READ)
		var x = JSON.parse_string(f.get_as_text())
		if x is Dictionary:
			stato = x
	_avviso("Cerco il salvataggio su Firebase...")
	var remoto: Dictionary = await net.carica_partita()
	if not remoto.is_empty() and (stato.is_empty() or int(remoto.get("passo", 0)) >= int(stato.get("passo", 0))):
		stato = remoto
	if stato.is_empty() or stato.get("stadio", "") == "fine":
		_avviso("Non c'è una partita salvata da continuare.")
		return
	online = false
	mio_posto = 0
	m = Motore.new()
	m.carica(stato)
	ia = IA.new(m)
	_apri_partita()

func _avviso(t: String) -> void:
	var p := pannello(Color(0.05, 0.08, 0.12, 0.97), C_GELO)
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.position = Vector2(-260, -90)
	p.custom_minimum_size = Vector2(520, 0)
	var l := etichetta(t, F_TESTO, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	schermo.add_child(p)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)

func _menu_regole() -> void:
	pulisci()
	_sfondo_scuro()
	var box := pannello()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 120
	box.offset_right = -120
	box.offset_top = 40
	box.offset_bottom = -40
	schermo.add_child(box)
	var v := VBoxContainer.new()
	box.add_child(v)
	v.add_child(etichetta("REGOLE IN BREVE", F_TITOLO, 40, C_GHIACCIO))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(980, 0)
	rt.add_theme_font_override("normal_font", F_TESTO)
	rt.add_theme_font_override("bold_font", F_GRASSETTO)
	rt.add_theme_font_size_override("normal_font_size", 19)
	rt.add_theme_font_size_override("bold_font_size", 19)
	rt.text = REGOLE
	sc.add_child(rt)
	v.add_child(bottone("INDIETRO", mostra_menu, Color(0.15, 0.15, 0.18)))

const REGOLE := """[b]Lo scopo.[/b] Siete una squadra di ricerca in Antartide: una forma di vita aliena, la Cosa, è libera nel campo e assume le sembianze umane. Dovete sopravvivere fino al [b]turno dell'elicottero[/b] e salire a bordo con abbastanza [b]Bonus elicottero[/b]. Servono 6 punti per ogni umano della squadra (anche morto); ogni infetto che sale a bordo aggiunge i suoi punti alla soglia. Chi viene contagiato gioca per la Cosa: vince se riesce a salire sull'elicottero e gli umani non raggiungono la soglia.

[b]Il turno.[/b] La partita dura 15 turni (18 nella partita lunga) divisi in 3 Fasi. All'inizio di ogni turno: Pasto o Sonno (alla fine di ogni Fase), calo di temperatura per chi è fuori, si recuperano le Azioni, si scopre un evento del campo. Poi ognuno gioca il suo turno con 5 Azioni (6 con Agilità).

[b]Le azioni.[/b] Spostarsi (1), cercare nel mazzo dello spazio in cui sei (2), costruire una tessera oggetto (1, dentro), ricevere carte da un altro giocatore nello stesso luogo (1), riscaldarsi alla caldaia (1, tira un dado: Successo = +1 Stamina), esplorare fuori (1, tira un dado: Successo = +1 XP), riparare Caldaia (dentro) o Porta (fuori): 2 Azioni sicure o 1 Azione e un dado. Giocare carte non costa Azioni. Si cambia luogo (dentro/fuori) una sola volta per turno.

[b]Gli eventi del campo.[/b] Ogni giocatore deve affrontare l'evento nel suo turno: Attacchi (rossi) e Ostacoli (blu) richiedono tanti Successi quanto la Fase (1, 2, 3). Tiri i dadi naturali (1 dado con 1-3 di Stamina, 2 dadi con 4 o più) più quelli delle tessere oggetto del colore giusto. Puoi aiutarti con carte e oggetti anche dopo aver tirato. Gli eventi col lucchetto bloccano il campo: riguardano solo chi è dentro e nessuno può cambiare luogo.

[b]Fuori.[/b] Cercare nei mazzi Fase dà 2 XP, Bonus elicottero, oggetti e cassette, ma anche Danni alla Porta e attacchi della Cosa (Fallimento: 1 Ferita e una carta Vulnerabile). A ogni turno chi è fuori perde Stamina (1, 2 o 3 a seconda della Fase); senza Stamina si congela e si riceve una Ferita.

[b]Caldaia e Porta.[/b] Con 3 Danni la Caldaia esplode (1 Ferita a chi è dentro, niente più riscaldamento) e la Porta si rompe (tutti dentro pescano una Vulnerabile e anche dentro si soffre il freddo).

[b]Ferite.[/b] Con 3 Ferite si muore. Le Ferite critiche vanno curate entro la fine del turno successivo, altrimenti diventano un'altra Ferita a ogni turno.

[b]Vulnerabili e contagio.[/b] Chi resta senza Scatoletta nel Pasto, dorme da solo nel Sonno, fallisce contro la Cosa o certi eventi, pesca una carta Vulnerabile: una sola è contaminata, e chi la pesca diventa l'[b]Ospite[/b]. Chi ha carte Vulnerabili deve mostrare il suo segnalatore quando dà una carta o quando dorme con qualcuno: un umano mostra sempre PULITO, un infetto può mostrare INFETTO e contagiare. Chi riceve una carta da un giocatore Vulnerabile può spendere Azioni e tirare un dado per evitare di guardare il segnalatore. L'Ospite può tentare l'Attacco d'infezione (5 Azioni) rivelandosi.

[b]Smascherare la Cosa.[/b] L'Esame del sangue del Dr. Copper e il Test dell'Ospite di Blair mostrano lo stato in segreto: poi chi l'ha fatto dichiara agli altri quello che ha visto (dicendo la verità... o no). Con 5 Azioni si può assaltare un giocatore nello stesso luogo.

[b]XP e sblocchi.[/b] Gli XP comprano: abilità unica del personaggio (3), Cardio (+1 Stamina massima, 2), Agilità (+1 Azione, 6), Combinazione dell'armadietto (un dado con bonus ogni turno, 6), 3 spazi oggetti in più (4) e, per ultimo, la Scorta XP (8): ogni 5 XP conservati vale un Bonus elicottero.

[b]L'elicottero.[/b] Il capo (il grado più alto) sale per primo e decide chi lasciare a terra; chi è a bordo può scendere. Poi tutti rivelano il segnalatore e ognuno a bordo tira il dado dell'elicottero, che si somma ai suoi Bonus."""

# ============================================================ online

var on_nome: LineEdit
var on_codice: LineEdit
var on_stato: Label
var lobby_box: VBoxContainer

func _menu_online() -> void:
	pulisci()
	_sfondo_scuro()
	var box := pannello()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(620, 520)
	box.position = Vector2(-310, -260)
	schermo.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)
	v.add_child(etichetta("ONLINE", F_TITOLO, 40, C_GHIACCIO))
	v.add_child(etichetta("Chi crea la stanza sceglie personaggio e numero di sopravvissuti; gli amici entrano col codice. I posti vuoti li guida l'IA.", F_TESTO, 16, C_SPENTO))
	var r1 := HBoxContainer.new()
	v.add_child(r1)
	r1.add_child(etichetta("Il tuo nome:", F_GRASSETTO, 18))
	on_nome = LineEdit.new()
	on_nome.custom_minimum_size = Vector2(260, 0)
	on_nome.text = str(net.load_session().get("name", "Sopravvissuto"))
	on_nome.max_length = 20
	r1.add_child(on_nome)
	v.add_child(etichetta("Crei la stanza con: %s, %d sopravvissuti%s%s (cambiali in Nuova partita)" % [Dati.PG[scelta_pg]["nome"], scelta_n, ", partita lunga" if scelta_lunga else "", ", clemente" if scelta_facile else ""], F_TESTO, 16))
	v.add_child(bottone("CREA UNA STANZA", _online_crea, Color(0.3, 0.14, 0.14), 20))
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	on_codice = LineEdit.new()
	on_codice.placeholder_text = "CODICE"
	on_codice.max_length = 4
	on_codice.custom_minimum_size = Vector2(120, 0)
	r2.add_child(on_codice)
	r2.add_child(bottone("ENTRA", _online_entra, Color(0.14, 0.28, 0.42), 20))
	var sess := net.load_session()
	if str(sess.get("room", "")) != "":
		r2.add_child(bottone("RIENTRA IN %s" % sess["room"], func():
			on_codice.text = str(sess["room"])
			_online_entra(), Color(0.14, 0.2, 0.3), 16))
	on_stato = etichetta("", F_TESTO, 17, C_FUOCO)
	on_stato.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(on_stato)
	lobby_box = VBoxContainer.new()
	v.add_child(lobby_box)
	v.add_child(bottone("INDIETRO", mostra_menu, Color(0.15, 0.15, 0.18)))

func _online_crea() -> void:
	on_stato.text = "Creo la stanza..."
	net._save({"name": on_nome.text})
	var cfg := {"pg": scelta_pg, "n": scelta_n, "lunga": scelta_lunga, "facile": scelta_facile}
	var c := await net.create_room(on_nome.text, cfg)
	if c == "":
		on_stato.text = "Non riesco a creare la stanza: " + net.last_error
		return
	codice = c
	mio_posto = 0
	net.remember_room(c, 0)
	on_stato.text = "Stanza %s creata. Dai il codice agli amici, poi premi INIZIA." % c
	_lobby(true)

func _online_entra() -> void:
	var c := on_codice.text.strip_edges().to_upper()
	if c.length() != 4:
		on_stato.text = "Il codice ha 4 lettere."
		return
	on_stato.text = "Entro nella stanza %s..." % c
	net._save({"name": on_nome.text})
	var p := await net.join_room(c, on_nome.text)
	if p < 0:
		on_stato.text = "Non riesco a entrare (stanza piena, inesistente o già iniziata). " + net.last_error
		return
	codice = c
	mio_posto = p
	net.remember_room(c, p)
	var room := await net.room(c)
	if room.get("status", "") == "playing":
		_avvia_da_stanza(room)
		return
	on_stato.text = "Sei nella stanza %s, posto %d. Aspetta che l'host inizi." % [c, p + 1]
	_lobby(false)

func _lobby(host: bool) -> void:
	for ch in lobby_box.get_children():
		ch.queue_free()
	var lista := etichetta("", F_TESTO, 17)
	lobby_box.add_child(lista)
	if host:
		lobby_box.add_child(bottone("INIZIA LA PARTITA", _online_inizia, Color(0.5, 0.12, 0.1), 20))
	while is_instance_valid(lista) and not in_partita:
		var room := await net.room(codice)
		if not is_instance_valid(lista):
			return
		var seats := Rete._as_dict(room.get("seats", {}))
		var t := "Giocatori nella stanza:\n"
		for k in seats:
			t += "  %d. %s\n" % [int(k) + 1, seats[k].get("name", "?")]
		lista.text = t
		if not host and room.get("status", "") == "playing":
			_avvia_da_stanza(room)
			return
		await get_tree().create_timer(1.5).timeout

func _online_inizia() -> void:
	var room := await net.room(codice)
	var seats := Rete._as_dict(room.get("seats", {}))
	var cfg = JSON.parse_string(str(room.get("cfg", "{}")))
	var n: int = max(int(cfg.get("n", 5)), seats.size())
	n = min(n, 8)
	var seed := int(Time.get_unix_time_from_system()) % 1000000
	var pgs := _scegli_pg(str(cfg.get("pg", "garry")), n, seed)
	# i posti online (in ordine) prendono i primi personaggi, gli altri sono dell'IA
	var posti := seats.keys()
	posti.sort_custom(func(a, b): return int(a) < int(b))
	var seat_arr := []
	var nomi := {}
	for k in n:
		if k < posti.size():
			seat_arr.append(int(posti[k]))
			nomi[str(posti[k])] = seats[posti[k]].get("name", "?")
		else:
			seat_arr.append(-1)
	var game := {"pg": pgs, "seat": seat_arr, "seed": seed, "lunga": bool(cfg.get("lunga", false)), "facile": bool(cfg.get("facile", false)), "nomi": nomi}
	if not await net.start_room(codice, game):
		on_stato.text = "Non riesco a iniziare: " + net.last_error
		return
	room["game"] = JSON.stringify(game)
	_avvia_da_stanza(room)

func _avvia_da_stanza(room: Dictionary) -> void:
	var game = JSON.parse_string(str(room.get("game", "{}")))
	if not (game is Dictionary):
		on_stato.text = "Dati della partita illeggibili."
		return
	online = true
	nomi_posti = game.get("nomi", {})
	m = Motore.new()
	m.nuova(game)
	ia = IA.new(m)
	# si rigiocano le decisioni già prese (chi rientra ritrova la partita al punto giusto)
	var log := await net.get_decisions(codice, 0)
	var guard := 0
	while not m.finita() and guard < 20000:
		guard += 1
		var r := m.richiesta()
		if r.is_empty():
			break
		var seat: int = m.g(r["g"])["seat"]
		var id := ""
		if seat < 0:
			id = ia.decidi(r)
		elif log.has(int(m.s["passo"])):
			id = str(log[int(m.s["passo"])].get("id", ""))
		else:
			break
		m.applica({"id": id})
	_apri_partita()

# ============================================================ la partita

func io(i: int) -> bool:
	return m.g(i)["seat"] == mio_posto

func mio_pg() -> int:
	for i in m.s["ordine"]:
		if io(i):
			return i
	return -1

func _apri_partita() -> void:
	pulisci()
	in_partita = true
	richiesta_mostrata = -1
	ultimo_log = 0
	conoscenze_viste = {}
	# il tavolo 3D occupa tutto lo schermo
	var sfondo := ColorRect.new()
	sfondo.color = Color(0.03, 0.05, 0.09)
	sfondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	schermo.add_child(sfondo)
	var cont := SubViewportContainer.new()
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.offset_left = 262
	cont.offset_right = -352
	cont.offset_top = 46
	cont.offset_bottom = -206
	cont.stretch = true
	schermo.add_child(cont)
	vista = SubViewport.new()
	vista.msaa_3d = Viewport.MSAA_2X
	vista.handle_input_locally = true
	cont.add_child(vista)
	plancia = Plancia3D.new()
	vista.add_child(plancia)
	plancia.spazio_cliccato.connect(_spazio_cliccato)
	_costruisci_hud()
	# cronaca: l'ultima cosa successa, in grande sopra il tavolo
	cronaca = etichetta("", F_TITOLO, 26, C_GHIACCIO)
	cronaca.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cronaca.offset_left = 270
	cronaca.offset_right = -360
	cronaca.offset_top = 54
	cronaca.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cronaca.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cronaca.add_theme_constant_override("outline_size", 8)
	cronaca.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.05))
	cronaca.mouse_filter = Control.MOUSE_FILTER_IGNORE
	schermo.add_child(cronaca)
	_aggiorna_tutto()

func _costruisci_hud() -> void:
	# barra in alto
	var top := pannello(Color(0.02, 0.04, 0.07, 0.88))
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 46
	schermo.add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 18)
	top.add_child(th)
	var logo := etichetta("WHO GOES THERE?", F_TITOLO, 26, C_GHIACCIO)
	th.add_child(logo)
	top_info = etichetta("", F_GRASSETTO, 19)
	th.add_child(top_info)
	top_evento = etichetta("", F_GRASSETTO, 19, C_FUOCO)
	th.add_child(top_evento)
	top_stato = HBoxContainer.new()
	top_stato.add_theme_constant_override("separation", 14)
	top_stato.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_stato.alignment = BoxContainer.ALIGNMENT_END
	th.add_child(top_stato)
	var menu_b := bottone("MENU", _menu_partita, Color(0.12, 0.14, 0.18), 16)
	th.add_child(menu_b)
	# giocatori a sinistra
	var sx := ScrollContainer.new()
	sx.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	sx.offset_top = 52
	sx.offset_bottom = -212
	sx.offset_right = 262
	sx.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	schermo.add_child(sx)
	var colsx := VBoxContainer.new()
	colsx.add_theme_constant_override("separation", 6)
	sx.add_child(colsx)
	colonna_giocatori = VBoxContainer.new()
	colonna_giocatori.add_theme_constant_override("separation", 5)
	colonna_giocatori.custom_minimum_size = Vector2(255, 0)
	colsx.add_child(colonna_giocatori)
	evento_box = CenterContainer.new()
	colsx.add_child(evento_box)
	# a destra: diario e azioni
	var dx := VBoxContainer.new()
	dx.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	dx.offset_left = -350
	dx.offset_top = 52
	dx.offset_bottom = -6
	dx.offset_right = -6
	dx.add_theme_constant_override("separation", 6)
	schermo.add_child(dx)
	var pd := pannello(Color(0.86, 0.84, 0.76, 0.93), Color(0.4, 0.35, 0.25))
	pd.custom_minimum_size = Vector2(0, 230)
	dx.add_child(pd)
	var vd := VBoxContainer.new()
	pd.add_child(vd)
	vd.add_child(etichetta("DIARIO DELL'AVAMPOSTO 31", F_DIARIO, 15, Color(0.35, 0.08, 0.05)))
	diario = RichTextLabel.new()
	diario.scroll_following = true
	diario.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diario.add_theme_font_override("normal_font", F_DIARIO)
	diario.add_theme_font_size_override("normal_font_size", 13)
	diario.add_theme_color_override("default_color", Color(0.12, 0.1, 0.08))
	vd.add_child(diario)
	var pa := pannello()
	pa.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dx.add_child(pa)
	var va := VBoxContainer.new()
	pa.add_child(va)
	titolo_azioni = etichetta("", F_TITOLO, 22, C_GHIACCIO)
	titolo_azioni.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	va.add_child(titolo_azioni)
	var sa := ScrollContainer.new()
	sa.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sa.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	va.add_child(sa)
	pannello_azioni = VBoxContainer.new()
	pannello_azioni.add_theme_constant_override("separation", 3)
	pannello_azioni.custom_minimum_size = Vector2(318, 0)
	sa.add_child(pannello_azioni)
	# in basso: la tua mano e il tuo stato
	var basso := pannello(Color(0.02, 0.04, 0.07, 0.9))
	basso.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	basso.offset_top = -206
	basso.offset_right = -356
	schermo.add_child(basso)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	basso.add_child(hb)
	var vs := VBoxContainer.new()
	vs.custom_minimum_size = Vector2(210, 0)
	hb.add_child(vs)
	stato_mio = etichetta("", F_GRASSETTO, 17)
	stato_mio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vs.add_child(stato_mio)
	tessere_mie = HBoxContainer.new()
	tessere_mie.add_theme_constant_override("separation", 3)
	vs.add_child(tessere_mie)
	segreto_btn = bottone("GUARDA IL TUO SEGNALATORE", _mostra_segreto, Color(0.25, 0.08, 0.08), 15)
	vs.add_child(segreto_btn)
	segreto_lbl = etichetta("", F_TITOLO, 22, C_SANGUE)
	vs.add_child(segreto_lbl)
	var sm := ScrollContainer.new()
	sm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sm.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hb.add_child(sm)
	mano_box = HBoxContainer.new()
	mano_box.add_theme_constant_override("separation", 6)
	sm.add_child(mano_box)
	# comandi della telecamera (per il tocco)
	var cam := HBoxContainer.new()
	cam.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cam.position = Vector2(-356 - 290, -244)
	schermo.add_child(cam)
	for x in [["RUOTA SX", Vector2(-20, 0)], ["RUOTA DX", Vector2(20, 0)], ["SU", Vector2(0, -8)], ["GIÙ", Vector2(0, 8)]]:
		var d: Vector2 = x[1]
		cam.add_child(bottone(x[0], func(): plancia.ruota(d.x, d.y), Color(0.08, 0.1, 0.14, 0.8), 13))
	cam.add_child(bottone("+", func(): plancia.zoom(-0.5), Color(0.08, 0.1, 0.14, 0.8), 14))
	cam.add_child(bottone("-", func(): plancia.zoom(0.5), Color(0.08, 0.1, 0.14, 0.8), 14))

func _mostra_segreto() -> void:
	var i := mio_pg()
	if i < 0:
		return
	if segreto_lbl.text != "":
		segreto_lbl.text = ""
		segreto_btn.text = "GUARDA IL TUO SEGNALATORE"
		return
	var g: Dictionary = m.g(i)
	var t := "SEI UMANO"
	if g["infetto"]:
		t = "SEI LA COSA" + (" (OSPITE)" if g["ospite"] else "")
	segreto_lbl.text = t
	segreto_lbl.add_theme_color_override("font_color", C_SANGUE if g["infetto"] else C_GHIACCIO)
	segreto_btn.text = "NASCONDI"

func _menu_partita() -> void:
	_chiudi_dialogo()
	var opz := [
		{"t": "Riprendi", "f": _chiudi_dialogo},
		{"t": "Velocità dell'IA: %s" % {0.5: "lenta", 1.0: "normale", 2.5: "veloce"}.get(velocita, "normale"), "f": func():
			velocita = {0.5: 1.0, 1.0: 2.5, 2.5: 0.5}.get(velocita, 1.0)
			_menu_partita()},
		{"t": "Salva ed esci al menu", "f": func():
			_salva(true)
			mostra_menu()},
	]
	_dialogo("MENU", "", opz.map(func(x): return {"testo": x["t"], "cb": x["f"]}))

# ---------- dialoghi

func _chiudi_dialogo() -> void:
	if dialogo and is_instance_valid(dialogo):
		dialogo.queue_free()
	dialogo = null

func _dialogo(titolo: String, testo: String, opz: Array, extra: Control = null) -> void:
	_chiudi_dialogo()
	dialogo = pannello(Color(0.04, 0.06, 0.1, 0.97), C_GHIACCIO)
	dialogo.set_anchors_preset(Control.PRESET_CENTER)
	dialogo.custom_minimum_size = Vector2(520, 0)
	dialogo.position = Vector2(-260 - 50, -200)
	schermo.add_child(dialogo)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	dialogo.add_child(v)
	var t := etichetta(titolo, F_TITOLO, 28, C_GHIACCIO)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	if testo != "":
		var l := etichetta(testo, F_TESTO, 18)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(500, 0)
		v.add_child(l)
	if extra:
		v.add_child(extra)
	for o in opz:
		var b := bottone(o["testo"], o["cb"], o.get("col", Color(0.14, 0.24, 0.34)), 18)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(b)
	await get_tree().process_frame
	if is_instance_valid(dialogo):
		dialogo.position = (schermo.size - dialogo.size) / 2.0 - Vector2(60, 20)

# ---------- ciclo

func _process(delta: float) -> void:
	if not in_partita or m == null:
		return
	if m.finita():
		if richiesta_mostrata != -2:
			richiesta_mostrata = -2
			_aggiorna_tutto()
			_mostra_fine()
		return
	var r := m.richiesta()
	if r.is_empty():
		return
	var seat: int = m.g(r["g"])["seat"]
	if seat < 0:
		attesa += delta * velocita
		var pausa := 0.8 if r["k"] == "turno" else 0.4
		if attesa >= pausa:
			attesa = 0.0
			var id := ia.decidi(r)
			m.applica({"id": id})
			_aggiorna_tutto()
	elif seat == mio_posto:
		if richiesta_mostrata != int(m.s["passo"]):
			richiesta_mostrata = int(m.s["passo"])
			_mostra_richiesta(r)
	elif online and not aspetto_rete:
		_aspetta_remoto()

func _aspetta_remoto() -> void:
	aspetto_rete = true
	var n: int = m.s["passo"]
	var d = await net.get_decision(codice, n)
	if d is Dictionary and d.has("id") and int(m.s["passo"]) == n:
		m.applica({"id": str(d["id"])})
		_aggiorna_tutto()
	else:
		await get_tree().create_timer(1.0).timeout
	aspetto_rete = false

func _decidi(id: String) -> void:
	_chiudi_dialogo()
	if online:
		var n: int = m.s["passo"]
		var ok := await net.post_decision(codice, n, {"id": id})
		if not ok:
			_avviso("Rete: non riesco a inviare la mossa (" + net.last_error + "). Riprovo...")
			richiesta_mostrata = -1
			return
	m.applica({"id": id})
	_aggiorna_tutto()
	if not online:
		_salva(false)

func _salva(subito: bool) -> void:
	if online or m == null:
		return
	var testo := JSON.stringify(m.s)
	var f := FileAccess.open(SALVA_LOCALE, FileAccess.WRITE)
	if f:
		f.store_string(testo)
		f.close()
	var ora := Time.get_unix_time_from_system()
	if (subito or ora - ultimo_salvataggio > 20.0) and not salvataggio_in_corso:
		ultimo_salvataggio = ora
		salvataggio_in_corso = true
		await net.salva_partita(m.s)
		salvataggio_in_corso = false

func _spazio_cliccato(sp: String) -> void:
	var r := m.richiesta()
	if r.is_empty() or r["k"] != "turno" or not io(r["g"]):
		return
	for o in r["opz"]:
		if str(o["id"]) == "muovi:" + sp:
			_decidi(o["id"])
			return

# ---------- richieste del giocatore

const GRUPPI := [["evento", "Evento del campo"], ["costruisci", "Costruire"], ["muovi", "Spostarti"], ["cerca", "Cercare"],
	["azioni", "Altre azioni"], ["carte", "Giocare carte"], ["armadietto", "Dado armadietto"], ["sblocca", "Sbloccare (XP)"],
	["falo", "Falò"], ["scambi", "Dare carte"], ["chiedi", "Chiedere carte"], ["assalto", "Violenza"],
	["tessere", "Tessere oggetto"], ["scarta", "Scartare carte"], ["bisogni", "Dire cosa ti serve"], ["fine", "Fine"]]
const GRUPPI_CHIUSI := ["chiedi", "scambi", "tessere", "scarta", "falo", "assalto", "bisogni"]

func _mostra_richiesta(r: Dictionary) -> void:
	_pulisci_azioni()
	if r["k"] == "turno":
		_chiudi_dialogo()
		var i: int = r["g"]
		titolo_azioni.text = "TOCCA A TE, %s - %d Azioni" % [m.nome(i).to_upper(), m.g(i)["azioni"]]
		var per_gruppo := {}
		for o in r["opz"]:
			var gr: String = o.get("gr", "azioni")
			if not per_gruppo.has(gr):
				per_gruppo[gr] = []
			per_gruppo[gr].append(o)
		for gk in GRUPPI:
			var gr2: String = gk[0]
			if not per_gruppo.has(gr2):
				continue
			var aperto: bool = gruppi_aperti.get(gr2, not (gr2 in GRUPPI_CHIUSI))
			var testa := bottone(("[-] " if aperto else "[+] ") + gk[1] + " (%d)" % per_gruppo[gr2].size(), func():
				gruppi_aperti[gr2] = not aperto
				_mostra_richiesta(m.richiesta()), Color(0.06, 0.09, 0.13), 15)
			testa.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if gr2 == "fine" or gr2 == "evento":
				pass
			else:
				pannello_azioni.add_child(testa)
			if not aperto and gr2 != "fine" and gr2 != "evento":
				continue
			for o in per_gruppo[gr2]:
				var col := Color(0.12, 0.2, 0.3)
				if gr2 == "evento":
					col = Color(0.55, 0.14, 0.08)
				elif gr2 == "fine":
					col = Color(0.18, 0.18, 0.22)
				elif gr2 == "assalto":
					col = Color(0.4, 0.06, 0.06)
				var id: String = o["id"]
				var b := bottone(o["testo"], func(): _decidi(id), col, 15)
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				pannello_azioni.add_child(b)
		return
	# le altre richieste sono finestre al centro
	titolo_azioni.text = "Scegli..."
	var extra: Control = null
	if r["k"] == "potenzia" and m.s["ctx"].has("prova"):
		extra = _vista_dadi(m.s["ctx"]["prova"])
	var opz := []
	for o in r["opz"]:
		var id2: String = o["id"]
		var col2 := Color(0.14, 0.24, 0.34)
		if id2 in ["infetto"]:
			col2 = Color(0.5, 0.08, 0.08)
		opz.append({"testo": o["testo"], "cb": func(): _decidi(id2), "col": col2})
	var tit: String = {"letto": "TURNO DEL SONNO", "accetta_letto": "TURNO DEL SONNO", "segnalatore": "IL TUO SEGNALATORE",
		"segnalatore_scambio": "IL TUO SEGNALATORE", "evita": "SEGNALATORE DI INFEZIONE", "potenzia": "IL TIRO", "partenza": "INIZIO",
		"imbarco": "L'ELICOTTERO", "scendi": "L'ELICOTTERO", "chiesta": "UNA RICHIESTA", "dichiara": "COSA DICI?", "test": "IL TEST",
		"forziere": "UNA CASSETTA", "troppe": "TROPPE CARTE"}.get(r["k"], "SCEGLI")
	_dialogo(tit, r.get("testo", ""), opz, extra)

func _vista_dadi(p: Dictionary) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	for e in p["esiti"]:
		var d := PanelContainer.new()
		d.add_theme_stylebox_override("panel", stile(Color(0.13, 0.42, 0.78) if e else Color(0.2, 0.24, 0.3), Color.WHITE, 2, 6))
		d.custom_minimum_size = Vector2(44, 44)
		var l := etichetta("S" if e else "-", F_TITOLO, 24)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.add_child(l)
		hb.add_child(d)
	if p["extra"] > 0:
		hb.add_child(etichetta("+%d" % p["extra"], F_TITOLO, 24, C_FUOCO))
	return hb

func _pulisci_azioni() -> void:
	for c in pannello_azioni.get_children():
		c.queue_free()

# ---------- aggiornamento della schermata

func _aggiorna_tutto() -> void:
	if not in_partita or m == null:
		return
	plancia.aggiorna(m)
	var s := m.s
	var ti := m.turno_info()
	var tot: int = s["turni"].size()
	if s["turno"] >= tot:
		top_info.text = "TURNO DELL'ELICOTTERO"
	else:
		var tipo: String = {"pasto": " - PASTO", "sonno": " - SONNO"}.get(ti.get("tipo", ""), "")
		top_info.text = "Turno %d/%d  Fase %d%s  (servono %d Successi)" % [max(1, s["turno"] + 1), tot, m.fase(), tipo, m.successi_richiesti()]
	if not s["evento"].is_empty():
		var et: String = s["evento"]["t"]
		top_evento.text = "Evento: %s%s" % [Dati.nome_carta(et), " (BLOCCO)" if s["blocco"] else ""]
		top_evento.tooltip_text = Dati.testo_carta(et)
		top_evento.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		top_evento.text = ""
	var chiave_ev: String = s["evento"].get("img", "") + str(s["turno"])
	if chiave_ev != evento_mostrato:
		evento_mostrato = chiave_ev
		for c in evento_box.get_children():
			c.queue_free()
		if not s["evento"].is_empty():
			var vv := VBoxContainer.new()
			vv.add_child(etichetta("EVENTO DEL CAMPO", F_TITOLO, 18, C_FUOCO))
			var ca := carta(s["evento"], 160.0)
			vv.add_child(ca)
			if s["blocco"]:
				vv.add_child(etichetta("BLOCCO: riguarda solo chi è dentro,
nessuno cambia luogo.", F_GRASSETTO, 14, C_SANGUE))
			evento_box.add_child(vv)
	for c in top_stato.get_children():
		c.queue_free()
	top_stato.add_child(etichetta("Caldaia", F_TESTO, 16, C_SPENTO))
	top_stato.add_child(barra(s["caldaia"], 3, C_SANGUE, 12, 14))
	top_stato.add_child(etichetta("Porta", F_TESTO, 16, C_SPENTO))
	top_stato.add_child(barra(s["porta"], 3, C_SANGUE, 12, 14))
	top_stato.add_child(etichetta("Falò %d/5" % s["falo"].size(), F_TESTO, 16, C_FUOCO if s["falo"].size() >= 5 else C_SPENTO))
	top_stato.add_child(etichetta("Vulnerabili %d" % s["mazzi"]["vulnerabili"].size(), F_TESTO, 16, C_SPENTO))
	_aggiorna_giocatori()
	_aggiorna_mano()
	_aggiorna_diario()
	_controlla_conoscenze()
	var r := m.richiesta()
	if r.is_empty() or not io(r["g"]):
		_pulisci_azioni()
		if not r.is_empty():
			titolo_azioni.text = "Tocca a %s..." % m.nome(r["g"])
			if m.g(r["g"])["seat"] >= 0 and online:
				titolo_azioni.text += " (%s)" % nomi_posti.get(str(m.g(r["g"])["seat"]), "online")

func _aggiorna_giocatori() -> void:
	for c in colonna_giocatori.get_children():
		c.queue_free()
	var cor := m.corrente()
	for i in m.s["ordine"]:
		var g: Dictionary = m.g(i)
		var info: Dictionary = Dati.PG[g["pg"]]
		var bordo: Color = info["colore"] if i == cor else Color(0.25, 0.32, 0.4, 0.6)
		var p := pannello(Color(0.03, 0.05, 0.08, 0.9) if not g["morto"] else Color(0.1, 0.03, 0.03, 0.9), bordo)
		colonna_giocatori.add_child(p)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		p.add_child(hb)
		var img := immagine("res://assets/pg/%s.webp" % g["pg"], 54, 54)
		if g["morto"]:
			img.modulate = Color(0.4, 0.3, 0.3)
		hb.add_child(img)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 1)
		hb.add_child(v)
		var chi := "IA"
		if g["seat"] == mio_posto:
			chi = "TU"
		elif g["seat"] >= 0:
			chi = str(nomi_posti.get(str(g["seat"]), "online"))
		var capo := " - CAPO" if m.s["capo"] == i else ""
		v.add_child(etichetta("%s  [%s]%s" % [info["nome"], chi, capo], F_GRASSETTO, 16, info["colore"].lightened(0.35)))
		if g["morto"]:
			v.add_child(etichetta("MORTO", F_TITOLO, 18, C_SANGUE))
			continue
		var pos: String = Dati.NOMI_SPAZI.get(g["pos"], "-")
		v.add_child(etichetta("%s  XP %d  Carte %d  Vuln. %d" % [pos, g["xp"], g["mano"].size(), m.s["n_vuln_pubbliche"].get(str(i), 0)], F_TESTO, 14, C_TESTO))
		var r2 := HBoxContainer.new()
		r2.add_theme_constant_override("separation", 6)
		v.add_child(r2)
		r2.add_child(barra(g["stamina"], g["stamina_max"], Color(0.3, 0.8, 0.35), 8, 8))
		r2.add_child(barra(g["ferite"] + g["critiche"], 3, C_SANGUE, 8, 8))
		var tb := HBoxContainer.new()
		tb.add_theme_constant_override("separation", 2)
		v.add_child(tb)
		for t in g["tessere"]:
			var ti2 := immagine("res://assets/tessere/%s.webp" % t, 22, 22)
			ti2.tooltip_text = Dati.TESSERE[t]["nome"] + ": " + Dati.TESSERE[t]["testo"]
			ti2.mouse_filter = Control.MOUSE_FILTER_STOP
			tb.add_child(ti2)
		var bis: Array = m.s.get("bisogni", {}).get(str(i), [])
		if not bis.is_empty():
			var lb := etichetta("Cerca: " + ", ".join(bis.map(func(x): return Dati.nome_carta(x).to_lower())), F_TESTO, 13, C_FUOCO)
			lb.custom_minimum_size = Vector2(180, 0)
			lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(lb)
		var bonus := m.bonus_giocatore(i)
		if bonus > 0:
			tb.add_child(etichetta(" Bonus %d" % bonus, F_GRASSETTO, 14, C_FUOCO))
		var sa = m.g(mio_pg())["sa"].get(str(i), null) if mio_pg() >= 0 else null
		if sa is Dictionary:
			tb.add_child(etichetta(" visto: %s" % ("INFETTO" if sa["v"] == "infetto" else "pulito"), F_GRASSETTO, 13, C_SANGUE if sa["v"] == "infetto" else C_GHIACCIO))

func _aggiorna_mano() -> void:
	for c in mano_box.get_children():
		c.queue_free()
	for c in tessere_mie.get_children():
		c.queue_free()
	var i := mio_pg()
	if i < 0:
		return
	var g: Dictionary = m.g(i)
	var arm := ""
	if m.ha_sblocco(i, "armadietto") and g["armadietto"] != "":
		var f: String = g["armadietto"]
		if f == "unico":
			f = Dati.PG[g["pg"]]["armadietto"]
		arm = "\nArmadietto: %s%s" % [Dati.NOMI_ARMADIETTO.get(f, f).split(" (")[0], " (usato)" if g["arm_usato"] else ""]
	stato_mio.text = "%s - %s\nAzioni %d/%d  Stamina %d/%d\nFerite %d%s  XP %d%s" % [Dati.PG[g["pg"]]["nome"], Dati.NOMI_SPAZI.get(g["pos"], "-"),
		g["azioni"], g["azioni_max"], g["stamina"], g["stamina_max"], g["ferite"] + g["critiche"], " (critica!)" if g["critiche"] > 0 else "", g["xp"], arm]
	for t in g["tessere"]:
		var ti := immagine("res://assets/tessere/%s.webp" % t, 40, 40)
		ti.tooltip_text = Dati.TESSERE[t]["nome"] + ": " + Dati.TESSERE[t]["testo"]
		ti.mouse_filter = Control.MOUSE_FILTER_STOP
		tessere_mie.add_child(ti)
	for c in g["mano"]:
		mano_box.add_child(carta(c, 118.0))
	for t in g["tavolo"]:
		var cc := carta({"t": t, "img": _img_tipo(t)}, 104.0)
		cc.modulate = Color(1, 0.95, 0.85)
		mano_box.add_child(cc)
	for v in g["vuln"]:
		var vc := carta({"t": "vuln_contaminata" if v else "vuln_pulita", "img": "vulnerabili_219236cf" if v else "vulnerabili_af2a7d07"}, 90.0, false)
		mano_box.add_child(vc)

func _img_tipo(t: String) -> String:
	for mz in Dati.carte()["mazzi"]:
		for c in Dati.carte()["mazzi"][mz]:
			if c["tipo"] == t:
				return c["img"]
	return "vulnerabili_af2a7d07"

func _aggiorna_diario() -> void:
	var log: Array = m.s["log"]
	if log.size() < ultimo_log:
		ultimo_log = 0
		diario.clear()
	for k in range(ultimo_log, log.size()):
		var riga: String = log[k]
		if riga.begins_with("==="):
			diario.push_color(Color(0.45, 0.05, 0.03))
			diario.add_text("\n" + riga.replace("=", "").strip_edges() + "\n")
			diario.pop()
		elif riga.contains(": \""):
			diario.push_color(Color(0.1, 0.22, 0.45))
			diario.add_text(riga + "\n")
			diario.pop()
		else:
			diario.add_text(riga + "\n")
	if log.size() > ultimo_log and cronaca:
		var ultima: String = log[log.size() - 1]
		if not ultima.begins_with("==="):
			cronaca.text = ultima
			cronaca.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0) if ultima.contains(": \"") else C_GHIACCIO)
			cronaca.modulate.a = 1.0
			if cronaca_tw:
				cronaca_tw.kill()
			cronaca_tw = create_tween()
			cronaca_tw.tween_interval(2.5)
			cronaca_tw.tween_property(cronaca, "modulate:a", 0.0, 1.0)
	ultimo_log = log.size()

## Avvisa il giocatore quando ha visto qualcosa in segreto (segnalatori, esami).
func _controlla_conoscenze() -> void:
	var i := mio_pg()
	if i < 0:
		return
	var sa: Dictionary = m.g(i)["sa"]
	for k in sa:
		if not (sa[k] is Dictionary):
			continue
		var chiave := "%s_%s_%s" % [k, sa[k]["v"], sa[k]["turno"]]
		if conoscenze_viste.has(chiave):
			continue
		conoscenze_viste[chiave] = true
		var j := int(k)
		if sa[k]["v"] == "infetto":
			_notifica("Il segnalatore di %s dice: INFETTO.%s" % [m.nome(j), " Ora sei anche tu della Cosa." if m.g(i)["infetto"] else ""], C_SANGUE)
		else:
			_notifica("Hai visto %s: PULITO." % m.nome(j), C_GHIACCIO)

func _notifica(t: String, col: Color) -> void:
	var p := pannello(Color(0.04, 0.05, 0.08, 0.96), col)
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.position = Vector2(-280, 60)
	p.custom_minimum_size = Vector2(460, 0)
	var l := etichetta(t, F_TITOLO, 24, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	schermo.add_child(p)
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)

# ---------- fine partita

func _mostra_fine() -> void:
	_chiudi_dialogo()
	_pulisci_azioni()
	titolo_azioni.text = "PARTITA FINITA"
	if not online:
		if FileAccess.file_exists(SALVA_LOCALE):
			DirAccess.remove_absolute(SALVA_LOCALE)
		net.cancella_partita()
	var es: Dictionary = m.s["esito"]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var griglia := GridContainer.new()
	griglia.columns = 4
	griglia.add_theme_constant_override("h_separation", 10)
	v.add_child(griglia)
	for i in m.s["ordine"]:
		var g: Dictionary = m.g(i)
		var cell := VBoxContainer.new()
		var img := immagine("res://assets/pg/%s.webp" % g["pg"], 90, 90)
		if g["morto"]:
			img.modulate = Color(0.45, 0.35, 0.35)
		cell.add_child(img)
		cell.add_child(etichetta(m.nome(i), F_GRASSETTO, 16))
		cell.add_child(etichetta("INFETTO" if g["infetto"] else "UMANO", F_TITOLO, 20, C_SANGUE if g["infetto"] else C_GHIACCIO))
		var dove := "morto" if g["morto"] else ("a bordo" if g["bordo"] else "a terra")
		var tiro = es.get("tiri", {}).get(str(i), null)
		cell.add_child(etichetta(dove + ("  dado %d, bonus %d" % [int(tiro), m.bonus_giocatore(i)] if tiro != null else ""), F_TESTO, 14, C_SPENTO))
		griglia.add_child(cell)
	var i0 := mio_pg()
	var titolo := "FINE"
	if i0 >= 0:
		titolo = "HAI VINTO!" if m.ha_vinto(i0) else "HAI PERSO"
	_dialogo(titolo, str(es.get("testo", "")), [{"testo": "Torna al menu", "cb": mostra_menu}], v)
