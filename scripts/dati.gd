## Dati fissi di Who Goes There?: personaggi, tessere oggetto, ricette, turni.
## Le carte (composizione dei mazzi e testi in italiano) stanno in assets/dati/carte.json.
class_name Dati
extends RefCounted

const PG := {
	"garry": {"nome": "Garry", "titolo": "Il comandante", "grado": 1, "mazzo": "specialita_garry",
		"unico": "pistola", "unico_nome": "Pistola", "unico_testo": "Puoi usare i Proiettili del tuo mazzo Specialità.",
		"armadietto": "proiettili", "colore": Color(0.85, 0.47, 0.0)},
	"mcready": {"nome": "MacReady", "titolo": "Il meteorologo", "grado": 2, "mazzo": "specialita_mcready",
		"unico": "fiaschetta", "unico_nome": "Fiaschetta", "unico_testo": "Una volta per turno, fuori, tira 1 dado: Successo = +1 Stamina.",
		"armadietto": "alcol", "colore": Color(0.51, 0.45, 0.64)},
	"kinner": {"nome": "Kinner", "titolo": "Il cuoco", "grado": 3, "mazzo": "specialita_kinner",
		"unico": "mangia_poco", "unico_nome": "Mangia poco", "unico_testo": "Nei turni del Pasto puoi mangiare uno Snack al posto della Scatoletta.",
		"armadietto": "snack", "colore": Color(0.46, 0.59, 0.22)},
	"copper": {"nome": "Dr. Copper", "titolo": "Il medico", "grado": 4, "mazzo": "specialita_copper",
		"unico": "disinfettante", "unico_nome": "Disinfettante", "unico_testo": "Le tue Ferite critiche diventano Ferite normali.",
		"armadietto": "pronto_soccorso", "colore": Color(0.21, 0.43, 0.6)},
	"blair": {"nome": "Blair", "titolo": "Il biologo", "grado": 5, "mazzo": "specialita_blair",
		"unico": "accendino", "unico_nome": "Accendino", "unico_testo": "Non ti servono più i Fiammiferi (per costruire e per il Falò).",
		"armadietto": "racchette", "colore": Color(0.51, 0.51, 0.46)},
	"clark": {"nome": "Clark", "titolo": "L'addestratore di cani", "grado": 6, "mazzo": "specialita_clark",
		"unico": "compagno", "unico_nome": "Compagno: Jack", "unico_testo": "Il cane Jack occupa uno spazio oggetti: +1 Attacco, +1 Ostacolo. Va sfamato nel Pasto.",
		"armadietto": "biscotto", "colore": Color(0.39, 0.82, 0.74)},
	"vanwall": {"nome": "Van Wall", "titolo": "Il pilota", "grado": 7, "mazzo": "specialita_vanwall",
		"unico": "spazio_extra", "unico_nome": "Spazio in più", "unico_testo": "Puoi tenere 1 tessera oggetto in più.",
		"armadietto": "kit_riparazione", "colore": Color(0.72, 0.19, 0.16)},
	"norris": {"nome": "Norris", "titolo": "Il fisico", "grado": 8, "mazzo": "specialita_norris",
		"unico": "doppia_arma", "unico_nome": "Doppia arma", "unico_testo": "Puoi equipaggiare tessere oggetto doppie.",
		"armadietto": "tirapugni", "colore": Color(0.97, 0.77, 0.0)},
}
const ORDINE_PG := ["garry", "mcready", "kinner", "copper", "blair", "clark", "vanwall", "norris"]

## Facce del dado Armadietto: 2 del personaggio, Razzo, 2 XP, 2 Materiale.
const FACCE_ARMADIETTO := ["unico", "unico", "razzo", "xp2", "materiale", "materiale"]
const NOMI_ARMADIETTO := {"proiettili": "Proiettili (+2 dadi contro un Attacco, con la Pistola)",
	"alcol": "Alcol (come materiale, o +1 Stamina fuori)", "snack": "Snack (+1 Stamina)",
	"pronto_soccorso": "Pronto soccorso (togli 1 Ferita)", "racchette": "Racchette da neve (ti sposti senza spendere Azioni)",
	"biscotto": "Biscotto (sfama Jack nel Pasto)", "kit_riparazione": "Kit riparazione (togli 1 Danno a Porta o Caldaia)",
	"tirapugni": "Tirapugni (ritira 1 dado contro un Attacco)", "razzo": "Razzo (1 dado mancato diventa Successo)",
	"xp2": "2 XP", "materiale": "Materiale (sostituisce un materiale qualsiasi)"}

