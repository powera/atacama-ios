//
//  MicButton.swift
//  Atacama
//
//  Big round push-to-dictate button. Reflects recording state.
//

import SwiftUI

struct MicButton: View {
    let isRecording: Bool
    /// Diameter of the button. Shrinks on vertically-constrained layouts.
    var size: CGFloat = 80
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.accentColor)
                    .frame(width: size, height: size)
                    .shadow(radius: isRecording ? 8 : 2)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel(isRecording ? "Stop dictation" : "Start dictation")
    }
}
