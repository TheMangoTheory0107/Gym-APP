"""Merges foods_new.txt (+ fibre for existing foods) into IronLog/Resources/Data/foods.json.
Run from the repo root: python3 tools/food/build_foods.py"""
import json, re, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from fibre_existing import FIB

path = "IronLog/Resources/Data/foods.json"
data = json.load(open(path))
foods = data["foods"]
ids = {f["id"] for f in foods}
names = {f["name"].lower() for f in foods}

def num(x):
    x = float(x)
    return int(x) if x == int(x) else x

for f in foods:
    if "fiber" not in f:
        f["fiber"] = num(FIB.get(f["id"], 0))

added, warn = 0, []
for line in open(os.path.join(os.path.dirname(__file__), "foods_new.txt")):
    line = line.strip()
    if not line or line.startswith("#"): continue
    name, aliases, macros, units, cat = [p.strip() for p in line.split("|")]
    if name.lower() in names: continue
    k, p, c, fat, fib = [float(x) for x in macros.split(",")]
    fid = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    while fid in ids: fid += "-2"
    u = {}
    for kv in filter(None, units.split(";")):
        a, b = kv.split("="); u[a.strip()] = num(b)
    est = 4 * p + 4 * c + 9 * fat
    if k > 30 and abs(est - k) / k > 0.25 and cat != "Drinks":
        warn.append(f"{name}: {k} vs {round(est)}")
    foods.append({"id": fid, "name": name, "category": cat,
                  "aliases": [a.strip() for a in aliases.split(",") if a.strip()],
                  "kcal": num(k), "protein": num(p), "carbs": num(c), "fat": num(fat), "fiber": num(fib), "units": u})
    ids.add(fid); names.add(name.lower()); added += 1

order = ["id", "name", "category", "aliases", "kcal", "protein", "carbs", "fat", "fiber", "units"]
data["_readme"] = ("Values per 100 g (or 100 ml): kcal, protein, carbs, fat, fiber. 'units' = grams in one household "
                   "unit for that food. Typical values (IFCT / common recipes); home cooking varies with oil.")
with open(path, "w") as fh:
    fh.write("{\n")
    fh.write('  "_readme": ' + json.dumps(data["_readme"]) + ",\n")
    fh.write('  "genericUnits": ' + json.dumps({**data["genericUnits"], "bunch": 150, "peg": 30}) + ",\n")
    fh.write('  "foods": [\n' + ",\n".join("    " + json.dumps({k: f[k] for k in order if k in f}, ensure_ascii=False) for f in foods) + "\n  ]\n}\n")
print("added", added, "total", len(foods))
for w in warn: print("CHECK", w)
