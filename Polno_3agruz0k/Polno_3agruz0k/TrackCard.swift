import SwiftUI

struct TrackCard: View {
    let item: TrackInfo
    @EnvironmentObject var audioManager: AudioPlayerManager
    let downloadAction: () -> Void
    let formatTime: (Double) -> String

    var isCurrent: Bool {
        audioManager.playingID == item.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                AsyncImage(url: URL(string: item.thumbnail)) { image in
                    image.resizable()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 100, height: 100)
                .cornerRadius(8)

                VStack(alignment: .leading) {
                    Text(item.title).bold()
                    Text("Длительность: \(item.duration)")
                }
            }

            if isCurrent {
                Slider(value: Binding(
                    get: { audioManager.currentTime },
                    set: { audioManager.seek(to: $0) }
                ), in: 0...audioManager.duration)
                .padding(.top, 8)

                Text("\(formatTime(audioManager.currentTime)) / \(formatTime(audioManager.duration))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            HStack(spacing: 16) {
                Button(isCurrent && audioManager.isPlaying ? "Пауза" : "Прослушать") {
                    if isCurrent {
                        if audioManager.isPlaying {
                            audioManager.pause()
                        } else {
                            audioManager.resume()
                        }
                    } else {
                        audioManager.streamMP3(from: item.streamURL, id: item.id)
                    }
                }
                .buttonStyle(.bordered)

                Button("Скачать MP3") {
                    downloadAction()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
