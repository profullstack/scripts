# scripts

Hand-written command-line tools. Everything in `bin/` is meant to sit on `PATH`.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/profullstack/scripts/main/install.sh | sh
```

That is the whole thing on a brand-new box: the repo is public, so the clone
needs no key and no account. It also ends the chicken-and-egg this repo used to
have, where `provision-ssh-keys` — the tool that puts our keys on a machine —
could only be fetched using the key it exists to install.

Cloning by hand works the same way, and `--ssh` gets you a checkout you can push
from:

```sh
git clone https://github.com/profullstack/scripts.git ~/scripts
sh ~/scripts/install.sh          # or: sh ~/scripts/install.sh --ssh
```

`install.sh` clones (or updates) the checkout, moves it to the newest release
tag, and symlinks every executable in `bin/` into `~/.local/bin`. Symlinking
rather than copying keeps `~/.local/bin` and this repo from drifting apart.

```sh
sh install.sh                 # newest release
sh install.sh --edge          # track main instead
sh install.sh --ref v0.2.0    # a specific tag
sh install.sh --ssh           # clone over SSH, for a checkout you push from
sh install.sh --dry-run       # say what would happen, change nothing
```

## Upgrading

```sh
scripts-upgrade               # move to the newest release
scripts-upgrade --status      # where this box is, and what is newest
scripts-upgrade --edge        # switch to tracking main
```

`scripts-upgrade` is a front for the same `install.sh`, so a fresh machine and
an existing one run identical code.

**Releases are the point of the tag, not a tarball.** Nothing downloads an
archive from this repo; `install.sh` resolves the newest `v*` tag on the remote
and checks the tree out at it. Cutting a release is therefore exactly:

```sh
git tag -a v0.2.0 -m "..." && git push origin v0.2.0
```

Pushing the tag is enough. `.github/workflows/release.yml` runs the gate and
then creates the release object, so `gh release create` by hand is only a
fallback for when Actions is unavailable.

**The gate runs twice, and that is deliberate.** `bin/scripts-check` is the
rule — it parses every script by shebang, verifies the executable bits, and runs
`shellcheck -S error` over the shell ones. `.githooks/pre-push` runs it before
anything leaves the machine, and CI runs *that same file* on the runner. Neither
is a re-implementation of the other, which is how the two used to be free to
drift; the hook stays because feedback before a push beats feedback after one.

**A note on the red X in the history, and why CI came back.** This workflow was
deleted on 2026-08-29 and restored when the repo was opened up. It was never
broken YAML: an unpaid balance on the `profullstack` org suspends Actions
compute, and the job was refused before a runner was ever allocated — a red X
with no logs, which is indistinguishable from a workflow that ran and failed. A
gate that cannot run is worse than no gate, because the X implies something was
checked, so it was removed rather than left there lying.

Be precise about the money, because the obvious assumption is wrong: **this
repo's CI minutes were never the cost.** They are covered by the included
allowance at net $0.00. The balance is Actions artifact storage and Code Quality
credits accrued on unrelated repositories, so deleting this workflow saved
nothing on the bill and was never going to.

What changed is not the balance — it is still owed, and every *private* repo in
the org is still suspended by it. The suspension only applies to private repos.
This one is public now, so the single thing standing between this workflow and a
runner is gone.

**A development checkout is left alone.** Because `~/.local/bin/*` are symlinks
into the working tree, the command on PATH is whatever the checkout is at, so
tracking `main` means an unfinished edit is instantly the installed tool. That
is why the default is a tag. The box where this repo is actually developed is
the exception and needs no flag: a tree with uncommitted changes or unpushed
commits is never moved, only re-symlinked.

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

### `gh-issues`

The same table for open issues rather than pull requests. `gh search issues`
excludes pull requests unless asked for them, so the two tools never overlap.

```sh
gh-issues --orgs profullstack,moshcoder,h4kr,infernetprotocol
gh-issues --users ralyodio
gh-issues --orgs profullstack --users ralyodio --limit 50
```

`--csv` writes the result set to `~/gh-issues-YYYY-MM-DD.csv` instead of
printing the table, and `--csv=FILE` picks the path. The CSV is the archival
form of the same query: whole titles rather than 70 columns of one, ISO 8601
`CREATED` and `UPDATED` timestamps rather than "3 days ago", and a bare issue
number so a spreadsheet reads it as one.

```sh
gh-issues --orgs profullstack,moshcoder,h4kr,infernetprotocol --csv
gh-issues --orgs profullstack --csv=/tmp/issues.csv
```

Bare `--csv` takes no argument on purpose, so `--csv --limit 10` cannot swallow
the next flag as a filename.

### `gh-pulse`

Moved to [profullstack/cli-tools](https://github.com/profullstack/cli-tools#gh-pulse)
on 2026-09-13, the same day it landed here, so that the email, the `gh-pulse
show` terminal view, `open`, `text` and `json` are one implementation with one
name on `PATH`. The snapshots under `~/.local/share/gh-pulse` are the same files
either way. `curl -fsSL https://raw.githubusercontent.com/profullstack/cli-tools/master/install.sh | sh`
installs it.

### `gh-prs-merge`

Moved to [profullstack/cli-tools](https://github.com/profullstack/cli-tools#gh-prs-merge)
on 2026-09-24, for the same reason `gh-pulse` went: two implementations of one
name on `PATH` drift, and this one had already drifted. The TypeScript copy
carries the fix for GitHub refusing to merge a stacked PR through the GraphQL
mutation, and has tests around it.

One behaviour differs, so the swap is not silent: repairs were **on** here
unless you passed `--no-fix`, and are **off** there unless you pass `--fix`.
An alias that relied on the old default needs `--fix` added.
`curl -fsSL https://raw.githubusercontent.com/profullstack/cli-tools/master/install.sh | sh`
installs it.

### `domainjson`

Whois-style, JSON-first name lookup. Prints a single JSON object:

```json
{ "name": "...", "rdap": { ... }, "dns": { "records": {}, "hosts": [], "reverse": [], "axfr": [] } }
```

```sh
domainjson example.com
domainjson --timeout 8000 test.hacker
domainjson -s https://rdap.nic.cz -t domain example.cz   # openrdap args pass through
```

Names ending in a [Moshpit](https://pit.moshcode.sh) TLD skip RDAP and are
served from the registry API under a `moshpit` key instead. Everything else
goes through the OpenRDAP CLI (`rdap`); its flags pass through unchanged,
except the output-format flags (`--text`, `--whois`, `--raw`), which are
dropped — the RDAP section is always JSON. DNS is queried one type at a time
(`A`, `AAAA`, `CNAME`, `MX`, `TXT`, `NS`; never `ANY`), plus reverse PTR for
every resolved address and an AXFR attempt against each nameserver — a
refused transfer is reported, never fatal. If every data source fails, the
exit status is non-zero and the JSON carries an `error` key.

| Flag | Effect |
| --- | --- |
| `--registry URL` | Moshpit registry base URL, default `https://pit.moshcode.sh` |
| `--timeout MS` | per-query timeout for HTTP and dig, default 4000 |
| `--name NAME` | alternative to the positional name argument |

### `provision-ssh-keys`

Authorizes our public keys on a machine, so every box we buy is reachable
without a password. **Dry run by default** — nothing is written until you pass
`--apply`. Idempotent, so it doubles as a drift check on hosts we already own.

```sh
provision-ssh-keys 152.53.47.37                  # report only
provision-ssh-keys --apply 152.53.47.37          # install
provision-ssh-keys --apply --user anthony box    # into a non-root account
```

Every `~/.ssh/*.pub` is installed unless you narrow it with `--key`. Only `.pub`
files are accepted; the script refuses anything else, so a private key cannot be
shipped by a slip of the shell.

**The first key is a chicken-and-egg and this script will not solve it.** A
machine that has never seen one of our keys answers `Permission denied
(publickey,password)`, and nothing here handles passwords. Bootstrap one key
through the provider's own provisioning — netcup SCP, cloud-init, a rescue
console — or interactively, once, with `ssh-copy-id -i ~/.ssh/id_ed25519.pub
root@HOST`. After that this script converges the rest and re-converges later.

**Host keys.** By default an unknown host is refused rather than trusted;
`--accept-new` waives that. Better, pass `--fingerprint` with the value read off
the provider's console and the script verifies before it opens a session,
refusing on mismatch:

```sh
provision-ssh-keys --apply --fingerprint SHA256:AUyILK… 152.53.47.37
```

A reinstalled machine legitimately presents new host keys, so a mismatch means
*go re-read the console*, not necessarily an attack. It is still a stop.

Options:

| Flag | Effect |
| --- | --- |
| `--user USER` | Remote account to install into; default `root` |
| `--port N` | SSH port; default 22 |
| `--key PATH` | Public key to install; repeatable. Default: every `~/.ssh/*.pub` |
| `--fingerprint SHA256:…` | Require the host to present this key; repeatable |
| `--accept-new` | Trust an unknown host key instead of refusing |
| `--apply` | Actually write `authorized_keys` |

### `ssh-logins`

Who actually got in over SSH, and from where. Defaults to today.

```sh
ssh-logins                # today
ssh-logins yesterday      # any journalctl --since expression
ssh-logins -7d
ssh-logins --count        # one row per user+source
ssh-logins --raw          # the original journal lines
```

No `sudo`. Membership in the `adm` group is enough to read the journal, so the
command never stops to authenticate. Scoped to `-u ssh` because a full day is
~15k lines and grepping all of them to find thirty is most of the runtime.

Counts `Accepted` only. Failed and half-finished attempts are thousands a day on
a public box and answer a different question.

### `alert`

Tells Anthony something broke: a text, or a phone call that reads it aloud
while no number can text yet, through smshub.dev alerts
(`POST /api/v1/alerts`, Anthony's account, key `SMSHUB_ALERT_API_KEY` in vault
`smshub--prod`). Cron jobs call it on real failures only.

```sh
alert "fleet-db-backup nightly failed"
alert --severity critical "coinpay webhooks are down"    # always rings
alert --key qc-sweep --every 6h "riotcoder-qc sweep is erroring"
alert --clear qc-sweep                                    # recovered
alert --check                                             # is the key accepted?
```

smshub sends the same text once per 10 minutes; `--key`/`--every` (default:
the message, 6h) keeps a job that fails every minute to one alert per window.
If smshub cannot be reached it emails `ALERT_EMAIL` (set in
`~/.config/alert/env`) instead. Log: `~/.local/state/alert/alert.log`.
If smshub rejects the key (401/403) the email subject says "smshub alert key
REJECTED", names where the key came from and how to replace it; every real alert
still gets its own email. `alert --check` (daily cron) asks smshub about the key
without alerting anyone and sends that email once per 6h while it is rejected.

### `anthropic-credit-check`

Asks the fleet's shared Anthropic key (vault `profullstack-sharable-keys--prod`)
for one token. Out of credits, over a usage limit or refused: `alert`, at most
once a day. Working again: clears it. Hourly from cron; `--dry-run` only prints.

### `scripts-upgrade`

Moves this box to the newest release of this repo. See [Upgrading](#upgrading).

### `scripts-check`

The release gate, runnable. Parses every script by shebang, checks that
everything in `bin/` is executable, and runs `shellcheck -S error` over the
shell ones.

```sh
scripts-check           # check the checkout this command lives in
scripts-check --quiet   # only complain
```

`.githooks/pre-push` runs it before every push, wired up by `install.sh` via
`git config core.hooksPath .githooks`. `git push --no-verify` bypasses it — and
CI then runs the same command on the runner, which does not.

A missing `shellcheck` is skipped with a note rather than failing — an absent
linter must not be able to block a release.

## `wrappers/`

Snapshots of the launcher scripts that third-party installers drop into
`~/.local/bin`. They are kept here for reference and recovery, not for
installation:

| File | Installed by | Launches |
| --- | --- | --- |
| `coinpay` | `https://coinpayportal.com/install.sh` | `~/.coinpay/pkg/bin/coinpay.js` |
| `moshcode` | `https://moshcoding.com/install.sh` | `~/.moshcode/pkg/bin/moshcode.mjs` |
| `moshscript` | `https://moshcoding.com/install.sh` | `moshcode.mjs run` |
| `logicsrc` | logicsrc CLI | `~/.logicsrc-cli/.../cli/dist/index.js` |

Two reasons they live outside `bin/` and are deliberately **not** symlinked:

- They hardcode absolute `/home/anthony` paths, so they are not portable to
  another machine or user.
- Their installers rewrite `~/.local/bin/<name>` on every update. Symlinking
  would let an installer write through into this repository, producing surprise
  diffs or silently replacing the link.

Re-run the relevant installer to restore or update one; copy from here only if
an installer is unavailable and you need the old contents back.

## Requirements

`gh` (authenticated), `jq`, and `awk`. `provision-ssh-keys` needs only OpenSSH
(`ssh`, `ssh-keyscan`, `ssh-keygen`) locally and `bash` on the remote host.
`domainjson` additionally wants `node`,
`dig`, and the OpenRDAP CLI (`go install github.com/openrdap/rdap/cmd/rdap@latest`,
run from `~/go/bin/rdap` or on `PATH`). `ssh-logins` needs `journalctl` and
membership in a group that can read the journal (`adm` on Ubuntu).

`install.sh` itself needs only POSIX `sh` and `git` — deliberately, since it is
the one file that runs before anything else is installed.

## newsletter-abtest

One email a day while a newsletter A/B test is running: every issue's sent,
opens, clicks and unsubscribes, what moved since the last reading, and the
arms pooled across the whole campaign with a two-proportion z test on clicks.
The delivery section uses the same house-style HTML when tracking is off and
reports stalled sends, uncertain pending outcomes, and any sent count above the
current listed audience. Every email also includes the plain-text report.

Opens and clicks keep arriving for days after a send, so a single reading at
the end cannot tell a real winner from an early lead. The verdict line says
when a gap is real, and when it is not it prints the recipients per arm it
would take, which is usually the more useful number: a 5,140 list settles a
0.6% against 1.4% gap in one send, and never settles 0.93% against 1.18%.

```
newsletter-abtest              snapshot every issue, mail the digest
newsletter-abtest --dry-run    build and print it, record nothing, send nothing
newsletter-abtest --print      snapshot and print, no mail
newsletter-abtest --prefix X   issues whose id starts with X (default profullstack-)
```

The month's sends live in `~/.config/newsletter-abtest/plan.json`; see
`examples/newsletter-abtest-plan.json`. Each entry gives the issue id, its
date, the CTA set and one line on what that issue tests, and the digest prints
the `myna newsletter blast` command for whichever is next. Cron it daily and
delete the line when the campaign is over.
## newsletter-prep

Drafts the next issue of a running newsletter campaign by itself, three days
before its date, and mails a test copy. It stops there: a person reads the
test copy and says go.

```
newsletter-prep              prepare the next issue due within 3 days
newsletter-prep --days 5     look further ahead
newsletter-prep --id X       that issue, whatever its date
newsletter-prep --dry-run    gather and draft, create nothing, mail nothing
newsletter-prep --force      redo one already drafted
```

It reads the campaign from `~/.config/newsletter-abtest/plan.json` (`--plan`
for a trial run against a copy), gathers
every blog post and GitHub release since the previous issue, has claude write
the prose from that material and nothing else, then checks every link itself
and drops the bullets whose links are dead. The issue is created in myna with
that issue's A/B design and one test copy goes out.

Give the plan a `recurring` block and the schedule keeps itself going: each
run marks off whatever myna has actually sent, and tops the plan up so there
is always a future issue on the books. Without that reconciliation the `sent`
flags never flip, the same issue stays next forever and the schedule stalls
after one send.

```json
"recurring": { "everyDays": 7, "keepAhead": 1, "keepSent": 12,
               "idPrefix": "profullstack-", "list": "profullstack-users",
               "ctaSet": "winner" }
```

Two things it will not do. It will not put age gated or adult material in a
newsletter to every customer, whatever the feeds say: the first automatic
draft pulled in a 21+ cigar post on its own, which is what `EXCLUDE_WORDS` is
for. And it will not send to the list. The send reaches thousands of people
and cannot be recalled, so the last step is a person reading the test copy and
running one line, after which the myna daemon sends it at its hour.

## nichedb-nightly

The nightly Knowledge Influencer report for nichedb.dev: what is waiting on a
human (claims, contributions, unanswered agent questions, payout addresses,
money owed), then niches, contributions, agent questions, money, tiers and the
index. HTML in the house report style, with a full text/plain part.

nichedb's Postgres has no public port, so a small Bun script is piped over
`ssh` into the running app container on dev2 and prints the numbers as one
JSON line; everything else happens locally. Each sent report appends a reading
to `~/.local/share/nichedb-nightly/snapshots.jsonl`, and the headline tiles
show the change since the one before.

```
nichedb-nightly                    read, record, mail the report
nichedb-nightly --dry-run          read and print; record nothing, send nothing
nichedb-nightly --to a@b.com       a test send elsewhere (records nothing)
nichedb-nightly --html FILE        also write the HTML part to FILE
nichedb-nightly --save-json FILE   keep the numbers that were read
nichedb-nightly --from-json FILE   render saved numbers instead of reading
```

Runs from cron at 05:05 UTC. A failure is mailed as "NicheDB nightly FAILED".

## pairux-nightly

The nightly PairUX report: installs, downloads and real users, in the same
shape as tron-nightly. PairUX has no telemetry and the desktop app does not
phone home for updates, so installs are counted where people fetch the bits:
outside IPs fetching `install.sh` / `install.ps1` and visiting `/download` in
dev2's shared nginx log (kept ~2 days, so the nightly must capture each day),
the daily rise in GitHub release installer downloads, Chocolatey, AUR, npm,
and GitHub clone counts of the brew/scoop/apt/rpm/nix/gentoo repos. Accounts
and usage (signups, meetings, joins, chat, recordings, channels, orgs) come
from the pairux Supabase Postgres on dev2, read-only, with our own and QA
accounts counted apart.

```
pairux-nightly                     mail yesterday's (UTC) report
pairux-nightly --dry-run           build it under ~/.local/share/pairux-nightly, send nothing
pairux-nightly --day 2026-10-16    a specific UTC day
pairux-nightly --to a@b.com,c@d    someone else (default anthony@ + preshy@profullstack.com)
```

Runs from cron at 05:45 UTC. A failure is mailed as "PairUX nightly FAILED".

## w3bs-nightly

The nightly W3BS report, in the same shape as pairux-nightly and smshub-nightly.
The w3bs CLI has no telemetry, so it is counted by its user agent
(`w3bs/<version>`) in dev2's shared nginx log (kept ~2 days): unique outside IPs
per day, by version and by kind of request (update check, package fetch, OS
channel, login). IPs in GitHub's published Actions ranges are shown apart as CI.
Installs are outside IPs fetching `install.sh` / `install.ps1` (root, `desktop/`,
`de/`, `training/`), minus our boxes and the package scanner; browse.w3bs.org
`/i/<publisher>/<pkg>` hits with a w3bs referer are install clicks. Accounts,
CLI logins, fleet machines and actions, signed releases, resources and tasks
come from the w3bs.org Postgres on dev2; Social accounts and repo writes from
the PDS sqlite; board users and posts from `tsbb.db`; visitors, top pages and
referrers from the CrawlProof tracker. All read-only, our accounts counted apart.

```
w3bs-nightly                     mail yesterday's (UTC) report
w3bs-nightly --dry-run           build it under ~/.local/share/w3bs-nightly, send nothing
w3bs-nightly --day 2026-10-25    a specific UTC day
w3bs-nightly --to a@b.com,c@d    someone else (default anthony@ + preshy@profullstack.com)
```

Runs from cron at 05:55 UTC. A failure is mailed as "W3BS nightly FAILED" and
raised with `alert`.

## threatcrush-nightly

The nightly ThreatCrush report, in the same shape as w3bs-nightly and
smshub-nightly, money first. Revenue is settled (confirmed/forwarded) rows across
every payment table in the threatcrush.com DB (credit deposits minus code grants,
scan orders, module and reputation subscriptions minus comp plans, licenses,
funding, crawl sales), plus checkouts opened and paid plans running. Installs are
outside IPs fetching `install.sh`/`install.ps1` in dev2's nginx log (kept ~2 days);
npm downloads of `@profullstack/threatcrush` come from api.npmjs.org (posted a day
late, shown as "·" until then). The CLI and daemon send Node's default `node`
user agent, so CLI users are outside IPs calling `/api/` with it, and daemon
heartbeats are ingest + ban-claim + run-poll calls (our boxes by server name).
Accounts, logins, CLI logins, orgs/teams/fleets/invites/agent keys, servers online
and daemon versions, GitHub App installs and repo scans, property runs, and the
fleet's attack events (detections) and bans (remediation_actions) come from the
threatcrush.com Supabase Postgres on dev2, read-only; visitors from CrawlProof.
Accounts matching the internal regex are ours, and so are the orgs they created
and those orgs' servers. ai-scan runs come from the CLI's anonymous usage ping
(`cli_usage_pings`, CLI 0.13.53+, opt-out with `THREATCRUSH_TELEMETRY=0`), split
into people (distinct install ids) and CI; `threatcrush scan` sends nothing
home, so local scans are not counted.

```
threatcrush-nightly                     mail yesterday's (UTC) report
threatcrush-nightly --dry-run           build it under ~/.local/share/threatcrush-nightly, send nothing
threatcrush-nightly --day 2026-10-26    a specific UTC day
threatcrush-nightly --to a@b.com,c@d    someone else (default anthony@ + preshy@profullstack.com)
```

Runs from cron at 06:00 UTC. A failure is mailed as "ThreatCrush nightly FAILED"
and raised with `alert --key threatcrush-nightly`.

### CoinPay signing monitor

`coinpay-vault-watch` runs on dev2 every 15 minutes. `coinpay-vault-watch --check`
reports current runtime capability and counts incompatible signing records without
sending notifications, unlocking keys, decrypting keys, or forwarding payments.
It requires Docker access and the deployed app's existing Supabase configuration.

Legacy deployments with operator-sealed signing records produce a deployment/format
mismatch alert, with no instruction to visit a nonexistent unlock page. Legacy
deployments without such records have no vault-unlock requirement. Vault-capable
deployments use explicit status logs; missing status is unknown, never proof of a lock.
Signing-format counts are compatibility checks, not evidence of current on-chain balances.
One critical smshub alert per six-hour incident cycle replaces duplicate text/call
requests; smshub selects its supported delivery channel. Existing unrelated alerts remain.
