const { Server } = require("@modelcontextprotocol/sdk/server/index.js");
const { StdioServerTransport } = require("@modelcontextprotocol/sdk/server/stdio.js");
const {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} = require("@modelcontextprotocol/sdk/types.js");
const http = require("http");

const HTTP_PORT = 8080;

let pendingToolCalls = []; // Queue of tasks for Roblox
const activeRequests = new Map(); // Pending responses from Roblox
let requestIdCounter = 0;

// Create HTTP server for Roblox communication
const httpServer = http.createServer((req, res) => {
  res.setHeader("Content-Type", "application/json");

  if (req.method === "POST") {
    let body = "";
    req.on("data", (chunk) => { body += chunk; });
    req.on("end", () => {
      try {
        const data = JSON.parse(body);
        
        // If Roblox sent a result
        if (data.type === "result") {
          if (activeRequests.has(data.id)) {
            const { resolve } = activeRequests.get(data.id);
            activeRequests.delete(data.id);
            resolve(data.result);
          }
          res.end(JSON.stringify({ status: "ok" }));
        } 
        // If Roblox is polling for new tasks
        else if (data.type === "poll") {
          if (pendingToolCalls.length > 0) {
            const nextCall = pendingToolCalls.shift();
            res.end(JSON.stringify(nextCall));
          } else {
            res.end(JSON.stringify({ type: "idle" }));
          }
        }
      } catch (err) {
        res.statusCode = 400;
        res.end(JSON.stringify({ error: "Invalid JSON" }));
      }
    });
  } else {
    res.statusCode = 404;
    res.end();
  }
});

httpServer.listen(HTTP_PORT, () => {
  console.error(`HTTP Bridge for Roblox running on port ${HTTP_PORT}`);
});

const server = new Server(
  { name: "roblox-executor-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

async function sendToRoblox(method, params) {
  const id = requestIdCounter++;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      activeRequests.delete(id);
      reject(new Error("Roblox request timed out (polling delay?)"));
    }, 15000);

    activeRequests.set(id, {
      resolve: (val) => {
        clearTimeout(timeout);
        resolve(val);
      },
    });

    pendingToolCalls.push({ id, method, params });
  });
}

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "run_lua",
        description: "Executes arbitrary Luau code in-game and returns the result.",
        inputSchema: {
          type: "object",
          properties: { code: { type: "string", description: "Code to execute" } },
          required: ["code"],
        },
      },
      {
        name: "list_children",
        description: "Returns a list of child objects for a given path.",
        inputSchema: {
          type: "object",
          properties: { path: { type: "string", description: "Path to object (e.g., 'game.Workspace')" } },
          required: ["path"],
        },
      },
      {
        name: "inspect_object",
        description: "Retrieves object details: properties, class, and attributes.",
        inputSchema: {
          type: "object",
          properties: { path: { type: "string", description: "Path to object" } },
          required: ["path"],
        },
      },
      {
        name: "decompile_script",
        description: "Decompiles a specified script (LocalScript or ModuleScript).",
        inputSchema: {
          type: "object",
          properties: { path: { type: "string", description: "Path to script" } },
          required: ["path"],
        },
      },
      {
        name: "get_remote_list",
        description: "Returns call statistics for captured Remotes (name and count).",
        inputSchema: { type: "object", properties: {} },
      },
      {
        name: "get_remote_logs",
        description: "Returns Remote event logs with pagination (30 per page, max 10 pages).",
        inputSchema: {
          type: "object",
          properties: {
            page: { type: "number", description: "Page number (1-10)", default: 1 },
            name: { type: "string", description: "Optional filter by Remote name" }
          },
        },
      },
      {
        name: "search_objects",
        description: "Searches for objects in the game using filters (name, class).",
        inputSchema: {
          type: "object",
          properties: {
            parentPath: { type: "string", description: "Search root path", default: "game" },
            name: { type: "string", description: "Partial object name" },
            className: { type: "string", description: "Exact class name" },
            limit: { type: "number", description: "Maximum number of results", default: 50 },
            recursive: { type: "boolean", description: "Recursive search", default: true }
          },
          required: ["parentPath"],
        },
      },
    ],
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  try {
    const result = await sendToRoblox(name, args);
    return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] };
  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${error.message}` }],
      isError: true,
    };
  }
});

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Roblox Executor MCP Server (HTTP Mode) running");
}

main().catch(console.error);