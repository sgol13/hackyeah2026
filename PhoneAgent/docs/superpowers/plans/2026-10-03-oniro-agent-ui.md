# Oniro Agent UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebrand Phone Agent as **Oniro Agent** with an "OA" agent logo, a redesigned main screen plus a separate Settings page, and an assistant overlay (floating orb → bottom sheet → status pill) that can also be opened by holding the Home button if a SystemUI patch works.

**Architecture:** The agent loop stays in the accessibility extension (`AgentA11y`), untouched apart from friendlier step text and a `origin` flag. The UI-side service logic (enable/ping/run/stop, status merging) moves out of `Index.ets` into `common/AgentClient.ets` + `common/StatusTracker.ets` so two front ends can share it: the app (`pages/Index`, `pages/Settings`) and a new `OverlayService` (`ServiceExtensionAbility`) that owns `TYPE_FLOAT` windows (`pages/OverlayOrb|OverlaySheet|OverlayPill|OverlayGlow`). Long-press Home is a patched `com.ohos.systemui` that starts `OverlayService` with `invoke: true`.

**Tech Stack:** ArkTS / ArkUI (OpenHarmony API 20, full SDK 6.0.0.48), `@kit.ArkUI` `window`/`display`, `@kit.AbilityKit` `ServiceExtensionAbility`, hypium tests run on the Oniro 6.1 emulator via `scripts/test.ps1`. No new runtime libraries. One bundled OFL font.

**Spec:** No separate spec file. The decisions below came out of the grilling session on 2026-10-03 and are the spec.

### Decisions (spec)

| # | Decision |
|---|---|
| D1 | Name shown everywhere (launcher, title, a11y service, system prompt, docs) is **Oniro Agent**. Bundle ID stays `com.hackyeah.phoneagent`; folder `PhoneAgent/`, script names and `phoneagent-signed.hap` stay. |
| D2 | Logo = **O ring + A spark**: a thick gradient ring (teal → violet → coral) with a gap at the upper right, and an upward arrowhead spark (the "A", notch = crossbar) cutting into the gap. The ring rotates while the agent works. |
| D3 | Visual mood: **follows system light/dark**; calm neutral surfaces; the orb gradient is the only strong color (logo, Run button, glow, active step). Large friendly type. |
| D4 | **All configuration in Settings** (provider, API key, model/custom ID, floating-button switch, agent-service status + Reconnect). Main screen: composer, suggestions, timeline, a read-only model chip that opens Settings. No key → empty state with one "Open Settings" button. |
| D5 | Timeline: **steps first**, plain sentences ("Open Messages", `Tap "Send"`); the model's thought is one muted line under its step, expandable; result as a highlighted row; errors in red. |
| D6 | Invocation: **floating orb** (edge-docked, draggable, semi-transparent when idle, hidden while our app is in front, on by default, switch in Settings) **+ a SystemUI long-press-Home spike, max 2 h**. |
| D7 | Invoked UI: **bottom sheet** (float window) takes the task → on Run it collapses to a **non-focusable pill** at the top centre (spinning mark + current step), screen edges glow; tap pill → log + Stop + Open app. Target app stays the active window. |
| D8 | Build/test on this machine: set up WSL Ubuntu-24.04 + Oniro emulator + full SDK first. |
| D9 | Order: 1) rename + logo → 2) Settings + main redesign → 3) orb/sheet/pill → 4) SystemUI spike. Each stage ends in a working state. |
| D10 | Git: **no commits until the user says so.** Checkpoint steps below say what would be committed; skip `git commit` unless the user has OK'd it (suggested branch `ui/oniro-agent`). |
| D11 | Settings lets you pick **model and reasoning effort**. Effort offers only the levels the chosen model's API accepts, plus "Default" (= today's behaviour). Models without an effort knob (Claude Haiku 4.5, Grok 4, custom model IDs) hide the effort row. The main-screen chip shows both, e.g. "Claude Opus 5.5, high effort". |

Effort per model (checked 2026-10-03; re-check the OpenAI/xAI/Gemini docs with Context7 before Task 6b Step 3, provider APIs drift):

| Provider / model | API field | Levels offered |
|---|---|---|
| Claude Opus 5.5, Claude Sonnet 5.5 | `output_config.effort` | low, medium, high, xhigh, max (Default = `medium`, as today) |
| Claude Haiku 4.5 | none (effort is rejected) | – |
| OpenAI GPT-5, GPT-5 mini | `reasoning_effort` | minimal, low, medium, high |
| xAI Grok 3 mini | `reasoning_effort` | low, high |
| xAI Grok 4 | none (rejects `reasoning_effort`) | – |
| Gemini 2.5 Pro | `generationConfig.thinkingConfig.thinkingBudget` | low 1024, medium 8192, high 24576 (Pro cannot turn thinking off) |
| Gemini 2.5 Flash | same | none 0, low 1024, medium 8192, high 24576 |

## Global Constraints

- Display name: exactly `Oniro Agent`. Bundle name stays `com.hackyeah.phoneagent` (`AppScope/app.json5`), `OWN_BUNDLE`/event names in `common/Bridge.ets` unchanged.
- Target: OpenHarmony API 20 full SDK, `system_core` signing via `scripts/sign.ps1`; runs on Oniro emulator v6.1 (`127.0.0.1:55555`).
- ArkTS strict mode: no `any`/`unknown`, typed interfaces, `JSON.parse(...) as T`, no untyped object literals.
- UI copy: English, sentence case, no ALL-CAPS labels, no `→` in buttons, no `A · B` meta strings. Inline strings in `.ets` like the existing code.
- Colors only through `$r('app.color.*')` tokens defined in `resources/base/element/color.json` and overridden in `resources/dark/element/color.json`.
- Orb gradient (same in both themes): teal `#12B5A6` → violet `#6E56F8` → coral `#FF6B5A`.
- Display font: Bricolage Grotesque SemiBold (OFL), family name `Bricolage`, used only for the wordmark, page titles and the greeting. Everything else uses the system font.
- Tests: hypium in `entry/src/ohosTest/ets/test/`, registered in `List.test.ets`, run with `.\scripts\test.ps1` (baseline `Pass: 51`).
- Keep existing behaviour: per-provider API keys, custom model IDs, `isValidModelId`, debug `task`/`autorun` launch params, service restart logic.

## Review Focus

1. **Agent reads or taps our overlay instead of the target app.** With the pill/glow/orb on screen, `getRootInActiveWindow()` must still return the target app; a run's log must show `App: com.ohos.mms`, never our bundle. Pinned by the manual check in Task 10 Step 9 plus non-focusable windows.
2. **Switching provider in Settings loses or mixes API keys.** Leaving a provider saves its key; arriving loads its own key; going back to Index uses the saved values. Pinned by the manual check in Task 7 Step 6.
3. **Very long step/thought text (up to 600 chars) in the one-line pill or the timeline.** Pill: one line with ellipsis; timeline thought: 2 lines until tapped. Pinned by `Timeline.test.ets` "currentStepText" and the visual check in Task 10.
4. **Running from the sheet while the agent service is not listening.** The sheet must show the error inline and stay open, not collapse into a pill stuck on "Starting". Pinned by `AgentClient.run` returning a message and Task 10 Step 9 (b).
5. **Orb dropped partly off-screen or under the status/navigation bar.** It must snap fully on-screen to the nearer side edge. Pinned by `OrbGeometry.test.ets`.

---

## File map

| File | Status | Responsibility |
|---|---|---|
| `PhoneAgent/scripts/screenshot.ps1` | create | Grab a device screenshot to `build/shots/<name>.jpeg` for visual review |
| `PhoneAgent/design/oa-mark.svg`, `oa-icon-foreground.svg`, `oa-icon-background.svg` | create | Logo masters |
| `entry/src/main/resources/base/media/oa_ring.svg`, `oa_spark.svg`, `ic_*.svg` | create | In-app logo parts + icons |
| `AppScope/resources/base/media/foreground.png`, `background.png`, entry `foreground.png`/`background.png`/`startIcon.png` | replace | Launcher + splash icon |
| `entry/src/main/resources/rawfile/fonts/BricolageGrotesque-SemiBold.ttf`, `OFL.txt` | create | Display font |
| `entry/src/main/resources/{base,dark}/element/color.json` | modify | Theme tokens |
| `entry/src/main/ets/common/Fonts.ets` | create | `DISPLAY_FONT`, `registerFonts(ui)` |
| `entry/src/main/ets/components/OaMark.ets` | create | Logo component, optional spinning ring |
| `entry/src/main/ets/agent/StepText.ets` | create | Plain-sentence step text (pure) |
| `entry/src/main/ets/agent/AgentLoop.ets` | modify | `Executor.appLabel`, use `stepText` |
| `entry/src/main/ets/a11y/DeviceExecutor.ets` | modify | `appLabel`, preload app list |
| `entry/src/main/ets/common/StatusTracker.ets` | create | Merge STATUS payloads (pure, from Index) |
| `entry/src/main/ets/common/Timeline.ets` | create | Log entries → steps (pure) |
| `entry/src/main/ets/common/RunCheck.ets` | create | Pre-run validation messages (pure) |
| `entry/src/main/ets/common/AgentClient.ets` | create | enable/restart/ping/run/stop service (from Index) |
| `entry/src/main/ets/common/Settings.ets` | modify | `effort` setting, `showOrb` flag |
| `entry/src/main/ets/common/Bridge.ets` | modify | `origin` and `effort` on RunRequest, `EVT_UI_VISIBLE`, constants |
| `entry/src/main/ets/agent/Providers.ets` | modify | `modelLabel()`, `modelSummary()`, per-model effort levels, `createLlm(..., effort)` |
| `entry/src/main/ets/agent/OpenAiCompat.ets`, `agent/Gemini.ets` | modify | Send `reasoning_effort` / `thinkingBudget` |
| `entry/src/main/ets/components/Composer.ets`, `StepList.ets` | create | Shared UI parts (app + overlay) |
| `entry/src/main/ets/pages/Index.ets` | rewrite | Main screen |
| `entry/src/main/ets/pages/Settings.ets` | create | Settings page |
| `entry/src/main/ets/overlay/OrbGeometry.ets` | create | Orb snapping (pure) |
| `entry/src/main/ets/overlay/OverlayController.ets` | create | Float windows + state |
| `entry/src/main/ets/overlay/OverlayService.ets` | create | ServiceExtensionAbility host |
| `entry/src/main/ets/pages/OverlayOrb.ets`, `OverlaySheet.ets`, `OverlayPill.ets`, `OverlayGlow.ets` | create | Overlay window pages |
| `entry/src/main/ets/entryability/EntryAbility.ets` | modify | Fonts, start overlay, publish UI visibility |
| `entry/src/main/ets/a11y/AgentA11y.ets` | modify | Rename text, skip reopening UI for overlay runs |
| `entry/src/main/module.json5`, `resources/base/profile/main_pages.json`, `signing/profile-template.json` | modify | Service, permission, pages, ACL |
| `README.md`, `PhoneAgent/README.md`, `PhoneAgent/ARCHITECTURE.md`, `PhoneAgent/AI_WORKFLOW.md` | modify | Name + new UI + spike result |

All `entry/...` paths below are relative to `PhoneAgent/`.

---

## Stage 0: Environment

### Task 0: Emulator, full SDK and screenshot script on this machine

**Files:**
- Create: `PhoneAgent/scripts/screenshot.ps1`

**Interfaces:**
- Produces: `.\scripts\screenshot.ps1 -Name <name>` → `PhoneAgent/build/shots/<name>.jpeg`. Used by every visual check below.

- [ ] **Step 1: User does the admin-only part** (needs an elevated PowerShell + reboot; ask the user to run these, suggest the `!` prefix for non-admin ones)

```powershell
wsl --install -d Ubuntu-24.04      # admin, then reboot, create the Linux user
```
Then follow `PhoneAgent/README.md` → Setup 1.2–1.5 (systemd in `/etc/wsl.conf`, `qemu-system-x86 qemu-utils unzip`, `usermod -aG kvm`, download `oniro_emulator.zip` into `~/oniro/images`).

- [ ] **Step 2: Full SDK** – download `ohos-sdk-full 6.0.0.48` (link in `PhoneAgent/README.md` Setup 2), unpack `ohos-sdk/windows/*` into `%LOCALAPPDATA%\OpenHarmony\Sdk\20\`.

Run: `Test-Path "$env:LOCALAPPDATA\OpenHarmony\Sdk\20\ets\api\@ohos.multimodalInput.inputConsumer-sys.d.ts"` (or any `*-sys.d.ts`)
Expected: `True`

- [ ] **Step 3: Boot and baseline**

Run (in `PhoneAgent/`): `.\scripts\start-emulator.ps1` then `.\scripts\test.ps1`
Expected: `ALL TESTS PASSED: Tests run: 51, Failure: 0, Error: 0, Pass: 51`

- [ ] **Step 4: Write the screenshot script**

```powershell
<#
.SYNOPSIS
  Saves a screenshot of the emulator/device to build\shots\<Name>.jpeg.
.EXAMPLE
  .\scripts\screenshot.ps1 -Name main-light
#>
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$DevEco = 'C:\Program Files\Huawei\DevEco Studio',
    [string]$Target = '127.0.0.1:55555'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$hdc = Join-Path $DevEco 'sdk\default\openharmony\toolchains\hdc.exe'
$dir = Join-Path $root 'build\shots'
New-Item -ItemType Directory -Force $dir | Out-Null
$remote = '/data/local/tmp/oa-shot.jpeg'
& $hdc -t $Target shell "snapshot_display -f $remote" | Out-Null
& $hdc -t $Target file recv $remote (Join-Path $dir "$Name.jpeg") | Out-Null
Write-Host (Join-Path $dir "$Name.jpeg")
```

- [ ] **Step 5: Check it and record the navigation facts for Stage 4**

Run: `.\scripts\screenshot.ps1 -Name baseline` and open the file with the Read tool.
Expected: the current Phone Agent screen or the launcher.

Run: `& $hdc -t 127.0.0.1:55555 shell "bm dump -a"` and look for `com.ohos.systemui` and `com.ohos.sceneboard`.
Write down which one exists, and whether the screenshot shows a 3-button bar (◁ ○ □) or a gesture bar. Stage 4 depends on this.

---

## Stage 1: Rename + logo

### Task 1: Rename to Oniro Agent

**Files:**
- Modify: `AppScope/resources/base/element/string.json`
- Modify: `entry/src/main/resources/base/element/string.json`
- Modify: `entry/src/main/ets/a11y/AgentA11y.ets:2,172`
- Modify: `entry/src/main/ets/agent/Prompt.ets:2`
- Modify: `entry/src/main/ets/pages/Index.ets:292` (title only; Index is rewritten in Task 8)
- Modify: `README.md`, `PhoneAgent/README.md`, `PhoneAgent/ARCHITECTURE.md`, `PhoneAgent/AI_WORKFLOW.md` (prose mentions only)

**Interfaces:** none.

- [ ] **Step 1: App label**

`AppScope/resources/base/element/string.json`:
```json
{
  "string": [
    {
      "name": "app_name",
      "value": "Oniro Agent"
    }
  ]
}
```

- [ ] **Step 2: Module strings** – in `entry/src/main/resources/base/element/string.json` set:
  - `module_desc` → `Oniro Agent: drives apps on the phone for you`
  - `EntryAbility_desc` → `Oniro Agent`
  - `EntryAbility_label` → `Oniro Agent`
  - `a11y_label` → `Oniro Agent service`
  - `a11y_desc` → `Reads the screen and taps/types on your behalf when you give Oniro Agent a task`

- [ ] **Step 3: Code mentions**
  - `AgentA11y.ets:2` comment → ` * Oniro Agent service: an AccessibilityExtensionAbility that hosts the agent loop.`
  - `AgentA11y.ets:172` → ``this.addLog(LOG_ERROR, `No ${provider.label} API key set. Add it in Oniro Agent Settings.`);``
  - `Prompt.ets:2` → `You are Oniro Agent, an assistant built into an OpenHarmony phone. …` (only the name changes)
  - `Index.ets:292` → `Text('Oniro Agent')`

- [ ] **Step 4: Docs** – replace the product name "Phone Agent" with "Oniro Agent" in prose of the four docs. Keep the paths `PhoneAgent/`, `phoneagent-signed.hap`, `com.hackyeah.phoneagent`, script names. Root `README.md` title becomes `# Oniro Agent (HackYeah 2026, Huawei challenge)`.

Run: `rg -n "Phone Agent" PhoneAgent README.md --glob '!docs/**'`
Expected: no matches (except `handoff-openharmony-phone-agent.md`, which is a historical note; leave it).

