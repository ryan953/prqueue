# PR Queue

A macOS app that turns a pile of GitHub review requests into a queue you can
actually work through.

The problem it solves: 66 open "review requested" pull requests is not a queue.
Almost none of them are addressed to you by name. Most arrive through one of
dozens of teams you belong to, many are written by bots, several are already
approved, and a good number are blocked on their own author.

## How it works

Every pull request lands in exactly one **lane**. The lane answers "is this
mine to do right now?", before any ranking happens.

| Lane | What it holds |
| --- | --- |
| **Needs you** | Open, green, human written, and still waiting on a reviewer |
| **My PRs** | Pull requests you wrote, ranked by what blocks them |
| **Blocked on author** | Failing checks, or changes already requested |
| **Bots** | Dependabot and friends, batched together |
| **Already approved** | Someone else approved it, so it does not need you |
| **Drafts** | The author is not asking yet |
| **Stale** | Untouched for longer than the stale threshold, so treated as abandoned |
| **Snoozed** | Hidden until a date, or until something happens |
| **Muted** | Every requesting team, the repository, or the author is muted |

Pull requests in **archived repositories are dropped entirely**, because
nothing can be done about them. GitHub's own `archived:false` search qualifier
does not reliably exclude them, so the repository's `isArchived` flag is used.

Inside a lane, a transparent score sets the order. Every rule that fired is
listed in the detail pane, so the ranking can always be questioned, and every
weight can be changed in Settings.

## Controls

- **Mute a team** — the strongest control, because most requests arrive through
  a team rather than by name.
- **Priority team** — the opposite: lift a team's pull requests.
- **Mute until activity** — hide a pull request until something really happens
  to it: a comment, a review, a push, or a check result. It comes back with a
  note saying what changed.
- **Snooze** — hide until tomorrow, three days, or a week.
- **Pin** — an explicit promise to review. Beats every other rule.
- **Mute a repository or an author.**

A request addressed to you by name is never muted.

## Requirements

- macOS 14 or later
- The [gh CLI](https://cli.github.com), logged in: `gh auth login`

The app reads its token from `gh`, so there is no separate login.

## Install

```sh
brew install --cask ryan953/tap/prqueue
```

Or download the zip from [Releases](../../releases), unzip it, and drag
**PRQueue.app** to `/Applications`.

The build is ad-hoc signed rather than notarized, so the first launch needs
**right-click → Open** (once), or:

```sh
xattr -dr com.apple.quarantine "/Applications/PRQueue.app"
```

## Build and run

```sh
Scripts/bundle.sh        # builds dist/PRQueue.app
open dist/PRQueue.app
```

`--version 1.2.3` stamps the bundle, and `--universal` builds for both Apple
silicon and Intel, which is what a release does.

Development:

```sh
swift build
swift test
swift run PRQueue --report      # print the triaged queue and exit
swift run PRQueue --report --all
```

`--report` runs the same rules headless, which makes the ranking easy to check
and to pipe into other tools.

## Where state lives

`~/Library/Application Support/PRQueue/preferences.json` — plain JSON holding
muted teams, repositories and authors, priority teams, snoozes, pins, the stale
threshold, and the rule weights. Safe to read, edit, and back up.
