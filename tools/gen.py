#!/usr/bin/env python3
"""Regenerates Data.swift + sprites.bin + color.bin from the original sources. Needs Pillow. Run from the repo root: python3 tools/gen.py

Sources (cached in tools/.cache, not committed):
  - pwalk_gray.png: the real Pokéwalker greyscale sprites, ripped from the HGSS ROM (vgmoose.dev). 25 per row, national-dex
    order, each cell 64x48 frame A over frame B, 4 greys on a transparent ground; 0/85/170/255 = LCD shade 3/2/1/0 (black outline, white body), transparent = 0.
  - pwalk_color.png: the same sprites colourised by vgmoose with the exact HGSS palette colours, same layout, <= 15 colours a cell.
  - PokeAPI HGSS front sprites, normal + shiny: same pixels, other palette, so pixel pairs give each species' normal -> shiny map.
  - Serebii's Pokéwalker course page: per course 6 Pokémon (groups A/B/C x 2) + 10 items, with min steps and chances.
  - PokeAPI CSVs: Korean names, Gen IV types (pokemon_types_past overrides the Fairy retcon).

The walker's own draw: for each of the 3 carried Pokémon, rarest first, "steps >= min and rand(100) < chance" wins, else the
next; the commonest is the fallback. Serebii prints the resulting band percentages; chance = the slot's % in the first band
where it appears, which reproduces every printed row (e.g. A 70 -> B (1-.7)*75 = 22.5 -> C 7.5).
"""
import csv, json, os, re, html, urllib.request
from PIL import Image

CACHE = os.path.join(os.path.dirname(__file__), '.cache')
API = 'https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/'
SRC = {
    'pwalk_gray.png': 'https://vgmoose.dev/posts/29263141%20-%20Extracting%20and%20colorizing%20Pokewalker%20Sprites!.post/pwalk_gray.png',
    'pwalk_color.png': 'https://vgmoose.dev/posts/29263141%20-%20Extracting%20and%20colorizing%20Pokewalker%20Sprites!.post/pwalk_color.png',
    **{f'hgss/{s}{i}.png': f'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/heartgold-soulsilver/{"shiny/" if s else ""}{i}.png'
       for i in range(1, 494) for s in ('', 's')},
    # PokeAPI's HGSS shiny 422/423 (West Sea) is a copy of the normal file; Platinum's pair is right and uses the same palette
    **{f'plat/{s}{i}.png': f'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/platinum/{"shiny/" if s else ""}{i}.png'
       for i in (422, 423) for s in ('', 's')},
    'serebii.html': 'https://www.serebii.net/heartgoldsoulsilver/pokewalker-area.shtml',
    **{f + '.csv': API + f + '.csv' for f in ['pokemon_species_names', 'item_names', 'pokemon_types', 'pokemon_types_past', 'types',
                                              'pokemon_evolution', 'pokemon_species', 'experience', 'items', 'type_names']},
}
N = 493  # HGSS national dex

def get(name):
    p = os.path.join(CACHE, name)
    if not os.path.exists(p):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        req = urllib.request.Request(SRC[name], headers={'User-Agent': 'Mozilla/5.0'})
        open(p, 'wb').write(urllib.request.urlopen(req).read())
    return p

# --- sprites.bin: 493 x 2 frames x 64x48, 2 bpp, 4 px per byte, leftmost pixel in the high bits. 768 B per frame.
im = Image.open(get('pwalk_gray.png')).convert('RGBA')
out = bytearray()
for dex in range(1, N + 1):
    cx, cy = (dex - 1) % 25 * 64, (dex - 1) // 25 * 96
    for f in range(2):
        for y in range(48):
            for x in range(0, 64, 4):
                b = 0
                for i in range(4):
                    r, g, bl, a = im.getpixel((cx + x + i, cy + f * 48 + y))
                    b = b << 2 | (3 - round(r / 85) if a else 0)   # the sheet is black-on-white: black outline = 3, white body = 0 (blank)
                out.append(b)
open('sprites.bin', 'wb').write(out)

