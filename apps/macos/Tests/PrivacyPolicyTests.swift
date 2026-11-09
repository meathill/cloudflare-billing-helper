import XCTest
@testable import MacApp

final class PrivacyPolicyTests: XCTestCase {
    func testSupportPolicySeparatesDistributionChannels() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try XCTUnwrap(PrivacyPolicyDocument.load(from: repo.appendingPathComponent("docs/macos/privacy-policy-draft.md")))
        for marker in ["App Store edition", "App Store 版", "external support", "外部支持"] {
            XCTAssertTrue(text.contains(marker), "Missing: \(marker)")
        }
    }

    func testBundledPolicySourceContainsBothCompleteLanguages() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("docs/macos/privacy-policy-draft.md")
        let text = try XCTUnwrap(PrivacyPolicyDocument.load(from: url))
        for marker in ["# Privacy Policy", "# 隐私政策", "## Information the app uses", "## Notifications", "## Removing data", "## External links", "## Contact", "## 应用使用的信息", "## 通知", "## 删除数据", "## 外部链接", "## 联系方式", "November 5, 2026", "2026 年 11 月 5 日", "meathill@gmail.com"] { XCTAssertTrue(text.contains(marker), "Missing: \(marker)") }
        let sections = PrivacyPolicyDocument.languages(in: text)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.joined(separator: "\n---\n"), text)
        XCTAssertTrue(sections[0].contains("## Removing data")); XCTAssertTrue(sections[1].contains("## 删除数据"))
        XCTAssertNil(PrivacyPolicyDocument.load(from: nil))
    }
}
