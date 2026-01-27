# Project Charter — Ora

## Contributors
- **Project Lead:** Eric Zhu
- **Primary Contributors:** Raul Valle, Alejandro Jimenez, Samuel Schneider, Haley Tarala
- **Secondary Contributors:** Matty Maloni

## Definition
- **Research / Product Question:** What are the trends that support hypertrophy progression? What are the trends that support strength progression? What are the trends that support endurance progression?
- **Claim / Hypothesis:** A local-first, voice-first workout tracker can capture high-quality training data and enable trend analysis to support hypertrophy, strength, and endurance progression.
- **Novelty:** A minimal tool for tracking workouts and recommendations for gym progress.
- **Target Venue / Deliverable Context:** ICML, IEEE EMBC, ML4H, ACSM, NSCA, ISSN.
- **Expected Artifacts:**
  - Code
  - Extensive data
  - Deployable app
  - Paper / analysis

## Delegation (initial)
| Workstream | Owner(s) | Output | Due |
|---|---|---|---|
| Machine learning | Raul Valle | Modeling plan + baseline experiments | TBD |
| Data science | Alejandro Jimenez | Trend analysis + metrics plan | TBD |
| UI design | Haley Tarala, Eric Zhu | UX flows + visual system | 2026-02-14 |
| Frontend engineering | Eric Zhu, Samuel Schneider | MVP Flutter implementation | 2026-02-14 |
| Backend engineering | Alejandro Jimenez, Samuel Schneider | Local data model + services | 2026-02-14 |

## Funding Use
- Budget: TBD
- What we will buy: Cloud / AI usage (potentially)
- Approval process: TBD

## Timeline
- **Weekly meeting time:** Tuesdays at 7:00 PM (timezone TBD)
- **Paper draft date (if relevant):** April 21, 2026

### Primary Milestones
| Milestone | Description | Date |
|---|---|---|
| M1 | Minimum Viable Product | 2026-02-14 |
| M2 | Completing workout features | 2026-03-14 |
| M3 | All other features | 2026-04-14 |
| M4 | Paper draft | 2026-04-21 |

## Definition of Done (DoD)
A milestone is “done” when:
- [ ] Repro steps exist (commands, versions, data pointers)
- [ ] Metrics are reported + comparable to baseline
- [ ] Artifacts are committed (code/docs) and discoverable
- [ ] A demo (or evaluation script) exists
- [ ] Open issues are filed for follow-up work
