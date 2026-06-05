//
//  MicButton.swift
//  Atacama
//
//  Big round push-to-dictate button. Reflects recording state.
//

import SwiftUI

struct MicButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: 80, height: 80)
                    .shadow(radius: isRecording ? 8 : 2)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel(isRecording ? "Stop dictation" : "Start dictation")
    }
}
