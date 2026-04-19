# NotchPal MVP — Findings

Fill this in as you run the spike. Do not wait until the end. Each section has a "fill-in" prompt below it. Keep answers concrete: a claim without evidence is not a finding.

**Spike dates:** [start] → [end]
**Hours spent:** [track honestly, including debugging]
**Machine tested on:** [e.g., MacBook Pro 14" M3, macOS 15.x]

---

## 1. Did the six success criteria pass?

Go through `PRD.md` §Success criteria one by one. For each: PASS / PARTIAL / FAIL, plus one sentence of what actually happened.

1. Panel renders under the notch with correct geometry — [ ]
2. Panel stays above fullscreen apps (Safari+YouTube, Xcode, Keynote) — [ ]
3. Hover expand/collapse with spring, respects Reduce Motion — [ ]
4. File drop onto collapsed notch triggers expansion + shows file — [ ]
5. LLDB-mutable `AgentStatus` drives the UI — [ ]
6. No focus theft over 30 minutes of mixed use — [ ]

**CPU at idle (Activity Monitor):** [measured %]

---

## 2. What surprised us?

Things that were harder than expected, easier than expected, or simply not what the PRD assumed. Be specific — "hover was weird" is useless, "onHover fires during drag-over causing double state transitions" is useful.

- [surprise 1]
- [surprise 2]
- [surprise 3]

---

## 3. Would DynamicNotchKit have saved meaningful time?

Read the actual source of `github.com/MrKai77/DynamicNotchKit` (not just the README). Compare to what we wrote in `Sources/Window/`. Answer concretely:

- **Hours saved if we'd adopted it:** [estimate]
- **Hours lost to learning its abstractions and fighting its opinions:** [estimate]
- **Verdict for the real product:** [adopt / wrap / skip]
- **Why:** [one paragraph]

---

## 4. The known bugs

Every bug you hit that didn't block the spike but will block the product. Include severity and a rough fix direction.

| Bug | Severity | Fix direction |
|-----|----------|---------------|
| Hover-during-drag double-fires | medium | Distinct drag-hover state, separate timeout |
| [bug] | | |
| [bug] | | |

---

## 5. The honest go/no-go

One of three answers, picked deliberately:

- [ ] **GO.** The platform holds up. Proceed to a HEKLA-surface PRD.
- [ ] **PIVOT.** The platform works but the HEKLA-surface framing is wrong. The right framing is [...].
- [ ] **NO-GO.** The platform is fundamentally fragile for our use case because [...]. Stop investing.

**Why this answer and not another:** [two or three sentences, no hedging]

---

## 6. If GO: the five hardest remaining problems

Not "add a preferences pane" — real engineering challenges that need design work before we can commit a timeline. Rank by risk.

1. [hardest problem]
2.
3.
4.
5.

---

## 7. If GO: what the HEKLA surface actually looks like

A paragraph, not a spec. What does the user see, what does it replace in their current HEKLA workflow, and what would make them say "I'd notice this missing"?

[paragraph]

---

## 8. If GO: rough effort to first usable HEKLA-surface release

Use the agent-hour-estimator skill to produce three tiers (vertical slice, parity demo, production-credible). Don't just paste a number.

- **Vertical slice (1 agent, status only, no drop):** [hours, with assumptions]
- **Parity demo (3 agents, status + drop + notifications):** [hours]
- **Production-credible (full HEKLA integration, error handling, reconnect, external display policy decided):** [hours]

---

## 9. What we would do differently next spike

Meta-observations on the spike process itself. Was 2-3 days the right budget? Did CLAUDE.md's anti-scope-creep rules hold? Did we ask the right question?

[paragraph]
