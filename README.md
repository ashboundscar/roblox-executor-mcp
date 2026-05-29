# Roblox Executor MCP Server

This MCP (Model Context Protocol) server acts as a bridge between CLI and your Roblox Executor. It allows the AI to interact with the game environment in real-time.

## Features

- **Lua Execution**: Run arbitrary Luau code directly in the game.
- **Object Inspection**: List children and get detailed properties (including hidden ones, attributes, and tags).
- **Decompilation**: Retrieve the source code of any `LocalScript` or `ModuleScript`.
- **Remote Logging**: Intercept and view `RemoteEvent` and `RemoteFunction` calls with pagination and filtering.

## Installation

1. Navigate to the `mcp` directory:
   ```bash
   cd mcp
   ```
2. Install dependencies:
   ```bash
   npm install
   ```

## Gemini CLI Configuration

Add the following configuration to your `settings.json` (usually located in `%APPDATA%\gemini-cli\settings.json` on Windows):

```json
{
  "mcpServers": {
    "scarhack": {
      "command": "node",
      "args": [
        "C:\\Users\\Admin\\Documents\\Projects\\roblox-executor-mcp\\index.js"
      ]
    }
  }
}
```

*Note: Ensure the path to `index.js` matches your local project location.*

## Usage

1. Start Gemini CLI.
2. Inside Roblox, execute the `mcp.lua` script using your executor. You should see "MCP: HTTP Polling started!" in the console.
3. You can now use various commands to interact with the game.

## Available Tools

- `run_lua(code)` — Execute Luau code.
- `list_children(path)` — List children of an object (e.g., `game.Workspace`).
- `inspect_object(path)` — Get full details of an object (Properties, Attributes, Tags).
- `decompile_script(path)` — Decompile a script to view its source code.
- `get_remote_list()` — Get a list of unique names of captured Remote events.
- `get_remote_logs(page, name)` — View Remote logs (30 per page, max 10 pages).
- `search_objects(parentPath, name, className, limit, recursive)` — Search for objects using filters.

## Prompt Examples

### Basic Commands
- "Check my username and what weapon I'm holding."
- "Analyze all objects inside my Character."
- "Show me all properties of the player's Humanoid."
- "Run this code: `print('Hello from Sharpness')`"

### Advanced Usage (Exploration & Development)
- **Automatic ESP Development**: "Find all objects in `Workspace` that look like loot crates. Analyze their model structure to see if they have a `PrimaryPart`. Then, update the `places/2000062521.lua` script to include these crates in the ESP system with a custom mint color."
- **Visual Optimization**: "I can't see some highlights. Check if there's a limit of 31 highlights on my screen. If so, modify the `libraries/esp.lua` to disable `Highlight` objects that are outside my current camera viewport."
- **Reverse Engineering**: "Monitor the `RemoteEvents` while I shoot. Identify which remote is responsible for weapon fire. Then, decompile the `LocalScript` that calls this remote and explain how the recoil logic is implemented."
- **Memory Hacking**: "Scan the game's memory for any tables that contain the word `Recoil`. If you find them, write a Lua script to zero out all recoil-related values and ensure they stay at zero even after I switch weapons."