import Foundation

struct AppStoreAppResult: Identifiable, Equatable {
    let name: String
    let bundleID: String
    let sellerName: String
    let artworkURL: URL?
    let trackID: Int?

    var id: String {
        bundleID.lowercased()
    }
}

struct AppStoreLookupService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func searchApps(query: String, limit: Int = 20) async throws -> [AppStoreAppResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let countryCode = Locale.current.regionCode?.uppercased() ?? "US"

        if let trackID = extractTrackID(from: trimmed) {
            return try await lookupApps(queryItems: [
                URLQueryItem(name: "id", value: trackID),
                URLQueryItem(name: "entity", value: "software"),
                URLQueryItem(name: "country", value: countryCode)
            ])
        }

        if isValidBundleID(trimmed) {
            return try await lookupApps(queryItems: [
                URLQueryItem(name: "bundleId", value: trimmed),
                URLQueryItem(name: "entity", value: "software"),
                URLQueryItem(name: "country", value: countryCode)
            ])
        }

        return try await searchByTerm(
            term: trimmed,
            limit: min(max(limit, 1), 50),
            countryCode: countryCode
        )
    }

    private func searchByTerm(term: String, limit: Int, countryCode: String) async throws -> [AppStoreAppResult] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: countryCode)
        ]

        guard let url = components.url else {
            throw AppStoreLookupError.invalidURL
        }

        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(AppStoreResponse.self, from: data)
        return normalize(response.results)
    }

    private func lookupApps(queryItems: [URLQueryItem]) async throws -> [AppStoreAppResult] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"
        components.queryItems = queryItems

        guard let url = components.url else {
            throw AppStoreLookupError.invalidURL
        }

        let (data, _) = try await session.data(from: url)
        let response = try JSONDecoder().decode(AppStoreResponse.self, from: data)
        return normalize(response.results)
    }

    private func normalize(_ items: [AppStoreResponse.Result]) -> [AppStoreAppResult] {
        var seen = Set<String>()
        var normalized: [AppStoreAppResult] = []

        for item in items {
            guard let bundleID = item.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !bundleID.isEmpty
            else {
                continue
            }

            let key = bundleID.lowercased()
            guard seen.insert(key).inserted else {
                continue
            }

            let name = item.trackName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let seller = item.sellerName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedName = (name?.isEmpty == false) ? name ?? bundleID : bundleID
            let normalizedSeller = (seller?.isEmpty == false) ? seller ?? "未知开发者" : "未知开发者"

            normalized.append(
                AppStoreAppResult(
                    name: normalizedName,
                    bundleID: bundleID,
                    sellerName: normalizedSeller,
                    artworkURL: URL(string: item.artworkUrl100 ?? ""),
                    trackID: item.trackId
                )
            )
        }

        return normalized
    }

    private func extractTrackID(from query: String) -> String? {
        if query.allSatisfy(\.isNumber) {
            return query
        }

        let range = NSRange(location: 0, length: query.utf16.count)
        guard let regex = try? NSRegularExpression(pattern: "id(\\d{5,})", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: query, options: [], range: range),
              let groupRange = Range(match.range(at: 1), in: query)
        else {
            return nil
        }

        return String(query[groupRange])
    }

    private func isValidBundleID(_ value: String) -> Bool {
        let pattern = "^[A-Za-z0-9\\-]+(\\.[A-Za-z0-9\\-]+)+$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

private enum AppStoreLookupError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "App Store 请求地址无效"
        }
    }
}

private struct AppStoreResponse: Decodable {
    struct Result: Decodable {
        let trackId: Int?
        let trackName: String?
        let bundleId: String?
        let sellerName: String?
        let artworkUrl100: String?
    }

    let results: [Result]
}
