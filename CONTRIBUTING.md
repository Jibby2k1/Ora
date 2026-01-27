# Contributing

## The Loop
1) Create/claim an Issue  
2) Get assigned (or comment “I’m taking this”)  
3) Create a branch named `issue-<id>-<slug>`  
4) Open a PR early (Draft is fine)  
5) PR must include `Fixes #<id>` and pass CI + review  
6) Merge closes the issue

## Branching
- Default branch: `main`
- Branch naming: `issue-123-short-description`
- Keep PRs small: prefer multiple PRs over one giant PR.

## Commit Style
- Recommended: `type(scope): message`
  - examples: `feat(model): add streaming separator`
            `fix(ci): pin python version`

## PR Requirements
- Must link issue: `Fixes #123`
- Must include test plan
- Must update docs if behavior changes

## Code Review
- Reviewer focuses on: correctness, reproducibility, clarity, scope
- Author addresses all comments (or resolves with rationale)

## Reproducibility (research-heavy projects)
- Log: dataset version, commit hash, hyperparams, metrics, hardware
- Store experiment summaries in `docs/experiments/`
