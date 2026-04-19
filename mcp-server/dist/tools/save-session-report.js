export async function handleSaveSessionReport(apiClient, args) {
    const result = await apiClient.saveSessionReport(args.sessionId, args.title, args.content);
    return `보고서가 저장되었습니다.\n- **보고서 ID:** ${result.reportId}\n- **세션 ID:** ${result.sessionId}\n- **생성 시각:** ${result.createdAt}\n\n대시보드에서 확인할 수 있습니다.`;
}
