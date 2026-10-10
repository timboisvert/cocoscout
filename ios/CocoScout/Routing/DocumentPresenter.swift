import HotwireNative
import QuickLook
import UIKit
import WebKit

/// Downloads a file the signed-in person can see (using the web view's
/// cookies) and shows it in Quick Look, which has Share, Print and, for a
/// calendar file, Add to Calendar.
@MainActor
final class DocumentPresenter: NSObject, QLPreviewControllerDataSource {
    static let shared = DocumentPresenter()

    private var fileURL: URL?

    func present(_ url: URL, from viewController: UIViewController) {
        Task {
            do {
                fileURL = try await download(url)
                let preview = QLPreviewController()
                preview.dataSource = self
                viewController.present(preview, animated: true)
            } catch {
                let alert = UIAlertController(title: "Couldn't open that file", message: "Check your connection and try again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                viewController.present(alert, animated: true)
            }
        }
    }

    private func download(_ url: URL) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        for cookie in await WKWebsiteDataStore.default().httpCookieStore.allCookies() {
            configuration.httpCookieStorage?.setCookie(cookie)
        }
        configuration.httpAdditionalHeaders = ["User-Agent": Hotwire.config.userAgent]

        let (data, response) = try await URLSession(configuration: configuration).data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType != "text/html" else {
            throw URLError(.badServerResponse)
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(response.suggestedFilename ?? "document")
        try data.write(to: file)
        return file
    }

    // MARK: QLPreviewControllerDataSource

    nonisolated func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        1
    }

    nonisolated func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        MainActor.assumeIsolated {
            (fileURL ?? URL(fileURLWithPath: "/dev/null")) as NSURL
        }
    }
}
