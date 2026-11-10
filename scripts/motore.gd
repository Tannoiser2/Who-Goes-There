## Motore delle regole di Who Goes There? (Certifiable Studios).
## Tutto lo stato della partita sta in `s` (un dizionario che si può salvare in JSON e mandare in rete).
## Il motore va avanti da solo finché non serve una decisione: allora `richiesta()` dice chi deve
## decidere cosa, con l'elenco delle opzioni; `applica({"id": ...})` la esegue.
## I dadi usano un generatore con seme, quindi la stessa sequenza di decisioni dà sempre la stessa partita
## (è così che funziona il gioco online: si scambiano solo le decisioni).
class_name Motore
extends RefCounted

var s: Dictionary = {}
var rng := RandomNumberGenerator.new()

const MAX_LOG := 4000

# ============================================================ avvio

## cfg: {pg: [id personaggi], seat: [-1 = IA, altrimenti posto], seed: int, lunga: bool}
func nuova(cfg: Dictionary) -> void:
	rng.seed = int(cfg.get("seed", 1))
	var pgs: Array = cfg["pg"]
	s = {"seed": int(cfg.get("seed", 1)), "passo": 0, "lunga": bool(cfg.get("lunga", false)),
		"turni": Dati.turni(bool(cfg.get("lunga", false))), "turno": -1, "fase": 1, "facile": bool(cfg.get("facile", false)),
		"giocatori": [], "ordine": [], "capo": 0, "corrente": -1, "stadio": "inizio",
		"mazzi": {}, "scarti_fase": [], "scarti_campo": [], "falo": [], "evento": {}, "blocco": false,
		"prossimo_evento": {}, "caldaia": 0, "porta": 0, "banco": {}, "riferimenti": [],
		"coda": [], "ctx": {}, "log": [], "dichiarazioni": [], "esito": {}, "eventi_pubblici": [], "n_vuln_pubbliche": {},
		"trattative": {}, "bisogni": {}}
	for k in Dati.TESSERE:
		s["banco"][k] = int(Dati.TESSERE[k]["n"])
	var c := Dati.carte()
	for m in c["mazzi"]:
		var arr: Array = []
		for card in c["mazzi"][m]:
			arr.append({"t": card["tipo"], "img": card["img"]})
		s["mazzi"][m] = arr
	for m in s["mazzi"]:
		_mescola(s["mazzi"][m])
	# 5 carte di ogni mazzo Fase scartate coperte
	for f in ["fase1", "fase2", "fase3"]:
		for i in 5:
			s["mazzi"][f].pop_back()
	var seats: Array = cfg.get("seat", [])
	for i in pgs.size():
		var pg: String = pgs[i]
		var g := {"pg": pg, "seat": int(seats[i]) if i < seats.size() else -1, "pos": "", "azioni": 5, "azioni_max": 5,
			"stamina": 3, "stamina_max": 5, "xp": 0, "ferite": 0, "critiche": 0, "mano": [], "vuln": [],
			"infetto": false, "ospite": false, "sblocchi": {}, "tessere": [], "tavolo": [], "armadietto": "",
			"arm_usato": false, "morto": false, "lasciato": "", "cambiato": false, "ev_fatto": false,
			"sa": {}, "flask": false, "hotspot": false, "giocato": false, "bordo": false, "n_vuln_ricevute": 0,
			"scienziato": false, "azioni_turno": 0, "jack": "", "rifiuti": {}, "tiri_bonus": 0}
		s["giocatori"].append(g)
	var ordine := range(pgs.size())
	ordine.sort_custom(func(a, b): return Dati.PG[pgs[a]]["grado"] < Dati.PG[pgs[b]]["grado"])
	s["ordine"] = ordine
	s["capo"] = ordine[0]
	_log("Avamposto 31, Antartide. %d sopravvissuti. Il capo è %s." % [pgs.size(), nome(s["capo"])])
	# ognuno pesca 1 carta da Magazzino, Officina e dal suo mazzo Specialità
	for gi in ordine:
		_pesca_mano(gi, "magazzino")
		_pesca_mano(gi, "officina")
		_pesca_mano(gi, Dati.PG[pgs[gi]]["mazzo"])
	# scelta dello spazio di partenza, in ordine di turno
	for gi in ordine:
		s["coda"].append({"g": gi, "k": "partenza", "testo": "Dove inizi la partita?", "opz": [
			{"id": "magazzino", "testo": "Magazzino (dentro): Scatolette, Pronto soccorso, armi"},
			{"id": "officina", "testo": "Officina (dentro): materiali per costruire"},
			{"id": "fase1", "testo": "Fuori, Fase 1: XP e Bonus elicottero (ma fa freddo)"}]})
	_salva_rng()
	avanza()

func carica(stato: Dictionary) -> void:
	s = stato
	rng.seed = int(s["seed"])
	rng.state = int(str(s.get("rng", "0")))

func _salva_rng() -> void:
	s["rng"] = str(rng.state)

# ============================================================ utilità

func g(i: int) -> Dictionary:
	return s["giocatori"][i]

func nome(i: int) -> String:
	return Dati.PG[g(i)["pg"]]["nome"]

func vivi() -> Array:
	var out := []
	for i in s["ordine"]:
		if not g(i)["morto"]:
			out.append(i)
	return out

func dentro(i: int) -> bool:
	return Dati.dentro(g(i)["pos"])

func luogo(i: int) -> String:
	return "dentro" if dentro(i) else "fuori"

func stesso_luogo(a: int, b: int) -> bool:
	return luogo(a) == luogo(b)

## Una frase detta ad alta voce da un personaggio (finisce nel diario).
func dice(i: int, frase: String) -> void:
	_log("%s: \"%s\"" % [nome(i), frase])

func _log(t: String) -> void:
	s["log"].append(t)
	if s["log"].size() > MAX_LOG:
		s["log"].pop_front()

