# Phone Agent

HackYeah 2026, Huawei challenge. You type "text grandma that I'll come to her birthday" and Claude does it on the phone: opens Messages, picks the contact, types, sends. Works with any app through accessibility. Only possible on OpenHarmony / Oniro (system app).

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [AI_WORKFLOW.md](AI_WORKFLOW.md)
- Demo video: _(link on submission)_

## Versions

Windows 11 · WSL2 Ubuntu 24.04 + KVM · QEMU 8.2.2 · Oniro emulator v6.1 · DevEco Studio 6.1.1.280 · OpenHarmony full SDK 6.0.0.48 (API 20)

## Setup

1. **Emulator** (WSL):
   set up Oniro emulator v6.1

   Start: `.\scripts\start-emulator.ps1`

2. **Full SDK** (the public one has no system APIs): [ohos-sdk-full 6.0.0.48](https://cidownload.openharmony.cn/version/Master_Version/OpenHarmony_6.0.0.48/20251122_043125/version-Master_Version-OpenHarmony_6.0.0.48-20251122_043125-ohos-sdk-full.tar.gz) → unpack `ohos-sdk/windows/*` into `%LOCALAPPDATA%\OpenHarmony\Sdk\20\`. For DevEco: Settings → OpenHarmony SDK → that folder.
3. **Build + sign + install + run**: `.\scripts\build.ps1` (or Run in DevEco after running `.\scripts\sign.ps1 -PrepareOnly` once)

Prebuilt `.hap` in GitHub Releases: `hdc install phoneagent-signed.hap`. If an older build is installed: `hdc uninstall com.hackyeah.phoneagent` first.

## Use

API key → model → task → **Run**. To test the SMS task, add a contact "Babcia" first.

## Check

- Tests: `.\scripts\test.ps1` → `Pass: 35`
- System app: `hdc shell "bm dump -n com.hackyeah.phoneagent" | findstr appPrivilegeLevel` → `system_core`
- Log: `hdc shell "hilog -x" | findstr AgentA11y`

## Not ours

DevEco template, OpenHarmony SDK + public test signing certs, Oniro emulator. No runtime libraries.
