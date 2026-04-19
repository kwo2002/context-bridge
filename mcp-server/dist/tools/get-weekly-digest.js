export async function handleGetWeeklyDigest(apiClient, args) {
    const data = await apiClient.getWeeklyDigest(args.week);
    return formatWeeklyDigest(data);
}
function formatWeeklyDigest(data) {
    const lines = [];
    lines.push(`# 주간 다이제스트: ${data.week} (${data.startDate} ~ ${data.endDate})`);
    lines.push("");
    lines.push("## 팀 요약");
    lines.push(`- 커밋: ${data.teamStats.totalCommits}건 | 세션: ${data.teamStats.totalSessions}개 | 참여자: ${data.teamStats.activeMemberCount}명`);
    lines.push(`- 변경 파일: ${data.teamStats.totalChangedFiles}개`);
    const tagEntries = Object.entries(data.teamStats.tagBreakdown);
    if (tagEntries.length > 0) {
        lines.push(`- 태그: ${tagEntries.map(([tag, count]) => `${tag} ${count}`).join(", ")}`);
    }
    lines.push("");
    if (data.keyDecisions.length > 0) {
        lines.push("## 이번 주 핵심 의사결정");
        data.keyDecisions.forEach((decision, i) => {
            lines.push(`### ${i + 1}. [${decision.tag}] ${decision.title} — ${decision.userName}`);
            lines.push(`- **의도**: ${decision.intent}`);
            lines.push(`- **기각한 대안**: ${decision.alternatives}`);
            lines.push(`- 세션: ${decision.sessionName} | 커밋: ${decision.commitHash.substring(0, 7)}`);
            lines.push("");
        });
    }
    if (data.memberDigests.length > 0) {
        lines.push("## 팀원별 작업 내역");
        for (const member of data.memberDigests) {
            lines.push(`### ${member.userName} (세션 ${member.stats.sessions}개, 커밋 ${member.stats.commits}건)`);
            for (const session of member.sessions) {
                const files = session.changedFiles.slice(0, 5).join(", ");
                lines.push(`- **${session.sessionName}** (${session.date.substring(0, 10)}): 커밋 ${session.commitCount}건, 파일: ${files}`);
            }
            if (member.topChangedFiles.length > 0) {
                lines.push(`- 주요 변경 파일: ${member.topChangedFiles.join(", ")}`);
            }
            lines.push("");
        }
    }
    if (data.mostChangedFiles.length > 0) {
        lines.push("## 가장 많이 변경된 파일 (Top 10)");
        lines.push("| 파일 | 변경 횟수 | 관련 태그 |");
        lines.push("|------|-----------|-----------|");
        for (const file of data.mostChangedFiles) {
            lines.push(`| ${file.file} | ${file.changeCount} | ${file.tags.join(", ")} |`);
        }
    }
    return lines.join("\n");
}
