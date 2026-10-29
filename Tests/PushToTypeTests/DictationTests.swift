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

    func testMultiWordFindDoesNotMatchInsideNeighboringWords() {
        let pairs = [ReplacementPair(find: "you know", replace: "YK")]
        XCTAssertEqual(
            DictionaryReplacements.apply("do you knowledge", pairs: pairs),
            "do you knowledge"
        )
        XCTAssertEqual(
            DictionaryReplacements.apply("bayou know", pairs: pairs),
            "bayou know"
        )
        XCTAssertEqual(
            DictionaryReplacements.apply("you know what", pairs: pairs),
            "YK what"
        )
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

    func testDollarReplacementStaysLiteral() {
        let text = DictionaryReplacements.apply(
            "see foo now",
            pairs: [ReplacementPair(find: "foo", replace: "$1 tag")]
        )
        XCTAssertEqual(text, "see $1 tag now")
    }

    func testBackslashReplacementStaysLiteral() {
        let text = DictionaryReplacements.apply(
            "see foo now",
            pairs: [ReplacementPair(find: "foo", replace: "\\n")]
        )
        XCTAssertEqual(text, "see \\n now")
    }

    func testStoredReplacementTrimsWhitespace() {
        let stored = DictionaryReplacements.storedReplacement("  k8s  ")
        XCTAssertEqual(stored, "k8s")
        let text = DictionaryReplacements.apply(
            "use kube now",
            pairs: [ReplacementPair(find: "kube", replace: stored)]
        )
        XCTAssertEqual(text, "use k8s now")
    }

    func testWhitespaceOnlyReplacementDeletesTheMatch() {
        let stored = DictionaryReplacements.storedReplacement(" \n\t ")
        XCTAssertEqual(stored, "")
        let text = DictionaryReplacements.apply(
            "see foo now",
            pairs: [ReplacementPair(find: "foo", replace: stored)]
        )
        XCTAssertEqual(text, "see  now")
    }

    func testEmptyReplacementDeletesTheMatch() {
        let text = DictionaryReplacements.apply(
            "see foo now",
            pairs: [ReplacementPair(find: "foo", replace: "")]
        )
        XCTAssertEqual(text, "see  now")
        XCTAssertFalse(DictionaryPairPolicy.isBlocked(find: "foo", replace: ""))
    }

    func testBenchmarkMishearingsBecomeTheWrittenTerms() {
        XCTAssertEqual(
            DevLexicon.correct("call use effect in the component", profile: .prose),
            "call useEffect in the component"
        )
        XCTAssertEqual(DevLexicon.correct("call use effects later", profile: .prose), "call use effects later")
        XCTAssertEqual(DevLexicon.correct("reuse effect later", profile: .code), "reuse effect later")
        XCTAssertEqual(DevLexicon.correct("Use Effect, then ship.", profile: .prose), "useEffect, then ship.")
        XCTAssertEqual(
            DevLexicon.correct("use the open IAPI today", profile: .prose),
            "use the OpenAI API today"
        )
        XCTAssertEqual(
            DevLexicon.correct("use the openRE API today", profile: .code),
            "use the OpenAI API today"
        )
        XCTAssertEqual(DevLexicon.correct("openRE APIs", profile: .prose), "openRE APIs")
        XCTAssertEqual(DevLexicon.correct("read the open ai docs", profile: .prose), "read the OpenAI docs")
        XCTAssertEqual(DevLexicon.correct("run gitribase now", profile: .prose), "run git rebase now")
        XCTAssertEqual(DevLexicon.correct("run getra base now", profile: .shell), "run git rebase now")
        XCTAssertEqual(DevLexicon.correct("getra basement", profile: .prose), "getra basement")
        XCTAssertEqual(DevLexicon.correct("mygitribase", profile: .prose), "mygitribase")
        XCTAssertEqual(DevLexicon.correct("postgars is up", profile: .prose), "Postgres is up")
        XCTAssertEqual(DevLexicon.correct("postgas is up", profile: .chat), "Postgres is up")
        XCTAssertEqual(DevLexicon.correct("postgarsx", profile: .prose), "postgarsx")
        XCTAssertEqual(DevLexicon.correct("xpostgas", profile: .prose), "xpostgas")
        XCTAssertEqual(DevLexicon.correct("post gres is up", profile: .prose), "PostgreSQL is up")
        XCTAssertEqual(DevLexicon.correct("the jason file", profile: .prose), "the jason file")
        XCTAssertEqual(DevLexicon.correct("the jason file", profile: .code), "the JSON file")
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
        XCTAssertEqual(DictationDefaults.engine, .appleSpeech)
        XCTAssertEqual(EngineSelection.resolve(stored: nil), .appleSpeech)
        XCTAssertEqual(EngineSelection.resolve(stored: ""), .appleSpeech)
        XCTAssertEqual(EngineSelection.resolve(stored: "not-an-engine"), .appleSpeech)
    }

    func testStoredEngineWinsOverTheDefault() {
        XCTAssertEqual(EngineSelection.resolve(stored: TranscriptionEngine.appleSpeech.rawValue), .appleSpeech)
        XCTAssertEqual(EngineSelection.resolve(stored: TranscriptionEngine.whisper.rawValue), .whisper)
        XCTAssertEqual(EngineSelection.resolve(stored: TranscriptionEngine.bark30Clean.rawValue), .bark30Clean)
    }

    func testUnsetWhisperModelIsSmallEnAndASavedModelWins() {
        XCTAssertEqual(DictationDefaults.whisperModel, .smallEn)
        XCTAssertEqual(WhisperModel.recommended, .smallEn)
        XCTAssertEqual(EngineSelection.resolveWhisperModel(stored: nil), .smallEn)
        XCTAssertEqual(EngineSelection.resolveWhisperModel(stored: ""), .smallEn)
        XCTAssertEqual(EngineSelection.resolveWhisperModel(stored: "not-a-model"), .smallEn)
        XCTAssertEqual(EngineSelection.resolveWhisperModel(stored: WhisperModel.small.rawValue), .small)
        XCTAssertEqual(EngineSelection.resolveWhisperModel(stored: WhisperModel.base.rawValue), .base)
        XCTAssertEqual(WhisperModel.smallEn.pickerLabel, "Whisper Small (English) · recommended")
        XCTAssertEqual(WhisperModel.small.pickerLabel, "Whisper Small")
        XCTAssertTrue(WhisperModel.smallEn.detail.contains("recommended"))
        XCTAssertFalse(WhisperModel.small.detail.contains("recommended"))
    }

    func testMissingWhisperModelUsesSpeechForThatTakeOnly() {
        let reason = WhisperModel.smallEn.unavailableMessage
        XCTAssertEqual(reason, "Whisper Small (English) is not downloaded. Download the model in the menu")
        let notice = EngineSelection.whisperUnavailableNotice(reason: reason)
        XCTAssertEqual(
            notice,
            "Whisper Small (English) is not downloaded. Download the model in the menu. This take used macOS Speech."
        )
        let missing = EngineSelection.engineForTake(
            selected: .whisper,
            whisperReady: false,
            translating: false,
            unavailableNotice: notice
        )
        XCTAssertEqual(missing.engine, .appleSpeech)
        XCTAssertEqual(missing.notice, notice)
        XCTAssertEqual(EngineSelection.resolve(stored: TranscriptionEngine.whisper.rawValue), .whisper)

        let ready = EngineSelection.engineForTake(
            selected: .whisper,
            whisperReady: true,
            translating: false,
            unavailableNotice: notice
        )
        XCTAssertEqual(ready, DictationTakePlan(engine: .whisper, notice: nil))

        let translate = EngineSelection.engineForTake(
            selected: .whisper,
            whisperReady: false,
            translating: true,
            unavailableNotice: notice
        )
        XCTAssertEqual(translate, DictationTakePlan(engine: .whisper, notice: nil))

        let speech = EngineSelection.engineForTake(
            selected: .appleSpeech,
            whisperReady: false,
            translating: false,
            unavailableNotice: notice
        )
        XCTAssertEqual(speech, DictationTakePlan(engine: .appleSpeech, notice: nil))
        XCTAssertEqual(
            EngineSelection.whisperUnavailableNotice(reason: "  "),
            "Whisper is not available. This take used macOS Speech."
        )
        XCTAssertEqual(
            EngineSelection.whisperUnavailableNotice(reason: "Already a sentence."),
            "Already a sentence. This take used macOS Speech."
        )
    }

    func testWhisperFallbackStaysOnDevice() {
        let message = WhisperModel.smallEn.unavailableMessage
        let first = SpeechPrivacy.firstRequest(
            route: .whisperFallback,
            supportsOnDevice: true,
            whisperMessage: message
        )
        XCTAssertEqual(first, .recognize(requiresOnDeviceRecognition: true))
        let failed = SpeechPrivacy.afterFailure(
            route: .whisperFallback,
            attemptedOnDevice: true,
            whisperMessage: message
        )
        XCTAssertEqual(failed, .whisperUnavailable(message))
        XCTAssertFalse(speechPlanLeavesTheMac(first))
        XCTAssertFalse(speechPlanLeavesTheMac(failed))
    }

    func testWhisperFallbackWithoutOnDeviceUsesTheWhisperMessage() {
        let message = WhisperModel.smallEn.unavailableMessage
        XCTAssertEqual(message, "Whisper Small (English) is not downloaded. Download the model in the menu")
        let unavailable = SpeechPrivacy.firstRequest(
            route: .whisperFallback,
            supportsOnDevice: false,
            whisperMessage: message
        )
        XCTAssertEqual(unavailable, .whisperUnavailable(message))
        let afterOffDeviceAttempt = SpeechPrivacy.afterFailure(
            route: .whisperFallback,
            attemptedOnDevice: false,
            whisperMessage: message
        )
        XCTAssertEqual(afterOffDeviceAttempt, .whisperUnavailable(message))
        XCTAssertFalse(speechPlanLeavesTheMac(unavailable))
        XCTAssertFalse(speechPlanLeavesTheMac(afterOffDeviceAttempt))
    }

    func testLivePartialsStayOnDeviceUnlessSpeechWasChosen() {
        let whisperOnDevice = SpeechPrivacy.livePartials(engine: .whisper, supportsOnDevice: true)
        let whisperUnsupported = SpeechPrivacy.livePartials(engine: .whisper, supportsOnDevice: false)
        XCTAssertEqual(whisperOnDevice, .recognize(requiresOnDeviceRecognition: true))
        XCTAssertEqual(whisperUnsupported, .skip)
        XCTAssertFalse(livePartialPlanLeavesTheMac(whisperOnDevice))
        XCTAssertFalse(livePartialPlanLeavesTheMac(whisperUnsupported))

        for engine in TranscriptionEngine.allCases where engine != .appleSpeech {
            XCTAssertEqual(
                SpeechPrivacy.livePartials(engine: engine, supportsOnDevice: true),
                .recognize(requiresOnDeviceRecognition: true)
            )
            XCTAssertEqual(
                SpeechPrivacy.livePartials(engine: engine, supportsOnDevice: false),
                .skip
            )
        }

        let speechOnDevice = SpeechPrivacy.livePartials(engine: .appleSpeech, supportsOnDevice: true)
        let speechUnsupported = SpeechPrivacy.livePartials(engine: .appleSpeech, supportsOnDevice: false)
        XCTAssertEqual(speechOnDevice, .recognize(requiresOnDeviceRecognition: false))
        XCTAssertEqual(speechUnsupported, .recognize(requiresOnDeviceRecognition: false))
        XCTAssertTrue(livePartialPlanLeavesTheMac(speechOnDevice))
        XCTAssertTrue(livePartialPlanLeavesTheMac(speechUnsupported))
    }

    func testSwitchingFromSpeechToWhisperDuringATakeDropsServerPartials() {
        let onDevice = SpeechPrivacy.reviseLivePartials(
            activeEngine: .appleSpeech,
            newEngine: .whisper,
            partialsEnabled: true,
            supportsOnDevice: true
        )
        XCTAssertEqual(onDevice, .replace(.recognize(requiresOnDeviceRecognition: true)))

        let unavailable = SpeechPrivacy.reviseLivePartials(
            activeEngine: .appleSpeech,
            newEngine: .whisper,
            partialsEnabled: true,
            supportsOnDevice: false
        )
        XCTAssertEqual(unavailable, .replace(.skip))

        XCTAssertEqual(
            SpeechPrivacy.reviseLivePartials(
                activeEngine: .whisper,
                newEngine: .whisper,
                partialsEnabled: true,
                supportsOnDevice: true
            ),
            .unchanged
        )
        XCTAssertEqual(
            SpeechPrivacy.reviseLivePartials(
                activeEngine: .appleSpeech,
                newEngine: .whisper,
                partialsEnabled: false,
                supportsOnDevice: true
            ),
            .unchanged
        )
    }

    func testLivePartialPlanWiresTheRequestFlag() {
        final class FakeRequest: LivePartialSpeechRequest {
            var requiresOnDeviceRecognition = false
            var shouldReportPartialResults = false
        }

        var made = 0
        let onDevice = LivePartialRequests.make(plan: .recognize(requiresOnDeviceRecognition: true)) {
            made += 1
            return FakeRequest()
        }
        XCTAssertEqual(made, 1)
        XCTAssertEqual(onDevice?.requiresOnDeviceRecognition, true)
        XCTAssertEqual(onDevice?.shouldReportPartialResults, true)

        let server = LivePartialRequests.make(plan: .recognize(requiresOnDeviceRecognition: false)) {
            made += 1
            return FakeRequest()
        }
        XCTAssertEqual(server?.requiresOnDeviceRecognition, false)

        let beforeSkip = made
        let skipped = LivePartialRequests.make(plan: .skip) {
            made += 1
            return FakeRequest()
        }
        XCTAssertNil(skipped)
        XCTAssertEqual(made, beforeSkip)

        let speechToWhisper = SpeechPrivacy.reviseLivePartials(
            activeEngine: .appleSpeech,
            newEngine: .whisper,
            partialsEnabled: true,
            supportsOnDevice: false
        )
        guard case .replace(let plan) = speechToWhisper else {
            return XCTFail("Expected the server partial request to be replaced")
        }
        let replacement = LivePartialRequests.make(plan: plan) {
            made += 1
            return FakeRequest()
        }
        XCTAssertNil(replacement)
        XCTAssertEqual(made, beforeSkip)
    }

    func testChosenSpeechCanStillRetryOffDevice() {
        let first = SpeechPrivacy.firstRequest(
            route: .chosenEngine,
            supportsOnDevice: true,
            whisperMessage: ""
        )
        XCTAssertEqual(first, .recognize(requiresOnDeviceRecognition: true))
        XCTAssertEqual(
            SpeechPrivacy.afterFailure(route: .chosenEngine, attemptedOnDevice: true, whisperMessage: ""),
            .recognize(requiresOnDeviceRecognition: false)
        )
        XCTAssertEqual(
            SpeechPrivacy.firstRequest(route: .chosenEngine, supportsOnDevice: false, whisperMessage: ""),
            .recognize(requiresOnDeviceRecognition: false)
        )
        XCTAssertEqual(
            SpeechPrivacy.afterFailure(route: .chosenEngine, attemptedOnDevice: false, whisperMessage: ""),
            .rethrowSpeechError
        )
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
            XCTAssertEqual(bark.loaderFiles.map(\.name), ["bark_mlx.py", "bark_loader.py"])
            XCTAssertTrue(bark.loaderChecksumJSON.contains(bark.loaderFiles[0].sha256))
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

final class LivePartialGateTests: XCTestCase {
    func testAppendAfterRevokeDoesNothing() {
        let gate = LivePartialGate<NSObject>()
        let request = NSObject()
        gate.publish(feeds: true, request: request)
        var appends = 0
        XCTAssertTrue(gate.appendIfLive { _ in appends += 1 })
        XCTAssertEqual(appends, 1)
        let revoked = gate.revoke()
        XCTAssertTrue(revoked === request)
        XCTAssertFalse(gate.appendIfLive { _ in appends += 1 })
        XCTAssertEqual(appends, 1)
    }

    func testSameRequestRepublishedBetweenSnapshotAndRecheckDoesNotAppend() {
        let gate = LivePartialGate<NSObject>()
        let request = NSObject()
        gate.publish(feeds: true, request: request)
        var ran = false
        gate.betweenSnapshotAndRecheck = {
            _ = gate.revoke()
            gate.publish(feeds: true, request: request)
        }
        defer { gate.betweenSnapshotAndRecheck = nil }
        // Identity matches again, so this fails only while the revoke epoch is checked.
        XCTAssertFalse(gate.appendIfLive { _ in ran = true })
        XCTAssertFalse(ran)
    }

    func testConcurrentRevokeAndAppendDoesNotCrashOrAppendAfterRevoke() {
        let gate = LivePartialGate<NSObject>()
        gate.publish(feeds: true, request: NSObject())
        let appends = LivePartialAppendCount()
        let group = DispatchGroup()
        for _ in 0..<6 {
            group.enter()
            DispatchQueue.global().async {
                for _ in 0..<300 {
                    gate.appendIfLive { _ in
                        appends.add()
                    }
                }
                group.leave()
            }
        }
        group.enter()
        DispatchQueue.global().async {
            gate.revoke()
            gate.publish(feeds: true, request: NSObject())
            gate.revoke()
            group.leave()
        }
        group.wait()
        let settled = appends.value
        XCTAssertFalse(gate.appendIfLive { _ in
            appends.add()
        })
        XCTAssertEqual(appends.value, settled)
    }
}

/// Increments only happen inside `LivePartialGate.appendIfLive`, which holds the gate lock.
private final class LivePartialAppendCount: @unchecked Sendable {
    private var stored = 0
    func add() { stored += 1 }
    var value: Int { stored }
}

private func livePartialPlanLeavesTheMac(_ plan: LivePartialPlan) -> Bool {
    switch plan {
    case .recognize(let requiresOnDeviceRecognition):
        return !requiresOnDeviceRecognition
    case .skip:
        return false
    }
}

private func speechPlanLeavesTheMac(_ plan: SpeechRequestPlan) -> Bool {
    switch plan {
    case .recognize(let requiresOnDeviceRecognition):
        return !requiresOnDeviceRecognition
    case .whisperUnavailable(_):
        return false
    case .rethrowSpeechError:
        return false
    }
}
