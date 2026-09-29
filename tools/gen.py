#!/usr/bin/env python3
"""Regenerates Sources/Data/{Data,BattleData}.swift + Resources/{hgss,icons}.bin from the original sources. Needs Pillow. Run from the repo root: python3 tools/gen.py

Sources (cached in tools/.cache, not committed):
  - PokeAPI HGSS battle sprites, front + back, normal + shiny: same pixels, other palette, so pixel pairs give each species' normal -> shiny map.
  - PokeAPI Gen IV icons (the HGSS box / party icons, 32x32) for the 도감 and 상자 grids.
  - Serebii's Pokéwalker course page: per course 6 Pokémon (groups A/B/C x 2) + 10 items, with min steps and chances.
  - PokeAPI CSVs: Korean names, Gen IV types (pokemon_types_past overrides the Fairy retcon).

The walker's own draw: for each of the 3 carried Pokémon, rarest first, "steps >= min and rand(100) < chance" wins, else the
next; the commonest is the fallback. Serebii prints the resulting band percentages; chance = the slot's % in the first band
where it appears, which reproduces every printed row (e.g. A 70 -> B (1-.7)*75 = 22.5 -> C 7.5).
"""
import csv, json, os, re, html, urllib.request, warnings
from PIL import Image
warnings.filterwarnings('ignore', category=DeprecationWarning)   # Pillow 12: getdata

CACHE = os.path.join(os.path.dirname(__file__), '.cache')
API = 'https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/'
SRC = {
    **{f'hgss/{s}{i}.png': f'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/heartgold-soulsilver/{"shiny/" if s else ""}{i}.png'
       for i in range(1, 494) for s in ('', 's')},
    **{f'hgss/b{s}{i}.png': f'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/heartgold-soulsilver/back/{"shiny/" if s else ""}{i}.png'
       for i in range(1, 494) for s in ('', 's')},
    **{f'icons/{i}.png': f'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/icons/{i}.png' for i in range(1, 494)},
    # PokeAPI's HGSS shiny 422/423 (West Sea) are copies of the normal files; Platinum's front pair is right (its back pair is a copy too)
    **{f'plat/{s}{i}.png': f'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/platinum/{"shiny/" if s else ""}{i}.png'
       for i in (422, 423) for s in ('', 's')},
    'serebii.html': 'https://www.serebii.net/heartgoldsoulsilver/pokewalker-area.shtml',
    **{f + '.csv': API + f + '.csv' for f in ['pokemon_species_names', 'item_names', 'pokemon_types', 'pokemon_types_past', 'types',
                                              'pokemon_evolution', 'pokemon_species', 'experience', 'items', 'type_names', 'pokemon_habitats',
                                              'pokemon_stats', 'pokemon', 'moves', 'move_names', 'pokemon_moves', 'type_efficacy', 'type_efficacy_past',
                                              'version_groups', 'move_changelog', 'pokemon_stats_past',
                                              'move_meta', 'move_meta_stat_changes', 'move_meta_ailments', 'move_flag_map', 'abilities', 'ability_names',
                                              'pokemon_abilities', 'pokemon_abilities_past', 'natures', 'nature_names']},
}
N = 493  # HGSS national dex

def get(name):
    p = os.path.join(CACHE, name)
    if not os.path.exists(p):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        req = urllib.request.Request(SRC[name], headers={'User-Agent': 'Mozilla/5.0'})
        open(p, 'wb').write(urllib.request.urlopen(req).read())
    return p