# --- color.bin: per species 15 normal + 15 shiny RGB (index 1...15; 0 = transparent), then 2 frames x 64x48 at 4 bpp (high nibble = left).
# 3162 B per species. A walker colour the HGSS sprite doesn't use (vgmoose's blends) takes the shift of its nearest HGSS colour.
col = Image.open(get('pwalk_color.png')).convert('RGBA')
cout = bytearray()
for dex in range(1, N + 1):
    cx, cy = (dex - 1) % 25 * 64, (dex - 1) // 25 * 96
    px = [[col.getpixel((cx + x, cy + y)) for x in range(64)] for y in range(96)]
    pal = sorted({p[:3] for r in px for p in r if p[3]})
    assert len(pal) <= 15, (dex, len(pal))
    src = 'plat' if open(get(f'hgss/{dex}.png'), 'rb').read() == open(get(f'hgss/s{dex}.png'), 'rb').read() else 'hgss'
    a, s = Image.open(get(f'{src}/{dex}.png')).convert('RGBA'), Image.open(get(f'{src}/s{dex}.png')).convert('RGBA')
    votes = {}
    for y in range(a.height):
        for x in range(a.width):
            p, q = a.getpixel((x, y)), s.getpixel((x, y))
            if p[3] and q[3]: votes.setdefault(p[:3], {}).setdefault(q[:3], 0); votes[p[:3]][q[:3]] += 1
    shift = {k: max(v, key=v.get) for k, v in votes.items()}
    def shiny(c):
        if c in shift or not shift: return shift.get(c, c)
        n = min(shift, key=lambda k: sum((i - j) ** 2 for i, j in zip(k, c)))
        return tuple(max(0, min(255, c[i] + shift[n][i] - n[i])) for i in range(3))
    pal += [(0, 0, 0)] * (15 - len(pal))
    for c in pal: cout += bytes(c)
    for c in pal: cout += bytes(shiny(c))
    idx = {c: i + 1 for i, c in enumerate(pal)}
    for y in range(96):
        for x in range(0, 64, 2):
            l, r = px[y][x], px[y][x + 1]
            cout.append((idx[l[:3]] if l[3] else 0) << 4 | (idx[r[:3]] if r[3] else 0))
open('color.bin', 'wb').write(cout)

# --- names / types
ko, en_item, ko_item, types = {}, {}, {}, {}
for r in csv.DictReader(open(get('pokemon_species_names.csv'))):
    if r['local_language_id'] == '3' and int(r['pokemon_species_id']) <= N: ko[int(r['pokemon_species_id'])] = r['name']
for r in csv.DictReader(open(get('item_names.csv'))):
    if r['local_language_id'] == '9': en_item[r['name'].lower().replace('é', 'e')] = r['item_id']
    if r['local_language_id'] == '3': ko_item[r['item_id']] = r['name']
tname = {r['id']: r['identifier'] for r in csv.DictReader(open(get('types.csv')))}
for r in csv.DictReader(open(get('pokemon_types.csv'))):
    if int(r['pokemon_id']) <= N: types.setdefault(int(r['pokemon_id']), []).append(tname[r['type_id']])
past = {}
for r in csv.DictReader(open(get('pokemon_types_past.csv'))):
    if int(r['pokemon_id']) <= N and int(r['generation_id']) >= 4: past.setdefault(int(r['pokemon_id']), []).append(tname[r['type_id']])
types.update(past)
assert len(ko) == N and len(types) == N

ITEM_FIX = {'EnergyPowder': 'Energy Powder', 'Moonstone': 'Moon Stone', 'Tomato Berry': 'Tamato Berry', 'X Special': 'X Sp. Atk',
            'PokéDoll': 'Poke Doll', 'SilverPowder': 'Silver Powder', 'X Defend': 'X Defense', 'Parlyz Heal': 'Paralyze Heal', 'TinyMushroom': 'Tiny Mushroom'}
def item_ko(n):
    m = re.match(r'TM(\d+)', n)
    if m: return '기술머신' + m.group(1)
    return ko_item[en_item[ITEM_FIX.get(n, n).lower().replace('é', 'e')]]

# --- courses (the 20 regular ones; the event courses need things this app can't do)
KO = {'Refreshing Field': '상쾌한 들판', 'Noisy Forest': '웅성웅성 숲', 'Rugged Road': '울퉁불퉁 산길', 'Beautiful Beach': '아름다운 해변',
      'Suburban Area': '교외', 'Dim Cave': '어둑어둑 동굴', 'Blue Lake': '푸른 호수', 'Town Outskirts': '마을 변두리', 'Hoenn Field': '호연 들판',
      'Warm Beach': '따뜻한 해변', 'Volcano Path': '화산 길', 'Treehouse': '나무 위 집', 'Scary Cave': '무서운 동굴', 'Sinnoh Field': '신오 들판',
      'Icy Mountain Rd.': '얼음 산길', 'Big Forest': '커다란 숲', 'White Lake': '하얀 호수', 'Stormy Beach': '거친 해변', 'Resort': '리조트', 'Quiet Cave': '고요한 동굴'}
