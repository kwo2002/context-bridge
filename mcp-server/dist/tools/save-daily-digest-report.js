export async function handleSaveDailyDigestReport(apiClient, args) {
    const result = await apiClient.saveDailyDigestReport(args.date, args.title, args.content);
    return `일일 다이제스트 보고서가 저장되었습니다.\n- **보고서 ID:** ${result.reportId}\n- **대상 날짜:** ${result.date}\n- **생성 시각:** ${result.createdAt}`;
}
