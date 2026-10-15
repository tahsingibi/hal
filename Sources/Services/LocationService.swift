import Foundation

actor LocationService {
    static let shared = LocationService()

    private var turkey: TurkeyData?
    private var worldStates: [String: [PlaceRegion]] = [:]

    struct TurkeyData: Sendable {
        var provinces: [PlaceRegion]
        var districts: [String: [PlaceCity]]
        var provinceCoordinates: [String: (Double, Double)]
    }

    func countries() -> [PlaceCountry] {
        Self.bundledCountries
    }

    func turkeyData() -> TurkeyData {
        if let turkey { return turkey }
        let loaded = Self.loadTurkey()
        turkey = loaded
        return loaded
    }

    func regions(for country: PlaceCountry) async -> [PlaceRegion] {
        if country.code == "TR" {
            return turkeyData().provinces
        }
        if let cached = worldStates[country.code] { return cached }
        let loaded = await Self.fetchWorldStates(country: country)
        worldStates[country.code] = loaded
        return loaded
    }

    func cities(country: PlaceCountry, region: PlaceRegion) -> [PlaceCity] {
        if country.code == "TR" {
            return turkeyData().districts[region.name] ?? []
        }
        return []
    }

    func coordinates(country: PlaceCountry, region: PlaceRegion, city: PlaceCity?) -> (Double, Double)? {
        if let city, let lat = city.latitude, let lon = city.longitude {
            return (lat, lon)
        }
        if country.code == "TR" {
            let data = turkeyData()
            if let city, let match = data.districts[region.name]?.first(where: { $0.name == city.name }),
               let lat = match.latitude, let lon = match.longitude {
                return (lat, lon)
            }
            if let pair = data.provinceCoordinates[region.name] {
                return pair
            }
        }
        return region.latitude.flatMap { lat in
            region.longitude.map { (lat, $0) }
        }
    }

    func geocode(country: String, state: String, city: String) async -> (Double, Double)? {
        let address = [city, state, country].filter { !$0.isEmpty }.joined(separator: ", ")
        if let url = URL(string: "https://api.aladhan.com/v1/addressToCoordinates?address=\(address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? address)"),
           let (data, response) = try? await NetworkClient.get(url),
           (200..<300).contains(response.statusCode),
           let json = try? NetworkClient.json(data),
           let object = JSONValue.object(json),
           let payload = JSONValue.object(object["data"]) ?? JSONValue.object(object) {
            if let lat = JSONValue.number(JSONValue.lookup(payload, keys: ["latitude", "lat"])),
               let lon = JSONValue.number(JSONValue.lookup(payload, keys: ["longitude", "lng", "lon"])) {
                return (lat, lon)
            }
        }
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "q", value: address)
        ]
        if let url = components?.url,
           let (data, response) = try? await NetworkClient.get(url),
           (200..<300).contains(response.statusCode),
           let json = try? NetworkClient.json(data),
           let first = JSONValue.array(json)?.first,
           let object = JSONValue.object(first),
           let lat = JSONValue.number(object["lat"]),
           let lon = JSONValue.number(object["lon"]) {
            return (lat, lon)
        }
        return nil
    }

    func searchCities(query: String, countryCode: String) async -> [PlaceCity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, !countryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "countrycodes", value: countryCode.lowercased()),
            URLQueryItem(name: "q", value: trimmed)
        ]
        guard let url = components?.url,
              let (data, response) = try? await NetworkClient.get(url),
              (200..<300).contains(response.statusCode),
              let json = try? NetworkClient.json(data),
              let array = JSONValue.array(json) else { return [] }
        return array.compactMap { item in
            guard let object = JSONValue.object(item) else { return nil }
            let name = JSONValue.string(object["name"])
                ?? JSONValue.string(object["display_name"])
                ?? trimmed
            return PlaceCity(
                name: name,
                latitude: JSONValue.number(object["lat"]),
                longitude: JSONValue.number(object["lon"])
            )
        }
    }

    private static func loadTurkey() -> TurkeyData {
        let urls = [
            Bundle.main.url(forResource: "turkey", withExtension: "json")
        ].compactMap { $0 }
        for url in urls {
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data),
               let root = JSONValue.object(json),
               let provinces = JSONValue.array(root["provinces"]) {
                var regions: [PlaceRegion] = []
                var districts: [String: [PlaceCity]] = [:]
                var coords: [String: (Double, Double)] = [:]
                for item in provinces {
                    guard let object = JSONValue.object(item),
                          let name = JSONValue.string(object["name"]) else { continue }
                    let lat = JSONValue.number(object["lat"])
                    let lon = JSONValue.number(object["lon"])
                    regions.append(PlaceRegion(name: name, latitude: lat, longitude: lon))
                    if let lat, let lon { coords[name] = (lat, lon) }
                    let cities = JSONValue.array(object["districts"])?.compactMap { district -> PlaceCity? in
                        let name: String?
                        if let dict = JSONValue.object(district) {
                            name = JSONValue.string(dict["name"])
                        } else {
                            name = JSONValue.string(district)
                        }
                        guard let name else { return nil }
                        return PlaceCity(name: name, latitude: nil, longitude: nil)
                    } ?? []
                    districts[name] = cities
                }
                return TurkeyData(provinces: regions, districts: districts, provinceCoordinates: coords)
            }
        }
        return TurkeyData(provinces: [], districts: [:], provinceCoordinates: [:])
    }

    private static func fetchWorldStates(country: PlaceCountry) async -> [PlaceRegion] {
        guard let url = URL(string: "https://countriesnow.space/api/v0.1/countries/states"),
              let (data, response) = try? await NetworkClient.get(url),
              (200..<300).contains(response.statusCode),
              let json = try? NetworkClient.json(data),
              let root = JSONValue.object(json),
              let array = JSONValue.array(root["data"]) else { return [] }
        let match = array.compactMap { JSONValue.object($0) }.first {
            JSONValue.string($0["iso2"]) == country.code || JSONValue.string($0["name"]) == country.name
        }
        let states = JSONValue.array(match?["states"]) ?? []
        return states.compactMap { item in
            let object = JSONValue.object(item)
            let name = JSONValue.string(object?["name"]) ?? JSONValue.string(item)
            guard let name else { return nil }
            return PlaceRegion(name: name.replacingOccurrences(of: " Province", with: ""), latitude: nil, longitude: nil)
        }
    }

    nonisolated static let bundledCountries: [PlaceCountry] = [
        .init(name: "Türkiye", code: "TR"),
        .init(name: "Almanya", code: "DE"),
        .init(name: "Amerika Birleşik Devletleri", code: "US"),
        .init(name: "Arjantin", code: "AR"),
        .init(name: "Arnavutluk", code: "AL"),
        .init(name: "Avustralya", code: "AU"),
        .init(name: "Avusturya", code: "AT"),
        .init(name: "Azerbaycan", code: "AZ"),
        .init(name: "Bahreyn", code: "BH"),
        .init(name: "Bangladeş", code: "BD"),
        .init(name: "Belçika", code: "BE"),
        .init(name: "Birleşik Arap Emirlikleri", code: "AE"),
        .init(name: "Birleşik Krallık", code: "GB"),
        .init(name: "Bosna-Hersek", code: "BA"),
        .init(name: "Brezilya", code: "BR"),
        .init(name: "Bulgaristan", code: "BG"),
        .init(name: "Cezayir", code: "DZ"),
        .init(name: "Çin", code: "CN"),
        .init(name: "Danimarka", code: "DK"),
        .init(name: "Endonezya", code: "ID"),
        .init(name: "Fas", code: "MA"),
        .init(name: "Filistin", code: "PS"),
        .init(name: "Finlandiya", code: "FI"),
        .init(name: "Fransa", code: "FR"),
        .init(name: "Güney Afrika", code: "ZA"),
        .init(name: "Gürcistan", code: "GE"),
        .init(name: "Hindistan", code: "IN"),
        .init(name: "Hollanda", code: "NL"),
        .init(name: "Irak", code: "IQ"),
        .init(name: "İran", code: "IR"),
        .init(name: "İrlanda", code: "IE"),
        .init(name: "İspanya", code: "ES"),
        .init(name: "İsveç", code: "SE"),
        .init(name: "İsviçre", code: "CH"),
        .init(name: "İtalya", code: "IT"),
        .init(name: "Japonya", code: "JP"),
        .init(name: "Kanada", code: "CA"),
        .init(name: "Karadağ", code: "ME"),
        .init(name: "Katar", code: "QA"),
        .init(name: "Kazakistan", code: "KZ"),
        .init(name: "Kenya", code: "KE"),
        .init(name: "Kıbrıs", code: "CY"),
        .init(name: "Kırgızistan", code: "KG"),
        .init(name: "Kore", code: "KR"),
        .init(name: "Kosova", code: "XK"),
        .init(name: "Kuveyt", code: "KW"),
        .init(name: "Libya", code: "LY"),
        .init(name: "Lübnan", code: "LB"),
        .init(name: "Macaristan", code: "HU"),
        .init(name: "Malezya", code: "MY"),
        .init(name: "Mısır", code: "EG"),
        .init(name: "Nijerya", code: "NG"),
        .init(name: "Norveç", code: "NO"),
        .init(name: "Özbekistan", code: "UZ"),
        .init(name: "Pakistan", code: "PK"),
        .init(name: "Polonya", code: "PL"),
        .init(name: "Portekiz", code: "PT"),
        .init(name: "Romanya", code: "RO"),
        .init(name: "Rusya", code: "RU"),
        .init(name: "Senegal", code: "SN"),
        .init(name: "Sırbistan", code: "RS"),
        .init(name: "Singapur", code: "SG"),
        .init(name: "Somali", code: "SO"),
        .init(name: "Suudi Arabistan", code: "SA"),
        .init(name: "Suriye", code: "SY"),
        .init(name: "Tunus", code: "TN"),
        .init(name: "Türkmenistan", code: "TM"),
        .init(name: "Ukrayna", code: "UA"),
        .init(name: "Umman", code: "OM"),
        .init(name: "Ürdün", code: "JO"),
        .init(name: "Yemen", code: "YE"),
        .init(name: "Yunanistan", code: "GR")
    ]
}
