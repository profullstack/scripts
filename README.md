# scripts

Hand-written command-line tools. Everything in `bin/` is meant to sit on `PATH`.

## Install

```sh
git clone git@github.com:profullstack/scripts.git ~/scripts
ln -sf ~/scripts/bin/* ~/.local/bin/
```

Symlinking rather than copying keeps `~/.local/bin` and this repo from drifting
apart.

## Tools

### `gh-prs`

Lists open pull requests across any number of organizations and personal
accounts, newest first, as an aligned table. In a capable terminal the PR number
and URL become clickable hyperlinks.

```sh
gh-prs --orgs profullstack,moshcoder,h4kr,infernetprotocol
gh-prs --users ralyodio
gh-prs --orgs profullstack --users ralyodio --limit 50
```

### `gh-prs-merge`

Walks the same scopes and squash-merges every PR that qualifies, oldest first.
**Dry run by default** — nothing changes until you pass `--apply`.

```sh
gh-prs-merge --orgs profullstack,moshcoder          # report only
gh-prs-merge --orgs profullstack,moshcoder --apply  # actually merge
```

A PR is merged only when all of these hold:

- it is open
- it is not a draft, or was successfully marked ready (see below)
- `mergeable` is `MERGEABLE` and `mergeStateStatus` is `CLEAN`
- at least one CI check exists, unless `--allow-no-checks` is passed
- every check is `pass` or `skipping`
- the head commit has not moved between the check and the merge, enforced with
  `--match-head-commit`

Merges never pass `--admin`, so branch protection and required reviews are still
enforced by GitHub. If a merge is refused, that refusal stands.

**Drafts.** Draft PRs are included by default. Under `--apply` each one is marked
ready for review, re-read, and then judged by the rules above — so a draft with
red CI ends up ready but unmerged, which is usually what you want. A dry run
reports them as `WOULD-READY` and changes nothing. Pass `--no-ready-drafts` to
ignore drafts entirely.

Options:

| Flag | Effect |
| --- | --- |
| `--orgs A,B` | search repositories owned by these organizations |
| `--users A,B` | search repositories owned by these personal accounts |
| `--limit N` | maximum PRs per owner, default 1000 |
| `--apply` | actually mark drafts ready and squash-merge |
| `--allow-no-checks` | also merge clean PRs that have no CI checks at all |
| `--no-ready-drafts` | leave draft PRs alone |

The closing summary counts `ready`, `readied`, `merged`, `skipped`, and `failed`.

## Requirements

`gh` (authenticated), `jq`, and `awk`.
