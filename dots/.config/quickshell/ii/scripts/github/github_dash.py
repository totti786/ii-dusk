#!/usr/bin/env python3
"""Everything the cheatsheet's GitHub tab shows, from the `gh` CLI (it keeps the login).

  github_dash.py            fetch, cache and print one JSON document
  github_dash.py --cached   print the last cache (or {}) without touching the network

The token never passes through this script: `gh api` does the authenticating. The cache is
~/.cache/github-dash/data.json.
"""
import json
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "github-dash" / "data.json"


def gh(*args, timeout=40):
    out = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=timeout)
    if out.returncode != 0:
        raise RuntimeError((out.stderr or "gh failed").strip().splitlines()[-1][:200])
    return json.loads(out.stdout or "null")


def streaks(days):
    """(current, longest) runs of days with a contribution. Today without one does not break a run."""
    counts = {d["date"]: d["contributionCount"] for d in days}
    longest = run = 0
    for d in days:
        run = run + 1 if d["contributionCount"] > 0 else 0
        longest = max(longest, run)
    cur = 0
    day = date.today()
    if counts.get(day.isoformat(), 0) == 0:
        day -= timedelta(days=1)
    while counts.get(day.isoformat(), 0) > 0:
        cur += 1
        day -= timedelta(days=1)
    return cur, longest


def describe(ev):
    p = ev.get("payload") or {}
    t = ev["type"]
    if t == "PushEvent":
        n = p.get("size") or len(p.get("commits") or []) or 1
        msg = ((p.get("commits") or [{}])[-1].get("message") or "").splitlines()[:1]
        return "commit", f"Pushed {n} commit{'s' if n != 1 else ''}", (msg[0] if msg else "")
    if t == "CreateEvent":
        return "add_circle", f"Created {p.get('ref_type', 'repository')}", p.get("ref") or ""
    if t == "DeleteEvent":
        return "delete", f"Deleted {p.get('ref_type', 'branch')}", p.get("ref") or ""
    if t == "WatchEvent":
        return "star", "Starred", ""
    if t == "ForkEvent":
        return "fork_right", "Forked", ""
    if t == "PullRequestEvent":
        pr = p.get("pull_request") or {}
        verb = "Merged" if pr.get("merged") else p.get("action", "updated").capitalize()
        return "merge", f"{verb} pull request", pr.get("title") or ""
    if t == "IssuesEvent":
        return "adjust", f"{p.get('action', 'updated').capitalize()} issue", (p.get("issue") or {}).get("title") or ""
    if t in ("IssueCommentEvent", "CommitCommentEvent", "PullRequestReviewCommentEvent"):
        return "chat", "Commented", ""
    if t == "PullRequestReviewEvent":
        return "rate_review", "Reviewed a pull request", ""
    if t == "ReleaseEvent":
        return "sell", "Released", (p.get("release") or {}).get("tag_name") or ""
    if t == "PublicEvent":
        return "public", "Made public", ""
    return "code", t.replace("Event", ""), ""


