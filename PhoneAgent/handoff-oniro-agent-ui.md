# Handoff: Oniro Agent UI changes (planning only, nothing implemented)

Repo: `C:\Users\user\PycharmProjects\hackyeah2026` (branch `main`, clean apart from the untracked plan below). App = `PhoneAgent/`, an ArkTS app for OpenHarmony/Oniro.

## Status
- **No app code was changed.** The only output is the plan file:
  `docs/superpowers/plans/2026-10-03-oniro-agent-ui.md` (untracked, not committed).
- The user wants **planning only**. Don't implement, don't commit, don't edit app code until they explicitly say so. They got upset when they saw edits (those were edits to the plan file) and asked for "revert + handoff".
- Open question for the user: keep the plan file in `docs/`, or move or delete it? (It's the main deliverable; it was not deleted.)

## What the user asked for (original request, Polish)
1. The app should be called "Oniro Agent" on screen and everywhere.
2. An agent-style logo ("OA"), in the spirit of Gemini, Siri and Celia.
3. A nice-looking app; use `/frontend-design:frontend-design`.
4. API keys moved to Settings, off the main screen.
5. Research: hold the Home button to open the agent, like Gemini on Android.
6. Added mid-session: **model AND reasoning effort selectable in Settings.**

## Decisions made in grilling
All are recorded in the plan's "Decisions" table (D1–D11) and the effort table. In short:
- The name only changes in labels and docs. Bundle ID `com.hackyeah.phoneagent` stays.
- Logo: an O gradient ring plus an A arrowhead spark.
- Look: follows the system light/dark theme; the orb is the only strong color.
- All configuration moves to Settings.
- Timeline shows steps first, with the model's thoughts folded.
- Overlay: a floating orb, a bottom sheet, and a non-focusable status pill.
- SystemUI long-press spike, timeboxed to 2 h.
- Order: visible changes first.
- Set up the emulator on this machine first.
- No commits.

## Research findings (point 5): not in the plan's prose beyond Task 11 background
- In stock OpenHarmony SystemUI (`applications_systemui`, `features/navigationservice/.../KeyCodeEvent.ts`), the soft Home button sends no key event. On touch-up it calls `startServiceExtensionAbility` on the launcher, and it has no long-press handler. A normal app cannot hook it.
- `inputConsumer.on('key', {finalKeyDownDuration})` (system API) only sees physical keys, and the emulator has no Home key. Accessibility `onKeyEvent` is deprecated since API 12 and also covers physical keys only.
- The only real route is patching and reinstalling `com.ohos.systemui` (plan Task 11, with gates).
- Not verified: whether Oniro 6.1 uses the legacy SystemUI or SceneBoard. The emulator couldn't start here because the WSL distro `Ubuntu-24.04` isn't installed and there's no full SDK in `%LOCALAPPDATA%\OpenHarmony\Sdk`.

## Known gaps in the plan (effort feature, added late, partially threaded through)
- Done in the plan:
  - D11 and the per-model effort table
  - Task 6b (providers, clients, Settings fields, `RunRequest.effort`, tests)
  - Task 7 Settings page code (the effort `Select`, reset on model or provider switch)
- Still to fix in the plan:
  - Task 8 Index: the run request must include `effort: this.settings.effort`. The model chip should show `"<model>, <effortLabel lower> effort"` when the effort isn't empty, and the default `settings` literal needs `effort: ''`.
  - Task 10 overlay `run()`: add `effort: s.effort` to the `RunRequest`.
  - Task 6b Step 6 notes that Index from Task 6 needs `effort: ''` in its `AgentSettings` literals.
  - File map: `common/Settings.ets` and `common/Bridge.ets` rows should mention effort.
- The OpenAI/xAI/Gemini effort values were taken from memory. Task 6b Step 2 says to verify them with Context7. Anthropic values were verified with the claude-api skill: Opus 5.5 and Sonnet 5.5 accept low/medium/high/xhigh/max, and Haiku 4.5 has none.

## Next steps
1. Ask the user whether the plan file stays where it is.
2. Patch the gaps listed above in the plan, editing the plan only.
3. Run the writing-plans self-review (spec coverage, type consistency), then ask the user to review the plan and choose an execution method (subagent-driven or native).

## Suggested skills
- `superpowers:writing-plans`: finish and self-review the plan; it covers the handoff/execution-choice wording.
- `grill-me`: only if new open decisions come up.
- `frontend-design:frontend-design`: the user explicitly asked for it; use it when implementing Tasks 2, 3 and 8–10.
- `claude-api`: before touching `Anthropic.ets` or effort values.
- Later, only when the user approves implementation: `superpowers:subagent-driven-development` or `superpowers:executing-plans`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`, `superpowers:systematic-debugging` (emulator/SystemUI spike).
