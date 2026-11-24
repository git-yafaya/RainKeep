// 验证浏览器请求的往返编码和 URL scheme 的信任边界。
import Foundation
import Testing
import RainkeepCore

/// 查询串内的分隔符、Unicode 和可选字段均应原样保留。
@Test func browserRequestRoundTrip() throws {
    let link = try #require(URL(string: "https://example.org/a?q=a%2Bb&file=1#piece"))
    let request = try #require(BrowserRequest(url: link, referrer: "https://example.org/?a=1&b=2",
                                              filename: "资料 + 100% & #1.zip",
                                              cookies: "token=a+b/c==; id=42", userAgent: "Browser/123"))
    #expect(BrowserRequest.parse(BrowserRequest.url(for: request)) == request)
    #expect(request.headers == ["Referer": "https://example.org/?a=1&b=2",
                                "Cookie": "token=a+b/c==; id=42", "User-Agent": "Browser/123"])
    let minimal = try #require(BrowserRequest(url: link))
    #expect(BrowserRequest.parse(BrowserRequest.url(for: minimal)) == minimal)
    #expect(minimal.headers.isEmpty)
}

/// 外部调用者不能指定其他协议、歧义目标、危险文件名或多行请求头。
@Test(arguments: [
    "https://add?url=https://example.org", "rainkeep://other?url=https://example.org",
    "rainkeep://add?url=file:///tmp/file", "rainkeep://add?url=data:text/plain,abc",
    "rainkeep://add?url=blob:https://example.org/id", "rainkeep://add?url=https:///file",
    "rainkeep://add", "rainkeep://add?url=https://one.test&url=https://two.test",
    "rainkeep://add?url=https://example.org&cookies=a%0D%0AX-Header:1",
    "rainkeep://add?url=https://example.org&filename=..%2Foutside",
])
func rejectsInvalidBrowserRequests(_ raw: String) throws {
    let url = try #require(URL(string: raw))
    #expect(BrowserRequest.parse(url) == nil)
}
