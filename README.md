# VibeProxy (personal fork)

This is a **personal fork of [VibeProxy](https://github.com/automazeio/vibeproxy)** — stripped down to far fewer features and tailored to my own daily workflow. It is not maintained for anyone else, and upstream features I don't use may be missing or reworked without notice.

All credit for the original app goes to **[Automaze, Ltd.](https://automaze.io)** (original author) and to **[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)**, which powers the proxy backend. The original MIT license is preserved in [LICENSE](LICENSE).

## What this fork keeps

- **OpenAI (Codex OAuth)** and **Z.AI GLM** as the primary providers — `glm-5.3` and `glm-5.3-flash` are wired in out of the box
- **CommandCode** and **Neuralwatt** as bundled OpenAI-compatible providers (add API keys from the UI)
- **Add any OpenAI-compatible provider** from the settings UI (presets + custom, with model aliases)
- Multi-account key/account pooling, round-robin with failover, hot config reload
- Everything else (Claude, Gemini, Kimi, Qwen, Copilot, Antigravity) still works but is tucked behind "Other providers"

## Codex quota in the menu bar

Open **Codex quota** in the status menu to see remaining session and weekly quota for each enabled Codex account. Each account submenu shows window reset times and available manual reset credits, sorted by earliest expiry. Quota refreshes when you open the Codex quota submenu and the last fetch is older than a minute, or through **Refresh quota**. There is no background quota polling.

**Use a manual reset** asks for confirmation, consumes one credit, then refreshes only that account's quota. The provider API used by the upstream management dashboard accepts only a redemption request ID, not a credit ID. Individual credit selection and guaranteed earliest-expiry consumption are therefore not implemented. The expiry order shown in the menu is display order, not a promise about which credit Codex consumes.

These requests go directly to ChatGPT using the account's current OAuth credentials. They do not wake the local backend or write credentials. If authorization fails, reconnect Codex in Settings. Other providers' quota is not included in this implementation.

## Efficiency

- **Eco mode (on by default):** the local proxy stays listening on :8317, but the Go backend cold-starts on the first request and stops itself after an idle timeout (5–60 min). Near-zero idle power draw.
- No telemetry (`usage-statistics-enabled: false`), no management-panel auto-updates, slower config polling, and the Sparkle updater was removed entirely.
- See [FORK_NOTES.md](FORK_NOTES.md) for the full change list.

## Build

Requires macOS 13+, Xcode Command Line Tools.

```bash
make app        # build VibeProxy.app (fetches the CLIProxyAPI binary on first run)
make install    # install to /Applications
make update-backend   # bump to the latest CLIProxyAPI release (and update the pin)
```

The backend binary (~56 MB) is not committed to the repo; the build script downloads the pinned release automatically.

## Usage

1. Launch — menu bar icon appears; server is on-demand by default.
2. Settings → Services: connect **Codex**, add a **Z.AI API key**, and add keys for **CommandCode** / **Neuralwatt** under Custom Providers.
3. Point any OpenAI/Anthropic-compatible client at `http://localhost:8317`.

## License

MIT — see [LICENSE](LICENSE). Original work Copyright © Automaze, Ltd.
