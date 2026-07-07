---
name: scaffold-state-controller-test
description: |
  Generate a unit-test skeleton for a StateController (scope architecture). Use when the user asks
  "напиши тесты для <feature>", "make tests for the controller", "test scaffold", "scaffold test",
  or after creating a new StateController via scaffold-feature. Reads the controller, parses public
  methods and State fields, generates test/features/<name>/<name>_state_controller_test.dart with a
  group per method and baseline scenarios (success, error-to-state, rollback, mutex when applicable).
---

# scaffold-state-controller-test

Generate a test skeleton for a `StateController`. The living etalon is the project's OWN existing
tests - the templates below are a fallback for projects with no tests yet.

## Before generating (dialect first)

1. Read `CLAUDE.md` and `.claude/context/*.md` (conventions) if present - test file layout, fake
   strategy, and any designated etalon tests override this skill's defaults.
2. Glob `test/**/*_state_controller_test.dart`. If any exist, read the closest one and CLONE its
   idioms (setUp/tearDown shape, fake helpers, assertion style) instead of the template below.
3. Check `test/helpers/` (or the project's equivalent) for existing fakes/factories. Extend them;
   do not create parallel ones.
4. Detect the mocking strategy: if the project has mockito/mocktail in dev_dependencies, follow it;
   otherwise default to MANUAL fakes (a `Fake<X>Repository` class with a `throwOnNext` field and
   per-call response setters) - they read better and need no codegen.

## When NOT to apply

- The controller already has tests - extend by hand, do not regenerate over them.
- A plain utility class (no StateController) - write a normal unit test, no template.

## Algorithm

1. **Read** the controller file fully: controller name, State name, constructor dependencies,
   public methods (skip `_private` and `dispose`), and its type traits:
   - optimistic mutations (snapshot + rollback in the error path)?
   - a per-id mutex / `runExclusive`-style serialization?
   - paged list with loadMore/dedup?
   - debouncing / timers?
   - key-value storage (SharedPreferences etc.)?

2. **Generate** `test/features/<name>/<name>_state_controller_test.dart` (adjust the path to the
   project's test layout):

   ```dart
   import 'package:flutter_test/flutter_test.dart';
   // package imports for the controller, State, StateType, fakes

   void main() {
     group('<Name>StateController', () {
       late Fake<Dep>Repository repo;
       late <Name>StateController controller;

       setUp(() {
         repo = Fake<Dep>Repository();
         controller = <Name>StateController(repository: repo);
       });

       tearDown(() {
         controller.dispose();
       });

       test('initial state is idle with default fields', () {
         expect(controller.state.stateType, StateType.idle);
       });

       group('<method>', () {
         test('success path', () async {
           // arrange: seed the fake's response
           // act: await controller.<method>(...)
           // assert: state fields
         });

         test('error path puts the error object into state', () async {
           repo.throwOnNext = Exception('network');
           // act + assert: stateType failure, state.error is the exception
         });
       });
     });
   }
   ```

3. **Never generate**:
   - Tests for private methods.
   - `controller.setState(...)` calls from tests - it is protected; seed via the constructor's
     `initialState:` instead.
   - Mocks for repositories/methods that do not exist - extend the project's fake first.
   - Placeholder TODO tests - either implement the scenario or drop it.

4. **Run** the generated file (`flutter test test/features/<name>/`) and make the skeleton compile
   and pass before reporting done. Include the test output in the report.

## Scenario templates by controller type

- **Optimistic + rollback (+ per-id mutex)**: for every mutating method - success path; rollback on
  error (state AND any shared updates layer restored, list lengths restored); when a mutex exists -
  two parallel calls on the same id serialize; for toggle methods - all branches (off->on, on->off,
  opposite->requested).
- **Paged list (loadMore)**: refresh loads page one; loadMore appends with dedup (feed a duplicate
  id, assert single instance); order preserved if the controller sorts after merge; `canLoadMore`
  correct after refresh and after the last page.
- **Simple feed**: load populates; repeated load without force is a no-op (fake counts calls);
  `forceLoad: true` reloads; error path lands in state.
- **Debounce / timers**: below-threshold input clears results; above-threshold input resolves after
  the debounce period; a second input cancels the first timer. Use real `Future.delayed` unless the
  project already uses FakeAsync.
- **Key-value storage**: in-memory implementation in setUp; empty-storage path produces no errors.
