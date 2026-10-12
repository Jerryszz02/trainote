#!/usr/bin/env python3
"""Reproduce bundled native anatomy data from the pinned MIT upstream (no runtime network)."""
import json, math, re, urllib.request
from pathlib import Path
SHA = '107dafe86f91298d66a41ff1c7b7251b073983d8'
BASE = f'https://raw.githubusercontent.com/crmapache/js-rich-body-highlighter/{SHA}/'
OUT = Path(__file__).resolve().parents[1] / 'Trainote/Resources/BodyMap'
GROUPS = {'abs': 'core', 'obliques': 'core', 'lats': 'back', 'upper_back': 'back', 'lower_back': 'back'}

def commands(d, offset):
    tokens = re.findall(r'[MmLlHhVvCcSsZz]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?', d)
    # Ensure tokenization did not silently ignore an unsupported SVG command.
    assert not re.sub(r'[\s,]', '', re.sub(r'[MmLlHhVvCcSsZz]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?', '', d))
    x = y = 0; start = (0, 0); previous = None; control = None; result = []; i = 0
    while i < len(tokens):
        if tokens[i].isalpha(): cmd = tokens[i]; i += 1
        if cmd.lower() == 'z':
            result.append([0]); x, y = start; previous = cmd; control = None; continue
        count = {'m':2, 'l':2, 'h':1, 'v':1, 'c':6, 's':4}[cmd.lower()]
        values = [float(v) for v in tokens[i:i+count]]; assert len(values) == count
        i += count; relative = cmd.islower(); kind = cmd.lower()
        def point(a,b): return (a+x if relative else a, b+y if relative else b)
        if kind in ['m','l']:
            p = point(*values); result.append([1 if kind == 'm' else 2,*p]); x,y = p
            if kind == 'm': start = p; cmd = 'l' if relative else 'L'
            control = None
        elif kind in ['h','v']:
            p = ((x+values[0] if relative else values[0]),y) if kind == 'h' else (x,(y+values[0] if relative else values[0]))
            result.append([2,*p]); x,y = p; control = None
        else:
            if kind == 'c': a,b,p = point(*values[:2]),point(*values[2:4]),point(*values[4:])
            else:
                a = (2*x-control[0],2*y-control[1]) if previous and previous.lower() in ['c','s'] and control else (x,y)
                b,p = point(*values[:2]),point(*values[2:])
            result.append([3,*a,*b,*p]); x,y = p; control = b
        previous = kind
    for item in result:
        for j in range(1,len(item),2): item[j] = round(item[j]+offset[0]*25.4/96,5); item[j+1] = round(item[j+1]+offset[1]*25.4/96,5)
        assert all(math.isfinite(v) for v in item)
    return result

masks = []
for side, filename in [('front','01_male_front_white_transparent.png'),('back','02_male_back_white_transparent.png')]:
    source = urllib.request.urlopen(BASE+f'src/data/muscles/{side}.ts').read().decode()
    for block in re.findall(r'\{\s*id:.*?\n  \}',source,re.S):
        def field(name): return re.search(r"\b"+name+r": '([^']+)'",block).group(1)
        if field('gender') != 'male': continue
        offset = re.search(r'offset: \{ x: ([-\d.]+), y: ([-\d.]+) \}',block)
        xy = tuple(map(float,offset.groups())) if offset else (0,0)
        d = re.search(r"\n    d: '([^']+)'",block).group(1)
        group = field('group')
        masks.append({'id':field('id'),'muscle':GROUPS.get(group,group),'side':side,'commands':commands(d,xy)})
    (OUT/f'anatomy-{side}.png').write_bytes(urllib.request.urlopen(BASE+'assets-src/'+filename).read())
(OUT/'anatomy-masks.json').write_text(json.dumps({'version':1,'width':1365*25.4/96,'height':2048*25.4/96,'masks':masks},separators=(',',':'))+'\n')
(OUT/'ANATOMY-LICENSE.txt').write_bytes(urllib.request.urlopen(BASE+'LICENSE').read())
print(f'Imported {len(masks)} masks: {sorted(set(m["muscle"] for m in masks))}')