def fetch():
    query = (HERE / "viewer.graphql").read_text()
    with ThreadPoolExecutor(2) as pool:
        f_main = pool.submit(gh, "api", "graphql", "-f", f"query={query}")
        f_notes = pool.submit(gh, "api", "notifications?per_page=15")
        main = f_main.result()
        try:
            notes = f_notes.result()
        except RuntimeError:
            notes = []
    v = main["data"]["viewer"]
    try:
        events = gh("api", f"users/{v['login']}/events?per_page=30")
    except RuntimeError:
        events = []

    cal = v["contributionsCollection"]["contributionCalendar"]
    weeks = [[d["contributionCount"] for d in w["contributionDays"]] for w in cal["weeks"]]
    dates = [[d["date"] for d in w["contributionDays"]] for w in cal["weeks"]]
    flat = [d for w in cal["weeks"] for d in w["contributionDays"]]
    cur, longest = streaks(flat)
    busiest = max(flat, key=lambda d: d["contributionCount"]) if flat else {"date": "", "contributionCount": 0}

    langs = {}
    repos = []
    for r in v["repos"]["nodes"]:
        lang = r.get("primaryLanguage") or {}
        if lang:
            langs.setdefault(lang["name"], {"name": lang["name"], "color": lang.get("color") or "#888", "repos": 0})["repos"] += 1
        head = ((r.get("defaultBranchRef") or {}).get("target")) or {}
        repos.append({
            "name": r["name"], "full": r["nameWithOwner"], "desc": r.get("description") or "", "url": r["url"],
            "private": r["isPrivate"], "archived": r["isArchived"], "stars": r["stargazerCount"], "forks": r["forkCount"],
            "pushed": r["pushedAt"], "lang": lang.get("name", ""), "langColor": lang.get("color") or "",
            "commit": head.get("messageHeadline", ""), "ci": (head.get("statusCheckRollup") or {}).get("state", ""),
        })

    def pr(n):
        roll = ((n.get("commits") or {}).get("nodes") or [{}])[0].get("commit", {}) if n.get("commits") else {}
        return {"title": n["title"], "url": n["url"], "number": n["number"], "repo": n["repository"]["nameWithOwner"],
                "updated": n["updatedAt"], "draft": n.get("isDraft", False), "review": n.get("reviewDecision") or "",
                "ci": ((roll or {}).get("statusCheckRollup") or {}).get("state", "")}

    notifications = [{"title": n["subject"]["title"], "type": n["subject"]["type"], "repo": n["repository"]["full_name"],
                      "reason": n["reason"].replace("_", " "), "updated": n["updated_at"], "unread": n["unread"]} for n in notes]
    feed = []
    for e in events:
        icon, title, detail = describe(e)
        feed.append({"icon": icon, "title": title, "detail": detail, "repo": e["repo"]["name"], "time": e["created_at"]})

    total = sum(1 for _ in v["allStars"]["nodes"])
    stars = sum(n["stargazerCount"] for n in v["allStars"]["nodes"])
    return {
        "ok": True, "fetched": datetime.now(timezone.utc).isoformat(),
        "user": {"login": v["login"], "name": v.get("name") or v["login"], "bio": v.get("bio") or "", "location": v.get("location") or "",
                 "company": v.get("company") or "", "url": v["url"], "avatar": v["avatarUrl"], "since": v["createdAt"],
                 "followers": v["followers"]["totalCount"], "following": v["following"]["totalCount"],
                 "publicRepos": v["repositories"]["totalCount"], "starred": v["starredRepositories"]["totalCount"]},
        "contrib": {"total": cal["totalContributions"], "weeks": weeks, "dates": dates, "current": cur, "longest": longest,
                    "busiest": busiest["date"], "busiestCount": busiest["contributionCount"],
                    "commits": v["contributionsCollection"]["totalCommitContributions"],
                    "prs": v["contributionsCollection"]["totalPullRequestContributions"],
                    "issues": v["contributionsCollection"]["totalIssueContributions"],
                    "reviews": v["contributionsCollection"]["totalPullRequestReviewContributions"],
                    "private": v["contributionsCollection"]["restrictedContributionsCount"]},
        "stars": stars, "repoCount": total,
        "languages": sorted(langs.values(), key=lambda l: -l["repos"]),
        "repos": repos,
        "pullRequests": {"count": v["pullRequests"]["totalCount"], "items": [pr(n) for n in v["pullRequests"]["nodes"]]},
        "issues": {"count": v["issues"]["totalCount"], "items": [
            {"title": n["title"], "url": n["url"], "number": n["number"], "repo": n["repository"]["nameWithOwner"],
             "updated": n["updatedAt"], "comments": n["comments"]["totalCount"]} for n in v["issues"]["nodes"]]},
        "reviews": {"count": main["data"]["reviews"]["issueCount"], "items": [
            {"title": n["title"], "url": n["url"], "number": n["number"], "repo": n["repository"]["nameWithOwner"],
             "updated": n["updatedAt"], "author": (n.get("author") or {}).get("login", "")} for n in main["data"]["reviews"]["nodes"] if n]},
        "notifications": notifications, "feed": feed[:20],
    }


def main():
    if "--cached" in sys.argv:
        try:
            print(CACHE.read_text())
        except OSError:
            print("{}")
        return 0
    if not shutil.which("gh"):
        print(json.dumps({"ok": False, "error": "The GitHub CLI (gh) is not installed", "kind": "missing"}))
        return 0
    try:
        data = fetch()
    except (RuntimeError, subprocess.SubprocessError, KeyError, json.JSONDecodeError) as e:
        msg = str(e)
        kind = "auth" if any(w in msg.lower() for w in ("auth", "login", "token", "401")) else "network"
        print(json.dumps({"ok": False, "error": msg or "The request failed", "kind": kind}))
        return 0
    CACHE.parent.mkdir(parents=True, exist_ok=True)
    tmp = CACHE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data))
    os.replace(tmp, CACHE)
    print(json.dumps(data))
    return 0


if __name__ == "__main__":
    sys.exit(main())
