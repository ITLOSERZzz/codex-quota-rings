# codex-usage-card implementation research

Checked on 2026-10-31, against [Lorie7813/codex-usage-card v0.9.4-beta.1](https://github.com/Lorie7813/codex-usage-card/releases/tag/v0.9.4-beta.1).

The published ZIP `CodexUsageCard-macOS-0.9.4.zip` was downloaded for source inspection only. Its SHA-256 matched both the public release value and GitHub asset digest: `e41cbb00fd01b785eb0cac73a946115a35dd2d9a2410c196ec7287ce4b1737f8`. None of its installation scripts, native binaries, agents, or background tasks were executed or installed. It is MIT licensed.

## How the sidebar icon works

In the ZIP's `agent.cjs`, `installUsageBadge()` creates the UI, and `place()` finds the visible `nav[data-app-navigation-rail]`. It inserts the add-on's own badge before the rail's footer with `insertBefore`; it does not move the app's React-owned controls. Mutation and resize observers maintain placement. `CdpSession` evaluates the bootstrap inside the desktop renderer using a loopback CDP connection. This is an unofficial renderer integration, not an official plugin sidebar entrypoint.

Our renderer now follows this layout approach while retaining its own concentric rings, independent green-to-red quota colors, shadow DOM, hover panel, reset-card count and current-desktop-account data source. It falls back to the earlier measured profile gap for layouts without that navigation-rail marker. No reference implementation code or assets were copied into the distributed package.

## How the original app icon works

`macos/startup/watch.cjs` subscribes to app-launch notifications through the packaged native `bridge`. It starts a `StartupController` in `macos/startup/controller.cjs`. The controller baselines existing processes, skips active sessions, and considers only a newly observed single launch. It checks an eight-second age window, input-idle duration, foreground process, existing debug arguments, port availability and a two-minute cooldown. It persists a receipt before requesting normal quit, waits for complete exit, and relaunches with debugging enabled. Refused quit or another instance cancels the handoff. This is the mechanism behind the original-icon experience.

The public release is macOS only. `NSWorkspace`, its native bridge, app launch tasks and quit mechanism cannot be reused directly on Windows. On the currently inspected Windows Codex build, closing the last window does not itself call `app.quit()`. A read-only native-menu probe did not expose a usable File > Exit command. We did not send a quit command, simulate shortcuts, terminate a desktop process, patch the application archive or register automatic restart tasks.

## Delivered and outstanding

Version 0.1.2 delivers navigation-rail placement, a launcher that waits for a user-initiated full exit instead of treating an already-running desktop as an error, cancellation/single-instance control, and a minimal local diagnostic command. Synthetic browser and launcher integration checks cover those changes. The first actual desktop mount still requires the user to exit the current non-CDP process and allow the launcher to reopen it.

The 0.1.3 candidate adds a Windows per-user on-demand task with no automatic triggers, so the wait/helper lifetime does not depend on the initiating Codex command runner. Actual task registration and service-parented waiting were checked. This is not the reference project's original-icon launch watcher and does not add automatic restart of a newly detected ordinary launch. Shared user-profile state avoids the differing AppData views observed during diagnosis.

Automatic loading from every original Windows entrypoint remains unimplemented. It requires a separately validated Windows launch/quit adapter; the package does not claim that the macOS startup behavior has already been ported.

Sources: [README](https://github.com/Lorie7813/codex-usage-card), [installation and startup behavior](https://github.com/Lorie7813/codex-usage-card/blob/main/docs/macos.md), [release and readable implementation ZIP](https://github.com/Lorie7813/codex-usage-card/releases/tag/v0.9.4-beta.1), [license](https://github.com/Lorie7813/codex-usage-card/blob/main/LICENSE).


## sub2api quota retrieval — 2026-11-01

Inspected [OpenAIQuotaService](https://github.com/Wei-Shaw/sub2api/blob/main/backend/internal/service/openai_quota_service.go). It queries `GET https://chatgpt.com/backend-api/wham/usage` and the dedicated `GET .../wham/rate-limit-reset-credits` endpoint using account-scoped OAuth context. It projects `used_percent`, `limit_window_seconds`, reset timestamps and reset-credit `available_count`; reset-credit inventory is separate from spendable credit balance. Multi-account support comes from an account repository and token provider. No sub2api code was copied or executed.

The official [Codex backend client](https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/client/rate_limit_resets.rs) uses these same usage/reset-credit endpoint families. Our renderer requests the current desktop account's read-only `account/rateLimits/read` through the desktop service, with identity verification before and after. It does not import a managed account pool or persist OAuth tokens. The original 0.1.4 failure was discovery of the renderer request client, not absence of upstream quota data. Version 0.1.5 prefers the preload bridge and retains the legacy path only when the bridge is absent.

This reduces dependence on React internals and hashed bundles. The native mount still depends on desktop layout and transport capabilities; neither undocumented upstream HTTP APIs nor internal desktop IPC can guarantee perpetual future compatibility.