ART = {'Field': 'field', 'Forest': 'forest', 'Treehouse': 'forest', 'Road': 'mountain', 'Path': 'mountain', 'Beach': 'beach', 'Lake': 'lake',
       'Area': 'town', 'Outskirts': 'town', 'Resort': 'town', 'Cave': 'cave', 'Rd.': 'mountain'}
t = open(get('serebii.html'), encoding='latin-1').read()
t = re.sub(r'<(script|style).*?</\1>', '', t, flags=re.S)
t = re.sub(r'<[^>]+>', ' ', t); t = html.unescape(t)
L = [re.sub(r'\s+', ' ', l).strip() for l in t.split('\n')]; L = [l for l in L if l]
starts = [i for i, l in enumerate(L) if l.startswith('Unlock Criterea')][:20]
TYPES = 'normal fire water grass electric ice fighting poison ground flying psychic bug rock ghost dragon dark steel'.split()
courses = []
for k, s in enumerate(starts):
    sec = L[s - 10:starts[k + 1] if k + 1 < len(starts) else s + 190]
    name = re.sub(r'\s*[぀-ヿ一-鿿].*', '', L[max(i for i in range(s - 10, s) if L[i].startswith('Location')) - 1])
    ctypes = [x.strip(' ,').lower() for x in L[s - 10:s] if x.strip(' ,').lower() in TYPES]
    m = re.search(r'(\d+) Watts', L[s]); watts = int(m.group(1)) if m else 0
    mons = [(int(a), g == '♀') for l in sec for a, g in re.findall(r'^#(\d+) [A-Z].*?(?: ([♀♂]))?$', l)]
    lv = [int(x) for l in sec if l.startswith('Level') for x in re.findall(r'Level (\d+)', l)]
    st = [int(re.match(r'(\d+)\+ Steps', l).group(1)) for l in sec if re.fullmatch(r'\d+\+ Steps', l)]
    rows = [re.findall(r'(\d+)\+ St: ([\d.]+)%', l) for l in sec if 'St:' in l]
    assert len(mons) == 6 and len(lv) == 6 and len(st) == 16, (name, mons, lv, st)
    # chance per slot: the % printed at the slot's own threshold in the first band it appears (A: last band, B: middle band)
    a = [float(rows[0][2][1]), float(rows[1][2][1])]
    bpairs = []
    for r in rows[2:]:
        p = (int(r[1][0]), float(r[1][1]))
        if float(r[0][1]) == 0 and p not in bpairs: bpairs.append(p)
    b = [next((c for th, c in bpairs if th == st[2]), bpairs[0][1]), next((c for th, c in reversed(bpairs) if th == st[3]), bpairs[-1][1])]
    chance = [a[0], a[1], b[0], b[1], 100, 100]
    ii = sec.index('Items'); j = ii + 13; items = []
    for n in range(10):
        nm = sec[j]; pc = [int(x.rstrip('%')) for x in sec[j + 1:j + 11]]; j += 11
        first = next(i for i, p in enumerate(pc) if p)
        items.append((item_ko(nm), st[6 + first], pc[first]))
    # check: every printed B row at the A band = (1 - A chance) * B chance for some A/B pair of this course
    for r in rows[2:]:
        if float(r[0][1]) == 0:
            assert any(abs((1 - av / 100) * bv - float(r[2][1])) < 0.6 for av in a for bv in b), (name, r, a, b)
    art = next(v for k2, v in ART.items() if name.endswith(k2) or name == k2)
    courses.append(dict(name=KO[name], watts=watts, types=ctypes, art=art,
                        slots=[(mons[i][0], lv[i], st[i], chance[i], mons[i][1]) for i in range(6)], items=items))

def s(x): return '"' + x.replace('"', '\\"') + '"'

