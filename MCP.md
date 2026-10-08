# Connect an external assistant

Linen provides a native MCP server for controlling shared browser tabs from an
external MCP client. Linen must be running. Linen's own assistant does not need
an API key, a model, or an open conversation for this.

1. In Settings, open **Advanced → External Connections** and enable **MCP server**.
2. Click **Add** beside your MCP client. Restart the client or reload its MCP
   connections. Other clients can use **Copy Configuration**.
3. Open the webpages you want to share in Linen. A split view can share several
   pages together.
4. Have the client call `requestAccess`. Linen comes to the foreground and opens
   an approval prompt for the displayed pages. Choose **Read Only** or
   **Allow Control**.
   If no shareable webpage is open, the prompt tells you so. Open a webpage and
   have the client request access again.
5. The client calls `listTabs`, then `readPage` with a returned `tabID`. Page
   actions use that tab ID, the returned `observationID`, and a numbered `ref`.

The copied configuration uses the path of the running app. For an installation
in Applications, a client accepting the common JSON configuration format uses:

```json
{
  "mcpServers": {
    "linen": {
      "command": "/Applications/Linen.app/Contents/MacOS/Linen",
      "args": ["--mcp"]
    }
  }
}
```

## Automatic client setup

Linen detects the standard macOS app, command-line tool, and configuration
locations for these clients:

| Client | User configuration |
| --- | --- |
| Codex | `~/.codex/config.toml`, or `$CODEX_HOME/config.toml` when Linen inherits that environment variable |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Claude Code | `~/.claude.json`, with the server added at user scope |
| Cursor | `~/.cursor/mcp.json` |

The **Copy Configuration** button sits above the client list. Use the
**… → Choose Configuration…** action beside a client for an existing
custom profile or another configuration location. Linen does not scan your
shell aliases or project directories. **… → Show Configuration** shows the
selected file in Finder. The client rows do not show file paths.

Linen reads the **Added** state from the saved configuration when this page
opens and when Linen becomes active again. This includes entries configured
elsewhere. These checks do not change the client configuration.

Setup merges only a `linen` server entry into the chosen configuration. It keeps
other servers, client settings, and project-specific entries. If an entry with
the same command and argument exists, setup leaves it unchanged, including any
disabled state or custom client permissions. If a different entry named `linen`
exists, setup reports a conflict and does not overwrite it. Review it in the
client if you move Linen to a new location. Setup does not enable MCP tools that
the client has disabled.

Before changing an existing file, Linen saves its exact bytes beside it as
`<filename>.linen-backup-<unique ID>`. **… → Show Backup** shows that copy.
Only your OS user can read backups and replacements (`0600`). Backups can
include credentials for your other servers, so keep them private. Setup
rejects linked, malformed, unsupported, or oversized files and checks for
concurrent edits before replacing a file atomically. JSON-with-comments files
can use the manual configuration route instead.

Codex setup uses the installed Codex CLI, including the executable bundled in
its desktop app, to parse and edit a private temporary copy of its TOML. This
preserves TOML syntax and comments without maintaining a second parser in
Linen. Setup deletes the temporary copy afterward. It does not launch a model,
connect a server, import client history, or grant access to browser tabs.

