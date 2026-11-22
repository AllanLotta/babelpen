import XCTest
@testable import BabelpenCore

final class DiffTests: XCTestCase {
    func testIdenticalTextHasNoChanges() {
        let ops = Diff.diff("Sounds good, thanks!", "Sounds good, thanks!")
        XCTAssertEqual(Diff.changeCount(ops), 0)
    }

    func testCountsSeparateChanges() {
        // "i didnt had" is one contiguous edit, "tomorow" another.
        let ops = Diff.diff("i didnt had time, see you tomorow", "I didn't have time, see you tomorrow")
        XCTAssertEqual(Diff.changeCount(ops), 2)
    }

    func testAdjacentEditsMergeIntoOneReplacement() {
        let ops = Diff.diff("we discuss about it", "we discussed it")
        XCTAssertEqual(ops, [.same("we"), .same(" "), .delete("discuss about"), .insert("discussed"), .same(" "), .same("it")])
    }

    func testRebuildsBothSides() {
        let a = "Can you give a look on this?", b = "Can you take a look at this?"
        var left = "", right = ""
        for op in Diff.diff(a, b) {
            switch op {
            case .same(let t): left += t; right += t
            case .delete(let t): left += t
            case .insert(let t): right += t
            }
        }
        XCTAssertEqual(left, a)
        XCTAssertEqual(right, b)
    }

    func testCompactCollapsesLongUnchangedRuns() {
        let long = String(repeating: "word ", count: 60)
        let ops = Diff.compact([.same(long), .delete("teh"), .insert("the"), .same(long)])
        guard case .same(let first) = ops[0], case .same(let last) = ops[3] else { return XCTFail() }
        XCTAssertTrue(first.hasPrefix("…"))
        XCTAssertTrue(last.hasSuffix("…"))
        XCTAssertLessThan(first.count, long.count)
    }

    func testEmptyInputs() {
        XCTAssertEqual(Diff.diff("", ""), [])
        XCTAssertEqual(Diff.diff("", "hi"), [.insert("hi")])
    }
}

final class PromptTests: XCTestCase {
    func testParsesFixedTag() {
        XCTAssertEqual(Prompt.parseFixed("<fixed>Hello there.</fixed>"), "Hello there.")
        XCTAssertEqual(Prompt.parseFixed("sure!\n<fixed>\nline one\nline two\n</fixed>"), "line one\nline two")
    }

    func testRejectsAnswersWithoutTag() {
        XCTAssertNil(Prompt.parseFixed("Hello there."))
        XCTAssertNil(Prompt.parseFixed("</fixed>oops<fixed>"))
    }

    func testKeepsUsersEdgeWhitespace() {
        XCTAssertEqual(Prompt.keepEdges(source: "hey i am here ", fixed: "Hey, I am here."), "Hey, I am here. ")
        XCTAssertEqual(Prompt.keepEdges(source: "\n text", fixed: "Text"), "\n Text")
    }

    func testContextBlockOnlyWhenThereIsContext() {
        XCTAssertEqual(Prompt.userMessage("hi"), "<text>\nhi\n</text>")
        let msg = Prompt.userMessage("ciao", context: PromptContext(languages: ["English", "Italian"], about: "Learning Italian",
                                                                     vocabulary: ["Babelpen", "k8s"]))
        XCTAssertTrue(msg.hasPrefix("<context>\n"))
        XCTAssertTrue(msg.contains("Writer's languages: English, Italian."))
        XCTAssertTrue(msg.contains("About the writer: Learning Italian"))
        XCTAssertTrue(msg.contains("Vocabulary (keep exactly as written): Babelpen | k8s"))
        XCTAssertTrue(msg.hasSuffix("<text>\nciao\n</text>"))
    }

    func testSystemPromptForbidsTranslation() {
        XCTAssertTrue(Prompt.system.contains("never translate"))
    }

    func testOneShotContainsTextInTags() {
        XCTAssertTrue(Prompt.oneShot("abc").hasSuffix("<text>\nabc\n</text>"))
        XCTAssertTrue(Prompt.oneShot("abc").hasPrefix(Prompt.system))
    }
}

final class LanguagesTests: XCTestCase {
    func testSystemLanguagesAreDistinctCodes() {
        XCTAssertEqual(Languages.fromSystem(["pt-BR", "en-US", "en-GB", "it-IT", "fr-FR"]), ["pt", "en", "it"])
        XCTAssertEqual(Languages.fromSystem([]), ["en"])
    }

    func testEffectivePrefersConfigured() {
        XCTAssertEqual(Languages.effective([], preferred: ["de-DE"]), ["de"])
        XCTAssertEqual(Languages.effective(["EN", " it "], preferred: ["de-DE"]), ["en", "it"])
    }

