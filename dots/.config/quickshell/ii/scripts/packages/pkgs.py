#!/usr/bin/env python3
"""Read-only package queries for the Packages app, answered as JSON on stdout.

    pkgs.py updates            repo updates (checkupdates) and AUR updates (yay -Qua)
    pkgs.py installed          every installed package, with the fields the list shows
    pkgs.py search QUERY       repo matches, and AUR matches with --aur
    pkgs.py info NAME          the full details of one package, installed or not
    pkgs.py orphans            dependencies nothing needs any more
    pkgs.py cache              what the pacman cache holds

Changing anything (install, remove, upgrade) is not done here: the app runs pacman
itself through pkexec so the password prompt and the log are the shell's.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time

ENV = dict(os.environ, LC_ALL="C", LANG="C")
UNITS = {"B": 1, "KiB": 1024, "MiB": 1024**2, "GiB": 1024**3, "TiB": 1024**4}


def run(cmd, timeout=120):
    try:
        done = subprocess.run(cmd, capture_output=True, text=True, env=ENV, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as err:
        return 255, "", str(err)
    return done.returncode, done.stdout, done.stderr


def size_bytes(text):
    match = re.match(r"([\d.]+)\s*(\w+)", text or "")
    if not match:
        return 0
    return int(float(match.group(1)) * UNITS.get(match.group(2), 1))


def parse_blocks(text):
    """`pacman -Qi/-Si` output as one dict per package; keys are the field names."""
    packages = []
    for block in text.split("\n\n"):
        fields = {}
        key = None
        for line in block.splitlines():
            match = re.match(r"^(\S[^:]*?)\s+:\s?(.*)$", line)
            if match:
                key = match.group(1)
                fields[key] = match.group(2)
            elif key and line.strip():
                fields[key] += " " + line.strip()
        if "Name" in fields:
            packages.append(fields)
    return packages


def listify(value):
    if not value or value == "None":
        return []
    return [part for part in re.split(r"\s{2,}", value.strip()) if part]


LOCAL_DB = "/var/lib/pacman/local"
SYNC_DB = "/var/lib/pacman/sync"
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "ii-packages")


def sync_signature():
    """Changes whenever pacman refreshes or adds a sync database."""
    try:
        return sorted((e.name, e.stat().st_mtime_ns) for e in os.scandir(SYNC_DB) if e.name.endswith(".db"))
    except OSError:
        return []


def repo_map():
    """name -> repository, for every package the sync databases know.

    `pacman -Sl` reads every sync database (over a second here), so its answer is kept
    until the databases change. The first repository listed wins, as it does for pacman."""
    cache_file = os.path.join(CACHE, "repos.json")
    signature = sync_signature()
    try:
        with open(cache_file) as f:
            cached = json.load(f)
        if cached.get("signature") == json.loads(json.dumps(signature)):
            return cached["repos"]
    except (OSError, ValueError, KeyError, AttributeError):
        pass
    mapping = {}
    code, out, _ = run(["pacman", "-Sl"])
    if code != 0:
        return mapping
    for line in out.splitlines():
        parts = line.split(" ", 3)
        if len(parts) >= 2:
            mapping.setdefault(parts[1], parts[0])
    try:
        os.makedirs(CACHE, exist_ok=True)
        tmp = cache_file + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"signature": signature, "repos": mapping}, f)
        os.replace(tmp, cache_file)
    except OSError:
        pass
    return mapping


def read_local_db():
    """Every installed package's desc file, as {field: [lines]}: the same data `pacman -Qi`
    prints, without it working out "Required By" for each package (two seconds here)."""
    packages = []
    for entry in os.scandir(LOCAL_DB):
        if not entry.is_dir():
            continue
        try:
            with open(os.path.join(entry.path, "desc"), encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError:
            continue
        fields = {}
        for block in text.split("\n\n"):
            lines = block.strip("\n").split("\n")
            if lines and lines[0].startswith("%") and lines[0].endswith("%"):
                fields[lines[0][1:-1]] = lines[1:]
        if fields.get("NAME"):
            packages.append(fields)
    return packages


def split_dep(dep):
    """"glibc>=2.40" -> ("glibc", ">=", "2.40"); "foo" -> ("foo", "", "")."""
    match = re.match(r"^([^<>=]+)(>=|<=|=|>|<)?(.*)$", dep.strip())
    return (match.group(1), match.group(2) or "", match.group(3)) if match else (dep, "", "")


def rpmvercmp(a, b):
    """libalpm's rpmvercmp: -1, 0 or 1."""
    if a == b:
        return 0
    i = j = 0
    while i < len(a) and j < len(b):
        si, sj = i, j
        while i < len(a) and not a[i].isalnum():
            i += 1
        while j < len(b) and not b[j].isalnum():
            j += 1
        if i >= len(a) or j >= len(b):
            break
        if i - si != j - sj:
            return -1 if i - si < j - sj else 1
        test = str.isdigit if a[i].isdigit() else str.isalpha
        ei, ej = i, j
        while ei < len(a) and test(a[ei]):
            ei += 1
        while ej < len(b) and test(b[ej]):
            ej += 1
        one, two = a[i:ei], b[j:ej]
        if not two:
            return 1 if test is str.isdigit else -1
        if test is str.isdigit:
            one, two = one.lstrip("0"), two.lstrip("0")
            if len(one) != len(two):
                return 1 if len(one) > len(two) else -1
        if one != two:
            return -1 if one < two else 1
        i, j = ei, ej
    rest_a, rest_b = a[i:], b[j:]
    if not rest_a and not rest_b:
        return 0
    if (not rest_a and not rest_b[:1].isalpha()) or rest_a[:1].isalpha():
        return -1
    return 1


