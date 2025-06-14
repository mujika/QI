//
//  ContentView.swift
//  QI
//
//  Created by 新村彰啓 on 6/10/25.
//

import SwiftUI
import AVFoundation
import CoreLocation
import PhotosUI

struct RecordingFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let date: Date
    let duration: TimeInterval
    let location: CLLocation?
    let locationName: String?
}

class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentPlayingId: UUID?
    @Published var isMonitoring = false
    @Published var inputLevel: Float = 0.0
    @Published var isRecording = false
    
    private var audioPlayer: AVAudioPlayer?
    private let recordingSession = AVAudioSession.sharedInstance()
    private var audioEngine: AVAudioEngine!
    private var inputNode: AVAudioInputNode!
    private var audioRecorder: AVAudioRecorder?
    
    override init() {
        super.init()
        setupAudioEngine()
        setupAudioSession()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
    }
    
    private func setupAudioSession() {
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try recordingSession.setActive(true)
            
            if recordingSession.preferredIOBufferDuration != 0.005 {
                try recordingSession.setPreferredIOBufferDuration(0.005)
            }
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
    
    func startMonitoring() {
        do {
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            audioEngine.reset()
            
            try recordingSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try recordingSession.setActive(true)
            
            let inputFormat = inputNode.outputFormat(forBus: 0)
            let outputFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
            
            print("Input format: \(inputFormat)")
            print("Output format: \(outputFormat)")
            
            if inputNode.numberOfInputs > 0 {
                // レベルメーター用のタップを設置
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
                    guard let self = self else { return }
                    
                    let channelData = buffer.floatChannelData?[0]
                    let frameLength = Int(buffer.frameLength)
                    guard frameLength > 0, let data = channelData else { return }
                    
                    var sum: Float = 0
                    for i in 0..<frameLength {
                        let sample = data[i]
                        sum += sample * sample
                    }
                    let rms = sqrt(sum / Float(frameLength))
                    
                    DispatchQueue.main.async {
                        self.inputLevel = min(rms * 10, 1.0)
                    }
                }
                
                // 入力を直接メインミキサーに接続（リアルタイム出力）
                audioEngine.connect(inputNode, to: audioEngine.mainMixerNode, format: inputFormat)
                
                try audioEngine.start()
                isMonitoring = true
                print("リアルタイムモニタリングを開始しました")
            } else {
                print("入力デバイスが見つかりません")
            }
            
        } catch {
            print("モニタリングの開始に失敗しました: \(error)")
            isMonitoring = false
        }
    }
    
    func stopMonitoring() {
        if audioEngine.isRunning && !isRecording {
            if inputNode.numberOfInputs > 0 {
                inputNode.removeTap(onBus: 0)
            }
            audioEngine.stop()
        }
        isMonitoring = false
        inputLevel = 0.0
        print("リアルタイムモニタリングを停止しました")
    }
    
    func startRecording(to url: URL) {
        do {
            // 録音中でもモニタリングを継続するため、AudioEngineを停止しない
            if !audioEngine.isRunning && isMonitoring {
                try startMonitoring()
            }
            
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
            print("録音を開始しました: \(url.lastPathComponent)")
            
        } catch {
            print("録音の開始に失敗しました: \(error)")
            isRecording = false
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        print("録音を停止しました")
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

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var locationName: String?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
    }
    
    func requestLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("位置情報のアクセスが許可されていません")
            return
        }
        locationManager.requestLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
        
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let error = error {
                print("位置情報の変換に失敗しました: \(error)")
                return
            }
            
            if let placemark = placemarks?.first {
                DispatchQueue.main.async {
                    self?.locationName = self?.formatLocationName(placemark)
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("位置情報の取得に失敗しました: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            requestLocation()
        }
    }
    
    private func formatLocationName(_ placemark: CLPlacemark) -> String {
        var components: [String] = []
        
        if let name = placemark.name {
            components.append(name)
        }
        if let locality = placemark.locality {
            components.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }
        
        return components.joined(separator: ", ")
    }
}

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var locationManager = LocationManager()
    @State private var recordingSession = AVAudioSession.sharedInstance()
    @State private var recordings: [RecordingFile] = []
    @State private var showingMonitorToggle = true
    @State private var showingRecordingAlert = false
    @State private var wallpaperImage: Image?
    @State private var wallpaperItem: PhotosPickerItem?
    
    var body: some View {
        NavigationView {
            ZStack {
                if let wallpaperImage = wallpaperImage {
                    wallpaperImage
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                }
                VStack(spacing: 20) {
                // 録音セクション
                VStack(spacing: 20) {
                    Text("ギター録音アプリ")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    // モニタリングコントロール
                    if showingMonitorToggle {
                        HStack {
                            Text("LINE入力モニタリング")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                if audioManager.isMonitoring {
                                    audioManager.stopMonitoring()
                                } else {
                                    audioManager.startMonitoring()
                                }
                            }) {
                                Text(audioManager.isMonitoring ? "停止" : "開始")
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 30)
                                    .background(audioManager.isMonitoring ? Color.red : Color.green)
                                    .cornerRadius(15)
                            }
                        }
                        .padding(.horizontal)
                        
                        // 入力レベルメーター
                        if audioManager.isMonitoring {
                            VStack {
                                Text("入力レベル")
                                    .font(.caption)
                                ProgressView(value: audioManager.inputLevel, total: 1.0)
                                    .progressViewStyle(LinearProgressViewStyle(tint: audioManager.inputLevel > 0.8 ? .red : .green))
                                    .frame(height: 10)
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    Image(systemName: audioManager.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 60))
                        .foregroundColor(audioManager.isRecording ? .red : .blue)
                        .scaleEffect(audioManager.isRecording ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: audioManager.isRecording)
                    
                    Button(action: {
                        if audioManager.isRecording {
                            audioManager.stopRecording()
                            loadRecordings()
                        } else {
                            locationManager.requestLocation()
                            let audioFilename = getDocumentsDirectory().appendingPathComponent("recording-\(Date().timeIntervalSince1970).m4a")
                            audioManager.startRecording(to: audioFilename)
                        }
                    }) {
                        Text(audioManager.isRecording ? "録音停止" : "録音開始")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 120, height: 40)
                            .background(audioManager.isRecording ? Color.red : Color.blue)
                            .cornerRadius(20)
                    }
                    
                    if audioManager.isRecording {
                        VStack {
                            Text("録音中...")
                                .foregroundColor(.red)
                                .font(.headline)
                            if let locationName = locationManager.locationName {
                                Text("場所: \(locationName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
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
                
                PhotosPicker(selection: $wallpaperItem, matching: .images, photoLibrary: .shared()) {
                    Text("壁紙を選択")
                        .foregroundColor(.blue)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(10)
                }
                .onChange(of: wallpaperItem) { newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            wallpaperImage = Image(uiImage: uiImage)
                        }
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
            locationManager.requestLocation()
        }
    }
    
    func setupRecordingSession() {
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try recordingSession.setActive(true)
            
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { allowed in
                    DispatchQueue.main.async {
                        if !allowed {
                            print("マイクへのアクセス許可が拒否されました")
                        }
                    }
                }
            } else {
                recordingSession.requestRecordPermission { allowed in
                    DispatchQueue.main.async {
                        if !allowed {
                            print("マイクへのアクセス許可が拒否されました")
                        }
                    }
                }
            }
        } catch {
            print("録音セッションの設定に失敗しました: \(error)")
        }
    }
    
    
    func loadRecordings() {
        let documentsPath = getDocumentsDirectory()
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsPath,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            let audioFiles = fileURLs.filter { $0.pathExtension == "m4a" }
            
            recordings = audioFiles.compactMap { url in
                guard
                    let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey]),
                    let creationDate = resourceValues.creationDate
                else { return nil }

                let duration = getAudioDuration(url: url)
                let name = url.lastPathComponent
                    .replacingOccurrences(of: ".m4a", with: "")
                    .replacingOccurrences(of: "recording-", with: "録音-")

                return RecordingFile(
                    url: url,
                    name: name,
                    date: creationDate,
                    duration: duration,
                    location: locationManager.location,
                    locationName: locationManager.locationName
                )
            }
            .sorted { $0.date > $1.date }
            
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()

    private var formattedDate: String {
        Self.dateFormatter.string(from: recording.date)
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
                
                if let locationName = recording.locationName {
                    HStack {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(locationName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
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
