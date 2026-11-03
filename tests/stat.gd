extends SceneTree
func _init():
	var tot_t := 0.0; var tot_d := 0.0; var n := 0; var mano := {}
	for p in 15:
		var mo := Motore.new()
		mo.nuova({"pg": ["garry","kinner","copper","blair","norris"], "seat": [], "seed": p*7+1})
		var ia := IA.new(mo)
		var k := 0
		while not mo.finita() and k < 5000:
			if mo.s["turno"] == 10 and mo.s["stadio"] == "giro" and mo.s["corrente"] == 0:
				break
			mo.applica({"id": ia.decidi(mo.richiesta())}); k += 1
		for i in mo.vivi():
			tot_t += mo.g(i)["tessere"].size(); tot_d += mo.dadi_per(i, "attacco"); n += 1
			for c in mo.g(i)["mano"]: mano[c["t"]] = mano.get(c["t"], 0) + 1
		print("partita ", p, " vivi al turno 11: ", mo.vivi().size(), " ", mo.vivi().map(func(x): return [mo.g(x)["tessere"], mo.g(x)["ferite"], mo.g(x)["stamina"]]))
	print("media tessere ", tot_t / max(1,n), " dadi attacco ", tot_d / max(1,n), " mano ", mano)
	quit()
