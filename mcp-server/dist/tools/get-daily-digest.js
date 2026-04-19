export async function handleGetDailyDigest(apiClient, args) {
    const data = await apiClient.getDailyDigest(args.date);
    return formatDailyDigest(data);
}
function formatDailyDigest(data) {
    const lines = [];
    lines.push(`## 일일 다이제스트: ${data.date}`);
    lines.push(`- **총 커밋 수:** ${data.summary.totalCommits}`);
    lines.push(`- **총 세션 수:** ${data.summary.totalSessions}`);
    lines.push(`- **총 변경 파일 수:** ${data.summary.totalChangedFiles}`);
    const tagEntries = Object.entries(data.summary.tagBreakdown);
    if (tagEntries.length > 0) {
        lines.push(`- **태그 분류:** ${tagEntries.map(([tag, count]) => `${tag}(${count})`).join(", ")}`);
    }
    lines.push("");
    if (data.sessions.length > 0) {
        lines.push("### 세션 목록");
        for (const session of data.sessions) {
            lines.push(`\n#### ${session.sessionName}`);
            lines.push(`- **세션 ID:** ${session.sessionId}`);
            lines.push(`- **커밋 수:** ${session.commits}`);
            lines.push(`- **변경 파일:** ${session.changedFiles.join(", ")}`);
            if (session.keyDecisions.length > 0) {
                lines.push(`- **주요 의사결정:**`);
                for (const decision of session.keyDecisions) {
                    lines.push(`  - ${decision}`);
                }
            }
        }
    }
    if (data.mostChangedFiles.length > 0) {
        lines.push("\n### 가장 많이 변경된 파일");
        for (const file of data.mostChangedFiles) {
            lines.push(`- **${file.file}** — ${file.changeCount}회 변경 (${file.tags.join(", ")})`);
        }
    }
    return lines.join("\n");
}
