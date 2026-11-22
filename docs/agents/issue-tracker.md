# Issue tracker: GitHub + project board

Issues and specs for this repo live as GitHub issues on `ahumadab/VepIndustriesMarket`. Use the `gh` CLI for all operations. Same conventions as `ahumadab/vepindustries-api`.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc or `--body-file` for multi-line bodies.
- **Read an issue**: `gh issue view <number> --json title,body,labels,comments`. Outside a terminal, `--comments` prints the comments only, without the body.
- **Refer to a sibling ticket** (in code, a comment, a PR): list the tickets of the spec first, `gh api repos/ahumadab/VepIndustriesMarket/issues/<spec>/sub_issues --jq '.[] | "\(.number) \(.title)"'`, and cite the one whose title matches.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`
- **A pull request closes its ticket**: its body says `Closes #<n>`. `develop` is the default branch, so GitHub closes the ticket when the PR merges into it. `.github/workflows/pr-title.yml` refuses a PR from `feature/<n>-…` without it.
- **A criterion no merge can meet** (it waits on a release, a friend in game) gets its own ticket, `ready-for-human`, a sub-issue of the spec, as soon as it shows (when the spec is split, at the latest during review): the PR still closes its ticket, and the spec stays open until that one closes.
- **A spec closes itself** once its last ticket closes (`.github/workflows/close-finished-specs.yml`): a spec still open after that points to a failed run of the workflow.
- **A ticket waiting on data** (days of real scans, a measurement in game) names it under `## Blocked by`, with the earliest date it can be met.
- **A PR meets another ticket's criterion**: comment on that ticket, naming the PR and the criterion, so whoever picks it up skips that work.

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either: resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue, routed by what it is:

- a spec → `--label spec`: the project board's **Produit** view lists specs by it, and its **Tickets** view leaves them out
- a ticket cut out of a spec → a sub-issue of that spec, its blocking edges as native dependencies (see **Sub-issues and blocking**), label `ready-for-agent` or `ready-for-human`
- an anomaly noticed while working → `--label needs-triage --label bug`
- an idea or a piece of feedback nobody has decided on → `--label needs-triage`

When a spec is split into tickets, every line of its Testing Decisions lands in one ticket's acceptance criteria: a seam that proves several behaviours is split with them, so that no part of it falls between two tickets.

A ticket that changes what the player sees in game has the acceptance criterion "validated in game by Boris after `npm run deploy` + `/reload`": the tests do not prove rendering.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --json title,body,labels,comments`.

## Sub-issues and blocking

Both endpoints take the other issue's numeric **database id** (`gh api repos/ahumadab/VepIndustriesMarket/issues/<n> --jq .id`), _not_ the `#number` or `node_id`.

- **Attach a ticket to its spec**: `gh api --method POST repos/ahumadab/VepIndustriesMarket/issues/<spec>/sub_issues -F sub_issue_id=<ticket-db-id>`.
- **Add a blocking edge**: `gh api --method POST repos/ahumadab/VepIndustriesMarket/issues/<ticket>/dependencies/blocked_by -F issue_id=<blocker-db-id>`. GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate). A ticket is unblocked when every blocker is closed.

## Project board

Every issue is on the user project [VepIndustries Market](https://github.com/users/ahumadab/projects/4) (number 4, copied from _Api Project_): views **Tickets** (board, `-label:spec`) and **Produit** (table, `label:spec`), Status `Todo` / `Done`. Sub-issues of a spec already on the board are added automatically. If an issue is missing from the board, add it: `gh project item-add 4 --owner ahumadab --url <issue-url>`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a sub-issue (see **Sub-issues and blocking**). Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: native issue dependencies (see **Sub-issues and blocking**).
- **Frontier query**: the map's open, unassigned children with no open blocker, in map order; the first line wins:

  ```sh
  gh api repos/ahumadab/VepIndustriesMarket/issues/<map>/sub_issues --paginate \
    --jq '.[] | select(.state=="open" and (.assignees|length)==0 and .issue_dependencies_summary.blocked_by==0) | "\(.number) \(.title)"'
  ```

- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
