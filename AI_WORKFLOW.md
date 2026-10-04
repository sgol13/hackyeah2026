# AI workflow

This file has two parts: the **AI feature inside Oniro Agent** (part 1) and **how we used AI tools to build it** (part 2). Required by the challenge rules; no API keys, credentials or personal data are included anywhere in the repository.

---

## Part 1: the AI feature in the app

### Model / service

Oniro Agent does not ship a model. It calls a cloud LLM that the user picks in **Settings → AI model**:

| Provider | API | Status |
|---|---|---|
| Anthropic Claude | Messages API (`/v1/messages`), tool use, extended thinking | tested end to end on the emulator |
| OpenAI | Chat Completions, tools | implemented + unit-tested, live endpoint checked only with an invalid key |
| xAI Grok | OpenAI-compatible Chat Completions | implemented + unit-tested, same |
| Google Gemini | `generateContent`, function calling | implemented + unit-tested, same |

The user enters their own API key, chooses a model (suggested list or any custom model ID, validated to plain identifier characters) and, where the model supports it, a reasoning-effort level. There are no vendor SDKs: each provider is one small translator over `@kit.NetworkKit` HTTP (`entry/src/main/ets/agent/Anthropic.ets`, `OpenAiCompat.ets`, `Gemini.ets`).

### Inference flow

```
user task ──► AgentLoop (inside AccessibilityExtensionAbility)
                │ 1. read the active window's accessibility tree
                │ 2. serialize it to numbered text lines (ScreenText.ets)
                │ 3. send task + screen + tool definitions to the model
                │ 4. model answers with ONE tool call
                │ 5. validate the tool call (Tools.ets) ── invalid ──► error sent back to model, nothing executed
                │ 6. execute it on the device (DeviceExecutor.ets)
                │ 7. send the result + the NEW screen back ──► repeat from 3
                └─ until `finish`, STOP, 25 model calls, or 4 actions in a row with no screen change
```

Tools available to the model: `list_apps`, `launch_app`, `read_screen`, `click`, `type_text`, `scroll`, `press_key`, `set_alarm`, `read_skill`, `finish`. The system prompt is in `entry/src/main/ets/agent/Prompt.ets`. Full component description: [ARCHITECTURE.md](ARCHITECTURE.md).

### Data handling and privacy

What leaves the phone, and only to the provider the user selected, over HTTPS:

- the task text the user typed,
- the **text of the current screen** of the app being operated (element type, visible text, accessibility description, state; capped at 150 elements and 80 characters per text),
- the list of installed apps (name + bundle name) and the phone's local date/time,
- names, descriptions and (when the model asks for one) the body of the user's enabled skills.

What does **not** leave the phone: screenshots (none are taken: no vision model, no `CAPTURE_SCREEN`), the API key (sent only as the auth header to its own provider), anything from apps the agent is not currently operating.

Storage: API keys, settings and skills live in the app's private `Preferences`. Each provider keeps its own key. The step timeline of a task is shown in the app only. Nothing is sent to us; there is no backend.

Privacy trade-off we are honest about: whatever is on the screen while the agent works (for example message text or contact names) is sent to the chosen cloud provider and is subject to that provider's data policy. The user starts every task explicitly and can stop it at any time; the edge glow and status pill show when the agent is active. The architecture is provider-agnostic, so an EU-hosted or on-device model can be plugged in as one more translator (see Limitations).

### Validation of model output

The model is never trusted (details and exact numbers: README, *Technical execution*):

- every tool call is validated before anything runs: argument types, element index within the current screen, enum values, text length ≤ 2000, bundle name exists;
- an invalid call returns a precise error to the model; nothing is executed;
- a failed action returns the error together with the current screen so the model can recover;
- refusals and truncated replies end the task without executing anything;
- a reply without a tool call gets one nudge, then the task stops;
- loop guards: 25 model calls per task, stop after 4 actions with no screen change, STOP button effective immediately (also during a pending HTTP request);
- API errors: retries only for 429 / 5xx / network errors with backoff and `Retry-After`; 401/403/404/billing errors are shown in plain language without retrying.

### Limitations

- **Cloud only today.** No on-device model; the agent needs internet and a provider key.
- **No confirmation before irreversible actions** (Send, Delete) in this hackathon version.
- **Prompt injection:** on-screen text (for example an incoming message) is model input. The narrow tool set limits the damage but cannot rule it out.
- Icon-only buttons without accessibility labels appear as `Image (click) @x,y`; the model has to infer them from position.
- WebView text fields ignore accessibility `SET_TEXT`.
- Only Claude was tested end to end with a real key; the other three providers are covered by unit tests with recorded responses.
- The emulator has no SIM: the agent fills in and taps Send, but the SMS is not delivered.

### How the AI feature was validated

