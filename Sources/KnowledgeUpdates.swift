import Foundation

extension AppModel {
    private static var downloadedKnowledge: URL { Paths.root.appendingPathComponent("Knowledge", isDirectory: true) }

    private static var ferryVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func reloadKnowledge() {
        let generated = KnowledgePack.generated(settings: SettingsCatalog.all, symptoms: Symptom.allCases.map { ($0.title, $0.guide) })
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Knowledge", isDirectory: true)
        let pack = KnowledgeManifest.loadBest(downloaded: Self.downloadedKnowledge, bundled: bundled, ferry: Self.ferryVersion)
        knowledge = (pack ?? KnowledgePack(docs: [])).adding(generated)
    }

    func suggestedModel(_ p: AssistantProvider) -> String? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Knowledge", isDirectory: true)
        return KnowledgeManifest.bestSuggestedModels(downloaded: Self.downloadedKnowledge, bundled: bundled, ferry: Self.ferryVersion)[p.rawValue]
    }

    var lastKnowledgeCheck: Date? {
        get { UserDefaults.standard.object(forKey: "lastKnowledgeCheck") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastKnowledgeCheck") }
    }

    func checkKnowledgePack() async {
        let base = KnowledgeManifest.endpoint(override: ProcessInfo.processInfo.environment["FERRY_KNOWLEDGE_URL"])
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Knowledge", isDirectory: true)
        let current = max(KnowledgeManifest.read(folder: Self.downloadedKnowledge)?.version ?? 0, bundled.flatMap(KnowledgeManifest.read)?.version ?? 0)
        let staging = Paths.root.appendingPathComponent("Knowledge.new", isDirectory: true)
        do {
            let installed = try await KnowledgeManifest.install(from: base, current: current, ferry: Self.ferryVersion, staging: staging, installed: Self.downloadedKnowledge)
            lastKnowledgeCheck = Date()
            if installed { reloadKnowledge() }
        } catch is URLError {
        } catch {
            lastKnowledgeCheck = Date()
        }
    }
}
