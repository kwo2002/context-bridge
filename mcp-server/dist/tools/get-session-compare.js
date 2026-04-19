export async function handleGetSessionCompare(apiClient, args) {
    const data = await apiClient.compareSessions(args.sessionId1, args.sessionId2);
    return formatSessionCompare(data);
}
function formatSessionCompare(data) {
    const lines = [];
    lines.push("## 세션 비교 결과");
    lines.push("");
    lines.push(`### 세션 1: ${data.session1.sessionName}`);
    lines.push(`- **세션 ID:** ${data.session1.sessionId}`);
    lines.push(`- **날짜:** ${data.session1.date}`);
    lines.push(`- **커밋 수:** ${data.session1.commits}`);
    lines.push(`- **태그:** ${Object.entries(data.session1.tags).map(([t, c]) => `${t}(${c})`).join(", ")}`);
    lines.push(`- **변경 파일:** ${data.session1.changedFiles.join(", ")}`);
    if (data.session1.keyDecisions.length > 0) {
        lines.push(`- **주요 의사결정:**`);
        for (const d of data.session1.keyDecisions) {
            lines.push(`  - ${d}`);
        }
    }
    lines.push("");
    lines.push(`### 세션 2: ${data.session2.sessionName}`);
    lines.push(`- **세션 ID:** ${data.session2.sessionId}`);
    lines.push(`- **날짜:** ${data.session2.date}`);
    lines.push(`- **커밋 수:** ${data.session2.commits}`);
    lines.push(`- **태그:** ${Object.entries(data.session2.tags).map(([t, c]) => `${t}(${c})`).join(", ")}`);
    lines.push(`- **변경 파일:** ${data.session2.changedFiles.join(", ")}`);
    if (data.session2.keyDecisions.length > 0) {
        lines.push(`- **주요 의사결정:**`);
        for (const d of data.session2.keyDecisions) {
            lines.push(`  - ${d}`);
        }
    }
    lines.push("");
    lines.push("### 비교 분석");
    lines.push(`- **공통 변경 파일:** ${data.comparison.overlappingFiles.length > 0 ? data.comparison.overlappingFiles.join(", ") : "없음"}`);
    lines.push(`- **세션 2 신규 파일:** ${data.comparison.newFilesInSession2.length > 0 ? data.comparison.newFilesInSession2.join(", ") : "없음"}`);
    lines.push(`- **연속 작업:** ${data.comparison.continuedWork ? "예" : "아니오"}`);
    lines.push(`- **태그 변화:** ${data.comparison.tagShift}`);
    return lines.join("\n");
}
