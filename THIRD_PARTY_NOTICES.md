# Third-party notices

The extension source code is MIT licensed. It has no npm runtime dependencies.

The complete Windows Release redistributes **Node.js v24.16.0 win-x64**. Its copyright notices and bundled third-party licenses are included verbatim in `third-party/Node-LICENSE.txt` and `runtime/LICENSE.txt`. Source-only checkouts do not contain the runtime binary. When updating the runtime, update the matching license and build-version check together.

Protocol and integration references:

- OpenAI's [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server).
- OpenAI's [plugin extensions](https://developers.openai.com/plugins/build/extensions) and [plugin packaging documentation](https://developers.openai.com/plugins/build/plugins).
- [JiaYang-BUAA/Codex-Desktop-Usage-Monitor-Windows](https://github.com/JiaYang-BUAA/Codex-Desktop-Usage-Monitor-Windows) demonstrated loopback CDP-based in-app mounting and informed feasibility research.
- [nnixaa/codex-usage-plugin](https://github.com/nnixaa/codex-usage-plugin) demonstrated standard plugin packaging and local quota tooling.
- [Lorie7813/codex-usage-card](https://github.com/Lorie7813/codex-usage-card), MIT licensed, informed navigation-rail placement and startup feasibility research. Its v0.9.4 Beta release ZIP was inspected without executing it. This package contains an independent implementation; its macOS startup helper is not redistributed. See `REFERENCE-RESEARCH.md`.

This repository implements its own small renderer, quota parser, MCP server, controller and installer. Windows COM activation identifiers are documented operating-system interface identifiers. No OpenAI logos or Codex application binaries are redistributed. The installed shortcut uses the locally installed Codex application's icon.

Codex, ChatGPT and OpenAI names identify the compatible product. This project is not affiliated with or endorsed by OpenAI.