# --- hgss.bin: the HGSS battle sprites, drawn one pixel a point. Per species: 15 normal + 15 shiny RGB (index 1...15; 0 = transparent),
# then the front and the back, 80x80 at 4 bpp (high nibble = left). 6490 B per species. Each frame is moved down to stand on its bottom
# row (PokeAPI keeps the DS's per-species offsets; the walker has no offset table). A colour slot is a (normal, shiny) pair: two DS
# slots can share a normal colour and part in the shiny.
def rgba(name): return Image.open(get(name)).convert('RGBA')
def dist(a, b): return sum((i - j) ** 2 for i, j in zip(a, b))
hout, over15 = bytearray(), []
for dex in range(1, N + 1):
    imgs = [(rgba(f'hgss/{b}{dex}.png'), rgba(f'hgss/{b}s{dex}.png')) for b in ('', 'b')]
    for a, sh in imgs: assert a.size == (80, 80) == sh.size, (dex, a.size)
    shiny = lambda p, q: q[:3] if q[3] >= 128 else p[:3]
    if all(a.tobytes() == sh.tobytes() for a, sh in imgs):
        # PokeAPI's HGSS shiny 422/423 (West Sea) are copies of the normal files, and so is Platinum's back pair: the normal -> shiny
        # map comes from Platinum's front pair, its colours snapped to HGSS's; a colour it never shows takes its nearest one's shift
        normals = {p[:3] for a, _ in imgs for p in a.getdata() if p[3] >= 128}
        votes = {}
        for p, q in zip(rgba(f'plat/{dex}.png').getdata(), rgba(f'plat/s{dex}.png').getdata()):
            if p[3] >= 128 and q[3] >= 128:
                n = min(normals, key=lambda k: dist(k, p[:3])); votes.setdefault(n, {}).setdefault(q[:3], 0); votes[n][q[:3]] += 1
        remap = {n: max(v, key=v.get) for n, v in votes.items()}
        for n in normals - remap.keys():
            m = min(remap, key=lambda k: dist(k, n)); remap[n] = tuple(max(0, min(255, c + s - o)) for c, s, o in zip(n, remap[m], m))
        shiny = lambda p, q: remap[p[:3]]
    count = {}
    for a, sh in imgs:
        for p, q in zip(a.getdata(), sh.getdata()):
            if p[3] >= 128: k = (p[:3], shiny(p, q)); count[k] = count.get(k, 0) + 1
    slots = sorted(count, key=lambda k: -count[k])[:15]                     # a DS palette is 15 colours; more (rare) snap to the nearest
    if len(count) > 15: over15.append(dex)
    index = {k: slots.index(k) + 1 if k in slots else 1 + min(range(len(slots)), key=lambda i: dist(slots[i][0], k[0]) + dist(slots[i][1], k[1])) for k in count}
    for n, _ in slots + [((0, 0, 0), 0)] * (15 - len(slots)): hout += bytes(n)
    for _, s in slots + [(0, (0, 0, 0))] * (15 - len(slots)): hout += bytes(s)
    for a, sh in imgs:
        px, qx = list(a.getdata()), list(sh.getdata())
        drop = 79 - max(y for y in range(80) if any(px[y * 80 + x][3] >= 128 for x in range(80)))   # onto the bottom row
        cell = lambda x, y: 0 if y < drop or px[(y - drop) * 80 + x][3] < 128 else index[(px[(y - drop) * 80 + x][:3], shiny(px[(y - drop) * 80 + x], qx[(y - drop) * 80 + x]))]
        for y in range(80):
            for x in range(0, 80, 2): hout.append(cell(x, y) << 4 | cell(x + 1, y))
assert len(hout) == N * 6490
if over15: print('palette snapped (> 15 colour pairs):', over15)
open('Resources/hgss.bin', 'wb').write(hout)

# --- icons.bin: the Gen IV box / party icons (the 도감 and 상자 grids), one pixel a point. Per species: 15 RGB (index 1...15; 0 =
# transparent), then 32x32 at 4 bpp (high nibble = left). 557 B per species. A DS icon palette is 16 colours, so 15 opaque always fit.
iout = bytearray()
for dex in range(1, N + 1):
    a = rgba(f'icons/{dex}.png'); assert a.size == (32, 32), (dex, a.size)
    px = list(a.getdata()); pal = sorted({p[:3] for p in px if p[3] >= 128})
    assert 0 < len(pal) <= 15, (dex, len(pal))
    for c in pal + [(0, 0, 0)] * (15 - len(pal)): iout += bytes(c)
    cell = lambda p: pal.index(p[:3]) + 1 if p[3] >= 128 else 0
    for k in range(0, 1024, 2): iout.append(cell(px[k]) << 4 | cell(px[k + 1]))
assert len(iout) == N * 557
open('Resources/icons.bin', 'wb').write(iout)

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

