extends SceneTree
func _initialize():
	var p := Plancia3D.new()
	root.add_child(p)
	var mo := Motore.new()
	mo.nuova({"pg": ["garry","kinner","copper","blair","norris"], "seat": [], "seed": 3})
	var ia := IA.new(mo)
	for k in 60:
		mo.applica({"id": ia.decidi(mo.richiesta())})
	_go.call_deferred(p, mo)
func _go(p, mo):
	p.aggiorna(mo)
	var args := OS.get_cmdline_user_args()
	if args.size() >= 3:
		p.pitch = float(args[0]); p.yaw = float(args[1]); p.dist = float(args[2]); p._aggiorna_camera()
	for i in 30: await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/foto3d.png")
	quit()
