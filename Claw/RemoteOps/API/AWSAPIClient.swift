import Foundation

struct AWSAPIClient {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchEC2Instances(keyId: String, secret: String, region: String) async throws -> [EC2Instance] {
        // Validate region against the AWS-allowed character set (lowercase letters,
        // digits, hyphens) so a malformed value can't redirect the request to an
        // attacker-controlled host via the interpolated subdomain.
        guard Self.isValidAWSRegion(region) else {
            throw AWSAPIError.invalidRegion(region)
        }
        guard let url = URL(string: "https://ec2.\(region).amazonaws.com/") else {
            throw AWSAPIError.invalidRegion(region)
        }
        let body = "Action=DescribeInstances&Version=2016-11-15".data(using: .utf8)!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let signer = AWSV4Signer(accessKeyId: keyId, secretAccessKey: secret, region: region, service: "ec2")
        let signed = try signer.sign(request: request)

        let (data, response) = try await session.data(for: signed)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AWSAPIError.httpError(code, body)
        }

        return parseDescribeInstances(xml: data, region: region)
    }

    // MARK: - XML Parsing

    private func parseDescribeInstances(xml: Data, region: String) -> [EC2Instance] {
        let parser = EC2XMLParser(data: xml, region: region)
        return parser.parse()
    }

    private static func isValidAWSRegion(_ region: String) -> Bool {
        guard !region.isEmpty, region.count <= 32 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return region.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - EC2 XML Parser

private final class EC2XMLParser: NSObject, XMLParserDelegate {

    private let data: Data
    private let region: String
    private var instances: [EC2Instance] = []
    private var path: [String] = []
    private var text: String = ""

    // Per-instance accumulation
    private var instanceId = ""
    private var instanceState = ""
    private var publicIP = ""
    private var privateIP = ""
    private var instanceType = ""
    private var tagName = ""
    private var pendingTagKey = ""

    init(data: Data, region: String) {
        self.data = data
        self.region = region
    }

    func parse() -> [EC2Instance] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return instances
    }

    // The path suffix after the last "instancesSet" element.
    // e.g. for instancesSet/item/tagSet/item/key → ["item","tagSet","item","key"]
    private var instanceSubpath: ArraySlice<String>? {
        guard let idx = path.lastIndex(of: "instancesSet") else { return nil }
        return path[(idx + 1)...]
    }

    // True when we're at instancesSet/item (depth 1 inside instancesSet).
    private var atInstanceItem: Bool {
        guard let sub = instanceSubpath else { return false }
        return sub.count >= 1 && sub.first == "item"
    }

    // True when the current element is a direct child of the instance item
    // (not inside a nested block like networkInterfaceSet/item).
    private var directInstanceChild: Bool {
        guard let sub = instanceSubpath else { return false }
        // sub = ["item", elementName] → direct child
        return sub.count == 2 && sub.first == "item"
    }

    // True when inside tagSet of the instance item.
    private var inTagSet: Bool {
        guard let sub = instanceSubpath else { return false }
        return sub.first == "item" && sub.contains("tagSet")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        path.append(elementName)
        text = ""
        // Reset accumulation when a new instance item starts
        if atInstanceItem, path.last == "item", instanceSubpath?.count == 1 {
            instanceId = ""; instanceState = ""; publicIP = ""; privateIP = ""
            instanceType = ""; tagName = ""; pendingTagKey = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        defer { text = ""; if !path.isEmpty { path.removeLast() } }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "item":
            // Closing an instance-level item → commit
            if let sub = instanceSubpath, sub.count == 1, sub.first == "item" {
                commitInstance()
            }

        case "instanceId" where directInstanceChild:
            instanceId = value

        case "name" where atInstanceItem:
            if path.dropLast().last == "instanceState" { instanceState = value }

        case "instanceType" where directInstanceChild:
            instanceType = value

        case "ipAddress" where directInstanceChild:
            publicIP = value

        case "privateIpAddress" where directInstanceChild:
            privateIP = value

        // VPC instances: public IP lives in networkInterfaceSet/.../association/publicIp
        case "publicIp" where atInstanceItem && publicIP.isEmpty:
            publicIP = value

        // Private IP also appears in networkInterfaceSet — take the first one
        case "privateIpAddress" where atInstanceItem && privateIP.isEmpty:
            privateIP = value

        case "key" where inTagSet:
            pendingTagKey = value

        case "value" where inTagSet:
            if pendingTagKey == "Name" { tagName = value }

        default:
            break
        }
    }

    private func commitInstance() {
        guard !instanceId.isEmpty else { return }
        instances.append(EC2Instance(
            id: instanceId,
            name: tagName.isEmpty ? instanceId : tagName,
            state: EC2State(rawValue: instanceState.lowercased()) ?? .stopped,
            publicIP: publicIP.isEmpty ? nil : publicIP,
            privateIP: privateIP.isEmpty ? nil : privateIP,
            instanceType: instanceType.isEmpty ? "unknown" : instanceType,
            region: region,
            metrics: nil,
            containers: []
        ))
    }
}

// MARK: - Error

enum AWSAPIError: Error, LocalizedError {
    case httpError(Int, String)
    case invalidRegion(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            let snippet = String(body.prefix(300))
            return "AWS HTTP \(code): \(snippet)"
        case .invalidRegion(let region):
            return "Invalid AWS region: \(region)"
        }
    }
}
