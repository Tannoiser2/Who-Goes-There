extends SceneTree
## Screenshot dell'interfaccia: xvfb-run godot --path . -s res://tests/foto.gd -- <modo>
## modo: menu | nuova | partita | fine
var main
func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()
func shot(nome: String):
	for i in 12: await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/shot_%s.png" % nome)
	print("shot ", nome)
func _run():
	var modo: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "menu"
	await shot("menu")
	if modo == "menu":
		quit(); return
	main._menu_nuova()
	await shot("nuova")
	if modo == "nuova":
		quit(); return
	main.scelta_pg = "copper"
	main._avvia_locale()
	main.velocita = 50.0
	# il giocatore umano sceglie a caso fino al suo primo vero turno
	var passi := 0
	var target := int(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 1
	var turni_miei := 0
	while passi < 3000:
		await process_frame
		var r: Dictionary = main.m.richiesta()
		if main.m.finita(): break
		if not r.is_empty() and main.io(r["g"]):
			if modo == "dialogo" and r["k"] != "turno" and r["k"] != "partenza" and passi > 5:
				for q in 20: await process_frame
				await shot("dialogo_" + r["k"])
				target -= 1
				if target <= 0:
					quit(); return
			if r["k"] == "turno":
				turni_miei += 1
				if turni_miei >= target and modo != "dialogo":
					break
			var id: String = main.ia.decidi(r)
			main._decidi(id)
		passi += 1
	main._aggiorna_tutto()
	await shot("partita")
	if modo == "fine":
		while not main.m.finita() and passi < 20000:
			var r2: Dictionary = main.m.richiesta()
			main.m.applica({"id": main.ia.decidi(r2)})
			passi += 1
		main._aggiorna_tutto()
		for i in 30: await process_frame
		await shot("fine")
	quit()
