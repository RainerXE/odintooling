#!/usr/bin/env python3
"""
crosscheck_c001.py — compare the lint rule C001 with the ownership graph, on real projects.

C001 reads one block at a time; the graph's ownership analysis follows each allocation through the
whole procedure (and across procedures). Where they disagree, one of them is wrong, which makes the
comparison a way to find bugs in either. For every project it lists

  agree           C001 flags it and the graph says the memory is never freed (default/param allocator)
  c001 only       C001 flags it but the graph sees it freed, returned, stored, passed on, or from an
                  allocator that is released wholesale (temp, arena)
  graph only      the graph says it is never freed and C001 is silent

Usage:  scripts/crosscheck_c001.py [-v] <project dir> [<project dir> ...]

Each project gets a graph exported into <dir>/.codegraph/g.db (the usual place); nothing else is written.
"""
import collections, os, platform, re, sqlite3, subprocess, sys

def find_olt():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    plat = {"Darwin-arm64": "macos-arm64", "Darwin-x86_64": "macos-x86_64",
            "Linux-x86_64": "linux-x86_64", "Linux-aarch64": "linux-arm64"}.get(
            f"{platform.system()}-{platform.machine()}", "")
    path = os.path.join(root, "artifacts", plat, "olt")
    if not os.path.exists(path):
        sys.exit(f"olt binary not found at {path} — run ./scripts/build.sh first")
    return path

def main(argv):
    verbose = "-v" in argv
    dirs = [a for a in argv if not a.startswith("-")]
    if not dirs:
        sys.exit(__doc__)
    olt = find_olt()
    total = collections.Counter()
    for d in dirs:
        root = os.path.realpath(d)
        subprocess.run([olt, "--export-symbols", "--db", ".codegraph/g.db", "."], cwd=root,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=900)
        db = os.path.join(root, ".codegraph", "g.db")
        if not os.path.exists(db):
            print(f"{d}: no graph produced"); continue
        lint = subprocess.run([olt, "--rule", "C001", "."], cwd=root, capture_output=True, text=True, timeout=900).stdout
        c001 = set()
        for m in re.finditer(r"(\S+?):(\d+):(\d+): C001", lint):
            f = m.group(1)
            c001.add((os.path.relpath(f, root) if f.startswith("/") else f, int(m.group(2))))
        con = sqlite3.connect(db)
        sites = {}
        for f, ln, api, kind, disp, var, pn in con.execute(
                "select p.file_path, a.line, a.api, a.allocator_kind, a.disposition, coalesce(a.var_name,''), p.name "
                "from odin_alloc_site a join nodes p on p.id=a.proc_id where a.api in ('make','new')"):
            sites[(f, ln)] = (api, kind, disp, var, pn)
        rows = collections.defaultdict(list)
        for key in sorted(c001):
            s = sites.get(key)
            if s is None:
                rows["c001 only (no graph site)"].append((key, None)); continue
            owned_unfreed = s[2] == "unfreed" and s[1] in ("default", "param")
            rows["agree" if owned_unfreed else f"c001 only: graph says {s[2]} / {s[1]} allocator"].append((key, s))
        for key, s in sorted(sites.items()):
            if key not in c001 and s[2] == "unfreed" and s[1] in ("default", "param"):
                rows["graph only (unfreed, default/param allocator)"].append((key, s))
        print(f"== {d}: C001 flags {len(c001)}, graph has {len(sites)} make/new sites")
        for cat, items in sorted(rows.items()):
            print(f"   {len(items):4d}  {cat}")
            total[cat.split(":")[0]] += len(items)
            if verbose:
                for (f, ln), s in items:
                    print(f"           {f}:{ln}" + (f"  {s[4]}: {s[3] or '-'}" if s else ""))
    print("== all projects:", dict(total))

if __name__ == "__main__":
    main(sys.argv[1:])
