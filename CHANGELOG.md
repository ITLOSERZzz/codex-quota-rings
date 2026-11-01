# Changelog

## 0.1.5 — 2026-11-01

- Save and validate desktop shortcuts through Unicode Windows Shell interfaces, including Chinese names on non-Chinese Windows installations. Verified on GitHub Windows Server CI.

- Prefer the desktop preload message bridge for allowlisted account/quota requests, with isolated request IDs and timeouts, instead of depending on a discoverable React client object. Retain the legacy client as a compatibility fallback when the bridge is absent.
- Permit bridge-based mounting without the private React root global. Detect capabilities rather than matching application version numbers.
- Replace the misleading version-incompatibility message with the actual missing-interface or synchronization condition.
- Verify mount, 5-hour/weekly windows and reset-card availability in a real native Codex test instance on the current machine. Add bridge-only mount, response isolation and error/recovery browser checks.
- Internal bridge/layout changes in future desktop builds can still require an update; universal future compatibility is not claimed.

## 0.1.4 candidate — 2026-10-31

- Track retained handles of the original desktop main processes instead of requiring every renderer, GPU worker and crash reporter to disappear at once.
- Remove the additional one-second empty-process interval. If another ordinary main process has already opened, report `ordinary-relaunch-detected` and its process IDs instead of continuing to wait or closing it.
- Resolve a valid recorded app path directly and precompile the Store activation adapter before waiting, reducing the handoff delay.
- Add a real owned-process regression with a main process that exits while a separate worker stays alive, subprocess-selection cases, and a launcher replacement-race test.
- Correct the Windows quit instructions: use the application icon's system-tray Quit command. The top File menu was not a verified exit entrypoint.

## 0.1.3 candidate — 2026-10-31

- Use an independent, per-user, on-demand Task Scheduler launcher with no automatic triggers or elevation. Registration and service-parented execution have been checked on the current account; the first actual desktop mount remains pending.
- Normalize Windows account names back to SIDs before checking task ownership; Task Scheduler canonicalizes supplied SIDs.
- Share state in `%USERPROFILE%\.codex-quota-rings` instead of divergent AppData views exposed to packaged and standalone processes.
- Retain the scheduled action for the helper's lifetime instead of relying on detached child processes.
- Include launcher process identity and a waiting heartbeat in sanitized status, and distinguish a stale waiting record from a live launcher.
- Validate task ownership before installation, invocation or deletion; refuse unrelated actions, working directories, triggers or elevated principals.
- Test task operations through in-memory COM doubles only. Installation fixtures skip OS-task registration explicitly.

## 0.1.2 — 2026-10-31

- Insert the owned ring widget into the native navigation rail before the profile footer, following layout research of Lorie7813/codex-usage-card. Retain the original concentric design and measured-position fallback.
- Treat an ordinary running Codex instance as a pending launch: wait for the user's the system-tray Quit command, then reopen once with the quota helper. Do not force quit or restart an active session.
- Prevent duplicate waiting launchers, cancel pending launches on upgrade/uninstall, and expire waiting after 30 minutes.
- Add Check.cmd and sanitized launcher/injection status.
- Add real-renderer browser checks for rail placement/remounting and synthetic Windows launcher checks for exit waiting, cancellation and expiry.
- Original-icon automatic startup remains unimplemented on Windows; the referenced macOS handoff has not been ported.

## 0.1.1 — 2026-10-31

- Fix the interactive install success message: PowerShell treated embedded smart quotes as string boundaries and bound `Codex` to the icon argument.
- Use named message parameters, validated icon names and typed WPF enum arguments.
- Add a regression that executes the actual success call and the non-Quiet installation branch with a test-only dialog recorder.

## 0.1.0 — 2026-10-31

- Double-ring sidebar design: outer 5-hour quota, inner weekly quota.
- Continuous green/yellow/orange/red capacity colors.
- Hover details, pin/unpin, reset timestamps and authoritative reset-card count.
- Current-desktop-account checks, separate quota buckets and explicit unknown/stale states.
- Native Windows launcher, user-only installer and ownership-checked uninstaller.
- Optional standard Codex MCP plugin and repository marketplace.
- Runtime-inclusive Windows release packaging, SHA-256 and GitHub Actions.
- Preview status: first mounting inside the active non-CDP desktop session requires a normal user relaunch and remains to be verified.
