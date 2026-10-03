# Phone Agent

HackYeah 2026, Huawei challenge. You type "text grandma that I'll come to her birthday" and an AI model does it on the phone: opens Messages, picks the contact, types, sends. Works with any app through accessibility. Only possible on OpenHarmony / Oniro (system app).

AI providers: Anthropic Claude (tested end to end), OpenAI, xAI Grok, Google Gemini (implemented and unit-tested; live endpoints checked only with an invalid key, no real keys).

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [AI_WORKFLOW.md](AI_WORKFLOW.md)
- Demo video: _(link on submission)_

## Versions

Windows 11 · WSL2 Ubuntu 24.04 + KVM · QEMU 8.2.2 · Oniro emulator v6.1 · DevEco Studio 6.1.1.280 · OpenHarmony full SDK 6.0.0.48 (API 20)

## Setup

1. **Emulator** (Oniro v6.1 in WSL2 with KVM; the window shows up on the Windows desktop through WSLg). One-time setup:

   1. Install WSL2 with Ubuntu 24.04 (PowerShell as admin, then reboot): `wsl --install -d Ubuntu-24.04`. Create the Linux user when asked.
   2. In Ubuntu, turn on systemd (`scripts/emulator.sh` runs the emulator as a systemd unit) by adding this to `/etc/wsl.conf`:
      ```ini
      [boot]
      systemd=true
      ```
      Then run `wsl --shutdown` in PowerShell and open Ubuntu again.
   3. Install QEMU and give your user access to KVM:
      ```bash
      sudo apt update && sudo apt install -y qemu-system-x86 qemu-utils unzip
      sudo usermod -aG kvm $USER
      ```
      Run `wsl --shutdown` again, then check: `ls -l /dev/kvm` should exist and `id` should list `kvm`. If `/dev/kvm` is missing, turn on virtualization (VT-x/AMD-V) in the BIOS.
   4. Download the emulator into `~/oniro/images` (the default path in `scripts/emulator.sh`; ~1.45 GB download, ~5.5 GB unpacked):
      ```bash
      mkdir -p ~/oniro && cd ~/oniro
      wget https://github.com/eclipse-oniro4openharmony/device_board_oniro/releases/download/v6.1/oniro_emulator.zip
      unzip oniro_emulator.zip        # creates ~/oniro/images/ with run.sh and the *.img files
      chmod +x images/run.sh
      ```
   5. Add hdc to the Windows PATH. It ships with DevEco: `C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains`.

   Start it from the repo root in PowerShell: `.\scripts\start-emulator.ps1`. The first boot takes ~1 min. The script waits for the boot to finish and connects hdc, after which `hdc list targets` shows `127.0.0.1:55555`. Stop it with `wsl -u root -- bash scripts/emulator.sh stop`.
   The script assumes DevEco is in `C:\Program Files\Huawei\DevEco Studio` and the distro is named `Ubuntu-24.04`. If not, pass `-DevEco "<path>"` / `-Distro <name>` (`wsl -l -v` lists distro names).

   **Optional: start button in DevEco Studio.** Go to File → Settings → Tools → External Tools → **+** and fill in:

   | Field | Value |
   |---|---|
   | Name | `Start Oniro emulator` |
   | Program | `powershell.exe` |
   | Arguments | `-NoProfile -ExecutionPolicy Bypass -File "$ProjectFileDir$\scripts\start-emulator.ps1"` |
   | Working directory | `$ProjectFileDir$` |

   Leave "Open console for tool output" ticked. Run it from Tools → External Tools → Start Oniro emulator. Afterwards `127.0.0.1:55555` shows up in DevEco's device list. If the device doesn't appear, use Tools → IP Connection → `127.0.0.1:55555`.

2. **Full SDK** (the public one has no system APIs): [ohos-sdk-full 6.0.0.48](https://cidownload.openharmony.cn/version/Master_Version/OpenHarmony_6.0.0.48/20251122_043125/version-Master_Version-OpenHarmony_6.0.0.48-20251122_043125-ohos-sdk-full.tar.gz) → unpack `ohos-sdk/windows/*` into `%LOCALAPPDATA%\OpenHarmony\Sdk\20\`. For DevEco: Settings → OpenHarmony SDK → that folder.
3. **Build + sign + install + run**: `.\scripts\build.ps1` (or Run in DevEco after running `.\scripts\sign.ps1 -PrepareOnly` once)

Prebuilt `.hap` in GitHub Releases: `hdc install phoneagent-signed.hap`. If an older build is installed: `hdc uninstall com.hackyeah.phoneagent` first.

## Use

Provider → API key → model (or "Custom model ID…") → task → **Run**. Each provider keeps its own key. To test the SMS task, add a contact "Babcia" first.

## Check

- Tests: `.\scripts\test.ps1` → `Pass: 51`
- System app: `hdc shell "bm dump -n com.hackyeah.phoneagent" | findstr appPrivilegeLevel` → `system_core`
- Log: `hdc shell "hilog -x" | findstr AgentA11y`

## Not ours

DevEco template, OpenHarmony SDK + public test signing certs, Oniro emulator. No runtime libraries.
