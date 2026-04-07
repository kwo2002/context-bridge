#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { loadConfig } from "./config.js";
import { ApiClient } from "./api-client.js";
import { handleGetFileHistory } from "./tools/get-file-history.js";
import { handleGetRecentCaptures } from "./tools/get-recent-captures.js";

const config = loadConfig();

const server = new McpServer({
  name: "context-bridge",
  version: "1.0.0",
});

server.tool(
  "get_file_history",
  "Retrieve past capture history for a specific file. Returns intent, alternatives considered, and key changes from previous work on this file.",
  {
    filePath: z.string().describe("File path to search for (e.g., 'src/main/PaymentService.kt')"),
    limit: z.number().optional().describe("Maximum number of results (default: 10)"),
  },
  async ({ filePath, limit }) => {
    if (!config) {
      return {
        content: [{ type: "text" as const, text: "Context Bridge is not configured. Place context-bridge.yml in your project root." }],
      };
    }
    const apiClient = new ApiClient(config);
    try {
      const text = await handleGetFileHistory(apiClient, { filePath, limit });
      return { content: [{ type: "text" as const, text }] };
    } catch (e) {
      return { content: [{ type: "text" as const, text: `Error querying Context Bridge: ${e instanceof Error ? e.message : String(e)}` }] };
    }
  }
);

server.tool(
  "get_recent_captures",
  "Retrieve recent capture entries. Returns a summary of recent work including intent, alternatives, and key changes.",
  {
    days: z.number().optional().describe("Number of days to look back (default: 7)"),
    limit: z.number().optional().describe("Maximum number of results (default: 20)"),
  },
  async ({ days, limit }) => {
    if (!config) {
      return {
        content: [{ type: "text" as const, text: "Context Bridge is not configured. Place context-bridge.yml in your project root." }],
      };
    }
    const apiClient = new ApiClient(config);
    try {
      const text = await handleGetRecentCaptures(apiClient, { days, limit });
      return { content: [{ type: "text" as const, text }] };
    } catch (e) {
      return { content: [{ type: "text" as const, text: `Error querying Context Bridge: ${e instanceof Error ? e.message : String(e)}` }] };
    }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("MCP Server failed to start:", error);
  process.exit(1);
});
