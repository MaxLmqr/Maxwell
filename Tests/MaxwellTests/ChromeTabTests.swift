import Testing
@testable import Maxwell

@Suite("Site d'une adresse")
struct ChromeTabTests {
    @Test(arguments: [
        ("https://github.com/anthropics/claude-code", "github.com"),
        ("https://www.youtube.com/watch?v=abc", "youtube.com"),
        ("https://WWW.Example.COM/", "example.com"),
        ("http://localhost:3000/dashboard", "localhost"),
        ("http://127.0.0.1:8080", "127.0.0.1"),
    ])
    func theSiteIsTheHostNameWithoutWww(url: String, site: String) {
        #expect(ChromeTab.site(fromURL: url) == site)
    }

    @Test func subdomainsStayApartSoGoogleServicesCanHaveDifferentCategories() {
        #expect(ChromeTab.site(fromURL: "https://mail.google.com/mail/u/0/#inbox") == "mail.google.com")
        #expect(ChromeTab.site(fromURL: "https://docs.google.com/document/d/1") == "docs.google.com")
    }

    @Test(arguments: [
        "chrome://newtab/",
        "chrome://settings/privacy",
        "chrome-extension://abcdef/popup.html",
        "about:blank",
        "file:///Users/max/Documents/facture.pdf",
        "",
    ])
    func pagesOutsideTheWebHaveNoSite(url: String) {
        #expect(ChromeTab.site(fromURL: url) == nil)
    }
}