- [ ] **Step 5: Build, install, check**

Run: `.\scripts\build.ps1` then `.\scripts\screenshot.ps1 -Name rename`
Expected: title reads "Oniro Agent". Press Home (`& $hdc shell "uinput -K -d 1 -u 1"`) and screenshot `launcher`: the icon label reads "Oniro Agent".

- [ ] **Step 6: Checkpoint** – (commit only if the user OK'd commits) `git add -A PhoneAgent README.md && git commit -m "Rename the app to Oniro Agent"`

### Task 2: OA mark, launcher icon, `OaMark` component

**Files:**
- Create: `PhoneAgent/design/oa-mark.svg`, `PhoneAgent/design/oa-icon-foreground.svg`, `PhoneAgent/design/oa-icon-background.svg`
- Create: `entry/src/main/resources/base/media/oa_ring.svg`, `entry/src/main/resources/base/media/oa_spark.svg`
- Replace: `AppScope/resources/base/media/foreground.png`, `background.png`; `entry/src/main/resources/base/media/foreground.png`, `background.png`, `startIcon.png`
- Create: `entry/src/main/ets/components/OaMark.ets`

**Interfaces:**
- Produces: `OaMark({ size: number, spinning: boolean })` ArkUI component (`components/OaMark.ets`).

- [ ] **Step 1: Master SVG** – `PhoneAgent/design/oa-mark.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120">
  <defs>
    <linearGradient id="oa" x1="0" y1="1" x2="1" y2="0">
      <stop offset="0" stop-color="#12B5A6"/>
      <stop offset="0.55" stop-color="#6E56F8"/>
      <stop offset="1" stop-color="#FF6B5A"/>
    </linearGradient>
  </defs>
  <!-- O: ring, gap at the upper right where the spark enters (circumference ~201) -->
  <circle cx="54" cy="66" r="32" fill="none" stroke="url(#oa)" stroke-width="15"
          stroke-linecap="round" stroke-dasharray="160 41" transform="rotate(-20 54 66)"/>
  <!-- A: arrowhead spark; the notch stands in for the crossbar -->
  <path d="M88 10 L106 56 L88 45 L70 56 Z" fill="url(#oa)"/>
</svg>
```

- [ ] **Step 2: Render and look**

Run (from `PhoneAgent/`): `& "C:\Program Files\Huawei\DevEco Studio\tools\node\npx.cmd" -y @resvg/resvg-js-cli --fit-width 512 design/oa-mark.svg build/shots/oa-mark.png`
Then Read `build/shots/oa-mark.png`.
Expected: it reads as "O" + "A": the ring's gap sits at about 1–2 o'clock and the spark's base overlaps the gap without touching the ring ends. If the gap is off, change only `rotate(-20 …)` and `stroke-dasharray`; if the spark crowds the ring, move the path's x values. Re-render until it reads cleanly at 48 px too (`--fit-width 48`).

- [ ] **Step 3: Split for the app** – copy the ring into `entry/src/main/resources/base/media/oa_ring.svg` (same `<defs>` + `<circle>`, no path) and the spark into `oa_spark.svg` (same `<defs>` + `<path>`, no circle). Both keep `viewBox="0 0 120 120"` so they stack exactly.

- [ ] **Step 4: Launcher icon layers**

`PhoneAgent/design/oa-icon-background.svg`:
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <radialGradient id="bg" cx="0.35" cy="0.3" r="0.9">
      <stop offset="0" stop-color="#232C3D"/>
      <stop offset="1" stop-color="#10151F"/>
    </radialGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
</svg>
```
`PhoneAgent/design/oa-icon-foreground.svg` = the mark centred in the safe zone (mark spans ~56% of the canvas):
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="-48 -48 216 216">
  <defs>
    <linearGradient id="oa" x1="0" y1="1" x2="1" y2="0">
      <stop offset="0" stop-color="#12B5A6"/>
      <stop offset="0.55" stop-color="#6E56F8"/>
      <stop offset="1" stop-color="#FF6B5A"/>
    </linearGradient>
  </defs>
  <circle cx="54" cy="66" r="32" fill="none" stroke="url(#oa)" stroke-width="15"
          stroke-linecap="round" stroke-dasharray="160 41" transform="rotate(-20 54 66)"/>
  <path d="M88 10 L106 56 L88 45 L70 56 Z" fill="url(#oa)"/>
</svg>
```
(Copy any tweak made in Step 2 into this file too.)

- [ ] **Step 5: Render PNGs at the existing sizes**

Run: `python -c "from PIL import Image;import sys;[print(p, Image.open(p).size) for p in sys.argv[1:]]" AppScope/resources/base/media/foreground.png AppScope/resources/base/media/background.png entry/src/main/resources/base/media/foreground.png entry/src/main/resources/base/media/background.png entry/src/main/resources/base/media/startIcon.png`
Then for each file render the matching SVG at that width with `npx -y @resvg/resvg-js-cli --fit-width <W> <svg> <png>` (foreground.png ← icon-foreground, background.png ← icon-background, startIcon.png ← icon-foreground).

- [ ] **Step 6: `OaMark` component** – `entry/src/main/ets/components/OaMark.ets`:

```ts
/** The OA mark: gradient ring ("O") + arrowhead spark ("A"). The ring turns while the agent works. */
@Component
export struct OaMark {
  @Prop size: number = 40;
  @Prop @Watch('onSpinning') spinning: boolean = false;
  @State private angle: number = 0;

  aboutToAppear(): void {
    this.onSpinning();
  }

  onSpinning(): void {
    if (this.spinning) {
      this.getUIContext().animateTo({ duration: 1400, curve: Curve.Linear, iterations: -1 }, () => {
        this.angle = 360;
      });
    } else {
      this.getUIContext().animateTo({ duration: 0 }, () => {
        this.angle = 0;
      });
    }
  }

  build() {
    Stack() {
      Image($r('app.media.oa_ring'))
        .width(this.size)
        .height(this.size)
        .rotate({ angle: this.angle, centerX: '45%', centerY: '55%' })
      Image($r('app.media.oa_spark'))
        .width(this.size)
        .height(this.size)
    }
    .width(this.size)
    .height(this.size)
    .accessibilityText('Oniro Agent')
  }
}
```
(`centerX/centerY` = ring centre 54/120, 66/120.)

- [ ] **Step 7: Use it in the current header** – in `Index.ets` `build()`, replace the `Text('Oniro Agent')` line with:
```ts
      Row({ space: 10 }) {
        OaMark({ size: 32, spinning: this.running })
        Text('Oniro Agent')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
```
and add `import { OaMark } from '../components/OaMark';`.

- [ ] **Step 8: Build and look**

Run: `.\scripts\build.ps1`, `.\scripts\screenshot.ps1 -Name mark-app`, go Home, `.\scripts\screenshot.ps1 -Name mark-launcher`. Read both.
Expected: mark renders with the gradient (if ArkUI drops the SVG gradient and shows solid black, change `fill`/`stroke` to `#6E56F8` in the two media SVGs and note it in `ARCHITECTURE.md`); launcher icon shows the mark on the dark tile. Start a scripted run (`aa start -b com.hackyeah.phoneagent -a EntryAbility --ps task "script:..." --pb autorun true` with any existing script from `ScriptedLlm.ets`) and confirm the ring turns while running.

- [ ] **Step 9: Checkpoint** – (only with user OK) `git add PhoneAgent && git commit -m "Add the OA mark, launcher icon and OaMark component"`

---

## Stage 2: Settings + main screen

### Task 3: Theme tokens and display font

**Files:**
- Modify: `entry/src/main/resources/base/element/color.json`
- Modify: `entry/src/main/resources/dark/element/color.json`
- Create: `entry/src/main/resources/rawfile/fonts/BricolageGrotesque-SemiBold.ttf`, `entry/src/main/resources/rawfile/fonts/OFL.txt`
- Create: `entry/src/main/ets/common/Fonts.ets`
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets` (`onWindowStageCreate`)

**Interfaces:**
- Produces: color tokens `bg, surface, surface_raised, ink, ink_muted, line, danger, orb_teal, orb_violet, orb_coral, on_orb, start_window_background`; `DISPLAY_FONT: string`, `registerFonts(ui: UIContext): void` in `common/Fonts.ets`.

- [ ] **Step 1: Light tokens** – `resources/base/element/color.json`:
```json
{
  "color": [
    { "name": "start_window_background", "value": "#F2F4F7" },
    { "name": "bg", "value": "#F2F4F7" },
    { "name": "surface", "value": "#FFFFFF" },
    { "name": "surface_raised", "value": "#FFFFFF" },
    { "name": "ink", "value": "#141B26" },
    { "name": "ink_muted", "value": "#5E6878" },
    { "name": "line", "value": "#DCE1E8" },
    { "name": "danger", "value": "#C9372C" },
    { "name": "orb_teal", "value": "#12B5A6" },
    { "name": "orb_violet", "value": "#6E56F8" },
    { "name": "orb_coral", "value": "#FF6B5A" },
    { "name": "on_orb", "value": "#FFFFFF" }
  ]
}
```

- [ ] **Step 2: Dark tokens** – `resources/dark/element/color.json` (orb colors are inherited from base):
```json
{
  "color": [
    { "name": "start_window_background", "value": "#0F141C" },
    { "name": "bg", "value": "#0F141C" },
    { "name": "surface", "value": "#192029" },
    { "name": "surface_raised", "value": "#222A35" },
    { "name": "ink", "value": "#E9EDF3" },
    { "name": "ink_muted", "value": "#96A0AF" },
    { "name": "line", "value": "#2B3440" },
    { "name": "danger", "value": "#FF8A7F" }
  ]
}
```

- [ ] **Step 3: Font file** (static instance of the variable font, Polish diacritics included)

```powershell
New-Item -ItemType Directory -Force entry\src\main\resources\rawfile\fonts | Out-Null
curl.exe -L -o build\Bricolage-var.ttf "https://github.com/google/fonts/raw/main/ofl/bricolagegrotesque/BricolageGrotesque%5Bopsz%2Cwdth%2Cwght%5D.ttf"
curl.exe -L -o entry\src\main\resources\rawfile\fonts\OFL.txt "https://github.com/google/fonts/raw/main/ofl/bricolagegrotesque/OFL.txt"
python -m pip install --quiet fonttools
python -m fontTools.varLib.instancer build\Bricolage-var.ttf wght=600 wdth=100 opsz=48 -o entry\src\main\resources\rawfile\fonts\BricolageGrotesque-SemiBold.ttf
python -c "from fontTools.ttLib import TTFont;c=TTFont(r'entry\src\main\resources\rawfile\fonts\BricolageGrotesque-SemiBold.ttf').getBestCmap();print(all(ord(x) in c for x in 'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ'))"
```
Expected last line: `True`

- [ ] **Step 4: `common/Fonts.ets`**
```ts
/** The one bundled typeface: Bricolage Grotesque SemiBold, for the wordmark, page titles and the greeting. */
export const DISPLAY_FONT = 'Bricolage';

/** Registers the bundled fonts with one window's UI. Call once per window (app and every overlay window). */
export function registerFonts(ui: UIContext): void {
  ui.getFont().registerFont({ familyName: DISPLAY_FONT, familySrc: $rawfile('fonts/BricolageGrotesque-SemiBold.ttf') });
}
```

- [ ] **Step 5: Register in the app window** – `EntryAbility.onWindowStageCreate`, inside the `loadContent` callback after the error check:
```ts
      registerFonts(windowStage.getMainWindowSync().getUIContext());
```
with `import { registerFonts } from '../common/Fonts';`.

- [ ] **Step 6: Build** – `.\scripts\build.ps1`. Expected: build succeeds (tokens are used from Task 8 on).

- [ ] **Step 7: Checkpoint** – (only with user OK) `git commit -am "Add theme tokens and the display font"` (plus `git add` the new files).

### Task 4: Plain-sentence step text

**Files:**
- Create: `entry/src/main/ets/agent/StepText.ets`
- Modify: `entry/src/main/ets/agent/AgentLoop.ets:25-39` (Executor), `:225-245` (describe)
- Modify: `entry/src/main/ets/a11y/DeviceExecutor.ets` (constructor, new `appLabel`)
- Test: `entry/src/ohosTest/ets/test/StepText.test.ets` (create), `entry/src/ohosTest/ets/test/AgentLoop.test.ets` (FakeExecutor, RecordingListener, one new test), `List.test.ets`

**Interfaces:**
- Consumes: `ToolAction`, `TOOL_*` from `agent/Tools.ets`; line format of `describeNode` (`[6] Button "Send" desc="x" hint="y" (click)`).
- Produces: `targetFromLine(line: string): string`, `stepText(a: ToolAction, appLabel: string, elementLine: string): string`; `Executor.appLabel(bundleName: string): string` ('' if unknown).

- [ ] **Step 1: Failing tests** – `StepText.test.ets`:
```ts
import { describe, expect, it } from '@ohos/hypium';
import { stepText, targetFromLine } from '../../../main/ets/agent/StepText';
import { ToolAction } from '../../../main/ets/agent/Tools';

function action(name: string): ToolAction {
  return { name: name, index: -1, text: '', bundleName: '', scrollDown: true, key: '', success: true };
}

export default function stepTextTest() {
  describe('StepText', () => {
    it('targetFromLine prefers text, then desc, then hint, then the type', 0, () => {
      expect(targetFromLine('[6] TextArea "Hello" (click,edit)')).assertEqual('"Hello"');
      expect(targetFromLine('[2] Button desc="Send" (click)')).assertEqual('"Send"');
      expect(targetFromLine('[3] TextInput hint="Message" (click,edit)')).assertEqual('"Message"');
      expect(targetFromLine('[4] Image (click)')).assertEqual('image');
      expect(targetFromLine('')).assertEqual('');
    });

    it('launch_app uses the app label, falling back to the bundle name', 0, () => {
      const a = action('launch_app');
      a.bundleName = 'com.ohos.mms';
      expect(stepText(a, 'Messages', '')).assertEqual('Open Messages');
      expect(stepText(a, '', '')).assertEqual('Open com.ohos.mms');
    });

    it('click, type_text and scroll name their target', 0, () => {
      const click = action('click');
      click.index = 2;
      expect(stepText(click, '', '[2] Button "Send" (click)')).assertEqual('Tap "Send"');
      expect(stepText(click, '', '')).assertEqual('Tap item 2');
      const type = action('type_text');
      type.index = 3;
      type.text = 'Będę';
      expect(stepText(type, '', '[3] TextInput hint="Message" (edit)')).assertEqual('Type "Będę" into "Message"');
      const scroll = action('scroll');
      scroll.index = 1;
      scroll.scrollDown = false;
      expect(stepText(scroll, '', '[1] List (scroll)')).assertEqual('Scroll up');
    });

    it('read_screen, list_apps and press_key read as plain verbs', 0, () => {
      expect(stepText(action('read_screen'), '', '')).assertEqual('Look at the screen');
      expect(stepText(action('list_apps'), '', '')).assertEqual('Check the installed apps');
      const key = action('press_key');
      key.key = 'home';
      expect(stepText(key, '', '')).assertEqual('Press Home');
    });
  });
}
```
Register in `List.test.ets` (`import stepTextTest from './StepText.test';` and call `stepTextTest();`).

- [ ] **Step 2: Run, expect failure** – `.\scripts\test.ps1` → build error "Cannot find module '../../../main/ets/agent/StepText'".

- [ ] **Step 3: Implement** – `agent/StepText.ets`:
```ts
/**
 * Plain-sentence text for the steps the user sees ("Open Messages", 'Tap "Send"').
 * The model-facing tool results keep their own wording; this is only for the log.
 */
import {
  TOOL_CLICK,
  TOOL_LAUNCH_APP,
  TOOL_LIST_APPS,
  TOOL_PRESS_KEY,
  TOOL_READ_SCREEN,
  TOOL_SCROLL,
  TOOL_TYPE_TEXT,
  ToolAction
} from './Tools';

const LINE = /^\[\d+\] (\S+)(?: "(.*?)")?(?: desc="(.*?)")?(?: hint="(.*?)")?(?: \(|$| @)/;

/** '"Send"' from a screen line's text, desc or hint; the lower-cased type otherwise; '' for an empty line. */
export function targetFromLine(line: string): string {
  const m = LINE.exec(line);
  if (m === null) {
    return '';
  }
  for (const part of [m[2], m[3], m[4]]) {
    if (part !== undefined && part.length > 0) {
      return `"${part}"`;
    }
  }
  return m[1].toLowerCase();
}

function capitalize(s: string): string {
  return s.length > 0 ? s.charAt(0).toUpperCase() + s.substring(1) : s;
}

export function stepText(a: ToolAction, appLabel: string, elementLine: string): string {
  const found = targetFromLine(elementLine);
  const target = found.length > 0 ? found : `item ${a.index}`;
  switch (a.name) {
    case TOOL_LIST_APPS:
      return 'Check the installed apps';
    case TOOL_LAUNCH_APP:
      return `Open ${appLabel.length > 0 ? appLabel : a.bundleName}`;
    case TOOL_READ_SCREEN:
      return 'Look at the screen';
    case TOOL_CLICK:
      return `Tap ${target}`;
    case TOOL_TYPE_TEXT:
      return `Type "${a.text}" into ${target}`;
    case TOOL_SCROLL:
      return `Scroll ${a.scrollDown ? 'down' : 'up'}`;
    case TOOL_PRESS_KEY:
      return `Press ${capitalize(a.key)}`;
    default:
      return a.name;
  }
}
```
Check the `@` alternative against a real `describeNode` line tail (`ScreenText.ets:70-110`); if lines end with ` @x,y` after the flags, the `(?: \(|$| @)` already covers it.

- [ ] **Step 4: Executor gets `appLabel`** – in `AgentLoop.ets` `Executor`, after `describeElement`:
```ts
  /** Launcher label of an installed app ('' if unknown). */
  appLabel(bundleName: string): string;
```
Replace the body of `describe(a)` with:
```ts
  private describe(a: ToolAction): string {
    const line = a.index >= 0 ? this.exec.describeElement(a.index) : '';
    const app = a.name === TOOL_LAUNCH_APP ? this.exec.appLabel(a.bundleName) : '';
    return stepText(a, app, line);
  }
```
(import `stepText` from `./StepText`; drop now-unused `TOOL_*` imports if the linter complains).

In `DeviceExecutor.ets` constructor add `this.loadApps().catch(() => {});` (so labels are ready before the first `launch_app`), and:
```ts
  appLabel(bundleName: string): string {
    const app = this.apps.find((a: AppEntry) => a.bundleName === bundleName);
    return app === undefined ? '' : app.label;
  }
```

- [ ] **Step 5: Test fakes** – in `AgentLoop.test.ets`: FakeExecutor gets
```ts
  appLabel(bundleName: string): string {
    return bundleName === 'com.ohos.mms' ? 'Messages' : '';
  }
```
RecordingListener gets `texts: string[] = [];` and `this.texts.push(text);` in `log`. New test inside `describe('AgentLoop')`:
```ts
    it('logs steps as plain sentences', 0, async () => {
      const s = setup();
      s[0].responses = [
        reply('tool_use', [toolUse('t1', 'launch_app', { 'bundle_name': 'com.ohos.mms' })]),
        finish('t2')
      ];
      await s[3].run('text grandma');
      expect(s[2].texts).assertContain('Open Messages');
    });
```

- [ ] **Step 6: Run** – `.\scripts\test.ps1` → `Failure: 0, Error: 0`, Pass = 51 + 5.

- [ ] **Step 7: Checkpoint** – (only with user OK) commit "Show agent steps as plain sentences".

### Task 5: StatusTracker, Timeline, RunCheck, modelLabel (pure logic)

**Files:**
- Create: `entry/src/main/ets/common/StatusTracker.ets`, `common/Timeline.ets`, `common/RunCheck.ets`
- Modify: `entry/src/main/ets/agent/Providers.ets` (add `modelLabel`)
- Test: create `StatusTracker.test.ets`, `Timeline.test.ets`, `RunCheck.test.ets`; extend `Providers.test.ets`; register in `List.test.ets`

**Interfaces:**
- Consumes: `AgentStatus`, `LogEntry` (`common/Bridge.ets`); `LOG_*` (`agent/AgentLoop.ets`); `isValidModelId`, `findProvider` (`agent/Providers.ets`).
- Produces:
  - `class StatusTracker { entries: LogEntry[]; running: boolean; seen: number; version: number; apply(data: string): boolean }`
  - `interface Step { seq: number; kind: string; text: string; thoughts: string[] }`, `buildTimeline(entries: LogEntry[]): Step[]`, `currentStepText(steps: Step[]): string`, `STEP_THINKING = 'Thinking'`
  - `checkRun(providerLabel: string, apiKey: string, model: string, task: string): string` ('' = OK)
  - `modelLabel(providerId: string, modelId: string): string`

- [ ] **Step 1: Failing tests**

`StatusTracker.test.ets`:
```ts
import { describe, expect, it } from '@ohos/hypium';
import { AgentStatus, LogEntry } from '../../../main/ets/common/Bridge';
import { StatusTracker } from '../../../main/ets/common/StatusTracker';

function status(instance: number, version: number, full: boolean, entries: LogEntry[], running: boolean): string {
  const s: AgentStatus = { instance: instance, version: version, running: running, full: full, entries: entries };
  return JSON.stringify(s);
}

function e(seq: number, text: string): LogEntry {
  return { seq: seq, kind: 'action', text: text };
}

export default function statusTrackerTest() {
  describe('StatusTracker', () => {
    it('appends new entries and replaces on a full status', 0, () => {
      const t = new StatusTracker();
      expect(t.apply(status(1, 1, false, [e(1, 'a')], true))).assertTrue();
      expect(t.apply(status(1, 2, false, [e(2, 'b')], true))).assertTrue();
      expect(t.entries.length).assertEqual(2);
      expect(t.running).assertTrue();
      expect(t.apply(status(1, 3, true, [e(1, 'x')], false))).assertTrue();
      expect(t.entries.length).assertEqual(1);
      expect(t.running).assertFalse();
    });

    it('drops stale and duplicate statuses but still counts them as seen', 0, () => {
      const t = new StatusTracker();
      t.apply(status(1, 5, false, [e(1, 'a')], true));
      expect(t.apply(status(1, 5, false, [e(2, 'dup')], true))).assertFalse();
      expect(t.apply(status(1, 4, false, [e(2, 'old')], true))).assertFalse();
      expect(t.entries.length).assertEqual(1);
      expect(t.seen).assertEqual(3);
    });

    it('seq 1 starts a new log; a new service instance is accepted at any version', 0, () => {
      const t = new StatusTracker();
      t.apply(status(1, 1, false, [e(1, 'a'), e(2, 'b')], true));
      t.apply(status(1, 2, false, [e(1, 'new task')], true));
      expect(t.entries.length).assertEqual(1);
      expect(t.apply(status(2, 1, false, [e(2, 'c')], true))).assertTrue();
      expect(t.entries.length).assertEqual(2);
    });

    it('ignores unparsable payloads', 0, () => {
      const t = new StatusTracker();
      expect(t.apply('not json')).assertFalse();
      expect(t.seen).assertEqual(0);
    });
  });
}
```

`Timeline.test.ets`:
```ts
import { describe, expect, it } from '@ohos/hypium';
import { LogEntry } from '../../../main/ets/common/Bridge';
import { buildTimeline, currentStepText, STEP_THINKING } from '../../../main/ets/common/Timeline';

function e(seq: number, kind: string, text: string): LogEntry {
  return { seq: seq, kind: kind, text: text };
}

export default function timelineTest() {
  describe('Timeline', () => {
    it('attaches thoughts to the next step', 0, () => {
      const steps = buildTimeline([
        e(1, 'task', 'text grandma'), e(2, 'thought', 'Open Messages first.'),
        e(3, 'action', 'Open Messages'), e(4, 'action', 'Look at the screen'), e(5, 'done', 'Sent.')
      ]);
      expect(steps.length).assertEqual(4);
      expect(steps[1].thoughts.join('|')).assertEqual('Open Messages first.');
      expect(steps[2].thoughts.length).assertEqual(0);
      expect(steps[3].kind).assertEqual('done');
    });

    it('trailing thoughts become a Thinking step', 0, () => {
      const steps = buildTimeline([e(1, 'task', 't'), e(2, 'thought', 'Hmm.')]);
      expect(steps[1].kind).assertEqual('thought');
      expect(steps[1].text).assertEqual(STEP_THINKING);
      expect(steps[1].thoughts[0]).assertEqual('Hmm.');
    });

    it('currentStepText is the last step, on one line', 0, () => {
      const long = 'a\nb ' + 'x'.repeat(600);
      const steps = buildTimeline([e(1, 'task', 't'), e(2, 'action', long)]);
      const text = currentStepText(steps);
      expect(text.indexOf('\n')).assertEqual(-1);
      expect(text.length <= 120).assertTrue();
      expect(currentStepText([])).assertEqual('');
    });
  });
}
```

`RunCheck.test.ets`:
```ts
import { describe, expect, it } from '@ohos/hypium';
import { checkRun } from '../../../main/ets/common/RunCheck';

export default function runCheckTest() {
  describe('RunCheck', () => {
    it('asks for the key first, in Settings', 0, () => {
      expect(checkRun('Anthropic Claude', '  ', 'claude-opus-5-5', 'x')).assertEqual('Add your Anthropic Claude API key in Settings.');
    });

    it('rejects invalid model IDs and empty tasks', 0, () => {
      expect(checkRun('OpenAI', 'k', 'bad id!', 'x')).assertContain('Settings');
      expect(checkRun('OpenAI', 'k', 'gpt-5', '   ')).assertEqual('Describe what the agent should do.');
    });

    it('returns empty when everything is set', 0, () => {
      expect(checkRun('OpenAI', 'k', 'gpt-5', 'Turn on Wi-Fi')).assertEqual('');
    });
  });
}
```

Add to `Providers.test.ets` inside its `describe`:
```ts
    it('modelLabel shows the suggested label or the raw custom ID', 0, () => {
      expect(modelLabel('anthropic', 'claude-opus-5-5')).assertEqual('Claude Opus 5.5');
      expect(modelLabel('openai', 'gpt-5.1-custom')).assertEqual('gpt-5.1-custom');
      expect(modelLabel('nope', 'x')).assertEqual('x');
    });
```
(add `modelLabel` to its Providers import). Register the three new suites in `List.test.ets`.

- [ ] **Step 2: Run, expect failure** – `.\scripts\test.ps1` → missing-module build errors.

- [ ] **Step 3: `common/StatusTracker.ets`** (logic moved verbatim from `Index.onStatus`, but producing a new array so `@State` copies refresh):
```ts
/** Merges the agent service's STATUS events into the current log (shared by the app and the overlay). */
import { AgentStatus, LogEntry } from './Bridge';

export class StatusTracker {
  entries: LogEntry[] = [];
  running: boolean = false;
  /** statuses received; any status proves the service is listening */
  seen: number = 0;
  version: number = 0;
  private instance: number = 0;

  /** Applies one STATUS payload; false if it was unparsable, stale or a duplicate. */
  apply(data: string): boolean {
    let status: AgentStatus;
    try {
      status = JSON.parse(data) as AgentStatus;
    } catch (e) {
      return false;
    }
    this.seen++;
    if (status.instance === this.instance && status.version <= this.version) {
      return false;
    }
    this.instance = status.instance;
    this.version = status.version;
    this.running = status.running;
    if (status.full) {
      this.entries = status.entries;
      return true;
    }
    let next = this.entries.slice();
    const lastSeq = next.length > 0 ? next[next.length - 1].seq : 0;
    for (const e of status.entries) {
      if (e.seq > lastSeq || e.seq === 1) {
        if (e.seq === 1) {
          next = [];
        }
        next.push(e);
      }
    }
    this.entries = next;
    return true;
  }
}
```
Note the original compares against `lastSeq` computed once before the loop; keep that.

- [ ] **Step 4: `common/Timeline.ets`**
```ts
/** Groups the agent log into the steps the user sees: each thought is folded under the step that follows it. */
import { LOG_THOUGHT } from '../agent/AgentLoop';
import { LogEntry } from './Bridge';

export const STEP_THINKING = 'Thinking';
const MAX_LINE = 120;

export interface Step {
  seq: number;
  kind: string;
  text: string;
  thoughts: string[];
}

export function buildTimeline(entries: LogEntry[]): Step[] {
  const steps: Step[] = [];
  let pending: string[] = [];
  for (const e of entries) {
    if (e.kind === LOG_THOUGHT) {
      pending.push(e.text);
      continue;
    }
    steps.push({ seq: e.seq, kind: e.kind, text: e.text, thoughts: pending });
    pending = [];
  }
  if (pending.length > 0) {
    steps.push({ seq: entries[entries.length - 1].seq, kind: LOG_THOUGHT, text: STEP_THINKING, thoughts: pending });
  }
  return steps;
}

/** The newest step as one short line, for the pill. */
export function currentStepText(steps: Step[]): string {
  if (steps.length === 0) {
    return '';
  }
  const line = steps[steps.length - 1].text.replace(/\s+/g, ' ').trim();
  return line.length > MAX_LINE ? line.substring(0, MAX_LINE - 1) + '…' : line;
}
```

- [ ] **Step 5: `common/RunCheck.ets`**
```ts
/** What is missing before a task can start ('' = ready). Shown in the app and in the overlay sheet. */
import { isValidModelId } from '../agent/Providers';

export function checkRun(providerLabel: string, apiKey: string, model: string, task: string): string {
  if (apiKey.trim().length === 0) {
    return `Add your ${providerLabel} API key in Settings.`;
  }
  if (!isValidModelId(model)) {
    return 'Choose a model in Settings. A custom model ID may use letters, digits and . _ - : /';
  }
  if (task.trim().length === 0) {
    return 'Describe what the agent should do.';
  }
  return '';
}
```

- [ ] **Step 6: `modelLabel`** – append to `agent/Providers.ets` after `isValidModelId`:
```ts
/** Display label of a model: the suggested model's label, or the custom ID itself. */
export function modelLabel(providerId: string, modelId: string): string {
  const m = findProvider(providerId)?.models.find((c: ModelChoice) => c.id === modelId);
  return m === undefined ? modelId : m.label;
}
```

- [ ] **Step 7: Run** – `.\scripts\test.ps1` → 0 failures; Pass = previous + 11.

- [ ] **Step 8: Checkpoint** – (only with user OK) commit "Extract status tracking, timeline grouping and run checks".

### Task 6: AgentClient (service control out of Index)

**Files:**
- Create: `entry/src/main/ets/common/AgentClient.ets`
- Modify: `entry/src/main/ets/common/Bridge.ets` (RunRequest `origin`, constants)
- Modify: `entry/src/main/ets/a11y/AgentA11y.ets` (`startRun` end)
- Modify: `entry/src/main/ets/pages/Index.ets` (use AgentClient + StatusTracker; visuals unchanged in this task)

**Interfaces:**
- Consumes: `StatusTracker` (Task 5).
- Produces (`common/AgentClient.ets`):
  - `class AgentClient { constructor(tracker: StatusTracker); enableService(): Promise<string>; restartService(): Promise<string>; waitForService(timeoutMs: number): Promise<boolean>; run(req: RunRequest): Promise<string>; stop(): Promise<string>; sync(): void }` (every `Promise<string>` resolves '' on success, else a user-facing message)
  - Bridge: `RunRequest.origin?: string`, `ORIGIN_APP = 'app'`, `ORIGIN_OVERLAY = 'overlay'`, `EVT_UI_VISIBLE = 'com.hackyeah.phoneagent.UI_VISIBLE'` (data `'1'`/`'0'`), `SYSTEMUI_BUNDLE = 'com.ohos.systemui'`.

- [ ] **Step 1: Bridge** – in `RunRequest` add:
```ts
  /** who started the task: ORIGIN_APP (default) or ORIGIN_OVERLAY; overlay runs do not reopen the app */
  origin?: string;
```
and after the event constants:
```ts
/** EntryAbility -> overlay: the app window went to the foreground ('1') or background ('0') */
export const EVT_UI_VISIBLE = 'com.hackyeah.phoneagent.UI_VISIBLE';

export const ORIGIN_APP = 'app';
export const ORIGIN_OVERLAY = 'overlay';
/** the stock navigation bar; the only other app allowed to open the overlay (long-press Home) */
export const SYSTEMUI_BUNDLE = 'com.ohos.systemui';
```

- [ ] **Step 2: AgentA11y** – replace the last lines of `startRun` (`// Leave the result visible…` + `setTimeout`) with:
```ts
    // Leave the result visible in the target app for a moment, then show the log.
    // Overlay runs show the result in the pill instead and leave the user where they are.
    if (req.origin !== ORIGIN_OVERLAY) {
      setTimeout(() => this.showUi(), RETURN_TO_UI_DELAY_MS);
    }
```
(import `ORIGIN_OVERLAY`).

- [ ] **Step 3: `common/AgentClient.ets`** (logic moved from `Index.enableService/run/waitForService/restartService`):
```ts
/**
 * Controls the agent service (our accessibility extension) for both front ends: the app and the overlay.
 * Every call that can fail resolves to '' on success or to a message for the user.
 */
import { config } from '@kit.AccessibilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { EVT_RUN, EVT_STOP, EVT_SYNC, OWN_A11Y_ABILITY, publishEvent, RunRequest } from './Bridge';
import { StatusTracker } from './StatusTracker';

const ERR_ALREADY_ENABLED = 9300002;
const SERVICE_ACK_TIMEOUT_MS = 5000;
const SERVICE_PING_TIMEOUT_MS = 8000;

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, ms));
}

export class AgentClient {
  private tracker: StatusTracker;

  constructor(tracker: StatusTracker) {
    this.tracker = tracker;
  }

  /** System API (WRITE_ACCESSIBILITY_CONFIG): switch on our own accessibility extension. */
  async enableService(): Promise<string> {
    try {
      await config.enableAbility(OWN_A11Y_ABILITY, ['retrieve', 'gesture']);
      return '';
    } catch (e) {
      const err = e as BusinessError;
      return err.code === ERR_ALREADY_ENABLED ? '' : `Agent service unavailable (${err.code}): ${err.message}`;
    }
  }

  /** Reconnects a service process that is enabled but not listening (e.g. after it was killed). */
  async restartService(): Promise<string> {
    try {
      await config.disableAbility(OWN_A11Y_ABILITY);
    } catch (e) {
      // not enabled: fine, enable below
    }
    return this.enableService();
  }

  /** Pings the service with SYNC until it answers with a status, or the timeout passes. */
  async waitForService(timeoutMs: number): Promise<boolean> {
    const before = this.tracker.seen;
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      try {
        await publishEvent(EVT_SYNC, '');
      } catch (e) {
        // keep trying until the deadline
      }
      for (let i = 0; i < 10 && Date.now() < deadline; i++) {
        await sleep(100);
        if (this.tracker.seen > before) {
          return true;
        }
      }
    }
    return false;
  }

  /** Starts a task and waits until the service acknowledges it with a status. */
  async run(req: RunRequest): Promise<string> {
    // Make sure the service is listening (e.g. right after boot it may still be connecting).
    if (!(await this.waitForService(SERVICE_PING_TIMEOUT_MS))) {
      await this.restartService();
      if (!(await this.waitForService(2 * SERVICE_PING_TIMEOUT_MS))) {
        return 'The agent service is not responding. Try again in a moment.';
      }
    }
    const versionBefore = this.tracker.version;
    try {
      await publishEvent(EVT_RUN, JSON.stringify(req));
    } catch (e) {
      return 'Could not reach the agent service.';
    }
    // The service answers every RUN with a status; if none arrives it was not listening yet.
    const deadline = Date.now() + SERVICE_ACK_TIMEOUT_MS;
    while (Date.now() < deadline) {
      await sleep(100);
      if (this.tracker.version !== versionBefore) {
        return '';
      }
    }
    await this.restartService();
    return 'The agent service did not respond. It is being restarted, try again in a moment.';
  }

  async stop(): Promise<string> {
    try {
      await publishEvent(EVT_STOP, '');
      return '';
    } catch (e) {
      return 'Could not reach the agent service.';
    }
  }

  /** Asks the service to republish the full log. */
  sync(): void {
    publishEvent(EVT_SYNC, '').catch(() => {});
  }
}
```

- [ ] **Step 4: Index uses it (no visual change yet)** – in `Index.ets`:
  - add fields `private tracker: StatusTracker = new StatusTracker();` and `private client: AgentClient = new AgentClient(this.tracker);`
  - `onStatus(data)` becomes:
    ```ts
    private onStatus(data: string): void {
      if (this.tracker.apply(data)) {
        this.entries = this.tracker.entries;
        this.running = this.tracker.running;
      }
    }
    ```
  - `enableService()` becomes `this.client.enableService().then((msg: string) => { this.serviceReady = msg.length === 0; if (msg.length > 0) { this.notice = msg; } });`
  - `run()`: keep the field checks for now, then replace everything from `this.running = true;` (the first one) to the end with:
    ```ts
    this.running = true;
    this.entries = [];
    const req: RunRequest = { task: task, provider: provider.id, model: model, origin: ORIGIN_APP };
    const msg = await this.client.run(req);
    if (msg.length > 0) {
      this.running = false;
      this.notice = msg;
    }
    ```
  - Stop button: `this.client.stop().then((msg: string) => { if (msg.length > 0) { this.notice = msg; } });`
  - delete `waitForService`, `restartService`, `statusesSeen`, `statusInstance`, `statusVersion`, `sleep`, the moved constants.

- [ ] **Step 5: Run tests + manual smoke** – `.\scripts\test.ps1` (0 failures), then `.\scripts\build.ps1` and run the debug autorun script task; check `hdc shell "hilog -x" | findstr AgentA11y` shows the run and the app reopens afterwards (origin app).

- [ ] **Step 6: Checkpoint** – (only with user OK) commit "Move agent service control into AgentClient".

### Task 6b: Reasoning effort per model (D11)

**Files:**
- Modify: `entry/src/main/ets/agent/Providers.ets` (models table, new helpers, `createLlm`)
- Modify: `entry/src/main/ets/agent/OpenAiCompat.ets:50-55` (`OaRequest`), `:121-124` (`buildOpenAiRequest`), `:226-244` (client)
- Modify: `entry/src/main/ets/agent/Gemini.ets:77-82` (`GmRequest`), `:198-205` (`buildGeminiRequest`), `:298-316` (client)
- Modify: `entry/src/main/ets/common/Settings.ets` (`AgentSettings.effort`), `common/Bridge.ets` (`RunRequest.effort`), `a11y/AgentA11y.ets:176`
- Test: `Providers.test.ets`, `OpenAiCompat.test.ets`, `Gemini.test.ets`

**Interfaces:**
- Produces:
  - `ModelChoice.efforts: string[]` (allowed levels, low → high; `[]` = no effort knob)
  - `effortsFor(providerId: string, modelId: string): string[]` (`[]` for unknown/custom models)
  - `effortLabel(effort: string): string` ('' → 'Default', 'none' → 'Off', 'minimal' → 'Minimal', 'low' → 'Low', 'medium' → 'Medium', 'high' → 'High', 'xhigh' → 'Extra high', 'max' → 'Max')
  - `anthropicModelOption(modelId: string, effort: string): ModelOption`
  - `modelSummary(providerId: string, modelId: string, effort: string): string` – chip text, e.g. "Claude Opus 5.5, high effort" (just the model label when effort is '')
  - `createLlm(provider: string, apiKey: string, model: string, effort?: string): Llm` (an effort the model does not list is ignored, so stale settings never cause a 400)
  - `buildOpenAiRequest(model, system, tools, messages, effort?: string)`; `OpenAiCompatClient(url, apiKey, model, effort?: string)`
  - `GEMINI_THINKING_BUDGET: Record<string, number>`; `buildGeminiRequest(system, tools, messages, effort?: string)`; `GeminiClient(apiKey, model, effort?: string)`
  - `AgentSettings.effort: string` ('' = Default); `RunRequest.effort?: string`

- [ ] **Step 1: Failing tests**

Add to `Providers.test.ets` (import `anthropicModelOption`, `effortLabel`, `effortsFor`, `modelSummary`):
```ts
    it('modelSummary adds the effort only when one is chosen', 0, () => {
      expect(modelSummary('anthropic', 'claude-opus-5-5', 'xhigh')).assertEqual('Claude Opus 5.5, extra high effort');
      expect(modelSummary('anthropic', 'claude-opus-5-5', '')).assertEqual('Claude Opus 5.5');
      expect(modelSummary('openai', 'my-custom-model', '')).assertEqual('my-custom-model');
    });

    it('lists effort levels only for models that take them', 0, () => {
      expect(effortsFor('anthropic', 'claude-opus-5-5').join(',')).assertEqual('low,medium,high,xhigh,max');
      expect(effortsFor('anthropic', 'claude-haiku-4-5').length).assertEqual(0);
      expect(effortsFor('xai', 'grok-4').length).assertEqual(0);
      expect(effortsFor('openai', 'my-custom-model').length).assertEqual(0);
      expect(effortLabel('xhigh')).assertEqual('Extra high');
      expect(effortLabel('')).assertEqual('Default');
    });

    it('anthropicModelOption keeps the default effort unless a valid one is chosen', 0, () => {
      expect(anthropicModelOption('claude-sonnet-5-5', '').effort).assertEqual('medium');
      expect(anthropicModelOption('claude-sonnet-5-5', 'max').effort).assertEqual('max');
      expect(anthropicModelOption('claude-haiku-4-5', 'high').effort).assertUndefined();
    });

    it('createLlm ignores an effort the model does not take', 0, () => {
      expect(createLlm('xai', 'key', 'grok-4', 'high') !== undefined).assertTrue();
      expect(createLlm('gemini', 'key', 'gemini-2.5-pro', 'none') !== undefined).assertTrue();
    });
```
Add to `OpenAiCompat.test.ets`:
```ts
    it('sends reasoning_effort only when chosen', 0, () => {
      expect(buildOpenAiRequest('gpt-5', 'SYSTEM', TOOLS, conversation(), 'high').reasoning_effort).assertEqual('high');
      expect(JSON.stringify(buildOpenAiRequest('gpt-5', 'SYSTEM', TOOLS, conversation())))
        .assertEqual(JSON.stringify(buildOpenAiRequest('gpt-5', 'SYSTEM', TOOLS, conversation(), '')));
      expect(JSON.stringify(buildOpenAiRequest('gpt-5', 'SYSTEM', TOOLS, conversation())).indexOf('reasoning_effort'))
        .assertEqual(-1);
    });
```
Add to `Gemini.test.ets` (reuse that file's `msgs` setup from the existing request test):
```ts
    it('maps effort to a thinking budget', 0, () => {
      expect(buildGeminiRequest('SYSTEM', TOOLS, msgs, 'low').generationConfig?.thinkingConfig.thinkingBudget)
        .assertEqual(1024);
      expect(buildGeminiRequest('SYSTEM', TOOLS, msgs, 'none').generationConfig?.thinkingConfig.thinkingBudget)
        .assertEqual(0);
      expect(buildGeminiRequest('SYSTEM', TOOLS, msgs).generationConfig).assertUndefined();
    });
```
Run `.\scripts\test.ps1` → build errors (missing exports/params).

- [ ] **Step 2: Check the API docs** – Context7 (`resolve-library-id` "OpenAI API", "Google Gemini API", "xAI API") for: `reasoning_effort` values on `gpt-5`/`gpt-5-mini` Chat Completions; whether `grok-4` rejects `reasoning_effort` and `grok-3-mini` takes `low|high`; `thinkingBudget` ranges for 2.5 Pro (128–32768, no 0) and 2.5 Flash (0–24576). If anything differs, change the table in Decisions and the `efforts` lists below to match before writing code.

- [ ] **Step 3: Providers** – in `ModelChoice` add:
```ts
  /** reasoning effort levels the model accepts, lowest first; [] = no effort setting */
  efforts: string[];
```
and give every model its list:
```ts
const CLAUDE_EFFORTS: string[] = ['low', 'medium', 'high', 'xhigh', 'max'];
const GPT5_EFFORTS: string[] = ['minimal', 'low', 'medium', 'high'];
```
- Claude Opus 5.5 / Sonnet 5.5: `efforts: CLAUDE_EFFORTS`; Claude Haiku 4.5: `efforts: []`
- GPT-5 / GPT-5 mini: `efforts: GPT5_EFFORTS`
- Grok 4: `efforts: []`; Grok 3 mini: `efforts: ['low', 'high']`
- Gemini 2.5 Pro: `efforts: ['low', 'medium', 'high']`; Gemini 2.5 Flash: `efforts: ['none', 'low', 'medium', 'high']`

New helpers (after `modelLabel`):
```ts
const EFFORT_LABELS: Record<string, string> = {
  'none': 'Off', 'minimal': 'Minimal', 'low': 'Low', 'medium': 'Medium', 'high': 'High', 'xhigh': 'Extra high', 'max': 'Max'
};

/** Effort levels of a suggested model; [] for models without one and for custom model IDs. */
export function effortsFor(providerId: string, modelId: string): string[] {
  const m = findProvider(providerId)?.models.find((c: ModelChoice) => c.id === modelId);
  return m === undefined ? [] : m.efforts;
}

/** '' (not set) shows as 'Default'. */
export function effortLabel(effort: string): string {
  return effort.length === 0 ? 'Default' : (EFFORT_LABELS[effort] ?? effort);
}

/** The Anthropic model options with the chosen effort; '' or an unsupported effort keeps the model's default. */
export function anthropicModelOption(modelId: string, effort: string): ModelOption {
  const base = findModel(modelId);
  const usable = base.effort !== undefined && effortsFor(PROVIDER_ANTHROPIC, modelId).indexOf(effort) >= 0;
  return { id: base.id, label: base.label, effort: usable ? effort : base.effort, fallbacks: base.fallbacks };
}

/** Model chip text: "Claude Opus 5.5, high effort", or just the model when the effort is the default. */
export function modelSummary(providerId: string, modelId: string, effort: string): string {
  const model = modelLabel(providerId, modelId);
  return effort.length > 0 ? `${model}, ${effortLabel(effort).toLowerCase()} effort` : model;
}
```
(import `ModelOption` from `./Anthropic`.) `createLlm` gets `effort: string = ''`, computes `const e = effortsFor(provider, model).indexOf(effort) >= 0 ? effort : '';` and passes it on:
```ts
    case PROVIDER_ANTHROPIC:
      return new AnthropicLlm(new AnthropicClient(apiKey, anthropicModelOption(model, e)));
    case PROVIDER_OPENAI:
      return new ChatClientLlm(new OpenAiCompatClient(OPENAI_CHAT_URL, apiKey, model, e));
    case PROVIDER_XAI:
      return new ChatClientLlm(new OpenAiCompatClient(XAI_CHAT_URL, apiKey, model, e));
    case PROVIDER_GEMINI:
      return new ChatClientLlm(new GeminiClient(apiKey, model, e));
```

- [ ] **Step 4: OpenAI-compatible** – `OaRequest` gets `reasoning_effort?: string;`. `buildOpenAiRequest(model, system, tools, messages, effort: string = '')`:
```ts
  const req: OaRequest = { model: model, messages: toOpenAiMessages(system, messages), tools: toOpenAiTools(tools), tool_choice: 'auto' };
  if (effort.length > 0) {
    req.reasoning_effort = effort;
  }
  return req;
```
`OpenAiCompatClient` stores `effort` (constructor param `effort: string = ''`) and passes it to `buildOpenAiRequest`.

- [ ] **Step 5: Gemini** – add:
```ts
export interface GmThinkingConfig {
  thinkingBudget: number;
}

export interface GmGenerationConfig {
  thinkingConfig: GmThinkingConfig;
}

/** effort level -> thinking token budget (Gemini 2.5) */
export const GEMINI_THINKING_BUDGET: Record<string, number> = { 'none': 0, 'low': 1024, 'medium': 8192, 'high': 24576 };
```
`GmRequest` gets `generationConfig?: GmGenerationConfig;`. `buildGeminiRequest(system, tools, messages, effort: string = '')` builds the same object as today into `const req: GmRequest`, then:
```ts
  const budget = GEMINI_THINKING_BUDGET[effort];
  if (budget !== undefined) {
    req.generationConfig = { thinkingConfig: { thinkingBudget: budget } };
  }
  return req;
```
`GeminiClient` stores `effort` (constructor param `effort: string = ''`) and passes it to `buildGeminiRequest`.

- [ ] **Step 6: Settings and run request**
  - `common/Settings.ets`: `AgentSettings` gets `/** reasoning effort; '' = the model's default */ effort: string;`, a `KEY_EFFORT = 'effort'` constant, `loadSettings` reads `effort: prefs.getSync(KEY_EFFORT, '') as string`, `saveSettings` writes `prefs.putSync(KEY_EFFORT, settings.effort)`.
  - `common/Bridge.ets` `RunRequest`: `/** reasoning effort; '' or missing = the model's default */ effort?: string;`
  - `AgentA11y.ets:176`: `llm = createLlm(provider.id, apiKey, typeof req.model === 'string' ? req.model.trim() : '', typeof req.effort === 'string' ? req.effort : '');`
  - The temporary Index from Task 6 still compiles: add `effort: ''` wherever it builds an `AgentSettings` literal (Task 7/8 replace that code).

- [ ] **Step 7: Run** – `.\scripts\test.ps1` → 0 failures; Pass = previous + 6.

- [ ] **Step 8: Live check (do it right after Task 7 lands; one call each, needs the user's keys; skip any provider without a key)** – set effort `max` for Claude Opus 5.5 in Settings (Task 7) and run "Turn on Wi-Fi"; `hilog` shows no 400. Same with GPT-5 `minimal` and Gemini 2.5 Flash `none` if keys exist. Record which were checked in `PhoneAgent/README.md` next to the provider list.

- [ ] **Step 9: Checkpoint** – (only with user OK) commit "Let the user choose reasoning effort per model".

### Task 7: Settings page

**Files:**
- Create: `entry/src/main/ets/pages/Settings.ets`
- Create: `entry/src/main/resources/base/media/ic_back.svg`, `ic_settings.svg`
- Modify: `entry/src/main/ets/common/Settings.ets` (orb flag)
- Modify: `entry/src/main/resources/base/profile/main_pages.json`
- Modify: `PhoneAgent/README.md` ("Use" section)

**Interfaces:**
- Consumes: `PROVIDERS`, `ModelChoice`, `ProviderInfo`, `isValidModelId` (Providers); `loadSettings`, `loadApiKey`, `saveApiKey`, `saveSettings` (Settings); `AgentClient`, `StatusTracker`; `DISPLAY_FONT`.
- Produces: route `pages/Settings`; `loadShowOrb(ctx: Context): boolean` (default true), `saveShowOrb(ctx: Context, on: boolean): Promise<void>`; AppStorage key `KEY_SERVICE_READY = 'serviceReady'` (exported from `pages/Settings.ets`? no: from `common/Settings.ets`) read by Settings, written by Index; `OVERLAY_ABILITY = 'OverlayService'` constant in `common/Settings.ets` (the Settings page starts/stops it; the service itself arrives in Task 9, until then the start call fails silently).

- [ ] **Step 1: Orb flag + shared keys** – append to `common/Settings.ets`:
```ts
const KEY_SHOW_ORB = 'showOrb';

/** AppStorage key: true while the agent service is enabled (written by Index, shown in Settings). */
export const KEY_SERVICE_READY = 'serviceReady';
/** ServiceExtensionAbility that owns the floating orb, sheet and pill. */
export const OVERLAY_ABILITY = 'OverlayService';

/** Whether the floating orb is shown over other apps (default on). */
export function loadShowOrb(ctx: Context): boolean {
  return store(ctx, false).getSync(KEY_SHOW_ORB, true) as boolean;
}

export async function saveShowOrb(ctx: Context, on: boolean): Promise<void> {
  const prefs = store(ctx, false);
  prefs.putSync(KEY_SHOW_ORB, on);
  await prefs.flush();
}
```

- [ ] **Step 2: Icons** – `ic_back.svg`:
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M15.4 5.4 14 4l-8 8 8 8 1.4-1.4L8.8 12z" fill="#000"/></svg>
```
`ic_settings.svg` (sliders):
```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="#000">
  <rect x="3" y="5" width="18" height="2" rx="1"/><circle cx="9" cy="6" r="2.6"/>
  <rect x="3" y="11" width="18" height="2" rx="1"/><circle cx="15" cy="12" r="2.6"/>
  <rect x="3" y="17" width="18" height="2" rx="1"/><circle cx="7" cy="18" r="2.6"/>
</svg>
```

- [ ] **Step 3: `pages/Settings.ets`**
```ts
import { common, Want } from '@kit.AbilityKit';
import { effortLabel, effortsFor, isValidModelId, ModelChoice, ProviderInfo, PROVIDERS } from '../agent/Providers';
import { AgentClient } from '../common/AgentClient';
import { OWN_BUNDLE } from '../common/Bridge';
import { DISPLAY_FONT } from '../common/Fonts';
import {
  KEY_SERVICE_READY,
  loadApiKey,
  loadSettings,
  loadShowOrb,
  OVERLAY_ABILITY,
  saveApiKey,
  saveSettings,
  saveShowOrb
} from '../common/Settings';
import { StatusTracker } from '../common/StatusTracker';

const CUSTOM_MODEL_LABEL = 'Custom model ID…';

function providerIndexOf(id: string): number {
  const i = PROVIDERS.findIndex((p: ProviderInfo) => p.id === id);
  return i >= 0 ? i : 0;
}

function modelOptions(p: ProviderInfo): SelectOption[] {
  const options = p.models.map((m: ModelChoice) => {
    const o: SelectOption = { value: m.label };
    return o;
  });
  const custom: SelectOption = { value: CUSTOM_MODEL_LABEL };
  options.push(custom);
  return options;
}

@Entry
@Component
struct Settings {
  @State providerIndex: number = 0;
  @State apiKey: string = '';
  /** index into the provider's models; models.length = custom model ID */
  @State modelIndex: number = 0;
  @State customModel: string = '';
  /** '' = the model's default */
  @State effort: string = '';
  @State showOrb: boolean = true;
  @State reconnecting: boolean = false;
  @State serviceNotice: string = '';
  @StorageLink(KEY_SERVICE_READY) serviceReady: boolean = false;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    const settings = loadSettings(this.ctx(), false);
    this.providerIndex = providerIndexOf(settings.provider);
    this.apiKey = settings.apiKey;
    const models = this.provider().models;
    const i = models.findIndex((m: ModelChoice) => m.id === settings.model);
    if (i >= 0) {
      this.modelIndex = i;
    } else {
      this.modelIndex = models.length;
      this.customModel = settings.model;
    }
    this.effort = this.efforts().indexOf(settings.effort) >= 0 ? settings.effort : '';
    this.showOrb = loadShowOrb(this.ctx());
  }

  onPageHide(): void {
    this.save();
  }

  private provider(): ProviderInfo {
    return PROVIDERS[this.providerIndex];
  }

  private isCustomModel(): boolean {
    return this.modelIndex >= this.provider().models.length;
  }

  private selectedModel(): string {
    return this.isCustomModel() ? this.customModel.trim() : this.provider().models[this.modelIndex].id;
  }

  /** effort levels of the selected model; [] hides the effort row */
  private efforts(): string[] {
    return effortsFor(this.provider().id, this.selectedModel());
  }

  private effortOptions(): SelectOption[] {
    return [''].concat(this.efforts()).map((e: string) => {
      const o: SelectOption = { value: effortLabel(e) };
      return o;
    });
  }

  /** A model switch keeps the effort only if the new model has the same level. */
  private selectModel(index: number): void {
    this.modelIndex = index;
    if (this.efforts().indexOf(this.effort) < 0) {
      this.effort = '';
    }
    this.save();
  }

  private save(): void {
    saveSettings(this.ctx(), {
      provider: this.provider().id, model: this.selectedModel(), apiKey: this.apiKey, effort: this.effort
    });
  }

  /** Keeps each provider's key: save the one being left, load the one being switched to. */
  private async switchProvider(index: number): Promise<void> {
    if (index === this.providerIndex) {
      return;
    }
    await saveApiKey(this.ctx(), this.provider().id, this.apiKey);
    this.providerIndex = index;
    this.apiKey = loadApiKey(this.ctx(), this.provider().id, false);
    this.modelIndex = 0;
    this.customModel = '';
    this.effort = '';
    this.save();
  }

  private async setShowOrb(on: boolean): Promise<void> {
    this.showOrb = on;
    await saveShowOrb(this.ctx(), on);
    const want: Want = { bundleName: OWN_BUNDLE, abilityName: OVERLAY_ABILITY };
    try {
      if (on) {
        await this.ctx().startServiceExtensionAbility(want);
      } else {
        await this.ctx().stopServiceExtensionAbility(want);
      }
    } catch (e) {
      // the overlay service is optional; the switch still takes effect on the next app start
    }
  }

  private async reconnect(): Promise<void> {
    this.reconnecting = true;
    const msg = await new AgentClient(new StatusTracker()).restartService();
    this.reconnecting = false;
    this.serviceReady = msg.length === 0;
    this.serviceNotice = msg;
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.ink_muted'))
      .margin({ top: 24, bottom: 8, left: 4 })
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.ink'))
          .padding(10)
          .width(44)
          .height(44)
          .accessibilityText('Back')
          .onClick(() => this.getUIContext().getRouter().back())
        Text('Settings')
          .fontFamily(DISPLAY_FONT)
          .fontSize(24)
          .fontColor($r('app.color.ink'))
      }
      .width('100%')
      .height(56)

      Scroll() {
        Column() {
          this.sectionTitle('AI model')
          Column({ space: 12 }) {
            Select(PROVIDERS.map((p: ProviderInfo) => {
              const o: SelectOption = { value: p.label };
              return o;
            }))
              .selected(this.providerIndex)
              .value(this.provider().label)
              .width('100%')
              .onSelect((index: number) => {
                this.switchProvider(index);
              })
            TextInput({ placeholder: this.provider().keyHint, text: this.apiKey })
              .type(InputType.Password)
              .showPasswordIcon(true)
              .onChange((v: string) => {
                this.apiKey = v;
              })
              .onBlur(() => this.save())
            Select(modelOptions(this.provider()))
              .selected(this.modelIndex)
              .value(this.isCustomModel() ? CUSTOM_MODEL_LABEL : this.provider().models[this.modelIndex].label)
              .width('100%')
              .onSelect((index: number) => {
                this.selectModel(index);
              })
            if (this.efforts().length > 0) {
              Row({ space: 12 }) {
                Text('Effort')
                  .fontSize(16)
                  .fontColor($r('app.color.ink'))
                Select(this.effortOptions())
                  .selected(this.effort.length === 0 ? 0 : this.efforts().indexOf(this.effort) + 1)
                  .value(effortLabel(this.effort))
                  .layoutWeight(1)
                  .onSelect((index: number) => {
                    this.effort = index === 0 ? '' : this.efforts()[index - 1];
                    this.save();
                  })
              }
              .width('100%')
              Text('Higher effort thinks longer: slower and more expensive, better on tricky tasks.')
                .fontSize(13)
                .fontColor($r('app.color.ink_muted'))
                .width('100%')
            }
            if (this.isCustomModel()) {
              TextInput({ placeholder: 'Model ID, e.g. gpt-5.1', text: this.customModel })
                .onChange((v: string) => {
                  this.customModel = v;
                })
                .onBlur(() => this.save())
              if (this.customModel.trim().length > 0 && !isValidModelId(this.customModel.trim())) {
                Text('Use letters, digits and . _ - : / only.')
                  .fontSize(13)
                  .fontColor($r('app.color.danger'))
                  .width('100%')
              }
            }
            Text('Each provider keeps its own key. Keys stay on this phone and are only sent to that provider.')
              .fontSize(13)
              .fontColor($r('app.color.ink_muted'))
              .width('100%')
          }
          .padding(16)
          .borderRadius(20)
          .backgroundColor($r('app.color.surface'))

          this.sectionTitle('Floating button')
          Row() {
            Column({ space: 2 }) {
              Text('Show Oniro Agent over other apps')
                .fontSize(16)
                .fontColor($r('app.color.ink'))
              Text('Tap the orb in any app to give the agent a task.')
                .fontSize(13)
                .fontColor($r('app.color.ink_muted'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.showOrb })
              .selectedColor($r('app.color.orb_violet'))
              .onChange((on: boolean) => {
                this.setShowOrb(on);
              })
          }
          .padding(16)
          .borderRadius(20)
          .backgroundColor($r('app.color.surface'))

          this.sectionTitle('Agent service')
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Circle()
                .width(10)
                .height(10)
                .fill(this.serviceReady ? $r('app.color.orb_teal') : $r('app.color.danger'))
              Text(this.serviceReady ? 'On: the agent can read and use other apps' : 'Off: the agent cannot use other apps')
                .fontSize(16)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
            }
            .width('100%')
            Button(this.reconnecting ? 'Reconnecting…' : 'Reconnect')
              .enabled(!this.reconnecting)
              .backgroundColor($r('app.color.bg'))
              .fontColor($r('app.color.ink'))
              .onClick(() => this.reconnect())
            if (this.serviceNotice.length > 0) {
              Text(this.serviceNotice)
                .fontSize(13)
                .fontColor($r('app.color.danger'))
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding(16)
          .borderRadius(20)
          .backgroundColor($r('app.color.surface'))
        }
        .padding({ left: 16, right: 16, bottom: 32 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }
}
```

- [ ] **Step 4: Register the page** – `main_pages.json`: `{ "src": ["pages/Index", "pages/Settings"] }`.

- [ ] **Step 5: Temporary entry point** – until Task 8 lands, add to the current Index header Row: `Image($r('app.media.ic_settings')).width(24).height(24).fillColor($r('app.color.ink')).onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings' }))`, and in `Index.onPageShow` reload `this.providerIndex/apiKey/modelIndex/customModel` from `loadSettings` (copy of `aboutToAppear`'s block). Index keeps writing `AppStorage.setOrCreate<boolean>(KEY_SERVICE_READY, ready)` wherever it sets `serviceReady`.

- [ ] **Step 6: Manual check (Review Focus 2)** – build; in Settings pick Anthropic, type key `A`; switch to OpenAI, type `B`; back to Anthropic → field shows `A`; to OpenAI → `B`. Leave Settings, re-enter → same. Pick a custom model `bad id!` → red hint shows. Effort: Claude Opus 5.5 → Effort row shows Default, Low … Max; pick High; switch to Claude Sonnet 5.5 → still High; switch to Claude Haiku 4.5 → row hidden; back to Opus → Default. Screenshot `settings-light`.

- [ ] **Step 7: README "Use"** – replace the Use paragraph with: `Settings (sliders icon, top right) → AI provider → API key → model (or "Custom model ID…"). Each provider keeps its own key. Back on the main screen type the task and tap the round button. To test the SMS task, add a contact "Babcia" first.`

- [ ] **Step 8: Checkpoint** – (only with user OK) commit "Add the Settings page".

### Task 8: Main screen redesign

**Files:**
- Create: `entry/src/main/ets/components/Composer.ets`, `components/StepList.ets`
- Create: `entry/src/main/resources/base/media/ic_arrow_up.svg`, `ic_stop.svg`, `ic_check.svg`, `ic_alert.svg`
- Rewrite: `entry/src/main/ets/pages/Index.ets`

**Interfaces:**
- Consumes: `OaMark`, `DISPLAY_FONT`, `StatusTracker`, `AgentClient`, `buildTimeline`/`Step`, `checkRun`, `modelSummary`, `findProvider`, `loadSettings`, `KEY_SERVICE_READY`, `ORIGIN_APP`, `KEY_INCOMING_*`.
- Produces: `Composer({ text: $text, running: boolean, canRun: boolean, placeholder?: string, onRun: () => void, onStop: () => void })`; `StepList({ steps: Step[], running: boolean })` – both reused by the overlay in Task 10.

- [ ] **Step 1: Icons** (filled, recolored with `fillColor`)
  - `ic_arrow_up.svg`: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M12 4l7 7-1.4 1.4L13 7.8V20h-2V7.8l-4.6 4.6L5 11z" fill="#000"/></svg>`
  - `ic_stop.svg`: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12" rx="2.5" fill="#000"/></svg>`
  - `ic_check.svg`: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M9.5 16.2 5.3 12l-1.4 1.4 5.6 5.6L20.6 7.9l-1.4-1.4z" fill="#000"/></svg>`
  - `ic_alert.svg`: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M11 6h2v8h-2zM11 16h2v2h-2z" fill="#000"/></svg>`

- [ ] **Step 2: `components/Composer.ets`**
```ts
/** Task input with the round gradient Run/Stop button. Used by the main screen and the overlay sheet. */
@Component
export struct Composer {
  @Link text: string;
  @Prop running: boolean = false;
  /** false while the service is off or a start is in progress */
  @Prop canRun: boolean = true;
  placeholder: string = 'Ask Oniro Agent to do something';
  onRun: () => void = () => {};
  onStop: () => void = () => {};

  private active(): boolean {
    return this.running || (this.canRun && this.text.trim().length > 0);
  }

  build() {
    Row({ space: 8 }) {
      TextArea({ placeholder: this.placeholder, text: this.text })
        .layoutWeight(1)
        .fontSize(17)
        .fontColor($r('app.color.ink'))
        .placeholderColor($r('app.color.ink_muted'))
        .backgroundColor(Color.Transparent)
        .constraintSize({ minHeight: 48, maxHeight: 140 })
        .enabled(!this.running)
        .onChange((v: string) => {
          this.text = v;
        })
      Column() {
        Image(this.running ? $r('app.media.ic_stop') : $r('app.media.ic_arrow_up'))
          .width(22)
          .height(22)
          .fillColor($r('app.color.on_orb'))
      }
      .id('run')
      .width(48)
      .height(48)
      .borderRadius(24)
      .justifyContent(FlexAlign.Center)
      .linearGradient({
        angle: 135,
        colors: [[$r('app.color.orb_teal'), 0], [$r('app.color.orb_violet'), 0.55], [$r('app.color.orb_coral'), 1]]
      })
      .opacity(this.active() ? 1 : 0.35)
      .accessibilityText(this.running ? 'Stop' : 'Run')
      .onClick(() => {
        if (this.running) {
          this.onStop();
        } else if (this.active()) {
          this.onRun();
        }
      })
    }
    .alignItems(VerticalAlign.Bottom)
    .padding({ left: 16, right: 6, top: 6, bottom: 6 })
    .borderRadius(28)
    .backgroundColor($r('app.color.surface_raised'))
    .border({ width: 1, color: $r('app.color.line') })
  }
}
```

- [ ] **Step 3: `components/StepList.ets`**
```ts
/** The agent's steps as a vertical timeline; the model's thoughts sit folded under each step. */
import { LOG_DONE, LOG_ERROR, LOG_TASK, LOG_THOUGHT } from '../agent/AgentLoop';
import { DISPLAY_FONT } from '../common/Fonts';
import { Step } from '../common/Timeline';

@Component
struct StepRow {
  @Prop step: Step;
  @Prop current: boolean = false;
  @State open: boolean = false;

  @Builder
  marker() {
    if (this.step.kind === LOG_DONE) {
      Image($r('app.media.ic_check')).width(18).height(18).fillColor($r('app.color.orb_violet'))
    } else if (this.step.kind === LOG_ERROR) {
      Image($r('app.media.ic_alert')).width(18).height(18).fillColor($r('app.color.danger'))
    } else {
      Circle()
        .width(this.current ? 10 : 8)
        .height(this.current ? 10 : 8)
        .fill(this.current ? $r('app.color.orb_violet') : $r('app.color.ink_muted'))
    }
  }

  build() {
    if (this.step.kind === LOG_TASK) {
      Text(this.step.text)
        .fontFamily(DISPLAY_FONT)
        .fontSize(22)
        .fontColor($r('app.color.ink'))
        .width('100%')
        .padding({ top: 8, bottom: 16 })
    } else {
      Row({ space: 12 }) {
        Column() {
          this.marker()
        }
        .width(18)
        .height(24)
        .justifyContent(FlexAlign.Center)
        Column({ space: 4 }) {
          Text(this.step.text)
            .fontSize(this.step.kind === LOG_DONE ? 17 : 16)
            .fontWeight(this.step.kind === LOG_DONE ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.step.kind === LOG_ERROR ? $r('app.color.danger') : $r('app.color.ink'))
            .fontStyle(this.step.kind === LOG_THOUGHT ? FontStyle.Italic : FontStyle.Normal)
          if (this.step.thoughts.length > 0) {
            Text(this.step.thoughts.join(' '))
              .fontSize(14)
              .fontColor($r('app.color.ink_muted'))
              .maxLines(this.open ? 40 : 2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                this.open = !this.open;
              })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Top)
      .width('100%')
      .padding(this.step.kind === LOG_DONE ? 14 : { top: 6, bottom: 6 })
      .borderRadius(this.step.kind === LOG_DONE ? 18 : 0)
      .backgroundColor(this.step.kind === LOG_DONE ? $r('app.color.surface') : Color.Transparent)
    }
  }
}

@Component
export struct StepList {
  @Prop @Watch('scrollDown') steps: Step[] = [];
  @Prop running: boolean = false;
  private scroller: Scroller = new Scroller();

  scrollDown(): void {
    setTimeout(() => this.scroller.scrollEdge(Edge.Bottom), 50);
  }

  build() {
    List({ scroller: this.scroller, space: 2 }) {
      ForEach(this.steps, (s: Step, i: number) => {
        ListItem() {
          StepRow({ step: s, current: this.running && i === this.steps.length - 1 })
        }
      }, (s: Step) => `${s.seq}-${s.kind}-${s.thoughts.length}`)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }
}
```

- [ ] **Step 4: Rewrite `pages/Index.ets`**
```ts
import { common } from '@kit.AbilityKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import { findProvider, modelSummary, PROVIDERS } from '../agent/Providers';
import { AgentClient } from '../common/AgentClient';
import { EVT_STATUS, ORIGIN_APP, RunRequest, subscribeEvents, unsubscribeEvents } from '../common/Bridge';
import { DISPLAY_FONT } from '../common/Fonts';
import { checkRun } from '../common/RunCheck';
import { AgentSettings, KEY_SERVICE_READY, loadSettings } from '../common/Settings';
import { StatusTracker } from '../common/StatusTracker';
import { buildTimeline, Step } from '../common/Timeline';
import { Composer } from '../components/Composer';
import { OaMark } from '../components/OaMark';
import { StepList } from '../components/StepList';
import { KEY_INCOMING_AUTORUN, KEY_INCOMING_TASK } from '../entryability/EntryAbility';

const AUTORUN_DELAY_MS = 1500;
const SUGGESTIONS: string[] = [
  'Text Babcia that I will come to her birthday',
  'Turn on Wi-Fi',
  'Set an alarm for 7:00'
];

@Entry
@Component
struct Index {
  @State settings: AgentSettings = {
    provider: PROVIDERS[0].id, model: PROVIDERS[0].models[0].id, apiKey: '', effort: ''
  };
  @State task: string = '';
  @State running: boolean = false;
  @State starting: boolean = false;
  @StorageLink(KEY_SERVICE_READY) serviceReady: boolean = false;
  @State notice: string = '';
  @State steps: Step[] = [];
  private tracker: StatusTracker = new StatusTracker();
  private client: AgentClient = new AgentClient(this.tracker);
  private subscriber: commonEventManager.CommonEventSubscriber | undefined = undefined;

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    subscribeEvents([EVT_STATUS], (event: string, data: string) => this.onStatus(data))
      .then((sub: commonEventManager.CommonEventSubscriber) => {
        this.subscriber = sub;
        this.client.sync();
      })
      .catch(() => {
        this.notice = 'Could not connect to the agent service.';
      });
    this.enableService();
  }

  aboutToDisappear(): void {
    unsubscribeEvents(this.subscriber);
  }

  onPageShow(): void {
    this.settings = loadSettings(this.ctx(), false);
    this.client.sync();
    const incoming = AppStorage.get<string>(KEY_INCOMING_TASK);
    if (incoming !== undefined && incoming.length > 0) {
      this.task = incoming;
      AppStorage.setOrCreate<string>(KEY_INCOMING_TASK, '');
      if (AppStorage.get<boolean>(KEY_INCOMING_AUTORUN) === true) {
        AppStorage.setOrCreate<boolean>(KEY_INCOMING_AUTORUN, false);
        setTimeout(() => this.run(), AUTORUN_DELAY_MS);
      }
    }
  }

  private enableService(): void {
    this.client.enableService().then((msg: string) => {
      this.serviceReady = msg.length === 0;
      if (msg.length > 0) {
        this.notice = msg;
      }
    });
  }

  private onStatus(data: string): void {
    if (this.tracker.apply(data)) {
      this.steps = buildTimeline(this.tracker.entries);
      this.running = this.tracker.running;
    }
  }

  private providerLabel(): string {
    const p = findProvider(this.settings.provider);
    return p === undefined ? this.settings.provider : p.label;
  }

  private hasKey(): boolean {
    return this.settings.apiKey.trim().length > 0;
  }

  private openSettings(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings' });
  }

  private async run(): Promise<void> {
    const problem = checkRun(this.providerLabel(), this.settings.apiKey, this.settings.model, this.task);
    if (problem.length > 0) {
      this.notice = problem;
      return;
    }
    this.notice = '';
    this.starting = true;
    this.running = true;
    this.steps = [];
    const req: RunRequest = {
      task: this.task.trim(), provider: this.settings.provider, model: this.settings.model,
      effort: this.settings.effort, origin: ORIGIN_APP
    };
    const msg = await this.client.run(req);
    this.starting = false;
    if (msg.length > 0) {
      this.running = false;
      this.notice = msg;
    }
  }

  private stop(): void {
    this.client.stop().then((msg: string) => {
      if (msg.length > 0) {
        this.notice = msg;
      }
    });
  }

  @Builder
  emptyState() {
    Column({ space: 20 }) {
      Text('What should I do?')
        .fontFamily(DISPLAY_FONT)
        .fontSize(34)
        .fontColor($r('app.color.ink'))
      if (!this.hasKey()) {
        Text('Add an API key to get started.')
          .fontSize(16)
          .fontColor($r('app.color.ink_muted'))
        Button('Open Settings')
          .backgroundColor($r('app.color.orb_violet'))
          .fontColor($r('app.color.on_orb'))
          .onClick(() => this.openSettings())
      } else {
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
          ForEach(SUGGESTIONS, (s: string) => {
            Text(s)
              .fontSize(15)
              .fontColor($r('app.color.ink'))
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .borderRadius(18)
              .border({ width: 1, color: $r('app.color.line') })
              .backgroundColor($r('app.color.surface'))
              .onClick(() => {
                this.task = s;
              })
          }, (s: string) => s)
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 48 })
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        OaMark({ size: 32, spinning: this.running })
        Text('Oniro Agent')
          .fontFamily(DISPLAY_FONT)
          .fontSize(20)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        Image($r('app.media.ic_settings'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.ink'))
          .padding(10)
          .width(44)
          .height(44)
          .accessibilityText('Settings')
          .onClick(() => this.openSettings())
      }
      .width('100%')

      Column() {
        if (this.steps.length === 0) {
          this.emptyState()
        } else {
          StepList({ steps: this.steps, running: this.running })
        }
      }
      .layoutWeight(1)
      .width('100%')

      if (this.notice.length > 0) {
        Text(this.notice)
          .fontSize(14)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
      Composer({
        text: $task,
        running: this.running,
        canRun: this.serviceReady && !this.starting,
        onRun: () => this.run(),
        onStop: () => this.stop()
      })
      Row({ space: 8 }) {
        Text(modelSummary(this.settings.provider, this.settings.model, this.settings.effort))
          .fontSize(13)
          .fontColor($r('app.color.ink_muted'))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.line') })
          .onClick(() => this.openSettings())
        Blank()
        Circle()
          .width(8)
          .height(8)
          .fill(this.serviceReady ? $r('app.color.orb_teal') : $r('app.color.danger'))
        Text(this.serviceReady ? 'Agent service on' : 'Agent service off')
          .fontSize(13)
          .fontColor($r('app.color.ink_muted'))
          .onClick(() => this.enableService())
      }
      .width('100%')
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
  }
}
```
(`LengthMetrics` comes from `@kit.ArkUI`; add `import { LengthMetrics } from '@kit.ArkUI';`. If `Flex` `space` is unavailable at API 20, drop it and give chips `.margin({ right: 8, bottom: 8 })`.)

- [ ] **Step 5: Build + visual review, light and dark**

Run: `.\scripts\build.ps1`; screenshots: `main-empty-nokey` (clear key in Settings first), `main-empty` (with key), `main-running` (scripted autorun task, mid-run), `main-done`.
Dark: temporarily change `ColorMode.COLOR_MODE_NOT_SET` → `COLOR_MODE_DARK` in `EntryAbility.onCreate`, rebuild, screenshot `main-dark` and `settings-dark`, then revert.
Read every screenshot. Check against D3/D5 and the Global Constraints: gradient only on mark + Run + violet accents; greeting in Bricolage; step rows readable; long thought folded to 2 lines; nothing clipped at 360 vp width. Fix and re-shoot until clean. Remove one decoration if the screen feels busy.

- [ ] **Step 6: Tests still pass** – `.\scripts\test.ps1` → 0 failures.

- [ ] **Step 7: Checkpoint** – (only with user OK) commit "Redesign the main screen".

---

## Stage 3: Floating orb, sheet and pill

### Task 9: OverlayService + draggable orb

**Files:**
- Create: `entry/src/main/ets/overlay/OrbGeometry.ets`, `overlay/OverlayController.ets`, `overlay/OverlayService.ets`, `pages/OverlayOrb.ets`
- Test: `entry/src/ohosTest/ets/test/OrbGeometry.test.ets` (+ `List.test.ets`)
- Modify: `entry/src/main/module.json5`, `main_pages.json`, `signing/profile-template.json`, `entryability/EntryAbility.ets`, `PhoneAgent/ARCHITECTURE.md`

**Interfaces:**
- Consumes: `StatusTracker`, `AgentClient`, `buildTimeline`, `subscribeEvents`, `EVT_STATUS`, `EVT_UI_VISIBLE`, `OWN_BUNDLE`, `SYSTEMUI_BUNDLE`, `loadShowOrb`, `OVERLAY_ABILITY`, `registerFonts`.
- Produces:
  - `snapOrb(x, y, size, screenW, screenH, margin, topInset, bottomInset: number): OrbPoint` (`interface OrbPoint { x: number; y: number }`, all px)
  - `OverlayController.get()` singleton with `start(ctx: common.ServiceExtensionContext, showOrb: boolean, appVisible: boolean): Promise<void>`, `shutdown(): void`, `openSheet(): void`, `orbDragStart(displayX: number, displayY: number): void`, `orbDragMove(displayX: number, displayY: number): void`, `orbDragEnd(): void`, `wake(): void` (Task 10 adds `closeSheet`, `run`, `stop`, `togglePill`, `openApp`)
  - AppStorage keys `KEY_OV_IDLE = 'ov.idle'`, `KEY_OV_STEPS = 'ov.steps'`, `KEY_OV_RUNNING = 'ov.running'`, `KEY_OV_NOTICE = 'ov.notice'`, `KEY_OV_BUSY = 'ov.busy'`, `KEY_OV_EXPANDED = 'ov.expanded'`, `KEY_OV_MODEL = 'ov.model'`
  - OverlayService accepts `want.parameters.invoke === true` from `com.ohos.systemui` or our own bundle → `openSheet()` (Stage 4 uses this).

- [ ] **Step 1: Failing test** – `OrbGeometry.test.ets`:
```ts
import { describe, expect, it } from '@ohos/hypium';
import { snapOrb } from '../../../main/ets/overlay/OrbGeometry';

export default function orbGeometryTest() {
  describe('OrbGeometry.snapOrb', () => {
    // 1080x2340 screen, 180 px orb, 24 px margin, 120 px status bar, 150 px navigation bar
    it('snaps to the nearer side edge', 0, () => {
      expect(snapOrb(100, 1000, 180, 1080, 2340, 24, 120, 150).x).assertEqual(24);
      expect(snapOrb(700, 1000, 180, 1080, 2340, 24, 120, 150).x).assertEqual(876);
    });

    it('keeps it below the status bar and above the navigation bar', 0, () => {
      expect(snapOrb(700, -400, 180, 1080, 2340, 24, 120, 150).y).assertEqual(144);
      expect(snapOrb(700, 5000, 180, 1080, 2340, 24, 120, 150).y).assertEqual(1986);
      expect(snapOrb(700, 1000, 180, 1080, 2340, 24, 120, 150).y).assertEqual(1000);
    });

    it('handles an orb dropped half off-screen', 0, () => {
      const p = snapOrb(-120, 1000, 180, 1080, 2340, 24, 120, 150);
      expect(p.x).assertEqual(24);
    });

    it('never goes above the top inset on a tiny screen', 0, () => {
      expect(snapOrb(0, 50, 180, 300, 300, 24, 120, 150).y).assertEqual(144);
    });
  });
}
```
Run `.\scripts\test.ps1` → fails (missing module).

- [ ] **Step 2: `overlay/OrbGeometry.ets`**
```ts
/** Where the floating orb settles after a drag (all values in px). */
export interface OrbPoint {
  x: number;
  y: number;
}

/** Snaps the orb to the nearer side edge and keeps it between the status bar and the navigation bar. */
export function snapOrb(x: number, y: number, size: number, screenW: number, screenH: number, margin: number,
  topInset: number, bottomInset: number): OrbPoint {
  const nx = x + size / 2 < screenW / 2 ? margin : screenW - size - margin;
  const minY = topInset + margin;
  const maxY = Math.max(minY, screenH - bottomInset - size - margin);
  return { x: nx, y: Math.min(Math.max(y, minY), maxY) };
}
```
Run tests → OrbGeometry passes.

- [ ] **Step 3: Manifest, ACL, pages**
  - `module.json5` `requestPermissions` add `{ "name": "ohos.permission.SYSTEM_FLOAT_WINDOW" }`.
  - `module.json5` `extensionAbilities` add:
    ```json5
      {
        "name": "OverlayService",
        "srcEntry": "./ets/overlay/OverlayService.ets",
        "type": "service",
        // SystemUI starts it on long-press Home (Stage 4); the service checks the caller
        "exported": true
      }
    ```
  - `signing/profile-template.json` `allowed-acls` add `"ohos.permission.SYSTEM_FLOAT_WINDOW"`.
  - `main_pages.json` src add `"pages/OverlayOrb"`.

- [ ] **Step 4: `overlay/OverlayController.ets` (orb part)**
```ts
/**
 * The assistant overlay: floating orb, task sheet, status pill and edge glow, each its own TYPE_FLOAT window.
 * Lives in the OverlayService process; the pages read its state from AppStorage and call it back.
 * Windows that only show status are not focusable, so the app being operated stays the active window
 * that the agent reads (getRootInActiveWindow).
 */
import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AgentClient } from '../common/AgentClient';
import { EVT_STATUS, EVT_UI_VISIBLE, subscribeEvents, unsubscribeEvents } from '../common/Bridge';
import { registerFonts } from '../common/Fonts';
import { StatusTracker } from '../common/StatusTracker';
import { buildTimeline } from '../common/Timeline';
import { snapOrb } from './OrbGeometry';

const DOMAIN = 0x0A12;
const TAG = 'Overlay';

export const KEY_OV_IDLE = 'ov.idle';
export const KEY_OV_STEPS = 'ov.steps';
export const KEY_OV_RUNNING = 'ov.running';
export const KEY_OV_NOTICE = 'ov.notice';
export const KEY_OV_BUSY = 'ov.busy';
export const KEY_OV_EXPANDED = 'ov.expanded';
export const KEY_OV_MODEL = 'ov.model';

const ORB_VP = 64;
const MARGIN_VP = 8;
const TOP_INSET_VP = 40;
const BOTTOM_INSET_VP = 56;
const IDLE_MS = 3000;

export class OverlayController {
  private static instance: OverlayController | undefined = undefined;
  private ctx: common.ServiceExtensionContext | undefined = undefined;
  private orb: window.Window | undefined = undefined;
  private tracker: StatusTracker = new StatusTracker();
  client: AgentClient = new AgentClient(this.tracker);
  private subs: commonEventManager.CommonEventSubscriber[] = [];
  private showOrb: boolean = true;
  private appVisible: boolean = false;
  private wasRunning: boolean = false;
  private screenW: number = 0;
  private screenH: number = 0;
  private density: number = 1;
  private orbX: number = 0;
  private orbY: number = 0;
  private dragX: number = 0;
  private dragY: number = 0;
  private dragOrbX: number = 0;
  private dragOrbY: number = 0;
  private idleTimer: number = -1;

  static get(): OverlayController {
    if (OverlayController.instance === undefined) {
      OverlayController.instance = new OverlayController();
    }
    return OverlayController.instance;
  }

  px(vp: number): number {
    return Math.round(vp * this.density);
  }

  async start(ctx: common.ServiceExtensionContext, showOrb: boolean, appVisible: boolean): Promise<void> {
    if (this.ctx !== undefined) {
      return;
    }
    this.ctx = ctx;
    this.showOrb = showOrb;
    this.appVisible = appVisible;
    const d = display.getDefaultDisplaySync();
    this.screenW = d.width;
    this.screenH = d.height;
    this.density = d.densityPixels;
    this.orbX = this.screenW - this.px(ORB_VP) - this.px(MARGIN_VP);
    this.orbY = Math.round(this.screenH * 0.6);
    this.subs.push(await subscribeEvents([EVT_STATUS], (e: string, data: string) => this.onStatus(data)));
    this.subs.push(await subscribeEvents([EVT_UI_VISIBLE], (e: string, data: string) => this.onAppVisible(data === '1')));
    this.client.sync();
    await this.updateOrb();
  }

  shutdown(): void {
    for (const s of this.subs) {
      unsubscribeEvents(s);
    }
    this.subs = [];
    this.orb?.destroyWindow();
    this.orb = undefined;
    this.ctx = undefined;
  }

  /** Creates a float window showing `page`, transparent outside the page's own shapes. */
  async createWindow(name: string, page: string, w: number, h: number, x: number, y: number,
    focusable: boolean): Promise<window.Window> {
    const config: window.Configuration = { name: name, windowType: window.WindowType.TYPE_FLOAT, ctx: this.ctx };
    const win = await window.createWindow(config);
    await win.setUIContent(page);
    win.setWindowBackgroundColor('#00000000');
    await win.setWindowFocusable(focusable);
    await win.resize(w, h);
    await win.moveWindowTo(x, y);
    registerFonts(win.getUIContext());
    return win;
  }

  /** Orb visible when: the switch is on, our app is not in front, and no sheet or pill is showing. */
  protected orbWanted(): boolean {
    return this.showOrb && !this.appVisible;
  }

  async updateOrb(): Promise<void> {
    const want = this.orbWanted();
    if (want && this.orb === undefined) {
      this.orb = await this.createWindow('oa.orb', 'pages/OverlayOrb', this.px(ORB_VP), this.px(ORB_VP),
        this.orbX, this.orbY, false);
    }
    if (this.orb === undefined) {
      return;
    }
    if (want) {
      await this.orb.showWindow();
      this.wake();
    } else {
      this.orb.minimize();
    }
  }

  private onAppVisible(visible: boolean): void {
    this.appVisible = visible;
    this.updateOrb().catch((e: Error) => hilog.error(DOMAIN, TAG, 'orb: %{public}s', e.message));
  }

  private onStatus(data: string): void {
    if (!this.tracker.apply(data)) {
      return;
    }
    AppStorage.setOrCreate(KEY_OV_STEPS, buildTimeline(this.tracker.entries));
    AppStorage.setOrCreate<boolean>(KEY_OV_RUNNING, this.tracker.running);
    this.wasRunning = this.tracker.running;
  }

  /** Full opacity now, fades back to idle after a few seconds. */
  wake(): void {
    AppStorage.setOrCreate<boolean>(KEY_OV_IDLE, false);
    clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => AppStorage.setOrCreate<boolean>(KEY_OV_IDLE, true), IDLE_MS);
  }

  orbDragStart(displayX: number, displayY: number): void {
    this.dragX = displayX;
    this.dragY = displayY;
    this.dragOrbX = this.orbX;
    this.dragOrbY = this.orbY;
    this.wake();
  }

  /** displayX/Y are in vp relative to the screen, so they stay valid while the window moves under the finger. */
  orbDragMove(displayX: number, displayY: number): void {
    this.orbX = this.dragOrbX + this.px(displayX - this.dragX);
    this.orbY = this.dragOrbY + this.px(displayY - this.dragY);
    this.orb?.moveWindowTo(this.orbX, this.orbY);
  }

  orbDragEnd(): void {
    const p = snapOrb(this.orbX, this.orbY, this.px(ORB_VP), this.screenW, this.screenH, this.px(MARGIN_VP),
      this.px(TOP_INSET_VP), this.px(BOTTOM_INSET_VP));
    this.orbX = p.x;
    this.orbY = p.y;
    this.orb?.moveWindowTo(p.x, p.y);
    this.wake();
  }

  /** Task 10 replaces this with the real sheet. */
  openSheet(): void {
    hilog.info(DOMAIN, TAG, 'openSheet');
  }
}
```
If `minimize()` does not hide a TYPE_FLOAT window on the emulator, use `hide()` (system API) instead and note it.

- [ ] **Step 5: `overlay/OverlayService.ets`**
```ts
/** Hosts the assistant overlay. Started by the app (orb switch on) or by SystemUI on long-press Home. */
import { ServiceExtensionAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OWN_BUNDLE, SYSTEMUI_BUNDLE } from '../common/Bridge';
import { loadShowOrb } from '../common/Settings';
import { OverlayController } from './OverlayController';

const CALLER_BUNDLE = 'ohos.aafwk.param.callerBundleName';

export default class OverlayService extends ServiceExtensionAbility {
  onCreate(want: Want): void {
    const fromApp = want.parameters?.['fromApp'] === true;
    OverlayController.get().start(this.context, loadShowOrb(this.context), fromApp)
      .catch((e: Error) => hilog.error(0x0A12, 'Overlay', 'start failed: %{public}s', e.message));
  }

  onRequest(want: Want, startId: number): void {
    const caller = want.parameters?.[CALLER_BUNDLE];
    if (want.parameters?.['invoke'] === true && (caller === SYSTEMUI_BUNDLE || caller === OWN_BUNDLE)) {
      OverlayController.get().openSheet();
    }
  }

  onDestroy(): void {
    OverlayController.get().shutdown();
  }
}
```
Note: `start` is async and `onRequest` follows `onCreate` right away; Task 10's `openSheet` must await the controller's ready promise (see there).

- [ ] **Step 6: `pages/OverlayOrb.ets`**
```ts
import { OaMark } from '../components/OaMark';
import { KEY_OV_IDLE, OverlayController } from '../overlay/OverlayController';

@Entry
@Component
struct OverlayOrb {
  @StorageProp(KEY_OV_IDLE) idle: boolean = false;

  build() {
    Stack() {
      Stack() {
        OaMark({ size: 40, spinning: false })
      }
      .width(52)
      .height(52)
      .borderRadius(26)
      .backgroundColor($r('app.color.surface'))
      .shadow({ radius: 12, color: '#33000000', offsetY: 3 })
    }
    .width('100%')
    .height('100%')
    .opacity(this.idle ? 0.55 : 1)
    .accessibilityText('Open Oniro Agent')
    .gesture(GestureGroup(GestureMode.Exclusive,
      TapGesture().onAction(() => OverlayController.get().openSheet()),
      PanGesture({ distance: 4 })
        .onActionStart((e: GestureEvent) => {
          OverlayController.get().orbDragStart(e.fingerList[0].displayX, e.fingerList[0].displayY);
        })
        .onActionUpdate((e: GestureEvent) => {
          OverlayController.get().orbDragMove(e.fingerList[0].displayX, e.fingerList[0].displayY);
        })
        .onActionEnd(() => OverlayController.get().orbDragEnd())
    ))
  }
}
```
If `FingerInfo.displayX` is missing in the API 20 SDK, use `globalX/globalY` and check on device that dragging tracks the finger (if it jitters, the window-relative coordinates are moving with the window; then accumulate `e.offsetX` deltas instead).

- [ ] **Step 7: EntryAbility starts the service and reports visibility** – in `EntryAbility.ets`:
```ts
  onForeground(): void {
    publishEvent(EVT_UI_VISIBLE, '1').catch(() => {});
  }

  onBackground(): void {
    publishEvent(EVT_UI_VISIBLE, '0').catch(() => {});
  }
```
and at the end of `onCreate`:
```ts
    if (loadShowOrb(this.context)) {
      const overlay: Want = { bundleName: OWN_BUNDLE, abilityName: OVERLAY_ABILITY, parameters: { 'fromApp': true } };
      this.context.startServiceExtensionAbility(overlay).catch((err: Error) => {
        hilog.warn(DOMAIN, 'testTag', 'overlay not started: %{public}s', err.message);
      });
    }
```
(imports: `EVT_UI_VISIBLE`, `OWN_BUNDLE`, `publishEvent` from Bridge; `loadShowOrb`, `OVERLAY_ABILITY` from Settings.)

- [ ] **Step 8: Device check**

Build, open the app, press Home. Screenshots: `orb-home` (orb on the right edge at ~60% height), drag it to the left half and release → `orb-left` (snapped to the left edge), wait 3 s → `orb-idle` (faded). Open Settings → switch off "Show Oniro Agent over other apps", go Home → `orb-off` (no orb). Switch on again. Tap the orb → `hilog -x | findstr Overlay` shows `openSheet`.
Run `.\scripts\test.ps1` → 0 failures.

- [ ] **Step 9: ARCHITECTURE.md** – add a bullet: `**Overlay**: OverlayService (ServiceExtensionAbility) owns TYPE_FLOAT windows: the orb, the task sheet, the status pill and the edge glow. Status windows are not focusable, so the app the agent operates stays the active window. It talks to the agent service over the same common events as the app.`

- [ ] **Step 10: Checkpoint** – (only with user OK) commit "Add the floating orb".

### Task 10: Sheet, pill, glow and overlay runs

**Files:**
- Modify: `entry/src/main/ets/overlay/OverlayController.ets`
- Create: `entry/src/main/ets/pages/OverlaySheet.ets`, `pages/OverlayPill.ets`, `pages/OverlayGlow.ets`
- Modify: `main_pages.json`, `PhoneAgent/README.md`

**Interfaces:**
- Consumes: Task 9 controller, `Composer`, `StepList`, `OaMark`, `checkRun`, `currentStepText`, `modelSummary`, `findProvider`, `loadSettings`, `ORIGIN_OVERLAY`, `OWN_BUNDLE`.
- Produces: `OverlayController.closeSheet(): void`, `run(task: string): Promise<void>`, `stop(): void`, `togglePill(): void`, `openApp(): void`.

- [ ] **Step 1: Pages list** – `main_pages.json` add `"pages/OverlaySheet"`, `"pages/OverlayPill"`, `"pages/OverlayGlow"`.

- [ ] **Step 2: Controller additions** – add fields and methods to `OverlayController`:
```ts
const SHEET_H_VP = 300;
const PILL_W_VP = 360;
const PILL_H_VP = 64;
const PILL_EXPANDED_H_VP = 440;
const RESULT_MS = 4000;

  private sheet: window.Window | undefined = undefined;
  private pill: window.Window | undefined = undefined;
  private glow: window.Window | undefined = undefined;
  private sheetY: number = 0;
  private resultTimer: number = -1;
  private ready: Promise<void> = Promise.resolve();
```
- `start()`: wrap its body so `this.ready` is the promise of the whole start (`this.ready = this.doStart(...)`; `await this.ready`).
- `orbWanted()` becomes `this.showOrb && !this.appVisible && this.sheet === undefined && this.pill === undefined`.
- `onStatus` additions after the AppStorage writes:
```ts
    if (this.tracker.running && this.sheet === undefined && !this.appVisible) {
      this.showPill();
    }
    if (this.wasRunning && !this.tracker.running) {
      clearTimeout(this.resultTimer);
      this.resultTimer = setTimeout(() => {
        if (AppStorage.get<boolean>(KEY_OV_EXPANDED) !== true) {
          this.hidePill();
        }
      }, RESULT_MS);
    }
```
(keep `this.wasRunning = this.tracker.running;` last). In `onAppVisible`, when `visible` is true also call `this.hidePill()` (the app shows the log itself).
- New methods:
```ts
  openSheet(): void {
    this.ready.then(() => this.doOpenSheet())
      .catch((e: Error) => hilog.error(DOMAIN, TAG, 'sheet: %{public}s', e.message));
  }

  private async doOpenSheet(): Promise<void> {
    if (this.tracker.running) {
      await this.showPill();
      this.togglePill();
      return;
    }
    if (this.sheet !== undefined || this.ctx === undefined) {
      return;
    }
    const s = loadSettings(this.ctx, true);
    AppStorage.setOrCreate<string>(KEY_OV_MODEL, modelSummary(s.provider, s.model, s.effort));
    AppStorage.setOrCreate<string>(KEY_OV_NOTICE, '');
    AppStorage.setOrCreate<boolean>(KEY_OV_BUSY, false);
    const h = this.px(SHEET_H_VP);
    this.sheetY = this.screenH - h;
    this.sheet = await this.createWindow('oa.sheet', 'pages/OverlaySheet', this.screenW, h, 0, this.sheetY, true);
    this.sheet.on('touchOutside', () => this.closeSheet());
    this.sheet.on('keyboardHeightChange', (kh: number) => {
      this.sheet?.moveWindowTo(0, this.sheetY - kh);
    });
    await this.sheet.showWindow();
    await this.updateOrb();
  }

  closeSheet(): void {
    const s = this.sheet;
    this.sheet = undefined;
    s?.destroyWindow();
    this.updateOrb().catch(() => {});
  }

  async run(task: string): Promise<void> {
    if (this.ctx === undefined) {
      return;
    }
    const s = loadSettings(this.ctx, true);
    const p = findProvider(s.provider);
    const problem = checkRun(p === undefined ? s.provider : p.label, s.apiKey, s.model, task);
    if (problem.length > 0) {
      AppStorage.setOrCreate<string>(KEY_OV_NOTICE, problem);
      return;
    }
    AppStorage.setOrCreate<string>(KEY_OV_NOTICE, '');
    AppStorage.setOrCreate<boolean>(KEY_OV_BUSY, true);
    const req: RunRequest = {
      task: task.trim(), provider: s.provider, model: s.model, effort: s.effort, origin: ORIGIN_OVERLAY
    };
    const msg = await this.client.run(req);
    AppStorage.setOrCreate<boolean>(KEY_OV_BUSY, false);
    if (msg.length > 0) {
      AppStorage.setOrCreate<string>(KEY_OV_NOTICE, msg); // the sheet stays open (Review Focus 4)
      return;
    }
    this.closeSheet();
    await this.showPill();
  }

  stop(): void {
    this.client.stop();
  }

  async showPill(): Promise<void> {
    if (this.pill === undefined) {
      const w = Math.min(this.screenW - this.px(32), this.px(PILL_W_VP));
      this.pill = await this.createWindow('oa.pill', 'pages/OverlayPill', w, this.px(PILL_H_VP),
        Math.round((this.screenW - w) / 2), this.px(TOP_INSET_VP), false);
    }
    AppStorage.setOrCreate<boolean>(KEY_OV_EXPANDED, false);
    await this.pill.showWindow();
    await this.showGlow();
    await this.updateOrb();
  }

  hidePill(): void {
    clearTimeout(this.resultTimer);
    const p = this.pill;
    this.pill = undefined;
    p?.destroyWindow();
    const g = this.glow;
    this.glow = undefined;
    g?.destroyWindow();
    this.updateOrb().catch(() => {});
  }

  togglePill(): void {
    if (this.pill === undefined) {
      return;
    }
    const expanded = AppStorage.get<boolean>(KEY_OV_EXPANDED) !== true;
    AppStorage.setOrCreate<boolean>(KEY_OV_EXPANDED, expanded);
    this.pill.resize(Math.min(this.screenW - this.px(32), this.px(PILL_W_VP)),
      this.px(expanded ? PILL_EXPANDED_H_VP : PILL_H_VP));
    if (!expanded && !this.tracker.running) {
      this.hidePill();
    }
  }

  openApp(): void {
    this.hidePill();
    this.ctx?.startAbility({ bundleName: OWN_BUNDLE, abilityName: 'EntryAbility' });
  }

  private async showGlow(): Promise<void> {
    if (this.glow !== undefined) {
      return;
    }
    this.glow = await this.createWindow('oa.glow', 'pages/OverlayGlow', this.screenW, this.screenH, 0, 0, false);
    await this.glow.setWindowTouchable(false);
    await this.glow.showWindow();
  }
```
(imports: `findProvider`, `modelSummary` from Providers; `loadSettings` from Settings; `checkRun`; `ORIGIN_OVERLAY`, `OWN_BUNDLE`, `RunRequest` from Bridge. `shutdown()` also calls `this.closeSheet(); this.hidePill();`.)

- [ ] **Step 3: `pages/OverlaySheet.ets`**
```ts
import { DISPLAY_FONT } from '../common/Fonts';
import { Composer } from '../components/Composer';
import { OaMark } from '../components/OaMark';
import { KEY_OV_BUSY, KEY_OV_MODEL, KEY_OV_NOTICE, OverlayController } from '../overlay/OverlayController';

@Entry
@Component
struct OverlaySheet {
  @State task: string = '';
  @StorageProp(KEY_OV_NOTICE) notice: string = '';
  @StorageProp(KEY_OV_BUSY) busy: boolean = false;
  @StorageProp(KEY_OV_MODEL) model: string = '';

  build() {
    Column({ space: 14 }) {
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor($r('app.color.line'))
      Row({ space: 10 }) {
        OaMark({ size: 28, spinning: this.busy })
        Text('What should I do?')
          .fontFamily(DISPLAY_FONT)
          .fontSize(22)
          .fontColor($r('app.color.ink'))
      }
      .width('100%')
      Composer({
        text: $task,
        running: false,
        canRun: !this.busy,
        onRun: () => {
          OverlayController.get().run(this.task);
        },
        onStop: () => {}
      })
      if (this.notice.length > 0) {
        Text(this.notice)
          .fontSize(14)
          .fontColor($r('app.color.danger'))
          .width('100%')
      }
      Text(this.busy ? 'Starting…' : this.model)
        .fontSize(13)
        .fontColor($r('app.color.ink_muted'))
        .width('100%')
    }
    .padding({ left: 16, right: 16, top: 10, bottom: 24 })
    .width('100%')
    .height('100%')
    .borderRadius({ topLeft: 28, topRight: 28 })
    .backgroundColor($r('app.color.surface'))
    .shadow({ radius: 24, color: '#40000000', offsetY: -4 })
  }
}
```

- [ ] **Step 4: `pages/OverlayPill.ets`**
```ts
import { LOG_ERROR } from '../agent/AgentLoop';
import { currentStepText, Step } from '../common/Timeline';
import { OaMark } from '../components/OaMark';
import { StepList } from '../components/StepList';
import { KEY_OV_EXPANDED, KEY_OV_RUNNING, KEY_OV_STEPS, OverlayController } from '../overlay/OverlayController';

@Entry
@Component
struct OverlayPill {
  @StorageProp(KEY_OV_STEPS) steps: Step[] = [];
  @StorageProp(KEY_OV_RUNNING) running: boolean = false;
  @StorageProp(KEY_OV_EXPANDED) expanded: boolean = false;

  private failed(): boolean {
    return this.steps.length > 0 && this.steps[this.steps.length - 1].kind === LOG_ERROR;
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        OaMark({ size: 28, spinning: this.running })
        Text(this.running ? currentStepText(this.steps) : (currentStepText(this.steps) || 'Done'))
          .fontSize(15)
          .fontColor(this.failed() ? $r('app.color.danger') : $r('app.color.ink'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .height(40)
      .width('100%')
      .onClick(() => OverlayController.get().togglePill())
      if (this.expanded) {
        Column() {
          StepList({ steps: this.steps, running: this.running })
        }
        .layoutWeight(1)
        Row({ space: 8 }) {
          Button('Open app')
            .layoutWeight(1)
            .backgroundColor($r('app.color.bg'))
            .fontColor($r('app.color.ink'))
            .onClick(() => OverlayController.get().openApp())
          if (this.running) {
            Button('Stop')
              .layoutWeight(1)
              .backgroundColor($r('app.color.danger'))
              .fontColor($r('app.color.on_orb'))
              .onClick(() => OverlayController.get().stop())
          }
        }
        .width('100%')
      }
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .width('100%')
    .height('100%')
    .borderRadius(this.expanded ? 24 : 32)
    .backgroundColor($r('app.color.surface'))
    .shadow({ radius: 16, color: '#33000000', offsetY: 4 })
  }
}
```

- [ ] **Step 5: `pages/OverlayGlow.ets`** (thin gradient edges; the window ignores touches)
```ts
@Entry
@Component
struct OverlayGlow {
  @State breathe: number = 0.5;

  aboutToAppear(): void {
    this.getUIContext().animateTo({ duration: 1600, iterations: -1, playMode: PlayMode.Alternate }, () => {
      this.breathe = 1;
    });
  }

  @Builder
  edge(vertical: boolean, align: Alignment) {
    Row()
      .width(vertical ? 4 : '100%')
      .height(vertical ? '100%' : 4)
      .linearGradient({
        angle: vertical ? 180 : 90,
        colors: [[$r('app.color.orb_teal'), 0], [$r('app.color.orb_violet'), 0.5], [$r('app.color.orb_coral'), 1]]
      })
      .align(align)
  }

  build() {
    Stack() {
      Column() { this.edge(false, Alignment.Top) }.width('100%').height('100%').justifyContent(FlexAlign.Start)
      Column() { this.edge(false, Alignment.Bottom) }.width('100%').height('100%').justifyContent(FlexAlign.End)
      Row() { this.edge(true, Alignment.Start) }.width('100%').height('100%').justifyContent(FlexAlign.Start)
      Row() { this.edge(true, Alignment.End) }.width('100%').height('100%').justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height('100%')
    .opacity(this.breathe)
    .hitTestBehavior(HitTestMode.None)
  }
}
```
If touches do not pass through the full-screen glow window on the emulator even with `setWindowTouchable(false)`, drop the glow (delete `showGlow` and the page) and note it in `ARCHITECTURE.md`; the pill alone satisfies D7.

- [ ] **Step 6: Build and look** – screenshots: tap orb → `sheet-light` (sheet at the bottom, keyboard pushes it up when the field is focused: `sheet-keyboard`); tap outside → sheet closes, orb back.

- [ ] **Step 7: Overlay run (happy path)** – with a valid key: open Messages manually, tap orb, type `Text Babcia that I will come to her birthday`, Run. Screenshots every ~5 s: `pill-running-1..n` (pill at top with turning ring and the current step, edges glowing, Messages fully usable underneath), `pill-expanded` (tap pill: steps + Open app + Stop), `pill-done` (result shown ~4 s, then pill and glow disappear and the orb comes back). The app must **not** jump to the front at the end (origin overlay).

- [ ] **Step 8: Stop from the pill** – start a longer task, expand the pill, tap Stop → log ends with the stop entry; pill shows it, then collapses.

- [ ] **Step 9: Review Focus checks**
  (a) During the run in Step 7: `& $hdc shell "hilog -x" | findstr AgentA11y` → every screen read starts with `App: com.ohos.mms` (or the launcher), never `com.hackyeah.phoneagent`.
  (b) `& $hdc shell "aa force-stop com.hackyeah.phoneagent"` is too blunt (kills the overlay too); instead disable the service from Settings → nothing; simplest: `& $hdc shell "accessibility disable -a AgentA11y -b com.hackyeah.phoneagent"` if available, else kill the extension process by pid (`ps -ef | grep phoneagent`, kill the `:accessibility` one). Then Run from the sheet → it shows "Starting…", then either recovers (service restarted) or shows the error message **in the sheet**; no pill appears for a run that never started.
  (c) A task whose thoughts are long: pill line ends in "…", expanded list folds the thought to 2 lines.

- [ ] **Step 10: README** – add to "Use": `Outside the app, tap the floating Oniro Agent orb (drag it to either edge) to give a task without leaving the app you are in. Progress shows in a pill at the top; tap it for the steps, Stop, or to open the app. Turn the orb off in Settings.`

- [ ] **Step 11: Tests** – `.\scripts\test.ps1` → 0 failures.

- [ ] **Step 12: Checkpoint** – (only with user OK) commit "Add the overlay sheet and status pill".

---

## Stage 4: SystemUI long-press Home spike (timebox: 2 h, stop at any failed gate)

### Task 11: Patch the navigation bar's Home button

**Files (outside this repo, in a scratch clone):**
- Modify: `applications_systemui/features/navigationservice/src/main/ets/com/ohos/navigationservice/KeyCodeEvent.ts`
- Modify (this repo): `PhoneAgent/ARCHITECTURE.md`, `PhoneAgent/README.md`, `PhoneAgent/AI_WORKFLOW.md` (record the outcome either way)

**Interfaces:**
- Consumes: `OverlayService` accepting `invoke: true` from `com.ohos.systemui` (Task 9 Step 5).

Background (researched 2026-10-03): in stock OpenHarmony SystemUI the soft Home button sends no key event; on touch-up `KeyCodeEvent.sendHomeKeyEvent()` calls `AbilityManager.startServiceExtensionAbility(...)` on the launcher. There is no long-press handler, so an app cannot observe a long press. Physical-key long presses (`inputConsumer.on('key', { finalKeyDownDuration })`, system API) do not help: the emulator has no Home key. Accessibility `onKeyEvent` is deprecated since API 12 and also sees physical keys only.

- [ ] **Gate 1 (10 min): is it the legacy SystemUI navigation bar?** From Task 0 Step 5 notes: `com.ohos.systemui` present and a 3-button bar on screen → continue. `com.ohos.sceneboard` drawing the bar, or a gesture bar → **stop**; record "Not possible on this image: navigation is SceneBoard" in ARCHITECTURE.md and finish.

- [ ] **Gate 2 (15 min): what is installed?**
Run: `& $hdc shell "bm dump -n com.ohos.systemui"` → note `versionCode`, `hapPath`/`codePath` of every module, `appId`/`fingerprint`, `appProvisionType`.
Back up the HAPs: `& $hdc file recv <each hapPath> build\systemui-backup\`.
Continue only if the signature looks like the public OpenHarmony test key (the `appId` starts with `com.ohos.systemui_` + the same base64 key as other preinstalled `com.ohos.*` apps signed with `OpenHarmonyApplication.pem`); otherwise stop and record.

- [ ] **Step 1: Clone the matching source**
```powershell
git clone --depth 1 -b OpenHarmony-v6.1-Release https://gitcode.com/openharmony/applications_systemui.git "$env:TEMP\oa-systemui"
```
(if that branch does not exist, list branches with `git ls-remote --heads https://gitcode.com/openharmony/applications_systemui.git` and pick the 6.x one closest to the emulator; `master` as last resort.)

- [ ] **Step 2: Patch `KeyCodeEvent.ts`** – add at module level:
```ts
const ASSISTANT_LONG_PRESS_MS = 600;
let homeTimer: number = -1;
let homeLongPressed: boolean = false;
```
replace the `case Constants.KEYCODE_HOME:` block with:
```ts
      case Constants.KEYCODE_HOME:
        if (eventType === TouchType.Down) {
          homeLongPressed = false;
          homeTimer = setTimeout(() => {
            homeLongPressed = true;
            this.startAssistant();
          }, ASSISTANT_LONG_PRESS_MS);
        } else if (eventType === TouchType.Up || eventType === TouchType.Cancel) {
          clearTimeout(homeTimer);
          if (eventType === TouchType.Up && !homeLongPressed) {
            Log.showDebug(TAG, 'sendKeyEvent : KEY_UP');
            this.sentEvnt();
            this.sendHomeKeyEvent();
          }
        }
        break;
```
and add the method:
```ts
  /** Long-press Home: open the Oniro Agent task sheet over the current app. */
  private startAssistant() {
    Log.showInfo(TAG, 'startAssistant');
    AbilityManager.startServiceExtensionAbility(AbilityManager.getContext(AbilityManager.ABILITY_NAME_NAVIGATION_BAR), {
      bundleName: 'com.hackyeah.phoneagent',
      abilityName: 'OverlayService',
      parameters: { invoke: true }
    });
  }
```

- [ ] **Gate 3 (45 min): build + sign** – build all HAPs of the bundle with the repo's own instructions (its README / `build-profile.json5`; open it in DevEco if hvigorw fails). Bump `versionCode` in its `AppScope/app.json5` above the installed one. Sign every HAP with the repo's `signature/*.p7b` profile and the SDK's `OpenHarmony.p12` (same `hap-sign-tool` call as `scripts/sign.ps1`, but `-profileFile` = that `.p7b`, `-appCertFile` = SDK `OpenHarmonyApplication.pem`). If it does not build within 45 min → stop and record.

- [ ] **Gate 4 (20 min): install**
Run: `& $hdc install -r <all signed systemui haps>`
Expected: `install bundle successfully`. If it fails with a signature or "system app cannot be updated" error, one attempt: `& $hdc shell "mount -o rw,remount /"`, push the HAPs over the `hapPath`s from Gate 2, `& $hdc shell reboot`. If the nav bar is missing after reboot, restore the backup HAPs the same way and stop.

- [ ] **Step 3: Verify**
  - Short tap Home → launcher (unchanged).
  - In Messages, hold Home ~1 s → the Oniro Agent sheet slides up over Messages; screenshot `home-longpress`.
  - Turn the orb off in Settings, go to any app, hold Home → sheet still appears (service started on demand).
  - `& $hdc shell "hilog -x" | findstr "startAssistant Overlay"` shows the call.

- [ ] **Step 4: Record the outcome** (always, also when a gate stopped the spike)
  - `ARCHITECTURE.md`: a bullet "Long-press Home: …" with what works or which gate failed and why.
  - `README.md`: if it works, a short "Optional: long-press Home" setup section with the exact build/sign/install commands used; otherwise one line saying the orb is the way to open the agent.
  - `AI_WORKFLOW.md`: one line on the research (SystemUI source reading, why apps cannot hook the soft Home key).

- [ ] **Step 5: Checkpoint** – (only with user OK) commit "Document the long-press Home spike" (+ a `patches/systemui-longpress-home.patch` file made with `git -C $env:TEMP\oa-systemui diff > PhoneAgent/patches/systemui-longpress-home.patch` if it worked).

---

## Final verification

- [ ] `.\scripts\test.ps1` → `Failure: 0, Error: 0`, Pass = 51 + all new tests.
- [ ] Fresh install (`hdc uninstall com.hackyeah.phoneagent`, `.\scripts\build.ps1`): launcher shows the OA icon labelled "Oniro Agent"; main screen asks for a key; Settings → key → back → Babcia task runs from the app and from the orb.
- [ ] Screenshots in `build/shots/` reviewed in light and dark.
- [ ] `rg -n "Phone Agent" PhoneAgent README.md` → only the historical handoff note.
