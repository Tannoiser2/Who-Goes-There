#!/usr/bin/env python3
"""Estrae dal modulo TTS di Who Goes There? (Deluxe) tutto il materiale usato dal gioco digitale.

Uso: python3 tools/estrai_tts.py CARTELLA_MOD_SCOMPATTATA CARTELLA_LAVORO
  CARTELLA_MOD_SCOMPATTATA  la cartella con Mods/ (il file .ttsmod è uno zip)
  CARTELLA_LAVORO           dove sono già stati estratti gli assetbundle (ex/) e le carte (carte/)

Produce, dentro assets/:
  carte/<mazzo>_<hash>.webp   illustrazione di ogni carta (il testo lo scrive il gioco, in italiano)
  carte/retro_<mazzo>.webp    il dorso di ogni mazzo
  dati/carte.json             composizione dei mazzi e testi
  pg/<pg>.webp                ritratto di ogni personaggio
  3d/*.glb                    tabelloni e miniature
  tessere/<tessera>.webp      tessere oggetto
"""
import json, os, re, sys, collections
from PIL import Image
import trimesh, numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from catalogo import TIPI, MAZZI

MOD, WORK = sys.argv[1], sys.argv[2]
REPO = os.path.join(os.path.dirname(__file__), '..')
A = os.path.join(REPO, 'assets')
EX = os.path.join(WORK, 'ex')
mazzi_src = json.load(open(os.path.join(WORK, 'mazzi.json')))

def webp(im, path, w=None, q=82):
    im = im.convert('RGBA') if im.mode in ('RGBA', 'LA', 'P') else im.convert('RGB')
    if w and im.width != w:
        im = im.resize((w, int(im.height * w / im.width)), Image.LANCZOS)
    im.save(path, 'WEBP', quality=q, method=6)

# ---------- carte ----------
os.makedirs(A + '/carte', exist_ok=True)
EVENTI = {'eventi'}
out = {'tipi': {}, 'mazzi': {}}
for k, (nome, testo, col) in TIPI.items():
    out['tipi'][k] = {'nome': nome, 'testo': testo, 'colore': col}
for mazzo, (src, mappa) in MAZZI.items():
    lista = []
    for p in mazzi_src[src]:
        h = p.rsplit('_', 1)[1][:8]
        tipo = mappa[h]
        img = f'{mazzo}_{h}'
        dst = f'{A}/carte/{img}.webp'
        if not os.path.exists(dst):
            im = Image.open(os.path.join(WORK, p)).convert('RGB')
            W, H = im.size
            if mazzo == 'vulnerabili':
                crop = im
            elif mazzo in EVENTI:
                crop = im.crop((0, 0, W, int(H * 0.625)))
            else:
                crop = im.crop((0, 0, W, int(H * 0.655)))
            webp(crop, dst, 300)
        lista.append({'tipo': tipo, 'img': img})
    out['mazzi'][mazzo] = lista
    print(mazzo, len(lista))
json.dump(out, open(A + '/dati/carte.json', 'w'), ensure_ascii=False, indent=0)

# ---------- ritratti ----------
os.makedirs(A + '/pg', exist_ok=True)
PG = {'garry': 'Garry_s_Board_29e1f8/Character Board_Garry.png', 'mcready': "McReady_s_Board_a0f19d/Character Board_McReady.png",
      'kinner': 'Kinner_s_Board_317687/Character Board_Kinner.png', 'copper': 'Dr_Copper_s_Board_eca76b/Character Board_Copper.png',
      'blair': 'Blair_s_Board_95a45e/Character Board_Blair.png', 'clark': 'Clark_s_Board_c452a7/Character Board_Clark.png',
      'vanwall': 'Van_Wall_s_Board_ffd26e/Character Board_Van Wall.png', 'norris': 'Norris_s_Board_297f1c/Character Board_Norris.png'}
for pg, f in PG.items():
    im = Image.open(os.path.join(EX, f)).convert('RGB')
    webp(im.crop((805, 255, 1215, 665)), f'{A}/pg/{pg}.webp', 320)
    # il ritratto grande sul retro della plancia (ruotato)
    big = im.crop((0, 1080, 790, 2010)).rotate(-90, expand=True)
    webp(big, f'{A}/pg/{pg}_grande.webp', 520)

# ---------- tessere ----------
os.makedirs(A + '/tessere', exist_ok=True)
T = os.path.join(EX, 'tiles')
for f in os.listdir(T):
    nome = f.replace('Tile ', '').replace(' Texture.png', '').lower().replace(' ', '_')
    im = Image.open(os.path.join(T, f)).convert('RGB')
    if nome in ('axe', 'flamethrower'):
        im = im.crop((0, 0, 168, 512)).rotate(-90, expand=True)  # tessere doppie (2 spazi)
    else:
        im = im.crop((0, 190, 256, 476))
    webp(im, f'{A}/tessere/{nome}.webp', 256 if nome not in ('axe', 'flamethrower') else 400)
# tessere uniche dei personaggi (sblocchi)
comp = Image.open(os.path.join(EX, 'Companion_Jack__3574c0/Tile Companion Texture.png')).convert('RGB')
webp(comp.crop((0, 190, 256, 476)), f'{A}/tessere/companion.webp', 256)
webp(comp.crop((256, 190, 512, 476)), f'{A}/tessere/companion_trained.webp', 256)

