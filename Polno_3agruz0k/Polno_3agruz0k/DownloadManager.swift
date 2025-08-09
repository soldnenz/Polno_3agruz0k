import Foundation
import SwiftUI

class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double = 0.0
    @Published var isDownloading = false

    var onComplete: ((URL?) -> Void)?

    private var targetURL: URL?

    func startDownload(from url: URL, apiKey: String) {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        isDownloading = true
        progress = 0.0

        targetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")

        let task = session.downloadTask(with: request)
        task.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            if totalBytesExpectedToWrite > 0 {
                self.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {

        print("📁 Файл загружен в: \(location.path)")

        guard let targetURL = targetURL else {
            print("❌ targetURL не задан")
            DispatchQueue.main.async {
                self.onComplete?(nil)
            }
            return
        }

        do {
            try FileManager.default.copyItem(at: location, to: targetURL)
            print("✅ Файл скопирован в: \(targetURL.path)")
            DispatchQueue.main.async {
                self.isDownloading = false
                self.progress = 1.0
                self.onComplete?(targetURL)
            }
        } catch {
            print("❌ Ошибка копирования: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.onComplete?(nil)
            }
        }
    }
}
