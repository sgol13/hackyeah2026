# Architecture

One ArkTS app on OpenHarmony. You type a task, an AI model operates the phone's apps for you.

- **AI**: no SDK. Hand-written clients (`@kit.NetworkKit` http) in a tool-use loop (`agent/`). The loop keeps one conversation format (Anthropic-style text / tool_use / tool_result blocks); each provider client translates it: Anthropic Messages (`Anthropic.ets`), OpenAI-compatible Chat Completions for OpenAI and xAI Grok (`OpenAiCompat.ets`), Gemini generateContent incl. thought signatures (`Gemini.ets`). Shared retries and error mapping in `Http.ets`, provider list and factory in `Providers.ets`.
- **Seeing and clicking**: `AccessibilityExtensionAbility`. It reads the other app's UI tree, turns it into text for the model (`[6] TextArea "Hello" (click,edit)`), then clicks, types and scrolls through `executeAction`. No screenshots, no vision.
- **Where the loop runs**: inside the accessibility extension, because it keeps running in the background while other apps are in front. The UI is only a remote control. The two talk over common events.
- **Launching apps**: `launcherBundleManager` lists the apps and `startAbility` opens them.
- **System app**: listing apps, starting them from the background and turning on accessibility from code all need system permissions. The app is signed `system_core` with the public OpenHarmony test CA (`scripts/sign.ps1`), so it installs with plain `hdc install`.