ITEM_FIX = {'EnergyPowder': 'Energy Powder', 'Thunderstone': 'Thunder Stone', 'BlackGlasses': 'Black Glasses', 'NeverMeltIce': 'Never-Melt Ice', 'TwistedSpoon': 'Twisted Spoon', 'DeepSeaScale': 'Deep Sea Scale', 'DeepSeaTooth': 'Deep Sea Tooth', 'BrightPowder': 'Bright Powder', 'SilphScope': 'Silph Scope', 'Moonstone': 'Moon Stone', 'Tomato Berry': 'Tamato Berry', 'X Special': 'X Sp. Atk',
            'PokéDoll': 'Poke Doll', 'SilverPowder': 'Silver Powder', 'X Defend': 'X Defense', 'Parlyz Heal': 'Paralyze Heal', 'TinyMushroom': 'Tiny Mushroom'}
def item_ko(n):
    m = re.match(r'TM(\d+)', n)
    if m: return '기술머신' + m.group(1)
    key = lambda x: re.sub(r'[^a-z]', '', x.lower().replace('é', 'e'))                 # "ThunderStone" == "Thunder Stone"
    loose = {key(k): v for k, v in en_item.items()}
    return ko_item[en_item.get(ITEM_FIX.get(n, n).lower().replace('é', 'e')) or loose[key(ITEM_FIX.get(n, n))]]

# --- courses: the 20 regular ones (unlocked by lifetime watts) + the 7 event ones, which here unlock by Pokédex count instead
KO = {'Refreshing Field': '상쾌한 들판', 'Noisy Forest': '웅성웅성 숲', 'Rugged Road': '울퉁불퉁 산길', 'Beautiful Beach': '아름다운 해변',
      'Suburban Area': '교외', 'Dim Cave': '어둑어둑 동굴', 'Blue Lake': '푸른 호수', 'Town Outskirts': '마을 변두리', 'Hoenn Field': '호연 들판',
      'Warm Beach': '따뜻한 해변', 'Volcano Path': '화산 길', 'Treehouse': '나무 위 집', 'Scary Cave': '무서운 동굴', 'Sinnoh Field': '신오 들판',
      'Icy Mountain Rd.': '얼음 산길', 'Big Forest': '커다란 숲', 'White Lake': '하얀 호수', 'Stormy Beach': '거친 해변', 'Resort': '리조트', 'Quiet Cave': '고요한 동굴',
      'Beyond the Sea': '바다 건너편', 'Night Skys Edge': '밤하늘의 끝', 'Yellow Forest': '노란 숲', 'Rally': '랠리', 'Sightseeing': '쇼핑',
      "Winner's Path": '챔피언의 길', 'Amity Meadow': '우정의 초원'}
EVENT = {'Yellow Forest': (10, 'forest'), 'Beyond the Sea': (20, 'beach'), 'Night Skys Edge': (30, 'field'), 'Rally': (45, 'town'),
         'Sightseeing': (60, 'town'), "Winner's Path": (80, 'mountain'), 'Amity Meadow': (100, 'field')}   # Pokédex count, picture
ART = {'Field': 'field', 'Forest': 'forest', 'Treehouse': 'forest', 'Road': 'mountain', 'Path': 'mountain', 'Beach': 'beach', 'Lake': 'lake',
       'Area': 'town', 'Outskirts': 'town', 'Resort': 'town', 'Cave': 'cave', 'Rd.': 'mountain'}
