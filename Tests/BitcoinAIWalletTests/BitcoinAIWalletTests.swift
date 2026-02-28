import XCTest
@testable import BitcoinAIWallet

final class BitcoinAIWalletTests: XCTestCase {

    // MARK: - BIP39 Mnemonic Tests

    func testMnemonicGenerates12Words() throws {
        let mnemonic = try Mnemonic.generate(wordCount: .twelve)
        let words = mnemonic.components(separatedBy: " ")
        XCTAssertEqual(words.count, 12)
    }

    func testMnemonicGenerates24Words() throws {
        let mnemonic = try Mnemonic.generate(wordCount: .twentyFour)
        let words = mnemonic.components(separatedBy: " ")
        XCTAssertEqual(words.count, 24)
    }

    func testMnemonicValidation() throws {
        let mnemonic = try Mnemonic.generate(wordCount: .twelve)
        XCTAssertTrue(Mnemonic.isValid(mnemonic: mnemonic))
        XCTAssertFalse(Mnemonic.isValid(mnemonic: "invalid mnemonic phrase that should fail"))
    }

    // MARK: - Intent Parser Tests

    func testSendIntentParsing() {
        let parser = IntentParser()
        let result = parser.parse("send 0.5 btc to bc1qtest123")
        if case .send = result {
            // Correct intent detected
        } else {
            XCTFail("Expected send intent, got \(result)")
        }
    }

    func testBalanceIntentParsing() {
        let parser = IntentParser()
        let result = parser.parse("what is my balance")
        if case .checkBalance = result {
            // Correct intent detected
        } else {
            XCTFail("Expected checkBalance intent, got \(result)")
        }
    }

    func testReceiveIntentParsing() {
        let parser = IntentParser()
        let result = parser.parse("receive bitcoin")
        if case .receive = result {
            // Correct intent detected
        } else {
            XCTFail("Expected receive intent, got \(result)")
        }
    }
}
