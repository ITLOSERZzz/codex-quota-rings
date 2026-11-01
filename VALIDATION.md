# Validation — 0.1.5

Date: 2026-10-31 (Asia/Shanghai).

Passed locally:

- 0.1.4 process regression: two owned Node processes model a main that exits while another worker remains alive. The real main handle signals exit promptly; renderer/crashpad arguments and an unrelated CLI are excluded by selection tests. A synthetic competing ordinary relaunch is reported without launching or closing a desktop.
- Actual read-only inspection of the current desktop selected exactly one main process and retained one live handle. Resolving the valid recorded Store app path took about 40 ms and returned a Store activation identity. No desktop was closed by this check.

- Candidate only: in-memory Task Scheduler doubles cover registration, on-demand invocation, ownership validation, refusal of unrelated/elevated/triggered tasks and removal. No OS task is created by this test.
- Actual per-user on-demand task registration and invocation succeeded after resolving Task Scheduler's canonical account name back to its SID. Zero triggers and limited privilege were confirmed. The waiting PowerShell process was parented by `svchost` and remained running with a continuing heartbeat across separate command-runner calls. This is not yet proof of the complete desktop-exit/mount handoff.
- A bounded, temporary, read-only task context probe confirmed that the standalone task and the packaged command runner saw different contents at the same AppData state path. The temporary diagnostic task was deleted in the same command. State now uses a shared, separate `%USERPROFILE%\.codex-quota-rings` directory.
- The launcher test also exercises keeping the scheduled parent alive until its helper exits, with a synthetic child-process double.
- The current 0.1.2 launch record remained at waiting-for-exit while its launcher process was absent after the user's restart, and the new desktop still had no debug port. This establishes that the launch handoff did not occur; the exact process-termination mechanism has not been conclusively proven.

- 0.1.2 renderer checks: the owned concentric-ring widget is inserted before the native navigation-rail profile footer, React-owned controls stay in place, and removing the widget triggers one remount without duplicates. All previous browser scenarios still pass.
- 0.1.2 Windows launcher integration: an existing synthetic desktop is allowed to exit fully before exactly one desktop/helper launch, with cancellation, timeout and duplicate-lock checks. Desktop/helper starts are recorded test doubles; no real Codex session is closed by tests.
- 0.1.2 reference research: verified the SHA-256 of Lorie7813/codex-usage-card v0.9.4-beta.1 and inspected its readable release source without executing the package. The referenced macOS automatic handoff is not shipped or claimed on Windows.

- 0.1.1 regression: execute the actual success-message call through Windows PowerShell 5.1's parser/binder, verify the WPF overload, and run non-Quiet installation with a test-only dialog recorder. The earlier 0.1.0 checks used Quiet mode and missed the smart-quote bug in this branch.
- Source manifests, JavaScript syntax and Windows PowerShell 5.1 UTF-8/BOM encoding checks.
- 11 unit/protocol tests: quota windows, general versus model-specific buckets, invalid values, zero/unknown reset cards, expiry, color continuity, freshness, loopback restrictions and MCP initialize/tools calls.
- Real Chrome integration using synthetic accounts: in-app mount, hover, independent colors, account-switch race, disconnect, adapter recovery, omitted/expired windows, reset cards, light theme, 390px layout, idempotent mounting and disposal.
- Full helper controller integration: attach, named-pipe status and stop, UI cleanup.
- Real official `codex app-server` read-only protocol check: authenticated account, valid 5-hour/weekly windows and reset-card count available. No raw account values, identifiers or credentials were logged. Production display uses the desktop's own renderer client, not this separate CLI diagnostic.
- Windows PowerShell 5.1 install/uninstall in directories containing Chinese characters and spaces; desktop shortcut creation/removal; preservation of user-added files.
- Runtime-inclusive Release install and SHA-256 payload validation. The uninstaller rejected a traversal manifest before deleting any owned file, then successfully uninstalled its owned runtime and files.
- Required ZIP payload entries present, including hidden plugin/marketplace files and bundled Node.js license.

Native 0.1.5 verification:

- A real Codex Desktop 26.1027.3384.0 instance with an isolated UI profile, using the existing official account service, accepted a loopback debugging endpoint. The owned native widget mounted in the navigation rail; both quota windows and reset-card availability were returned through the desktop preload bridge. No account identifiers or raw responses were logged. Only the owned test instance was closed.
- The user confirmed that rebooting Windows and using the dedicated quota shortcut opens Codex and mounts the rings. Their older installed renderer reported adapter-unavailable, which this bridge change addresses.

Remaining validation:

- Completed: updated the existing installed extension to 0.1.5, restarted only its owned monitoring task, reused the existing desktop debugging port without restarting Codex, and observed a mounted navigation-rail widget with reason `ok`, both quota windows and reset-card count present in the production profile. Rechecked ongoing refresh separately. No account identifiers were logged.

- Automatic handoff from every possible already-running ordinary desktop instance remains unproven; no user desktop was force-closed.
- Completed: all Windows checks and runtime-inclusive packaging passed in [GitHub Actions](https://github.com/ITLOSERZzz/codex-quota-rings/actions/runs/41264504341). The first cloud run exposed WScript shortcut saving under a non-Chinese locale; Unicode Shell interfaces fixed it and the full next run passed.
- Windows 10 and other desktop versions/locales beyond the currently checked resources and synthetic scenarios.

This is a preview release. Passing browser fixtures and protocol checks does not prove compatibility with every future Codex UI build.
