import type { Config } from "./config.js";

export interface CaptureItem {
  title: string;
  intent: string;
  alternatives: string | null;
  tag: string;
  commitHash: string;
  branch: string | null;
  changedFiles: string[];
  createdAt: string;
}

interface ApiResponse {
  success: boolean;
  response: {
    captures: CaptureItem[];
    total: number;
  } | null;
  error: { message: string } | null;
}

export class ApiClient {
  private readonly apiKey: string;
  private readonly endpoint: string;

  constructor(config: Config) {
    this.apiKey = config.apiKey;
    this.endpoint = config.endpoint;
  }

  async getFileHistory(filePath: string, limit: number): Promise<CaptureItem[]> {
    const params = new URLSearchParams({ filePath, limit: String(limit) });
    const data = await this.request(`/api/v1/captures/by-file?${params}`);
    return data?.captures ?? [];
  }

  async getRecentCaptures(days: number, limit: number): Promise<CaptureItem[]> {
    const params = new URLSearchParams({ days: String(days), limit: String(limit) });
    const data = await this.request(`/api/v1/captures/recent?${params}`);
    return data?.captures ?? [];
  }

  private async request(path: string): Promise<ApiResponse["response"]> {
    const url = `${this.endpoint}${path}`;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);

    try {
      const res = await fetch(url, {
        headers: {
          "X-API-Key": this.apiKey,
          "Accept": "application/json",
        },
        signal: controller.signal,
      });

      const body: ApiResponse = await res.json();

      if (!body.success) {
        throw new Error(body.error?.message ?? `HTTP ${res.status}`);
      }

      return body.response;
    } finally {
      clearTimeout(timeout);
    }
  }
}
