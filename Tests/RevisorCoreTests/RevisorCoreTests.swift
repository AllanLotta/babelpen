import XCTest
@testable import RevisorCore

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

    func testAboutIsAppendedOnlyWhenSet() {
        XCTAssertFalse(Prompt.system().contains("About the writer"))
        XCTAssertTrue(Prompt.system(about: "Writes in English and Spanish").contains("About the writer: Writes in English and Spanish"))
    }

    func testOneShotContainsTextInTags() {
        XCTAssertTrue(Prompt.oneShot("abc").hasSuffix("<text>\nabc\n</text>"))
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

    func testRoundTrip() throws {
        var config = Config()
        config.provider = .command
        config.command = ["ollama", "run", "llama3.2"]
        XCTAssertEqual(try Config.decode(config.encoded()), config)
    }

    func testStoreCreatesFileOnFirstLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("revisor-test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ConfigStore(url: url)
        XCTAssertNil(store.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}

final class L10nTests: XCTestCase {
    func testDetection() {
        XCTAssertEqual(L10n.detect(override: "", preferred: ["pt-BR", "en-US"]), .pt)
        XCTAssertEqual(L10n.detect(override: "", preferred: ["de-DE", "en-US"]), .en)
        XCTAssertEqual(L10n.detect(override: "", preferred: ["ja-JP"]), .en)
        XCTAssertEqual(L10n.detect(override: "en", preferred: ["pt-BR"]), .en)
    }

    func testPlurals() {
        XCTAssertEqual(L10n(.en).fixes(1), "1 fix")
        XCTAssertEqual(L10n(.en).fixes(3), "3 fixes")
        XCTAssertEqual(L10n(.pt).fixes(1), "1 correção")
        XCTAssertEqual(L10n(.pt).cardHeader(2), "REVISOR · 2 CORREÇÕES")
    }
}
