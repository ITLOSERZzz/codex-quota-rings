# Security and privacy

This is an unofficial, unsigned Windows desktop extension. The native mount depends on an internal renderer adapter and a loopback CDP endpoint; it is not an officially supported sidebar injection API.

- CDP is bound to `127.0.0.1` on a dynamically chosen port. The helper rejects remote endpoints, redirects, credentials in URLs, and websocket endpoints on another port. CDP exposes powerful debugging access to other local software; it must never be exposed to a network interface.
- The launcher never changes the signed Codex package, WindowsApps, app.asar, account files, model configuration, prompts, queued tasks or transcripts.
- The injected request allowlist is exactly `account/read` and `account/rateLimits/read`. No model calls, task start/resume, account switching, reset-card consumption or purchases are implemented.
- Account identity is compared in renderer memory and excluded from helper reports. Neither tokens, email addresses nor raw account objects are persisted or logged.
- Only the normalized quota percentages, reset timestamps, reset-card count, health state and local debugging port are stored in the helper status file. The launcher also records the Codex executable path and process ID for safe reuse of its own launch.
- Status and stop commands use a local named pipe, not a public HTTP service. The helper can only remove the UI it created; it never closes Codex.
- The 0.1.3 candidate registers one per-user Task Scheduler action, with interactive-token logon, limited privilege, and no triggers. It is started only on demand and is kept alive for the helper's lifetime. This avoids dependence on the initiating agent command runner. Installation, invocation and removal validate its action, resolved user SID, privilege level, working directory and ownership description. It is not a login/boot startup task. Actual registration and service-parented waiting have been verified; native mounting and read-only quota retrieval have also been verified in an isolated UI-profile test instance.
- State is stored under `%USERPROFILE%\.codex-quota-rings`, separate from official Codex account/configuration files, because packaged and standalone processes were observed to see different contents at the former AppData state path.
- An app update that removes the anchor or internal client results in unavailable data or a hidden icon. Existing native controls are never overwritten as a fallback.
- The installer validates installation ownership. Uninstall prevalidates all target paths, rejects directory links and path traversal, removes only owned files, and preserves user-added files.
- There is no telemetry, remote code loader, auto-updater, automatic startup registration, background web scraping or third-party service request in the extension. The official desktop client continues to handle its own authenticated quota requests.

Report issues using the repository's issue tracker after publication. Include version, Windows build and sanitized `placement/reason` status. Do not attach credentials, account responses, conversation logs or real debugging websocket URLs. Security fixes should be reviewed and released explicitly.