# ---------- dadi armadietto (facce) ----------
os.makedirs(A + '/ui', exist_ok=True)

# ---------- 3D ----------
os.makedirs(A + '/3d', exist_ok=True)
def glb_textured(obj, png, dst, scale=1.0, maxside=2048):
    m = trimesh.load(obj, force='mesh', process=False)
    tex = Image.open(png).convert('RGB')
    if max(tex.size) > maxside:
        tex = tex.resize((maxside, maxside))
    tex = tex.transpose(Image.FLIP_TOP_BOTTOM)  # le texture di Unity hanno l'origine in basso
    m.apply_scale(scale)
    uv = m.visual.uv
    m.visual = trimesh.visual.TextureVisuals(uv=uv, image=tex)
    m.export(dst)
def glb_colore(obj, rgb, dst, scale=1.0, facce=9000):
    m = trimesh.load(obj, force='mesh', process=True)
    if len(m.faces) > facce:
        import fast_simplification
        v, f = fast_simplification.simplify(m.vertices, m.faces, 1 - facce / len(m.faces))
        m = trimesh.Trimesh(v, f)
    m.apply_scale(scale)
    m.visual = trimesh.visual.ColorVisuals(m, face_colors=np.tile(np.array(list(rgb) + [255], dtype=np.uint8), (len(m.faces), 1)))
    m.export(dst)

glb_textured(EX + "/Inside_Board_ea4bd6/default.obj', EX + '/Inside_Board_ea4bd6/Camp Board UVs_Inside.png', A + '/3d/tabellone_dentro.glb', 0.01)
glb_textured(EX + '/Outside_Board_5e16fc/default.obj', EX + '/Outside_Board_5e16fc/Camp Board UVs_Outside.png', A + '/3d/tabellone_fuori.glb', 0.01)
# nell'assetbundle di ogni miniatura ci sono più mesh (anche il collisore): si prende la più grande
import UnityPy
BUNDLES = {v: k for k, v in json.load(open(os.path.join(WORK, 'bundles.json'))).items()}
def mesh_grande(cartella):
    env = UnityPy.load(os.path.join(MOD, 'Mods', BUNDLES[cartella]))
    best = None
    for o in env.objects:
        if o.type.name == 'Mesh':
            t = o.read().export()
            if best is None or t.count('\nf ') > best.count('\nf '):
                best = t
    open(os.path.join(EX, cartella, 'mini.obj'), 'w').write(best)
MINI = {'garry': 'Garry_b61873', 'mcready': 'McReady_2e77c4', 'kinner': 'Kinner_ebbb0d', 'copper': 'Dr_Copper_0bdd47',
        'blair': 'Blair_b4a673', 'clark': 'Clark_e474d7', 'vanwall': 'Van_Wall_263cf1', 'norris': 'Norris_9609c2'}
for pg, d in MINI.items():
    mesh_grande(d)
    png = [f for f in os.listdir(EX + '/' + d) if f.endswith('.png')][0]
    rgb = Image.open(EX + '/' + d + '/' + png).convert('RGB').getpixel((5, 5))
    glb_colore(EX + '/' + d + '/mini.obj', rgb, f'{A}/3d/mini_{pg}.glb', 0.01)
    print('mini', pg, rgb)
mesh_grande('Phase_Marker_6884d8')
glb_colore(EX + '/Phase_Marker_6884d8/mini.obj', (173, 174, 173), A + '/3d/segnalino_fase.glb', 0.01, 4000)
# sfondo dell'ambiente: pavimento per fase
for i in (1, 2, 3):
    webp(Image.open(EX + f'/Environment_4c7d19/Floor2_Phase{i}.png'), f'{A}/3d/pavimento_{i}.webp', 1024)
print('fatto')

# ---------- dorsi delle carte ----------
sys.path.insert(0, WORK)
from tts import d as TTS, fn as tts_fn, D as TTSD
src2m = {v[0]: k for k, v in MAZZI.items()}
fatti = set()
for o in TTS['ObjectStates']:
    if o['Name'] not in ('Deck', 'DeckCustom'):
        continue
    key = re.sub(r"[^a-z0-9]+", '_', o['Nickname'].lower()).strip('_')
    if key not in src2m or src2m[key] in fatti:
        continue
    cd = list(o['CustomDeck'].values())[0]
    im = Image.open(TTSD + '/' + tts_fn(cd['BackURL'])).convert('RGB').resize((300, 409))
    im.save(f'{A}/carte/retro_{src2m[key]}.webp', 'WEBP', quality=80)
    fatti.add(src2m[key])

# ---------- copertina (coperchio della scatola) ----------
box = Image.open(EX + '/Game_Box_f62624/8P Box Top.png').convert('RGB').crop((548, 604, 1516, 1590))
box.save(A + '/ui/copertina.webp', 'WEBP', quality=85)
box.resize((600, int(600 * box.height / box.width))).save(os.path.join(REPO, 'ludoteca', 'copertina.webp'), 'WEBP', quality=82)
