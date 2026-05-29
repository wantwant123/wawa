import Foundation

struct AIChatClient {
    private struct RequestBody: Codable {
        let model: String
        let messages: [Message]
    }

    private struct Message: Codable {
        let role: String
        let content: String
    }

    private struct ResponseBody: Codable {
        let choices: [Choice]
        let error: APIError?
    }

    private struct Choice: Codable {
        let message: Message
    }

    private struct APIError: Codable {
        let message: String?
    }

    let settings: AppSettings

    func complete(prompt: String) async throws -> String {
        guard !settings.aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentProcessingError.failed("还没有填写 AI API Key")
        }
        guard let url = URL(string: settings.aiEndpoint) else {
            throw DocumentProcessingError.failed("AI 接口地址不正确")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(settings.aiAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(
                model: settings.aiModel,
                messages: [
                    Message(role: "user", content: prompt)
                ]
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(ResponseBody.self, from: data)

        guard (200..<300).contains(status) else {
            let message = decoded?.error?.message ?? String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw DocumentProcessingError.failed("AI 请求失败：\(message)")
        }

        guard let content = decoded?.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw DocumentProcessingError.failed("AI 没有返回内容")
        }

        return content
    }
}
