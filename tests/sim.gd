extends SceneTree
## Partite automatiche tutte IA: controlla che finiscano e conta come finiscono.
## godot --headless --path . -s res://tests/sim.gd -- [partite] [giocatori]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 20
	var np := int(args[1]) if args.size() > 1 else 5
	var esiti := {}
	var tot_passi := 0
	var morti := 0
	var inf := 0
	var pu := 0
	var pt := 0
	for p in n:
		var mo := Motore.new()
		var pgs: Array = Dati.ORDINE_PG.duplicate()
		var r := RandomNumberGenerator.new()
		r.seed = p * 13 + 5
		for k in range(pgs.size() - 1, 0, -1):
			var j := r.randi_range(0, k)
			var t = pgs[k]; pgs[k] = pgs[j]; pgs[j] = t
		pgs = pgs.slice(0, np)
		mo.nuova({"pg": pgs, "seat": [], "seed": p * 101 + 7, "facile": OS.get_environment("FACILE") != ""})
		var ia := IA.new(mo)
		var passi := 0
		while not mo.finita() and passi < 20000:
			var rq := mo.richiesta()
			if rq.is_empty():
				push_error("nessuna richiesta ma partita non finita, stadio " + mo.s["stadio"])
				break
			var id := ia.decidi(rq)
			if not mo.applica({"id": id}):
				push_error("decisione rifiutata %s %s" % [rq["k"], id])
				break
			passi += 1
			if OS.get_environment("DBG") != "" and passi % 200 == 0:
				print(passi, " ", rq["k"], " ", id, " turno ", mo.s["turno"], " stadio ", mo.s["stadio"])
		tot_passi += passi
		var v: String = mo.s["esito"].get("vince", "NON FINITA")
		pu += int(mo.s["esito"].get("umani", 0)); pt += int(mo.s["esito"].get("totale", 0))
		esiti[v] = esiti.get(v, 0) + 1
		for i in mo.s["ordine"]:
			if mo.g(i)["morto"]: morti += 1
			if mo.g(i)["infetto"]: inf += 1
		if p < 3 or v == "NON FINITA":
			print("partita %d: %s, passi %d, turno %d | %s" % [p, v, passi, mo.s["turno"], mo.s["esito"].get("testo", "")])
			if v == "NON FINITA":
				print(mo.richiesta())
				for l in mo.s["log"].slice(-30):
					print("   ", l)
	print("ESITI ", esiti, " passi medi ", tot_passi / n, " morti/partita ", float(morti) / n, " infetti/partita ", float(inf) / n, " punti umani ", float(pu)/n, " su ", float(pt)/n)
	quit()
