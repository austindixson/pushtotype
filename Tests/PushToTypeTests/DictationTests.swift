import XCTest
@testable import PushToTypeSupport

final class DictionaryCorrectionTests: XCTestCase {
    func testSpokenHostingNameBecomesTheProductSpelling() {
        let text = DevLexicon.correct("deploy on ver cell tonight", profile: .prose)
        XCTAssertEqual(text, "deploy on Vercel tonight")
    }

    func testCodeOnlyJasonFixStaysOutOfProse() {
        XCTAssertEqual(DevLexicon.correct("the jason file", profile: .prose), "the jason file")
        XCTAssertEqual(DevLexicon.correct("the jason file", profile: .code), "the JSON file")
        let shell = DevLexicon.correct(
            "cat jason",
            profile: DictationContext.from(bundleID: "com.apple.Terminal")
        )
        XCTAssertEqual(shell, "cat JSON")
    }

    func testCloudRunIsCodeOnly() {
        XCTAssertEqual(DevLexicon.correct("use cloud run", profile: .prose), "use cloud run")
        XCTAssertEqual(DevLexicon.correct("use cloud run", profile: .code), "use Cloud Run")
    }

    func testSingleTokenDoesNotMatchInsideAnotherWord() {
        let text = DictionaryReplacements.apply(
            "medium",
            pairs: [ReplacementPair(find: "sum", replace: "SUM")]
        )
        XCTAssertEqual(text, "medium")
    }

    func testBlockedEverydayWordIsNotReplaced() {
        XCTAssertTrue(DictionaryPairPolicy.isBlocked(find: "this", replace: "that"))
        let text = DictionaryReplacements.apply(
            "use this",
            pairs: [ReplacementPair(find: "this", replace: "that")]
        )
        XCTAssertEqual(text, "use this")
    }

    func testUserPairWinsOverTheLexicon() {
        let text = DictationCorrections.apply(
            "ver cell",
            bundleID: nil,
            pairs: [ReplacementPair(find: "ver cell", replace: "vercel")]
        )
        XCTAssertEqual(text, "vercel")
    }

    func testLexiconIsLargeEnoughToBeTheDevDictionary() {
        XCTAssertGreaterThan(DevLexicon.termCount, 250)
        XCTAssertGreaterThan(DevLexicon.correctionCount, 40)
        XCTAssertLessThanOrEqual(DevLexicon.contextualStrings().count, DevLexicon.contextualStringLimit)
    }
}

final class EngineSelectionTests: XCTestCase {
    func testMissingOrUnknownValueUsesTheSingleDefault() {
        XCTAssertEqual(EngineSelection.resolve(stored: nil), DictationDefaults.engine)
        XCTAssertEqual(EngineSelection.resolve(stored: ""), DictationDefaults.engine)
        XCTAssertEqual(EngineSelection.resolve(stored: "not-an-engine"), DictationDefaults.engine)
    }

    func testStoredEngineWinsOverTheDefault() {
        XCTAssertEqual(EngineSelection.resolve(stored: TranscriptionEngine.whisper.rawValue), .whisper)
        XCTAssertEqual(EngineSelection.resolve(stored: TranscriptionEngine.bark30Clean.rawValue), .bark30Clean)
    }

    func testDistilModelUsesTheOfficialFileAndSize() {
        let model = WhisperModel.distillSmallEn.model
        let url = model.fileURL(model.files[0].name).absoluteString
        XCTAssertEqual(model.repo, "distil-whisper/distil-small.en")
        XCTAssertEqual(model.files[0].bytes, 336_191_657)
        XCTAssertEqual(model.files[0].sha256.count, 64)
        XCTAssertFalse(url.contains("ggerganov/whisper.cpp"))
        XCTAssertTrue(url.contains(model.revision))
    }

    func testBarkModelsShareTheLoaderAndArePinned() {
        for bark in BarkModel.allCases {
            let file = bark.model.files[0]
            XCTAssertEqual(file.name, "model.bark")
            XCTAssertEqual(bark.model.revision.count, 40)
            XCTAssertEqual(file.sha256.count, 64)
            XCTAssertGreaterThan(file.bytes, 1_000_000)
            XCTAssertTrue(bark.model.runtime.contains("mlx-audio"))
            XCTAssertEqual(bark.engine.barkModel, bark)
        }
    }

    func testCataloguedDownloadsAreHTTPSAndNamed() {
        var specs: [HuggingFaceModel] = WhisperModel.allCases.map(\.model) + ParakeetModel.allCases.map(\.model)
        specs.append(PhononCatalog.model)
        specs.append(contentsOf: BarkModel.allCases.map(\.model))
        for spec in specs {
            XCTAssertFalse(spec.id.isEmpty)
            XCTAssertFalse(spec.runtime.isEmpty)
            for file in spec.files {
                let url = spec.fileURL(file.name)
                XCTAssertEqual(url.scheme, "https")
                XCTAssertEqual(file.sha256.count, 64)
            }
        }
        XCTAssertEqual(OpenAITranscriptionCatalog.primaryModel, "gpt-4o-transcribe")
        XCTAssertEqual(OpenAITranscriptionCatalog.endpoint.host, "api.openai.com")
        XCTAssertFalse(TranscriptionEngine.allCases.contains { $0.displayName.isEmpty })
    }
}
