import Foundation

actor OpenSubtitlesClient {
  private let session: URLSession
  private let configuration: Configuration?
  private var authToken: String?

  init(
    session: URLSession = .shared,
    configuration: Configuration? = Configuration.fromEnvironment()
  ) {
    self.session = session
    self.configuration = configuration
  }

  func isConfigured() -> Bool {
    configuration != nil
  }

  func searchSubtitles(query: String, language: String = "en") async throws -> [RemoteSubtitleSearchResult] {
    guard let configuration else {
      throw OpenSubtitlesError.notConfigured
    }

    var components = URLComponents(url: configuration.baseURL.appending(path: "/api/v1/subtitles"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "query", value: query),
      URLQueryItem(name: "languages", value: language),
      URLQueryItem(name: "order_by", value: "download_count"),
      URLQueryItem(name: "order_direction", value: "desc")
    ]

    guard let url = components?.url else {
      throw OpenSubtitlesError.invalidResponse
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.addValue(configuration.apiKey, forHTTPHeaderField: "Api-Key")
    request.addValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")

    if let token = try await tokenIfAvailable() {
      request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw OpenSubtitlesError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw OpenSubtitlesError.requestFailed(statusCode: httpResponse.statusCode)
    }

    let payload = try JSONDecoder().decode(SearchResponse.self, from: data)

    var results: [RemoteSubtitleSearchResult] = []
    for item in payload.data {
      for file in item.attributes.files {
        results.append(
          RemoteSubtitleSearchResult(
            id: file.fileID,
            fileID: file.fileID,
            fileName: file.fileName,
            languageCode: item.attributes.language,
            languageName: item.attributes.languageName,
            release: item.attributes.releaseText,
            title: item.attributes.featureDetails?.title
          )
        )
      }
    }

    return results
  }

  func downloadSubtitle(fileID: Int) async throws -> (fileName: String, subtitleText: String) {
    guard let configuration else {
      throw OpenSubtitlesError.notConfigured
    }

    let token = try await tokenIfAvailable()

    let downloadURL = configuration.baseURL.appending(path: "/api/v1/download")
    var request = URLRequest(url: downloadURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 20
    request.addValue(configuration.apiKey, forHTTPHeaderField: "Api-Key")
    request.addValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
    if let token {
      request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(DownloadRequest(fileID: fileID, format: "srt"))

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw OpenSubtitlesError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw OpenSubtitlesError.requestFailed(statusCode: httpResponse.statusCode)
    }

    let payload = try JSONDecoder().decode(DownloadResponse.self, from: data)
    let linkRequest = URLRequest(url: payload.link)
    let (subtitleData, subtitleResponse) = try await session.data(for: linkRequest)

    guard let subtitleHTTPResponse = subtitleResponse as? HTTPURLResponse,
      (200..<300).contains(subtitleHTTPResponse.statusCode)
    else {
      throw OpenSubtitlesError.invalidResponse
    }

    guard let text = String(data: subtitleData, encoding: .utf8) else {
      throw OpenSubtitlesError.unreadableSubtitle
    }

    return (payload.fileName, text)
  }

  private func tokenIfAvailable() async throws -> String? {
    if let authToken {
      return authToken
    }

    guard let configuration, let username = configuration.username, let password = configuration.password else {
      return nil
    }

    var request = URLRequest(url: configuration.baseURL.appending(path: "/api/v1/login"))
    request.httpMethod = "POST"
    request.timeoutInterval = 20
    request.addValue(configuration.apiKey, forHTTPHeaderField: "Api-Key")
    request.addValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(LoginRequest(username: username, password: password))

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw OpenSubtitlesError.invalidResponse
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw OpenSubtitlesError.requestFailed(statusCode: httpResponse.statusCode)
    }

    let payload = try JSONDecoder().decode(LoginResponse.self, from: data)
    authToken = payload.token
    return payload.token
  }
}

extension OpenSubtitlesClient {
  struct Configuration {
    let apiKey: String
    let username: String?
    let password: String?
    let userAgent: String
    let baseURL: URL

    static func fromAPIKey(_ value: String) -> Self? {
      let apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !apiKey.isEmpty else {
        return nil
      }

      let env = ProcessInfo.processInfo.environment
      return Self(
        apiKey: apiKey,
        username: env["OPEN_SUBTITLES_USERNAME"],
        password: env["OPEN_SUBTITLES_PASSWORD"],
        userAgent: "JustPlayNative 1.0",
        baseURL: URL(string: "https://api.opensubtitles.com")!
      )
    }

    static func fromEnvironment() -> Self? {
      let env = ProcessInfo.processInfo.environment
      guard let apiKey = env["OPEN_SUBTITLES_API_KEY"] else {
        return nil
      }

      return fromAPIKey(apiKey)
    }
  }

  enum OpenSubtitlesError: LocalizedError {
    case notConfigured
    case requestFailed(statusCode: Int)
    case unreadableSubtitle
    case invalidResponse

    var errorDescription: String? {
      switch self {
      case .notConfigured:
        return "OpenSubtitles API key is not configured."
      case .requestFailed(let statusCode):
        return "Subtitle service request failed (\(statusCode))."
      case .unreadableSubtitle:
        return "Downloaded subtitle could not be decoded as UTF-8 text."
      case .invalidResponse:
        return "Subtitle service returned an invalid response."
      }
    }
  }
}

private extension OpenSubtitlesClient {
  struct SearchResponse: Decodable {
    let data: [SearchData]
  }

  struct SearchData: Decodable {
    let attributes: SearchAttributes
  }

  struct SearchAttributes: Decodable {
    let files: [SearchFile]
    let language: String
    let languageName: String?
    let release: ReleaseValue?
    let featureDetails: FeatureDetails?

    var releaseText: String? {
      release?.textValue
    }

    enum CodingKeys: String, CodingKey {
      case files
      case language
      case languageName = "language_name"
      case release
      case featureDetails = "feature_details"
    }
  }

  struct SearchFile: Decodable {
    let fileID: Int
    let fileName: String

    enum CodingKeys: String, CodingKey {
      case fileID = "file_id"
      case fileName = "file_name"
    }
  }

  struct FeatureDetails: Decodable {
    let title: String?
  }

  enum ReleaseValue: Decodable {
    case single(String)
    case multiple([String])

    var textValue: String? {
      switch self {
      case .single(let value):
        return value
      case .multiple(let values):
        return values.first
      }
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()
      if let single = try? container.decode(String.self) {
        self = .single(single)
        return
      }

      if let multiple = try? container.decode([String].self) {
        self = .multiple(multiple)
        return
      }

      throw DecodingError.typeMismatch(
        ReleaseValue.self,
        .init(codingPath: decoder.codingPath, debugDescription: "Expected string or [string] for release")
      )
    }
  }

  struct DownloadRequest: Encodable {
    let fileID: Int
    let format: String

    enum CodingKeys: String, CodingKey {
      case fileID = "file_id"
      case format = "sub_format"
    }
  }

  struct DownloadResponse: Decodable {
    let link: URL
    let fileName: String

    enum CodingKeys: String, CodingKey {
      case link
      case fileName = "file_name"
    }
  }

  struct LoginRequest: Encodable {
    let username: String
    let password: String
  }

  struct LoginResponse: Decodable {
    let token: String
  }
}
