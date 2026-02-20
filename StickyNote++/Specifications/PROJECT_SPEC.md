# Sticky Notes, Sticky Life — Project Spec

This document is the human-readable source of truth for the Sticky Notes, Sticky Life app.
It captures product intent, UX philosophy, and scope boundaries.  
Implementation details live in Spec.md.

---

## 1. Overview

Sticky Notes, Sticky Life is a calm, opinionated habit and task app inspired by *Atomic Habits*.
It helps individuals build consistent mornings and complete daily tasks by making progress
visible, friction intentional, and feedback immediate.

Unlike traditional to-do apps, it does not optimise for volume or power-user workflows.
It optimises for *showing up every day*.

**Primary audience**
- People familiar with Atomic Habits *and*
- People who want a simple, low-friction alternative to complex task managers

**Elevator pitch**
A habit and task app that shows you exactly what matters right now — and makes consistency
feel obvious, easy, and satisfying.

---

## 2. Goals

- **G1 — Consistent mornings**  
  Help users reliably complete their morning routine without decision fatigue.

- **G2 — Reduce procrastination**  
  Discourage endlessly deferring tasks through gentle friction and visual urgency.

- **G3 — Visible progress**  
  Make consistency and streaks immediately visible through simple, rewarding visuals.

---

## 3. Non-Goals

This app is intentionally *not*:

- A productivity power tool
- A project management system
- A tagging / filtering / prioritisation engine
- A collaboration or sharing app
- A quantified-self analytics dashboard

Out of scope for v1:
- Multiple routines
- Task priorities
- Tags, folders, or projects
- Retroactive editing of history
- Cross-user collaboration
- Analytics or tracking beyond iCloud sync

---

## 4. User Persona

### Persona: “The Routine Builder”

- **Context**  
  Busy, mentally overloaded, wants structure without overhead.

- **Motivations**  
  Wants mornings to run on autopilot.
  Wants to stop carrying the same tasks forward every day.

- **Pain Points**  
  - Traditional todo apps feel heavy and endless
  - Habit apps feel abstract or gamified
  - Loses motivation when progress isn’t visible

Sticky Notes, Sticky Life exists primarily for this persona.

---

## 5. Core User Scenarios

- As a user, I want to open the app in the morning and immediately see my morning routine.
- As a user, I want to visually see whether I’m staying consistent over the week.
- As a user, I want to cross off tasks in a way that feels physical and satisfying.
- As a user, I want to be discouraged from endlessly postponing tasks.
- As a user, I want gentle reminders only when I’m at risk of falling off track.
- As a user, I want my data to sync across devices without thinking about it.

---

## 6. UX Philosophy

- **Gently opinionated**  
  The app nudges behaviour but never scolds or blocks progress.

- **Context over choice**  
  Show one primary list at a time (morning *or* daily).

- **Friction with intent**  
  Friction exists only to prevent procrastination, never to slow completion.

- **Calm visual language**  
  Minimal copy, soft transitions, subtle colour shifts.

Tone mirrors *Atomic Habits*: practical, encouraging, non-judgemental.

---

## 7. Navigation Model

Tab bar with four primary tabs:

1. **Home** — contextual sticky note + 7-day summary
2. **Calendar** — read-only history view
3. **Add** — add tasks to any day
4. **Settings** — routines, time rules, notifications

Calendar → Home is the primary historical navigation loop.

---

## 8. Visual Design

- Modern digital “sticky note” aesthetic (not literal paper)
- Solid diagonal split circles for progress
- Red → green gradients for completion
- Increasing urgency colours for deferred tasks
- Today clearly highlighted
- Persistent ink-style strike-through for completed items

Supports light and dark mode.

---

## 9. Accessibility

- Dynamic Type supported throughout
- All gesture-based actions have button alternatives
- VoiceOver labels for all interactive elements
- Sufficient contrast for all colour states

---

## 10. Privacy

- No analytics
- No tracking
- No data collection beyond iCloud sync
- Data belongs to the user and stays within their iCloud account

---

## 11. Risks & Mitigations

- **Gesture complexity**  
  → Provide explicit buttons as fallbacks.

- **Scope creep**  
  → Enforce Non-Goals strictly.

- **CloudKit edge cases**  
  → Silent or minimal surfacing to preserve calm UX.

---

## 12. Roadmap (High-Level)

- **M1 — Foundations**  
  Morning routine, daily tasks, sticky note UI.

- **M2 — Consistency**  
  Streaks, 7-day history, calendar view.

- **M3 — Delight**  
  Persistent strike gestures, urgency colours, haptics.

- **M4 — Extension**  
  Widgets, notifications, future Mac app.

---

## 13. Glossary

- **Morning Template** — The editable routine definition in Settings
- **Morning Entry** — A per-day instance of a morning item
- **Daily Task** — A task tied to a specific day
- **Bump Count** — Number of times a task was deferred
- **Selected Day Context** — The day currently being viewed

---

