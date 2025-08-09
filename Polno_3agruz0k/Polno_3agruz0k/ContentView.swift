//  MediaDownloaderApp.swift
//  SwiftUI iOS 18

import SwiftUI
import AVKit
import UIKit
import Foundation
import Combine
import Photos


// MARK: - Constants
struct API {
    static let baseURL = ""
    static let apiKey = ""
}

// MARK: - Main View


struct MainView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            VideoDownloaderView()
                .tabItem {
                    Image(systemName: "video.fill")
                    Text("Видео")
                }.tag(0)

            AudioDownloaderView()
                .tabItem {
                    Image(systemName: "music.note")
                    Text("Музыка")
                }.tag(1)
        }
    }
}

// MARK: - Audio View

struct TrackInfo: Codable, Identifiable {
    let id: String
    let title: String
    let duration: String
    var thumbnail: String     // ← было let, теперь var
    let streamURL: String
    let downloadURL: String
    
    enum CodingKeys: String, CodingKey {
        case id = "uid"
        case title
        case duration
        case thumbnail
        case streamURL = "stream_url"
        case downloadURL = "download_url"
    }
}


struct AudioDownloaderView: View {
    @State private var query: String = ""
    @State private var results: [TrackInfo] = []
    @State private var isLoading = false
    @State private var pollingTimer: Timer?
    @State private var currentTaskID: String?
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool
    @StateObject private var audioManager = AudioPlayerManager()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        TextField("Введите название песни", text: $query)
                            .focused($isFocused)
                            .textFieldStyle(.roundedBorder)
                            .padding(.leading)

                        if !query.isEmpty {
                            Button {
                                query = ""
                                UIApplication.shared.impactFeedback(style: .light)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                            }
                            .padding(.trailing, 10)
                        }
                    }

                    Button("Поиск") {
                        UIApplication.shared.impactFeedback(style: .medium)
                        startSearch()
                    }
                    .buttonStyle(.borderedProminent)

                    if isLoading {
                        ProgressView()
                    }

                    ForEach(results, id: \.id) { item in
                        TrackCard(
                            item: item,
                            downloadAction: { downloadMP3(from: item.downloadURL) },
                            formatTime: formatTime
                        )
                        .environmentObject(audioManager)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    if let errorMessage = errorMessage {
                        Text(errorMessage).foregroundColor(.red).padding()
                    }
                }
                .padding()
                .onTapGesture {
                    isFocused = false
                }
            }
            .navigationTitle("Музыка")
        }
    }
    // MARK: - Отправка на сервер
    func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    
    func startSearch() {
        isLoading = true
        errorMessage = nil
        results = []

        guard let url = URL(string: "\(API.baseURL)/search_audio_task") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(API.apiKey, forHTTPHeaderField: "X-API-Key")
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        request.httpBody = "query=\(encodedQuery)".data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else {
                    self.errorMessage = "Ошибка сети: \(error?.localizedDescription ?? "неизвестно")"
                    self.isLoading = false
                    return
                }

                if let taskResponse = try? JSONDecoder().decode(TaskResponse.self, from: data) {
                    self.currentTaskID = taskResponse.task_id
                    self.pollStatus()
                } else {
                    self.errorMessage = "Ошибка получения task_id"
                    self.isLoading = false
                }
            }
        }.resume()
    }

    // MARK: - Опрос статуса

    func pollStatus() {
        guard let taskID = currentTaskID,
              let url = URL(string: "\(API.baseURL)/search_audio_status?task_id=\(taskID)") else { return }

        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            var request = URLRequest(url: url)
            request.setValue(API.apiKey, forHTTPHeaderField: "X-API-Key")

            URLSession.shared.dataTask(with: request) { data, _, error in
                DispatchQueue.main.async {
                    guard let data = data, error == nil else {
                        self.errorMessage = "Ошибка сети при проверке статуса"
                        self.isLoading = false
                        self.pollingTimer?.invalidate()
                        return
                    }

                    if let status = try? JSONDecoder().decode(StatusResponse.self, from: data) {
                        switch status.status {
                        case "pending":
                            break
                        case "done":
                            self.results = status.tracks ?? []
                            self.isLoading = false
                            self.pollingTimer?.invalidate()
                        case "error":
                            self.errorMessage = status.error ?? "Неизвестная ошибка"
                            self.isLoading = false
                            self.pollingTimer?.invalidate()
                        default:
                            self.errorMessage = "Неверный ответ сервера"
                            self.isLoading = false
                            self.pollingTimer?.invalidate()
                        }
                    } else {
                        self.errorMessage = "Ошибка парсинга статуса"
                        self.isLoading = false
                        self.pollingTimer?.invalidate()
                    }
                }
            }.resume()
        }
    }

    // MARK: - Аудио



    func downloadMP3(from downloadPath: String) {
        guard let url = URL(string: "\(API.baseURL)\(downloadPath)") else { return }

        var request = URLRequest(url: url)
        request.setValue(API.apiKey, forHTTPHeaderField: "X-API-Key")

        // Показываем оверлей загрузки
        DispatchQueue.main.async {
            if let window = UIApplication.shared.windows.first {
                let overlay = UIView(frame: window.bounds)
                overlay.backgroundColor = UIColor.black.withAlphaComponent(0.6)
                overlay.tag = 999  // Для последующего удаления

                let spinner = UIActivityIndicatorView(style: .large)
                spinner.center = overlay.center
                spinner.startAnimating()
                overlay.addSubview(spinner)

                let label = UILabel()
                label.text = "Идёт скачивание…"
                label.textColor = .white
                label.textAlignment = .center
                label.font = UIFont.boldSystemFont(ofSize: 16)
                label.translatesAutoresizingMaskIntoConstraints = false
                overlay.addSubview(label)

                NSLayoutConstraint.activate([
                    label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
                    label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor)
                ])

                window.addSubview(overlay)
            }
        }

        URLSession.shared.downloadTask(with: request) { tempURL, response, error in
            // Убираем оверлей
            DispatchQueue.main.async {
                if let window = UIApplication.shared.windows.first,
                   let overlay = window.viewWithTag(999) {
                    overlay.removeFromSuperview()
                }
            }

            guard let tempURL = tempURL, error == nil else {
                print("❌ Ошибка загрузки: \(error?.localizedDescription ?? "неизвестно")")
                return
            }

            let fileManager = FileManager.default
            let fileName = "downloaded_audio_\(UUID().uuidString).mp3"
            let destinationURL = fileManager.temporaryDirectory.appendingPathComponent(fileName)

            do {
                try fileManager.moveItem(at: tempURL, to: destinationURL)

                DispatchQueue.main.async {
                    let activityVC = UIActivityViewController(activityItems: [destinationURL], applicationActivities: nil)

                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        rootVC.present(activityVC, animated: true, completion: nil)
                    }
                }
            } catch {
                print("❌ Ошибка перемещения файла: \(error.localizedDescription)")
            }
        }.resume()
    }


}

