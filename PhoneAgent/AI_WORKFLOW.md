# AI workflow

This project has an **AI feature**: the app itself is an LLM agent. It was also **built with AI
development tools**. Both are documented below.

---

## Part 1: the AI feature

### Model and service

* **Service**: Anthropic Claude Messages API (`POST https://api.anthropic.com/v1/messages`,
  `anthropic-version: 2023-06-01`), called directly over HTTPS from the device
  (`entry/src/main/ets/agent/Anthropic.ets`). There is no Anthropic SDK for ArkTS, so the client is
  hand-written: request and response types, retries, error mapping.
* **Models** (chosen in the app): `claude-opus-5-5` (default), `claude-sonnet-5-5`, `claude-haiku-4-5`.
  * Opus 5.5 and Sonnet 5.5 always think (adaptive). The app sets `output_config.effort: "medium"`
    and opts into server-side refusal fallbacks (`fallbacks: "default"`, beta header
    `server-side-fallback-2026-07-01`).
  * Haiku 4.5 is called without effort or fallbacks, which it doesn't support.
  * `tool_choice: {type: "auto"}`. Forced tool choice returns 400 on the 5.5 models, so the
    prompt asks the model to finish with the `finish` tool instead.
  * Top-level `cache_control: {type: "ephemeral"}` (automatic prompt caching). The history is
    append-only, so each step reuses the cached prefix.
* **Bring your own key**: the user pastes an Anthropic API key. Claude.ai account login is not
  offered, because third-party apps may not use Claude.ai credentials.

### Inference flow

1. The user enters a task in the UI. The UI sends `{task, model}` to the accessibility service
   over a bundle-restricted common event.
2. The service builds the first user message from the task and the list of launchable apps
   (`Name (bundle)` per line).
3. Request: the system prompt (`agent/Prompt.ets`), 8 tool definitions (`agent/Tools.ets`) and
   the conversation so far.
4. The response is checked in this order:
   * `stop_reason`: `refusal` and `max_tokens` stop the task without executing anything.
   * then every `tool_use` block is validated against the tool schema in code.
5. Valid calls are executed through the accessibility framework. Each returns a `tool_result`
   with the new screen as text. Invalid calls and failed actions return `is_error: true` with a
   precise reason and the current screen.
6. Repeat until the model calls `finish(success, summary)`. The limit is 25 model calls; there is
   one nudge if the model replies without a tool, and the user can stop at any time.

The model never sees pixels. It sees the accessibility tree as text, for example:

```
App: com.ohos.mms
[0] Image (click) @36,64
[1] Text "New message" @130,64
[3] TextArea (click,edit) @180,120
[6] TextArea hint="Text message" (click,edit) @164,659
[7] Image (click) @332,658
```

### Data handling

| Data | Where it goes |
|---|---|
| API key | App-private Preferences on the device. Sent only as the `x-api-key` header to api.anthropic.com. Never logged, never in IPC events, not in the repo. |
| Task text | Sent to Anthropic. Shown in the in-app log and in `hilog`. |
| Screen contents (labels and text of visible UI elements of the foreground app while a task runs) | Sent to Anthropic as tool results. Not stored by the app beyond the running task. |
| List of installed apps (names and bundle names) | Sent to Anthropic at task start. |
| Model replies | Shown in the in-app log (short form). Kept in memory for the duration of the task. |

The app stores no conversation history on disk. Anthropic's API data-retention policy applies to
what is sent.

### Privacy

* An accessibility agent reads the screen. Whatever is visible in the app being operated (for
  example message threads or contact names) becomes part of the prompt. This is stated in the
  README and should be shown to users before first use. In this prototype, that disclosure is
  the README and the service description.
* Screen reading happens only while a task runs, and only on demand. `onAccessibilityEventInfo`
  ignores all events, and the service does no background monitoring.
* The agent has no permission to send SMS, call, read contacts or capture the screen. It can only
  use the UI the way the user would, so the OS and the apps' own confirmations still apply.

### Limitations

* Icon-only buttons without accessibility labels appear as `Image (click) @x,y`, and the model has
  to infer what they do from position and context.
* The agent is fully autonomous: there is no confirmation step before irreversible actions such as
  Send. That was a deliberate scope decision for the hackathon; a production version should ask
  before sending, paying or deleting.
* Latency is a few seconds per step: one model call, plus about 1.2 s waiting for the UI to settle.
* Prompt injection: text shown on screen, for example an incoming message, is model input and could
  try to steer the agent. Mitigations here: tool results are clearly separated from the task, the
  tool set is narrow, and nothing outside the UI is reachable. Ruling it out completely is not
  possible.
