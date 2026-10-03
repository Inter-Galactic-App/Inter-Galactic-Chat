# Product Roadmap Template

This is a lightweight planning template for Inter Galactic product and
community feedback. It is intentionally fill-in oriented: keep it current, do
not turn it into a long promise list, and move uncertain ideas through
`investigating` before calling them planned.

Last updated: 2026-05-14

## Roadmap Status Key

- `investigating` - The user need is real enough to research, but the solution,
  scope, or priority is not settled.
- `planned` - The team intends to build it and has a clear direction.
- `in progress` - Work is actively being designed, implemented, or validated.
- `blocked` - Work is waiting on a decision, dependency, platform limitation,
  or external service.
- `completed` - The work shipped or the user-visible need is met.
- `rejected` - The request is not a fit or will not be pursued.

## Planning Horizon

### Now

Use for work that is active or expected in the current beta/release cycle.

| Item | Status | Owner | Target | Source feedback | Notes |
| --- | --- | --- | --- | --- | --- |
|  | investigating / planned / in progress / blocked |  |  |  |  |

### Next

Use for likely follow-up work after the current cycle.

| Item | Status | Owner | Target | Source feedback | Notes |
| --- | --- | --- | --- | --- | --- |
|  | investigating / planned / blocked |  |  |  |  |

### Later

Use for good ideas that are not ready for scheduling.

| Item | Status | Owner | Source feedback | Revisit trigger |
| --- | --- | --- | --- | --- |
|  | investigating |  |  |  |

### Completed

Use for shipped or otherwise resolved product roadmap items.

| Item | Completed in | Owner | Source feedback | Notes |
| --- | --- | --- | --- | --- |
|  | version/build |  |  |  |

### Rejected Or Deferred

Use when a request should not keep resurfacing without new evidence.

| Item | Status | Owner | Reason | Revisit trigger |
| --- | --- | --- | --- | --- |
|  | rejected / blocked |  |  |  |

## Roadmap Item Template

Copy this block into the right horizon when a request needs more detail than a
table row.

```markdown
### <Roadmap Item>

**Status:** investigating / planned / in progress / blocked / completed / rejected
**Owner:**
**Target:**
**Source feedback:**
**Related feature spec:**

**User problem:**

**Proposed direction:**

**Scope:**
- Must have:
- Nice to have:
- Out of scope:

**Risks or dependencies:**

**Next step:**

**Update note for beta users:**
```

## Candidate: In-App Bug Reporting

**Status:** investigating
**Owner:**
**Related docs:** `feedback-triage.md`, `bug-report-template.md`,
`known-issues.md`

**User problem:**
Beta users can report issues faster if the app can package the right diagnostic
logs, app version, platform details, and reproduction notes without requiring
manual file hunting.

**Initial direction:**
Add an opt-in in-app report flow that previews redacted diagnostics, asks the
user what happened, allows screenshots or attachments, and submits the report
to a project-owned endpoint.

**Required decisions before implementation:**
- Endpoint owner and hosting location.
- Authentication or abuse-prevention model.
- Diagnostic redaction and retention policy.
- Maximum upload size and attachment rules.
- Whether reports create GitHub issues, Matrix admin-room posts, database
  records, or support tickets.
- Offline behavior when submission fails.
