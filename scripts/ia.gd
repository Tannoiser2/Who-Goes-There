## Intelligenza artificiale dei sopravvissuti di Who Goes There?
## Ogni personaggio controllato dall'IA gioca per la sua squadra: gli umani cercano di sopravvivere,
## raccogliere Bonus elicottero e scoprire gli infetti; chi è stato assimilato dalla Cosa si comporta
## come un umano qualunque per non farsi scoprire, contagia quando gli conviene e cerca di salire
## sull'elicottero.
## Le scelte dipendono solo dallo stato della partita (e da un generatore con seme legato al passo),
## quindi sono identiche su tutti i dispositivi di una partita online.
class_name IA
extends RefCounted

var m: Motore
var rng := RandomNumberGenerator.new()

func _init(motore: Motore) -> void:
	m = motore

func decidi(r: Dictionary) -> String:
	rng.seed = int(m.s["seed"]) * 7919 + int(m.s["passo"]) * 31 + int(r["g"])
	var opz: Array = r["opz"]
	if opz.is_empty():
		return ""
	var fn := "_k_" + str(r["k"])
	if has_method(fn):
		var id = call(fn, int(r["g"]), r)
		if id != null and str(id) != "" and _ha(opz, str(id)):
			return str(id)
	return str(opz[0]["id"])

func _ha(opz: Array, id: String) -> bool:
	for o in opz:
		if str(o["id"]) == id:
			return true
	return false

func _id_che_inizia(opz: Array, pref: String) -> String:
	for o in opz:
		if str(o["id"]).begins_with(pref):
			return str(o["id"])
	return ""

# ============================================================ sospetto

## Quanto i sospetta che j sia infetto (0..1), usando solo ciò che i può sapere.
func sospetto(i: int, j: int) -> float:
	if i == j:
		return 0.0
	var gi: Dictionary = m.g(i)
	var sa = gi["sa"].get(str(j), null)
	if sa is Dictionary and sa["v"] == "infetto":
		return 1.0
	var sus := 0.06 + 0.11 * float(m.s["n_vuln_pubbliche"].get(str(j), 0))
	for e in m.s["eventi_pubblici"]:
		match e["t"]:
			"scambio":
				if e["b"] == j and int(e.get("vuln", 0)) > 0 and e["a"] != i:
					sus += 0.07
				if e["a"] == j and e["b"] == i:
					sus -= 0.02
			"letto":
				if (e["a"] == j or e["b"] == j):
					var altro: int = e["b"] if e["a"] == j else e["a"]
					if altro != i and float(m.s["n_vuln_pubbliche"].get(str(altro), 0)) > 0:
						sus += 0.05
			"assalto":
				if e["a"] == j:
					var vittima_inf := false
					var sv = gi["sa"].get(str(e["b"]), null)
					if sv is Dictionary and sv["v"] == "infetto":
						vittima_inf = true
					sus += -0.1 if vittima_inf else 0.25
			"rifiuto_letto":
				if e["a"] == j and e["b"] == i:
					sus += 0.05
	for d in m.s["dichiarazioni"]:
		if d["su"] == j and d["chi"] != i:
			var fid := 1.0 - _sospetto_base(i, d["chi"])
			sus += (0.4 if d["v"] == "infetto" else -0.15) * fid
		if d["chi"] == j and d["v"] == "infetto":
			# chi accusa qualcuno che io so pulito è sospetto
			var sv2 = gi["sa"].get(str(d["su"]), null)
			if sv2 is Dictionary and sv2["v"] == "pulito" and sv2.get("certo", false):
				sus += 0.35
	if sa is Dictionary and sa["v"] == "pulito":
		var vecchio: int = int(m.s["turno"]) - int(sa["turno"])
		sus *= (0.25 if sa.get("certo", false) else 0.6) + 0.05 * vecchio
	return clamp(sus, 0.0, 1.0)

func _sospetto_base(i: int, j: int) -> float:
	var sa = m.g(i)["sa"].get(str(j), null)
	if sa is Dictionary and sa["v"] == "infetto":
		return 1.0
	if sa is Dictionary and sa["v"] == "pulito" and sa.get("certo", false):
		return 0.05
	return clamp(0.06 + 0.11 * float(m.s["n_vuln_pubbliche"].get(str(j), 0)), 0.0, 0.8)

func infetto(i: int) -> bool:
	return bool(m.g(i)["infetto"])

