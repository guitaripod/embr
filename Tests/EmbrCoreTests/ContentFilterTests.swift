import Testing
@testable import EmbrCore

@Suite struct ContentFilterTests {
    private let filter = ContentFilter()

    @Test func allowsCleanMessages() {
        #expect(!filter.shouldHide("great stream today, love the gameplay"))
        #expect(!filter.shouldHide("PogChamp that was insane"))
        #expect(!filter.shouldHide(""))
    }

    @Test func hidesSevereSlurEmbeddedInSentence() {
        #expect(filter.shouldHide("you are such a faggot lol"))
        #expect(filter.shouldHide("retard"))
    }

    @Test func doesNotHideBenignWordsContainingATerm() {
        for word in ["classic", "assassin", "grape", "grapes", "therapist", "scrape",
                     "class", "kiss", "cockburn", "scunthorpe", "encyclopedia"] {
            #expect(!filter.shouldHide("what a \(word) moment"), "false positive on \(word)")
        }
    }

    @Test func doesNotHideShorterWordsThatCollapseOntoATerm() {
        for word in ["con", "cons", "icon", "bacon", "second", "gok"] {
            #expect(!filter.shouldHide("pros and \(word) here"), "false positive on \(word)")
        }
    }

    @Test func defeatsLeetspeakObfuscation() {
        #expect(filter.shouldHide("n1gg3r"))
        #expect(filter.shouldHide("f4ggot"))
        #expect(filter.shouldHide("f@g"))
    }

    @Test func defeatsCharacterElongation() {
        #expect(filter.shouldHide("niiiggerrr"))
        #expect(filter.shouldHide("faaaggg"))
    }

    @Test func userKeywordsHideMatchingMessages() {
        let custom = ContentFilter(userTerms: ["spoiler"], includeDefaultList: false)
        #expect(custom.shouldHide("big SPOILER ahead"))
        #expect(!custom.shouldHide("totally safe message"))
    }

    @Test func userPhrasesMatchAsSubstring() {
        let custom = ContentFilter(userTerms: ["free vbucks"], includeDefaultList: false)
        #expect(custom.shouldHide("get your free vbucks here"))
        #expect(!custom.shouldHide("vbucks are cool"))
    }

    @Test func userKeywordsWithInternalPunctuationStillMatch() {
        let custom = ContentFilter(userTerms: ["n-word", "web.gg"], includeDefaultList: false)
        #expect(custom.shouldHide("stop saying the n-word"))
        #expect(custom.shouldHide("visit web.gg now"))
        #expect(!custom.shouldHide("just a normal message"))
    }

    @Test func emptyFilterHidesNothing() {
        let inert = ContentFilter(userTerms: [], includeDefaultList: false)
        #expect(inert.isEmpty)
        #expect(!inert.shouldHide("nigger"))
    }

    @Test func userTermsComposeWithDefaultList() {
        let combined = ContentFilter(userTerms: ["mmr"], includeDefaultList: true)
        #expect(combined.shouldHide("stop talking about mmr"))
        #expect(combined.shouldHide("what a faggot"))
        #expect(!combined.shouldHide("good game everyone"))
    }
}
