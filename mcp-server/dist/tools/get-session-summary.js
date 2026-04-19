export async function handleGetSessionSummary(apiClient, args) {
    const data = await apiClient.getSessionSummary(args.sessionId);
    return formatSessionSummary(data);
}
function formatSessionSummary(data) {
    const lines = [];
    lines.push(`## 세션 요약: ${data.sessionName}`);
    lines.push(`- **세션 ID:** ${data.sessionId}`);
    lines.push(`- **시작 시각:** ${data.startedAt}`);
    lines.push(`- **총 커밋 수:** ${data.summary.totalCommits}`);
    lines.push(`- **변경 파일:** ${data.summary.changedFiles.join(", ")}`);
    const tagEntries = Object.entries(data.summary.tagBreakdown);
    if (tagEntries.length > 0) {
        lines.push(`- **태그 분류:** ${tagEntries.map(([tag, count]) => `${tag}(${count})`).join(", ")}`);
    }
    lines.push("");
    for (const entry of data.entries) {
        lines.push(`### ${entry.title}`);
        lines.push(`- **Tag:** ${entry.tag}`);
        lines.push(`- **Commit:** ${entry.commitHash}`);
        lines.push(`- **Date:** ${entry.createdAt}`);
        lines.push(`- **Files:** ${entry.changedFiles.join(", ")}`);
        lines.push(`\n**Intent:**\n${entry.intent}`);
        if (entry.alternatives) {
            lines.push(`\n**Alternatives considered:**\n${entry.alternatives}`);
        }
        lines.push("---");
    }
    return lines.join("\n");
}
