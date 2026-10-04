# Handoff: OpenHarmony "phone agent" app — HackYeah 2026 Huawei challenge

Date: 2026-10-03 (hackathon 3–4 Oct 2026, Tauron Arena Kraków; deadline per HackYeah schedule, results 4 Oct).
User language: Polish (casual, blunt). User has caveman-mode output style active. User prefers minimal, working solutions; decides fast.

## Source docs (read these, don't re-summarise)
- Challenge rules: `~/Downloads/5c37d383-6e2a-4e33-b2f5-77e5436127c7-2.pdf`
- Challenge description + tech requirements + deliverables + scoring: `~/Downloads/f97e834f-d47c-4acf-8228-5d894329ec91-2.pdf`
  Key constraints: target HarmonyOS/OpenHarmony/Oniro, **API 20+ (min API 20)**, `.hap`, runs on emulator, reproducible README, public repo, demo video, ARCHITECTURE desc, `AI_WORKFLOW.md` mandatory (AI feature + AI dev tools), all in English. "Improvement without modifying the system itself." Scoring: originality/usefulness/tech execution/platform capabilities 20% each, demo 10%, reproducibility 10%; jury checks tests, error handling of bad model output, no secrets, minimal permissions.

## Goal
Phone app = general AI agent using remote LLM (Anthropic API key pasted by user, model picker). User types e.g. "napisz do babci sms że będę na jej urodzinach" → agent opens Messages app, fills recipient + text, presses Send, finishes. Must be general (drive any app), not a per-app tool catalogue.

