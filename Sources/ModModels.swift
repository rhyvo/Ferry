import Foundation

enum ModSource: String, Codable { case pcgamingwiki, github, file }

enum ModLink: Equatable {
    case githubRepo(owner: String, repo: String)
    case directFile(URL)
    case webPage(URL)
}

struct ModResult: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let source: ModSource
    let link: ModLink?
    var steps: Int = 1

    var reviewed: Bool { source == .pcgamingwiki }

    var canAutoInstall: Bool {
        guard steps <= 1 else { return false }
        switch link {
        case .githubRepo, .directFile: return true
        default: return false
        }
    }
}

enum ModRecipe: String, Codable { case dropIn, mirror, dataFiles, program, installer }

struct ModCopy: Equatable {
    let from: URL
    let to: URL
}

struct ModPlan: Equatable {
    var recipe: ModRecipe
    var copies: [ModCopy]
    var overrides: [String]
    var programExe: URL?
}

struct ModFileRecord: Codable, Equatable {
    let path: String
    let sha256: String
    var backup: String?
    var createdFolders: [String]? = nil
}

struct InstalledMod: Codable, Identifiable, Equatable {
    var id = UUID()
    let name: String
    let source: String
    let recipe: ModRecipe
    var files: [ModFileRecord]
    var overrides: [String]
    var addedGameID: UUID?
    var installedAt = Date()
}

struct GameFolders {
    let exeFolder: URL
    let root: URL
    let is64bit: Bool
}

struct LossyList<T: Decodable>: Decodable {
    var items: [T] = []

    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            if let item = try? c.decode(T.self) { items.append(item) } else { _ = try c.decode(Skip.self) }
        }
    }
}
