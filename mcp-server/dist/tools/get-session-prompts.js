export async function handleGetSessionPrompts(apiClient, args) {
    const data = await apiClient.getSessionPrompts(args.sessionId);
    return formatSessionPrompts(data);
}
function formatSessionPrompts(data) {
    return [
        `## 세션 프롬프트 내용`,
        `- **작업 세션 ID:** ${data.workSessionId}`,
        ``,
        `### 대화 내용 (JSON Lines)`,
        data.content,
    ].join("\n");
}