## Quanti infetti ci sono in tutto (la Cosa "sente" i suoi simili).
func n_infetti() -> int:
	var n := 0
	for k in m.s["ordine"]:
		if m.g(k)["infetto"] and not m.g(k)["morto"]:
			n += 1
	return n

# ============================================================ richieste semplici

func _k_partenza(i: int, _r: Dictionary):
	var x := rng.randf()
	if x < 0.42:
		return "officina"
	if x < 0.84:
		return "magazzino"
	return "fase1"

func _k_letto(i: int, r: Dictionary):
	var best := ""
	var bs := 2.0
	for o in r["opz"]:
		if o["id"] == "solo":
			continue
		var sc := sospetto(i, o["j"])
		if infetto(i):
			# la Cosa preferisce dormire con chi non è ancora contagiato
			sc = 0.3 if not infetto(o["j"]) else 0.5
			sc += rng.randf() * 0.2
		if sc < bs:
			bs = sc
			best = o["id"]
	if best != "" and (infetto(i) or bs < 0.55):
		return best
	return "solo"

func _k_accetta_letto(i: int, r: Dictionary):
	if infetto(i):
		return "si"
	return "si" if sospetto(i, r["da"]) < 0.55 else "no"

func _k_segnalatore(i: int, r: Dictionary):
	return "infetto" if _vuole_contagiare(i, r["b"]) else "pulito"

func _k_segnalatore_scambio(i: int, r: Dictionary):
	var b: int = m.s["ctx"].get("scambio", {}).get("a", -1)
	return "infetto" if b >= 0 and _vuole_contagiare(i, b) else "pulito"

func _vuole_contagiare(i: int, b: int) -> bool:
	if infetto(b):
		return false
	var vivi := m.vivi().size()
	# troppi contagi fanno perdere anche la Cosa: si contagia fino a circa metà della squadra
	if n_infetti() >= int(ceil(vivi / 2.0)):
		return false
	return rng.randf() < 0.7

func _k_evita(i: int, r: Dictionary):
	var da: int = m.s["ctx"]["scambio"]["da"]
	if infetto(i):
		return "accetta"
	if _ha(r["opz"], "tira") and sospetto(i, da) > 0.3:
		return "tira"
	return "accetta"

func _k_chiesta(i: int, r: Dictionary):
	if not _ha(r["opz"], "si"):
		return "no"
	var da: int = r["da"]
	var tipo: String = r["tipo"]
	if tipo in ["scatoletta", "scatoletta2"] and m.conta_mano(i, "scatoletta") + m.conta_mano(i, "scatoletta2") <= 1 and _turni_al_pasto() <= 3:
		return "no"
	if tipo in Dati.MATERIALI and _serve_materiale(i, tipo) and m.conta_mano(i, tipo) <= 1 and rng.randf() < 0.6:
		return "no"
	if infetto(i):
		return "si"
	return "si" if sospetto(i, da) < 0.6 else "no"

func _k_potenzia(i: int, r: Dictionary):
	var p: Dictionary = m.s["ctx"]["prova"]
	var manca: int = p["richiesti"] - m._succ(p)
	# prima le cose che danno Successi sicuri
	for pref in ["t", "arm", "shield", "hotspot", "c"]:
		for o in r["opz"]:
			var id: String = o["id"]
			if id == "accetta":
				continue
			if id.begins_with(pref):
				if pref == "c" and manca >= 4:
					continue
				return id
	return "accetta"

func _k_ferita_o_xp(i: int, _r: Dictionary):
	var gg := m.g(i)
	if gg["ferite"] + gg["critiche"] >= 1 or gg["xp"] >= 4:
		return "xp"
	return "xp" if rng.randf() < 0.5 else "ferita"

func _k_cibo_o_vuln(_i: int, _r: Dictionary):
	return "cibo"

func _k_forziere(i: int, r: Dictionary):
	var t: String = r["tipo"]
	var gg := m.g(i)
	match t:
		"forziere_lanciafiamme":
			return "tira" if m.puo_equipaggiare(i, "flamethrower") else "xp"
		"forziere_torcia":
			return "tira" if m.puo_equipaggiare(i, "torch") else "xp"
		"forziere_borsa":
			return "tira" if m.puo_equipaggiare(i, "pouch") and rng.randf() < 0.6 else "xp"
		"forziere_sciarpa":
			return "tira" if m.puo_equipaggiare(i, "scarf") and rng.randf() < 0.4 else "xp"
		"forziere_stamina":
			return "tira" if gg["stamina"] <= 2 else "xp"
		"forziere_specialita":
			return "tira" if rng.randf() < 0.4 else "xp"
	return "xp"

