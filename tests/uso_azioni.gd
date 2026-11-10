extends SceneTree
## Statistiche sull'IA: quante Azioni lascia inutilizzate e cosa sceglie.
func _init():
	var avanzate := 0; var turni := 0; var scelte := {}
	for p in 10:
		var mo := Motore.new()
		mo.nuova({"pg": ["garry","kinner","copper","blair","norris"], "seat": [], "seed": p*31+3})
		var ia := IA.new(mo)
		var k := 0
		while not mo.finita() and k < 6000:
			var r := mo.richiesta()
			var id := ia.decidi(r)
			if r["k"] == "turno":
				var az := id.split(":")[0]
				scelte[az] = scelte.get(az, 0) + 1
				if id == "fine":
					turni += 1; avanzate += mo.g(r["g"])["azioni"]
			mo.applica({"id": id}); k += 1
	print("azioni avanzate per turno: ", float(avanzate) / turni)
	var ks := scelte.keys(); ks.sort_custom(func(a, b): return scelte[a] > scelte[b])
	for a in ks: print("  ", a, " ", scelte[a])
	quit()
