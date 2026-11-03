extends SceneTree
func _init():
	var mo := Motore.new()
	mo.nuova({"pg": ["garry","kinner","copper","blair","norris"], "seat": [], "seed": int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 3})
	var ia := IA.new(mo)
	var n := 0
	while not mo.finita() and n < 5000:
		var rq := mo.richiesta()
		var id := ia.decidi(rq)
		if rq["k"] == "turno": mo._log("    [%s sceglie %s | az %d st %d fer %d xp %d]" % [mo.nome(rq["g"]), id, mo.g(rq["g"])["azioni"], mo.g(rq["g"])["stamina"], mo.g(rq["g"])["ferite"], mo.g(rq["g"])["xp"]])
		mo.applica({"id": id})
		n += 1
	for l in mo.s["log"]: print(l)
	quit()
