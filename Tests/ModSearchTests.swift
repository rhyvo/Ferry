import Foundation

func runSearchTests() {
    let wiki = """
    ==Video==
    {{Fixbox|description=Use dhewm3 for widescreen and HUD/UI fixes|ref=<ref>x</ref>|fix=
    # Download [https://github.com/dhewm/dhewm3/releases dhewm3] and extract it.
    }}
    {{Fixbox|description=Set widescreen manually|fix=Edit <code>DoomConfig.cfg</code> and set {{code|r_aspectRatio}}.}}
    {{Fixbox|description=HD textures|fix=Get it from [https://www.moddb.com/mods/hd ModDB].}}
    """
    let fx = ModSearch.fixes(fromWikitext: wiki)
    check(fx.count == 3, "three fixboxes")
    check(fx.first?.id == "pcgw-0" && fx.first?.source == .pcgamingwiki, "id and source")
    check(fx[0].title == "Use dhewm3 for widescreen and HUD/UI fixes", "title")
    check(fx[0].link == .githubRepo(owner: "dhewm", repo: "dhewm3") && fx[0].canAutoInstall, "github link auto")
    check(fx[0].detail.hasPrefix("Video: Download dhewm3"), "heading + cleaned text")
    check(fx[1].link == nil && !fx[1].canAutoInstall, "instructions only")
    check(fx[1].detail.contains("r_aspectRatio") && fx[1].detail.contains("DoomConfig.cfg") && !fx[1].detail.contains("{{") && !fx[1].detail.contains("<"), "code values kept, markup gone")
    check(fx[2].link == .webPage(URL(string: "https://www.moddb.com/mods/hd")!) && !fx[2].canAutoInstall, "moddb is manual")
    check(ModSearch.matches(fx[0], query: "WIDESCREEN dhewm3") && !ModSearch.matches(fx[2], query: "widescreen"), "query filter")
    check(ModSearch.matches(fx[2], query: "  "), "empty query matches")

    let nested = "{{Fixbox|description=Nested|fix={{ii}} See [[Doom 3|the game]] and [[Wiki page]] with '''bold''' {{Term|x|y}}.|ref=a}}"
    let nf = ModSearch.fixes(fromWikitext: nested)
    check(nf.count == 1 && nf[0].detail == "See the game and Wiki page with bold x.", "nested cleanup, got \(nf.first?.detail ?? "nil")")
    let long = "{{Fixbox|description=Long|fix=" + String(repeating: "word ", count: 100) + "}}"
    check(ModSearch.fixes(fromWikitext: long)[0].detail.count <= 200, "detail cut to 200")
    let two = "{{Fixbox|description=Two|fix=[https://a.org/page page] or [https://a.org/fix.zip file]}}"
    check(ModSearch.fixes(fromWikitext: two)[0].link == .directFile(URL(string: "https://a.org/fix.zip")!), "direct file preferred")

    let multi = """
    ===Widescreen resolution===
    {{Fixbox|description=Use dhewm3 for widescreen and HUD/UI fixes|ref=<ref>{{Refurl|url=https://github.com/dhewm/dhewm3/pull/641|title=PR|date=2025-07-01}}</ref>|fix=
    # Install [[#Source ports|dhewm3]].
    # Download [https://github.com/user-attachments/files/18462597/z_cstd3_guis.zip z_cstd3_guis.zip] to {{folder|{{p|game}}\\base}}.
    # Rename {{file|z_cstd3_guis.zip}} to {{file|z_cstd3_guis.pk4}} to gain widescreen GUI support.

    '''Notes'''
    {{ii}} Old saved games will stop working after adding {{file|z_cstd3_guis.pk4}}. This note is long enough to push the text past two hundred characters.
    }}
    {{Fixbox|description=One step|fix=Put [https://a.org/fix.zip fix.zip] in the game folder.}}
    """
    let mf = ModSearch.fixes(fromWikitext: multi)
    check(mf.count == 2 && mf[0].steps == 3, "three steps counted, got \(mf.first?.steps ?? -1)")
    check(mf[0].link == .directFile(URL(string: "https://github.com/user-attachments/files/18462597/z_cstd3_guis.zip")!) && !mf[0].canAutoInstall, "multi-step keeps its link but is not Auto Install")
    check(mf[0].detail.contains("\n2. Download z_cstd3_guis.zip") && mf[0].detail.contains("\n3. Rename z_cstd3_guis.zip to z_cstd3_guis.pk4") && mf[0].detail.hasSuffix("two hundred characters."),
          "multi-step text in full, one step per line, got \(mf.first?.detail ?? "nil")")
    check(mf[1].steps == 1 && mf[1].canAutoInstall, "one-step zip fix is Auto Install")

    check(ModSearch.classify("https://x.org/f/fix.ZIP") == .directFile(URL(string: "https://x.org/f/fix.ZIP")!), "direct file")
    check(ModSearch.classify("https://github.com/a/b/releases/tag/v1") == .githubRepo(owner: "a", repo: "b"), "github deep path")
    check(ModSearch.classify("https://github.com/user-attachments/files/18462597/z_cstd3_guis.zip") == .directFile(URL(string: "https://github.com/user-attachments/files/18462597/z_cstd3_guis.zip")!), "github attachment is a file")
    check(ModSearch.classify("https://github.com/orgs/foo") == .webPage(URL(string: "https://github.com/orgs/foo")!), "github non-repo is a web page")
    check(ModSearch.classify("https://github.com/a/b/releases/download/v1/fix.zip") == .directFile(URL(string: "https://github.com/a/b/releases/download/v1/fix.zip")!), "release download is a file")
    check(ModSearch.classify("https://x.org/page") == .webPage(URL(string: "https://x.org/page")!), "web page")
    check(ModSearch.classify("ftp://x.org/a") == nil && ModSearch.classify("not a url") == nil, "not http")

    let gh = ModSearch.githubResults(fromSearchJSON: #"{"items":[{"full_name":"silentgameplays/doom-3-widescreen-fix","description":"Fix"},{"full_name":"a/b","description":null}]}"#.data(using: .utf8)!)
    check(gh.count == 2 && gh[0].source == .github && gh[0].reviewed == false, "github results not reviewed")
    check(gh[0].id == "gh-silentgameplays/doom-3-widescreen-fix" && gh[0].link == .githubRepo(owner: "silentgameplays", repo: "doom-3-widescreen-fix"), "github id and link")
    check(gh[1].detail == "", "missing description")
    check(ModSearch.githubResults(fromSearchJSON: Data("junk".utf8)).isEmpty, "bad json")

    check(ModSearch.pickAsset(["fix-src.zip", "fix-win64.zip", "fix-win32.zip"], is64bit: false) == .one("fix-win32.zip"), "arch pick")
    check(ModSearch.pickAsset(["fix-win64.zip", "fix-win32.zip"], is64bit: true) == .one("fix-win64.zip"), "arch pick 64")
    check(ModSearch.pickAsset(["a.zip", "b.7z"], is64bit: true) == .ask(["a.zip", "b.7z"]), "ask when unclear")
    check(ModSearch.pickAsset(["only.zip", "source.zip", "notes.txt"], is64bit: true) == .one("only.zip"), "one left")
    check(ModSearch.pickAsset(["notes.txt", "src.zip"], is64bit: true) == .none, "none")

    check(ModSearch.failureMessage(status: 403).contains("limit") && ModSearch.failureMessage(status: 429).contains("limit"), "rate limit message")
    check(ModSearch.failureMessage(status: nil).contains("internet"), "offline message")
    check(ModSearch.failureMessage(status: 500) == "GitHub didn't answer (error 500).", "other message")

    check(ModSearch.webSearchURL(game: "Doom 3", query: "widescreen").absoluteString == "https://duckduckgo.com/?q=Doom%203%20widescreen%20mod", "web search url")

    check(ModSearch.isGitHubHost("github.com") && ModSearch.isGitHubHost("WWW.GitHub.com"), "github hosts")
    check(!ModSearch.isGitHubHost("notgithub.com") && !ModSearch.isGitHubHost("github.com.evil.net") && !ModSearch.isGitHubHost(nil), "not github hosts")
    let blob = URL(string: "https://github.com/a/b/blob/main/blob/fix.zip?x=/blob/")!
    check(ModSearch.downloadURL(blob).absoluteString == "https://github.com/a/b/raw/main/blob/fix.zip?x=/blob/", "blob becomes raw in the path only, once")
    let other = URL(string: "https://notgithub.com/a/b/blob/main/fix.zip")!
    check(ModSearch.downloadURL(other) == other, "other hosts unchanged")
    let release = URL(string: "https://github.com/a/b/releases/download/v1/fix.zip")!
    check(ModSearch.downloadURL(release) == release, "release links unchanged")

    runWikiFixtureTests()
}

private func wikitext(_ name: String) -> String? {
    guard let repo = ProcessInfo.processInfo.environment["FERRY_REPO"],
          let data = FileManager.default.contents(atPath: repo + "/Tests/Fixtures/" + name + ".json"),
          let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let parse = root["parse"] as? [String: Any], let text = parse["wikitext"] as? String else {
        check(false, "fixture \(name) readable (FERRY_REPO set?)")
        return nil
    }
    return text
}

private func runWikiFixtureTests() {
    for page in ["Doom_3", "Call_of_Duty_4__Modern_Warfare", "Grand_Theft_Auto__San_Andreas", "Half-Life_2"] {
        guard let text = wikitext(page) else { continue }
        let fixes = ModSearch.fixes(fromWikitext: text)
        check(fixes.count >= 5, "\(page): fixes found, got \(fixes.count)")
        for f in fixes {
            check(!f.detail.hasPrefix("Notes"), "\(page): detail starts with a label: \(f.detail.prefix(40))")
            for bad in ["{{", "}}", "[[", "]]", "''", "----", "<ref", "<li"] {
                check(!f.title.contains(bad) && !f.detail.contains(bad), "\(page): \(bad) left in \(f.title) / \(f.detail.prefix(60))")
            }
            check(!f.detail.split(separator: "\n").contains { $0.hasPrefix(";") }, "\(page): definition marker left in \(f.detail.prefix(60))")
        }
    }
    if let doom = wikitext("Doom_3") {
        let fixes = ModSearch.fixes(fromWikitext: doom)
        let enhanced = fixes.first { $0.title.hasPrefix("Use Doom 3 Enhanced Edition") }
        check(enhanced.map { $0.detail.count > "Widescreen resolution".count && $0.detail.contains("Redux") } == true, "empty fix shows more than its heading, got \(enhanced?.detail ?? "nil")")
        let skip = fixes.first { $0.title.hasPrefix("Use the +disconnect") }
        check(skip?.detail == "Skip intro videos: Only works when a valid CD key has been registered.", "Notes label dropped, got \(skip?.detail ?? "nil")")
        let af = fixes.first { $0.title == "Set AF manually" }
        check(af?.detail.contains("game folder\\base\\autoexec.cfg") == true, "{{p|game}} kept as text, got \(af?.detail ?? "nil")")
        check(fixes.contains { $0.title.hasPrefix("Use dhewm3 (set in F10") }, "{{key|F10}} kept in the title")
        let manual = fixes.first { $0.title == "Set widescreen manually" }
        check(manual.map { $0.steps >= 5 && $0.detail.contains("\n2. Create and open") } == true, "html list items are steps, got \(manual?.detail ?? "nil")")
    }

    let markup = "==Heading==\n{{Fixbox|description=D|fix=\n;Term:\n----\n'''''both''''' and ''italic''\n'''Notes'''\n{{mm}} Text {{key|Ctrl|F}} {{Term|DRM}}.\n}}"
    let m = ModSearch.fixes(fromWikitext: markup)
    check(m.count == 1 && m[0].detail == "Heading: Term: both and italic Text Ctrl+F DRM.", "markup cleanup, got \(m.first?.detail ?? "nil")")

    let cut = "{{Fixbox|description=First|fix=Do this.}}\n{{Fixbox|description=Second|fix=Do {{code|that}} and"
    let c = ModSearch.fixes(fromWikitext: cut)
    check(c.count == 1 && c[0].title == "First", "unterminated fixbox returns the fixes before it, got \(c.count)")
    check(ModSearch.fixes(fromWikitext: "{{Fixbox|description=Only|fix=never ends").isEmpty, "only an unterminated fixbox gives none")
}
