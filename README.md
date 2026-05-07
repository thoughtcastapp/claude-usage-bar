# Claude Usage Bar

A native macOS menu bar widget that shows your **Claude Desktop** usage in real time — your 5-hour session, your weekly quota, your per-model split, and your overage credits — without ever leaving your menu bar.

> **Unofficial.** This is a community project, not affiliated with or endorsed by Anthropic. It reads only local data and talks to a non-public Claude endpoint. May break if Anthropic changes the API.

---

## Install — one command

Apple Silicon (M1 / M2 / M3 / M4), macOS 14+:

```bash
curl -fsSL https://raw.githubusercontent.com/irysagency/claude-usage-bar/main/install.sh | bash
```

The script:
1. Downloads the latest `.app` from the [Releases page](https://github.com/irysagency/claude-usage-bar/releases/latest)
2. Strips the macOS quarantine flag (we ad-hoc sign — no $99 Apple Developer dance)
3. Drops the app in `/Applications`
4. Launches it

Total: **~10 seconds.** No Xcode, no Homebrew, no Swift toolchain required.

> First launch will ask once for Keychain access (`"Claude Safe Storage"`). Click **Always Allow** — this is the system-standard way to read the cookie that Claude Desktop already uses to talk to its own API. Nothing leaves your Mac.

---

## What you get

A status item in the right side of the menu bar showing your current 5-hour session utilization (e.g. `◐ 76%`), tinted **green / orange / red** as you approach the cap.

Click it for a SwiftUI popover with the full breakdown:

| Section | Content |
|---|---|
| **Session 5h** | Big headline percent, animated progress bar, live "reset dans 2h 47m" |
| **Hebdo** | Weekly utilization, plus per-model split: Sonnet, Opus, Cowork |
| **Crédits overage** | How much overage spend you've used vs. your monthly cap |
| **Footer** | Plan tier (e.g. `Claude Max 5x`), "Mis à jour il y a Xs" |
| **Toolbar** | Refresh now · Open Claude · Quit |

Right-click the icon for a tiny escape menu with just **Quit**.

---

## How it works (if you're curious)

Claude Desktop is an Electron app. Like all Electron apps, it stores its session cookie in a Chromium-style SQLite db and encrypts the value with a Keychain-derived AES key. Anthropic's web app exposes an authenticated endpoint at `https://claude.ai/api/organizations/{org}/usage` that returns the same numbers the in-app rate-limit banner reads from.

This widget:
1. Reads `~/Library/Application Support/Claude/Cookies` in **read-only mode** (so it doesn't conflict with the running app)
2. Fetches the Chromium AES key from your Keychain via the standard `Security.framework` API (this is what triggers the one-time **Always Allow** prompt)
3. Decrypts the `sessionKey` cookie locally — the token never leaves your Mac
4. Calls the `/usage` endpoint with the cookie set, exactly as Claude Desktop itself does, every 30 seconds (with exponential back-off on errors)
5. Renders the result with SwiftUI

That's the whole thing. Pure Swift, no external dependencies, only Apple system frameworks (Foundation, AppKit, SwiftUI, Combine, SQLite3, Security, CommonCrypto).

---

## FAQ

**Does this leak my Claude account?**
No. The session token is read locally and only sent to the same `claude.ai` host the app already talks to. There is no outbound traffic to anywhere else. Inspect the source — it's [< 1500 lines of Swift](Sources/ClaudeUsageBar/).

**Will this get my account banned?**
The widget hits the same authenticated endpoint Claude Desktop hits, at a much lower rate (every 30 s, with back-off). It's a read-only call. We can't promise Anthropic's TOS will love it forever, but the surface is small.

**Why does it ask for Keychain access?**
That's how macOS protects the cookie encryption key. Claude Desktop itself goes through the same flow. Click **Always Allow** once.

**Why ad-hoc signed and not notarized?**
Apple charges $99/year for a Developer ID. For a tiny open-source widget, ad-hoc signing + the `install.sh` quarantine strip works fine. If you want to harden, fork and sign with your own cert.

**Intel Mac (x86_64) support?**
Not yet. The release artifact is arm64 only. Build from source with `swift build -c release && ./build.sh` if you're on Intel.

**Doesn't work / number is wrong / app crashes?**
[Open an issue](https://github.com/irysagency/claude-usage-bar/issues) with macOS version, Claude Desktop version, and what you saw. Logs are in **Console.app** under process `ClaudeUsageBar`.

---

## Build from source

You need Apple's Swift toolchain (preinstalled with Xcode or [Command Line Tools](https://developer.apple.com/download/all/?q=command%20line%20tools)).

```bash
git clone https://github.com/irysagency/claude-usage-bar
cd claude-usage-bar
./build.sh                    # produces ClaudeUsageBar.app/
open ClaudeUsageBar.app       # or drag it into /Applications
```

A clean `swift build -c release` is enforced with `-warnings-as-errors`; no warnings allowed in a release build.

---

## Project layout

```
Sources/ClaudeUsageBar/
  main.swift          App entry, NSApp.accessory activation
  AppDelegate.swift   NSStatusItem + NSPopover lifecycle, NSWorkspace observers
  ContentView.swift   SwiftUI root for the popover
  Components.swift    GlassCard, UsageBar, StatChip, IconButton, PrimaryButton
  UsageStore.swift    Refresh timer + ObservableObject state
  API.swift           Codable models, URLSession client
  Cookies.swift       SQLite reader + decrypt orchestration
  Keychain.swift      Read "Claude Safe Storage" password
  Crypto.swift        PBKDF2 + AES-128-CBC via CommonCrypto
  Formatting.swift    Bar/percent/reset-time/icon helpers
```

---

## License

[MIT](LICENSE). Fork it, ship it, sell it, whatever.

## Credits

Built by [Irys Agency](https://github.com/irysagency). Reverse-engineering done with [Claude Code](https://claude.com/claude-code).

If you ship a video, a thread, or just a "this is neat" tweet — tag us, we'll repost.