t = open(get('serebii.html'), encoding='latin-1').read()
t = re.sub(r'<(script|style).*?</\1>', '', t, flags=re.S)
t = re.sub(r'<[^>]+>', ' ', t); t = html.unescape(t)
L = [re.sub(r'\s+', ' ', l).strip() for l in t.split('\n')]; L = [l for l in L if l]
starts = [i for i, l in enumerate(L) if l.startswith('Unlock Criterea')][:27]
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
    dexNeed, art = EVENT.get(name) or (0, next(v for k2, v in ART.items() if name.endswith(k2) or name == k2))
    if name in EVENT: watts = 0
    courses.append(dict(name=KO[name], watts=watts, dex=dexNeed, types=ctypes, art=art,
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

with open('Sources/Data/Data.swift', 'w') as f:
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
    courses = courses[:20] + sorted(courses[20:], key=lambda c: c['dex'])
    # --- more Pokémon per course (not in the original): each group gets 2 more candidates, plus 5 rare "guests" (10 % of radar finds).
    # By habitat (PokeAPI has it up to Gen III; Gen IV goes by primary type); group by catch rate: A < 75, B 75-149, C >= 150 (and a base form).
    hab = {r['id']: r['identifier'] for r in csv.DictReader(open(get('pokemon_habitats.csv')))}
    BY_TYPE = {'water': 'sea', 'grass': 'forest', 'bug': 'forest', 'rock': 'mountain', 'ground': 'rough-terrain', 'steel': 'mountain', 'ghost': 'cave',
               'dark': 'urban', 'poison': 'urban', 'normal': 'grassland', 'flying': 'grassland', 'fire': 'rough-terrain', 'ice': 'mountain',
               'electric': 'urban', 'psychic': 'urban', 'fighting': 'urban', 'dragon': 'mountain'}
    HABITATS = {'field': {'grassland'}, 'forest': {'forest'}, 'mountain': {'mountain', 'rough-terrain'}, 'beach': {'sea', 'waters-edge'},
                'lake': {'waters-edge', 'sea'}, 'town': {'urban', 'grassland'}, 'cave': {'cave'}}
    def habitat(d): return hab.get(sp[d]['habitat_id']) or BY_TYPE[types[d][0]]
    legendary = {d for d in range(1, N + 1) if sp[d]['is_legendary'] == '1' or sp[d]['is_mythical'] == '1'}
    usable = [d for d in range(1, N + 1) if d not in legendary and sp[d]['is_baby'] == '0' and d != 292]
    tier = lambda d: 0 if int(sp[d]['capture_rate']) < 75 else 1 if int(sp[d]['capture_rate']) < 150 else 2
    def stage(d): f = sp[d]['evolves_from_species_id']; return 0 if not f else 1 + stage(int(f))
    fits_level = lambda d, lv: stage(d) == 0 or stage(d) == 1 and lv >= 20 or stage(d) >= 2 and lv >= 35   # no Lv.8 핫삼
    original = {sl[0] for c in courses for sl in c['slots']}
    used = {}
    import random
    for ci, c in enumerate(courses):
        rnd = random.Random(ci)                                                            # stable data: same picks on every run
        mine = {sl[0] for sl in c['slots']}
        top = max(sl[1] for sl in c['slots'])
        pool = [d for d in usable if habitat(d) in HABITATS[c['art']] and d not in mine and fits_level(d, top)]
        score = lambda d: (used.get(d, 0), 0 if set(types[d]) & set(c['types']) else 1, d in original, rnd.random())   # spread out, the course's types first
        extra = []
        for g in range(3):
            lv = c['slots'][2 * g][1]
            cand = sorted([d for d in pool if tier(d) == g and fits_level(d, lv) and d not in extra], key=score)[:2]
            if len(cand) < 2: cand += sorted([d for d in pool if d not in extra and d not in cand and fits_level(d, lv)], key=score)[:2 - len(cand)]
            base = c['slots'][2 * g]
            for d in cand:
                used[d] = used.get(d, 0) + 1
                fem = sp[d]['gender_rate'] == '8' or (sp[d]['gender_rate'] not in ('-1', '0') and rnd.random() < 0.5)
                extra.append((d, base[1], base[2], base[3], fem))
        taken = {e[0] for e in extra}
        assert len(extra) == 6, (c['name'], extra)
        gpool = sorted([d for d in pool if d not in taken], key=lambda d: (d in original, used.get(d, 0), rnd.random()))[:5]
        for d in gpool: used[d] = used.get(d, 0) + 1
        c['extra'], c['guests'] = extra, gpool
    # legendary courses (not in the original): a regular course's Pokémon + items, plus a rare legend on the radar; unlock by Pokédex count
    by = {c['name']: c for c in courses}
    LEGEND = [('전설의 새 둥지', 150, '화산 길', [144, 145, 146]), ('방황하는 들판', 170, '호연 들판', [243, 244, 245]),
              ('고대 유적', 190, '무서운 동굴', [377, 378, 379, 486]), ('호연의 하늘과 바다', 210, '따뜻한 해변', [380, 381, 382, 383, 384]),
              ('신오 호수', 230, '하얀 호수', [480, 481, 482, 485, 488]), ('시공의 틈', 260, '고요한 동굴', [483, 484, 487, 491]),
              ('환상의 숲', 300, '커다란 숲', [151, 251, 385, 386, 489, 490, 492]), ('시작의 방', 350, '리조트', [249, 493])]
    SHOP = [250, 150]                                                                   # 칠색조 (W) and 뮤츠 (BP): bought only, never met — Walk.legendShop
    legends = [d for *_, ls in LEGEND for d in ls]
    assert sorted(legends + SHOP) == sorted(d for d in range(1, N + 1) if sp[d]['is_legendary'] == '1' or sp[d]['is_mythical'] == '1'), 'every legend exactly once'
    for name, need, base, ls in LEGEND: courses.append({**by[base], 'name': name, 'watts': 0, 'dex': need, 'legends': ls})
    # eggs: the bases of every line you can't otherwise reach (no legends; Shedinja comes from Nincada)
    reach = {25} | {sl[0] for c in courses for sl in c['slots']}                                     # eggs = bases the ORIGINAL tables miss (the extras overlap them on purpose)
    while True:
        more = {to for frm, to, *_ in evos if frm in reach} - reach
        if not more: break
        reach |= more
    pool = [d for d in range(1, N + 1) if not sp[d]['evolves_from_species_id'] and d not in reach and d not in legends and d not in SHOP and d != 292]
    base_of = lambda d: d if not sp[d]['evolves_from_species_id'] else base_of(int(sp[d]['evolves_from_species_id']))
    reach2 = reach | {d for d in range(1, N + 1) if base_of(d) in pool} | set(legends) | set(SHOP) | {292}
    assert reach2 == set(range(1, N + 1)), sorted(set(range(1, N + 1)) - reach2)
    f.write('let eggPool: [Int] = [' + ', '.join(map(str, pool)) + ']   // every line not on a course\n')
    f.write('let eggCycles: [Int] = [0, ' + ', '.join(sp[i]['hatch_counter'] for i in range(1, N + 1)) + ']   // x 255 steps (Gen IV)\n')
    # --- battles (Gen IV as in HGSS): base stats, base EXP, catch rate, level-up learnsets (damaging moves only — no status conditions here),
    # move data rolled back to HGSS through the changelog (e.g. 10만볼트 95, not today's 90), and the Gen IV type chart (no Fairy; Steel resists Ghost / Dark)
    stats = {}
    for r in csv.DictReader(open(get('pokemon_stats.csv'))):
        if int(r['pokemon_id']) <= N: stats.setdefault(int(r['pokemon_id']), {})[int(r['stat_id'])] = int(r['base_stat'])
    past = {}
    for r in csv.DictReader(open(get('pokemon_stats_past.csv'))):                          # Gen VI raised some (피카츄 방어 30 -> 40): take the value that held in Gen IV
        d, k, g = int(r['pokemon_id']), int(r['stat_id']), int(r['generation_id'])
        if d <= N and k <= 6 and g >= 4 and g < past.get((d, k), (99, 0))[0]: past[(d, k)] = (g, int(r['base_stat']))
    for (d, k), (_, v) in past.items(): stats[d][k] = v
    bexp = {int(r['id']): int(r['base_experience'] or 50) for r in csv.DictReader(open(get('pokemon.csv'))) if int(r['id']) <= N}
    vg = {r['id']: int(r['order']) for r in csv.DictReader(open(get('version_groups.csv')))}
    HG = vg['10']
    mv = {int(r['id']): dict(r) for r in csv.DictReader(open(get('moves.csv'))) if int(r['generation_id']) <= 4}
    for r in sorted(csv.DictReader(open(get('move_changelog.csv'))), key=lambda r: vg[r['changed_in_version_group_id']], reverse=True):
        m = mv.get(int(r['move_id']))
        if m is None or vg[r['changed_in_version_group_id']] <= HG: continue
        for k in ('type_id', 'power', 'accuracy', 'priority'):
            if r[k]: m[k] = r[k]                                                        # newest-first, so the earliest change after HGSS wins
    mko = {int(r['move_id']): r['name'] for r in csv.DictReader(open(get('move_names.csv'))) if r['local_language_id'] == '3'}
    # moves this engine can't do right: 속이기 (first turn + flinch), ones that need sleep / a charge / an item / a delay, and self-KOs that would just be free 200-power hits
    known = set(mv)                                                                     # every Gen I-IV move; Battle.swift knows which ones it can run
    learn = {}
    for r in csv.DictReader(open(get('pokemon_moves.csv'))):
        d, i = int(r['pokemon_id']), int(r['move_id'])
        if d <= N and r['version_group_id'] == '10' and r['pokemon_move_method_id'] == '1' and i in known:
            learn.setdefault(d, set()).add((int(r['level']), i))
    used = {165} | {i for s in learn.values() for _, i in s}                          # 165 발버둥: for anyone with nothing to hit with yet
    tid = {r['id']: r['identifier'] for r in csv.DictReader(open(get('types.csv')))}
    chart = {}
    for r in csv.DictReader(open(get('type_efficacy.csv'))):
        if r['damage_factor'] != '100' and tid[r['damage_type_id']] in TYPES and tid[r['target_type_id']] in TYPES:
            chart.setdefault(tid[r['damage_type_id']], {})[tid[r['target_type_id']]] = int(r['damage_factor']) / 100
    for r in csv.DictReader(open(get('type_efficacy_past.csv'))):
        if int(r['generation_id']) >= 4: chart.setdefault(tid[r['damage_type_id']], {})[tid[r['target_type_id']]] = int(r['damage_factor']) / 100
    assert chart['ghost']['steel'] == 0.5 and chart['electric']['water'] == 2 and chart['normal']['ghost'] == 0
    def stage(d): f = sp[d]['evolves_from_species_id']; return 0 if not f else 1 + stage(int(f))
    f.write('let baseStats: [[Int]] = [[], ' + ', '.join('[' + ', '.join(str(stats[d][k]) for k in range(1, 7)) + ']' for d in range(1, N + 1)) + ']   // HP Atk Def SpA SpD Spe\n')
    f.write('let baseExp: [Int] = [0, ' + ', '.join(str(bexp[d]) for d in range(1, N + 1)) + ']\n')
    f.write('let catchRate: [Int] = [0, ' + ', '.join(sp[d]['capture_rate'] for d in range(1, N + 1)) + ']\n')
    f.write('let stageOf: [Int] = [0, ' + ', '.join(str(stage(d)) for d in range(1, N + 1)) + ']\n')
    # --- battle data for the full Gen IV engine: every move with its meta (ailment, stat changes, hits, drain, crit, flinch, flags),
    # abilities as they were in Gen IV (pokemon_abilities_past rolls back later changes, e.g. 팬텀 = 부유), natures, EV yields, weight, gender ratio
    meta = {int(r['move_id']): r for r in csv.DictReader(open(get('move_meta.csv')))}
    ail = {r['id']: r['identifier'] for r in csv.DictReader(open(get('move_meta_ailments.csv')))}
    sch = {}
    for r in csv.DictReader(open(get('move_meta_stat_changes.csv'))): sch.setdefault(int(r['move_id']), []).append((int(r['stat_id']), int(r['change'])))
    KIND = {'2': 0, '3': 1, '1': 2}                                                     # physical, special, status
    FLAG = {'1': 1, '8': 2, '9': 4, '4': 8, '5': 16, '6': 32, '3': 64, '2': 128, '10': 256, '11': 512, '13': 1024}   # contact punch sound protect reflectable snatch recharge charge gravity defrost heal
    flags = {}
    for r in csv.DictReader(open(get('move_flag_map.csv'))): flags[int(r['move_id'])] = flags.get(int(r['move_id']), 0) | FLAG.get(r['move_flag_id'], 0)
    with open('Sources/Data/BattleData.swift', 'w') as g:
        g.write('// Generated by tools/gen.py (PokeAPI, rolled back to HGSS / Gen IV). Do not edit by hand.\n\n')
        # one statement per move: a single 485-entry literal took swiftc 13 s to type-check, statements are checked one at a time
        g.write('let moveTable = Dictionary(uniqueKeysWithValues: allMoves().map { ($0.id, $0) })\n')
        g.write('@_optimize(none) private func allMoves() -> [MoveInfo] {\n    var m: [MoveInfo] = []\n')
        for i in sorted(mv):
            m, me = mv[i], meta.get(i, {})
            def n(k, d=0): return int(me.get(k) or d)
            g.write(f'    m.append(MoveInfo(id: {i}, name: {s(mko.get(i, m["identifier"]))}, type: {s(tid[m["type_id"]])}, power: {m["power"] or 0}, accuracy: {m["accuracy"] or 0}, '
                    f'kind: {KIND[m["damage_class_id"]]}, priority: {m["priority"]}, pp: {m["pp"] or 1}, cat: {n("meta_category_id")}, target: {m["target_id"]}, '
                    f'ailment: {s(ail.get(me.get("meta_ailment_id", "0"), "none"))}, ailmentChance: {n("ailment_chance")}, flinch: {n("flinch_chance")}, '
                    f'stats: [{", ".join(f"{a}, {b}" for a, b in sch.get(i, []))}], statChance: {n("stat_chance")}, minHits: {n("min_hits")}, maxHits: {n("max_hits")}, '
                    f'minTurns: {n("min_turns")}, maxTurns: {n("max_turns")}, drain: {n("drain")}, healing: {n("healing")}, crit: {n("crit_rate")}, flags: {flags.get(i, 0)}))\n')
        g.write('    return m\n}\n')
        # abilities in Gen IV
        slots = {}
        for r in csv.DictReader(open(get('pokemon_abilities.csv'))):
            d = int(r['pokemon_id'])
            if d <= N and r['is_hidden'] == '0': slots.setdefault(d, {})[int(r['slot'])] = int(r['ability_id'])
        pastA = {}
        for r in csv.DictReader(open(get('pokemon_abilities_past.csv'))):
            d, gg, sl = int(r['pokemon_id']), int(r['generation_id']), int(r['slot'])
            if d <= N and sl in (1, 2) and gg >= 4 and gg < pastA.get((d, sl), (99, None))[0]: pastA[(d, sl)] = (gg, int(r['ability_id']) if r['ability_id'] else None)
        for (d, sl), (_, a) in pastA.items():
            if a is None: slots.setdefault(d, {}).pop(sl, None)
            else: slots.setdefault(d, {})[sl] = a
        ab = [[a for sl, a in sorted(slots.get(d, {}).items()) if a <= 123] for d in range(N + 1)]
        assert all(ab[d] for d in range(1, N + 1)), [d for d in range(1, N + 1) if not ab[d]]
        assert ab[94] == [26], ab[94]                                                    # 팬텀: 부유 in Gen IV
        g.write('let abilitySlots: [[Int]] = [[], ' + ', '.join('[' + ', '.join(map(str, ab[d])) + ']' for d in range(1, N + 1)) + ']\n')
        an = {int(r['ability_id']): r['name'] for r in csv.DictReader(open(get('ability_names.csv'))) if r['local_language_id'] == '3'}
        g.write('let abilityNames: [Int: String] = [' + ', '.join(f'{i}: {s(an[i])}' for i in range(1, 124)) + ']\n')
        nat = list(csv.DictReader(open(get('natures.csv'))))
        nko = {r['nature_id']: r['name'] for r in csv.DictReader(open(get('nature_names.csv'))) if r['local_language_id'] == '3'}
        g.write('let natures: [(name: String, up: Int, down: Int)] = [' + ', '.join(f'({s(nko[r["id"]])}, {int(r["increased_stat_id"]) - 1}, {int(r["decreased_stat_id"]) - 1})' for r in sorted(nat, key=lambda r: int(r['game_index']))) + ']   // stat index 1-5, up == down = neutral\n')
        ev = {}
        for r in csv.DictReader(open(get('pokemon_stats.csv'))):
            if int(r['pokemon_id']) <= N: ev.setdefault(int(r['pokemon_id']), {})[int(r['stat_id'])] = int(r['effort'])
        g.write('let evYield: [[Int]] = [[], ' + ', '.join('[' + ', '.join(str(ev[d][k]) for k in range(1, 7)) + ']' for d in range(1, N + 1)) + ']\n')
        wt = {int(r['id']): int(r['weight']) for r in csv.DictReader(open(get('pokemon.csv'))) if int(r['id']) <= N}
        g.write('let weightKg: [Double] = [0, ' + ', '.join(f'{wt[d] / 10:g}' for d in range(1, N + 1)) + ']\n')
        g.write('let genderRate: [Int] = [0, ' + ', '.join(sp[d]['gender_rate'] for d in range(1, N + 1)) + ']   // -1 genderless, else eighths female\n')
    f.write('let learnsets: [[Int]] = [[], ' + ', '.join('[' + ', '.join(f'{l}, {i}' for l, i in sorted(learn.get(d, set()))) + ']' for d in range(1, N + 1)) + ']   // level, move, level, move ...\n')
    f.write('let typeChart = typeRows()\n@_optimize(none) private func typeRows() -> [String: [String: Double]] {\n    var c: [String: [String: Double]] = [:]\n')   # a row a statement: quick to type-check
    for a, row in sorted(chart.items()): f.write(f'    c[{s(a)}] = [' + ', '.join(f'{s(b)}: {float(v)!r}' for b, v in sorted(row.items())) + ']\n')
    f.write('    return c\n}\n')
    f.write('let courses: [Course] = [\n')
    for c in courses:
        f.write(f'    Course(name: {s(c["name"])}, watts: {c["watts"]}, dex: {c["dex"]}, legends: [{", ".join(map(str, c.get("legends", [])))}], types: [{", ".join(s(x) for x in c["types"])}], art: .{c["art"]},\n')
        f.write('           slots: [' + ', '.join(f'Slot(dex: {d}, level: {l}, steps: {st}, chance: {ch:g}, female: {str(fe).lower()})' for d, l, st, ch, fe in c['slots']) + '],\n')
        f.write('           extra: [' + ', '.join(f'Slot(dex: {d}, level: {l}, steps: {st}, chance: {ch:g}, female: {str(fe).lower()})' for d, l, st, ch, fe in c['extra']) + '],\n')
        f.write('           guests: [' + ', '.join(map(str, c['guests'])) + '],\n')
        f.write('           items: [' + ', '.join(f'Find(item: {s(n)}, steps: {st}, chance: {ch})' for n, st, ch in c['items']) + ']),\n')
    f.write(']\n')
# Every table behind an unoptimised function: -O spent a minute folding these literals into constants, for data read once at launch.
for path in ['Sources/Data/Data.swift', 'Sources/Data/BattleData.swift']:
    src, out_lines, cur = open(path).read().split('\n'), [], None
    def flush():
        if cur:
            name, typ, body = cur
            head = [f'let {name}: {typ} = _{name}()', f'@_optimize(none) private func _{name}() -> {typ} {{']
            if body[0] == '[' and body[-1] == ']':                                # a multi-line list: one append per element, each checked on its own
                elems = []
                for l in body[1:-1]:
                    if re.match(r'^    \S', l): elems.append([l])
                    else: elems[-1].append(l)
                out_lines.extend(head + [f'    var a: {typ} = []'] + [x for e in elems for x in (['    a.append(' + e[0].strip()] + e[1:-1] + [e[-1].rstrip(',') + ')'] if len(e) > 1 else ['    a.append(' + e[0].strip().rstrip(',') + ')'])] + ['    return a', '}'])
            else: out_lines.extend(head + ['    ' + body[0]] + body[1:] + ['}'])
    for line in src:
        m = re.match(r'^let (\w+): (.+?) = (.*)$', line)
        if m: flush(); cur = (m.group(1), m.group(2), [m.group(3)]); continue
        if cur and line and not re.match(r'^(let |@|//|private )', line): cur[2].append(line); continue
        flush(); cur = None; out_lines.append(line)
    flush()
    open(path, 'w').write('\n'.join(out_lines))
print('ok', len(courses), 'courses,', len(hout), 'hgss sprite bytes,', len(iout), 'icon bytes')
