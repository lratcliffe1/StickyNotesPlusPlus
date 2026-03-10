# Test Scaffolding Notes

This folder currently provides refactor validation artifacts for Stage 2.

- `IntegrationChecklist.md` contains scenario-driven checks for logic, migration, integration, and app/widget parity.
- The project currently has no dedicated XCTest target in `StickyNote++.xcodeproj`; when a test target is added, convert checklist items into executable tests in this folder.

Recommended next step once test target exists:

1. Add `HomeDataStoreTests` for day parsing, sort ordering, migration idempotency.
2. Add `DailyTaskMutationServiceTests` for shared creation semantics.
3. Add widget parity integration tests around completion and bump actions.
