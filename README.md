# Oniro Agent

<p align="center">
  <a href="https://www.youtube.com/shorts/yb8SysyHY5I">
    <img src="docs/demo.gif" width="300" alt="Oniro Agent demo on the Oniro 6.1 emulator: one sentence, the agent reads Notes, creates a Calendar event and a reminder, and texts Grandma">
  </a>
  <br>
  <sub>Real run on the Oniro 6.1 emulator, sped up 2.5×. <a href="https://www.youtube.com/shorts/yb8SysyHY5I"><b>▶ Watch the full demo with sound on YouTube</b></a></sub>
</p>

HackYeah 2026, Huawei challenge. You type "text grandma that I'll come to her birthday" and an AI model does it on the phone: opens Messages, picks the contact, types, sends. Works with any app through accessibility. Only possible on OpenHarmony / Oniro (system app).

AI providers: Anthropic Claude (tested end to end), OpenAI, xAI Grok, Google Gemini (implemented and unit-tested; live endpoints checked only with an invalid key, no real keys). Model and reasoning effort are chosen in Settings; effort levels per model follow the providers' docs as of 2026-10-04 and were not checked live.

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [AI_WORKFLOW.md](AI_WORKFLOW.md)
- Ready-to-install package: [`build/phoneagent-release-signed.hap`](build/phoneagent-release-signed.hap) (see [Install the prebuilt .hap](#install-the-prebuilt-hap))



## At a glance

### Originality
- Phone agent that works in **any app** through accessibility, with no per-app integrations.
- Reads the screen as **text** (accessibility tree), not screenshots. Needs no vision model.
- Ships as a **system component** we built and signed ourselves, without modifying the OS.
- Combines **Intelligent Experiences** (AI agent) and **Human-Centric Technology** (accessibility).

### Usefulness
- **For:** people who struggle with multi-step phone UIs (older people, motor or vision impairments, busy hands).
- **Problem:** "text grandma I'll come" takes 6 steps (app → new message → contact picker → contact → text → Send). Here it takes one sentence.
- **Works today (narrow):** SMS via Messages 3/3 runs, 6 actions, ~31 s each. Settings → WLAN in 2 actions, Bluetooth on/off. (Claude models, emulator, 3 Oct.)
- Works from inside any app via the floating orb.

### Technical execution
- Architecture with diagram: [ARCHITECTURE.md](ARCHITECTURE.md). Agent loop, providers, device access and UI are separate modules, behind interfaces.
- **Error handling:**

  | What | Behaviour |
  |---|---|
  | API retries | max 3, only 429 / 5xx / network; backoff 1 → 2 → 4 s; `Retry-After` honoured up to 60 s |
  | Timeouts | connect 30 s, read 180 s |
  | 401 / 403 / 404 / billing | no retry, plain-language message ("API key was rejected…") |
  | Bad model output | every tool call validated (types, index range, enums, text ≤ 2000 chars, bundle name); errors go back to the model, nothing executed |
  | Failed action | error + current screen sent back so the model can recover |
  | Refusal / cut-off reply | nothing executed, task ends |
  | Model answers without a tool | 1 nudge, then stop |
  | Stuck | 4 actions in a row with no screen change → stop |
  | Limits | 25 model calls per task; screen ≤ 150 elements, texts ≤ 80 chars |
  | Stop | immediate, even during a pending model call |
  | Agent service not responding | pinged before each task, restarted if silent (8 s ping, 5 s ack) |
- **Tests:** 106 on-device hypium tests (`scripts/test.ps1` → `Pass: 106`): tool validation, malformed / refused / truncated responses, API errors of all 4 providers, agent loop with a scripted model, screen serializer.
- **Hygiene:** no secrets in the repo (keys stored in app-private storage, signing material generated locally and git-ignored). 8 permissions, each one used (INTERNET for the model API, 4 for accessibility / app listing / background start, SYSTEM_FLOAT_WINDOW for the orb, 2 for `set_alarm` reminders). 0 runtime dependencies, no vendor SDKs.

### Platform capabilities
| OpenHarmony API | Used for |
|---|---|
| `AccessibilityExtensionAbility` | read and operate other apps, in the background |
| `accessibility config.enableAbility` | switch the agent on from the app |
| `launcherBundleManager` + `startAbility` from background | find and open apps |
| `TYPE_FLOAT` windows + `ServiceExtensionAbility` | orb, status pill and edge glow over all apps |
| Common events | UI ↔ agent service ↔ overlay |
| `system_core` signing | the above without modifying the OS |

Does not run unchanged on any other OS.

### Demo
- Runs on the Oniro 6.1 emulator, not mockups.
- Everything here was built during the hackathon (first commit 3 Oct, 17:25).
- **Not on the emulator:** no SIM, so the SMS is not delivered. The agent taps Send and reports that sending could not be confirmed. No Bluetooth adapter either.

### Reproducibility
- Exact versions and step-by-step setup below. Native Windows, no WSL. Scripts start the emulator, build, sign, install and test.
- Commit history shows the progress. AI usage, prompts and lessons: [AI_WORKFLOW.md](AI_WORKFLOW.md).

## Versions

Windows 11 · QEMU 11.1.0 for Windows (WHPX) · Oniro emulator v6.1 · DevEco Studio 6.1.1.280 · OpenHarmony full SDK 6.0.0.48 (API 20)

## Install the prebuilt .hap

The signed release package of Oniro Agent is in the repository: **[`build/phoneagent-release-signed.hap`](build/phoneagent-release-signed.hap)**. It is signed as a system app with the public OpenHarmony test certificates, so it installs on the Oniro v6.1 emulator (or another stock OpenHarmony test image) without building anything. Start the emulator ([step 3](#3-prepare-and-start-the-oniro-emulator)), then from this directory:

```powershell
hdc install build\phoneagent-release-signed.hap
hdc shell aa start -a EntryAbility -b com.hackyeah.phoneagent
```

If another copy of Oniro Agent is installed (signed on a different computer), run `hdc uninstall com.hackyeah.phoneagent` first. The companion apps used in the demo are prebuilt next to it: `build\calendar-signed.hap`, `build\notes-signed.hap` and `build\reminders-signed.hap` (install them the same way). Then continue with [Use](#use).

## Setup

The tested setup is **Windows 11 x64**, DevEco Studio **6.1.1.280**, OpenHarmony **full SDK 6.0.0.48 / API 20**, and the **Oniro v6.1** emulator. Use a PC with hardware virtualization enabled in BIOS/UEFI; the emulator allocates 4 GB RAM. Internet access is needed for tool downloads, first-build dependencies and AI requests. Everything runs in Windows PowerShell without WSL.

### 1. Install tools and get the source

Install [DevEco Studio for Windows](https://developer.huawei.com/consumer/en/download/) in `C:\Program Files\Huawei\DevEco Studio`, including its bundled SDK/toolchains. Complete its first-run setup. The scripts use the bundled Node, Java, OHPM and Hvigor; separate Node or Java installations are unnecessary.

Clone this repository with Git for Windows, or download and extract its source ZIP. Open PowerShell **in the repository root, containing `AppScope`, `entry` and `scripts`**. This is also the directory to open in DevEco Studio. All commands below run from that directory unless stated otherwise.

Allow scripts in this terminal and make `hdc` available in it:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
$env:Path = 'C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains;' + $env:Path
```

These settings last for this PowerShell session. Repeat them after opening another terminal. If DevEco is installed elsewhere, change the PATH and pass `-DevEco '<installation directory>'` to the scripts.

### 2. Install the full OpenHarmony API 20 SDK

The app uses system APIs, so it requires the **full** OpenHarmony SDK. [Oniro's SDK guide](https://docs.oniroproject.org/application-development/environment-setup-guide/full-public-sdk/) explains obtaining and extracting the component archives.

Download [ohos-sdk-full 6.0.0.48](https://cidownload.openharmony.cn/version/Master_Version/OpenHarmony_6.0.0.48/20251122_043125/version-Master_Version-OpenHarmony_6.0.0.48-20251122_043125-ohos-sdk-full.tar.gz). If that archived artifact is unavailable, use the [OpenHarmony build portal](https://dcp.openharmony.cn/) to find a full SDK for **API 20**. Extract the `.tar.gz`, locate `ohos-sdk\windows` inside it, then extract **each component ZIP** into `$env:LOCALAPPDATA\OpenHarmony\Sdk\20`. The result must contain the component directories directly under `20`:

```text
%LOCALAPPDATA%\OpenHarmony\Sdk\20\
  ets\
  js\
  native\
  previewer\
  toolchains\
```

For example, these checks must return `True`:

```powershell
Test-Path "$env:LOCALAPPDATA\OpenHarmony\Sdk\20\ets\api\@ohos.bundle.launcherBundleManager.d.ts"
Test-Path "$env:LOCALAPPDATA\OpenHarmony\Sdk\20\toolchains\lib\hap-sign-tool.jar"
Test-Path "$env:LOCALAPPDATA\OpenHarmony\Sdk\20\toolchains\lib\OpenHarmony.p12"
```

In DevEco Studio, select this **SDK root** in the OpenHarmony SDK settings: `%LOCALAPPDATA%\OpenHarmony\Sdk` (the directory containing `20`). Let the IDE generate its own `local.properties`. The command-line scripts use the same root by default; for another location pass `-Sdk 'D:\OpenHarmony\Sdk'` to build/test scripts. The SDK argument points to the parent of `20`.

### 3. Prepare and start the Oniro emulator

In **administrator PowerShell**, enable Windows Hypervisor Platform, then reboot when requested:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
```

Install QEMU for Windows (tested with 11.1.0) in `C:\Program Files\qemu`:

```powershell
winget install --exact --id SoftwareFreedomConservancy.QEMU
```

Download the [Oniro v6.1 emulator release](https://github.com/eclipse-oniro4openharmony/device_board_oniro/releases/tag/v6.1), about 1.45 GB compressed / 5.5 GB extracted. From your regular project PowerShell terminal:

```powershell
$oniroDirectory = Join-Path $env:USERPROFILE 'oniro'
New-Item -ItemType Directory -Force $oniroDirectory | Out-Null
curl.exe -fL https://github.com/eclipse-oniro4openharmony/device_board_oniro/releases/download/v6.1/oniro_emulator.zip -o "$oniroDirectory\oniro_emulator.zip"
if ($LASTEXITCODE -ne 0) { throw 'Emulator download failed' }
tar.exe -xf "$oniroDirectory\oniro_emulator.zip" -C $oniroDirectory
```

Check that `%USERPROFILE%\oniro\images` contains `bzImage`, `ramdisk.img`, `updater.img`, `system.img`, `vendor.img` and `userdata.img`. Start and connect it:

```powershell
.\scripts\start-emulator.ps1
hdc list targets
```

The script waits for boot and `hdc list targets` should show `127.0.0.1:55555`. For other locations pass `-Images '<images directory>'`, `-Qemu '<QEMU directory>'` or `-DevEco '<DevEco directory>'`. To diagnose boot failures use `.\scripts\start-emulator.ps1 -Foreground`; the serial log is `%TEMP%\oniro-emulator-serial.log`. Stop it with `.\scripts\start-emulator.ps1 -Stop`. Ctrl+Alt+G releases a captured mouse.

### 4. Build, sign, install and configure the apps

With the emulator running:

```powershell
.\scripts\build.ps1
.\scripts\build-calendar.ps1
.\scripts\build-notes.ps1
.\scripts\build-reminders.ps1
.\scripts\test.ps1
```

The first build installs OHPM dependencies automatically, builds the agent and creates its signing material in `.signing`. Public OpenHarmony test certificates and the system-app profile template are included in `signing/`; you do not need a Huawei account or personal signing certificate for this Oniro image. Keep `.signing` for subsequent updates. A new checkout on another computer creates a different app certificate; installing over a copy signed elsewhere may require uninstalling that copy first, which deletes its local settings and skills. Builds using the same signing material can update in place.

The scripts install and launch **Oniro Agent**, **Calendar**, **Notes**, and **Reminders**. Grant Calendar access when asked. The Oniro image already includes Contacts and Messages; the Notes companion exposes note bodies to accessibility, and Reminders schedules actual system notifications. Open Oniro Agent, then **Settings → AI provider → API key → model**. Enter your own provider key; keys are not included in the repository. The app enables its accessibility service and shows **Agent service on**. The test suite requires the emulator but does not call paid AI APIs; a successful run reports **Pass: 106**.

Each build script accepts `-NoInstall` for build-only output. Signed HAPs are written to `build\phoneagent-signed.hap`, `build\calendar-signed.hap`, `build\notes-signed.hap`, and `build\reminders-signed.hap`. These system-app signatures target the Oniro/OpenHarmony test image; commercial HarmonyOS phones require different signing and permissions.

### 5. Run from DevEco Studio (optional)

Open this project, configure the SDK root as above, and run `.\scripts\sign.ps1 -PrepareOnly` from the project terminal once (the command-line build already does this). `hvigorfile.ts` loads the generated signing configuration. Select the connected `127.0.0.1:55555` device and use Run. If it is missing, use **Tools → IP Connection → 127.0.0.1:55555**.

To add an emulator start button under **File → Settings → Tools → External Tools**, use:

| Field | Value |
|---|---|
| Name | `Start Oniro emulator` |
| Program | `powershell.exe` |
| Arguments | `-NoProfile -ExecutionPolicy Bypass -File "$ProjectFileDir$\scripts\start-emulator.ps1"` |
| Working directory | `$ProjectFileDir$` |

Leave **Open console for tool output** enabled. For a custom SDK location, prepare signing with `.\scripts\sign.ps1 -PrepareOnly -SdkLib 'D:\OpenHarmony\Sdk\20\toolchains\lib'`; add `-DevEco` if the IDE is installed elsewhere.

## Check

- Tests: `.\scripts\test.ps1` → `Pass: 106`
- Screenshot: `.\scripts\screenshot.ps1 -Name main` → `build\shots\main.jpeg`
- System app: `hdc shell "bm dump -n com.hackyeah.phoneagent" | findstr appPrivilegeLevel` → `system_core`
- Log: `hdc shell "hilog -x" | findstr AgentA11y`

## Not ours

DevEco template, OpenHarmony SDK + public test signing certs, Oniro emulator, Bricolage Grotesque font (OFL, `entry/src/main/resources/rawfile/fonts/OFL.txt`). No runtime libraries.

## License

[Apache License 2.0](LICENSE)
