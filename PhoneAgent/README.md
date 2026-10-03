# Phone Agent: an AI agent that uses your OpenHarmony phone for you

*HackYeah 2026 · Huawei challenge "A standout system feature or an app for a new mobile operating system"*
*Areas: **Intelligent Experiences** (an on-device agent) and **Human-Centric Technology** (accessibility).*

You tell the phone what you want, for example *"napisz do babci SMS, że będę na jej
urodzinach"* ("text grandma that I'll come to her birthday"). Phone Agent opens Messages, picks
the recipient, writes the text and presses Send, the same way you would with your finger.
It isn't a catalogue of per-app integrations. It reads whatever is on screen through the
OpenHarmony accessibility framework, and a Claude model decides the next tap. So it works with
any app, including apps that were never designed for automation.

Who it is for: people for whom small touch targets and multi-step UIs are a real barrier
(older people, people with motor or visual impairments), and anyone whose hands are busy.

This is only possible on an open platform: operating other apps requires OpenHarmony system
APIs. On Oniro / OpenHarmony, a self-signed app may use them without modifying the OS (see
[ARCHITECTURE.md](ARCHITECTURE.md#platform-capabilities-used)).

* Architecture and design decisions: [ARCHITECTURE.md](ARCHITECTURE.md)
* AI feature and AI-assisted development: [AI_WORKFLOW.md](AI_WORKFLOW.md)
* Demo video: *(link added on submission)*

## How it works (short)

1. The UI (Index page) stores your Anthropic API key and model choice, and switches on the app's
   own accessibility service with `config.enableAbility`.
2. You type a task and tap **Run**. The task goes to the **AgentA11y** accessibility extension,
   which runs in its own process, so it keeps working while other apps are in front.
3. The agent loop sends the task, the list of installed apps and the tool definitions to the
   Claude Messages API. Claude replies with tool calls (`launch_app`, `click`, `type_text`,
   `scroll`, `press_key`, `finish`, …).
4. Each call is validated, executed through accessibility actions, and answered with the new
   screen, rendered as compact text (`[6] TextArea hint="Text message" (click,edit) @164,659`).
   This repeats until Claude calls `finish`.
5. The UI shows a live log, and the app comes back to the front with the summary.

## Tested environment (exact versions)

| Component | Version |
|---|---|
| Host | Windows 11 Pro 10.0.26200 x64 (AMD Ryzen AI 7 PRO 350), 60 GB RAM |
| Emulator host | WSL 2.6.3, Ubuntu 24.04, `/dev/kvm` available, systemd enabled |
| QEMU | 8.2.2 (`qemu-system-x86` from Ubuntu 24.04) |
| Emulator image | Oniro emulator **v6.1** (`oniro_emulator.zip`, OpenHarmony **6.1.0.31**, API 23) |
| IDE / build tools | DevEco Studio **6.1.1.280** (bundled hvigor 6.24.2, Node 18.20.1, JBR 21.0.8, hdc 3.2.0d) |
| SDK | OpenHarmony **full** SDK **6.0.0.48** (API **20**) for Windows, from the OpenHarmony CI |
| App target | `runtimeOS: OpenHarmony`, `compileSdkVersion` / `compatibleSdkVersion` / `targetSdkVersion` = **20** |
| Test framework | `@ohos/hypium` 1.0.25 |
| Models | `claude-opus-5-5` (default), `claude-sonnet-5-5`, `claude-haiku-4-5` |

Other setups (Linux host with KVM, DevEco on macOS) should work with the same steps. Only the
paths differ.

## Setup

### 1. Emulator (Oniro 6.1 in WSL2 with KVM)

In WSL (Ubuntu 24.04, systemd on):

```bash
sudo apt install qemu-system-x86
sudo usermod -aG kvm $USER          # then open a new WSL shell
mkdir -p ~/oniro && cd ~/oniro
curl -LO https://github.com/eclipse-oniro4openharmony/device_board_oniro/releases/download/v6.1/oniro_emulator.zip
unzip oniro_emulator.zip            # -> ~/oniro/images/{run.sh,*.img,bzImage}
```

From the repository folder in Windows PowerShell:

```powershell
wsl -u root -- bash scripts/emulator.sh start     # runs run.sh as a systemd unit (survives wsl.exe exit)
# wait ~40 s; the emulator window appears on the desktop through WSLg
& "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" tconn 127.0.0.1:55555
```

`wsl -u root -- bash scripts/emulator.sh stop` shuts it down.

### 2. OpenHarmony full SDK (API 20)

The public SDK in DevEco has no system APIs, so you need the **full** SDK. Download
`ohos-sdk-full` 6.0.0.48 (branch `OpenHarmony-6.0-Release`) from the OpenHarmony CI:
<https://cidownload.openharmony.cn/version/Master_Version/OpenHarmony_6.0.0.48/20251122_043125/version-Master_Version-OpenHarmony_6.0.0.48-20251122_043125-ohos-sdk-full.tar.gz>
(3.2 GB; other builds are listed at <https://dcp.openharmony.cn/workbench/cicd/dailybuild/dailylist>).
Extract the five archives from `ohos-sdk/windows/` (`ets`, `js`, `native`, `previewer`,
`toolchains`) into `%LOCALAPPDATA%\OpenHarmony\Sdk\20\`, so that you get
`...\Sdk\20\ets\oh-uni-package.json` and so on. Windows' built-in `tar -xf <zip> -C <dir>` is fast.

To use the DevEco IDE as well, point *Settings → OpenHarmony SDK* at `%LOCALAPPDATA%\OpenHarmony\Sdk`.

### 3. Build, sign, install, launch

```powershell
.\scripts\build.ps1              # hvigor build -> sign as system app -> hdc install -> start
.\scripts\build.ps1 -NoInstall   # only produce build\phoneagent-signed.hap
```

`build.ps1` uses DevEco's bundled Node, hvigor and Java, plus the SDK from step 2 (override it
with `-Sdk` or `OHOS_BASE_SDK_HOME`). Signing is done by `scripts/sign.ps1` (details in
[ARCHITECTURE.md](ARCHITECTURE.md#platform-capabilities-used)). The first time you run it, it
creates a private app key in `.signing/` (git-ignored).

> If a build *without* the accessibility extension was installed before, uninstall it first
> (`hdc uninstall com.hackyeah.phoneagent`). The accessibility service only registers new
> extensions on a fresh install, not on an update.

The prebuilt, signed `.hap` is attached to the GitHub release. Install it with
`hdc install phoneagent-signed.hap`.

## Using it

1. Open **Phone Agent**. "Agent service: on" means the accessibility extension is enabled.
2. Paste your Anthropic API key and pick a model.
3. Type a task and tap **Run**. Examples:
   * *Open Settings and turn on Bluetooth.*
   * *Napisz do babci SMS, że będę na jej urodzinach.* (the demo adds a contact "Babcia" first)
4. Watch the agent work. The log shows each step (▶ action, ✖ error, ✔ result). **Stop**
   cancels the task.

## Verifying it

* **Tests on the emulator**: `.\scripts\test.ps1` builds the app and the hypium test HAP, signs
  and installs both, and runs them with `aa test`. Expected result: `Tests run: 30, Failure: 0,
  Error: 0, Pass: 30`. They cover the tool-call validator (bad model output), the screen
  serializer, API error and response parsing, and the agent loop with a scripted fake model and
  device (refusal, truncation, step limit, recovery, stop).
* **System-app check**: `hdc shell "bm dump -n com.hackyeah.phoneagent" | findstr "appPrivilegeLevel isSystemApp"`
  shows `system_core` / `true`.
* **Agent log**: `hdc shell "hilog -x" | findstr AgentA11y` shows every step the service took.

## Security and privacy

* The API key is entered by the user and stored in app-private Preferences. It is never logged,
  never sent in IPC events, and leaves the device only in the HTTPS request to
  `api.anthropic.com`. There are no secrets in this repository. The signing passwords in
  `scripts/sign.ps1` belong to the *public* OpenHarmony test keystore.
* While a task runs, the text of the current screen (element labels and contents) is sent to
  Anthropic. Don't run tasks on screens with data you don't want to share. Details are in
  [AI_WORKFLOW.md](AI_WORKFLOW.md#privacy).
* IPC is restricted to this bundle in both directions, so other apps can't trigger the agent.
* Minimal permissions: there is no screen capture, input injection, SMS, telephony or contacts
  permission. The agent can only do what the user could do by hand.

## Repository layout

```
PhoneAgent/
├─ AppScope/                     app.json5 (bundle com.hackyeah.phoneagent)
├─ entry/src/main/ets/
│  ├─ pages/Index.ets            UI
│  ├─ entryability/              UIAbility
│  ├─ a11y/                      AgentA11y extension, ScreenReader, DeviceExecutor
│  ├─ agent/                     AgentLoop, Tools, ScreenText, Anthropic client, Prompt
│  └─ common/                    Bridge (IPC), Settings
├─ entry/src/ohosTest/           hypium tests (run on device)
├─ signing/                      profile template (apl system_core) + public OpenHarmony CA certs
├─ scripts/                      build.ps1, sign.ps1, test.ps1, emulator.sh
├─ ARCHITECTURE.md, AI_WORKFLOW.md
```

## Pre-existing and third-party components

* DevEco Studio "Empty Ability" project template (hvigor config, EntryAbility skeleton, icons).
* OpenHarmony SDK, `hap-sign-tool` and the public test signing material: `OpenHarmony.p12`
  from the SDK; `rootCA.cer` and `subCA.cer` from
  [developtools_hapsigner](https://gitcode.com/openharmony/developtools_hapsigner).
* Oniro emulator v6.1 images and `run.sh` (Eclipse Oniro project).
* No third-party runtime libraries. The Anthropic API client is hand-written, because there is no
  Anthropic SDK for ArkTS.
* AI coding assistance: Claude Code. See [AI_WORKFLOW.md](AI_WORKFLOW.md).

Everything else was written during the hackathon (3–4 Oct 2026). The commit history shows how
it progressed.