    func testToggleStartsFromSystemLanguages() {
        XCTAssertEqual(Languages.toggle("it", in: [], preferred: ["en-US"]), ["en", "it"])
        XCTAssertEqual(Languages.toggle("en", in: ["en", "it"]), ["it"])
    }

    func testNames() {
        XCTAssertEqual(Languages.name("it", in: "en"), "Italian")
        XCTAssertEqual(Languages.name("it", in: "pt"), "Italiano")
        XCTAssertEqual(Languages.name("de", in: "fr"), "Allemand")
    }
}

final class VocabularyTests: XCTestCase {
    func testParseSkipsCommentsBlanksAndDuplicates() {
        XCTAssertEqual(Vocabulary.parse("# header\n\nBabelpen\n  k8s  \nBabelpen\n"), ["Babelpen", "k8s"])
    }

    func testNormalize() {
        XCTAssertEqual(Vocabulary.normalize("  Expo Router, "), "Expo Router")
        XCTAssertNil(Vocabulary.normalize("   "))
        XCTAssertNil(Vocabulary.normalize("two\nlines"))
        XCTAssertNil(Vocabulary.normalize(String(repeating: "a", count: 61)))
    }

    func testAppendingIsIdempotent() {
        let once = Vocabulary.appending("gonna", to: Vocabulary.fileHeader)
        XCTAssertNotNil(once)
        XCTAssertEqual(Vocabulary.parse(once!), ["gonna"])
        XCTAssertNil(Vocabulary.appending("gonna", to: once!))
    }

    func testStoreAddsTerms() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("babelpen-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(url: dir.appendingPathComponent("config.json"))
        XCTAssertEqual(store.vocabulary(), [])
        XCTAssertTrue(store.addToVocabulary("Babelpen"))
        XCTAssertFalse(store.addToVocabulary("Babelpen"))
        XCTAssertEqual(store.vocabulary(), ["Babelpen"])
    }
}

final class ConfigTests: XCTestCase {
    func testMissingKeysFallBackToDefaults() throws {
        let config = try Config.decode(Data(#"{"provider":"codex","about":"hi"}"#.utf8))
        XCTAssertEqual(config.provider, .codex)
        XCTAssertEqual(config.about, "hi")
        XCTAssertEqual(config.debounceSeconds, 1.0)
        XCTAssertEqual(config.ignoredApps, Config.defaultIgnoredApps)
    }

    func testUnknownProviderFallsBackToClaude() throws {
        XCTAssertEqual(try Config.decode(Data(#"{"provider":"nope"}"#.utf8)).provider, .claude)
    }

    func testLegacyLanguageKeyStillWorks() throws {
        XCTAssertEqual(try Config.decode(Data(#"{"language":"pt"}"#.utf8)).interfaceLanguage, "pt")
        XCTAssertEqual(try Config.decode(Data(#"{"interfaceLanguage":"it","languages":["en","it"]}"#.utf8)).languages, ["en", "it"])
    }

    func testRoundTrip() throws {
        var config = Config()
        config.provider = .command
        config.command = ["ollama", "run", "llama3.2"]
        XCTAssertEqual(try Config.decode(config.encoded()), config)
    }

    func testStoreCreatesFileOnFirstLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("babelpen-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ConfigStore(url: url)
        XCTAssertNil(store.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}

final class L10nTests: XCTestCase {
    func testDetection() {
        XCTAssertEqual(L10n.detect(override: "", preferred: ["pt-BR", "en-US"]), .pt)
        XCTAssertEqual(L10n.detect(override: "", preferred: ["ko-KR", "en-US"]), .en)
        XCTAssertEqual(L10n.detect(override: "", preferred: ["ja-JP"]), .en)
        XCTAssertEqual(L10n.detect(override: "en", preferred: ["pt-BR"]), .en)
    }

    func testPlurals() {
        XCTAssertEqual(L10n(.en).fixes(1), "1 fix")
        XCTAssertEqual(L10n(.en).fixes(3), "3 fixes")
        XCTAssertEqual(L10n(.pt).fixes(1), "1 correção")
        XCTAssertEqual(L10n(.pt).cardHeader(2), "BABELPEN · 2 CORREÇÕES")
        XCTAssertEqual(L10n(.de).fixes(2), "2 Korrekturen")
    }

    func testEveryStringExistsInEveryLanguage() {
        for key in L10n.Key.allCases {
            for language in L10n.Language.allCases {
                XCTAssertNotNil(L10n.table[key]?[language], "missing \(key) in \(language)")
            }
        }
    }

    func testDetectsAllInterfaceLanguages() {
        XCTAssertEqual(L10n.detect(override: "", preferred: ["it-IT"]), .it)
        XCTAssertEqual(L10n.detect(override: "", preferred: ["fr-CA"]), .fr)
        XCTAssertEqual(L10n.detect(override: "es", preferred: ["en"]), .es)
    }
}