func _k_scelta_tessera(i: int, r: Dictionary):
	for o in r["opz"]:
		if o["id"] != "xp":
			return o["id"]
	return "xp"

func _k_scelta_carte(i: int, _r: Dictionary):
	return "carte" if m.g(i)["mano"].size() <= 3 else "xp"

func _k_pesca_interna(i: int, r: Dictionary):
	if m.conta_mano(i, "scatoletta") == 0:
		return "magazzino"
	return "officina" if rng.randf() < 0.5 else r["opz"][2]["id"]

func _valore_carta(i: int, c: Dictionary) -> float:
	var t: String = c["t"]
	match t:
		"spazzatura": return 0.0
		"scatoletta", "scatoletta2": return 9.0 if m.conta_mano(i, "scatoletta") + m.conta_mano(i, "scatoletta2") <= 1 else 5.0
		"pronto_soccorso": return 8.0
		"fucile", "colpo_in_canna", "proiettile", "molotov": return 6.0
		"esame_sangue", "test_ospite": return 7.0
	if t in Dati.MATERIALI:
		return 3.0 + (2.0 if _serve_materiale(i, t) else 0.0)
	return 4.0

func _serve_materiale(i: int, t: String) -> bool:
	for r in Dati.ORDINE_RICETTE:
		var ric: Dictionary = Dati.RICETTE[r]
		if t in ric["m"] and (not ric.has("da") or ric["da"] in m.g(i)["tessere"]) and not (r in m.g(i)["tessere"]):
			return true
	return false

## Il materiale che manca (uno solo) per completare una ricetta, oppure "".
func _manca_solo(i: int) -> String:
	var gg := m.g(i)
	for r in Dati.ORDINE_RICETTE:
		var ric: Dictionary = Dati.RICETTE[r]
		if ric.has("da") and not (ric["da"] in gg["tessere"]):
			continue
		if ric.has("da2") and not (ric["da2"] in gg["tessere"]):
			continue
		if r in gg["tessere"] or m.s["banco"].get(r, 0) <= 0:
			continue
		var mano := {}
		for c in gg["mano"]:
			mano[c["t"]] = mano.get(c["t"], 0) + 1
		var mancano := []
		for mt in ric["m"]:
			if mano.get(mt, 0) > 0:
				mano[mt] -= 1
			else:
				mancano.append(mt)
		if mancano.size() == 1 and mancano[0] != "accendino_vuoto":
			return mancano[0]
	return ""

func _peggiore(i: int, opz: Array) -> String:
	var best := ""
	var bv := 999.0
	for o in opz:
		if not o.has("k"):
			continue
		var v := _valore_carta(i, m.g(i)["mano"][o["k"]])
		if o.get("falo", false):
			v -= 0.5
		if v < bv:
			bv = v
			best = o["id"]
	return best

func _k_scarta(i: int, r: Dictionary):
	return _peggiore(i, r["opz"])

func _k_troppe(i: int, r: Dictionary):
	return _peggiore(i, r["opz"])

func _k_ombre(i: int, r: Dictionary):
	return _peggiore(i, r["opz"])

func _k_test(i: int, r: Dictionary):
	var best := ""
	var bs := -1.0
	for o in r["opz"]:
		var sc := sospetto(i, o["j"])
		if infetto(i):
			sc = 0.5 if not infetto(o["j"]) else 0.0
		if sc > bs:
			bs = sc
			best = o["id"]
	return best

func _k_dichiara(i: int, r: Dictionary):
	var su: int = r["su"]
	if not infetto(i):
		var sa = m.g(i)["sa"].get(str(su), null)
		if sa is Dictionary:
			return sa["v"]
		return "zitto"
	# la Cosa copre i suoi simili e ogni tanto getta sospetti su un umano
	if infetto(su):
		return "pulito"
	return "infetto" if rng.randf() < 0.25 else "pulito"

func _k_bersaglio_infezione(i: int, r: Dictionary):
	for o in r["opz"]:
		if not infetto(o["j"]):
			return o["id"]
	return r["opz"][0]["id"]

