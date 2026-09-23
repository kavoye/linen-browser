# OpenAI integration

Linen uses its Responses client for providers configured with the Responses
adapter. Other providers use AnyLanguageModel. The implementation lives in
`Linen/Agent/Providers/OpenAI`.

## Settings and tools

Open Settings > Assistant > OpenAI to configure voice, external connections,
and data use. Developer Settings contains advanced JSON and model overrides.

For supported models on the official OpenAI endpoint, Linen enables web search,
code interpreter, and image generation automatically. Model capability checks
control availability. Custom endpoints and utility jobs keep separate settings.
OpenAI usage charges apply.

Browser actions, including screenshot and pointer tools, pass through Linen's
permission checks. Hosted tools do not grant extra access to local tabs, files,
or credentials. Hosted shell runs in an OpenAI container; Linen does not
execute local shell commands from model output. Unknown action types stop with
an unsupported-action result.

The assistant can display citations, reasoning summaries, and generated images.
Users can save generated images and download cited files. Remote MCP connections
have a separate management page.

## Conversation state

The client preserves native response items, reasoning state, and response IDs
across tool calls and checkpoints. Native compaction preserves the returned input
window. The generic transcript remains available when switching providers.
Partial or failed responses do not execute local tools.

Connection reuse is managed for chat on the official endpoint. WebSocket
continuations send incremental input only when the stored history matches the
connection's cached prefix. Otherwise the client sends the full input. It does
not automatically replay failed or cancelled requests.

Reported token usage and timings are diagnostic data. Missing usage fields remain
unavailable. Prompts, answers, native reasoning state, attachments, and tool results
are private conversation data and must not enter diagnostic exports.

## Voice

OpenAI dictation uses microphone transcription. Voice conversations use the
Realtime connection and PCM playback, with browser work delegated to Linen's
assistant. Conversation text follows the chat's storage lifecycle. Users can
choose on-device voice in settings.

Voice preferences belong to the provider. Switching profiles or ending a voice
conversation stops its active session. Microphone access requires macOS permission.

## External connections

Remote MCP servers configured in OpenAI settings are separate from Linen's own
[MCP server](MCP.md). Linen's server shares selected browser tabs with an external
client. OpenAI connections let the built-in assistant use a remote service.

Remote service credentials stay in Keychain. OAuth and manually entered tokens
have separate storage. Connecting a service does not grant it browser permissions.
Tool approvals and browser action permissions remain separate checks.

## Validation

The default test suite uses fixtures. Live tests require an explicit opt-in and
may incur API charges. Use a normally signed development build to access Linen's
saved Keychain credential. An inherited `OPENAI_API_KEY` is also supported. Do not
put a key in command arguments or checked-in configuration.

Check credential availability without making API requests:

```sh
python3 Tools/validate-openai-live.py --build --output /tmp/linen-openai-preflight
```

Run live acceptance explicitly:

```sh
python3 Tools/validate-openai-live.py --live --output /tmp/linen-openai-live
```

Use `--model` to select an exact model. Separate modes include `--hosted-only`,
`--files-only`, `--voice-only`, `--conversation-only`, `--mcp-only`, and
`--tool-search-only`. See `--help` for their options. Use a fresh output directory
and the same derived-data path for the build and its tests.

Reports omit prompts, generated text, reasoning state, and credentials. Output
folders also contain local Xcode logs and test bundles. Review and share the
sanitized report rather than the whole directory. Voice service tests use
synthetic audio; they do not establish microphone or speaker quality.

Check for changes in the upstream SDK contract without an API key:

```sh
python3 Tools/check-openai-contract.py \
  --baseline Tools/openai-contract-baseline.json
```

The tool parses downloaded source without executing it. Review changed fields and
variants before updating the baseline with `--record`. A matching snapshot does
not establish support for every API operation.

Scripted browser checks require the separate `browser-agent-bench` checkout:

```sh
Tools/build-benchmark-adapter.sh
../browser-agent-bench/.venv/bin/python Tools/validate-agent-workflows.py \
  --provider openai --output /tmp/linen-openai-validation
```

These checks use synthetic token values. They validate browser outcomes and
accounting, not live cost or comparative model performance.
