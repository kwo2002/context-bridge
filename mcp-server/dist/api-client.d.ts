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
export declare class ApiClient {
    private readonly apiKey;
    private readonly endpoint;
    constructor(config: Config);
    getFileHistory(filePath: string, limit: number): Promise<CaptureItem[]>;
    getRecentCaptures(days: number, limit: number): Promise<CaptureItem[]>;
    private request;
}