func _k_sesto_senso(_i: int, _r: Dictionary):
	var t: String = m.s["evento"].get("t", "")
	return "si" if t in ["ev_cosa", "ev_filo_spinato", "ev_cane_rabbioso", "ev_incendio_caldaia", "ev_pazzo"] else "no"

func _k_imbarco(i: int, r: Dictionary):
	if infetto(i):
		# la Cosa porta con sé tutti: più infetti a bordo, più dura per gli umani
		for o in r["opz"]:
			if str(o["id"]).begins_with("su:"):
				return o["id"]
		return "ok"
	var peggio := ""
	var ps := 0.5
	for o in r["opz"]:
		var id: String = o["id"]
		if id.begins_with("giu:"):
			var sc := sospetto(i, o["j"])
			if sc >= ps:
				ps = sc
				peggio = id
	if peggio != "":
		return peggio
	return "ok"

func _k_scendi(_i: int, _r: Dictionary):
	return "resta"

# ============================================================ il turno

func _turni_al_pasto() -> int:
	var t: int = m.s["turno"]
	var tt: Array = m.s["turni"]
	for k in range(t, tt.size()):
		if tt[k]["tipo"] == "pasto":
			return k - t
	return 99

func _turni_alla_fine() -> int:
	return m.s["turni"].size() - int(m.s["turno"])

func _ha_cibo(i: int) -> bool:
	if m.conta_mano(i, "scatoletta") + m.conta_mano(i, "scatoletta2") > 0:
		return true
	return m.g(i)["pg"] == "kinner" and m.ha_sblocco(i, "unico") and m.conta_mano(i, "snack") > 0

## Dove vuole stare l'IA in questo turno: "dentro" o "fuori".
func _meta(i: int) -> String:
	var gg := m.g(i)
	var f := m.fase()
	if _turni_al_pasto() <= 3 and not _ha_cibo(i):
		return "dentro"
	if gg["ferite"] + gg["critiche"] >= 2:
		return "dentro"
	if s_blocco():
		return m.luogo(i)
	# prima ci si arma: senza almeno due tessere oggetto fuori si muore (in Fase 1 si esce comunque a far XP)
	if m.spazi_usati(i) < 2 and _turni_alla_fine() > 6 and not (f == 1 and m.dadi_per(i, "attacco") >= 2 and rng.randf() < 0.5):
		return "dentro"
	if m.spazi_usati(i) < 3 and f >= 2 and _turni_alla_fine() > 6 and rng.randf() < 0.6:
		return "dentro"
	# fuori fa freddo: serve abbastanza Stamina per il prossimo calo e dadi contro la Cosa
	var resiste: bool = gg["stamina"] >= f + 1
	var dadi := m.dadi_per(i, "attacco")
	if resiste and dadi >= f + 1 and gg["azioni"] >= 3:
		return "fuori"
	# verso la fine servono i Bonus elicottero: si rischia di più
	if resiste and (dadi >= f or _turni_alla_fine() <= 5) and _turni_alla_fine() <= 8 and gg["azioni"] >= 3:
		return "fuori"
	return "dentro"

func s_blocco() -> bool:
	return bool(m.s["blocco"])

func _spazio_fuori(i: int) -> String:
	var dadi := m.dadi_per(i, "attacco")
	var best := "fase1"
	for f in range(1, m.fasi_aperte() + 1):
		var sp := "fase%d" % f
		if m.s["mazzi"][sp].is_empty():
			continue
		if dadi >= f + 1 or f == 1:
			best = sp
	return best

func _spazio_dentro(i: int) -> String:
	if (not _ha_cibo(i) and _turni_al_pasto() <= 2) or (m.conta_mano(i, "pronto_soccorso") == 0 and m.g(i)["ferite"] > 1):
		return "magazzino"
	# servono armi: materiali dall'Officina
	if m.spazi_usati(i) < m.spazi_oggetti(i):
		return "officina" if rng.randf() < 0.75 else "magazzino"
	return "officina" if rng.randf() < 0.4 else "magazzino"

