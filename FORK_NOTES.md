# Personal Fork Notes

Tuned for a daily workflow around **OpenAI (Codex)**, **Z.AI GLM**, **CommandCode**, and **Neuralwatt**, with lower idle power draw. See README for credits.

## What changed vs upstream

### Providers
- **Z.AI GLM defaults updated to GLM-5.3 + GLM-5.3-Flash** (flash = first native multimodal GLM-5 model, 3× coding-plan quota vs GLM-5.3), with GLM-4.7 kept as fallback. Same endpoint (`https://api.z.ai/api/coding/paas/v4`).
- **CommandCode** (`commandcode`) and **Neuralwatt** (`neuralwatt`) ship as bundled OpenAI-compatible providers — add keys from Settings → Custom Providers.
  - CommandCode base URL: `https://api.commandcode.ai/provider/v1` (key from commandcode.ai/studio). Claude models are exposed only via CommandCode's Anthropic endpoint and intentionally omitted; the OpenAI-protocol catalog (GPT-5.6, GLM-5.3, Kimi, Qwen, Grok, DeepSeek, MiniMax…) is exposed with `cc-` aliases.
  - Neuralwatt base URL: `https://api.neuralwatt.com/v1` (key from portal.neuralwatt.com). Models use `nw-` aliases. Responses include energy (joules/kWh/watts) usage blocks.
- **Add any OpenAI-compatible provider from the UI** (Custom Providers → Add Provider). Presets included; models are entered one per line as `model-id` or `model-id = alias`. Writes to `~/.cli-proxy-api/config.yaml`, stores keys in `~/.cli-proxy-api/openai-compat-*.json` (600 perms). User-added providers can be removed from the UI; bundled ones can be toggled off instead.
- Services list reordered: **Codex and Z.AI first**, everything else behind "Other providers".

### Efficiency (Settings → Efficiency)
- **On-demand backend (eco mode)** — on by default. The Swift proxy (port 8317) always listens, but the Go backend (port 8318) cold-starts on the first request and is stopped after the idle timeout (default 15 min). Menu bar shows "On-demand (idle)".
  - Manual "Stop Server" suspends wake-on-request until the next "Start Server".
  - Cold start adds ~1–2 s latency to the first request after an idle stop.
- **Sparkle removed entirely** — no update checks, no appcast, no upstream network traffic. Rebuild from source to update.
- **`usage-statistics-enabled: false`** and **`remote-management.disable-auto-update-panel: true`** — no telemetry, no periodic management-panel GitHub updates.
- Config fingerprint poller slowed from 1 s to 5 s (fs events still catch edits instantly).

### UI fixes
- Settings window scrolls again: removed the upstream `.scrollDisabled(expandedRowCount == 0)` lock that froze the form whenever no account rows were expanded.
- Window content size matches its fixed 480×740 layout.

### Removed upstream pieces
- Sparkle updater + appcast files + auto-update workflows (`.github/`), upstream docs (Factory/Amp setup guides, changelog), marketing assets, and all author/company branding inside the app. Credits live in the README; the MIT LICENSE is retained.

### Backend (CLIProxyAPI)
- The backend binary is **fetched at build time** (pinned: v7.2.146) instead of being committed — `create-app-bundle.sh` downloads it automatically on first build; nothing >50 MB lives in git.
- `make update-backend` bumps to the latest CLIProxyAPI release (update the `PINNED_VERSION` in `scripts/update-backend.sh` afterwards), `make pin-backend` re-fetches the pinned version.

## Building

```bash
make app        # build VibeProxy.app
make install    # install to /Applications
cd src && swift test   # run unit tests (requires full Xcode for XCTest)
```

## Notes

- Eco mode stops the Go process when idle, so background OAuth token refresh only happens on demand (tokens refresh when used). Not an issue for daily use.
- The first GLM-5.3 request on the coding endpoint with `thinking.type: "disabled"` will fail; use `enabled` + `reasoning_effort: low` instead (Z.AI migration notice).