## Tessere oggetto: r = dadi contro Attacchi (rossi), b = contro Ostacoli (blu), spazi occupati, quante ce ne sono.
const TESSERE := {
	"club": {"nome": "Mazza", "r": 1, "b": 0, "n": 6, "tipo": "arma", "testo": "+1 dado contro gli Attacchi."},
	"torch": {"nome": "Torcia", "r": 1, "b": 1, "n": 6, "tipo": "arma", "testo": "+1 dado contro Attacchi e Ostacoli."},
	"lantern": {"nome": "Lanterna", "r": 1, "b": 2, "n": 6, "tipo": "arma", "testo": "Ritira 1 dado mancato per Stamina o XP."},
	"barricade": {"nome": "Barricata", "r": 0, "b": 1, "n": 6, "tipo": "arma", "testo": "+1 XP a ogni turno. Se dormi da solo tira 1 dado: Successo = niente carta Vulnerabile."},
	"knife": {"nome": "Coltello", "r": 1, "b": 0, "n": 6, "tipo": "arma", "testo": "+1 dado contro gli Attacchi."},
	"hatchet": {"nome": "Accetta", "r": 1, "b": 1, "n": 6, "tipo": "arma", "testo": "Ritira 1 dado mancato nelle Riparazioni."},
	"axe": {"nome": "Ascia", "r": 2, "b": 2, "n": 6, "tipo": "arma", "spazi": 2, "testo": "+2 dadi contro Attacchi e Ostacoli. Occupa 2 spazi."},
	"shield": {"nome": "Scudo", "r": 0, "b": 1, "n": 6, "tipo": "arma", "testo": "Ritira 1 dado mancato contro un Attacco dell'evento del campo."},
	"camp_defense": {"nome": "Difesa del campo", "r": 2, "b": 1, "n": 6, "tipo": "arma", "testo": "Spendi 1 XP per guardare il prossimo evento del campo."},
	"scarf": {"nome": "Sciarpa", "r": 0, "b": 0, "n": 6, "tipo": "utile", "testo": "Ritira 1 dado mancato per Stamina o XP."},
	"travel_coat": {"nome": "Giaccone da viaggio", "r": 0, "b": 0, "n": 6, "tipo": "utile", "cappotto": true, "testo": "Cercare fuori costa solo 1 Azione."},
	"mechanic_coat": {"nome": "Tuta da meccanico", "r": 0, "b": 0, "n": 6, "tipo": "utile", "cappotto": true, "testo": "Cercare dentro costa solo 1 Azione."},
	"pouch": {"nome": "Borsa", "r": 0, "b": 0, "n": 6, "tipo": "utile", "testo": "Puoi tenere 2 carte in più in mano."},
	"guideline": {"nome": "Corda guida", "r": 0, "b": 0, "n": 6, "tipo": "utile", "testo": "Spostarsi non costa Azioni."},
	"hot_spot": {"nome": "Scaldino", "r": 0, "b": 0, "n": 6, "tipo": "utile", "testo": "Una volta per turno, fuori, ritira 1 dado mancato."},
	"lighter": {"nome": "Accendino", "r": 0, "b": 0, "n": 6, "tipo": "utile", "testo": "Vale come Fiammiferi (per costruire e per il Falò)."},
	"crowbar": {"nome": "Piede di porco", "r": 1, "b": 0, "n": 2, "tipo": "arma", "testo": "Ritira 1 dado sulle Cassette."},
	"flare_gun": {"nome": "Lanciarazzi", "r": 1, "b": 1, "n": 2, "tipo": "arma", "testo": "+1 dado contro Attacchi e Ostacoli."},
	"flare_gun_kinner": {"nome": "Lanciarazzi di Kinner", "r": 1, "b": 1, "n": 1, "tipo": "arma", "testo": "+1 dado contro Attacchi e Ostacoli."},
	"flamethrower": {"nome": "Lanciafiamme", "r": 3, "b": 1, "n": 1, "tipo": "arma", "spazi": 2, "testo": "+3 dadi contro gli Attacchi. Occupa 2 spazi."},
	"pocket_knife": {"nome": "Coltellino svizzero", "r": 1, "b": 1, "n": 1, "tipo": "arma", "testo": "Ritira 1 dado mancato nelle Riparazioni."},
	"companion": {"nome": "Jack, compagno fedele", "r": 1, "b": 1, "n": 1, "tipo": "unico", "testo": "Se Clark dorme da solo tira 1 dado: Successo = niente Vulnerabile. Va sfamato nel Pasto."},
	"companion_trained": {"nome": "Jack, addestrato", "r": 1, "b": 2, "n": 1, "tipo": "unico", "testo": "Se Clark dorme da solo non pesca la Vulnerabile. Va sfamato nel Pasto."},
}