func _k_turno(i: int, r: Dictionary):
	var gg := m.g(i)
	var opz: Array = r["opz"]
	var conta: int = gg.get("_ia_passi", 0)
	if m.s.get("_ia_turno_di", -1) != i or m.s.get("_ia_turno_n", -1) != m.s["turno"]:
		m.s["_ia_turno_di"] = i
		m.s["_ia_turno_n"] = m.s["turno"]
		m.s["_ia_meta"] = _meta(i)
		m.s["_ia_spazio"] = _spazio_fuori(i) if m.s["_ia_meta"] == "fuori" else _spazio_dentro(i)
		m.s["_ia_cont"] = 0
	m.s["_ia_cont"] += 1
	if m.s["_ia_cont"] > 40:
		return "fine"
	if m.s["_ia_cont"] == 1:
		m.s["_ia_chiesti"] = 0
	var meta: String = m.s["_ia_meta"]
	var spazio: String = m.s["_ia_spazio"]
	var best := "fine"
	var bv := 6.0
	for o in opz:
		var v := _valuta(i, o, meta, spazio)
		if v > bv:
			bv = v
			best = o["id"]
	if best.begins_with("chiedi"):
		m.s["_ia_chiesti"] = int(m.s.get("_ia_chiesti", 0)) + 1
	return best