func _mescola(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

func dado() -> bool:
	return rng.randi_range(0, 5) < 3

func turno_info() -> Dictionary:
	if s["turno"] < 0 or s["turno"] >= s["turni"].size():
		return {"fase": 3, "tipo": "elicottero"}
	return s["turni"][s["turno"]]

func fase() -> int:
	return int(turno_info().get("fase", 3)) if s["turno"] >= 0 else 1

func ha_sblocco(i: int, k: String) -> bool:
	return bool(g(i)["sblocchi"].get(k, false))

func dadi_naturali(i: int) -> int:
	var st: int = g(i)["stamina"]
	if st <= 0:
		return 0
	return 1 if st <= 3 else 2

func max_mano(i: int) -> int:
	return 7 if "pouch" in g(i)["tessere"] else 5

func spazi_oggetti(i: int) -> int:
	var n := 2
	if ha_sblocco(i, "spazi"):
		n += 3
	if g(i)["pg"] == "vanwall" and ha_sblocco(i, "unico"):
		n += 1
	return n

func spazi_usati(i: int) -> int:
	var n := 0
	for t in g(i)["tessere"]:
		n += int(Dati.TESSERE[t].get("spazi", 1))
	return n

func conta_mano(i: int, tipo: String) -> int:
	var n := 0
	for c in g(i)["mano"]:
		if c["t"] == tipo:
			n += 1
	return n

func indice_mano(i: int, tipo: String) -> int:
	for k in g(i)["mano"].size():
		if g(i)["mano"][k]["t"] == tipo:
			return k
	return -1

func vuln_pulite(i: int) -> int:
	var n := 0
	for v in g(i)["vuln"]:
		if not v:
			n += 1
	return n

func ha_contaminata(i: int) -> bool:
	return true in g(i)["vuln"]

func umani_veri() -> Array:
	var out := []
	for i in s["ordine"]:
		if not g(i)["infetto"]:
			out.append(i)
	return out

func _carta_da_mazzo(m: String):
	var d: Array = s["mazzi"][m]
	if d.is_empty():
		return null
	return d.pop_back()

func _pesca_mano(i: int, m: String) -> bool:
	var c = _carta_da_mazzo(m)
	if c == null:
		_log("Il mazzo %s è vuoto." % _nome_mazzo(m))
		return false
	g(i)["mano"].append(c)
	return true

func _nome_mazzo(m: String) -> String:
	if m.begins_with("specialita"):
		return "Specialità"
	return {"magazzino": "del Magazzino", "officina": "dell'Officina", "fase1": "Fase 1", "fase2": "Fase 2",
		"fase3": "Fase 3", "eventi": "degli eventi", "vulnerabili": "Vulnerabili"}.get(m, m)

func mazzo_specialita(i: int) -> String:
	return Dati.PG[g(i)["pg"]]["mazzo"]

func _scarta(c: Dictionary) -> void:
	s["scarti_campo"].append(c)

# ============================================================ ciclo principale

func richiesta() -> Dictionary:
	if s["coda"].is_empty():
		return {}
	var r: Dictionary = s["coda"][0]
	if r["k"] == "ombre":
		r["opz"] = _opz_mano(r["g"])
		if r["opz"].is_empty():
			r["opz"] = [{"id": "niente", "testo": "Non hai carte da passare"}]
	return r

func finita() -> bool:
	return s["stadio"] == "fine"

## Esegue i passi automatici finché serve una decisione.
func avanza() -> void:
	var guard := 0
	while s["coda"].is_empty() and s["stadio"] != "fine":
		guard += 1
		if guard > 500:
			push_error("motore bloccato")
			return
		_passo_auto()
	_salva_rng()

func _passo_auto() -> void:
	var st: String = s["stadio"]
	if st == "inizio":
		s["stadio"] = "preturno"
		s["passi"] = []
		_nuovo_turno()
	elif st == "preturno":
		if s["passi"].is_empty():
			_inizia_giri()
		else:
			var p: String = s["passi"].pop_front()
			call("_pre_" + p)
	elif st == "giro":
		_prossimo_giocatore()
	elif st == "elicottero":
		_elicottero_passo()

func _nuovo_turno() -> void:
	s["turno"] += 1
	if s["turno"] >= s["turni"].size():
		s["stadio"] = "elicottero"
		s["passi_eli"] = ["imbarco"]
		_log("=== IL TURNO DELL'ELICOTTERO ===")
		return
	var t := turno_info()
	s["fase"] = t["fase"]
	_log("=== Turno %d (Fase %d)%s ===" % [s["turno"] + 1, t["fase"], {"pasto": " - PASTO", "sonno": " - SONNO"}.get(t["tipo"], "")])
	s["passi"] = []
	if t["tipo"] == "pasto":
		s["passi"].append("pasto")
	elif t["tipo"] == "sonno":
		s["passi"].append("sonno")
	s["passi"].append_array(["freddo", "reset", "evento", "istantaneo"])

# ---------- passi del preturno

func _pre_pasto() -> void:
	_log("Turno del Pasto: tutti devono mangiare una Scatoletta.")
	for i in vivi():
		var gg := g(i)
		var k := indice_mano(i, "scatoletta")
		if k < 0:
			k = indice_mano(i, "scatoletta2")
		if k < 0 and gg["pg"] == "kinner" and ha_sblocco(i, "unico"):
			k = indice_mano(i, "snack")
		if k >= 0:
			var c: Dictionary = gg["mano"][k]
			gg["mano"].remove_at(k)
			_scarta(c)
			_guadagna_stamina(i, 2 if c["t"] == "scatoletta2" else 1)
			_log("%s mangia (%s)." % [nome(i), Dati.nome_carta(c["t"])])
		else:
			_log("%s non ha cibo: è vulnerabile." % nome(i))
			_vulnerabile(i)
		if gg["jack"] != "":
			var kk := indice_mano(i, "biscotto")
			if kk < 0:
				kk = indice_mano(i, "scatoletta")
			if kk >= 0:
				_scarta(gg["mano"][kk])
				gg["mano"].remove_at(kk)
				_log("Jack mangia.")
			elif gg["armadietto"] == "biscotto" and not gg["arm_usato"]:
				gg["arm_usato"] = true
				_log("Jack mangia un biscotto dall'armadietto.")
			else:
				_log("Jack non ha da mangiare: Clark è vulnerabile.")
				_vulnerabile(i)

func _pre_sonno() -> void:
	_log("Turno del Sonno: si dorme in coppia, nello stesso luogo.")
	s["ctx"]["letti"] = {}
	s["ctx"]["rifiuti_letto"] = {}
	_sonno_prossimo()

func _sonno_prossimo() -> void:
	var letti: Dictionary = s["ctx"]["letti"]
	for i in vivi():
		if letti.has(str(i)):
			continue
		var opz := []
		for j in vivi():
			if j != i and not letti.has(str(j)) and stesso_luogo(i, j) and not s["ctx"]["rifiuti_letto"].has("%d_%d" % [i, j]):
				opz.append({"id": "con:%d" % j, "testo": "Dormi con %s" % nome(j), "j": j})
		opz.append({"id": "solo", "testo": "Dormi da solo (peschi una carta Vulnerabile)"})
		s["coda"].append({"g": i, "k": "letto", "testo": "Con chi dormi stanotte?", "opz": opz})
		return

func _dorme_solo(i: int) -> void:
	s["ctx"]["letti"][str(i)] = -1
	var gg := g(i)
	_log("%s dorme da solo." % nome(i))
	if gg["jack"] == "companion_trained":
		_log("Jack veglia su Clark: niente carta Vulnerabile.")
		return
	if gg["jack"] == "companion" or "barricade" in gg["tessere"]:
		if dado():
			_log("Successo: %s dorme tranquillo." % nome(i))
			return
	var k := indice_mano(i, "adrenalina")
	if k >= 0:
		_scarta(gg["mano"][k])
		gg["mano"].remove_at(k)
		_log("%s usa l'Adrenalina e resta sveglio." % nome(i))
		return
	_vulnerabile(i)

func _pre_freddo() -> void:
	var f := fase()
	var porta_rotta: bool = s["porta"] >= 3
	for i in vivi():
		if dentro(i) and not porta_rotta:
			continue
		var gg := g(i)
		if gg["stamina"] <= 0:
			_log("%s sta congelando: 1 Ferita." % nome(i))
			_ferita(i)
		else:
			gg["stamina"] = max(0, gg["stamina"] - f)
			_log("Calo di temperatura: %s perde %d Stamina." % [nome(i), f])

func _pre_reset() -> void:
	for i in vivi():
		var gg := g(i)
		gg["azioni"] = gg["azioni_max"]
		gg["giocato"] = false
		gg["ev_fatto"] = false
		gg["scienziato"] = false
		gg["lasciato"] = ""
		gg["cambiato"] = false
		gg["flask"] = false
		gg["hotspot"] = false
		if ha_sblocco(i, "armadietto"):
			# l'IA e il giocatore tengono la faccia buona se non l'hanno usata; altrimenti si ritira
			if gg["arm_usato"] or gg["armadietto"] == "":
				gg["armadietto"] = Dati.FACCE_ARMADIETTO[rng.randi_range(0, 5)]
				gg["arm_usato"] = false
		if "barricade" in gg["tessere"]:
			gg["xp"] += 1

func _pre_evento() -> void:
	var c = _carta_da_mazzo("eventi")
	if c == null:
		s["mazzi"]["eventi"] = s.get("scarti_eventi", [])
		s["scarti_eventi"] = []
		_mescola(s["mazzi"]["eventi"])
		c = _carta_da_mazzo("eventi")
	if c == null:
		s["evento"] = {}
		return
	if not s.has("scarti_eventi"):
		s["scarti_eventi"] = []
	s["scarti_eventi"].append(c)
	s["evento"] = c
	var info: Dictionary = Dati.EVENTI[c["t"]]
	s["blocco"] = bool(info.get("blocco", false))
	_log("Evento del campo: %s%s." % [Dati.nome_carta(c["t"]), " (BLOCCO: riguarda solo chi è dentro)" if s["blocco"] else ""])
	# Sesto senso di Clark: si può saltare l'evento
	for i in vivi():
		if indice_mano(i, "sesto_senso") >= 0:
			s["coda"].append({"g": i, "k": "sesto_senso", "testo": "Evento: %s. Usi Sesto senso per saltarlo?" % Dati.nome_carta(c["t"]),
				"opz": [{"id": "si", "testo": "Sì, salta all'evento successivo"}, {"id": "no", "testo": "No"}]})
			return

func _pre_istantaneo() -> void:
	if s["evento"].is_empty():
		return
	var t: String = s["evento"]["t"]
	if Dati.EVENTI[t]["tipo"] != "istantaneo":
		return
	match t:
		"ev_danno_caldaia":
			_danno_caldaia(2)
		"ev_congelamento":
			for i in vivi():
				g(i)["azioni"] = max(0, g(i)["azioni"] - 1)
			_log("Congelamento: tutti perdono 1 Azione.")
		"ev_paranoia_dadi":
			var tot := 0
			for i in vivi():
				for k in 4:
					if dado():
						tot += 1
			var serve := 2 * vivi().size()
			_log("Paranoia: %d Successi su %d necessari." % [tot, serve])
			if tot < serve:
				for i in vivi():
					_ferita(i)
		"ev_paranoia_carte":
			for i in vivi():
				if dado():
					s["coda"].append({"g": i, "k": "pesca_interna", "testo": "Paranoia: Successo! Da quale mazzo interno peschi?", "opz": _opz_mazzi_interni(i)})
				elif not g(i)["mano"].is_empty():
					s["coda"].append({"g": i, "k": "scarta", "testo": "Paranoia: Mancato. Scegli una carta da scartare.", "opz": _opz_mano(i)})
		"ev_ombre":
			var capo: int = s["capo"]
			if g(capo)["morto"]:
				capo = vivi()[0]
			s["ctx"]["ombre"] = []
			s["coda"].append({"g": capo, "k": "pesca_interna", "testo": "Ombre mortali: peschi 1 carta da un mazzo interno.", "opz": _opz_mazzi_interni(capo)})
			for i in vivi():
				s["coda"].append({"g": i, "k": "ombre", "testo": "Ombre mortali: scegli la carta da passare a %s." % nome(_successivo(i)), "opz": []})
		"ev_scienziato":
			_log("Lo scienziato: chi vuole può spendere 1 XP per avere 1 Azione in più.")

func _successivo(i: int) -> int:
	var v := vivi()
	var k := v.find(i)
	return v[(k + 1) % v.size()]

func _opz_mazzi_interni(i: int) -> Array:
	return [{"id": "magazzino", "testo": "Magazzino"}, {"id": "officina", "testo": "Officina"},
		{"id": mazzo_specialita(i), "testo": "Il tuo mazzo Specialità"}]

func _opz_mano(i: int, filtro := "") -> Array:
	var out := []
	for k in g(i)["mano"].size():
		var c: Dictionary = g(i)["mano"][k]
		if filtro == "" or c["t"] == filtro:
			out.append({"id": "c%d" % k, "testo": Dati.nome_carta(c["t"]), "k": k})
	return out

func _inizia_giri() -> void:
	s["stadio"] = "giro"
	s["corrente"] = -1

func _prossimo_giocatore() -> void:
	var ord: Array = s["ordine"]
	s["corrente"] += 1
	while s["corrente"] < ord.size() and g(ord[s["corrente"]])["morto"]:
		s["corrente"] += 1
	if vivi().is_empty():
		_fine_tutti_morti()
		return
	if s["corrente"] >= ord.size():
		s["stadio"] = "preturno"
		_nuovo_turno()
		return
	var i: int = ord[s["corrente"]]
	g(i)["azioni_turno"] = 0
	g(i)["rifiuti"] = {}
	s["trattative"] = {}
	_chiedi_turno(i)

func corrente() -> int:
	if s["stadio"] != "giro" or s["corrente"] < 0 or s["corrente"] >= s["ordine"].size():
		return -1
	return s["ordine"][s["corrente"]]

func _chiedi_turno(i: int) -> void:
	s["coda"].append({"g": i, "k": "turno", "testo": "Il tuo turno", "opz": azioni_possibili(i)})

# ============================================================ azioni del turno

func evento_mi_riguarda(i: int) -> bool:
	if s["evento"].is_empty():
		return false
	var info: Dictionary = Dati.EVENTI[s["evento"]["t"]]
	if info["tipo"] == "istantaneo":
		return false
	if s["blocco"] and not dentro(i):
		return false
	return true

func costo_muovere(i: int) -> int:
	if "guideline" in g(i)["tessere"]:
		return 0
	return 1

func costo_cercare(i: int) -> int:
	if dentro(i) and "mechanic_coat" in g(i)["tessere"]:
		return 1
	if not dentro(i) and "travel_coat" in g(i)["tessere"]:
		return 1
	return 2

## Successi richiesti contro eventi e attacchi: quanti la Fase (nella modalità clemente uno in meno, minimo 1).
func successi_richiesti() -> int:
	if s.get("facile", false):
		return max(1, fase() - 1)
	return fase()

func fasi_aperte() -> int:
	return fase()

func azioni_possibili(i: int) -> Array:
	var gg := g(i)
	var a: int = gg["azioni"]
	var out := []
	var pos: String = gg["pos"]
	var serve_evento: bool = evento_mi_riguarda(i) and not gg["ev_fatto"]
	if serve_evento:
		var ev: String = s["evento"]["t"]
		out.append({"id": "evento", "testo": "Affronta l'evento: %s (%s, servono %d Successi)" % [Dati.nome_carta(ev), Dati.EVENTI[ev]["tipo"], successi_richiesti()], "gr": "evento"})
	# muoversi
	var cm := costo_muovere(i)
	var snow: bool = gg["armadietto"] == "racchette" and not gg["arm_usato"]
	for sp in ["magazzino", "officina", "fase1", "fase2", "fase3"]:
		if sp == pos:
			continue
		if sp.begins_with("fase") and int(sp.substr(4)) > fasi_aperte():
			continue
		var cambia: bool = Dati.dentro(sp) != Dati.dentro(pos)
		if cambia and (s["blocco"] or gg["cambiato"]):
			continue
		if cambia and gg["lasciato"] == ("dentro" if Dati.dentro(sp) else "fuori"):
			continue
		if a >= cm:
			out.append({"id": "muovi:" + sp, "testo": "Vai: %s (%d Azion%s)" % [Dati.NOMI_SPAZI[sp], cm, "e" if cm == 1 else "i"], "gr": "muovi", "sp": sp})
		elif snow:
			pass
		if snow and cm > 0:
			out.append({"id": "muovi_racchette:" + sp, "testo": "Vai: %s con le racchette (gratis)" % Dati.NOMI_SPAZI[sp], "gr": "muovi", "sp": sp})
	# cercare
	var cc := costo_cercare(i)
	if a >= cc:
		if Dati.dentro(pos):
			out.append({"id": "cerca:" + pos, "testo": "Cerca nel %s (%d Azioni)" % [Dati.NOMI_SPAZI[pos], cc], "gr": "cerca"})
			if not s["mazzi"][mazzo_specialita(i)].is_empty():
				out.append({"id": "cerca:" + mazzo_specialita(i), "testo": "Cerca nel tuo mazzo Specialità (%d Azioni)" % cc, "gr": "cerca"})
		elif not s["mazzi"][pos].is_empty():
			out.append({"id": "cerca:" + pos, "testo": "Cerca nel mazzo %s (%d Azioni, +2 XP)" % [Dati.NOMI_SPAZI[pos], cc], "gr": "cerca"})
	# costruire
	var puo_costruire := dentro(i) or _riferimento("banco_lavoro")
	if puo_costruire and a >= 1:
		for r in Dati.ORDINE_RICETTE:
			if puo_costruire_oggetto(i, r):
				out.append({"id": "costruisci:" + r, "testo": "Costruisci: %s (1 Azione)" % Dati.TESSERE[r]["nome"], "gr": "costruisci"})
	# stamina / xp / riparare
	if a >= 1 and dentro(i) and s["caldaia"] < 3 and gg["stamina"] < gg["stamina_max"]:
		out.append({"id": "stamina", "testo": "Riscaldati alla caldaia: tira 1 dado per +1 Stamina (1 Azione)", "gr": "azioni"})
	if a >= 1 and not dentro(i):
		out.append({"id": "xp", "testo": "Esplora: tira 1 dado per +1 XP (1 Azione)", "gr": "azioni"})
	var dan: int = s["caldaia"] if dentro(i) else s["porta"]
	if dan > 0:
		var cosa := "la Caldaia" if dentro(i) else "la Porta"
		if a >= 2:
			out.append({"id": "ripara", "testo": "Ripara %s: togli 1 Danno (2 Azioni)" % cosa, "gr": "azioni"})
		if a >= 1:
			out.append({"id": "ripara_tiro", "testo": "Ripara %s a fortuna: tira 1 dado (1 Azione)" % cosa, "gr": "azioni"})
	# Fiaschetta di MacReady
	if gg["pg"] == "mcready" and ha_sblocco(i, "unico") and not dentro(i) and not gg["flask"]:
		out.append({"id": "fiaschetta", "testo": "Fiaschetta: tira 1 dado per +1 Stamina (gratis, 1 volta per turno)", "gr": "azioni"})
	# Lo scienziato
	if not s["evento"].is_empty() and s["evento"]["t"] == "ev_scienziato" and not gg["scienziato"] and gg["xp"] >= 1:
		out.append({"id": "scienziato", "testo": "Lo scienziato: spendi 1 XP per +1 Azione", "gr": "azioni"})
	# carte giocabili
	for k in gg["mano"].size():
		var c: Dictionary = gg["mano"][k]
		var o := _opz_gioca(i, k, c)
		if not o.is_empty():
			out.append(o)
	# falò
	if dentro(i):
		for k in gg["mano"].size():
			var c: Dictionary = gg["mano"][k]
			out.append({"id": "falo:%d" % k, "testo": "Metti nel Falò: %s" % Dati.nome_carta(c["t"]), "gr": "falo", "k": k})
		if s["falo"].size() >= 5 and _puo_accendere(i):
			out.append({"id": "accendi", "testo": "Accendi il Falò (%d carte): tutti dentro +2 Stamina" % s["falo"].size(), "gr": "falo"})
	# dado armadietto
	if ha_sblocco(i, "armadietto") and not gg["arm_usato"] and gg["armadietto"] != "":
		var o := _opz_armadietto(i)
		if not o.is_empty():
			out.append(o)
	# sblocchi
	for k in Dati.ORDINE_SBLOCCHI:
		if ha_sblocco(i, k):
			continue
		var costo: int = Dati.SBLOCCHI[k]["xp"]
		if k == "scorta_xp":
			var tutti := true
			for k2 in Dati.ORDINE_SBLOCCHI:
				if k2 != "scorta_xp" and not ha_sblocco(i, k2):
					tutti = false
			if not tutti:
				continue
		if gg["xp"] >= costo:
			var nm: String = Dati.SBLOCCHI[k]["nome"]
			if k == "unico":
				nm = "Abilità: " + Dati.PG[gg["pg"]]["unico_nome"]
			out.append({"id": "sblocca:" + k, "testo": "Sblocca %s (%d XP)" % [nm, costo], "gr": "sblocca"})
	# scambi
	for j in vivi():
		if j == i or not _possono_scambiare(i, j):
			continue
		var aperta := _trattativa_aperta(i, j)
		if aperta or _puo_ricevere(j):
			for k in gg["mano"].size():
				var c: Dictionary = gg["mano"][k]
				out.append({"id": "dai:%d:%d" % [j, k], "testo": "Dai a %s: %s%s" % [nome(j), Dati.nome_carta(c["t"]), " (stesso scambio)" if aperta else ""], "gr": "scambi", "j": j, "k": k})
		if (a >= 1 or _trattativa_aperta(j, i)) and not g(j)["mano"].is_empty() and gg["mano"].size() < max_mano(i) + 3:
			for tipo in ["scatoletta", "pronto_soccorso", "fiammiferi", "alcol", "legno", "stoffa", "corda", "viti", "metallo"]:
				if not g(i)["rifiuti"].has("%d_%s" % [j, tipo]):
					out.append({"id": "chiedi:%d:%s" % [j, tipo], "testo": "Chiedi a %s: %s (1 Azione se te la dà)" % [nome(j), Dati.nome_carta(tipo)], "gr": "chiedi", "j": j, "tipo": tipo})
	# dire agli altri cosa ti serve (non costa Azioni)
	var miei: Array = s["bisogni"].get(str(i), [])
	for tipo in ["scatoletta", "pronto_soccorso", "fiammiferi", "alcol", "legno", "stoffa", "corda", "viti", "metallo"]:
		if tipo in miei:
			out.append({"id": "nonserve:" + tipo, "testo": "Non mi serve più: %s" % Dati.nome_carta(tipo), "gr": "bisogni"})
		elif miei.size() < 3:
			out.append({"id": "serve:" + tipo, "testo": "Annuncia che ti serve: %s" % Dati.nome_carta(tipo), "gr": "bisogni"})
	# assalto e attacco d'infezione
	if a >= 5:
		for j in vivi():
			if j != i and stesso_luogo(i, j):
				out.append({"id": "assalto:%d" % j, "testo": "ASSALTA %s (5 Azioni): ogni Successo gli dà 1 Ferita" % nome(j), "gr": "assalto", "j": j})
		if gg["ospite"] and ha_contaminata(i) and vuln_pulite(i) >= 1:
			var bersagli := []
			for j in vivi():
				if j != i and stesso_luogo(i, j):
					bersagli.append(j)
			var n: int = min(bersagli.size(), vuln_pulite(i))
			for q in range(1, n + 1):
				out.append({"id": "infezione:%d" % q, "testo": "ATTACCO D'INFEZIONE su %d giocator%s nel tuo luogo (5 Azioni, ti riveli)" % [q, "e" if q == 1 else "i"], "gr": "assalto", "n": q})
	# tessere da scartare
	for k in gg["tessere"].size():
		out.append({"id": "scarta_tessera:%d" % k, "testo": "Scarta la tessera %s" % Dati.TESSERE[gg["tessere"][k]]["nome"], "gr": "tessere", "k": k})
	# riferimenti (landmark) utilizzabili
	out.append_array(_opz_riferimenti(i))
	# scartare carte
	for k in gg["mano"].size():
		out.append({"id": "scarta:%d" % k, "testo": "Scarta: %s" % Dati.nome_carta(gg["mano"][k]["t"]), "gr": "scarta", "k": k})
	if not serve_evento:
		out.append({"id": "fine", "testo": "Fine del turno", "gr": "fine"})
	else:
		out.append({"id": "fine", "testo": "Fine del turno (prima affronti l'evento)", "gr": "fine"})
	return out

func _possono_scambiare(i: int, j: int) -> bool:
	if stesso_luogo(i, j):
		return true
	if _riferimento("sella"):
		for k in vivi():
			if g(k)["jack"] != "":
				return true
	return false

## Uno scambio fra due giocatori resta aperto per tutto il turno: chi riceve paga 1 Azione una volta sola,
## e il segnalatore di chi dà si passa una volta sola, qualunque sia il numero di carte.
func _trattativa_aperta(da: int, a: int) -> bool:
	return s["trattative"].has("%d_%d" % [da, a])

## Chi riceve una carta spende 1 Azione: se ha già giocato il turno deve averne tenuta una da parte.
func _puo_ricevere(j: int) -> bool:
	return g(j)["azioni"] >= 1

func _puo_accendere(i: int) -> bool:
	if indice_mano(i, "fiammiferi") >= 0 or "lighter" in g(i)["tessere"]:
		return true
	if g(i)["pg"] == "blair" and ha_sblocco(i, "unico"):
		return true
	return false

func _riferimento(t: String) -> bool:
	for r in s["riferimenti"]:
		if r["t"] == t:
			return true
	return false

func _opz_gioca(i: int, k: int, c: Dictionary) -> Dictionary:
	var gg := g(i)
	var t: String = c["t"]
	var base := {"gr": "carte", "k": k}
	var nm := Dati.nome_carta(t)
	match t:
		"alcol":
			if not dentro(i) and gg["stamina"] < gg["stamina_max"]:
				return _d(base, "gioca:%d" % k, "Bevi l'Alcol: +1 Stamina")
		"scatoletta", "scatoletta2", "snack":
			if gg["stamina"] < gg["stamina_max"]:
				return _d(base, "gioca:%d" % k, "Mangia %s: +%d Stamina" % [nm, 2 if t == "scatoletta2" else 1])
		"pronto_soccorso":
			if gg["ferite"] + gg["critiche"] > 0:
				return _d(base, "gioca:%d" % k, "Pronto soccorso: togli 1 Ferita")
		"dex":
			return _d(base, "gioca:%d" % k, "Dex: +1 Azione")
		"boost_stamina":
			return _d(base, "gioca:%d" % k, "Ricarica: +2 o +3 Stamina")
		"carta_piede_porco", "carta_lanciarazzi", "carta_torcia", "bisturi", "lanciarazzi_kinner", "coltellino":
			var tess: String = {"carta_piede_porco": "crowbar", "carta_lanciarazzi": "flare_gun", "carta_torcia": "torch",
				"bisturi": "knife", "lanciarazzi_kinner": "flare_gun_kinner", "coltellino": "pocket_knife"}[t]
			if puo_equipaggiare(i, tess):
				return _d(base, "gioca:%d" % k, "%s: prendi la tessera %s" % [nm, Dati.TESSERE[tess]["nome"]])
		"accendino_vuoto":
			pass
		"guaritore":
			return _d(base, "gioca:%d" % k, "Guarigione rapida: -1 Ferita a chi è nel tuo spazio")
		"kit_riparazione":
			if (dentro(i) and s["caldaia"] > 0) or (not dentro(i) and s["porta"] > 0):
				return _d(base, "gioca:%d" % k, "Kit riparazione: togli 1 Danno a %s" % ("Caldaia" if dentro(i) else "Porta"))
		"esame_sangue":
			if gg["vuln"].size() >= 1:
				for j in vivi():
					if j != i and stesso_luogo(i, j):
						return _d(base, "gioca:%d" % k, "Esame del sangue con un giocatore del tuo luogo")
		"test_ospite":
			if gg["vuln"].size() >= 1:
				for j in vivi():
					if j != i and stesso_luogo(i, j) and g(j)["vuln"].size() >= 1:
						return _d(base, "gioca:%d" % k, "Test dell'Ospite con un giocatore del tuo luogo")
		"resistenza":
			return _d(base, "gioca:%d" % k, "Resistenza: tutti ottengono il Cardio")
		"ingegno":
			return _d(base, "gioca:%d" % k, "Ingegno: tutti ritirano il dado Armadietto")
		"riporto":
			return _d(base, "gioca:%d" % k, "Riporto!: tutti girano il dado Armadietto su Razzo")
		"legnetti":
			if dentro(i):
				return _d(base, "gioca:%d" % k, "Legnetti nel Falò: +1 Stamina extra quando si accende")
		"dispensa", "stazione_medica", "sella", "cassetta_attrezzi":
			if dentro(i):
				return _d(base, "gioca:%d" % k, "Metti in gioco: %s" % nm)
		"offro_io", "banco_lavoro":
			return _d(base, "gioca:%d" % k, "Metti in gioco: %s" % nm)
		"manuale_addestramento":
			if gg["jack"] == "companion":
				return _d(base, "gioca:%d" % k, "Manuale: Jack diventa addestrato")
	return {}

func _d(base: Dictionary, id: String, testo: String) -> Dictionary:
	var o := base.duplicate()
	o["id"] = id
	o["testo"] = testo
	return o

func _opz_armadietto(i: int) -> Dictionary:
	var gg := g(i)
	var f: String = gg["armadietto"]
	var faccia := f
	if f == "unico":
		faccia = Dati.PG[gg["pg"]]["armadietto"]
	var base := {"gr": "armadietto"}
	match faccia:
		"xp2":
			return _d(base, "armadietto", "Dado armadietto: +2 XP")
		"snack":
			if gg["stamina"] < gg["stamina_max"]:
				return _d(base, "armadietto", "Dado armadietto: Snack, +1 Stamina")
		"alcol":
			if not dentro(i) and gg["stamina"] < gg["stamina_max"]:
				return _d(base, "armadietto", "Dado armadietto: Alcol, +1 Stamina")
		"pronto_soccorso":
			if gg["ferite"] + gg["critiche"] > 0:
				return _d(base, "armadietto", "Dado armadietto: togli 1 Ferita")
		"kit_riparazione":
			if (dentro(i) and s["caldaia"] > 0) or (not dentro(i) and s["porta"] > 0):
				return _d(base, "armadietto", "Dado armadietto: togli 1 Danno a %s" % ("Caldaia" if dentro(i) else "Porta"))
	return {}

func _opz_riferimenti(i: int) -> Array:
	var out := []
	for r in s["riferimenti"]:
		match r["t"]:
			"dispensa":
				if dentro(i) and g(i)["xp"] >= 1:
					out.append({"id": "rif_dispensa", "testo": "Dispensa: spendi 1 XP e pesca una carta interna (%d usi)" % r["usi"], "gr": "carte"})
			"stazione_medica":
				if dentro(i) and g(i)["xp"] >= 5 and g(i)["ferite"] + g(i)["critiche"] > 0:
					out.append({"id": "rif_medica", "testo": "Stazione medica: spendi 5 XP e togli 1 Ferita", "gr": "carte"})
			"offro_io":
				if luogo(i) == r.get("luogo", "") and indice_mano(i, "alcol") >= 0:
					out.append({"id": "rif_offro", "testo": "Offro io: gioca un Alcol, +1 Stamina a tutti nel luogo (%d usi)" % r["usi"], "gr": "carte"})
	return out

# ---------- costruzione

func puo_equipaggiare(i: int, t: String) -> bool:
	if s["banco"].get(t, 0) <= 0:
		return false
	var gg := g(i)
	if t in gg["tessere"] and not (gg["pg"] == "norris" and ha_sblocco(i, "unico")):
		return false
	if Dati.TESSERE[t].get("cappotto", false):
		for x in gg["tessere"]:
			if Dati.TESSERE[x].get("cappotto", false):
				return false
	return spazi_usati(i) + int(Dati.TESSERE[t].get("spazi", 1)) <= spazi_oggetti(i)

## Restituisce le carte (indici in mano) da usare per la ricetta, oppure [] se non si può.
func carte_per_ricetta(i: int, r: String) -> Array:
	var ric: Dictionary = Dati.RICETTE[r]
	var mano: Array = g(i)["mano"]
	var usati := {}
	var out := []
	var risorsa_usata := false
	var arm_mat: bool = g(i)["armadietto"] in ["materiale"] and not g(i)["arm_usato"] and ha_sblocco(i, "armadietto")
	var cassetta: bool = _riferimento("cassetta_attrezzi") and dentro(i) and g(i)["xp"] >= 1
	var arm_alcol: bool = g(i)["armadietto"] == "unico" and Dati.PG[g(i)["pg"]]["armadietto"] == "alcol" and not g(i)["arm_usato"] and ha_sblocco(i, "armadietto")
	for m in ric["m"]:
		if m == "fiammiferi" and ("lighter" in g(i)["tessere"] or (g(i)["pg"] == "blair" and ha_sblocco(i, "unico"))):
			continue
		var trovato := -1
		for k in mano.size():
			if not usati.has(k) and mano[k]["t"] == m:
				trovato = k
				break
		if trovato < 0 and m != "accendino_vuoto":
			if arm_alcol and m == "alcol":
				arm_alcol = false
				out.append(-2)
				continue
			if arm_mat:
				arm_mat = false
				out.append(-2)
				continue
			if cassetta:
				cassetta = false
				out.append(-3)
				continue
			if not risorsa_usata:
				for k in mano.size():
					if not usati.has(k) and mano[k]["t"] == "risorsa":
						trovato = k
						risorsa_usata = true
						break
		if trovato < 0:
			return []
		usati[trovato] = true
		out.append(trovato)
	return out

func puo_costruire_oggetto(i: int, r: String) -> bool:
	var ric: Dictionary = Dati.RICETTE[r]
	var gg := g(i)
	var tolte := 0
	if ric.has("da"):
		if not (ric["da"] in gg["tessere"]):
			return false
		tolte += int(Dati.TESSERE[ric["da"]].get("spazi", 1))
	if ric.has("da2"):
		if not (ric["da2"] in gg["tessere"]):
			return false
		tolte += int(Dati.TESSERE[ric["da2"]].get("spazi", 1))
	if s["banco"].get(r, 0) <= 0:
		return false
	if r in gg["tessere"] and not (gg["pg"] == "norris" and ha_sblocco(i, "unico")):
		return false
	if Dati.TESSERE[r].get("cappotto", false):
		for x in gg["tessere"]:
			if Dati.TESSERE[x].get("cappotto", false) and x != ric.get("da", ""):
				return false
	if spazi_usati(i) - tolte + int(Dati.TESSERE[r].get("spazi", 1)) > spazi_oggetti(i):
		return false
	return not carte_per_ricetta(i, r).is_empty() or _ricetta_vuota_ok(i, r)

func _ricetta_vuota_ok(i: int, r: String) -> bool:
	# tutte le voci coperte da Accendino/Blair (es. nessuna): non capita, ma per sicurezza
	return false

func _costruisci(i: int, r: String) -> void:
	var gg := g(i)
	var idx := carte_per_ricetta(i, r)
	var da_togliere := []
	for k in idx:
		if k == -2:
			gg["arm_usato"] = true
		elif k == -3:
			gg["xp"] -= 1
			_usa_riferimento("cassetta_attrezzi")
		else:
			da_togliere.append(k)
	da_togliere.sort()
	da_togliere.reverse()
	for k in da_togliere:
		_scarta(gg["mano"][k])
		gg["mano"].remove_at(k)
	var ric: Dictionary = Dati.RICETTE[r]
	for key in ["da", "da2"]:
		if ric.has(key):
			_togli_tessera(i, ric[key])
	_prendi_tessera(i, r)
	_log("%s costruisce: %s." % [nome(i), Dati.TESSERE[r]["nome"]])

func _prendi_tessera(i: int, t: String) -> void:
	if s["banco"].get(t, 0) <= 0:
		_log("Non ci sono più tessere %s." % Dati.TESSERE[t]["nome"])
		return
	if not puo_equipaggiare(i, t):
		_log("%s non ha spazio per %s." % [nome(i), Dati.TESSERE[t]["nome"]])
		return
	s["banco"][t] -= 1
	g(i)["tessere"].append(t)

func _togli_tessera(i: int, t: String) -> void:
	var k: int = g(i)["tessere"].find(t)
	if k >= 0:
		g(i)["tessere"].remove_at(k)
		if s["banco"].has(t):
			s["banco"][t] += 1

# ============================================================ applica una decisione

func applica(dec: Dictionary) -> bool:
	var r := richiesta()
	if r.is_empty():
		return false
	var scelta = null
	for o in r["opz"]:
		if str(o["id"]) == str(dec.get("id", "")):
			scelta = o
			break
	if scelta == null:
		push_warning("decisione non valida: %s per %s" % [dec, r["k"]])
		return false
	s["coda"].pop_front()
	s["passo"] += 1
	var i: int = r["g"]
	call("_dec_" + r["k"], i, scelta, r)
	_controlla_morti()
	avanza()
	return true

func _dec_partenza(i: int, o: Dictionary, _r: Dictionary) -> void:
	g(i)["pos"] = o["id"]
	_log("%s parte da: %s." % [nome(i), Dati.NOMI_SPAZI[o["id"]]])

func _dec_sesto_senso(i: int, o: Dictionary, _r: Dictionary) -> void:
	if o["id"] == "si":
		var k := indice_mano(i, "sesto_senso")
		_scarta(g(i)["mano"][k])
		g(i)["mano"].remove_at(k)
		_log("%s usa Sesto senso: l'evento viene saltato." % nome(i))
		s["passi"].push_front("evento")

func _dec_letto(i: int, o: Dictionary, _r: Dictionary) -> void:
	if o["id"] == "solo":
		_dorme_solo(i)
		_sonno_prossimo()
		return
	var j: int = o["j"]
	s["coda"].push_front({"g": j, "k": "accetta_letto", "testo": "%s vuole dormire con te. Accetti?" % nome(i), "da": i,
		"opz": [{"id": "si", "testo": "Sì, dormiamo vicini"}, {"id": "no", "testo": "No, non mi fido"}]})

func _dec_accetta_letto(j: int, o: Dictionary, r: Dictionary) -> void:
	var i: int = r["da"]
	if o["id"] == "no":
		s["ctx"]["rifiuti_letto"]["%d_%d" % [i, j]] = true
		_log("%s rifiuta di dormire con %s." % [nome(j), nome(i)])
		s["eventi_pubblici"].append({"t": "rifiuto_letto", "a": j, "b": i, "turno": s["turno"]})
		_sonno_prossimo()
		return
	s["ctx"]["letti"][str(i)] = j
	s["ctx"]["letti"][str(j)] = i
	_log("%s e %s dormono vicini." % [nome(i), nome(j)])
	s["eventi_pubblici"].append({"t": "letto", "a": i, "b": j, "turno": s["turno"]})
	# segnalatori di infezione: chi ha carte Vulnerabili lo mostra all'altro
	var dopo := []
	if g(i)["vuln"].size() > 0:
		dopo.append([i, j])
	if g(j)["vuln"].size() > 0:
		dopo.append([j, i])
	s["ctx"]["dopo_letto"] = true
	for p in dopo:
		_mostra_segnalatore(p[0], p[1], "letto")
	if s["coda"].is_empty():
		_sonno_prossimo()

## a mostra il suo segnalatore a b. Se a è infetto sceglie cosa mostrare.
func _mostra_segnalatore(a: int, b: int, motivo: String) -> void:
	if g(a)["infetto"] and g(a)["vuln"].size() > 0:
		s["coda"].push_front({"g": a, "k": "segnalatore", "testo": "Mostri il segnalatore a %s: cosa fai vedere?" % nome(b), "b": b, "motivo": motivo,
			"opz": [{"id": "pulito", "testo": "PULITO (resti nascosto)"}, {"id": "infetto", "testo": "INFETTO (contagi %s)" % nome(b)}]})
	else:
		_vede(b, a, "pulito")

func _dec_segnalatore(a: int, o: Dictionary, r: Dictionary) -> void:
	var b: int = r["b"]
	_vede(b, a, o["id"])
	if r.get("motivo", "") == "letto" and s["coda"].is_empty() and s["stadio"] == "preturno":
		_sonno_prossimo()

## b vede il segnalatore di a.
func _vede(b: int, a: int, cosa: String) -> void:
	if cosa == "infetto":
		g(b)["sa"][str(a)] = {"v": "infetto", "turno": s["turno"]}
		if not g(b)["infetto"]:
			g(b)["infetto"] = true
			s["ctx"]["contagi"] = s["ctx"].get("contagi", 0) + 1
		# chi è contagiato sa che anche l'altro è della Cosa
		g(a)["sa"][str(b)] = {"v": "infetto", "turno": s["turno"]}
	else:
		g(b)["sa"][str(a)] = {"v": "pulito", "turno": s["turno"]}
	if not s.has("visti"):
		s["visti"] = []
	s["visti"].append({"chi": b, "di": a, "turno": s["turno"]})

func _dec_pesca_interna(i: int, o: Dictionary, _r: Dictionary) -> void:
	_pesca_mano(i, o["id"])
	_dopo_sotto(i)

func _dec_scarta(i: int, o: Dictionary, _r: Dictionary) -> void:
	var k: int = o["k"]
	_scarta(g(i)["mano"][k])
	g(i)["mano"].remove_at(k)
	_dopo_sotto(i)

func _dec_ombre(i: int, o: Dictionary, r: Dictionary) -> void:
	# opzioni generate al momento: se la richiesta era vuota la completiamo qui
	var mano: Array = g(i)["mano"]
	if mano.is_empty() or not o.has("k"):
		return
	var k: int = o["k"]
	var c = mano[k]
	mano.remove_at(k)
	var j := _successivo(i)
	g(j)["mano"].append(c)

# ---------- il turno

func _dec_turno(i: int, o: Dictionary, _r: Dictionary) -> void:
	var gg := g(i)
	var id: String = o["id"]
	var parti := id.split(":")
	var az := parti[0]
	var continua := true
	match az:
		"evento":
			continua = false
			_affronta_evento(i)
		"muovi", "muovi_racchette":
			var sp: String = o["sp"]
			if az == "muovi":
				gg["azioni"] -= costo_muovere(i)
			else:
				gg["arm_usato"] = true
			if Dati.dentro(sp) != dentro(i):
				gg["lasciato"] = luogo(i)
				gg["cambiato"] = true
			gg["pos"] = sp
			_log("%s va: %s." % [nome(i), Dati.NOMI_SPAZI[sp]])
		"cerca":
			gg["azioni"] -= costo_cercare(i)
			var m: String = parti[1]
			if m.begins_with("fase"):
				gg["xp"] += 2
				continua = _cerca_fuori(i, m)
			else:
				if _pesca_mano(i, m):
					_log("%s cerca nel %s." % [nome(i), "mazzo Specialità" if m.begins_with("spec") else Dati.NOMI_SPAZI[m]])
		"costruisci":
			gg["azioni"] -= 1
			_costruisci(i, parti[1])
		"stamina":
			gg["azioni"] -= 1
			var ok := dado()
			if not ok and _reroll_stamina_xp(i):
				ok = dado()
			if ok:
				_guadagna_stamina(i, 1)
				_log("%s si scalda: +1 Stamina." % nome(i))
			else:
				_log("%s non riesce a scaldarsi." % nome(i))
		"xp":
			gg["azioni"] -= 1
			var ok2 := dado()
			if not ok2 and _reroll_stamina_xp(i):
				ok2 = dado()
			if not ok2 and _reroll_hotspot(i):
				ok2 = dado()
			if ok2:
				gg["xp"] += 1
				_log("%s esplora: +1 XP." % nome(i))
		"ripara":
			gg["azioni"] -= 2
			_ripara(i)
		"ripara_tiro":
			gg["azioni"] -= 1
			var ok3 := dado()
			if not ok3 and ("hatchet" in gg["tessere"] or "pocket_knife" in gg["tessere"]):
				ok3 = dado()
			if ok3:
				_ripara(i)
			else:
				_log("%s prova a riparare, senza successo." % nome(i))
		"fiaschetta":
			gg["flask"] = true
			if dado():
				_guadagna_stamina(i, 1)
				_log("%s beve dalla fiaschetta: +1 Stamina." % nome(i))
		"scienziato":
			gg["scienziato"] = true
			gg["xp"] -= 1
			gg["azioni"] += 1
		"gioca":
			continua = _gioca_carta(i, int(parti[1]))
		"falo":
			var k := int(parti[1])
			var c: Dictionary = gg["mano"][k]
			gg["mano"].remove_at(k)
			s["falo"].append(c)
			_log("%s mette una carta nel Falò (%d)." % [nome(i), s["falo"].size()])
		"accendi":
			_accendi_falo(i)
		"armadietto":
			_usa_armadietto(i)
		"sblocca":
			_sblocca(i, parti[1])
		"dai":
			continua = false
			_scambio(i, int(parti[1]), int(parti[2]), i)
		"serve":
			var lb: Array = s["bisogni"].get(str(i), [])
			lb.append(parti[1])
			s["bisogni"][str(i)] = lb
			_log("%s: \"Mi serve: %s.\"" % [nome(i), Dati.nome_carta(parti[1])])
		"nonserve":
			var lb2: Array = s["bisogni"].get(str(i), [])
			lb2.erase(parti[1])
			s["bisogni"][str(i)] = lb2
		"chiedi":
			continua = false
			var j := int(parti[1])
			s["coda"].push_front({"g": j, "k": "chiesta", "testo": "%s ti chiede: %s. Gliela dai?" % [nome(i), Dati.nome_carta(parti[2])],
				"da": i, "tipo": parti[2], "opz": _opz_chiesta(j, parti[2])})
		"assalto":
			gg["azioni"] -= 5
			_assalto(i, int(parti[1]))
		"infezione":
			gg["azioni"] -= 5
			continua = false
			_attacco_infezione(i, int(parti[1]))
		"scarta_tessera":
			var t: String = gg["tessere"][int(parti[1])]
			_togli_tessera(i, t)
			if t.begins_with("companion"):
				gg["jack"] = ""
		"scarta":
			var k2 := int(parti[1])
			_scarta(gg["mano"][k2])
			gg["mano"].remove_at(k2)
		"rif_dispensa":
			gg["xp"] -= 1
			_usa_riferimento("dispensa")
			continua = false
			s["coda"].push_front({"g": i, "k": "pesca_interna", "testo": "Dispensa: da quale mazzo peschi?", "opz": _opz_mazzi_interni(i)})
			s["ctx"]["torna_turno"] = i
		"rif_medica":
			gg["xp"] -= 5
			_usa_riferimento("stazione_medica")
			_cura(i)
		"rif_offro":
			var k3 := indice_mano(i, "alcol")
			_scarta(gg["mano"][k3])
			gg["mano"].remove_at(k3)
			_usa_riferimento("offro_io")
			for j in vivi():
				if luogo(j) == luogo(i):
					_guadagna_stamina(j, 1)
			_log("%s offre da bere: +1 Stamina a tutti nel luogo." % nome(i))
		"fine":
			_fine_turno(i)
			return
	if continua and not gg["morto"]:
		_chiedi_turno(i)
	elif continua and gg["morto"]:
		pass
	elif s["coda"].is_empty():
		_torna_al_turno(i)

## Dopo una sequenza di richieste (tiri, scambi...) si ripropone il turno al giocatore corrente.
func _torna_al_turno(i: int) -> void:
	var c := corrente()
	if c >= 0 and not g(c)["morto"] and s["stadio"] == "giro":
		_chiedi_turno(c)

func _opz_chiesta(j: int, tipo: String) -> Array:
	var out := []
	var k := indice_mano(j, tipo)
	if k >= 0:
		out.append({"id": "si", "testo": "Sì, gliela do", "k": k})
	out.append({"id": "no", "testo": "No" if k >= 0 else "Non ce l'ho"})
	return out

func _dec_chiesta(j: int, o: Dictionary, r: Dictionary) -> void:
	var i: int = r["da"]
	if o["id"] == "si":
		_scambio(j, i, int(o["k"]), i)
	else:
		g(i)["rifiuti"]["%d_%s" % [j, r["tipo"]]] = true
		_log("%s non dà %s a %s." % [nome(j), Dati.nome_carta(r["tipo"]), nome(i)])
		_torna_al_turno(i)

## da dà la carta k a a. Chi riceve spende 1 Azione. Se chi dà ha carte Vulnerabili passa il segnalatore.
func _scambio(da: int, a: int, k: int, chi_turno: int) -> void:
	var c: Dictionary = g(da)["mano"][k]
	g(da)["mano"].remove_at(k)
	g(a)["mano"].append(c)
	# chi aveva annunciato di averne bisogno non lo cerca più
	var lb: Array = s["bisogni"].get(str(a), [])
	if c["t"] in lb:
		lb.erase(c["t"])
	if _trattativa_aperta(da, a):
		_log("%s dà un'altra carta a %s." % [nome(da), nome(a)])
		_torna_al_turno(chi_turno)
		return
	s["trattative"]["%d_%d" % [da, a]] = true
	g(a)["azioni"] = max(0, g(a)["azioni"] - 1)
	_log("%s dà una carta a %s." % [nome(da), nome(a)])
	s["eventi_pubblici"].append({"t": "scambio", "a": da, "b": a, "turno": s["turno"], "vuln": g(da)["vuln"].size()})
	if g(da)["vuln"].size() > 0:
		s["ctx"]["scambio"] = {"da": da, "a": a, "turno_di": chi_turno}
		# prima chi dà regola il segnalatore (in segreto), poi chi riceve prova a evitarlo
		if g(da)["infetto"]:
			s["coda"].push_front({"g": da, "k": "segnalatore_scambio", "testo": "Passi il segnalatore a %s: cosa mostri?" % nome(a),
				"opz": [{"id": "pulito", "testo": "PULITO (resti nascosto)"}, {"id": "infetto", "testo": "INFETTO (contagi %s)" % nome(a)}]})
		else:
			s["ctx"]["scambio"]["mostra"] = "pulito"
			_chiedi_evita(a)
	else:
		_torna_al_turno(chi_turno)

func _dec_segnalatore_scambio(_da: int, o: Dictionary, _r: Dictionary) -> void:
	s["ctx"]["scambio"]["mostra"] = o["id"]
	_chiedi_evita(s["ctx"]["scambio"]["a"])

func _chiedi_evita(a: int) -> void:
	var da: int = s["ctx"]["scambio"]["da"]
	var opz := [{"id": "accetta", "testo": "Prendi il segnalatore di %s e guardalo" % nome(da)}]
	if g(a)["azioni"] >= 1:
		opz.push_front({"id": "tira", "testo": "Spendi 1 Azione e tira: Successo = non prendi il segnalatore"})
	s["coda"].push_front({"g": a, "k": "evita", "testo": "%s ha carte Vulnerabili: con la carta arriva il suo segnalatore." % nome(da), "opz": opz})

func _dec_evita(a: int, o: Dictionary, _r: Dictionary) -> void:
	var sc: Dictionary = s["ctx"]["scambio"]
	if o["id"] == "tira":
		g(a)["azioni"] -= 1
		if dado():
			_log("%s evita il segnalatore di %s." % [nome(a), nome(sc["da"])])
			_torna_al_turno(sc["turno_di"])
			return
		_log("%s tira: Mancato." % nome(a))
		_chiedi_evita(a)
		return
	_vede(a, sc["da"], sc["mostra"])
	_log("%s guarda il segnalatore di %s." % [nome(a), nome(sc["da"])])
	_torna_al_turno(sc["turno_di"])

func _fine_turno(i: int) -> void:
	var gg := g(i)
	if evento_mi_riguarda(i) and not gg["ev_fatto"]:
		# chi dimentica l'evento ne subisce la penalità
		_log("%s non ha affrontato l'evento: ne subisce la penalità." % nome(i))
		gg["ev_fatto"] = true
		_esegui(i, _penalita_evento(s["evento"]["t"]), true)
	if gg["mano"].size() > max_mano(i):
		s["coda"].push_front({"g": i, "k": "troppe", "testo": "Hai più di %d carte: scegline una da scartare (o metterla nel Falò)." % max_mano(i), "opz": _opz_troppe(i)})
		return
	# ferite critiche non curate entro la fine del turno successivo
	if gg["critiche"] > 0:
		if gg.get("critiche_turno", -1) < s["turno"]:
			_log("%s non ha curato la Ferita critica: 1 Ferita in più." % nome(i))
			_ferita(i)
	gg["giocato"] = true
	_controlla_morti()
	s["stadio"] = "giro"

func _opz_troppe(i: int) -> Array:
	var out := []
	for k in g(i)["mano"].size():
		var c: Dictionary = g(i)["mano"][k]
		out.append({"id": "s%d" % k, "testo": "Scarta: " + Dati.nome_carta(c["t"]), "k": k})
		if dentro(i):
			out.append({"id": "f%d" % k, "testo": "Nel Falò: " + Dati.nome_carta(c["t"]), "k": k, "falo": true})
	return out

func _dec_troppe(i: int, o: Dictionary, _r: Dictionary) -> void:
	var c: Dictionary = g(i)["mano"][o["k"]]
	g(i)["mano"].remove_at(o["k"])
	if o.get("falo", false):
		s["falo"].append(c)
	else:
		_scarta(c)
	_fine_turno(i)

# ---------- effetti

func _guadagna_stamina(i: int, n: int) -> void:
	var gg := g(i)
	gg["stamina"] = min(gg["stamina_max"], gg["stamina"] + n)

func _ferita(i: int, critica := false) -> void:
	var gg := g(i)
	if gg["morto"]:
		return
	# Giubbotto antiproiettile: evita 1 Ferita
	var kj: int = gg["tavolo"].find("giubbotto")
	if kj >= 0:
		gg["tavolo"].remove_at(kj)
		_log("Il giubbotto di %s para il colpo." % nome(i))
		return
	if critica and not (gg["pg"] == "copper" and ha_sblocco(i, "unico")):
		gg["critiche"] += 1
		gg["critiche_turno"] = s["turno"]
		_log("%s riceve una Ferita CRITICA." % nome(i))
	else:
		gg["ferite"] += 1
		_log("%s riceve 1 Ferita." % nome(i))
	if gg["ferite"] + gg["critiche"] >= 3:
		_muore(i)

func _muore(i: int) -> void:
	var gg := g(i)
	if gg["morto"]:
		return
	gg["morto"] = true
	_log("%s è MORTO." % nome(i))
	for t in gg["tessere"]:
		if s["banco"].has(t):
			s["banco"][t] += 1
	gg["tessere"] = []
	for c in gg["mano"]:
		_scarta(c)
	gg["mano"] = []
	gg["tavolo"] = []
	if s["capo"] == i:
		for j in s["ordine"]:
			if not g(j)["morto"]:
				s["capo"] = j
				_log("Il nuovo capo è %s." % nome(j))
				break

func _controlla_morti() -> void:
	if vivi().is_empty() and s["stadio"] != "fine":
		_fine_tutti_morti()

func _fine_tutti_morti() -> void:
	s["coda"] = []
	s["stadio"] = "fine"
	s["esito"] = {"vince": "nessuno", "testo": "Nessuno è sopravvissuto all'inverno antartico."}
	_log(s["esito"]["testo"])

func _cura(i: int) -> void:
	var gg := g(i)
	if gg["critiche"] > 0:
		gg["critiche"] -= 1
	elif gg["ferite"] > 0:
		gg["ferite"] -= 1
	_log("%s si cura: -1 Ferita." % nome(i))

func _vulnerabile(i: int, attacco_cosa := false) -> void:
	var c = _carta_da_mazzo("vulnerabili")
	if c == null:
		if not attacco_cosa:
			_log("Non ci sono più carte Vulnerabili: %s riceve 1 Ferita." % nome(i))
			_ferita(i)
		return
	var cont: bool = c["t"] == "vuln_contaminata"
	g(i)["vuln"].append(cont)
	s["n_vuln_pubbliche"][str(i)] = g(i)["vuln"].size()
	_log("%s pesca una carta Vulnerabile (ne ha %d)." % [nome(i), g(i)["vuln"].size()])
	if cont:
		g(i)["infetto"] = true
		g(i)["ospite"] = true

func _danno_caldaia(n: int) -> void:
	for k in n:
		s["caldaia"] += 1
		if s["caldaia"] == 3:
			_log("La CALDAIA ESPLODE! Tutti quelli dentro ricevono 1 Ferita.")
			for i in vivi():
				if dentro(i):
					_ferita(i)
	_log("Caldaia: %d Danni." % s["caldaia"])

func _danno_porta(n: int) -> void:
	for k in n:
		s["porta"] += 1
		if s["porta"] == 3:
			_log("La PORTA SI ROMPE! Tutti quelli dentro sono vulnerabili e ora soffrono il freddo.")
			for i in vivi():
				if dentro(i):
					_vulnerabile(i)
	_log("Porta del campo: %d Danni." % s["porta"])

func _ripara(i: int) -> void:
	if dentro(i):
		s["caldaia"] = max(0, s["caldaia"] - 1)
		_log("%s ripara la Caldaia (%d Danni)." % [nome(i), s["caldaia"]])
	else:
		s["porta"] = max(0, s["porta"] - 1)
		_log("%s ripara la Porta (%d Danni)." % [nome(i), s["porta"]])

func _reroll_stamina_xp(i: int) -> bool:
	return "scarf" in g(i)["tessere"] or "lantern" in g(i)["tessere"]

func _reroll_hotspot(i: int) -> bool:
	if "hot_spot" in g(i)["tessere"] and not g(i)["hotspot"] and not dentro(i):
		g(i)["hotspot"] = true
		return true
	return false

func _esegui(i: int, effs: Array, auto := false) -> void:
	for e in effs:
		match e["e"]:
			"ferita":
				_ferita(i)
			"critica":
				_ferita(i, true)
			"vuln":
				_vulnerabile(i)
			"caldaia":
				_danno_caldaia(int(e["n"]))
			"ferita_o_xp":
				if auto and g(i)["xp"] >= 2:
					g(i)["xp"] -= 2
				elif g(i)["xp"] >= 2:
					s["coda"].push_front({"g": i, "k": "ferita_o_xp", "testo": "Fallimento: cosa perdi?", "opz": [
						{"id": "xp", "testo": "Perdi 2 XP"}, {"id": "ferita", "testo": "Ricevi 1 Ferita"}]})
				else:
					_ferita(i)
			"cibo_o_vuln":
				var k := indice_mano(i, "scatoletta")
				if k < 0:
					k = indice_mano(i, "scatoletta2")
				if k >= 0 and auto:
					_scarta(g(i)["mano"][k])
					g(i)["mano"].remove_at(k)
				elif k >= 0:
					s["coda"].push_front({"g": i, "k": "cibo_o_vuln", "testo": "Morsi della fame: giochi una Scatoletta o peschi una Vulnerabile?", "opz": [
						{"id": "cibo", "testo": "Gioca una Scatoletta", "k": k}, {"id": "vuln", "testo": "Pesca una carta Vulnerabile"}]})
				else:
					_vulnerabile(i)

func _dec_ferita_o_xp(i: int, o: Dictionary, _r: Dictionary) -> void:
	if o["id"] == "xp":
		g(i)["xp"] -= 2
		_log("%s perde 2 XP." % nome(i))
	else:
		_ferita(i)
	_dopo_sotto(i)

func _dec_cibo_o_vuln(i: int, o: Dictionary, _r: Dictionary) -> void:
	if o["id"] == "cibo":
		_scarta(g(i)["mano"][o["k"]])
		g(i)["mano"].remove_at(o["k"])
	else:
		_vulnerabile(i)
	_dopo_sotto(i)

## Fine di una sotto-richiesta durante il turno: si torna al turno se non c'è altro in coda.
func _dopo_sotto(i: int) -> void:
	if s["coda"].is_empty() and s["stadio"] == "giro":
		_torna_al_turno(i)

func _penalita_evento(t: String) -> Array:
	match t:
		"ev_incendio_caldaia": return [{"e": "caldaia", "n": 2}]
		"ev_incendio": return [{"e": "ferita"}]
		"ev_pazzo": return [{"e": "ferita"}, {"e": "caldaia", "n": 1}]
		"ev_filo_spinato": return [{"e": "critica"}]
		"ev_fame": return [{"e": "cibo_o_vuln"}]
		"ev_cane": return [{"e": "ferita"}]
		"ev_cane_rabbioso": return [{"e": "critica"}]
		"ev_valanga": return [{"e": "ferita_o_xp"}]
		"ev_cosa": return [{"e": "ferita"}, {"e": "vuln"}]
		"ev_blackout": return [{"e": "ferita_o_xp"}]
	return []

# ---------- prove con i dadi

func dadi_per(i: int, colore: String) -> int:
	var n := dadi_naturali(i)
	for t in g(i)["tessere"]:
		n += int(Dati.TESSERE[t]["r" if colore == "attacco" else "b"])
	return n

func _affronta_evento(i: int) -> void:
	g(i)["ev_fatto"] = true
	var t: String = s["evento"]["t"]
	var col: String = Dati.EVENTI[t]["tipo"]
	_prova(i, col, successi_richiesti(), "evento", _penalita_evento(t), Dati.nome_carta(t))

## Prova: tira i dadi; se non bastano si possono usare carte e oggetti (richiesta "potenzia").
func _prova(i: int, colore: String, richiesti: int, motivo: String, penalita: Array, titolo: String) -> void:
	var n := dadi_per(i, colore)
	var esiti := []
	for k in n:
		esiti.append(dado())
	var p := {"g": i, "colore": colore, "richiesti": richiesti, "motivo": motivo, "pen": penalita, "esiti": esiti,
		"extra": 0, "titolo": titolo, "usati": {}}
	s["ctx"]["prova"] = p
	_log("%s affronta %s: %d dad%s, %d Successi (ne servono %d)." % [nome(i), titolo, n, "o" if n == 1 else "i", _succ(p), richiesti])
	_dopo_tiro()

func _succ(p: Dictionary) -> int:
	var n: int = p["extra"]
	for e in p["esiti"]:
		if e:
			n += 1
	return n

func _dopo_tiro() -> void:
	var p: Dictionary = s["ctx"]["prova"]
	var i: int = p["g"]
	if _succ(p) >= p["richiesti"]:
		_log("Superato!")
		_chiudi_prova(true)
		return
	var opz := _opz_potenzia(i, p)
	if opz.is_empty():
		_log("Fallito.")
		_chiudi_prova(false)
		return
	opz.append({"id": "accetta", "testo": "Accetta il fallimento"})
	s["coda"].push_front({"g": i, "k": "potenzia", "testo": "%s: %d Successi su %d. Vuoi aiutarti?" % [p["titolo"], _succ(p), p["richiesti"]], "opz": opz})

func _ha_mancati(p: Dictionary) -> bool:
	return false in p["esiti"]

func _opz_potenzia(i: int, p: Dictionary) -> Array:
	var gg := g(i)
	var out := []
	var att: bool = p["colore"] == "attacco"
	var u: Dictionary = p["usati"]
	for k in gg["mano"].size():
		var t: String = gg["mano"][k]["t"]
		var nm := Dati.nome_carta(t)
		match t:
			"colpo_in_canna", "fucile":
				if att:
					out.append({"id": "c%d" % k, "testo": "%s: +%d dadi" % [nm, 2 if t == "colpo_in_canna" else 3], "k": k})
			"proiettile":
				if att and gg["pg"] == "garry" and ha_sblocco(i, "unico"):
					out.append({"id": "c%d" % k, "testo": "Proiettile: +2 dadi", "k": k})
			"molotov":
				if att:
					out.append({"id": "c%d" % k, "testo": "Molotov: +1 Successo", "k": k})
			"salvatore_att", "salvatore_ost", "salvatore_any":
				if p["motivo"] == "evento" and (t == "salvatore_any" or (t == "salvatore_att") == att):
					out.append({"id": "c%d" % k, "testo": "Salvatore: +1 Successo", "k": k})
			"razzo":
				if _ha_mancati(p):
					out.append({"id": "c%d" % k, "testo": "Razzo: 1 Mancato diventa Successo", "k": k})
	for k in gg["tavolo"].size():
		var t2: String = gg["tavolo"][k]
		if t2 == "termite" and att:
			out.append({"id": "t%d" % k, "testo": "Termite: +2 Successi", "k": k})
		if t2 == "coltelli_lancio" and att:
			out.append({"id": "t%d" % k, "testo": "Coltelli da lancio: +1 dado", "k": k})
	if ha_sblocco(i, "armadietto") and not gg["arm_usato"]:
		var f: String = gg["armadietto"]
		if f == "razzo" and _ha_mancati(p):
			out.append({"id": "arm", "testo": "Dado armadietto: Razzo, 1 Mancato diventa Successo"})
		elif f == "unico" and Dati.PG[gg["pg"]]["armadietto"] == "proiettili" and att and ha_sblocco(i, "unico"):
			out.append({"id": "arm", "testo": "Dado armadietto: Proiettili, +2 dadi"})
		elif f == "unico" and Dati.PG[gg["pg"]]["armadietto"] == "tirapugni" and att and _ha_mancati(p):
			out.append({"id": "arm", "testo": "Dado armadietto: Tirapugni, ritira 1 dado"})
	if att and p["motivo"] == "evento" and "shield" in gg["tessere"] and not u.has("shield") and _ha_mancati(p):
		out.append({"id": "shield", "testo": "Scudo: ritira 1 dado mancato"})
	if not dentro(i) and "hot_spot" in gg["tessere"] and not gg["hotspot"] and _ha_mancati(p):
		out.append({"id": "hotspot", "testo": "Scaldino: ritira 1 dado mancato"})
	return out

func _ritira_un_mancato(p: Dictionary) -> void:
	var k: int = p["esiti"].find(false)
	if k >= 0:
		p["esiti"][k] = dado()

func _dec_potenzia(i: int, o: Dictionary, _r: Dictionary) -> void:
	var p: Dictionary = s["ctx"]["prova"]
	var gg := g(i)
	var id: String = o["id"]
	if id == "accetta":
		_log("Fallito.")
		_chiudi_prova(false)
		return
	if id.begins_with("c"):
		var k: int = o["k"]
		var t: String = gg["mano"][k]["t"]
		_scarta(gg["mano"][k])
		gg["mano"].remove_at(k)
		match t:
			"colpo_in_canna", "proiettile":
				p["esiti"].append(dado())
				p["esiti"].append(dado())
			"fucile":
				for q in 3:
					p["esiti"].append(dado())
			"molotov", "salvatore_att", "salvatore_ost", "salvatore_any":
				p["extra"] += 1
			"razzo":
				p["esiti"][p["esiti"].find(false)] = true
		_log("%s gioca %s." % [nome(i), Dati.nome_carta(t)])
	elif id.begins_with("t"):
		var k2: int = o["k"]
		var t2: String = gg["tavolo"][k2]
		gg["tavolo"].remove_at(k2)
		if t2 == "termite":
			p["extra"] += 2
		else:
			p["esiti"].append(dado())
		_log("%s usa %s." % [nome(i), Dati.nome_carta(t2)])
	elif id == "arm":
		gg["arm_usato"] = true
		var f: String = gg["armadietto"]
		if f == "razzo":
			p["esiti"][p["esiti"].find(false)] = true
		elif Dati.PG[gg["pg"]]["armadietto"] == "proiettili":
			p["esiti"].append(dado())
			p["esiti"].append(dado())
		else:
			_ritira_un_mancato(p)
	elif id == "shield":
		p["usati"]["shield"] = true
		_ritira_un_mancato(p)
	elif id == "hotspot":
		gg["hotspot"] = true
		_ritira_un_mancato(p)
	_dopo_tiro()

func _chiudi_prova(ok: bool) -> void:
	var p: Dictionary = s["ctx"]["prova"]
	var i: int = p["g"]
	s["ctx"].erase("prova")
	if not ok:
		_esegui(i, p["pen"])
	if p["motivo"] == "cosa" and not ok:
		pass
	_dopo_sotto(i)

# ---------- cercare fuori (carte Fase)

func _cerca_fuori(i: int, m: String) -> bool:
	var c = _carta_da_mazzo(m)
	if c == null:
		_log("Il mazzo %s è finito." % Dati.NOMI_SPAZI[m])
		return true
	s["scarti_fase"].append(c)
	s["ultima_fase"] = {"g": i, "c": c}
	var t: String = c["t"]
	_log("%s cerca fuori (+2 XP) e trova: %s." % [nome(i), Dati.nome_carta(t)])
	var gg := g(i)
	match t:
		"danno_porta":
			_danno_porta(1)
		"cosa_attacca":
			s["eventi_pubblici"].append({"t": "cosa_fuori", "a": i, "turno": s["turno"]})
			_prova(i, "attacco", successi_richiesti(), "cosa", [{"e": "ferita"}, {"e": "vuln"}], "La Cosa")
			return false
		"mappe", "taniche", "dati_ricerca", "manuale_elicottero", "coltelli_lancio", "giubbotto", "termite":
			s["scarti_fase"].pop_back()
			gg["tavolo"].append(t)
		"forziere_torcia", "forziere_sciarpa", "forziere_borsa", "forziere_stamina", "forziere_lanciafiamme", "forziere_xp", "forziere_specialita":
			var xp := 3 if t == "forziere_stamina" else 2
			s["coda"].push_front({"g": i, "k": "forziere", "testo": "%s: prendi %d XP o tenti la sorte?" % [Dati.nome_carta(t), xp], "tipo": t, "opz": [
				{"id": "xp", "testo": "Prendi %d XP" % xp}, {"id": "tira", "testo": "Tira 1 dado: %s" % Dati.testo_carta(t).split("Successo = ")[1]}]})
			return false
		"coltello_fase", "accendino_fase", "guida_fase", "lanterna_fase", "cappotto_fase":
			var tess: String = {"coltello_fase": "knife", "accendino_fase": "lighter", "guida_fase": "guideline", "lanterna_fase": "lantern"}.get(t, "")
			var xp2 := 1 if t == "accendino_fase" else 2
			var opz := [{"id": "xp", "testo": "Prendi %d XP" % xp2}]
			if t == "cappotto_fase":
				for cc in ["scarf", "travel_coat", "mechanic_coat"]:
					if puo_equipaggiare(i, cc):
						opz.append({"id": cc, "testo": "Prendi la tessera " + Dati.TESSERE[cc]["nome"]})
			elif puo_equipaggiare(i, tess):
				opz.append({"id": tess, "testo": "Prendi la tessera " + Dati.TESSERE[tess]["nome"]})
			s["coda"].push_front({"g": i, "k": "scelta_tessera", "testo": Dati.nome_carta(t), "xp": xp2, "opz": opz})
			return false
		"scelta_interne", "scelta_specialita":
			s["coda"].push_front({"g": i, "k": "scelta_carte", "testo": Dati.nome_carta(t), "tipo": t, "opz": [
				{"id": "xp", "testo": "Prendi 3 XP"}, {"id": "carte", "testo": "Pesca 1 carta da ogni mazzo interno" if t == "scelta_interne" else "Pesca 2 carte dal tuo mazzo Specialità"}]})
			return false
	return true

func _dec_forziere(i: int, o: Dictionary, r: Dictionary) -> void:
	var t: String = r["tipo"]
	var gg := g(i)
	if o["id"] == "xp":
		gg["xp"] += 3 if t == "forziere_stamina" else 2
	else:
		var ok := dado()
		if not ok and "crowbar" in gg["tessere"]:
			ok = dado()
		if ok:
			_log("%s apre la cassetta!" % nome(i))
			match t:
				"forziere_torcia": _prendi_tessera(i, "torch")
				"forziere_sciarpa": _prendi_tessera(i, "scarf")
				"forziere_borsa": _prendi_tessera(i, "pouch")
				"forziere_lanciafiamme": _prendi_tessera(i, "flamethrower")
				"forziere_stamina": _guadagna_stamina(i, 4)
				"forziere_xp": gg["xp"] += 4
				"forziere_specialita":
					var opz := []
					var d: Array = s["mazzi"][mazzo_specialita(i)]
					var visti := {}
					for k in d.size():
						if not visti.has(d[k]["t"]):
							visti[d[k]["t"]] = true
							opz.append({"id": "k%d" % k, "testo": Dati.nome_carta(d[k]["t"]), "k": k})
					if not opz.is_empty():
						s["coda"].push_front({"g": i, "k": "prendi_specialita", "testo": "Scegli una carta dal tuo mazzo Specialità", "opz": opz})
						return
		else:
			_log("La cassetta resta chiusa.")
	_dopo_sotto(i)

func _dec_prendi_specialita(i: int, o: Dictionary, _r: Dictionary) -> void:
	var d: Array = s["mazzi"][mazzo_specialita(i)]
	g(i)["mano"].append(d[o["k"]])
	d.remove_at(o["k"])
	_dopo_sotto(i)

func _dec_scelta_tessera(i: int, o: Dictionary, r: Dictionary) -> void:
	if o["id"] == "xp":
		g(i)["xp"] += int(r["xp"])
	else:
		_prendi_tessera(i, o["id"])
	_dopo_sotto(i)

func _dec_scelta_carte(i: int, o: Dictionary, r: Dictionary) -> void:
	if o["id"] == "xp":
		g(i)["xp"] += 3
	elif r["tipo"] == "scelta_interne":
		_pesca_mano(i, "magazzino")
		_pesca_mano(i, "officina")
		_pesca_mano(i, mazzo_specialita(i))
	else:
		_pesca_mano(i, mazzo_specialita(i))
		_pesca_mano(i, mazzo_specialita(i))
	_dopo_sotto(i)

# ---------- carte giocate

func _gioca_carta(i: int, k: int) -> bool:
	var gg := g(i)
	var c: Dictionary = gg["mano"][k]
	var t: String = c["t"]
	gg["mano"].remove_at(k)
	var scarta := true
	var continua := true
	_log("%s gioca: %s." % [nome(i), Dati.nome_carta(t)])
	match t:
		"alcol", "snack", "scatoletta":
			_guadagna_stamina(i, 1)
		"scatoletta2":
			_guadagna_stamina(i, 2)
		"pronto_soccorso":
			_cura(i)
		"dex":
			gg["azioni"] += 1
		"boost_stamina":
			_guadagna_stamina(i, 3 if dado() else 2)
		"carta_piede_porco": _prendi_tessera(i, "crowbar")
		"carta_lanciarazzi": _prendi_tessera(i, "flare_gun")
		"carta_torcia": _prendi_tessera(i, "torch")
		"bisturi": _prendi_tessera(i, "knife")
		"lanciarazzi_kinner": _prendi_tessera(i, "flare_gun_kinner")
		"coltellino": _prendi_tessera(i, "pocket_knife")
		"guaritore":
			for j in vivi():
				if g(j)["pos"] == gg["pos"] and g(j)["ferite"] + g(j)["critiche"] > 0:
					_cura(j)
		"kit_riparazione":
			_ripara(i)
		"esame_sangue", "test_ospite":
			continua = false
			var opz := []
			for j in vivi():
				if j != i and stesso_luogo(i, j) and (t == "esame_sangue" or g(j)["vuln"].size() >= 1):
					opz.append({"id": "j%d" % j, "testo": nome(j), "j": j})
			s["coda"].push_front({"g": i, "k": "test", "testo": "Con chi fai il %s?" % Dati.nome_carta(t).to_lower(), "tipo": t, "opz": opz})
		"resistenza":
			for j in vivi():
				if not ha_sblocco(j, "cardio"):
					g(j)["sblocchi"]["cardio"] = true
					g(j)["stamina_max"] = 6
		"ingegno":
			for j in vivi():
				if ha_sblocco(j, "armadietto") and not g(j)["arm_usato"]:
					g(j)["armadietto"] = Dati.FACCE_ARMADIETTO[rng.randi_range(0, 5)]
		"riporto":
			for j in vivi():
				if ha_sblocco(j, "armadietto") and not g(j)["arm_usato"]:
					g(j)["armadietto"] = "razzo"
		"legnetti":
			s["falo"].append(c)
			scarta = false
		"dispensa", "offro_io", "stazione_medica", "cassetta_attrezzi", "banco_lavoro", "sella":
			var usi: int = {"dispensa": 3, "offro_io": 3, "stazione_medica": 1, "cassetta_attrezzi": 3}.get(t, 99)
			s["riferimenti"].append({"t": t, "usi": usi, "luogo": luogo(i), "di": i})
			scarta = false
		"manuale_addestramento":
			var kk: int = gg["tessere"].find("companion")
			if kk >= 0:
				gg["tessere"][kk] = "companion_trained"
				gg["jack"] = "companion_trained"
	if scarta:
		_scarta(c)
	return continua

func _usa_riferimento(t: String) -> void:
	for k in s["riferimenti"].size():
		var r: Dictionary = s["riferimenti"][k]
		if r["t"] == t:
			r["usi"] -= 1
			if r["usi"] <= 0:
				s["riferimenti"].remove_at(k)
				_log("%s è esaurito." % Dati.nome_carta(t))
			return

func _dec_test(i: int, o: Dictionary, r: Dictionary) -> void:
	var j: int = o["j"]
	var t: String = r["tipo"]
	s["eventi_pubblici"].append({"t": "test", "a": i, "b": j, "turno": s["turno"]})
	if t == "esame_sangue":
		g(i)["sa"][str(j)] = {"v": "infetto" if g(j)["infetto"] else "pulito", "turno": s["turno"], "certo": true}
		g(j)["sa"][str(i)] = {"v": "infetto" if g(i)["infetto"] else "pulito", "turno": s["turno"], "certo": true}
		_log("%s e %s si fanno l'esame del sangue, in segreto." % [nome(i), nome(j)])
	else:
		g(i)["sa"]["ospite_" + str(j)] = ha_contaminata(j)
		g(j)["sa"]["ospite_" + str(i)] = ha_contaminata(i)
		if ha_contaminata(j):
			g(i)["sa"][str(j)] = {"v": "infetto", "turno": s["turno"], "certo": true}
		if ha_contaminata(i):
			g(j)["sa"][str(i)] = {"v": "infetto", "turno": s["turno"], "certo": true}
		_log("%s e %s si mostrano le carte Vulnerabili, in segreto." % [nome(i), nome(j)])
	# chi ha fatto il test può dichiarare cosa ha visto
	s["coda"].push_front({"g": i, "k": "dichiara", "testo": "Cosa dici agli altri di %s?" % nome(j), "su": j, "opz": [
		{"id": "pulito", "testo": "\"%s è pulito\"" % nome(j)}, {"id": "infetto", "testo": "\"%s è INFETTO!\"" % nome(j)}, {"id": "zitto", "testo": "Non dico niente"}]})
	s["coda"].insert(1, {"g": j, "k": "dichiara", "testo": "Cosa dici agli altri di %s?" % nome(i), "su": i, "opz": [
		{"id": "pulito", "testo": "\"%s è pulito\"" % nome(i)}, {"id": "infetto", "testo": "\"%s è INFETTO!\"" % nome(i)}, {"id": "zitto", "testo": "Non dico niente"}]})

func _dec_dichiara(i: int, o: Dictionary, r: Dictionary) -> void:
	if o["id"] != "zitto":
		s["dichiarazioni"].append({"chi": i, "su": r["su"], "v": o["id"], "turno": s["turno"]})
		_log("%s dichiara: \"%s è %s\"." % [nome(i), nome(r["su"]), "PULITO" if o["id"] == "pulito" else "INFETTO"])
	_dopo_sotto(corrente() if corrente() >= 0 else i)

func _accendi_falo(i: int) -> void:
	var k := indice_mano(i, "fiammiferi")
	if not ("lighter" in g(i)["tessere"] or (g(i)["pg"] == "blair" and ha_sblocco(i, "unico"))) and k >= 0:
		_scarta(g(i)["mano"][k])
		g(i)["mano"].remove_at(k)
	var bonus := 2
	for c in s["falo"]:
		if c["t"] == "legnetti":
			bonus += 1
	for c in s["falo"]:
		_scarta(c)
	s["falo"] = []
	for j in vivi():
		if dentro(j):
			_guadagna_stamina(j, bonus)
	_log("%s accende il Falò: +%d Stamina a tutti quelli dentro." % [nome(i), bonus])

func _usa_armadietto(i: int) -> void:
	var gg := g(i)
	var f: String = gg["armadietto"]
	if f == "unico":
		f = Dati.PG[gg["pg"]]["armadietto"]
	gg["arm_usato"] = true
	match f:
		"xp2": gg["xp"] += 2
		"snack", "alcol": _guadagna_stamina(i, 1)
		"pronto_soccorso": _cura(i)
		"kit_riparazione": _ripara(i)
	_log("%s usa il dado armadietto." % nome(i))

func _sblocca(i: int, k: String) -> void:
	var gg := g(i)
	gg["xp"] -= int(Dati.SBLOCCHI[k]["xp"])
	gg["sblocchi"][k] = true
	match k:
		"cardio":
			gg["stamina_max"] = 6
		"agilita":
			gg["azioni_max"] = 6
			gg["azioni"] += 1
		"armadietto":
			gg["armadietto"] = "unico"
			gg["arm_usato"] = false
		"unico":
			if gg["pg"] == "clark":
				if puo_equipaggiare(i, "companion"):
					s["banco"]["companion"] -= 1
					gg["tessere"].append("companion")
					gg["jack"] = "companion"
	_log("%s sblocca: %s." % [nome(i), Dati.PG[gg["pg"]]["unico_nome"] if k == "unico" else Dati.SBLOCCHI[k]["nome"]])

# ---------- assalto e infezione

func _assalto(i: int, j: int) -> void:
	var n := dadi_per(i, "attacco")
	var succ := 0
	for k in n:
		if dado():
			succ += 1
	_log("%s ASSALTA %s: %d Successi su %d dadi." % [nome(i), nome(j), succ, n])
	s["eventi_pubblici"].append({"t": "assalto", "a": i, "b": j, "turno": s["turno"], "succ": succ})
	for k in succ:
		_ferita(j)

func _attacco_infezione(i: int, n: int) -> void:
	var bersagli := []
	for j in vivi():
		if j != i and stesso_luogo(i, j):
			bersagli.append(j)
	s["ctx"]["infezione"] = {"da": i, "n": n, "scelti": []}
	var opz := []
	for j in bersagli:
		opz.append({"id": "j%d" % j, "testo": nome(j), "j": j})
	s["coda"].push_front({"g": i, "k": "bersaglio_infezione", "testo": "Scegli il bersaglio dell'attacco (%d da scegliere)" % n, "opz": opz})

func _dec_bersaglio_infezione(i: int, o: Dictionary, r: Dictionary) -> void:
	var inf: Dictionary = s["ctx"]["infezione"]
	inf["scelti"].append(o["j"])
	if inf["scelti"].size() < inf["n"]:
		var opz := []
		for x in r["opz"]:
			if x["j"] != o["j"]:
				opz.append(x)
		s["coda"].push_front({"g": i, "k": "bersaglio_infezione", "testo": "Scegli un altro bersaglio (%d da scegliere)" % (inf["n"] - inf["scelti"].size()), "opz": opz})
		return
	# si mischiano la contaminata e una pulita per bersaglio; ognuno ne prende una, l'Ospite tiene l'ultima
	var gg := g(i)
	var mazzetto := [true]
	gg["vuln"].erase(true)
	for k in inf["n"]:
		gg["vuln"].erase(false)
		mazzetto.append(false)
	_mescola(mazzetto)
	_log("%s rivela la carta CONTAMINATA: ATTACCO D'INFEZIONE contro %s!" % [nome(i), ", ".join(inf["scelti"].map(func(x): return nome(x)))])
	gg["ospite"] = false
	for j in s["ordine"]:
		g(j)["sa"][str(i)] = {"v": "infetto", "turno": s["turno"], "certo": true}
	s["eventi_pubblici"].append({"t": "infezione", "a": i, "turno": s["turno"]})
	for j in inf["scelti"]:
		var cc: bool = mazzetto.pop_back()
		g(j)["vuln"].append(cc)
		s["n_vuln_pubbliche"][str(j)] = g(j)["vuln"].size()
		if cc:
			g(j)["infetto"] = true
			g(j)["ospite"] = true
	var ultima: bool = mazzetto.pop_back()
	gg["vuln"].append(ultima)
	if ultima:
		gg["ospite"] = true
	s["n_vuln_pubbliche"][str(i)] = gg["vuln"].size()
	s["ctx"].erase("infezione")
	_torna_al_turno(i)

# ============================================================ elicottero

func _elicottero_passo() -> void:
	var passi: Array = s["passi_eli"]
	if passi.is_empty():
		return
	var p: String = passi.pop_front()
	match p:
		"imbarco":
			var capo: int = s["capo"]
			if g(capo)["morto"]:
				if vivi().is_empty():
					_fine_tutti_morti()
					return
				capo = vivi()[0]
				s["capo"] = capo
			g(capo)["bordo"] = true
			_log("Il capo %s sale per primo sull'elicottero e decide chi sale." % nome(capo))
			for j in vivi():
				if j != capo:
					g(j)["bordo"] = true
			s["coda"].append({"g": capo, "k": "imbarco", "testo": "Chi lasci a terra? (tutti gli altri salgono)", "opz": _opz_imbarco(capo)})
		"scendere":
			for j in vivi():
				if j != s["capo"] and g(j)["bordo"]:
					s["coda"].append({"g": j, "k": "scendi", "testo": "Sei a bordo. Resti o scendi dall'elicottero?", "opz": [
						{"id": "resta", "testo": "Resto a bordo"}, {"id": "scendi", "testo": "Scendo: non mi fido di chi c'è a bordo"}]})
		"partenza":
			_partenza()

func _opz_imbarco(capo: int) -> Array:
	var opz := [{"id": "ok", "testo": "Si parte con chi è a bordo"}]
	for j in vivi():
		if j == capo:
			continue
		if g(j)["bordo"]:
			opz.append({"id": "giu:%d" % j, "testo": "Lascia a terra %s" % nome(j), "j": j})
		else:
			opz.append({"id": "su:%d" % j, "testo": "Fai salire %s" % nome(j), "j": j})
	opz.append({"id": "scendo", "testo": "Il capo scende: comanda il prossimo"})
	return opz

func _dec_imbarco(capo: int, o: Dictionary, _r: Dictionary) -> void:
	var id: String = o["id"]
	if id == "ok":
		s["passi_eli"] = ["scendere", "partenza"]
		return
	if id == "scendo":
		g(capo)["bordo"] = false
		_log("%s scende dall'elicottero." % nome(capo))
		var v := vivi()
		var k := v.find(capo)
		var nuovo := -1
		for q in range(1, v.size()):
			var c: int = v[(k + q) % v.size()]
			if g(c)["bordo"]:
				nuovo = c
				break
		if nuovo < 0:
			s["passi_eli"] = ["partenza"]
			return
		s["capo"] = nuovo
		_log("Ora comanda %s." % nome(nuovo))
		s["coda"].append({"g": nuovo, "k": "imbarco", "testo": "Ora comandi tu: chi lasci a terra?", "opz": _opz_imbarco(nuovo)})
		return
	var j: int = o["j"]
	g(j)["bordo"] = id.begins_with("su")
	_log("%s %s." % [nome(j), "sale a bordo" if g(j)["bordo"] else "viene lasciato a terra"])
	s["coda"].append({"g": capo, "k": "imbarco", "testo": "Chi lasci a terra?", "opz": _opz_imbarco(capo)})

func _dec_scendi(j: int, o: Dictionary, _r: Dictionary) -> void:
	if o["id"] == "scendi":
		g(j)["bordo"] = false
		_log("%s scende dall'elicottero." % nome(j))

func bonus_giocatore(i: int) -> int:
	var b := 0
	for t in g(i)["tavolo"]:
		b += {"mappe": 1, "taniche": 2, "dati_ricerca": 3}.get(t, 0)
	if ha_sblocco(i, "scorta_xp"):
		b += min(5, int(g(i)["xp"]) / 5)
	return b

func _partenza() -> void:
	var a_bordo := []
	for i in vivi():
		if g(i)["bordo"]:
			a_bordo.append(i)
	_log("Lo sportello si chiude. Tutti rivelano il proprio segnalatore...")
	var umani_bordo := a_bordo.filter(func(x): return not g(x)["infetto"])
	var infetti_bordo := a_bordo.filter(func(x): return g(x)["infetto"])
	var esito := {"a_bordo": a_bordo, "tiri": {}}
	if umani_veri().is_empty():
		esito["vince"] = "nessuno"
		esito["testo"] = "TROPPI CONTAGI: tutti sono stati assimilati e nessuno può guidare l'elicottero. Tutti perdono."
	elif umani_bordo.is_empty():
		var vivi_umani := vivi().filter(func(x): return not g(x)["infetto"])
		if vivi_umani.is_empty():
			esito["vince"] = "nessuno"
			esito["testo"] = "Nessun umano vivo può partire: la Cosa resta bloccata nel ghiaccio con tutti voi. Tutti perdono."
		else:
			_log("Errore d'imbarco: gli infetti devono scendere, salgono solo gli umani.")
			umani_bordo = vivi_umani
			infetti_bordo = []
			a_bordo = vivi_umani
			esito["a_bordo"] = a_bordo
	if not esito.has("vince"):
		var totale := 6 * umani_veri().size()
		var punti_umani := 0
		for i in umani_bordo:
			var t := rng.randi_range(1, 6)
			if "manuale_elicottero" in g(i)["tavolo"]:
				t = max(t, rng.randi_range(1, 6))
			esito["tiri"][str(i)] = t
			punti_umani += bonus_giocatore(i) + t
		var punti_cosa := 0
		for i in infetti_bordo:
			var t2 := rng.randi_range(1, 6)
			esito["tiri"][str(i)] = t2
			punti_cosa += bonus_giocatore(i) + t2
		totale += punti_cosa
		esito["totale"] = totale
		esito["umani"] = punti_umani
		esito["cosa"] = punti_cosa
		if infetti_bordo.is_empty():
			if punti_umani >= totale:
				esito["vince"] = "umani"
				esito["testo"] = "Tutti a bordo sono umani e l'elicottero attraversa la tempesta: %d punti su %d. GLI UMANI VINCONO." % [punti_umani, totale]
			else:
				esito["vince"] = "nessuno"
				esito["testo"] = "A bordo solo umani, ma l'elicottero sparisce nella tempesta (%d su %d). Tutti perdono." % [punti_umani, totale]
		else:
			if punti_umani >= totale:
				esito["vince"] = "umani"
				esito["testo"] = "In volo uno di voi si trasforma... ma lo gettate fuori con un razzo! %d su %d: GLI UMANI VINCONO." % [punti_umani, totale]
			else:
				esito["vince"] = "cosa"
				esito["testo"] = "In volo la Cosa si rivela e assimila l'equipaggio (%d su %d). LA COSA VINCE: l'umanità è perduta." % [punti_umani, totale]
	s["esito"] = esito
	s["stadio"] = "fine"
	s["coda"] = []
	_log(esito["testo"])

## Vale per chi gioca: ha vinto il giocatore i?
func ha_vinto(i: int) -> bool:
	var v: String = s["esito"].get("vince", "nessuno")
	if v == "umani":
		return not g(i)["infetto"] and g(i)["bordo"] and not g(i)["morto"]
	if v == "cosa":
		return g(i)["infetto"]
	return false