- On-device hypium test suite (`entry/src/ohosTest`, run with `scripts/test.ps1`, no paid API calls): tool validation, malformed / refused / truncated model responses, API error handling for all 4 providers, the agent loop driven by a scripted fake model (`a11y/ScriptedLlm.ets`), screen serializer, skills parsing.
- Real-model runs on the Oniro 6.1 emulator with Claude: SMS via Messages 3/3 runs (6 actions each), Settings → WLAN, Bluetooth on/off, and the multi-app demo task (Notes → Calendar → Reminders → Messages). Records in [DEMO.md](DEMO.md).

---

## Part 2: AI tools used during development

### Tools

| Tool | Used for |
|---|---|
| **Claude Code** (CLI) with **Claude Opus 5.5** | research, planning, almost all code, scripts, tests, docs |
| **Superpowers** plugin skills for Claude Code | `writing-plans`, `executing-plans`, `subagent-driven-development`, `test-driven-development`, `systematic-debugging`, `verification-before-completion` |
| **grill-me** skill ([mattpocock/skills](https://github.com/mattpocock/skills)) | the agent interviews us about every design decision before writing a plan |
| **Context7 MCP server** | current OpenHarmony / ArkTS / provider API documentation |
| Claude Sonnet 5.5, GPT models via the app itself | runtime models during end-to-end testing (not development tools) |

No other coding assistants, no MCP servers other than Context7.

### Main prompts and reusable instructions

The repeated loop for every feature was:

1. *"Do research about this"* — the agent reads the challenge PDF, OpenHarmony docs and the SDK `.d.ts` files.
2. *"Plan"* + `/grill-me` — the agent asks us one question at a time until every decision is made (≈23 questions for the first plan: providers, where the loop runs, screen-as-text vs screenshots, signing, emulator host...).
3. *"Implement according to the plan"* — with `superpowers:executing-plans` / `subagent-driven-development`, one task per step, tests first where possible.
4. *"Test + review"*, then commit.

The written artifacts of this process are in the repository:

- [`docs/handoff-openharmony-phone-agent.md`](docs/handoff-openharmony-phone-agent.md) — research results, all grilling decisions, phased plan with gates, risks. This was the hand-off between sessions.
- [`docs/handoff-oniro-agent-ui.md`](docs/handoff-oniro-agent-ui.md) — hand-off for the UI / overlay phase.
- [`docs/superpowers/plans/2026-10-03-oniro-agent-ui.md`](docs/superpowers/plans/2026-10-03-oniro-agent-ui.md) — step-by-step plan for the UI, orb, pill and glow.
- [`docs/superpowers/plans/2026-10-04-user-skills.md`](docs/superpowers/plans/2026-10-04-user-skills.md) — plan for user skills.

### Workflow, ideation → debugging

- **Ideation (human):** the idea ("Gemini for Oniro": an agent that operates any app) was ours. AI suggestions for ideas were generic, so we used AI only to check feasibility on OpenHarmony 6.1: accessibility APIs, system-app signing with the public test CA, float windows.
- **Architecture (AI + human):** decided in the grilling session; key calls were ours (loop inside the accessibility extension, text instead of screenshots, no vendor SDKs, system app without modifying the OS).
- **Implementation (AI, human-steered):** in phases with a gate each: emulator + signing spike → accessibility spike (read/click/type in Settings) → agent loop with Claude → SMS demo 3× in a row → tests and docs → UI/overlay → more providers → skills → companion apps. The commit history follows these phases.
- **Testing:** hypium tests written with the code; scripted fake model for keyless end-to-end runs on the device.
- **Debugging:** `superpowers:systematic-debugging` on emulator logs (`hilog`), UI-tree dumps (`build/*.json`) and screenshots (`scripts/screenshot.ps1`).

### How generated output was reviewed, tested and validated

- Every change was built, installed and exercised on the Oniro emulator by a human, not only "compiles".
- The test suite (`scripts/test.ps1`) had to pass before a commit.
- Real-model runs were repeated (SMS 3/3) before a feature counted as done.
- We read the diffs; claims in the README were checked against the code and against runs (for example untested providers are marked as untested).

### Unsuccessful approaches and lessons learned

- **Emulator on Apple Silicon** (QEMU TCG) was too slow; we moved to Windows + QEMU with WHPX and wrote `scripts/start-emulator.ps1` (no WSL).
- **`hdc shell accessibility enable`** no longer exists in 6.1 and Settings does not list services → we enable the service from code with `config.enableAbility` (system API).
- **Stock Notes** is a WebView: its body is not exposed to accessibility and ignores `SET_TEXT` → companion Notes app.
- **No usable Calendar / alarm UI on the image** → Calendar and Reminders companion apps and the `set_alarm` tool over `reminderAgentManager`.
- **Long-press Home** cannot be hooked without patching SystemUI → floating orb instead (we chose not to modify the OS).
- **Typed contact names are not resolved** in Messages → the prompt tells the model to use the contact picker.
- `SET_TEXT` inserts at the cursor on this image → the executor selects existing text first.
- Lesson: AI writes code fast but needs hard gates (on-device check, tests, repeated runs); without them it confidently reports success that did not happen.
