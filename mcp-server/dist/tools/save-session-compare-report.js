export async function handleSaveSessionCompareReport(apiClient, args) {
    const result = await apiClient.saveSessionCompareReport(args.sessionId1, args.sessionId2, args.title, args.content);
    return `세션 비교 보고서가 저장되었습니다.\n- **보고서 ID:** ${result.reportId}\n- **세션 1:** ${result.sessionId1}\n- **세션 2:** ${result.sessionId2}\n- **생성 시각:** ${result.createdAt}`;
}