* The emulator has no SIM card, so SMS sending ends at the Messages app's `canSendMessage=false`.
* Text editors built on WebView (for example the Notes app's note body) don't accept accessibility
  `SET_TEXT`. The agent gets an `is_error` and has to work around it.

### Validation approach

* **Unit and integration tests on the device** (`entry/src/ohosTest`, 35 hypium tests, run with
  `scripts/test.ps1`):
  * the tool-call validator against malformed model output (unknown tool, wrong types, out-of-range
    or non-integer index, bad enum, oversized text, missing input);
  * API error and response parsing (401, 429, 529, non-JSON bodies, malformed JSON, missing fields);
  * per-model request options;
  * the screen serializer;
  * the agent loop with a scripted fake model and fake device: parallel tool calls answered in one
    message, `is_error` round trips, recovery with the current screen, refusal, `max_tokens`, the
    nudge, the step limit, user stop, and thinking blocks echoed back unchanged.
  * To check that the async tests are really awaited, an assertion was deliberately made wrong; the
    run failed (34/35) and the change was reverted.
* **On-device spikes** before building on each assumption, using hilog and screenshots:
  * system signing: `appPrivilegeLevel: system_core`;
  * `launcherBundleManager` returns 12 apps;
  * the accessibility service reads Settings (87 nodes in about 300 ms) and Messages;
  * CLICK works, including walking up to a clickable parent;
  * SET_TEXT works only after focusing the field;
  * BACK works;
  * the Send tap reaches Messages (its log shows `send, start`).
* **End to end against the real API**: HTTPS from the emulator and the error path (a dummy key gives
  a clean "API key was rejected") were verified. Before every run the target app was force-stopped,
  so it started from a fresh state. Results on the Oniro 6.1 emulator, 3–4 Oct 2026:

  | Task | Model | Actions | Time | Outcome |
  |---|---|---|---|---|
  | Open Settings and go to WLAN | Opus 5.5 | 2 | 15 s | ✔ WLAN page open |
  | Open Settings and go to WLAN | Haiku 4.5 | 2 | 15 s | ✔ same |
  | *Napisz do babci SMS, że będę na jej urodzinach* (×3 with the final prompt) | Opus 5.5 | 6 | 31 s each | ✔ 3/3: Messages → "+" → contact picker → Babcia → text "Cześć Babciu, będę na Twoich urodzinach!" → Send. Summary in Polish notes that the phone could not confirm sending (no SIM). |
  | same task (×3 with the earlier prompt) | Opus 5.5 | 8 | 41–46 s | Same path, but Send was tapped twice and the success flag varied. This led to the "tap Send once, success=true with a note" rule in the prompt. |
  | Turn on Bluetooth | Opus 5.5 | 3 | 21 s | ✔ toggle on. The emulator has no Bluetooth adapter, so the system state stays "Off". |
  | Turn off Bluetooth | Sonnet 5.5 | 1 | 10 s | ✔ reported "already off", read correctly from the Settings list |
  | *Zanotuj: kupić tort dla babci w sobotę* (note) | Opus 5.5 | 10 | ~70 s | Partial. The note body is a WebView editor that accessibility can't type into (one `is_error`). The agent switched to the note title, found its 20-character limit, saved "Sobota: tort babci" and explained this in the summary. |

  The step logs of these runs come from `hilog` (tag `AgentA11y`) and the in-app log.

---

## Part 2: AI-assisted development

### Tools used

| Tool | Used for |
|---|---|
| **Claude Code** (Anthropic CLI agent) | Research, design, implementation, debugging and docs: all code in this repository. |
| Model: **Claude Opus 5.5** (`claude-opus-5-5`, effort `xhigh`) | Implementation session (this repository's history). |
| Claude Code **`claude-api` skill** | Checked the Messages API details before writing the client: model IDs, thinking defaults per model, forced `tool_choice` returning 400 on the 5.5 models, `fallbacks: "default"`, error types and retry rules. |
| An earlier Claude Code research session | Platform research and decision-making (see below). It produced the handoff document that drove implementation. |
| MCP servers | None used. |

### Workflow

1. **Ideation and research** (Claude Code research session). The challenge PDFs were read first.
   Then two routes were compared:
   * **Route A**: a normal app on the commercial HarmonyOS emulator. Rejected: every way of
     operating other apps there is system-only. Accessibility read/click of other apps has been
     deprecated for third parties since API 12, UiTest only runs via `aa test`, input injection is
     `system_core`, and explicit `startAbility` into other apps is blocked.
   * **Route B**: OpenHarmony / Oniro, with the app self-signed as a system app using the public
     OpenHarmony test CA. Accepted.

   The session ended with a structured interview of the developer ("grilling") that fixed the
   decisions: accessibility tree as text instead of screenshots, fully autonomous, Anthropic only,
   no streaming, ArkTS native, minimal tests. The output was a handoff document listing the
   decisions, sources, risks and a phased plan with a gate per phase.
2. **Implementation** (Claude Code, this repository). The main prompt was *"Your task is described
   in handoff-openharmony-phone-agent.md. Is everything clear and understandable?"*, followed by
   short confirmations. Claude Code first checked the handoff against the real machine, found the
   discrepancies (Windows instead of a Mac, DevEco already installed, a HarmonyOS template instead
   of OpenHarmony) and asked three questions before starting. Then it worked phase by phase:
   * **P0 environment**: Oniro emulator under WSL2 with KVM, full SDK from the OpenHarmony CI,
     hello-world installed.
   * **P1 system signing**: `scripts/sign.ps1`; a system API returns data.
   * **P2 accessibility spike**: a debug command channel drove read/click/type/back in Settings and
     Messages from the PC.
   * **P3 agent loop**: client, tools, executor, IPC, UI.
   * **P5 tests and docs.**

   Each phase ended with an on-device check (screenshot, hilog or `bm dump`) before the next
   started, and with a git commit.
3. **Review and validation of generated code**:
   * every build goes through the strict ArkTS compiler;
   * every phase gate was verified on the emulator rather than assumed;
   * request shapes were checked against current API docs (the `claude-api` skill), not the
     model's memory;
   * the test suite was checked to catch failures (deliberately broken assertion);
   * the developer reviewed the diffs and commits.

### Reusable instructions and configuration

* `handoff-openharmony-phone-agent.md`: the handoff from the research session, used as the task
  specification (decisions, constraints, plan, risks).
* `scripts/*.ps1` / `scripts/emulator.sh`: written so the same commands work for humans and agents
  (non-interactive, exit codes checked).

### Unsuccessful approaches and lessons learned

* **Commercial HarmonyOS emulator (Route A)**: dropped during research (see above).
* **QEMU started from `wsl.exe`** was killed whenever the launching `wsl.exe` exited, even with
  `setsid nohup`. Fixed by running it as a transient **systemd unit** (`scripts/emulator.sh`).
* **Extracting the SDK from inside WSL onto NTFS** was very slow: still unfinished after 10 minutes
  for one archive. Windows' own `tar` did all four in 14 s.
* **DevEco's `hvigorw.bat`** checks `NODE_HOME` but then runs plain `node.exe` from `PATH`. The
  build script calls Node directly.
* **HarmonyOS template vs OpenHarmony**: the template's `buildVersion` field and the `phone` device
  type are invalid for OpenHarmony API 20 (OpenHarmony uses `default`). hvigor also refuses an SDK
  without the `native` component.
* **`bundleManager.getAllBundleInfo`** now needs the user-granted `GET_INSTALLED_BUNDLE_LIST`, even
  for system apps. Switched to `launcherBundleManager.getAllLauncherAbilityInfo`, which needs only
  `GET_BUNDLE_INFO_PRIVILEGED` and returns exactly the launchable apps.
* **`SET_TEXT` returned success but changed nothing** until the field was focused. `type_text` now
  clicks first, waits 400 ms, then sets the text.
* **The accessibility service reported "ability not installed"** after an *update* install that
  added the extension. A fresh install registers it (documented in the README).
* **Status events raced**: an incremental "running" status overtook the final "done" status. Fixed
  with sequential publishing plus instance and version stamps. A `RUN` sent while the service was
  still connecting was lost; fixed with an acknowledgement timeout in the UI.
* **After the service process was killed** (e.g. `aa force-stop`), the framework restarted it, but
  through the *older* callbacks (`onConnect`, `onAccessibilityEvent`). The API 20 ones were not
  called, so the service never subscribed to commands. It now handles both callback sets, and the
  UI restarts the service (disable + enable) if a Run isn't acknowledged.
* **Signing from the IDE**: hvigor's `signingConfigs` only accepts passwords encrypted with a
  DevEco-specific local material folder, so our script-made system-app profile couldn't be used
  from the IDE. The format is readable in hvigor's own `decipher-util.js`. `scripts/ide-signing.js`
  generates compatible material, and the project `hvigorfile.ts` injects the config at build time,
  which keeps `build-profile.json5` free of machine-specific secrets.
* **Prompt iteration on real runs**: the first SMS runs tapped Send twice and set the success flag
  inconsistently when the phone (no SIM) gave no confirmation. One rule in the system prompt fixed
  both: 3/3 runs afterwards took 6 actions and 31 s each.
* **Lesson**: on a young platform, verify each assumption on the device before building on it.
  Several documented behaviours differed in practice, and each spike took minutes, whereas
  finding the same problem later would have cost hours.
