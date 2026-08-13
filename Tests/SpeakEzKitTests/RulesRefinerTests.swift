import Testing
@testable import SpeakEzKit

@Suite struct RulesRefinerTests {
    private func refine(_ text: String, vocabulary: [VocabTerm] = []) -> String {
        RulesRefiner(vocabulary: vocabulary).refineSync(text)
    }

    @Test func removesSimpleFillers() {
        #expect(refine("um so I opened the file") == "So I opened the file")
        #expect(refine("I think, uh, we should ship it") == "I think, we should ship it")
        #expect(refine("Um, hello there") == "Hello there")
    }

    @Test func keepsCleanTextUntouched() {
        #expect(refine("Ship the release notes today.") == "Ship the release notes today.")
        #expect(refine("The version is 3.5 gb in size.") == "The version is 3.5 gb in size.")
    }

    @Test func doesNotRemoveFillerLookalikesInsideWords() {
        // "er" and "um" appear inside real words; only standalone tokens go.
        #expect(refine("the summer era was umpteen years ago")
            == "The summer era was umpteen years ago")
    }

    @Test func collapsesStutters() {
        #expect(refine("the the build is green") == "The build is green")
        #expect(refine("I think I think it works") == "I think it works")
        #expect(refine("no no no wait") == "No wait")
    }

    @Test func capitalizesAfterSentenceEnds() {
        #expect(refine("it works. um it really works") == "It works. It really works")
    }

    @Test func planAcceptanceExample() {
        let vocabulary = [VocabTerm(text: "tmux", aliases: ["tea mux", "teemux"])]
        #expect(refine("um so I uh opened tea mux", vocabulary: vocabulary)
            == "So I opened tmux")
    }

    @Test func removesFillerPhrases() {
        let refiner = RulesRefiner(
            lexicon: FillerLexicon(
                words: FillerLexicon.standard.words, phrases: ["you know"]))
        #expect(refiner.refineSync("it was, you know, fine") == "It was, fine")
    }

    @Test func fillerAtEndOfSentence() {
        #expect(refine("that should work um.") == "That should work.")
    }

    @Test func emptyAndWhitespaceInput() {
        #expect(refine("") == "")
        #expect(refine("   ") == "")
        #expect(refine("um uh") == "")
    }
}

@Suite struct RefinementOptionsTests {
    private let vocabulary = [VocabTerm(text: "tmux", aliases: ["tea mux"])]

    private func refine(_ text: String, options: RefinementOptions) -> String {
        RulesRefiner(vocabulary: vocabulary, options: options).refineSync(text)
    }

    @Test func fillersCanBeKept() {
        let options = RefinementOptions(removeFillers: false)
        #expect(refine("um the the build works", options: options)
            == "Um the build works")
    }

    @Test func stuttersCanBeKept() {
        let options = RefinementOptions(collapseStutters: false)
        #expect(refine("um the the build works", options: options)
            == "The the build works")
    }

    @Test func vocabularyCanBeSkipped() {
        let options = RefinementOptions(applyVocabulary: false)
        #expect(refine("um I opened tea mux", options: options)
            == "I opened tea mux")
    }

    @Test func capitalizationCanBeSkipped() {
        let options = RefinementOptions(fixCapitalization: false)
        #expect(refine("um so it works. um it really works", options: options)
            == "so it works. it really works")
    }

    @Test func seamRepairRunsRegardless() {
        // Even with capitalization off, removing a filler must not leave
        // orphaned commas or double spaces behind.
        let options = RefinementOptions(fixCapitalization: false)
        #expect(refine("I think, um, that works", options: options)
            == "I think, that works")
    }

    @Test func everythingOffLeavesTextAlone() {
        let options = RefinementOptions(
            removeFillers: false, collapseStutters: false,
            applyVocabulary: false, fixCapitalization: false)
        #expect(refine("um the the tea mux thing", options: options)
            == "um the the tea mux thing")
    }
}

@Suite struct VocabularyCorrectorTests {
    private let corrector = VocabularyCorrector(terms: [
        VocabTerm(text: "tmux", aliases: ["tea mux"]),
        VocabTerm(text: "herdr", aliases: []),
        VocabTerm(text: "PostgreSQL", aliases: ["postgres sequel"]),
    ])

    @Test func exactMatchFixesCasing() {
        #expect(corrector.correct("Tmux") == "tmux")
        #expect(corrector.correct("tmux") == nil)  // already right
        #expect(corrector.correct("postgresql") == "PostgreSQL")
    }

    @Test func aliasMatch() {
        #expect(corrector.correctPair("tea", "mux") == "tmux")
        #expect(corrector.correctPair("postgres", "sequel") == "PostgreSQL")
        #expect(corrector.correctPair("tea", "cup") == nil)
    }

    @Test func fuzzyMatchWithinDistanceOne() {
        #expect(corrector.correct("herder") == "herdr")
        #expect(corrector.correct("tmax") == "tmux")
    }

    @Test func conservativeAboutRealWords() {
        // Distance 2 from "herdr": must NOT be corrected.
        #expect(corrector.correct("harder") == nil)
        // Different first letter: must not be corrected.
        #expect(corrector.correct("emux") == nil)
        // Short words never fuzzy-match.
        #expect(corrector.correct("tux") == nil)
    }

    @Test func disabledTermsAreIgnored() {
        let disabled = VocabularyCorrector(terms: [
            VocabTerm(text: "tmux", aliases: ["tea mux"], enabled: false)
        ])
        #expect(disabled.correct("Tmux") == nil)
        #expect(disabled.correctPair("tea", "mux") == nil)
    }
}
