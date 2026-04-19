export async function handleSaveWeeklyDigestReport(apiClient, args) {
    const result = await apiClient.saveWeeklyDigestReport(args.week, args.title, args.content);
    return `주간 다이제스트 보고서가 저장되었습니다.\n- **보고서 ID:** ${result.reportId}\n- **대상 주차:** ${result.week}\n- **생성 시각:** ${result.createdAt}`;
}
