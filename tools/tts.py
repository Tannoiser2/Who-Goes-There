import json,re,os,sys
import os
D=os.path.join(os.environ.get('TTS_MOD', '/home/claude/src'), 'Mods')
d=json.load(open(D+'/Workshop/1828454091.json'))
def fn(url):
    if not url: return None
    k=re.sub(r'[^A-Za-z0-9]','',url)
    m=re.search(r'ugc(.*)',k)
    if m: k=m.group(1)
    for sub in ('Images','Assetbundles','Models'):
        p=os.path.join(D,sub)
        if not os.path.isdir(p): continue
        for f in os.listdir(p):
            if f.rsplit('.',1)[0].endswith(k): return sub+'/'+f
    return 'MISSING:'+url
def allobj(objs,path=''):
    for o in objs:
        yield path,o
        if 'ContainedObjects' in o: yield from allobj(o['ContainedObjects'],path+'/'+(o.get('Nickname') or o['Name']))