## Ricette: materiali (legno, stoffa, corda, viti, metallo, alcol, fiammiferi) + tessera richiesta (aggiornamento).
const RICETTE := {
	"club": {"m": ["legno", "viti"]},
	"torch": {"m": ["fiammiferi", "stoffa"], "da": "club"},
	"lantern": {"m": ["fiammiferi", "alcol"], "da": "torch"},
	"barricade": {"m": ["viti", "metallo"], "da": "club"},
	"knife": {"m": ["corda", "metallo"]},
	"hatchet": {"m": ["legno", "viti"], "da": "knife"},
	"axe": {"m": ["legno", "metallo"], "da": "hatchet"},
	"shield": {"m": ["metallo", "metallo"]},
	"camp_defense": {"m": ["viti"], "da": "knife", "da2": "shield"},
	"scarf": {"m": ["stoffa", "stoffa"]},
	"travel_coat": {"m": ["corda", "fiammiferi"], "da": "scarf"},
	"mechanic_coat": {"m": ["corda", "viti"], "da": "scarf"},
	"pouch": {"m": ["stoffa", "corda"]},
	"guideline": {"m": ["corda", "corda", "metallo"]},
	"hot_spot": {"m": ["alcol", "fiammiferi", "stoffa"]},
	"lighter": {"m": ["alcol", "accendino_vuoto"]},
}
const ORDINE_RICETTE := ["club", "knife", "shield", "scarf", "pouch", "guideline", "hot_spot", "lighter",
	"torch", "barricade", "hatchet", "travel_coat", "mechanic_coat", "lantern", "axe", "camp_defense"]
const MATERIALI := ["legno", "stoffa", "corda", "viti", "metallo", "alcol", "fiammiferi"]
const NOMI_MAT := {"legno": "Legno", "stoffa": "Stoffa", "corda": "Corda", "viti": "Viti", "metallo": "Metallo",
	"alcol": "Alcol", "fiammiferi": "Fiammiferi", "accendino_vuoto": "Accendino vuoto"}

const SBLOCCHI := {
	"unico": {"nome": "Abilità unica", "xp": 3},
	"cardio": {"nome": "Cardio (+1 Stamina massima)", "xp": 2},
	"agilita": {"nome": "Agilità (+1 Azione)", "xp": 6},
	"armadietto": {"nome": "Combinazione armadietto (dado)", "xp": 6},
	"spazi": {"nome": "3 spazi oggetti in più", "xp": 4},
	"scorta_xp": {"nome": "Scorta XP (5 XP = 1 Bonus elicottero)", "xp": 8},
}
const ORDINE_SBLOCCHI := ["unico", "cardio", "agilita", "armadietto", "spazi", "scorta_xp"]

## Luoghi e spazi.
const SPAZI := ["magazzino", "officina", "fase1", "fase2", "fase3"]
const NOMI_SPAZI := {"magazzino": "Magazzino", "officina": "Officina", "fase1": "Fase 1", "fase2": "Fase 2",
	"fase3": "Fase 3", "elicottero": "Elicottero"}
static func dentro(spazio: String) -> bool:
	return spazio == "magazzino" or spazio == "officina"

## Eventi del campo: tipo (attacco, ostacolo, istantaneo) e blocco (riguarda solo chi è dentro, nessuno cambia luogo).
const EVENTI := {
	"ev_incendio_caldaia": {"tipo": "ostacolo", "blocco": true},
	"ev_incendio": {"tipo": "ostacolo", "blocco": true},
	"ev_pazzo": {"tipo": "attacco", "blocco": true},
	"ev_filo_spinato": {"tipo": "ostacolo", "blocco": true},
	"ev_scienziato": {"tipo": "istantaneo"},
	"ev_fame": {"tipo": "ostacolo"},
	"ev_danno_caldaia": {"tipo": "istantaneo"},
	"ev_cane": {"tipo": "attacco"},
	"ev_congelamento": {"tipo": "istantaneo"},
	"ev_cane_rabbioso": {"tipo": "attacco"},
	"ev_paranoia_dadi": {"tipo": "istantaneo"},
	"ev_valanga": {"tipo": "ostacolo"},
	"ev_paranoia_carte": {"tipo": "istantaneo"},
	"ev_cosa": {"tipo": "attacco", "blocco": true},
	"ev_ombre": {"tipo": "istantaneo"},
	"ev_blackout": {"tipo": "ostacolo", "blocco": true},
}

## Turni della partita: per ogni fase 3 turni normali (4 nella partita lunga), il Pasto e il Sonno.
static func turni(lunga: bool) -> Array:
	var out := []
	for f in [1, 2, 3]:
		for i in (4 if lunga else 3):
			out.append({"fase": f, "tipo": "normale"})
		out.append({"fase": f, "tipo": "pasto"})
		out.append({"fase": f, "tipo": "sonno"})
	return out

static var _carte := {}
static func carte() -> Dictionary:
	if _carte.is_empty():
		var f := FileAccess.open("res://assets/dati/carte.json", FileAccess.READ)
		_carte = JSON.parse_string(f.get_as_text())
	return _carte

static func nome_carta(tipo: String) -> String:
	return str(carte()["tipi"].get(tipo, {}).get("nome", tipo))

static func testo_carta(tipo: String) -> String:
	return str(carte()["tipi"].get(tipo, {}).get("testo", ""))