def vercmp(v1, v2):
    """alpm_pkg_vercmp: epoch, then version, then pkgrel when both have one."""
    def evr(v):
        epoch, _, rest = v.partition(":") if re.match(r"^\d+:", v) else ("0", "", v)
        version, dash, rel = rest.rpartition("-")
        return (epoch, version, rel) if dash else (epoch, rest, None)
    e1, ver1, r1 = evr(v1)
    e2, ver2, r2 = evr(v2)
    return rpmvercmp(e1, e2) or rpmvercmp(ver1, ver2) or (rpmvercmp(r1, r2) if r1 and r2 else 0)


def version_ok(have, mod, want):
    cmp = vercmp(have, want)
    return {"=": cmp == 0, ">=": cmp >= 0, "<=": cmp <= 0, ">": cmp > 0, "<": cmp < 0}[mod]


def cmd_updates():
    result = {"repo": [], "aur": [], "errors": []}
    code, out, err = run(["checkupdates"], timeout=180)
    # checkupdates exits 2 when nothing is pending
    if code in (0, 2):
        for line in out.splitlines():
            match = re.match(r"^(\S+) (\S+) -> (\S+)", line)
            if match:
                result["repo"].append({"name": match.group(1), "old": match.group(2), "new": match.group(3)})
        repos = repo_map() if result["repo"] else {}
        for pkg in result["repo"]:
            pkg["repo"] = repos.get(pkg["name"], "")
    else:
        result["errors"].append(err.strip() or "checkupdates failed")
    if shutil.which("yay"):
        code, out, err = run(["yay", "-Qua"], timeout=180)
        if code in (0, 1):
            for line in out.splitlines():
                match = re.match(r"^(\S+) (\S+) -> (\S+)", line)
                if match:
                    result["aur"].append({"name": match.group(1), "old": match.group(2), "new": match.group(3), "repo": "aur"})
        else:
            result["errors"].append(err.strip() or "yay -Qua failed")
    return result


def reverse_deps(local, field):
    """name -> the installed packages whose `field` (DEPENDS or OPTDEPENDS) it satisfies,
    the way pacman works out "Required By" and "Optional For": a package satisfies a
    dependency by its own name and version or by a provision, and an unversioned provision
    only meets an unversioned need."""
    providers = {}
    for fields in local:
        name = fields["NAME"][0]
        version = (fields.get("VERSION") or [""])[0]
        providers.setdefault(name, []).append((name, version))
        for provision in fields.get("PROVIDES", []):
            pname, pmod, pversion = split_dep(provision)
            providers.setdefault(pname, []).append((name, pversion if pmod == "=" else None))
    needed_by = {}
    for fields in local:
        name = fields["NAME"][0]
        for dep in fields.get(field, []):
            # An optional dependency carries its reason after ": "
            dname, dmod, dversion = split_dep(dep.partition(": ")[0])
            for provider, version in providers.get(dname, ()):
                if not dmod or (version is not None and version_ok(version, dmod, dversion)):
                    needed_by.setdefault(provider, set()).add(name)
    return needed_by


def cmd_installed():
    try:
        local = read_local_db()
    except OSError as err:
        return {"error": str(err), "packages": []}
    required_by = reverse_deps(local, "DEPENDS")
    # Not in any sync database is what `pacman -Qm` means by foreign
    repos = repo_map()
    packages = []
    for fields in local:
        name = fields["NAME"][0]
        stamp = int((fields.get("INSTALLDATE") or ["0"])[0] or 0)
        packages.append({
            "name": name,
            "version": (fields.get("VERSION") or [""])[0],
            "description": (fields.get("DESC") or [""])[0],
            "size": int((fields.get("SIZE") or ["0"])[0] or 0),
            "explicit": (fields.get("REASON") or ["0"])[0] != "1",
            "repo": repos.get(name, "aur"),
            "installed": time.strftime("%a %d %b %Y %I:%M:%S %p %Z", time.localtime(stamp)) if stamp else "",
            "requiredBy": len(required_by.get(name, ())),
        })
    packages.sort(key=lambda p: p["name"])
    return {"packages": packages}