Configuration formats follow the official documentation for
[Codex](https://learn.chatgpt.com/docs/extend/mcp?surface=cli),
[Claude Desktop](https://modelcontextprotocol.io/docs/develop/connect-local-servers),
[Claude Code](https://code.claude.com/docs/en/mcp), and
[Cursor](https://cursor.com/docs/mcp).

Clients with a different settings format need the same command and argument.
Restart the client's connection after moving the app or enabling the server.
The server is off until you enable it. After that, it stays on across launches
and profile changes. Each connection uses the regular window that has focus
when it connects. Switching focus does not change its tabs or sharing grants.
Closing that window, switching its profile, or quitting disconnects affected
clients and clears their grants. The relay reconnects on the next tool call,
and the client must request sharing approval again. The relay never replays an
interrupted call, because the action may already have happened.

A private window does not accept new MCP connections. Connections already bound
to regular windows continue working. Use **Disconnect** beside a connection in
Advanced settings to revoke that connection immediately.

## Tools in this version

| Tool | Behavior |
| --- | --- |
| `requestAccess` | Ask once to share the webpages currently on screen. |
| `listTabs` | List only tabs shared with this connection. |
| `readPage` | Search rendered text, scope or paginate controls, and return an observation ID. |
| `clickOnPage` | Click a numbered control from that observation. |
| `typeOnPage` | Fill a nonsensitive field, optionally submitting it. |
| `selectOption` | Choose an option in a select control. |
| `fillFields` | Fill up to 32 text, dropdown, date, color, range, checkbox, or radio controls without submitting; report verified refs and per-field failures. |
| `inspectControl` | Read control state and paginate dropdown options. |
| `setChecked` | Set a checkbox, switch, or radio to the requested state. |
| `waitForPage` | Wait for text, absent text, a URL substring, or document readiness, up to 15 seconds. |
| `screenshotPage` | Return a viewport image; refuse capture when detected sensitive fields are filled. |
| `pressKey` | Send a supported keyboard key to a control in a visible tab. |
| `hoverOnPage` | Dispatch pointer/mouse hover handlers. CSS-only hover is unsupported. |
| `scrollPage` | Scroll vertically or horizontally, optionally inside a referenced container. |
| `goBack` | Go back within the shared website. |
| `navigate` | Navigate a shared tab; another website requires approval. |
| `newTab` | Ask to open and share a new webpage. Requires existing control access. |
| `switchTab` | Activate an already shared tab before controlling it. |
| `closeTab` | Close an already shared, unpinned tab. |

This first version covers browser page and tab actions. Assistant conversations,
background research, the media player, arbitrary JavaScript, desktop screenshots,
cookies, credential stores, and filesystem access are not exposed.

Successful page actions return fresh controls and an `observationID`; reuse that result for
the next action. A partial batch can also return fresh controls while `isError` remains true.
Check the completed count before continuing. Reads and actions share the same isolated
page runtime and document-bound references. Linen refuses a stale, replaced, or unobserved target.

Use `lookingFor` to search beyond the first excerpt, `scope` for a CSS control subtree,
`viewportOnly` for visible controls, and `textOffset` / `controlOffset` to continue.
Keep the query and scope unchanged when paging. Text offsets use UTF-16 units.
The standard text response budget is about 6 KB before MCP framing; screenshot data is separate.
Use screenshots only when text and control state do not answer the task.


## Privacy boundaries

- Connecting and discovering tools disclose no tabs or page content. Every
  connection starts with no grants. The client supplies the name Linen shows.
  It is not a verified app identity.
- Access is restricted to the captured tab IDs and their website origins. Other
  tabs, private browsing, internal pages, and denied sites cannot be listed or
  addressed by guessing an ID. Redirecting to another website does not grant
  access to its contents. Reconnect and request sharing again when needed.
- External sharing grants are separate from the assistant's site grants.
  **Assistant Access: Off** blocks external access; **Read Only** blocks external
  control even when the connection has a control grant. External sharing does
  not change those settings.
- The existing page driver detects and masks sensitive fields and refuses to
  fill them. Consequential actions use Linen's native confirmation UI. External
  confirmations do not inherit the assistant's saved action approvals. An
  approval saved during a connection lasts only for that connection.
- External page scripts run in WebKit's isolated client world. Observation IDs
  belong to one connection and one document. Another read invalidates the
  underlying control snapshot. Linen checks revocation and navigation again
  after suspension and before it returns page data.
- After reading untrusted content, outbound navigation must use an observed
  link, including its query string. The client cannot construct an arbitrary
  address from page content and navigate to it through these tools.
- External calls run one at a time. Starting an in-browser assistant task
  cancels an active external call. External calls do not enter the assistant's
  conversation history. Settings shows connected clients, grant counts, and
  tool-call counts. Linen does not save page bodies or arguments as MCP logs.

The MCP transport stays on this Mac. Shared page data goes to the connected
application, which may send it to its own model provider. A local transport does
not imply that the external application's processing is local.

## Implementation

`Linen --mcp` starts a relay before initializing AppDelegate, profiles, databases,
or WebKit. It keeps a standard MCP stdio session alive independently of the
browser and forwards tool calls over a Unix socket. Browser connections are
initialized on demand, including after a restart; sharing grants and observations
are never replayed. The official Swift MCP SDK handles protocol initialization,
tool discovery, calls, and cancellation. No TCP listener or HTTP endpoint is opened.
The relay exits when its client's stdin closes. Its tool catalog belongs to the
launched relay version. Reload the client connection after an update that changes
the tools, or once when upgrading from the old relay that exited on browser shutdown.

The socket is in a directory owned by the current OS user with mode `0700`.
The socket has mode `0600`. Directory and lock-file symlinks are rejected, and a
file lock prevents another Linen process from replacing the live endpoint.
Message sizes, buffered messages, and concurrent connections are bounded.

`MCPBrowserSession` owns external grants, observations, and transient activity.
It calls the existing `PageDriver` and honors `TabAssistantAccessCenter` policy.
`AgentToolkit` and assistant conversation scoping retain their existing behavior.
`PageAutomationGuard` supplies additional revocation and document checks only
while an external page call is executing.

The SDK dependency is pinned in the Xcode project and package lockfile. Focused
tests live in `MCPPrivacyTests` and `MCPTransportTests` and use local fixtures.
