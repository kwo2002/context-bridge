export async function handleSavePromptEvaluationReport(apiClient, args) {
    const result = await apiClient.savePromptEvaluationReport(args.sessionId, args.title, args.content);
    return [
        `프롬프트 평가 보고서가 저장되었습니다.`,
        `- **보고서 ID:** ${result.reportId}`,
        `- **작업 세션 ID:** ${result.workSessionId}`,
        `- **프로젝트:** ${result.projectName}`,
        `- **생성 시각:** ${result.createdAt}`,
    ].join("\n");
}