## State
- Research + grilling DONE. No code written. Nothing downloaded/installed yet (user asked: research only until now).
- Working dir in this session (`managed-agent-sandbox`) is UNRELATED to the hackathon — create a new repo elsewhere.
- Host: MacBook Apple M5 (arm64), 24 GB RAM, ~96 GB free. DevEco Studio and `hdc` are NOT installed on this Mac (user's existing DevEco HarmonyOS emulator lives elsewhere / is irrelevant now).
- Last open question to user (Q23, unanswered): run Oniro emulator on the M5 (QEMU TCG, slow) vs cloud x86 Linux VM with KVM (headless + SSH tunnel VNC 5900 / hdc 55555). Recommendation given: start M5 boot now, switch to KVM VM if no usable UI in ~45 min. Also awaiting user's confirmation of shared understanding before starting P0.

## Decisions made (grilling)
- Platform: **Route B** — pure OpenHarmony / **Oniro emulator v6.1** (OpenHarmony 6.1-Release = API 23; build with API 20 full SDK, min API 20). App **self-signed as system app** (`apl: system_core`, `app-feature: hos_system_app`) with PUBLIC OpenHarmony SDK signing materials. Not root, no system image modification.
- User rejected a fallback cut-off ("lecimy") — no plan-A timebox, but agent/LLM code is platform-agnostic anyway.
- Agent perception: accessibility tree as text (`[7] Button 'Send'`), model replies with tool calls (click/type). No screenshots/vision.
- Fully autonomous (no in-app confirmation step).
- LLM: Anthropic only, API key in Preferences (plaintext sandbox, simplest), hardcoded model list `claude-haiku-4-5`, `claude-sonnet-5-5`, `claude-opus-5-5`, **no streaming**, `tool_choice: auto` (forced tool_choice returns 400 on 5.x models). No Claude.ai OAuth — Anthropic ToS forbids third-party Claude.ai login.
- No voice, no narrative work ("narracja nie ma znaczenia"), InsightIntent not in MVP.
- Tests minimal: one hypium file (tool_use parser, dispatcher, bad model output → is_error, tree serializer).
- ArkTS native (no RNOH).

## Key research findings (with why route A was dropped)
Commercial HarmonyOS / DevEco emulator, normal third-party app — all system-only:
- Accessibility read/click of other apps: public APIs deprecated since API 12; replacements `-sys` + `ACCESSIBILITY_EXTENSION_ABILITY`.
- `@ohos.UiTest` only from `aa test` via hdc. `inputEventClient` inject = system_core.
- `getAllBundleInfo`, `insightIntentDriver` (execute/list other apps' intents), A2A client = system only. Explicit `startAbility` to 3rd-party app blocked (16000018).
- `sms.sendShortMessage` needs SEND_MESSAGES (system). Only compose-draft via `com.ohos.mms` Want / `sms:` URI.
- PC-side agents (Open-AutoGLM, hmdriver2, Midscene) use hdc+uitest from PC → violates "app on device".

Route B facts (OpenHarmony docs + 6.1 source; not runtime-tested by anyone we found):
- Signing: edit `UnsignedReleasedProfileTemplate.json` (SDK `toolchains/lib`), set apl/app-feature/`acls.allowed-acls`, also list ACL perms in `requestPermissions`, sign with `hap-sign-tool` + bundled `OpenHarmony.p12` (password = public default from SDK docs). Stock OpenHarmony trusts these certs (`security_appverify/.../config/OpenHarmony/trusted_apps_sources.json`). Docs: https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/security/app-provision-structure.md , .../hapsigntool-guidelines.md
- Full SDK required for systemapi d.ts: `mac-sdk-full` from https://dcp.openharmony.cn/workbench/cicd/dailybuild/dailylist ; Oniro guide https://docs.oniroproject.org/application-development/environment-setup-guide/full-public-sdk/ . DevEco Studio 6.0.0 Release, `runtimeOS: "OpenHarmony"`.
- Oniro emulator: https://github.com/eclipse-oniro4openharmony/device_board_oniro/releases (v6.1, ~1.45 GB, QEMU x86_64). `x86_general/kernel/run.sh`; on Apple Silicon uses TCG (slow). Homebrew qemu has no SDL → use `./run.sh --headless` (VNC :5900) or patch `-display cocoa`. Network = user NAT (internet OK). hdc: `hdc tconn 127.0.0.1:55555`; DevEco Tools → IP Connection. Docs: https://docs.oniroproject.org/device-development/developer-boards/emulator/
- Preinstalled: launcher, `com.ohos.settings`, `com.ohos.mms`, `com.ohos.contacts` (+dialer), callui, note, camera, photos, clock, kikaInput. NO browser, NO calendar app.
- Accessibility: declare `extensionAbilities` type `accessibility`, metadata `ohos.accessibleability` → profile `{"accessibilityCapabilities":["retrieve","gesture"]}`. Enable from code: `config.enableAbility('bundle/Ability', caps)` (systemapi, `WRITE_ACCESSIBILITY_CONFIG`). `hdc shell accessibility enable` removed in 6.1; Settings no longer lists services. New sys APIs: `getRootInActiveWindow`, `executeAction(CLICK/SET_TEXT/BACK/HOME)`, `getChildren`, `findElementByContent`. Deprecated `getWindowRootElement`/`performAction`/`injectGestureSync` still bound in 6.1 source. setText param key must be `setText`.
- Template repo: https://github.com/huangwei021230/GUIAgent (GUIAgent-OH, system_core OpenHarmony agent; uses injectTouchEvent/injectKeyEvent + CAPTURE_SCREEN).
- SMS send on emulator → `SEND_SMS_FAILURE_SERVICE_UNAVAILABLE` (no modem). Demo = agent drives Messages UI; message ends "not sent" — explain in video.
- LLM in ArkTS: `@kit.NetworkKit` `http.createHttp().request()` (new object per request, `destroy()` after), `ohos.permission.INTERNET`. Anthropic: POST /v1/messages, headers `x-api-key`, `anthropic-version: 2023-06-01`. No Anthropic ohpm SDK → hand-roll. ArkTS strictness: no any/unknown, typed interfaces + `JSON.parse(...) as T`, tool input as `Record<string, Object>`, tools schema as prebuilt JSON string.

## Implementation plan (agreed, pending Q23 + confirmation)
Architecture: one `.hap` (system_core). EntryAbility/Index page = API key, model dropdown, prompt, step log; first run calls `enableAbility`. Agent loop lives inside `AgentA11y` (AccessibilityExtensionAbility) so it survives when target app is foreground; UI↔extension via `commonEvent` ("agent.run" / "agent.log"). Tools: `list_apps` (getAllBundleInfo), `launch_app(bundle)`, `read_screen` (tree → ≤150 visible/clickable elements), `click(i)` (performAction/executeAction, fallback injectTouchEvent at bbox center), `type_text(i,text)`, `press(back|home)`, `done(summary)`. Loop max 25 steps; bad JSON/unknown tool → `is_error`.
ACLs: ACCESSIBILITY_EXTENSION_ABILITY, WRITE_ACCESSIBILITY_CONFIG, GET_INSTALLED_BUNDLE_LIST, GET_BUNDLE_INFO_PRIVILEGED, START_ABILITIES_FROM_BACKGROUND, INJECT_INPUT_EVENT (+ INTERNET).

Phases (each has a gate):
- P0 env 2.5–4h: qemu + Oniro headless + VNC, hdc tconn, DevEco + full SDK API 20, hello world installs. If boot >45 min/unusable → KVM cloud VM.
- P1 system-sign spike 1h: `scripts/sign.sh` committed; app shows getAllBundleInfo count.
- P2 a11y spike 2h: enableAbility; read Settings tree, click item, setText in Notes. Decide new vs deprecated APIs and click fallback.
- P3 agent loop 3h: Anthropic client, tree serializer, dispatcher, commonEvent bridge. Gate: "open settings → Wi-Fi".
- P4 demo 2h: add "Babcia" contact; SMS flow via Messages UI 3× in a row; tune system prompt.
- P5 2h: hypium tests, README (exact versions), ARCHITECTURE.md, AI_WORKFLOW.md (model, data flow — screen tree sent to Anthropic, privacy, limits, prompts, dev tools used), `.hap` in GitHub Release, demo video.
Total ~13–15h.

Risks: TCG slowness on M5; no one verified end-to-end on 6.1; extension process isolation (hence commonEvent); performAction may not click some components.

## Suggested skills for next agent
- `grilling` — only if new decisions appear (Q23 still open).
- `superpowers:writing-plans` — turn the plan above into a step-by-step plan file in the new repo.
- `superpowers:executing-plans` / `superpowers:subagent-driven-development` — execute phases.
- `claude-api` — before writing the Anthropic client (model ids, tool-use shapes).
- `superpowers:test-driven-development` / `tdd` — for parser/dispatcher/serializer tests.
- `superpowers:systematic-debugging` — emulator/signing/a11y failures.
- `superpowers:verification-before-completion` — before claiming gates passed.
- `research` — any further fact-finding (note: WebSearch was flaky; developer.huawei.com is JS-rendered — read via its document JSON API or the OpenHarmony docs GitHub mirror).
