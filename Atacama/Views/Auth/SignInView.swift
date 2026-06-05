//
//  SignInView.swift
//  Atacama
//
//  Sign-in screen. Kicks off the OAuth web auth session via SessionManager.
//

import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mic.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Atacama")
                    .font(.largeTitle.bold())
                Text("Voice-first authoring for earlyversion.com")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                session.signIn()
            } label: {
                HStack {
                    if session.isSigningIn {
                        ProgressView()
                    }
                    Text(session.isSigningIn ? "Signing in…" : "Sign in")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isSigningIn)

            if let error = session.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }
}
