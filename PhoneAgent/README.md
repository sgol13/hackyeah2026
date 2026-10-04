# Oniro Agent

HackYeah 2026, Huawei challenge. You type "text grandma that I'll come to her birthday" and an AI model does it on the phone: opens Messages, picks the contact, types, sends. Works with any app through accessibility. Only possible on OpenHarmony / Oniro (system app).

AI providers: Anthropic Claude (tested end to end), OpenAI, xAI Grok, Google Gemini (implemented and unit-tested; live endpoints checked only with an invalid key, no real keys). Model and reasoning effort are chosen in Settings; effort levels per model follow the providers' docs as of 2026-10-04 and were not checked live.

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [AI_WORKFLOW.md](AI_WORKFLOW.md)
- Demo video: _(link on submission)_

## Versions

Windows 11 · QEMU 11.1.0 for Windows (WHPX) · Oniro emulator v6.1 · DevEco Studio 6.1.1.280 · OpenHarmony full SDK 6.0.0.48 (API 20)

## Setup

The tested setup is **Windows 11 x64**, DevEco Studio **6.1.1.280**, OpenHarmony **full SDK 6.0.0.48 / API 20**, and the **Oniro v6.1** emulator. Use a PC with hardware virtualization enabled in BIOS/UEFI; the emulator allocates 4 GB RAM. Internet access is needed for tool downloads, first-build dependencies and AI requests. Everything runs in Windows PowerShell without WSL.

### 1. Install tools and get the source

Install [DevEco Studio for Windows](https://developer.huawei.com/consumer/en/download/) in `C:\Program Files\Huawei\DevEco Studio`, including its bundled SDK/toolchains. Complete its first-run setup. The scripts use the bundled Node, Java, OHPM and Hvigor; separate Node or Java installations are unnecessary.

Clone this repository with Git for Windows, or download and extract its source ZIP. Open PowerShell **in the project directory containing `AppScope`, `entry` and `scripts`**. This is also the directory to open in DevEco Studio. All commands below run from that directory unless stated otherwise.

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
.\scripts\test.ps1
```

The first build installs OHPM dependencies automatically, builds the agent and creates its signing material in `.signing`. Public OpenHarmony test certificates and the system-app profile template are included in `signing/`; you do not need a Huawei account or personal signing certificate for this Oniro image. Keep `.signing` for subsequent updates. A new checkout on another computer creates a different app certificate; installing over a copy signed elsewhere may require uninstalling that copy first, which deletes its local settings and skills. Builds using the same signing material can update in place.

The scripts install and launch **Oniro Agent** and the separate **Calendar** app. Grant Calendar access when asked. Open Oniro Agent, then **Settings → AI provider → API key → model**. Enter your own provider key; keys are not included in the repository. The app enables its accessibility service and shows **Agent service on**. The test suite requires the emulator but does not call paid AI APIs; a successful run reports **Pass: 102**.

For build-only output, use `.\scripts\build.ps1 -NoInstall` and `.\scripts\build-calendar.ps1 -NoInstall`. Signed HAPs are written to `build\phoneagent-signed.hap` and `build\calendar-signed.hap`. These system-app signatures target the Oniro/OpenHarmony test image; commercial HarmonyOS phones require different signing and permissions.

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

## Use

Settings (sliders icon, top right) → AI provider → API key → model (or "Custom model ID…"). Each provider keeps its own key. Back on the main screen type the task and tap the round button. To test the SMS task, add a contact "Babcia" first.

When you leave the app it shrinks into a floating orb (like a chat head; drag it to either edge); tap the orb to open the app again. While a task runs, a pill at the top shows the current step and the model's latest thought; its red button stops the task immediately, and tapping the pill shows all steps. Turn the orb off in Settings.

Contacts on the test emulator: Babcia, Mama, Tata, Dziadek, Kuba (600100200–600100204), added by the agent itself.

### User skills

Open **Skills** (the book icon beside Settings), then tap **+** to add instructions. Name and Description are required; limits are 60, 200 and 4000 characters for Name, Description and Body. Names are unique regardless of case. Save applies changes; Back discards them. Existing skills can be edited, disabled with the list toggle, or deleted after confirmation.

At task start the agent receives the enabled skills' names and descriptions. It loads relevant instructions using `read_skill`; the timeline shows **Read skill: name**. Skill contents stay fixed for that task, and each read counts toward the 25-step limit. There are no built-in skills.

### Calendar tasks

The Oniro v6.1 image includes the hidden `com.ohos.calendardata` data service, but no usable Calendar UI. Build and install the separate Calendar companion app:

```powershell
.\scripts\build-calendar.ps1
```

Allow calendar access when it first opens. It appears as **Calendar** in the launcher (`com.hackyeah.calendar`) and stores events in the system calendar service. Then rebuild Oniro Agent with `.\scripts\build.ps1` and enter:

> utworz wydarzenie w kalendarzu o nazwie impreza jutro o 17

The agent opens Calendar, fills the event form and saves **impreza** for tomorrow at **17:00**, with a one-hour duration by default. Relative dates use the phone's local date and timezone. Events remain saved after closing the app. The Calendar source is in `calendar/`; it is a small companion app, separate from OpenHarmony's upstream Calendar app.

Verified on the Oniro emulator on 2026-10-04 with this exact Polish prompt: the agent saved **impreza**, **2026-10-05 17:00–18:00**, and the event remained after restarting Calendar.

Calendar date validation checks (using DevEco's bundled Node and the full SDK):

```powershell
& 'C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe' .\calendar\test-time.cjs
```

## Check

- Tests: `.\scripts\test.ps1` → `Pass: 102`
- Screenshot: `.\scripts\screenshot.ps1 -Name main` → `build\shots\main.jpeg`
- System app: `hdc shell "bm dump -n com.hackyeah.phoneagent" | findstr appPrivilegeLevel` → `system_core`
- Log: `hdc shell "hilog -x" | findstr AgentA11y`

## Not ours

DevEco template, OpenHarmony SDK + public test signing certs, Oniro emulator, Bricolage Grotesque font (OFL, `entry/src/main/resources/rawfile/fonts/OFL.txt`). No runtime libraries.
