# Phone Agent

HackYeah 2026, Huawei challenge. You type "text grandma that I'll come to her birthday" and an AI model does it on the phone: opens Messages, picks the contact, types, sends. Works with any app through accessibility. Only possible on OpenHarmony / Oniro (system app).

AI providers: Anthropic Claude (tested end to end), OpenAI, xAI Grok, Google Gemini (implemented and unit-tested; live endpoints checked only with an invalid key, no real keys).

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [AI_WORKFLOW.md](AI_WORKFLOW.md)
- Demo video: _(link on submission)_

## Versions

Windows 11 · QEMU 11.1.0 for Windows (WHPX) · Oniro emulator v6.1 · DevEco Studio 6.1.1.280 · OpenHarmony full SDK 6.0.0.48 (API 20)

## Setup

Everything runs natively on Windows 11 (no WSL). All commands are PowerShell, run from the repo root unless stated otherwise.

1. **DevEco Studio** 6.1.1.280 (Huawei developer download center), installed to the default `C:\Program Files\Huawei\DevEco Studio`. Add hdc to the PATH: `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains`.
2. **Emulator** (Oniro v6.1 in QEMU for Windows):

   1. Turn on Windows Hypervisor Platform (QEMU's accelerator). PowerShell as admin:
      ```powershell
      Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
      ```
      Reboot if it asks. Virtualization (VT-x/AMD-V) must be on in the BIOS.
   2. Install QEMU (into `C:\Program Files\qemu`): `winget install SoftwareFreedomConservancy.QEMU`
   3. Download the emulator into `%USERPROFILE%\oniro\images` (the script's default; ~1.45 GB download, ~5.5 GB unpacked):
      ```powershell
      mkdir $env:USERPROFILE\oniro; cd $env:USERPROFILE\oniro
      curl.exe -LO https://github.com/eclipse-oniro4openharmony/device_board_oniro/releases/download/v6.1/oniro_emulator.zip
      tar -xf oniro_emulator.zip      # creates images\ with the *.img files
      ```

   Start it (back in the repo root): `.\scripts\start-emulator.ps1`. Booting takes ~30 s. The script waits for it, then connects hdc, so `hdc list targets` shows `127.0.0.1:55555`. Stop it: `.\scripts\start-emulator.ps1 -Stop`. To use the mouse, click into the emulator window; Ctrl+Alt+G releases it.
   Other locations: `-Images <folder>`, `-Qemu <folder>`, `-DevEco <folder>`. If the window closes right away, `.\scripts\start-emulator.ps1 -Foreground` shows QEMU's error.

   **Optional: start button in DevEco Studio.** Go to File → Settings → Tools → External Tools → **+** and fill in:

   | Field | Value |
   |---|---|
   | Name | `Start Oniro emulator` |
   | Program | `powershell.exe` |
   | Arguments | `-NoProfile -ExecutionPolicy Bypass -File "$ProjectFileDir$\scripts\start-emulator.ps1"` |
   | Working directory | `$ProjectFileDir$` |

   Leave "Open console for tool output" ticked. Run it from Tools → External Tools → Start Oniro emulator. Afterwards `127.0.0.1:55555` shows up in DevEco's device list. If the device doesn't appear, use Tools → IP Connection → `127.0.0.1:55555`.

3. **Full SDK** (the public one has no system APIs): [ohos-sdk-full 6.0.0.48](https://cidownload.openharmony.cn/version/Master_Version/OpenHarmony_6.0.0.48/20251122_043125/version-Master_Version-OpenHarmony_6.0.0.48-20251122_043125-ohos-sdk-full.tar.gz) → unpack `ohos-sdk/windows/*` into `%LOCALAPPDATA%\OpenHarmony\Sdk\20\`. For DevEco: Settings → OpenHarmony SDK → that folder.
4. **Build + sign + install + run**: `.\scripts\build.ps1` (or Run in DevEco after running `.\scripts\sign.ps1 -PrepareOnly` once)

Prebuilt `.hap` in GitHub Releases: `hdc install phoneagent-signed.hap`. If an older build is installed: `hdc uninstall com.hackyeah.phoneagent` first.

## Use

Provider → API key → model (or "Custom model ID…") → task → **Run**. Each provider keeps its own key. To test the SMS task, add a contact "Babcia" first.

## Check

- Tests: `.\scripts\test.ps1` → `Pass: 51`
- System app: `hdc shell "bm dump -n com.hackyeah.phoneagent" | findstr appPrivilegeLevel` → `system_core`
- Log: `hdc shell "hilog -x" | findstr AgentA11y`

## Not ours

DevEco template, OpenHarmony SDK + public test signing certs, Oniro emulator. No runtime libraries.
