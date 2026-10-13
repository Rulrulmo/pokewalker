#!/usr/bin/env python3
"""Regenerates Sources/Data/{Data,BattleData}.swift + Resources/{hgss,icons,frames,anims,walk}.bin from the original sources. Needs Pillow. Run from the repo root: python3 tools/gen.py
(`python3 tools/gen.py art`: the pictures only; `data`: the tables only)

Sources (cached in tools/.cache, not committed; every URL is in SRC below — README "그림 · 데이터 출처" has the same list):
  - PokeAPI sprites (raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/...):
      heartgold-soulsilver/{n}.png, shiny/{n}.png, back/{n}.png, back/shiny/{n}.png  HGSS battle sprites -> hgss.bin (same pixels, other palette:
        pixel pairs give each species' normal -> shiny map); platinum/{,shiny/}422|423.png (HGSS's shiny 422/423 are copies of the normal)
      icons/{n}.png                                    Gen IV box / party icons (32x32) -> icons.bin (도감 / 포켓몬 grids)
      heartgold-soulsilver/animated/{n}.png            HGSS entry animations (APNG; shiny/ too) -> anims.bin
      heartgold-soulsilver/egg.png                     the HGSS egg -> frames.bin
  - Pokémon Showdown trainer sprites: play.pokemonshowdown.com/sprites/trainers/<name>.png (Gen IV rips) -> frames.bin (tower trainers)
  - HGSS following Pokémon (overworld walking, 4 frames a direction): github.com/teobz/pkmn-hgss-animated-overworld-sprites,
      APNG/by-direction/{left,right,down,up}/{regular,shiny}/{nnn}_{shiny_}{dir}.png (dex 3 digits) -> walk.bin
  - 5.0 (plan 18 §9): the forms of 1-493 by PokeAPI's own names in the folders above (10008.png = 히트로토무, 201-b.png, 479-wash_down.png);
      494-721, every Mega and primal, the forms past 493 from github.com/BluRosie/hg-engine at HGE (data/graphics/sprites/<name>/: male/front.png
      (its palette the normal), male/back.png (the shiny), icon.png, overworld.png + overworld-tsure_poke1.pal) -> hgss.bin, icons.bin, walk.bin;
      their animations: play.pokemonshowdown.com/sprites/gen5ani/<name>.gif (BW's; Smogon's past 649), where one lies on the picture -> anims.bin
  - Serebii's Pokéwalker course page: per course 6 Pokémon (groups A/B/C x 2) + 10 items, with min steps and chances.
  - PokeAPI CSVs (raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/): Korean names, Gen IV types (pokemon_types_past overrides
      the Fairy retcon), moves, abilities, natures, evolutions, stats... (the list is in SRC).
  New species beyond 493 (5.0, plan 18): the tables go to N = 721, and so do the pictures (then every form: the art list below). The Gen IV
  tables are 4.1's exactly (Gen4: 1-493 as HGSS, the new species as Gen VI, never read with content5 off);
  the Gen VI ones are their changes (Gen6Changes / Gen6Added), applied by Sources/Data/Content.swift behind the content5 switch.
  `python3 tools/gen.py data` writes the tables only.

The walker's own draw: for each of the 3 carried Pokémon, rarest first, "steps >= min and rand(100) < chance" wins, else the
next; the commonest is the fallback. Serebii prints the resulting band percentages; chance = the slot's % in the first band
where it appears, which reproduces every printed row (e.g. A 70 -> B (1-.7)*75 = 22.5 -> C 7.5).
"""
import csv, io, json, os, re, html, struct, sys, urllib.request, warnings, zlib
if 'data' not in sys.argv[1:]: from PIL import Image, ImageChops
warnings.filterwarnings('ignore', category=DeprecationWarning)   # Pillow 12: getdata

CACHE = os.path.join(os.path.dirname(__file__), '.cache')
API = 'https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/'
SRC = {
    **{f'hgss/{s}{i}.png': f'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/heartgold-soulsilver/{"shiny/" if s else ""}{i}.png'
       for i in range(1, 494) for s in ('', 's')},
    **{f'hgss/b{s}{i}.png': f'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/heartgold-soulsilver/back/{"shiny/" if s else ""}{i}.png'
       for i in range(1, 494) for s in ('', 's')},
    **{f'icons/{i}.png': f'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/icons/{i}.png' for i in range(1, 494)},
    **{f'anim/{i}.png': f'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/heartgold-soulsilver/animated/{i}.png' for i in range(1, 494)},
    # PokeAPI's HGSS shiny 422/423 (West Sea) are copies of the normal files; Platinum's front pair is right (its back pair is a copy too)
    **{f'plat/{s}{i}.png': f'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/platinum/{"shiny/" if s else ""}{i}.png'
       for i in (422, 423) for s in ('', 's')},
    'serebii.html': 'https://www.serebii.net/heartgoldsoulsilver/pokewalker-area.shtml',
    # the HGSS following Pokémon (the overworld walking sprites), teobz/pkmn-hgss-animated-overworld-sprites: 4 frames a direction
    **{f'ow/{d}/{v}{i:03}.png': f'https://raw.githubusercontent.com/teobz/pkmn-hgss-animated-overworld-sprites/main/APNG/by-direction/{d}/{"shiny" if v else "regular"}/{i:03}_{v}{d}.png'
       for i in range(1, 494) for d in ('left', 'right', 'down') for v in ('', 'shiny_')},
    'frames/egg.png': 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/heartgold-soulsilver/egg.png',
    **{f'frames/{t}.png': f'https://play.pokemonshowdown.com/sprites/trainers/{t}.png' for t in [
        'acetrainer-gen4', 'acetrainerf-gen4', 'veteran-gen4', 'veteranf', 'lady-gen4', 'hiker-gen4', 'scientist-gen4', 'blackbelt-gen4',
        'battlegirl-gen4', 'psychic-gen4', 'psychicf-gen4', 'dragontamer', 'schoolkid-gen4', 'pokemonranger-gen4', 'pokemonrangerf-gen4', 'palmer']},
    **{f + '.csv': API + f + '.csv' for f in ['pokemon_species_names', 'item_names', 'pokemon_types', 'pokemon_types_past', 'types',
                                              'pokemon_evolution', 'pokemon_species', 'experience', 'items', 'type_names', 'pokemon_habitats',
                                              'pokemon_stats', 'pokemon', 'moves', 'move_names', 'pokemon_moves', 'type_efficacy', 'type_efficacy_past',
                                              'version_groups', 'move_changelog', 'pokemon_stats_past',
                                              'move_meta', 'move_meta_stat_changes', 'move_meta_ailments', 'move_flag_map', 'abilities', 'ability_names',
                                              'pokemon_abilities', 'pokemon_abilities_past', 'natures', 'nature_names', 'ability_flavor_text',
                                              'pokemon_forms', 'pokemon_form_names', 'item_categories']},
}
N = 721   # the national dex through Gen VI (5.0, plan 18): every table below goes to N
N4 = 493  # HGSS's: every Gen IV table stops here (and HGSS's own pictures); above it only the Gen VI tables (Sources/Data/Content.swift)
ARTWORK = 'data' not in sys.argv[1:]

HGE = 'c056eb74d8486ec1b046ed4628ca23821c79dadd'   # BluRosie/hg-engine (2026-10-11): 5.0's pictures past HGSS's (494-721, the Megas, their forms)

def url(name):
    """Where a cached file comes from: SRC's, else by its folder (the 5.0 pictures, named from the CSVs)."""
    if name in SRC: return SRC[name]
    d, f = name.split('/', 1)
    pa = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-iv/'
    if d == 'hgss': b, sh, k = re.fullmatch(r'(b?)(s?)(\d.*)\.png', f).groups(); return pa + 'heartgold-soulsilver/' + 'back/' * (b == 'b') + 'shiny/' * (sh == 's') + k + '.png'
    if d == 'plat': sh, k = re.fullmatch(r'(s?)(\d.*)\.png', f).groups(); return pa + 'platinum/' + 'shiny/' * (sh == 's') + k + '.png'
    if d == 'icons': return pa + 'icons/' + f
    if d == 'anim': return pa + 'heartgold-soulsilver/animated/' + f
    if d == 'ow':
        dr, v, k = re.fullmatch(r'(\w+)/(shiny_)?(.+)\.png', f).groups()
        return f'https://raw.githubusercontent.com/teobz/pkmn-hgss-animated-overworld-sprites/main/APNG/by-direction/{dr}/{"shiny" if v else "regular"}/{k}_{v or ""}{dr}.png'
    if d == 'hge': return f'https://raw.githubusercontent.com/BluRosie/hg-engine/{HGE}/data/graphics/sprites/{f}'
    if d == 'gen5ani': return 'https://play.pokemonshowdown.com/sprites/gen5ani/' + ('' if f == 'index.html' else f)   # the folder's listing: which exist
    if d == 'sd': return 'https://play.pokemonshowdown.com/sprites/' + f
    raise KeyError(name)

def get(name):
    p = os.path.join(CACHE, name)
    if not os.path.exists(p):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        req = urllib.request.Request(url(name), headers={'User-Agent': 'Mozilla/5.0'})
        open(p + '.part', 'wb').write(urllib.request.urlopen(req).read()); os.replace(p + '.part', p)
    return p

def form_rows():
    """monForms' forms (5.0: Mon.form 1...; the pictures after the species'), one list for the tables and the pictures: [(row, pokemon id, species,
    kind)], pokemon_forms.csv in (pokemon id, form order, id) order; not a species' own, nor what 5.0 leaves out (past ORAS, 피카츄's, 아르세우스 ·
    게노세크트's, the 귀 · 영원의 꽃 ones). A species' forms are numbered in this order."""
    species = {int(r['id']): int(r['species_id']) for r in csv.DictReader(open(get('pokemon.csv')))}
    out = []
    for r in sorted(csv.DictReader(open(get('pokemon_forms.csv'))), key=lambda r: (int(r['pokemon_id']), int(r['form_order']), int(r['id']))):
        pid, d = int(r['pokemon_id']), species[int(r['pokemon_id'])]
        if d > N or int(r['introduced_in_version_group_id']) > 16 or r['identifier'] in {'pichu-spiky-eared', 'floette-eternal'} or d in (25, 493, 649): continue
        if r['is_default'] == '1' and pid < 10000: continue                                # the species itself
        kind = 'mega' if r['is_mega'] == '1' else 'primal' if r['identifier'].endswith('-primal') else 'battle' if r['is_battle_only'] == '1' else 'stored' if pid > 10000 else 'look'
        out.append((r, pid, d, kind))
    return out

