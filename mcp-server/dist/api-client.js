export class ApiClient {
    apiKey;
    endpoint;
    constructor(config) {
        this.apiKey = config.apiKey;
        this.endpoint = config.endpoint;
    }
    async getFileHistory(filePath, limit) {
        const params = new URLSearchParams({ filePath, limit: String(limit) });
        const data = await this.request(`/api/v1/captures/by-file?${params}`);
        return data?.captures ?? [];
    }
    async getRecentCaptures(days, limit) {
        const params = new URLSearchParams({ days: String(days), limit: String(limit) });
        const data = await this.request(`/api/v1/captures/recent?${params}`);
        return data?.captures ?? [];
    }
    async request(path) {
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
            const body = await res.json();
            if (!body.success) {
                throw new Error(body.error?.message ?? `HTTP ${res.status}`);
            }
            return body.response;
        }
        finally {
            clearTimeout(timeout);
        }
    }
}