# --- growth + evolutions. 1 step = 1 EXP (the HGSS Pokéwalker rule). Evolution methods as in Gen IV, mapped onto a walker:
#   friendship / beauty -> steps walked together; "knows move X" -> the level it learns X; special places -> course kinds;
#   stones and held items come from the bag; trade -> Connect while it's the companion. Alt-form / regional rows are dropped.
sp = {int(r['id']): r for r in csv.DictReader(open(get('pokemon_species.csv')))}
growth = [0] + [int(sp[i]['growth_rate_id']) for i in range(1, N + 1)]
exp = {}
for r in csv.DictReader(open(get('experience.csv'))): exp.setdefault(int(r['growth_rate_id']), {})[int(r['level'])] = int(r['experience'])
item_id = {r['id']: r['identifier'] for r in csv.DictReader(open(get('items.csv')))}
MOVE_LEVEL = {424: 32, 469: 33, 463: 33, 465: 33, 473: 33, 185: 17, 122: 18}      # Aipom Yanma Lickitung Tangela Piloswine Bonsly Mime Jr.
PLACE = {462: 'cave', 476: 'cave', 470: 'forest', 471: 'ice'}
evos = set()
for r in csv.DictReader(open(get('pokemon_evolution.csv'))):
    to = int(r['evolved_species_id'])
    if to > N or r['region_id'] or int(r['evolved_pokemon_form_id'] or 0) > 10000 or int(r['required_pokemon_form_id'] or 0) > 10000: continue
    frm = int(sp[to]['evolves_from_species_id'])
    trig = {'1': 'level', '2': 'trade', '3': 'item'}.get(r['evolution_trigger_id'])
    if not trig: continue                                                                   # shed (Shedinja)
    way, level = trig, int(r['minimum_level'] or 0)
    if trig == 'level' and (r['minimum_happiness'] or r['minimum_beauty']): way = 'friend'
    if r['known_move_id']: level = MOVE_LEVEL[to]
    item = r['trigger_item_id'] or r['held_item_id']
    item = ko_item.get(item) if item else None
    fem = {'1': 'true', '2': 'false'}.get(r['gender_id'], 'nil')
    time = r['time_of_day'] or None
    place = PLACE.get(to) if r['location_id'] else None
    party = int(r['party_species_id']) if r['party_species_id'] else None
    if r['location_id'] and not place: continue
    evos.add((frm, to, way, level, item, fem, time, place, party))
evos = sorted(evos)
tko = {}
for r in csv.DictReader(open(get('type_names.csv'))):
    if r['local_language_id'] == '3': tko[tname[r['type_id']]] = r['name']

with open('Data.swift', 'w') as f:
    f.write('// Generated by tools/gen.py from the HGSS Pokéwalker data (Serebii) and PokeAPI. Do not edit by hand.\n\n')
    f.write('let monNames: [String] = ["", ' + ', '.join(s(ko[i]) for i in range(1, N + 1)) + ']\n')
    f.write('let monTypes: [[String]] = [[], ' + ', '.join('[' + ', '.join(s(x) for x in types[i]) + ']' for i in range(1, N + 1)) + ']\n\n')
    f.write('let growthRate: [Int] = [' + ', '.join(map(str, growth)) + ']\n')
    f.write('let expTable: [[Int]] = [[], ' + ', '.join('[0, ' + ', '.join(str(exp[g][l]) for l in range(1, 101)) + ']' for g in range(1, 7)) + ']   // [rate][level]\n')
    f.write('let typeKo: [String: String] = [' + ', '.join(f'{s(k)}: {s(v)}' for k, v in sorted(tko.items()) if k in TYPES) + ']\n')
    f.write('let evolutions: [Evo] = [\n')
    for frm, to, way, level, item, fem, time, place, party in evos:
        f.write(f'    Evo(from: {frm}, to: {to}, way: .{way}, level: {level}, item: {s(item) if item else "nil"}, female: {fem}, time: {s(time) if time else "nil"}, place: {s(place) if place else "nil"}, party: {party or "nil"}),\n')
    f.write(']\n\n')
    f.write('let courses: [Course] = [\n')
    for c in courses:
        f.write(f'    Course(name: {s(c["name"])}, watts: {c["watts"]}, types: [{", ".join(s(x) for x in c["types"])}], art: .{c["art"]},\n')
        f.write('           slots: [' + ', '.join(f'Slot(dex: {d}, level: {l}, steps: {st}, chance: {ch:g}, female: {str(fe).lower()})' for d, l, st, ch, fe in c['slots']) + '],\n')
        f.write('           items: [' + ', '.join(f'Find(item: {s(n)}, steps: {st}, chance: {ch})' for n, st, ch in c['items']) + ']),\n')
    f.write(']\n')
print('ok', len(courses), 'courses,', len(out), 'sprite bytes')
