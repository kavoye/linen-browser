# Connect an external assistant

Linen provides a native MCP server. An external MCP client, such as Claude Code
or Codex, uses it to drive Linen with the same tools as Linen's own assistant.
The only difference is who runs the tools. Linen must be running. Linen's own
assistant does not need an API key, a model, or an open conversation for this.

1. In Settings, open **Assistant → External connections** and enable **MCP server**.
2. Click **Add** beside your MCP client.
3. Restart the client or reload its MCP connections. Other clients can use
   **Copy Configuration**.
4. Ask the client to do something in Linen. On its first tool call, Linen asks
   you to allow the connection. Click **Allow**.
5. The client works in the active tab of the window that had focus when it
   connected. Its tool calls appear in that tab's assistant conversation.

The prompt names the client and its developer. Linen reads the developer from
the code signature of the process that launched the connection. If Linen cannot
verify the signature, the prompt says so and shows the program's path.

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
when it connects. Switching focus does not move the connection to another
window. Closing that window, switching its profile, or quitting disconnects
affected clients. The relay reconnects on the next tool call, and Linen asks
you to allow the connection again. The relay never replays an interrupted call,
because the action may already have happened.

A private window does not accept new MCP connections. Connections already bound
to regular windows continue working. Use **Disconnect** beside a connection in
**Assistant → External connections** to revoke that connection immediately.

## Tools

The client receives the tools of Linen's own assistant, with the same names,
descriptions and argument schemas. Linen generates the MCP tool list from the
assistant's tool definitions, so a tool added to the assistant is also available
to clients. The only tool that clients do not receive is `askUser`, because the
client asks you questions in its own interface.

| Group | Tools |
| --- | --- |
| Research | `searchWeb`, `navigate`, `readPage`, `readArticle`, `goBack` |
| Interaction | `clickOnPage`, `typeOnPage`, `fillFields`, `selectOption`, `setChecked`, `scrollPage`, `hoverOnPage`, `pressKey` |
| Observation | `inspectControl`, `waitForPage`, `screenshotPage` |
| Visual | `movePointer`, `clickAtPoint`, `typeAtPointer`, `doubleClickAtPoint`, `dragOnPage` |
| Frames | `listFrames`, `readFrame`, `actInFrame` |
| Files | `chooseFilesOnPage`, `inspectDownloads` |
| Tabs | `listTabs`, `newTab`, `switchTab`, `closeTab` |
| Media | `playVideo`, `closeVideo`, `controlMedia` |
| Watches | `watchPage`, `listWatches`, `stopWatch` |

Tool results are the same text that Linen's assistant receives. Page tools take
an optional `page` argument (a page ID, title, site, or split position) and
default to the active tab. Actions need the `observationID` and the `[N]` ref
from the latest read or action result.

## Access

There is one permission model for Linen's assistant and external clients. The
connection approval is the only addition, and it exists because any program on
this Mac that runs as your user can open the local socket. The approval lets you
decide which program drives Linen; everything after that follows the rules you
already set for the assistant.

- **Connection approval.** Linen asks once per connection, on the first tool
  call. **Don't Allow** refuses every call from that connection without asking
  again. Reconnect the client to be asked again. Connecting and listing tools
  disclose no tabs or page content.
- **Assistant Access.** Each website's Assistant Access setting applies to
  external clients exactly as to the assistant. The setting covers the whole
  site, for example every page on google.com. A site set to Ask prompts you the
  first time a client reads or controls it. **Off** blocks it, and **Read Only**
  blocks clicks, typing and navigation on it.
- **Which tabs.** A client works in the active tab and in the tabs it opens,
  like the assistant does in a conversation. When you switch to another tab, the
  next call works there. Private windows are never available.
- **Sensitive actions.** Linen masks password and payment fields and refuses to
  fill them. Purchases, posts and other consequential actions use Linen's
  confirmation prompt, which names the client. An approval saved during a
  connection lasts only for that connection.
- **Addresses.** After a client reads a page, it opens only addresses from
  search results or page links, as the assistant does. A client cannot build an
  address from page content and open it.
- **One at a time.** External calls run one at a time. Starting a task in
  Linen's assistant cancels an active external call.

## Activity

A client's work appears in the tab's assistant conversation as a task, with the
same step list as the assistant's own tasks. When a client opens a tab, the task
also appears in that tab, as it does for the assistant. The tab shows the working state
while the client runs tools. A task ends when the client pauses for 20 seconds
or disconnects, and its message names the client. Verified clients from
Anthropic or OpenAI show that provider's icon. Settings shows each connected
client and its tool-call count. External tasks do not appear in Recent Tasks on
the start page, because there is no question to ask again.

The MCP transport stays on this Mac. Shared page data goes to the connected
application, which may send it to its own model provider. A local transport does
not imply that the external application's processing is local.

## Implementation

`Linen --mcp` starts a relay before initializing AppDelegate, profiles, databases,
or WebKit. It keeps a standard MCP stdio session alive independently of the
browser and forwards tool calls over a Unix socket. Browser connections are
initialized on demand, including after a restart. Connection approvals and
observations are never replayed. The official Swift MCP SDK handles protocol initialization,
tool discovery, calls, and cancellation. No TCP listener or HTTP endpoint is opened.
The relay exits when its client's stdin closes. Its tool catalog belongs to the
launched relay version. Reload the client connection after an update that changes
the tools, or once when upgrading from the old relay that exited on browser shutdown.

The socket is in a directory owned by the current OS user with mode `0700`.
The socket has mode `0600`. Directory and lock-file symlinks are rejected, and a
file lock prevents another Linen process from replacing the live endpoint.
Message sizes, buffered messages, and concurrent connections are bounded.

`MCPBrowserSession` is a thin adapter. Each connection gets its own
`AgentToolkit` on its window, and calls the same `Tool` values that
`makeAgentTools` builds for the assistant. `MCPToolCatalog` derives names,
descriptions and JSON schemas from `agentToolTypes`, so the relay can list tools
before the browser starts. An `AgentDriver` on the task tells the toolkit and the
confirmation prompts who is running. The server accepts connections with a BSD
socket so that it can read the peer's audit token. `MCPClientIdentity` then
checks that the peer is this Linen executable and reads the signature of the
process that launched it.

The SDK dependency is pinned in the Xcode project and package lockfile. Focused
tests live in `MCPPrivacyTests`, `MCPActivityTests`, `MCPWindowScopeTests` and
`MCPTransportTests` and use local fixtures.