if ARTWORK:   # `python3 tools/gen.py data`: the tables only (Sources/Data), the Resources/*.bin left as they are; `art`: the pictures only
    from concurrent.futures import ThreadPoolExecutor
    def rgba(name): return Image.open(get(name)).convert('RGBA')
    def dist(a, b): return sum((i - j) ** 2 for i, j in zip(a, b))
    def rows(name): return list(csv.DictReader(open(get(name))))
    def pal16(im): p = (im.getpalette() or [])[:48]; p += [0] * (48 - len(p)); return [tuple(p[k:k + 3]) for k in range(0, 48, 3)]
    def jasc(name): L = open(get(name)).read().split('\n'); n = int(L[2]); return [tuple(map(int, L[3 + k].split())) for k in range(n)] + [(0, 0, 0)] * (16 - n)
    def indexed(im, pal, box):
        """A DS frame (palette index 0 = clear) through a palette, as RGBA."""
        im = im.crop(box); out = Image.new('RGBA', im.size); out.putdata([pal[i] + (255,) if i else (0, 0, 0, 0) for i in im.getdata()]); return out

    # --- the pictures' numbers ("art": Pixels.swift's artIndex(dex, form)): 1-N the species, then every form of the tables' monForms in (species,
    # form) order (form_rows, as the tables'; SelfTest counts them). Where each comes from:
    #   1-493 and their forms (not the Megas): HGSS's as in 4.1 (PokeAPI; teobz's walking); a form by PokeAPI's own name (10008 = 히트로토무, 201-b = 안농 B, 422-east)
    #   494-721, every Mega and primal, the forms past 493: hg-engine (80x80 DS sprites made as HGSS's: front.png's palette the normal, back.png's
    #   the shiny; its box icon; its walking sprite, 2 frames a direction), and Showdown's gen5ani (BW's animations, Smogon's in their style) where there's one
    spi = {int(r['id']): r['identifier'] for r in rows('pokemon_species.csv')}
    forms = [{'dex': d, 'ident': r['identifier'], 'kind': kind, 'pid': pid} for r, pid, d, kind in form_rows()]
    ART = [None] + [{'dex': d, 'ident': spi[d], 'kind': None, 'pid': d} for d in range(1, N + 1)] + sorted(forms, key=lambda a: a['dex'])   # (stable: a species' forms in their order)
    have5 = set(re.findall(r'href="\./([^"/]+)\.gif"', open(get('gen5ani/index.html')).read()))
    for a in ART[1:]:
        d, i, k = a['dex'], a['ident'], a['kind']
        tail = i.split('-', 1)[1] if k else ''
        a['walks'] = k in (None, 'look', 'stored')                                     # a Mega or a fight's form never walks
        if d <= N4 and k not in ('mega', 'primal'):
            a['hgss'] = str(d) if not k else str(a['pid']) if a['pid'] > 10000 else f'{d}-{tail}'
            a['ow'] = (f'{d:03}' if not k else f'{d:03}-{tail}') if a['walks'] else None
        else:
            # hg-engine's folders: mega_charizard_x, flabebe_yellow_flower; its 비비용 is the 얼음 무늬 (the games' first) and 꽃밭 무늬 PokeAPI's
            a['hge'] = {'vivillon': 'vivillon_meadow', 'vivillon-icy-snow': 'vivillon', 'darmanitan-zen': 'darmanitan_zen_mode'}.get(i) or \
                (re.sub(r'^(.+)-mega(-[xy])?$', r'mega_\1\2', i) + '_flower' * bool(re.fullmatch(r'(flabebe|floette|florges)-\w+', i))).replace('-', '_')
            a['sd'] = i.replace('-', '') if not k else i.split('-', 1)[0] + '-' + tail.replace('female', 'f').replace('-', '')   # Showdown's: charizard-megax, pyroar-f
            a['ani'] = a['sd'] if a['sd'] in have5 else None
    need = []
    for a in ART[1:]:
        if 'hgss' in a: need += [f'hgss/{b}{s}{a["hgss"]}.png' for b in ('', 'b') for s in ('', 's')] + [f'icons/{a["hgss"]}.png', f'anim/{a["hgss"]}.png']
        if a.get('ow'): need += [f'ow/{dr}/{v}{a["ow"]}.png' for dr in ('left', 'right', 'down') for v in ('', 'shiny_')]
        if 'hge' in a: need += [f'hge/{a["hge"]}/{f}' for f in ['male/front.png', 'male/back.png', 'icon.png'] + ['overworld.png', 'overworld-tsure_poke1.pal'] * a['walks']]
        if a.get('ani'): need.append(f'gen5ani/{a["ani"]}.gif')
    def tryget(name):
        try: get(name)
        except Exception: pass                                                          # none there (HGSS's walking misses a few): said below
    todo = [n for n in need if not os.path.exists(os.path.join(CACHE, n))]
    if todo: print(f'fetching {len(todo)} files'); list(ThreadPoolExecutor(16).map(tryget, todo))
    print(f'art: {len(ART) - 1} = {N} species + {len(ART) - 1 - N} forms ({sum(1 for a in ART[1:] if "hge" in a)} from hg-engine, {sum(1 for a in ART[1:] if a.get("ani"))} BW animations)')

    # --- hgss.bin: the battle sprites, drawn one pixel a point. Per picture (art): 15 normal + 15 shiny RGB (index 1...15; 0 = transparent),
    # then the front and the back, 80x80 at 4 bpp (high nibble = left). 6490 B each. Each frame is moved down to stand on its bottom
    # row (PokeAPI keeps the DS's per-species offsets; the walker has no offset table). A colour slot is a (normal, shiny) pair: two DS
    # slots can share a normal colour and part in the shiny.
    hout, over15 = bytearray(), []
    for art, a in enumerate(ART[1:], 1):
        shiny = lambda p, q: q[:3] if q[3] >= 128 else p[:3]
        if 'hge' in a:
            def pic(x): p = get(f'hge/{a["hge"]}/male/{x}.png'); return Image.open(p if os.path.getsize(p) else get(f'hge/{a["hge"]}/female/{x}.png'))
            f, b = pic('front'), pic('back')
            assert f.mode == b.mode == 'P' and f.size == b.size == (160, 80), (a['hge'], f.size, b.size)   # (its male one, or the female where that's all: 부리공 · 버랜지나 · 메가캥카 · 냐오닉스 ♀)
            imgs = [(indexed(x, pal16(f), (0, 0, 80, 80)), indexed(x, pal16(b), (0, 0, 80, 80))) for x in (f, b)]   # frame 1 of its two
        else:
            k = a['hgss']; imgs = [(rgba(f'hgss/{b}{k}.png'), rgba(f'hgss/{b}s{k}.png')) for b in ('', 'b')]
        for x, sh in imgs: assert x.size == (80, 80) == sh.size, (art, x.size)
        if all(x.tobytes() == sh.tobytes() for x, sh in imgs):
            # PokeAPI's HGSS shiny 422/423 (West Sea) are copies of the normal files, and so is Platinum's back pair (and hg-engine's 달마모드 has
            # one palette): the normal -> shiny map comes from another rip's front pair (Platinum's; Showdown's BW), its colours snapped to ours; a
            # colour it never shows takes its nearest one's shift
            normals = {p[:3] for x, _ in imgs for p in x.getdata() if p[3] >= 128}
            votes = {}
            two = [f'plat/{s}{a["hgss"]}.png' for s in ('', 's')] if 'hgss' in a else [f'sd/{s}/{a["sd"]}.png' for s in ('gen5', 'gen5-shiny')]
            for p, q in zip(rgba(two[0]).getdata(), rgba(two[1]).getdata()):
                if p[3] >= 128 and q[3] >= 128:
                    n = min(normals, key=lambda c: dist(c, p[:3])); votes.setdefault(n, {}).setdefault(q[:3], 0); votes[n][q[:3]] += 1
            remap = {n: max(v, key=v.get) for n, v in votes.items()}
            for n in normals - remap.keys():
                m = min(remap, key=lambda c: dist(c, n)); remap[n] = tuple(max(0, min(255, c + s - o)) for c, s, o in zip(n, remap[m], m))
            shiny = lambda p, q: remap[p[:3]]
        count = {}
        for x, sh in imgs:
            for p, q in zip(x.getdata(), sh.getdata()):
                if p[3] >= 128: c = (p[:3], shiny(p, q)); count[c] = count.get(c, 0) + 1
        slots = sorted(count, key=lambda c: -count[c])[:15]                     # a DS palette is 15 colours; more (rare) snap to the nearest
        if len(count) > 15: over15.append(art)
        index = {c: slots.index(c) + 1 if c in slots else 1 + min(range(len(slots)), key=lambda i: dist(slots[i][0], c[0]) + dist(slots[i][1], c[1])) for c in count}
        for n, _ in slots + [((0, 0, 0), 0)] * (15 - len(slots)): hout += bytes(n)
        for _, s in slots + [(0, (0, 0, 0))] * (15 - len(slots)): hout += bytes(s)
        for x, sh in imgs:
            px, qx = list(x.getdata()), list(sh.getdata())
            drop = 79 - max(y for y in range(80) if any(px[y * 80 + c][3] >= 128 for c in range(80)))   # onto the bottom row
            cell = lambda c, y: 0 if y < drop or px[(y - drop) * 80 + c][3] < 128 else index[(px[(y - drop) * 80 + c][:3], shiny(px[(y - drop) * 80 + c], qx[(y - drop) * 80 + c]))]
            for y in range(80):
                for c in range(0, 80, 2): hout.append(cell(c, y) << 4 | cell(c + 1, y))
    assert len(hout) == (len(ART) - 1) * 6490
    if over15: print('palette snapped (> 15 colour pairs):', over15)
    open('Resources/hgss.bin', 'wb').write(hout)

    # --- icons.bin: the box / party icons (the 도감 and 상자 grids), one pixel a point. Per picture: 15 RGB (index 1...15; 0 = transparent),
    # then 32x32 at 4 bpp (high nibble = left). 557 B each. A DS icon palette is 16 colours, so 15 opaque always fit.
    iout = bytearray()
    for art, a in enumerate(ART[1:], 1):
        if 'hge' in a: im = Image.open(get(f'hge/{a["hge"]}/icon.png')); assert im.mode == 'P' and im.width == 32, (a['hge'], im.size); im = indexed(im, pal16(im), (0, 0, 32, 32))
        else: im = rgba(f'icons/{a["hgss"]}.png')
        assert im.size == (32, 32), (art, im.size)
        px = list(im.getdata()); pal = sorted({p[:3] for p in px if p[3] >= 128})
        assert 0 < len(pal) <= 15, (art, len(pal))
        for c in pal + [(0, 0, 0)] * (15 - len(pal)): iout += bytes(c)
        cell = lambda p: pal.index(p[:3]) + 1 if p[3] >= 128 else 0
        for k in range(0, 1024, 2): iout.append(cell(px[k]) << 4 | cell(px[k + 1]))
    assert len(iout) == (len(ART) - 1) * 557
    open('Resources/icons.bin', 'wb').write(iout)

    # --- frames.bin: other 80x80 frames at one pixel a point: the HGSS egg, then the Battle Tower's trainers (Gen IV sprites, Showdown's rips).
    # Per frame: 15 RGB, then 80x80 at 4 bpp. 3245 B each, in FRAMES order (Pixels.swift's frameNames mirrors it). Each stands on row 79.
    FRAMES = ['egg', 'acetrainer-gen4', 'acetrainerf-gen4', 'veteran-gen4', 'veteranf', 'lady-gen4', 'hiker-gen4', 'scientist-gen4', 'blackbelt-gen4',
              'battlegirl-gen4', 'psychic-gen4', 'psychicf-gen4', 'dragontamer', 'schoolkid-gen4', 'pokemonranger-gen4', 'pokemonrangerf-gen4',
              'palmer']   # 3.9: 타워 타이쿤 (Pt · HGSS's Tower Tycoon)
    fout = bytearray()
    for f in FRAMES:
        a = rgba(f'frames/{f}.png'); assert a.size == (80, 80), (f, a.size)
        bot = max(y for y in range(80) for x in range(80) if a.getpixel((x, y))[3] >= 128)
        b = Image.new('RGBA', (80, 80)); b.paste(a, (0, 79 - bot)); a = b
        px = list(a.getdata()); pal = sorted({p[:3] for p in px if p[3] >= 128})
        assert 0 < len(pal) <= 15, (f, len(pal))
        for c in pal + [(0, 0, 0)] * (15 - len(pal)): fout += bytes(c)
        cell = lambda p: pal.index(p[:3]) + 1 if p[3] >= 128 else 0
        for k in range(0, 6400, 2): fout.append(cell(px[k]) << 4 | cell(px[k + 1]))
    assert len(fout) == len(FRAMES) * 3245
    open('Resources/frames.bin', 'wb').write(fout)

    # --- anims.bin: the entry animations: what a species does as it appears in battle, on its summary, when tapped. HGSS's (PokeAPI's APNGs) for
    # 1-493 and their forms; BW's (Showdown's gen5ani GIFs) for hg-engine's pictures, played through once (1-10 s). Each frame goes onto our
    # grounded 80x80 frame: its rest frame (HGSS: the last, long-held one; BW: the first, its still sprite) is matched against hgss.bin's front by
    # opaque mask, which carries the grounding shift; hg-engine redrew the big ones to fit 80x80, so a BW one that won't lie on it as it is is
    # tried smaller (each pixel the colour slot covering most of it). Every colour snaps to the picture's normal slots (another rip: RGB a little
    # off, a few more colours), so shiny and the grey shades work as for the sprite; where two slots share a normal colour, the one the front has
    # there. Consecutive equal frames merge; the final hold (the APNG's loop pause) is cut to 100 ms. Per picture, raw DEFLATE of:
    #   x, y (int16: the box's top-left in the 80x80 frame, may be < 0 or past 79), w (even), h, n (uint8), n x uint16 ms, n frames w x h at 4 bpp.
    # The file: one uint32 offset a picture and one more (art a = off[a - 1] ..< off[a]; empty = none, the static sprite stays), then the blocks.
    def apng(path):
        """The frames composited, [(RGBA, ms)]: Pillow clears a palette frame to index 0 (opaque black here), not to clear."""
        b, i, ch = open(path, 'rb').read(), 8, []
        while i < len(b):
            n, = struct.unpack('>I', b[i:i + 4]); ch.append((b[i + 4:i + 8], b[i + 8:i + 8 + n])); i += 12 + n
        head = {t: c for t, c in ch if t in (b'IHDR', b'PLTE', b'tRNS')}
        def png(w, h, data):
            c = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
            return Image.open(io.BytesIO(b'\x89PNG\r\n\x1a\n' + c(b'IHDR', struct.pack('>II', w, h) + head[b'IHDR'][8:]) + b''.join(c(t, head[t]) for t in (b'PLTE', b'tRNS') if t in head)
                                         + c(b'IDAT', data) + c(b'IEND', b''))).convert('RGBA')
        fr = []
        for t, c in ch:
            if t == b'fcTL': fr.append([struct.unpack('>IIIIIHHBB', c)[1:], b''])
            elif t == b'IDAT' and fr: fr[-1][1] += c                           # an IDAT before any fcTL is the default image, not a frame
            elif t == b'fdAT': fr[-1][1] += c[4:]
        canvas, out = Image.new('RGBA', struct.unpack('>II', head[b'IHDR'][:8])), []
        for k, ((w, h, x, y, num, den, dop, bop), data) in enumerate(fr):
            f, keep = png(w, h, data), canvas.copy()
            if bop == 0: canvas.paste(f, (x, y))
            else: canvas.alpha_composite(f, (x, y))
            out.append((canvas.copy(), round(num * 1000 / (den or 100))))
            if dop == 1 or dop == 2 and k == 0: canvas.paste((0, 0, 0, 0), (x, y, x + w, y + h))
            elif dop == 2: canvas = keep
        return out
    def gif(path):
        """A GIF's frames as Pillow composites them, [(RGBA, ms)]."""
        g, out = Image.open(path), []
        for k in range(g.n_frames): g.seek(k); out.append((g.convert('RGBA'), g.info.get('duration') or 100))
        return out
    def shrink(m, k):
        """An index image (L: 0 clear, slots 1-15) k times as big: each pixel the slot that covers most of it, clear where it's under half covered."""
        W, H = max(1, round(m.width * k)), max(1, round(m.height * k))
        out, best, hist = Image.new('L', (W, H)), Image.new('L', (W, H)), m.histogram()
        for v in (v for v in range(1, 16) if hist[v]):
            c = m.point(lambda p, v=v: 255 if p == v else 0).resize((W, H), Image.BOX)
            out.paste(v, mask=ImageChops.subtract(c, best).point(lambda p: 255 if p else 0)); best = ImageChops.lighter(best, c)
        out.paste(0, mask=m.point(lambda p: 255 if p else 0).resize((W, H), Image.BOX).point(lambda p: 255 if p < 128 else 0))
        return out
    nib = lambda at, k: hout[at + k // 2] >> 4 if k % 2 == 0 else hout[at + k // 2] & 15
    blocks, poor, none, small, cuts, dropped = [], [], [], [], [], []
    for art, a in enumerate(ART[1:], 1):
        o = (art - 1) * 6490
        try: frames = apng(get(f'anim/{a["hgss"]}.png')) if 'hgss' in a else gif(get(f'gen5ani/{a["ani"]}.gif')) if a.get('ani') else None
        except Exception: frames = None                                              # missing / broken: the static sprite stays
        if not frames: (none if 'hgss' in a or a.get('ani') else []).append(art); blocks.append(b''); continue   # (most past 493 have none)
        slot, front = [tuple(hout[o + i * 3:o + i * 3 + 3]) for i in range(15)], [nib(o + 90, k) for k in range(6400)]
        # where the rest frame's canvas sits on our frame: the best mask overlap near where their boxes line up
        smask = Image.frombytes('L', (80, 80), bytes(255 if i else 0 for i in front))
        sb, ns = smask.getbbox(), smask.histogram()[255]
        def fit(rest, cut=False, reach=3):                                          # cut: only what falls in the 80x80 frame counts
            rb, nr = rest.getbbox(), rest.histogram()[255]
            def iou(x, y):
                w = rest.crop((x, y, x + 80, y + 80)); i = ImageChops.multiply(smask, w).histogram()[255]
                return i / (ns + (w.histogram()[255] if cut else nr) - i)
            cand = {(ax + ex, ay + ey) for ax in {rb[0] - sb[0], rb[2] - sb[2]} for ay in {rb[1] - sb[1], rb[3] - sb[3]} for ex in range(-reach, reach + 1) for ey in range(-reach, reach + 1)}
            return max((iou(x, y), x, y) for x, y in cand)                         # canvas (x, y) = our frame's (x - dx, y - dy)
        rest = frames[-1 if 'hgss' in a else 0][0].getchannel('A').point(lambda v: 255 if v >= 128 else 0)
        (score, dx, dy), scale, cut = fit(rest), 1.0, False
        if 'hge' in a and score < 0.9:
            # hg-engine redrew the big ones to fit 80x80: drawn smaller (so is its animation), or cut off at the frame (so is its animation: what's
            # cut counts for nothing, which flatters a little: 0.05 off)
            tries = [(fit(rest, cut=True, reach=6), 1.0, True)] + [(fit(rest.resize((max(1, round(rest.width * k)), max(1, round(rest.height * k))), Image.BOX).point(lambda v: 255 if v >= 128 else 0)), k, False)
                                                                   for k in (k / 100 for k in range(99, 49, -1))]
            (score, dx, dy), scale, cut = max([((score, dx, dy), 1.0, False)] + tries, key=lambda t: t[0][0] - 0.05 * t[2])
        if 'hge' in a and score - 0.05 * cut < 0.8: dropped.append((art, a['ani'], round(score, 3), scale, cut)); blocks.append(b''); continue   # too far off its picture: it'd jump at the end
        if scale < 1: small.append((art, scale))
        if cut: cuts.append(art)
        # colours: each of the rip's colours to the slot the front mostly has under it in the rest frame (if they line up), else to the nearest
        # of the picture's own normal colours
        used = sorted((set(front) | {nib(o + 3290, k) for k in range(6400)}) - {0})                   # the slots the front and back use
        of = {slot[i - 1]: [j for j in used if slot[j - 1] == slot[i - 1]] for i in used}   # a normal colour's slots
        shared = {i for s in of.values() if len(s) > 1 for i in s}                # two slots, one normal colour (their shinies part)
        cols = sorted({c[:3] for im, _ in frames for _, c in im.getcolors(1 << 16) if c[3] >= 128}); assert len(cols) <= 256, (art, len(cols))
        votes, R = {}, frames[-1 if 'hgss' in a else 0][0]
        if scale < 1: R = R.resize((max(1, round(R.width * scale)), max(1, round(R.height * scale))), Image.NEAREST)   # (its own colours, where they land)
        rp, (W, H) = R.load(), R.size
        for k, i in enumerate(front):
            X, Y = k % 80 + dx, k // 80 + dy
            if i and 0 <= X < W and 0 <= Y < H and rp[X, Y][3] >= 128: v = votes.setdefault(rp[X, Y][:3], {}); v[i] = v.get(i, 0) + 1
        to = {c: max(votes[c], key=votes[c].get) if score >= (0.9 if 'hgss' in a else 0.8) and sum(votes.get(c, {}).values()) >= 3 else min(used, key=lambda i: dist(slot[i - 1], c)) for c in cols}
        pal = Image.new('P', (1, 1)); pal.putpalette([v for c in cols + cols[:1] * (256 - len(cols)) for v in c])
        lut = bytes(to[c] for c in cols + cols[:1] * (256 - len(cols)))
        idx = [(Image.composite(Image.frombytes('L', im.size, im.convert('RGB').quantize(palette=pal, dither=Image.Dither.NONE).tobytes().translate(lut)),
                                Image.new('L', im.size), im.getchannel('A').point(lambda v: 255 if v >= 128 else 0)), ms) for im, ms in frames]
        if scale < 1: idx = [(shrink(m, scale), ms) for m, ms in idx]
        if cut: frame = Image.new('L', idx[0][0].size); frame.paste(255, (dx, dy, dx + 80, dy + 80)); idx = [(Image.composite(m, Image.new('L', m.size), frame), ms) for m, ms in idx]
        bx = [m.getbbox() for m, _ in idx if m.getbbox()]
        b0, b1, b3 = min(b[0] for b in bx), min(b[1] for b in bx), max(b[3] for b in bx)
        w = max(b[2] for b in bx) - b0; w += w % 2; h = b3 - b1; x0, y0 = b0 - dx, b1 - dy
        out = []
        for m, ms in idx:
            px = bytearray(m.crop((b0, b1, b0 + w, b3)).tobytes())
            for k in range(len(px)) if shared else ():                              # a shared normal colour: the slot the front has there, if it's one of them
                x, y = x0 + k % w, y0 + k // w
                if px[k] in shared and 0 <= x < 80 and 0 <= y < 80 and front[y * 80 + x] in of[slot[px[k] - 1]]: px[k] = front[y * 80 + x]
            if out and out[-1][0] == px: out[-1][1] += ms
            else: out.append([px, ms])
        out[-1][1] = min(out[-1][1], 100)
        while len(out) > 255: out = [[p, m + (out[k + 1][1] if k + 1 < len(out) else 0)] for k, (p, m) in enumerate(out) if k % 2 == 0]   # (none so long yet)
        last = out[-1][0]; at = lambda k: last[(k // 80 - y0) * w + k % 80 - x0] if 0 <= k % 80 - x0 < w and 0 <= k // 80 - y0 < h else 0
        same = sum(at(k) == i for k, i in enumerate(front) if i) / sum(1 for i in front if i)   # the rest frame against the front, index by index
        if score < 0.95 or same < 0.9: poor.append((art, round(score, 3), round(same, 3)))
        assert w < 256 and h < 256, (art, w, h, len(out))
        blk = struct.pack('<hhBBB', x0, y0, w, h, len(out)) + b''.join(struct.pack('<H', min(ms, 65535)) for _, ms in out)
        for px, _ in out: blk += (int.from_bytes(bytes(px[0::2]).translate(bytes(i * 16 & 255 for i in range(256))), 'big') | int.from_bytes(bytes(px[1::2]), 'big')).to_bytes(len(px) // 2, 'big')
        z = zlib.compressobj(9, zlib.DEFLATED, -15); blocks.append(z.compress(blk) + z.flush())
    off = [4 * len(ART)]
    for b in blocks: off.append(off[-1] + len(b))
    aout = b''.join(struct.pack('<I', v) for v in off) + b''.join(blocks)
    open('Resources/anims.bin', 'wb').write(aout)
    print(f'anims.bin {len(aout) / 1e6:.2f} MB; no animation: {none}; rest frame off the front (art, mask IoU, same index):', poor)
    print('BW ones drawn smaller (art, scale):', small, '; cut to the frame:', cuts, '; left out, too far off the picture (art, name, IoU, scale, cut):', dropped)

    # --- walk.bin: the following Pokémon, walking (the home screen's course picture): HGSS's (teobz's: 4 frames a direction) for 1-493 and their
    # forms; hg-engine's (2 a direction, as HGSS's own: teobz's 4 are each of them, then it 1 px up) past them. Per picture, raw DEFLATE of: size
    # (uint8: 32, or 64 for the big ones), 15 normal + 15 shiny RGB (slot pairs, as in hgss.bin: the shiny files have the same pixels in other
    # colours), then left, right, down x 4 frames, size x size at 4 bpp. The file: offsets as anims.bin's (empty = none: a Mega, a fight's form).
    wblocks, wover, wnone = [], [], []
    for art, a in enumerate(ART[1:], 1):
        four = lambda fs: (fs * 4)[:4]                                                   # 4 frames a direction (딱충이 facing us has 3: round again)
        try:
            if not a['walks']: raise LookupError
            if 'hge' in a:
                ow = Image.open(get(f'hge/{a["hge"]}/overworld.png')); size = ow.width; assert ow.mode == 'P' and ow.height == 8 * size, (a['hge'], ow.size)
                n, s = pal16(ow), jasc(f'hge/{a["hge"]}/overworld-tsure_poke1.pal')
                fr = [ow.crop((0, size * i, size, size * i + size)) for i in range(8)]       # up up, down down, left left, right right
                lift = lambda f: f.crop((0, 1, size, size + 1))                             # (the row below its feet: clear)
                dirs = [[indexed(f, p, (0, 0, size, size)) for f in (lift(fr[j]), fr[j], lift(fr[j + 1]), fr[j + 1])] for j in (4, 6, 2) for p in (n, s)]
                dirs = list(zip(dirs[0::2], dirs[1::2]))
            else:
                dirs = [(four([f for f, _ in apng(get(f'ow/{d}/{a["ow"]}.png'))]), four([f for f, _ in apng(get(f'ow/{d}/shiny_{a["ow"]}.png'))])) for d in ('left', 'right', 'down')]
        except Exception: wnone.append(art); wblocks.append(b''); continue
        size = dirs[0][0][0].size[0]; assert all(len(n) == 4 == len(sh) and all(f.size == (size, size) for f in n + sh) for n, sh in dirs), art
        pairs = {}
        for n, sh in dirs:
            for x, y in zip(n, sh):
                for p, q in zip(x.getdata(), y.getdata()):
                    if p[3] >= 128: pairs.setdefault(p[:3], {}).setdefault(q[:3] if q[3] >= 128 else p[:3], 0); pairs[p[:3]][q[:3] if q[3] >= 128 else p[:3]] += 1
        pal = sorted(pairs, key=lambda c: -sum(pairs[c].values()))
        if len(pal) > 15: wover.append((art, len(pal))); pal = pal[:15]
        near = lambda c: min(range(len(pal)), key=lambda i: dist(pal[i], c))
        blk = bytearray([size])
        for c in pal + [(0, 0, 0)] * (15 - len(pal)): blk += bytes(c)
        for c in pal: blk += bytes(max(pairs[c], key=pairs[c].get))
        blk += bytes(3 * (15 - len(pal)))
        for n, _ in dirs:
            for f in n:
                px = list(f.getdata()); cell = lambda p: (pal.index(p[:3]) if p[:3] in pal else near(p[:3])) + 1 if p[3] >= 128 else 0
                for k in range(0, size * size, 2): blk.append(cell(px[k]) << 4 | cell(px[k + 1]))
        c = zlib.compressobj(9, zlib.DEFLATED, -15); wblocks.append(c.compress(bytes(blk)) + c.flush())
    off = [4 * len(ART)]                                                                # offsets into the file, as anims.bin's
    for b in wblocks: off.append(off[-1] + len(b))
    wout = b''.join(struct.pack('<I', v) for v in off) + b''.join(wblocks)
    open('Resources/walk.bin', 'wb').write(wout)
    print(f'walk.bin {len(wout) / 1e6:.2f} MB; none: {[a for a in wnone if ART[a]["walks"]]}; palette cut to 15:', wover, '; 64 px:', sum(1 for b in wblocks if b and zlib.decompress(b, -15)[0] == 64))
    if sys.argv[1:] == ['art']: sys.exit()                                              # `python3 tools/gen.py art`: the pictures only

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
    if int(r['pokemon_id']) <= N4 and int(r['generation_id']) >= 4: past.setdefault(int(r['pokemon_id']), []).append(tname[r['type_id']])
    assert int(r['generation_id']) < 6, r                                                  # Gen VI's types are today's
types6 = {d: list(t) for d, t in types.items()}
types.update(past)
retyped = {d: types6[d] for d in range(1, N4 + 1) if types6[d] != types[d]}                # the Fairy retcon: 20 species
assert len(retyped) == 20 and all('fairy' in t for t in retyped.values()), retyped
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
    if to > N or r['region_id']: continue
    if to not in (666, 678) and (int(r['evolved_pokemon_form_id'] or 0) > 10000 or int(r['required_pokemon_form_id'] or 0) > 10000): continue   # 비비용's patterns, 냐오닉스 ♀: a look, not a species
    frm = int(sp[to]['evolves_from_species_id'])
    trig = {'1': 'level', '2': 'trade', '3': 'item'}.get(r['evolution_trigger_id'])
    if not trig: continue                                                                   # shed (Shedinja)
    way, level = trig, int(r['minimum_level'] or 0)
    if trig == 'level' and (r['minimum_happiness'] or r['minimum_beauty'] or r['minimum_affection']): way = 'friend'   # 님피아: affection (a Fairy move aside), as friendship
    if r['known_move_id']: level = MOVE_LEVEL[to]
    item = r['trigger_item_id'] or r['held_item_id']
    item = ko_item.get(item) if item else None
    fem = {'1': 'true', '2': 'false'}.get(r['gender_id'], 'nil')
    time = r['time_of_day'] or None
    place = PLACE.get(to) if r['location_id'] else None
    party = int(r['party_species_id']) if r['party_species_id'] else None
    ptype = tname[r['party_type_id']] if r['party_type_id'] else None                   # 판짱: a Dark type on the walker or in the box
    rain = 'rain' if r['needs_overworld_rain'] == '1' else None                          # 미끄네일: the walk's weather is rain
    mtype = tname[r['known_move_type_id']] if r['known_move_type_id'] else None        # 님피아: it knows a Fairy move (and goes first)
    if r['location_id'] and not place: continue
    evos.add((frm, to, way, level, item, fem, time, place, party, ptype, rain, mtype))
evos = sorted(evos)
tko = {}
for r in csv.DictReader(open(get('type_names.csv'))):
    if r['local_language_id'] == '3': tko[tname[r['type_id']]] = r['name']

with open('Sources/Data/Data.swift', 'w') as f:
    f.write('// Generated by tools/gen.py from the HGSS Pokéwalker data (Serebii) and PokeAPI. Do not edit by hand.\n\n')
    f.write('let monNames: [String] = ["", ' + ', '.join(s(ko[i]) for i in range(1, N + 1)) + ']\n')
    f.write('let monTypesGen4: [[String]] = [[], ' + ', '.join('[' + ', '.join(s(x) for x in (types[i] if i <= N4 else types6[i])) + ']' for i in range(1, N + 1)) + ']\n')
    f.write('let monTypesGen6Changes: [Int: [String]] = [' + ', '.join(f'{d}: [' + ', '.join(s(x) for x in t) + ']' for d, t in sorted(retyped.items())) + ']\n\n')
    f.write('let growthRate: [Int] = [' + ', '.join(map(str, growth)) + ']\n')
    f.write('let expTable: [[Int]] = [[], ' + ', '.join('[0, ' + ', '.join(str(exp[g][l]) for l in range(1, 101)) + ']' for g in range(1, 7)) + ']   // [rate][level]\n')
    f.write('let typeKo: [String: String] = [' + ', '.join(f'{s(k)}: {s(v)}' for k, v in sorted(tko.items()) if k in TYPES or k == 'fairy') + ']\n')
    f.write('let evolutionsGen4: [Evo] = [\n')
    def evo(frm, to, way, level, item, fem, time, place, party, ptype, rain, mtype):
        return (f'    Evo(from: {frm}, to: {to}, way: .{way}, level: {level}, item: {s(item) if item else "nil"}, female: {fem}, time: {s(time) if time else "nil"}, place: {s(place) if place else "nil"}, party: {party or "nil"}'
                + (f', partyType: {s(ptype)}' if ptype else '') + (f', weather: {s(rain)}' if rain else '') + (f', moveType: {s(mtype)}' if mtype else '') + '),\n')
    for e in evos:
        if e[1] <= N4: f.write(evo(*e))
    f.write(']\n')
    f.write('let evolutionsGen6Added: [Evo] = [\n')                                    # the Gen V-VI lines, 이브이 → 님피아 among them
    for e in evos:
        if e[1] > N4: f.write(evo(*e))
    f.write(']\n\n')
    courses = courses[:20] + sorted(courses[20:], key=lambda c: c['dex'])
    # --- more Pokémon per course (not in the original): each group gets 2 more candidates, plus 5 rare "guests" (10 % of radar finds).
    # By habitat (PokeAPI has it up to Gen III; Gen IV goes by primary type); group by catch rate: A < 75, B 75-149, C >= 150 (and a base form).
    hab = {r['id']: r['identifier'] for r in csv.DictReader(open(get('pokemon_habitats.csv')))}
    BY_TYPE = {'water': 'sea', 'grass': 'forest', 'bug': 'forest', 'rock': 'mountain', 'ground': 'rough-terrain', 'steel': 'mountain', 'ghost': 'cave',
               'dark': 'urban', 'poison': 'urban', 'normal': 'grassland', 'flying': 'grassland', 'fire': 'rough-terrain', 'ice': 'mountain',
               'electric': 'urban', 'psychic': 'urban', 'fighting': 'urban', 'dragon': 'mountain', 'fairy': 'grassland'}   # (fairy: Gen VI's only)
    HABITATS = {'field': {'grassland'}, 'forest': {'forest'}, 'mountain': {'mountain', 'rough-terrain'}, 'beach': {'sea', 'waters-edge'},
                'lake': {'waters-edge', 'sea'}, 'town': {'urban', 'grassland'}, 'cave': {'cave'}}
    def habitat(d): return hab.get(sp[d]['habitat_id']) or BY_TYPE[types[d][0]]
    legendary = {d for d in range(1, N4 + 1) if sp[d]['is_legendary'] == '1' or sp[d]['is_mythical'] == '1'}
    usable = [d for d in range(1, N4 + 1) if d not in legendary and sp[d]['is_baby'] == '0' and d != 292]
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
    assert sorted(legends + SHOP) == sorted(d for d in range(1, N4 + 1) if sp[d]['is_legendary'] == '1' or sp[d]['is_mythical'] == '1'), 'every legend exactly once'
    for name, need, base, ls in LEGEND: courses.append({**by[base], 'name': name, 'watts': 0, 'dex': need, 'legends': ls})
    # eggs: the bases of every line you can't otherwise reach (no legends; Shedinja comes from Nincada)
    reach = {25} | {sl[0] for c in courses for sl in c['slots']}                                     # eggs = bases the ORIGINAL tables miss (the extras overlap them on purpose)
    while True:
        more = {to for frm, to, *_ in evos if frm in reach and to <= N4} - reach
        if not more: break
        reach |= more
    pool = [d for d in range(1, N4 + 1) if not sp[d]['evolves_from_species_id'] and d not in reach and d not in legends and d not in SHOP and d != 292]
    base_of = lambda d: d if not sp[d]['evolves_from_species_id'] else base_of(int(sp[d]['evolves_from_species_id']))
    reach2 = reach | {d for d in range(1, N4 + 1) if base_of(d) in pool} | set(legends) | set(SHOP) | {292}
    assert reach2 == set(range(1, N4 + 1)), sorted(set(range(1, N4 + 1)) - reach2)
    f.write('let eggPoolGen4: [Int] = [' + ', '.join(map(str, pool)) + ']   // every line not on a course\n')
    # --- 5.0 (content5, plan 18 §8): 하나 6 and 칼로스 3 courses, after the 35. Each a regular course's steps, odds and items (and its slots' level
    # shape, banded by courseBands) with the region's own: A A B B C C from its first stages by catch rate, 2 more a group, 5 guests, spread so
    # every first stage walks somewhere; its first course open to all, the rest by that region's Pokédex count. The lines left over hatch from eggs.
    START, FOSSIL = {495, 498, 501, 650, 653, 656}, {564, 566, 696, 698}
    REGIONS = [((494, 649), [('하나 들판', 'field', '상쾌한 들판', 0), ('하나 숲', 'forest', '웅성웅성 숲', 10), ('하나 해변', 'beach', '아름다운 해변', 20),
                            ('하나 거리', 'town', '교외', 35), ('하나 산길', 'mountain', '울퉁불퉁 산길', 50), ('하나 동굴', 'cave', '어둑어둑 동굴', 70)]),
               ((650, 721), [('칼로스 들판', 'field', '호연 들판', 0), ('칼로스 해안', 'beach', '따뜻한 해변', 10), ('칼로스 산', 'mountain', '얼음 산길', 25)])]
    region_courses, on_course = [], set()
    for (lo, hi), plan in REGIONS:
        wild = [d for d in range(lo, hi + 1) if sp[d]['is_legendary'] == '0' and sp[d]['is_mythical'] == '0' and base_of(d) not in START | FOSSIL and base_of(d) >= lo]   # (not 님피아: 이브이's)
        firsts = [d for d in wild if not sp[d]['evolves_from_species_id']]
        rused = {}
        for ci, (name, art, base, need) in enumerate(plan):
            rnd = random.Random(1000 * lo + ci)
            b = by[base]; top = max(sl[1] for sl in b['slots'])
            home = [d for d in firsts if habitat(d) in HABITATS[art]]
            score = lambda d: (rused.get(d, 0), 0 if d in home else 1, rnd.random())     # the least walked first, its habitat's next
            slots, extra = [], []
            for g in range(3):
                pick = sorted([d for d in firsts if tier(d) == g and d not in slots], key=score)[:2]
                if len(pick) < 2: pick += sorted([d for d in firsts if d not in slots + pick], key=score)[:2 - len(pick)]
                for k, d in enumerate(pick):
                    rused[d] = rused.get(d, 0) + 1; bs = b['slots'][2 * g + k]
                    slots.append((d, bs[1], bs[2], bs[3], sp[d]['gender_rate'] == '8' or (sp[d]['gender_rate'] not in ('-1', '0') and rnd.random() < 0.5)))
            mine = {x[0] for x in slots}
            for g in range(3):
                lv = slots[2 * g][1]
                pick = sorted([d for d in wild if d not in mine and fits_level(d, lv) and (tier(d) == g or stage(d) > 0)], key=lambda d: (rused.get(d, 0), stage(d), 0 if habitat(d) in HABITATS[art] else 1, rnd.random()))[:2]
                for d in pick:
                    rused[d] = rused.get(d, 0) + 1; mine.add(d)
                    extra.append((d, slots[2 * g][1], slots[2 * g][2], slots[2 * g][3], sp[d]['gender_rate'] == '8' or (sp[d]['gender_rate'] not in ('-1', '0') and rnd.random() < 0.5)))
            assert len(slots) == 6 and len(extra) == 6, (name, slots, extra)
            guests = sorted([d for d in wild if d not in mine and fits_level(d, top)], key=lambda d: (rused.get(d, 0), stage(d), 0 if habitat(d) in HABITATS[art] else 1, rnd.random()))[:5]
            for d in guests: rused[d] = rused.get(d, 0) + 1
            tcount = {}
            for x in slots:
                for t in types[x[0]]: tcount[t] = tcount.get(t, 0) + 1
            ctypes = sorted(tcount, key=lambda t: (-tcount[t], t))[:2]
            region_courses.append(dict(name=name, watts=0, dex=need, types=ctypes, art=art, slots=slots, extra=extra, guests=guests, items=b['items'], region=(lo, hi)))
            on_course |= {x[0] for x in slots + extra} | set(guests)
    reach6 = set(on_course)
    while True:
        more = {to for frm, to, *_ in evos if frm in reach6} - reach6
        if not more: break
        reach6 |= more
    eggs6 = [d for d in range(N4 + 1, N + 1) if not sp[d]['evolves_from_species_id'] and d not in reach6 and sp[d]['is_legendary'] == '0' and sp[d]['is_mythical'] == '0']
    reach6 |= {d for d in range(N4 + 1, N + 1) if base_of(d) in eggs6}
    reach6 |= {d for d in range(N4 + 1, N + 1) if base_of(d) <= N4}                     # 님피아: 이브이's line, on the 4.1 courses
    legends6 = {d for d in range(N4 + 1, N + 1) if sp[d]['is_legendary'] == '1' or sp[d]['is_mythical'] == '1'}
    assert reach6 | legends6 >= set(range(N4 + 1, N + 1)), sorted(set(range(N4 + 1, N + 1)) - reach6 - legends6)
    assert set(firsts) and all(d in on_course for lo_hi, pl in REGIONS for d in range(lo_hi[0], lo_hi[1] + 1) if not sp[d]['evolves_from_species_id'] and sp[d]['is_legendary'] == '0' and sp[d]['is_mythical'] == '0' and d not in START | FOSSIL), 'every first stage walks somewhere'
    f.write('let eggPoolGen6Added: [Int] = [' + ', '.join(map(str, eggs6)) + ']   // content5: the Gen V-VI lines no course has (starters, fossils ...)\n')
    print(f'region courses: {len(region_courses)}, eggs added: {len(eggs6)}')
    f.write('let eggCycles: [Int] = [0, ' + ', '.join(sp[i]['hatch_counter'] for i in range(1, N + 1)) + ']   // x 255 steps (Gen IV)\n')
    # --- battles (Gen IV as in HGSS): base stats, base EXP, catch rate, level-up learnsets (damaging moves only — no status conditions here),
    # move data rolled back to HGSS through the changelog (e.g. 10만볼트 95, not today's 90), and the Gen IV type chart (no Fairy; Steel resists Ghost / Dark)
    stats = {}
    for r in csv.DictReader(open(get('pokemon_stats.csv'))):
        if int(r['pokemon_id']) <= N: stats.setdefault(int(r['pokemon_id']), {})[int(r['stat_id'])] = int(r['base_stat'])
    def rolled(gen, upto):                                                                 # the value that held in that generation
        out, past = {d: dict(v) for d, v in stats.items() if d <= upto}, {}
        for r in csv.DictReader(open(get('pokemon_stats_past.csv'))):
            d, k, g = int(r['pokemon_id']), int(r['stat_id']), int(r['generation_id'])
            if d <= upto and k <= 6 and g >= gen and g < past.get((d, k), (99, 0))[0]: past[(d, k)] = (g, int(r['base_stat']))
        for (d, k), (_, v) in past.items(): out[d][k] = v
        return out
    stats6 = rolled(6, N)                                                                  # Gen VI raised some (피카츄 방어 30 -> 40); Gen VII's raises rolled back
    stats = {**stats6, **rolled(4, N4)}                                                    # Gen IV's, for 1-493
    raised = {d: stats6[d] for d in range(1, N4 + 1) if stats6[d] != stats[d]}
    bexp = {int(r['id']): int(r['base_experience'] or 50) for r in csv.DictReader(open(get('pokemon.csv'))) if int(r['id']) <= N}
    vg = {r['id']: int(r['order']) for r in csv.DictReader(open(get('version_groups.csv')))}
    HG = vg['10']
    mv = {int(r['id']): dict(r) for r in csv.DictReader(open(get('moves.csv'))) if int(r['generation_id']) <= 4}
    N4M = max(i for i in mv if i < 10000)                                               # 467: the Gen IV moves (10001-: Colosseum's shadow moves)
    oldChance = {}                                                                      # a secondary effect's chance as it was in HGSS (move_meta only has today's)
    for r in sorted(csv.DictReader(open(get('move_changelog.csv'))), key=lambda r: vg[r['changed_in_version_group_id']], reverse=True):
        m = mv.get(int(r['move_id']))
        if m is None or vg[r['changed_in_version_group_id']] <= HG: continue
        for k in ('type_id', 'power', 'pp', 'accuracy', 'priority'):
            if r[k]: m[k] = r[k]                                                        # newest-first, so the earliest change after HGSS wins
        if r['effect_chance']: oldChance[int(r['move_id'])] = int(r['effect_chance'])
    # what the changelog misses (Gen V+ changes PokeAPI only has as today's values): priorities, Gen IX's healing PP, stat changes
    for i, pr in {182: 3, 197: 3, 203: 3, 245: 1, 252: 1}.items(): mv[i]['priority'] = str(pr)        # 방어 판별 버티기 +3, 신속 속이기 +1
    for i in (105, 135, 208, 303, 355, 156): mv[i]['pp'] = '10'                         # HP회복 알낳기 우유마시기 게으름피우기 날개쉬기 잠자기
    mko = {int(r['move_id']): r['name'] for r in csv.DictReader(open(get('move_names.csv'))) if r['local_language_id'] == '3'}
    # moves this engine can't do right: 속이기 (first turn + flinch), ones that need sleep / a charge / an item / a delay, and self-KOs that would just be free 200-power hits
    known = set(mv)                                                                     # every Gen I-IV move; Battle.swift knows which ones it can run
    mv6ids = {int(r['id']) for r in csv.DictReader(open(get('moves.csv'))) if int(r['generation_id']) <= 6}
    learn, oras = {}, {}
    for r in csv.DictReader(open(get('pokemon_moves.csv'))):
        d, i = int(r['pokemon_id']), int(r['move_id'])
        if d <= N4 and r['version_group_id'] == '10' and r['pokemon_move_method_id'] == '1' and i in known:
            learn.setdefault(d, set()).add((int(r['level']), i))
        if d <= N and r['version_group_id'] == '16' and r['pokemon_move_method_id'] == '1' and i in mv6ids:
            oras.setdefault(d, set()).add((int(r['level']), i))
    for d in range(N4 + 1, N + 1): learn[d] = oras.get(d, set())
    # the 20 retyped keep HGSS's and add ORAS's new Fairy moves (천사의키스 · 애교부리기 · 달빛 were already there, as Normal);
    # 픽시 문포스 46 and 토게키스 요정의바람 1 (stone evolutions: what 삐삐 · 토게틱 learn) are the user's (plan 18 §2.1); so is 이브이's 천사의키스
    # at 9 (님피아 wants a Fairy move, and HGSS's 이브이 learns none)
    fairy6 = {int(r['id']) for r in csv.DictReader(open(get('moves.csv'))) if int(r['id']) > 467 and int(r['generation_id']) <= 6 and tname[r['type_id']] == 'fairy'}
    fairyAdd = {d: {(l, i) for l, i in oras.get(d, set()) if i in fairy6} for d in retyped}
    fairyAdd[36].add((46, 585)); fairyAdd[468].add((1, 584)); fairyAdd[133] = {(9, 186)}
    for add in fairyAdd.values():                                                       # ORAS lists 가디안's 문포스 · 입치트's 치근거리기 at 1 too: the real level only
        add -= {(1, i) for l, i in add if l > 1}
    learn6 = {d: learn.get(d, set()) | add for d, add in fairyAdd.items() if add}
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
    f.write('let baseStatsGen4: [[Int]] = [[], ' + ', '.join('[' + ', '.join(str(stats[d][k]) for k in range(1, 7)) + ']' for d in range(1, N + 1)) + ']   // HP Atk Def SpA SpD Spe\n')
    f.write('let baseStatsGen6Changes: [Int: [Int]] = [' + ', '.join(f'{d}: [' + ', '.join(str(v[k]) for k in range(1, 7)) + ']' for d, v in sorted(raised.items())) + ']\n')
    f.write('let baseExp: [Int] = [0, ' + ', '.join(str(bexp[d]) for d in range(1, N + 1)) + ']\n')
    f.write('let catchRate: [Int] = [0, ' + ', '.join(sp[d]['capture_rate'] for d in range(1, N + 1)) + ']\n')
    f.write('let stageOf: [Int] = [0, ' + ', '.join(str(stage(d)) for d in range(1, N + 1)) + ']\n')
    # --- battle data for the full Gen IV engine: every move with its meta (ailment, stat changes, hits, drain, crit, flinch, flags),
    # abilities as they were in Gen IV (pokemon_abilities_past rolls back later changes, e.g. 팬텀 = 부유), natures, EV yields, weight, gender ratio
    meta = {int(r['move_id']): r for r in csv.DictReader(open(get('move_meta.csv')))}
    ail = {r['id']: r['identifier'] for r in csv.DictReader(open(get('move_meta_ailments.csv')))}
    sch = {}
    for r in csv.DictReader(open(get('move_meta_stat_changes.csv'))): sch.setdefault(int(r['move_id']), []).append((int(r['stat_id']), int(r['change'])))
    sch.update({229: [], 74: [(4, 1)], 107: [(8, 1)], 230: [(8, -1)], 81: [(6, -1)], 294: [(4, 2)]})   # Gen IV: 고속스핀 no Speed, 성장 특공 only, 작아지기 / 달콤한향기 / 실뿜기 ±1, 반딧불 +2
    for i, c in oldChance.items():                                                      # the old chance goes on whichever secondary the move has
        me = meta.get(i)
        if me: me.update({k: str(c) for k in ('ailment_chance', 'flinch_chance', 'stat_chance') if int(me.get(k) or 0) > 0})
    if 305 in meta: meta[305]['ailment_chance'] = '30'                                  # 맹독엄니: 30 % in Gen IV
    if 448 in meta: meta[448]['ailment_chance'] = '10'                                  # 수다: by the recorded cry's loudness in Gen IV (0-31 %), not today's sure confusion
    KIND = {'2': 0, '3': 1, '1': 2}                                                     # physical, special, status
    FLAG = {'1': 1, '8': 2, '9': 4, '4': 8, '5': 16, '6': 32, '3': 64, '2': 128, '10': 256, '11': 512, '13': 1024}   # contact punch sound protect reflectable snatch recharge charge gravity defrost heal
    flags = {}
    for r in csv.DictReader(open(get('move_flag_map.csv'))): flags[int(r['move_id'])] = flags.get(int(r['move_id']), 0) | FLAG.get(r['move_flag_id'], 0)
    with open('Sources/Data/BattleData.swift', 'w') as g:
        g.write('// Generated by tools/gen.py (PokeAPI, rolled back to HGSS / Gen IV; the Gen6 tables to ORAS). Do not edit by hand.\n\n')
        # one statement per move: a single 485-entry literal took swiftc 13 s to type-check, statements are checked one at a time
        def moveInfo(i, m, me, sch, flags):
            def n(k, d=0): return int(me.get(k) or d)
            return (f'MoveInfo(id: {i}, name: {s(mko.get(i, m["identifier"]))}, type: {s(tid[m["type_id"]])}, power: {m["power"] or 0}, accuracy: {m["accuracy"] or 0}, '
                    f'kind: {KIND[m["damage_class_id"]]}, priority: {m["priority"]}, pp: {m["pp"] or 1}, cat: {n("meta_category_id")}, target: {m["target_id"]}, '
                    f'ailment: {s(ail.get(me.get("meta_ailment_id", "0"), "none"))}, ailmentChance: {n("ailment_chance")}, flinch: {n("flinch_chance")}, '
                    f'stats: [{", ".join(f"{a}, {b}" for a, b in sch.get(i, []))}], statChance: {n("stat_chance")}, minHits: {n("min_hits")}, maxHits: {n("max_hits")}, '
                    f'minTurns: {n("min_turns")}, maxTurns: {n("max_turns")}, drain: {n("drain")}, healing: {n("healing")}, crit: {n("crit_rate")}, flags: {flags.get(i, 0)})')
        g.write('let moveTableGen4 = Dictionary(uniqueKeysWithValues: allMoves().map { ($0.id, $0) })\n')
        g.write('@_optimize(none) private func allMoves() -> [MoveInfo] {\n    var m: [MoveInfo] = []\n')
        line4 = {i: moveInfo(i, mv[i], meta.get(i, {}), sch, flags) for i in sorted(mv)}
        for i in sorted(mv): g.write(f'    m.append({line4[i]})\n')
        g.write('    return m\n}\n')
        # Gen VI (content5): 1-467 rolled back to ORAS (vg 16) instead of HGSS (화염방사 90, 탁쳐서떨구기 65 ...) and 468-621, both as of ORAS;
        # only what differs from the Gen IV table. 251 집단구타 · 386 혼내기 keep Gen IV's: the engine works their power out.
        T6 = vg['16']
        mv6 = {int(r['id']): dict(r) for r in csv.DictReader(open(get('moves.csv'))) if int(r['generation_id']) <= 6}
        old6 = {}
        for r in sorted(csv.DictReader(open(get('move_changelog.csv'))), key=lambda r: vg[r['changed_in_version_group_id']], reverse=True):
            m = mv6.get(int(r['move_id']))
            if m is None or vg[r['changed_in_version_group_id']] <= T6: continue
            for k in ('type_id', 'power', 'pp', 'accuracy', 'priority'):
                if r[k]: m[k] = r[k]
            if r['effect_chance']: old6[int(r['move_id'])] = int(r['effect_chance'])
        for i in (105, 135, 208, 303, 355, 156): mv6[i]['pp'] = '10'                    # Gen IX's healing PP 5 came after ORAS
        meta6 = {int(r['move_id']): r for r in csv.DictReader(open(get('move_meta.csv')))}
        sch6 = {}
        for r in csv.DictReader(open(get('move_meta_stat_changes.csv'))): sch6.setdefault(int(r['move_id']), []).append((int(r['stat_id']), int(r['change'])))
        sch6[229] = []                                                                   # 고속스핀's Speed +1 is Gen VIII's
        sch6[591] = [(3, 1)]                                                             # 다이아스톰: 방어 +1 in Gen VI (+2 is Gen VII's)
        mv6[594]['damage_class_id'] = '2'                                               # 물수리검: physical in Gen VI (special from Gen VII)
        for i, c in old6.items():
            me = meta6.get(i)
            if me: me.update({k: str(c) for k in ('ailment_chance', 'flinch_chance', 'stat_chance') if int(me.get(k) or 0) > 0})
        FLAG6 = {**FLAG, '14': 2048, '15': 4096, '16': 8192, '17': 16384, '18': 32768, '19': 65536}   # + authentic (sound through a substitute) powder bite pulse ballistics mental
        flags6 = {}
        for r in csv.DictReader(open(get('move_flag_map.csv'))): flags6[int(r['move_id'])] = flags6.get(int(r['move_id']), 0) | FLAG6.get(r['move_flag_id'], 0)
        line6 = {i: moveInfo(i, mv6[i], meta6.get(i, {}), sch6, flags6) for i in sorted(mv6)}
        moves6 = [i for i in sorted(mv6) if N4M < i < 10000 or i in line4 and line6[i] != line4[i] and i not in (251, 386)]
        g.write('let moveTableGen6Changes = Dictionary(uniqueKeysWithValues: gen6Moves().map { ($0.id, $0) })\n')
        g.write('@_optimize(none) private func gen6Moves() -> [MoveInfo] {\n    var m: [MoveInfo] = []\n')
        for i in moves6: g.write(f'    m.append({line6[i]})\n')
        g.write('    return m\n}\n')
        print(f'Gen VI moves: {sum(i <= N4M for i in moves6)} of 1-{N4M} differ, {sum(N4M < i < 10000 for i in moves6)} new')
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
        ab = [[a for sl, a in sorted(slots.get(d, {}).items()) if a <= 123] for d in range(N4 + 1)]
        assert all(ab[d] for d in range(1, N4 + 1)), [d for d in range(1, N4 + 1) if not ab[d]]
        assert ab[94] == [26], ab[94]                                                    # 팬텀: 부유 in Gen IV
        def rolledAbilities(gen, hidden):                                                # as they were in that generation (pokemon_abilities_past); forms' rows too
            sl, past = {}, {}
            ok = lambda d: d <= N or d > 10000
            for r in csv.DictReader(open(get('pokemon_abilities.csv'))):
                d = int(r['pokemon_id'])
                if ok(d) and (r['is_hidden'] == '1') == hidden: sl.setdefault(d, {})[int(r['slot'])] = int(r['ability_id'])
            for r in csv.DictReader(open(get('pokemon_abilities_past.csv'))):
                d, gg, k = int(r['pokemon_id']), int(r['generation_id']), int(r['slot'])
                if ok(d) and (k == 3) == hidden and gg >= gen and gg < past.get((d, k), (99, None))[0]: past[(d, k)] = (gg, int(r['ability_id']) if r['ability_id'] else None)
            for (d, k), (_, a) in past.items():
                if a is None: sl.setdefault(d, {}).pop(k, None)
                else: sl.setdefault(d, {})[k] = a
            return sl
        s6, h6 = rolledAbilities(6, False), rolledAbilities(6, True)
        wt = {int(r['id']): int(r['weight']) for r in csv.DictReader(open(get('pokemon.csv'))) if int(r['id']) <= N}
        ab6 = [[a for k, a in sorted(s6.get(d, {}).items()) if k in (1, 2)] for d in range(N + 1)]
        hidden = [0] + [h6.get(d, {}).get(3, 0) for d in range(1, N + 1)]
        assert all(ab6[d] and max(ab6[d]) <= 191 for d in range(1, N + 1)) and max(hidden) <= 191, 'a Gen VII+ ability left'
        assert ab6[94] == [26] and hidden[94] == 0 and ab6[460] == [117] and hidden[460] == 43, (ab6[94], hidden[94], ab6[460], hidden[460])   # 팬텀 부유; 눈설왕 눈퍼뜨리기 (방음)
        abChanges = {d: ab6[d] for d in range(1, N4 + 1) if ab6[d] != ab[d]}
        g.write('let abilitySlotsGen4: [[Int]] = [[], ' + ', '.join('[' + ', '.join(map(str, ab[d] if d <= N4 else ab6[d])) + ']' for d in range(1, N + 1)) + ']\n')
        g.write('let abilitySlotsGen6Changes: [Int: [Int]] = [' + ', '.join(f'{d}: [' + ', '.join(map(str, v)) + ']' for d, v in sorted(abChanges.items())) + ']\n')
        g.write('let hiddenAbility: [Int] = [' + ', '.join(map(str, hidden)) + ']   // content5: Gen VI\'s hidden ability (Mon.ability 2), 0 none\n')
        # --- forms (content5, plan 18 §5 · §6): per species, forms 1... (Mon.form; 0 = the species, the tables above), as of ORAS. Only what a form
        # changes: types, stats, abilities, hidden, weight, its own level-up moves; a Mega its stone. Left out: 피카츄's costumes, 뾰족귀 피츄,
        # 영원의 꽃 플라엣테 (events), 아르세우스 · 게노세크트 (their held item does it), and Gen VII+.
        pk = {int(r['id']): r for r in csv.DictReader(open(get('pokemon.csv')))}
        fko = {int(r['pokemon_form_id']): r['form_name'] or r['pokemon_name'] for r in csv.DictReader(open(get('pokemon_form_names.csv'))) if r['local_language_id'] == '3'}
        ptypes, pstats = {}, {}
        for r in csv.DictReader(open(get('pokemon_types.csv'))): ptypes.setdefault(int(r['pokemon_id']), []).append((int(r['slot']), tid[r['type_id']]))
        for r in csv.DictReader(open(get('pokemon_stats.csv'))):
            if int(r['stat_id']) <= 6: pstats.setdefault(int(r['pokemon_id']), {})[int(r['stat_id'])] = int(r['base_stat'])
        fpast = {}
        for r in csv.DictReader(open(get('pokemon_stats_past.csv'))):                  # Gen VII's changes rolled back (메가후딘 특수방어 105 -> 95)
            d, k, gg = int(r['pokemon_id']), int(r['stat_id']), int(r['generation_id'])
            if d > 10000 and k <= 6 and gg >= 6 and gg < fpast.get((d, k), (99, 0))[0]: fpast[(d, k)] = (gg, int(r['base_stat']))
        for (d, k), (_, v) in fpast.items(): pstats[d][k] = v
        flearn = {}
        for r in csv.DictReader(open(get('pokemon_moves.csv'))):
            d, i = int(r['pokemon_id']), int(r['move_id'])
            if d > 10000 and r['pokemon_move_method_id'] == '1' and i in mv6ids and r['version_group_id'] in ('10', '16'): flearn.setdefault((d, r['version_group_id']), set()).add((int(r['level']), i))
        icat = {r['id']: r['identifier'] for r in csv.DictReader(open(get('item_categories.csv')))}
        stones = {r['identifier']: ko_item[r['id']] for r in csv.DictReader(open(get('items.csv'))) if icat[r['category_id']] == 'mega-stones' and int(r['id']) <= 811}
        def stone(ident):                                                               # charizard-mega-x -> charizardite-x: the longest shared start
            base, xy = ident.split('-mega')[0], ident.split('-mega')[1][1:]
            pre = lambda a, b: next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
            c = [k for k in stones if (k.endswith('-' + xy) if xy else not k[-2:] in ('-x', '-y'))]
            return stones[max(c, key=lambda k: pre(k, base))]
        SKIP = {'pichu-spiky-eared', 'floette-eternal'}
        forms = {}
        for r in sorted(csv.DictReader(open(get('pokemon_forms.csv'))), key=lambda r: (int(r['pokemon_id']), int(r['form_order']), int(r['id']))):
            pid, d = int(r['pokemon_id']), int(pk[int(r['pokemon_id'])]['species_id'])
            if d > N or int(r['introduced_in_version_group_id']) > 16 or r['identifier'] in SKIP or d in (25, 493, 649): continue
            if r['is_default'] == '1' and pid < 10000: continue                                # the species itself
            kind = 'mega' if r['is_mega'] == '1' else 'primal' if r['identifier'].endswith('-primal') else 'battle' if r['is_battle_only'] == '1' else 'stored' if pid > 10000 else 'look'
            name = ('원시' + ko[d]) if kind == 'primal' else fko[int(r['id'])]
            x = {'name': s(name), 'kind': '.' + kind}
            if pid > 10000:
                ty = [t for _, t in sorted(ptypes[pid])]; st = [pstats[pid][k] for k in range(1, 7)]
                ab = [a for k, a in sorted(s6.get(pid, {}).items()) if k in (1, 2)]; hd = h6.get(pid, {}).get(3, 0)
                assert ab and max(ab) <= 191 and hd <= 191, (r['identifier'], ab, hd)
                base6 = (types6[d], stats6[d], ab6[d], hidden[d], wt[d])
                if ty != base6[0]: x['types'] = '[' + ', '.join(map(s, ty)) + ']'
                if [stats6[d][k] for k in range(1, 7)] != st: x['stats'] = '[' + ', '.join(map(str, st)) + ']'
                if ab != base6[2]: x['abilities'] = '[' + ', '.join(map(str, ab)) + ']'
                if hd != base6[3]: x['hidden'] = str(hd)
                if int(pk[pid]['weight']) != wt[d]: x['weight'] = f'{int(pk[pid]["weight"]) / 10:g}'
                ls = flearn.get((pid, '10' if d <= N4 else '16'))
                if ls and ls != learn.get(d, set()): x['learnset'] = '[' + ', '.join(f'{l}, {i}' for l, i in sorted(ls)) + ']'
            if kind == 'mega' and d != 384: x['item'] = s(stone(r['identifier']))             # 메가레쿠쟈: 화룡점정, no stone
            if kind == 'primal': x['item'] = s({'kyogre-primal': '쪽빛구슬', 'groudon-primal': '주홍구슬'}[r['identifier']])
            forms.setdefault(d, []).append(x)
        megas = [x for fs in forms.values() for x in fs if x['kind'] == '.mega']
        assert len(megas) == 48 and len({x['item'] for x in megas if 'item' in x}) == 47 == len(stones), (len(megas), len(stones))
        g.write('let monForms = formTable()   // content5: species -> its forms 1... (Mon.form)\n@_optimize(none) private func formTable() -> [Int: [MonForm]] {\n    var f: [Int: [MonForm]] = [:]\n')
        for d, fs in sorted(forms.items()):
            g.write(f'    f[{d}] = [' + ', '.join('MonForm(' + ', '.join(f'{k}: {v}' for k, v in x.items()) + ')' for x in fs) + ']\n')
        g.write('    return f\n}\n')
        print(f'forms: {sum(map(len, forms.values()))} on {len(forms)} species ({len(megas)} megas)')
        an = {int(r['ability_id']): r['name'] for r in csv.DictReader(open(get('ability_names.csv'))) if r['local_language_id'] == '3'}
        g.write('let abilityNames: [Int: String] = [' + ', '.join(f'{i}: {s(an[i])}' for i in range(1, 192)) + ']\n')
        # what each does, in Korean: the earliest Korean flavour text (X/Y; line breaks are the games' layout)
        fl = {}
        for r in csv.DictReader(open(get('ability_flavor_text.csv'))):
            a, vg = int(r['ability_id']), int(r['version_group_id'])
            if r['language_id'] == '3' and a <= 191 and (a not in fl or vg < fl[a][0]): fl[a] = (vg, ' '.join(r['flavor_text'].split()))
        assert len(fl) == 191, sorted(set(range(1, 192)) - set(fl))
        fl6 = {a: fl[a][1] for a in (1, 5, 12, 31, 114)}                                   # content5: what the X/Y text says is what they do in Gen VI
        # where the X/Y text describes a later generation's effect, what it does here (Gen IV, singles only); 6: a line break had split 폭발할
        fl.update({a: (0, t) for a, t in {1: '배틀에서는 효과가 없다.', 5: '일격필살 기술을 받지 않는다.', 6: '누구도 폭발할 수 없게 된다.', 12: '헤롱헤롱 상태가 되지 않는다.',
                                          31: '전기 기술을 끌어모은다. 싱글 배틀에서는 효과가 없다.', 114: '물 기술을 끌어모은다. 싱글 배틀에서는 효과가 없다.',
                                          57: '마이너스와 함께 싸우면 특수공격이 오른다. 싱글 배틀에서는 효과가 없다.', 58: '플러스와 함께 싸우면 특수공격이 오른다. 싱글 배틀에서는 효과가 없다.'}.items()})
        g.write('let abilityDescsGen4: [Int: String] = [' + ', '.join(f'{i}: {s(fl[i][1])}' for i in range(1, 192)) + ']\n')
        g.write('let abilityDescsGen6Changes: [Int: String] = [' + ', '.join(f'{i}: {s(t)}' for i, t in sorted(fl6.items())) + ']\n')
        nat = list(csv.DictReader(open(get('natures.csv'))))
        nko = {r['nature_id']: r['name'] for r in csv.DictReader(open(get('nature_names.csv'))) if r['local_language_id'] == '3'}
        g.write('let natures: [(name: String, up: Int, down: Int)] = [' + ', '.join(f'({s(nko[r["id"]])}, {int(r["increased_stat_id"]) - 1}, {int(r["decreased_stat_id"]) - 1})' for r in sorted(nat, key=lambda r: int(r['game_index']))) + ']   // stat index 1-5, up == down = neutral\n')
        ev = {}
        for r in csv.DictReader(open(get('pokemon_stats.csv'))):
            if int(r['pokemon_id']) <= N: ev.setdefault(int(r['pokemon_id']), {})[int(r['stat_id'])] = int(r['effort'])
        g.write('let evYield: [[Int]] = [[], ' + ', '.join('[' + ', '.join(str(ev[d][k]) for k in range(1, 7)) + ']' for d in range(1, N + 1)) + ']\n')
        g.write('let weightKg: [Double] = [0, ' + ', '.join(f'{wt[d] / 10:g}' for d in range(1, N + 1)) + ']\n')
        g.write('let genderRate: [Int] = [0, ' + ', '.join(sp[d]['gender_rate'] for d in range(1, N + 1)) + ']   // -1 genderless, else eighths female\n')
    f.write('let learnsetsGen4: [[Int]] = [[], ' + ', '.join('[' + ', '.join(f'{l}, {i}' for l, i in sorted(learn.get(d, set()))) + ']' for d in range(1, N + 1)) + ']   // level, move, level, move ...\n')
    f.write('let learnsetsGen6Changes: [Int: [Int]] = [' + ', '.join(f'{d}: [' + ', '.join(f'{l}, {i}' for l, i in sorted(v)) + ']' for d, v in sorted(learn6.items())) + ']\n')
    f.write('let typeChartGen4 = typeRows()\n@_optimize(none) private func typeRows() -> [String: [String: Double]] {\n    var c: [String: [String: Double]] = [:]\n')   # a row a statement: quick to type-check
    for a, row in sorted(chart.items()): f.write(f'    c[{s(a)}] = [' + ', '.join(f'{s(b)}: {float(v)!r}' for b, v in sorted(row.items())) + ']\n')
    f.write('    return c\n}\n')
    chart6 = {}
    for r in csv.DictReader(open(get('type_efficacy.csv'))):
        a, b = tid[r['damage_type_id']], tid[r['target_type_id']]
        if r['damage_factor'] != '100' and a in TYPES + ['fairy'] and b in TYPES + ['fairy']: chart6.setdefault(a, {})[b] = int(r['damage_factor']) / 100
    assert chart6['dragon']['fairy'] == 0 and chart6['ghost'].get('steel', 1) == 1 and chart6['fairy']['dragon'] == 2
    f.write('let typeChartGen6 = typeRows6()\n@_optimize(none) private func typeRows6() -> [String: [String: Double]] {\n    var c: [String: [String: Double]] = [:]\n')
    for a, row in sorted(chart6.items()): f.write(f'    c[{s(a)}] = [' + ', '.join(f'{s(b)}: {float(v)!r}' for b, v in sorted(row.items())) + ']\n')
    f.write('    return c\n}\n')
    f.write('let rawCourses: [Course] = [\n')   # Model/Course.swift bands its levels into `courses`
    def course(c):
        f.write(f'    Course(name: {s(c["name"])}, watts: {c["watts"]}, dex: {c["dex"]}, legends: [{", ".join(map(str, c.get("legends", [])))}], types: [{", ".join(s(x) for x in c["types"])}], art: .{c["art"]},\n')
        f.write('           slots: [' + ', '.join(f'Slot(dex: {d}, level: {l}, steps: {st}, chance: {ch:g}, female: {str(fe).lower()})' for d, l, st, ch, fe in c['slots']) + '],\n')
        f.write('           extra: [' + ', '.join(f'Slot(dex: {d}, level: {l}, steps: {st}, chance: {ch:g}, female: {str(fe).lower()})' for d, l, st, ch, fe in c['extra']) + '],\n')
        f.write('           guests: [' + ', '.join(map(str, c['guests'])) + '],\n')
        f.write('           items: [' + ', '.join(f'Find(item: {s(n)}, steps: {st}, chance: {ch})' for n, st, ch in c['items']) + ']'
                + (f', region: {c["region"][0]}...{c["region"][1]}' if c.get('region') else '') + '),\n')
    for c in courses: course(c)
    f.write(']\n')
    f.write('let rawCoursesGen6Added: [Course] = [\n')   # content5: 하나 6, 칼로스 3 (their dex = that region\'s count)
    for c in region_courses: course(c)
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
print('ok', len(courses), 'courses' + (f', {len(hout)} hgss sprite bytes, {len(iout)} icon bytes' if ARTWORK else ' (tables only)'))
