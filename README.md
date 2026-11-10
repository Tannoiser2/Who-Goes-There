# Who Goes There? - versione digitale

Versione digitale non ufficiale, per uso personale, di **Who Goes There?** (Certifiable Studios, edizione Deluxe con
tutti gli 8 personaggi), il cooperativo «finché dura» ispirato al racconto di John W. Campbell da cui nasce *La Cosa*.

Si gioca qui: https://tannoiser2.github.io/Who-Goes-There/

## Cosa c'è

- **Regole complete** del gioco base Deluxe: 15 turni (18 nella partita lunga) in 3 Fasi, Pasto e Sonno, cali di
  temperatura, eventi del campo (Attacchi, Ostacoli, Istantanei, Blocco), Caldaia e Porta, Falò, mazzi
  Magazzino/Officina/Specialità e mazzi Fase, cassette, Bonus elicottero, costruzione e aggiornamento delle tessere
  oggetto, sblocchi con gli XP (abilità unica, Cardio, Agilità, dado dell'armadietto, spazi oggetti, Scorta XP),
  Ferite e Ferite critiche, carte Vulnerabili, segnalatori di infezione negli scambi e nel Sonno, Ospite e Attacco
  d'infezione, Esame del sangue e Test dell'Ospite, assalti, turno dell'elicottero con imbarco, rivelazione e partenza.
- **Gli 8 personaggi** con le loro abilità, i loro mazzi Specialità, i punti di riferimento (Dispensa, Offro io,
  Banco da lavoro, Cassetta attrezzi, Stazione medica, Sella) e Jack, il cane di Clark.
- **IA** per tutti i personaggi non giocati: gli umani si armano, esplorano, curano, si scambiano carte e sospettano di
  chi ha troppe carte Vulnerabili o si comporta in modo strano; chi è stato assimilato dalla Cosa si comporta come un
  umano, contagia quando conviene, mente nelle dichiarazioni e cerca di salire sull'elicottero.
- **Tavolo 3D** con i tabelloni, le miniature dei personaggi, i mazzi e l'evento del campo presi dal modulo di
  Tabletop Simulator; si gira trascinando e si avvicina con la rotella (o coi pulsanti, sul tablet).
- **Carte ricomposte in italiano**: illustrazione originale, nome e testo tradotti.
- **Online** con gli amici (stanze con codice di 4 lettere su Firebase, i posti vuoti li guida l'IA) e **salvataggio**
  della partita contro l'IA su Firebase (e sul dispositivo).
- **Scambi** come nel regolamento: uno scambio fra due giocatori resta aperto per tutto il turno, chi riceve paga
  1 Azione una volta sola e il segnalatore passa una volta sola; si può annunciare agli altri cosa ti serve.
- **Modalità clemente** facoltativa: eventi e attacchi della Cosa chiedono un Successo in meno.

## Semplificazioni rispetto al regolamento

- La carta «Prendere il comando» di Garry non si può giocare (servirebbe intervenire durante il tiro di un altro).
- La «Difesa del campo» non permette di guardare il prossimo evento spendendo 1 XP.
- Nel turno dell'elicottero non c'è la discussione libera: il capo decide, chi è a bordo può scendere.
- Il capo è sempre il personaggio di grado più alto (non si può cedere il comando).

## Struttura

- `scripts/motore.gd` – le regole: tutto lo stato in un dizionario, decisioni numerate (stessa sequenza = stessa partita).
- `scripts/ia.gd` – l'intelligenza artificiale (sospetti, bluff della Cosa, strategia di turno).
- `scripts/dati.gd` – personaggi, tessere, ricette, eventi; `assets/dati/carte.json` – mazzi e testi italiani.
- `scripts/plancia3d.gd` – il tavolo 3D; `scripts/main.gd` – menu e interfaccia; `scripts/rete.gd` – Firebase.
- `tools/estrai_tts.py` (+ `catalogo.py`, `tts.py`) – estrae carte, tabelloni, miniature e tessere dal modulo TTS.
- `tools/controlla_glifi.py` – controlla che ogni carattere dei testi esista nei font.
- `firebase/database.rules.json` – regole del database (radice `whogoesthere`, da unire a quelle del progetto condiviso).

## Prove

```
godot --headless --path . -s res://tests/sim.gd -- 30 5        # 30 partite tutte IA da 5 giocatori
FACILE=1 godot --headless --path . -s res://tests/sim.gd -- 30 5
xvfb-run godot --path . -s res://tests/foto.gd -- partita 2    # screenshot dell'interfaccia
python3 tests/firebase_mock.py 8765 &                          # finto Firebase per la prova online
```

## Pubblicazione

Il workflow `Pubblica` parte a mano (Actions → Pubblica → Run workflow) oppure con un commit che contiene `[pubblica]`.