// MARK: - Ответы сервера

struct TaskResponse: Codable {
    let task_id: String
    let status: String
}

struct StatusResponse: Codable {
    let status: String
    let tracks: [TrackInfo]?
    let error: String?
}


// MARK: - Video View
struct VideoDownloaderView: View {
    @State private var url: String = ""
    @State private var result: VideoResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var taskId: String?
    @State private var pollingTimer: Timer?
    @FocusState private var isFocused: Bool

    // Для алерта
    @State private var showAlert = false
    @State private var alertMessage = ""
    @StateObject private var downloader = DownloadManager()
    // Хелпер для сохранения видео
    private let videoSaver = VideoSaveHelper()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Поле ввода ссылки
                    HStack {
                        TextField("Вставьте ссылку", text: $url)
                            .focused($isFocused)
                            .textFieldStyle(.roundedBorder)
                            .padding(.leading)

                        if !url.isEmpty {
                            Button(action: {
                                url = ""
                                UIApplication.shared.impactFeedback(style: .light)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .padding(.trailing, 10)
                        }
                    }

                    // Кнопки
                    HStack(spacing: 16) {
                        Button("Вставить из буфера") {
                            if let clipboard = UIPasteboard.general.string {
                                url = clipboard
                                UIApplication.shared.impactFeedback(style: .soft)
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Скачать видео") {
                            UIApplication.shared.impactFeedback(style: .medium)
                            startDownload()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    // Лоадер
                    if isLoading {
                        ProgressView().padding()
                    }
                    // Прогресс загрузки файла с сервера
                    if downloader.isDownloading {
                        VStack(spacing: 8) {
                            Text("Загрузка файла...").font(.subheadline)
                            ProgressView(value: downloader.progress)
                                .progressViewStyle(LinearProgressViewStyle())
                                .padding(.horizontal)
                            Text("\(Int(downloader.progress * 100))%")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }

                    // Результат
                    if let result = result {
                        VStack(alignment: .leading, spacing: 10) {
                            AsyncImage(url: URL(string: result.thumbnail)) { image in
                                image.resizable()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(height: 200)
                            .cornerRadius(12)

                            Text(result.title).bold()
                            Button("Сохранить в галерею") {
                                UIApplication.shared.impactFeedback(style: .soft)
                                downloadAndSaveFile(url: result.file)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }

                    // Ошибка
                    if let errorMessage = errorMessage {
                        Text(errorMessage).foregroundColor(.red).padding()
                    }
                }
                .padding()
                .onTapGesture {
                    isFocused = false
                }
            }
            .navigationTitle("Видео")
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Готово"), message: Text(alertMessage), dismissButton: .default(Text("Ок")))
            }
        }
    }

    // MARK: - Старт задачи на сервере
    func startDownload() {
        isLoading = true
        errorMessage = nil
        result = nil
        taskId = nil

        guard let formData = "link=\(url)".data(using: .utf8) else { return }

        var request = URLRequest(url: URL(string: "\(API.baseURL)/download_video")!)
        request.httpMethod = "POST"
        request.httpBody = formData
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(API.apiKey, forHTTPHeaderField: "X-API-Key")

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let data = data,
                   let taskResponse = try? JSONDecoder().decode(DownloadTaskResponse.self, from: data) {
                    self.taskId = taskResponse.task_id
                    self.pollDownloadStatus()
                } else {
                    self.isLoading = false
                    self.errorMessage = "Ошибка запуска задачи"
                }
            }
        }.resume()
    }

    func pollDownloadStatus() {
        guard let taskId = taskId else { return }

        pollingTimer?.invalidate()

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            var request = URLRequest(url: URL(string: "\(API.baseURL)/download_status?task_id=\(taskId)")!)
            request.setValue(API.apiKey, forHTTPHeaderField: "X-API-Key")

            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    guard let data = data, error == nil else {
                        self.pollingTimer?.invalidate()
                        self.isLoading = false
                        self.errorMessage = "Ошибка сети при проверке статуса"
                        return
                    }

                    do {
                        // Попробуем декодировать только статус
                        let base = try JSONDecoder().decode(GenericStatus.self, from: data)

                        switch base.status {
                        case "pending":
                            // Просто ждём, ничего не делаем
                            break
                        case "done":
                            let decoded = try JSONDecoder().decode(VideoResult.self, from: data)
                            self.pollingTimer?.invalidate()
                            self.isLoading = false
                            self.result = decoded
                        case "error":
                            let errorDecoded = try JSONDecoder().decode(ErrorStatus.self, from: data)
                            self.pollingTimer?.invalidate()
                            self.isLoading = false
                            self.errorMessage = "Ошибка: \(errorDecoded.error ?? "неизвестно")"
                        default:
                            self.pollingTimer?.invalidate()
                            self.isLoading = false
                            self.errorMessage = "Неизвестный статус: \(base.status)"
                        }

                    } catch {
                        self.pollingTimer?.invalidate()
                        self.isLoading = false
                        self.errorMessage = "Ошибка парсинга: \(error.localizedDescription)"
                    }
                }
            }.resume()
        }
    }


    // MARK: - Скачивание и сохранение
    func downloadAndSaveFile(url: String) {
        guard let fileURL = URL(string: "\(API.baseURL)\(url)") else { return }

        downloader.onComplete = { savedURL in
            guard let savedURL = savedURL else {
                self.alertMessage = "Ошибка при загрузке файла"
                self.showAlert = true
                return
            }

            print("🎬 Передаём в галерею: \(savedURL.path)")
            saveToPhotoLibrary(url: savedURL)

        }


        downloader.startDownload(from: fileURL, apiKey: API.apiKey)
    }


    func saveToPhotoLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.alertMessage = "Нет доступа к галерее"
                    self.showAlert = true
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: nil)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.alertMessage = "🎉 Видео сохранено в галерею"
                    } else {
                        self.alertMessage = "Ошибка при сохранении: \(error?.localizedDescription ?? "неизвестно")"
                    }
                    self.showAlert = true
                }
            }
        }
    }
}

// MARK: - Видео-хелпер
class VideoSaveHelper: NSObject {
    var onComplete: ((Error?) -> Void)?

    func saveVideo(from url: URL) {
        UISaveVideoAtPathToSavedPhotosAlbum(url.path, self, #selector(videoSaved(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func videoSaved(_ videoPath: String, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        onComplete?(error)
    }
}

// MARK: - Модели
struct VideoResult: Codable {
    let status: String
    let file: String
    let title: String
    let thumbnail: String
    let description: String?
    let tags: [String]?
    let duration: Double?
    let uploader: String?
}


struct DownloadTaskResponse: Codable {
    let task_id: String
    let status: String
}

struct ErrorStatus: Codable {
    let status: String
    let error: String?
}

struct GenericStatus: Codable {
    let status: String
}



// MARK: - Haptics Helper
extension UIApplication {
    func impactFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