func _valuta(i: int, o: Dictionary, meta: String, spazio: String) -> float:
	var gg := m.g(i)
	var id: String = o["id"]
	var parti := id.split(":")
	var az := parti[0]
	var f := m.fase()
	var a: int = gg["azioni"]
	match az:
		"evento":
			# prima si migliora il tiro (Stamina a 4 = 2 dadi naturali, armi), poi si affronta l'evento
			return 52.0 if a > 0 else 100.0
		"gioca":
			var t: String = gg["mano"][int(parti[1])]["t"]
			match t:
				"pronto_soccorso": return 95.0 if gg["critiche"] > 0 else 70.0 + 10.0 * gg["ferite"]
				"carta_piede_porco", "carta_lanciarazzi", "carta_torcia", "bisturi", "lanciarazzi_kinner", "coltellino": return 65.0
				"dex": return 45.0 if a <= 1 else 0.0
				"snack": return 40.0 if gg["stamina"] <= 2 else 0.0
				"alcol": return 45.0 if gg["stamina"] <= gg["stamina_max"] - 1 else 0.0
				"scatoletta", "scatoletta2":
					if m.conta_mano(i, "scatoletta") + m.conta_mano(i, "scatoletta2") >= 2 and gg["stamina"] <= 2:
						return 35.0
					return 0.0
				"boost_stamina": return 45.0 if gg["stamina"] <= gg["stamina_max"] - 2 else 0.0
				"guaritore":
					var n := 0
					for j in m.vivi():
						if m.g(j)["pos"] == gg["pos"] and m.g(j)["ferite"] + m.g(j)["critiche"] > 0:
							n += 1
					return 30.0 * n
				"kit_riparazione": return 50.0
				"esame_sangue", "test_ospite":
					if infetto(i):
						return 0.0
					for j in m.vivi():
						if j != i and m.stesso_luogo(i, j) and sospetto(i, j) >= 0.3:
							return 55.0
					return 0.0
				"resistenza": return 50.0
				"legnetti": return 30.0
				"dispensa", "stazione_medica", "offro_io", "banco_lavoro", "cassetta_attrezzi", "sella": return 40.0
				"manuale_addestramento": return 60.0
				"ingegno", "riporto": return 10.0
			return 0.0
		"armadietto":
			var testo: String = o["testo"]
			if "Ferita" in testo:
				return 85.0
			if "XP" in testo:
				return 30.0
			if "Danno" in testo:
				return 45.0
			return 25.0 if gg["stamina"] <= 2 else 0.0
		"sblocca":
			var k: String = parti[1]
			match k:
				"unico": return 80.0 if m.g(i)["pg"] == "garry" else 72.0
				"cardio": return 62.0
				"agilita": return 56.0
				"armadietto": return 50.0
				"spazi": return 64.0 if m.spazi_usati(i) >= m.spazi_oggetti(i) else 20.0
				"scorta_xp": return 66.0
		"costruisci":
			var t2: String = parti[1]
			var tt: Dictionary = Dati.TESSERE[t2]
			return 58.0 + 6.0 * (tt["r"] + tt["b"]) + (8.0 if Dati.RICETTE[t2].has("da") else 0.0)
		"stamina":
			if gg["stamina"] >= gg["stamina_max"]:
				return 0.0
			if gg["stamina"] < 4 and m.evento_mi_riguarda(i) and not gg["ev_fatto"]:
				return 56.0
			return 18.0 + 6.0 * (gg["stamina_max"] - gg["stamina"]) - (0.0 if meta == "dentro" else 10.0)
		"ripara", "ripara_tiro":
			var dan: int = m.s["caldaia"] if m.dentro(i) else m.s["porta"]
			var base := 55.0 if dan >= 2 else 24.0
			if az == "ripara_tiro":
				base -= 8.0 if a >= 2 else -2.0
			return base
		"fiaschetta":
			return 40.0
		"scienziato":
			return 30.0
		"accendi":
			var n2 := 0
			for j in m.vivi():
				if m.dentro(j) and m.g(j)["stamina"] < m.g(j)["stamina_max"] - 1:
					n2 += 1
			return 30.0 + 15.0 * n2
		"falo":
			var t3: String = gg["mano"][int(parti[1])]["t"]
			return 28.0 if t3 == "spazzatura" else 0.0
		"muovi", "muovi_racchette":
			var sp: String = o["sp"]
			var dove := "dentro" if Dati.dentro(sp) else "fuori"
			var bonus := 5.0 if az == "muovi_racchette" else 0.0
			if dove != m.luogo(i):
				if dove == meta and sp == spazio:
					return 50.0 + bonus
				return 0.0
			if sp == spazio and gg["pos"] != spazio:
				return 42.0 + bonus
			return 0.0
		"cerca":
			var mz: String = parti[1]
			if mz.begins_with("fase"):
				if m.luogo(i) != "fuori":
					return 0.0
				var dd := m.dadi_per(i, "attacco")
				var fm := int(mz.substr(4))
				if dd >= fm + 1:
					return 46.0
				if dd >= fm:
					return 36.0
				return 12.0 if _turni_alla_fine() > 5 else 30.0
			if mz.begins_with("specialita"):
				var sv := 33.0 + (4.0 if m.s["mazzi"][mz].size() > 8 else 0.0)
				if not _ha_cibo(i) and _turni_al_pasto() <= 4:
					sv += 8.0
				return sv
			if mz == gg["pos"]:
				var cv := 40.0 if gg["pos"] == spazio else 34.0
				if mz == "magazzino" and not _ha_cibo(i) and _turni_al_pasto() <= 2:
					cv += 6.0
				if mz == "officina" and m.spazi_usati(i) < m.spazi_oggetti(i):
					cv += 6.0
				return cv
			return 0.0
		"xp":
			return 16.0
		"dai":
			var j: int = int(parti[1])
			var t4: String = gg["mano"][int(parti[2])]["t"]
			if infetto(i) and gg["vuln"].size() > 0 and not infetto(j) and _vuole_contagiare(i, j) and t4 == "spazzatura":
				return 26.0
			return 0.0
		"chiedi":
			var j2: int = int(parti[1])
			var tipo: String = parti[2]
			if int(m.s.get("_ia_chiesti", 0)) >= 2:
				return 0.0
			if tipo == "scatoletta" and not _ha_cibo(i) and _turni_al_pasto() <= 3 and a >= 1:
				return 47.0 if (infetto(i) or sospetto(i, j2) < 0.45) else 0.0
			if tipo == "pronto_soccorso" and gg["ferite"] + gg["critiche"] >= 2 and a >= 1:
				return 34.0 if sospetto(i, j2) < 0.45 else 0.0
			if tipo in Dati.MATERIALI and a >= 2 and _manca_solo(i) == tipo:
				return 44.0 if (infetto(i) or sospetto(i, j2) < 0.45) else 0.0
			return 0.0
		"assalto":
			var j3: int = int(parti[1])
			if infetto(i):
				# la Cosa elimina chi l'ha smascherata, se è debole
				for d in m.s["dichiarazioni"]:
					if d["su"] == i and d["chi"] == j3 and d["v"] == "infetto" and m.g(j3)["ferite"] >= 1:
						return 60.0
				return 0.0
			var sc := sospetto(i, j3)
			if sc >= 0.95:
				return 80.0
			if sc >= 0.8 and _turni_alla_fine() <= 4:
				return 62.0
			return 0.0
		"infezione":
			if _turni_alla_fine() <= 7 and n_infetti() < int(ceil(m.vivi().size() / 2.0)) and rng.randf() < 0.3:
				return 55.0
			return 0.0
		"rif_dispensa":
			return 30.0 if gg["xp"] >= 3 else 0.0
		"rif_medica":
			return 70.0 if gg["ferite"] + gg["critiche"] >= 2 else 0.0
		"rif_offro":
			return 32.0
	return 0.0
