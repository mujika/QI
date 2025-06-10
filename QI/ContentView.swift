//
//  ContentView.swift
//  QI
//
//  Created by 新村彰啓 on 6/10/25.
//

import SwiftUI
import AVFoundation
import Combine

struct RecordingFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let date: Date
    let duration: TimeInterval
}

class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentPlayingId: UUID?
    
    private var audioPlayer: AVAudioPlayer?
    private var recordingSession: AVAudioSession!
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        recordingSession = AVAudioSession.sharedInstance()
        
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try recordingSession.setActive(true)
        } catch {
            print("オーディオセッションの設定に失敗しました: \(error)")
        }
    }
    
    func playRecording(_ recording: RecordingFile) {
        stopPlayback()
        
        do {
            try recordingSession.setCategory(.playback, mode: .default, options: [])
            try recordingSession.setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: recording.url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            let success = audioPlayer?.play() ?? false
            if success {
                currentPlayingId = recording.id
                isPlaying = true
                print("再生開始: \(recording.name)")
            } else {
                print("再生開始に失敗しました")
            }
        } catch {
            print("再生に失敗しました: \(error)")
            print("ファイルパス: \(recording.url)")
            print("ファイル存在確認: \(FileManager.default.fileExists(atPath: recording.url.path))")
        }
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentPlayingId = nil
        isPlaying = false
        print("再生を停止しました")
    }
    
    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.currentPlayingId = nil
            self.isPlaying = false
            print("再生が完了しました")
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.currentPlayingId = nil
            self.isPlaying = false
            print("再生エラー: \(error?.localizedDescription ?? "不明なエラー")")
        }
    }
}

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @State private var audioRecorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var recordingSession: AVAudioSession!
    @State private var recordings: [RecordingFile] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 録音セクション
                VStack(spacing: 20) {
                    Text("音声録音アプリ")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Image(systemName: isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 60))
                        .foregroundColor(isRecording ? .red : .blue)
                        .scaleEffect(isRecording ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isRecording)
                    
                    Button(action: {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    }) {
                        Text(isRecording ? "録音停止" : "録音開始")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 120, height: 40)
                            .background(isRecording ? Color.red : Color.blue)
                            .cornerRadius(20)
                    }
                    
                    if isRecording {
                        Text("録音中...")
                            .foregroundColor(.red)
                            .font(.headline)
                    }
                }
                .padding(.top)
                
                Divider()
                
                // 録音リストセクション
                VStack(alignment: .leading) {
                    HStack {
                        Text("録音一覧")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text("\(recordings.count)件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    if recordings.isEmpty {
                        VStack {
                            Image(systemName: "waveform")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("録音データがありません")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                    } else {
                        List {
                            ForEach(recordings) { recording in
                                RecordingRow(
                                    recording: recording,
                                    isPlaying: audioManager.currentPlayingId == recording.id,
                                    onTap: {
                                        if audioManager.currentPlayingId == recording.id {
                                            audioManager.stopPlayback()
                                        } else {
                                            audioManager.playRecording(recording)
                                        }
                                    }
                                )
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    deleteRecording(recordings[index])
                                }
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                }
                
                Spacer()
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .onAppear {
            setupRecordingSession()
            loadRecordings()
        }
    }
    
    func setupRecordingSession() {
        recordingSession = AVAudioSession.sharedInstance()
        
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try recordingSession.setActive(true)
            
            recordingSession.requestRecordPermission { allowed in
                DispatchQueue.main.async {
                    if !allowed {
                        print("マイクへのアクセス許可が拒否されました")
                    }
                }
            }
        } catch {
            print("録音セッションの設定に失敗しました: \(error)")
        }
    }
    
    func startRecording() {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording-\(Date().timeIntervalSince1970).m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            isRecording = true
            print("録音を開始しました: \(audioFilename.lastPathComponent)")
        } catch {
            print("録音の開始に失敗しました: \(error)")
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        print("録音を停止しました")
        loadRecordings()
    }
    
    func loadRecordings() {
        let documentsPath = getDocumentsDirectory()
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            
            let audioFiles = fileURLs.filter { $0.pathExtension == "m4a" }
            
            recordings = audioFiles.compactMap { url in
                guard let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey]),
                      let creationDate = resourceValues.creationDate else {
                    return nil
                }
                
                let duration = getAudioDuration(url: url)
                let name = url.lastPathComponent.replacingOccurrences(of: ".m4a", with: "")
                    .replacingOccurrences(of: "recording-", with: "録音-")
                
                return RecordingFile(url: url, name: name, date: creationDate, duration: duration)
            }.sorted { $0.date > $1.date }
            
        } catch {
            print("録音ファイルの読み込みに失敗しました: \(error)")
        }
    }
    
    func getAudioDuration(url: URL) -> TimeInterval {
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            return audioPlayer.duration
        } catch {
            return 0
        }
    }
    
    
    func deleteRecording(_ recording: RecordingFile) {
        // 削除対象が再生中の場合は停止
        if audioManager.currentPlayingId == recording.id {
            audioManager.stopPlayback()
        }
        
        do {
            try FileManager.default.removeItem(at: recording.url)
            loadRecordings()
            print("録音を削除しました: \(recording.name)")
        } catch {
            print("削除に失敗しました: \(error)")
        }
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}

struct RecordingRow: View {
    let recording: RecordingFile
    let isPlaying: Bool
    let onTap: () -> Void
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: recording.date)
    }
    
    private var formattedDuration: String {
        let minutes = Int(recording.duration) / 60
        let seconds = Int(recording.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 再生状態を示すアイコン
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.circle")
                .font(.title2)
                .foregroundColor(isPlaying ? .green : .blue)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

#Preview {
    ContentView()
}
