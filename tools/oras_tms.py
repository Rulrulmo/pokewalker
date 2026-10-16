#!/usr/bin/env python3
# ORAS's TM / HM compatibility (version group 16, method 4 = machine) from tools/.cache/pokemon_moves.csv: {dex: [move ids]} for 1-721's
# own forms, on stdout. For plan 19 §2 (5.2's TMs) and the Mega ranking's MEGA_RANK_TM (server/Tests/PokeCoreTests/MegaRank.swift).
import csv, json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
out = {}
for r in csv.DictReader(open(os.path.join(here, '.cache', 'pokemon_moves.csv'))):
    if r['version_group_id'] == '16' and r['pokemon_move_method_id'] == '4' and int(r['pokemon_id']) <= 721:
        out.setdefault(int(r['pokemon_id']), set()).add(int(r['move_id']))
json.dump({str(k): sorted(v) for k, v in sorted(out.items())}, sys.stdout, separators=(',', ':'))