def parse_search(text, installed_mark=True):
    results = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith(" ") or not line.strip():
            continue
        match = re.match(r"^(?:(\S+)/)?(\S+) (\S+)(.*)$", line)
        if not match:
            continue
        description = lines[i + 1].strip() if i + 1 < len(lines) and lines[i + 1].startswith(" ") else ""
        results.append({
            "repo": match.group(1) or "",
            "name": match.group(2),
            "version": match.group(3),
            "installed": "[installed" in match.group(4),
            "description": description,
        })
    return results


def cmd_search(query, aur):
    results = []
    code, out, _ = run(["pacman", "-Ss", "--", query])
    if code == 0:
        results += parse_search(out)
    if aur and shutil.which("yay"):
        code, out, _ = run(["yay", "-Ssa", "--topdown", "--", query], timeout=60)
        if code == 0:
            seen = {pkg["name"] for pkg in results}
            for pkg in parse_search(out):
                if pkg["repo"] == "aur" and pkg["name"] not in seen:
                    results.append(pkg)
    return {"results": results[:200], "truncated": len(results) > 200}


def cmd_info(name):
    for cmd, source in ((["pacman", "-Qi", name], "installed"), (["pacman", "-Si", name], "repo"),
                        (["yay", "-Si", name], "aur")):
        if cmd[0] == "yay" and not shutil.which("yay"):
            continue
        code, out, _ = run(cmd)
        blocks = parse_blocks(out) if code == 0 else []
        if blocks:
            f = blocks[0]
            if source == "installed":
                # Not in any sync database is what `pacman -Qm` calls foreign
                f["Repository"] = repo_map().get(name, "aur")
            return {
                "name": f["Name"], "version": f.get("Version", ""), "description": f.get("Description", ""),
                "url": f.get("URL", ""), "licenses": listify(f.get("Licenses")),
                "repo": f.get("Repository", "local" if source == "installed" else source),
                "source": source, "size": size_bytes(f.get("Installed Size") or f.get("Installed Size")),
                "downloadSize": size_bytes(f.get("Download Size")),
                "depends": listify(f.get("Depends On")), "optional": listify(f.get("Optional Deps")),
                "requiredBy": listify(f.get("Required By")), "optionalFor": listify(f.get("Optional For")),
                "provides": listify(f.get("Provides")), "conflicts": listify(f.get("Conflicts With")),
                "packager": f.get("Packager", ""), "built": f.get("Build Date", ""),
                "installedOn": f.get("Install Date", ""), "reason": f.get("Install Reason", ""),
            }
    return {"error": "not found", "name": name}


def cmd_orphans():
    """What `pacman -Qdtq` lists (installed as a dependency, and neither required nor
    optionally required by anything), read from the local database directly."""
    try:
        local = read_local_db()
    except OSError:
        return {"names": [], "size": 0}
    required_by = reverse_deps(local, "DEPENDS")
    optional_for = reverse_deps(local, "OPTDEPENDS")
    orphans = [f for f in local if (f.get("REASON") or ["0"])[0] == "1"
               and not required_by.get(f["NAME"][0]) and not optional_for.get(f["NAME"][0])]
    orphans.sort(key=lambda f: f["NAME"][0])
    return {"names": [f["NAME"][0] for f in orphans],
            "size": sum(int((f.get("SIZE") or ["0"])[0] or 0) for f in orphans)}


def cmd_cache():
    cache = "/var/cache/pacman/pkg"
    total = files = 0
    try:
        for entry in os.scandir(cache):
            if entry.is_file():
                files += 1
                total += entry.stat().st_size
    except OSError:
        pass
    old = 0
    if shutil.which("paccache"):
        code, out, _ = run(["paccache", "-dk2", "-v"])
        match = re.search(r"([\d.]+ \w+) would be freed", out)
        if match:
            old = size_bytes(match.group(1))
    return {"size": total, "files": files, "reclaimable": old}


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd, rest = argv[1], argv[2:]
    # Everything after a bare "--" is the query, even when it starts with dashes
    tail = rest[rest.index("--") + 1:] if "--" in rest else []
    head = rest[:rest.index("--")] if "--" in rest else rest
    flags = [a for a in head if a.startswith("--")]
    args = tail or [a for a in head if not a.startswith("--")]
    table = {
        "updates": lambda: cmd_updates(),
        "installed": lambda: cmd_installed(),
        "search": lambda: cmd_search(args[0], "--aur" in flags) if args else {"results": []},
        "info": lambda: cmd_info(args[0]) if args else {"error": "no package"},
        "orphans": lambda: cmd_orphans(),
        "cache": lambda: cmd_cache(),
    }
    if cmd not in table:
        print(__doc__)
        return 2
    json.dump(table[cmd](), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
