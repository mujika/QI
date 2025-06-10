//
//  ContentView.swift
//  QI
//
//  Created by 新村彰啓 on 6/10/25.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var audioRecorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var recordingSession: AVAudioSession!
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    var body: some View {
        VStack(spacing: 30) {
            Text("音声録音アプリ")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .font(.system(size: 80))
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
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 150, height: 50)
                    .background(isRecording ? Color.red : Color.blue)
                    .cornerRadius(25)
            }
            
            if isRecording {
                Text("録音中...")
                    .foregroundColor(.red)
                    .font(.headline)
            }
        }
        .padding()
        .onAppear {
            setupRecordingSession()
        }
        .alert("メッセージ", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    func setupRecordingSession() {
        recordingSession = AVAudioSession.sharedInstance()
        
        do {
            try recordingSession.setCategory(.playAndRecord, mode: .default)
            try recordingSession.setActive(true)
            
            recordingSession.requestRecordPermission { allowed in
                DispatchQueue.main.async {
                    if !allowed {
                        self.alertMessage = "マイクへのアクセス許可が必要です"
                        self.showAlert = true
                    }
                }
            }
        } catch {
            alertMessage = "録音セッションの設定に失敗しました"
            showAlert = true
        }
    }
    
    func startRecording() {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording-\(Date().timeIntervalSince1970).m4a")
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            isRecording = true
            alertMessage = "録音を開始しました"
            showAlert = true
        } catch {
            alertMessage = "録音の開始に失敗しました"
            showAlert = true
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        alertMessage = "録音を停止しました"
        showAlert = true
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}

#Preview {
    ContentView()
}
