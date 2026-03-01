# MedaDebug

Developer toolkit for World of Warcraft addon development with AI agent integration.

## Features

### Error Handling
- **Automatic error capture** via `seterrorhandler` -- catches all Lua errors before other addons
- **Smart error classification** -- identifies nil access, type mismatches, taint, secret value errors, and more
- **Error grouping** -- duplicate errors are grouped by signature with occurrence counts
- **Error suppression** -- suppress noisy errors so they log silently without triggering the notification icon or badge count. Suppressed signatures persist across sessions.
- **Blizzard error popup replacement** -- hides the blocking `ScriptErrorsFrame` and shows a subtle, non-blocking text notice at the top of the screen instead. No more "disable addons or reload" interrupting combat.
- **BugGrabber integration** -- automatically uses BugGrabber as error source when available

### Debug Output
- **Multi-addon message routing** -- any addon can register and send categorized messages (DEBUG, INFO, WARN, ERROR)
- **Addon filtering** -- filter messages by source addon
- **Session persistence** -- messages and errors survive `/reload`

### Live Monitoring
- **Event Monitor** -- real-time WoW event stream with category filtering and throttling
- **System Monitor** -- FPS, memory usage, and latency polling with per-addon memory breakdown
- **Timer Tracker** -- hooks `C_Timer` to track active timers across all addons
- **Frame Inspector** -- click-to-inspect any UI frame with property viewer and ignore list

### Developer Tools
- **Lua Console** -- execute arbitrary Lua with autocomplete and pretty-printed table output
- **Variable Watch** -- watch any global variable path with live updates
- **SavedVariables Diff** -- take snapshots and diff SavedVariables to see what changed
- **Secrets Explorer** -- inspect WoW 12.0+ secret/restricted values

### UI
- **Tabbed debug window** with Messages, Errors, Events, Console, Inspector, Watch, Timers, and System tabs
- **Floating error notification** -- draggable icon with red badge count (configurable size and opacity)
- **Minimap button** -- left-click toggles debug window, right-click opens settings
- **Settings panel** -- configure all options without editing SavedVariables

## Slash Commands

| Command | Description |
|---------|-------------|
| `/mdebug` | Toggle debug window |
| `/mdebug settings` | Open settings panel |
| `/mdebug dev` | Toggle development mode (auto-show on login) |
| `/mdebug errors` | Show errors tab |
| `/mdebug msgs` | Show messages tab |
| `/mdebug events` | Show events tab |
| `/mdebug console` | Show console tab |
| `/mdebug inspect` | Start frame inspect mode |
| `/mdebug watch <path>` | Watch a variable |
| `/mdebug run <code>` | Execute Lua code |
| `/mdebug snapshot` | Take SavedVariables snapshot |
| `/mdebug diff` | Show SavedVariables diff |
| `/mdebug clear [all]` | Clear current tab or all |
| `/mdebug help` | Show all commands |
| `/mderrors` | Quick error summary (works even if UI is broken) |

## API Usage

Other addons can send debug messages to MedaDebug:

```lua
-- Register your addon
MedaDebug:RegisterAddon("MyAddon", {
    color = {0.6, 0.8, 1},
})

-- Send messages at different levels
MedaDebug:Log("MyAddon", "Player loaded", "INFO")
MedaDebug:Log("MyAddon", "Cache miss for item 12345", "DEBUG")
MedaDebug:Log("MyAddon", "Failed to parse response", "WARN")
```

## Installation

1. Clone or download into your WoW `Interface/AddOns/` folder
2. MedaDebug depends on [MedaUI](https://github.com/Medalink/MedaUI) -- include it as a submodule or install alongside

## License

MIT License. See [LICENSE](LICENSE) for details.
