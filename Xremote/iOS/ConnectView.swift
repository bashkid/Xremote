//
//  ConnectView.swift
//  Server discovery list + PIN entry sheet.
//

#if os(iOS)

import SwiftUI

struct ConnectView: View {
    @Bindable var browser: ServerBrowser
    @Bindable var client: XremoteClient

    @State private var pinEntry: String = ""
    @FocusState private var pinFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                NavBarGlowBackground()
                listContent
            }
            .navigationTitle("Xremote")
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ThemeToggleButton()
                }
            }
            .sheet(isPresented: pinSheetBinding) {
                pinSheet
            }
        }
        .onAppear { browser.start() }
    }

    private var listContent: some View {
        List {
            Section {
                if browser.servers.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Searching for Xremote Server on your network…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(browser.servers) { server in
                        Button {
                            Haptic.tap()
                            client.connect(to: server)
                        } label: {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(.blue)
                                Text(server.name)
                                Spacer()
                                if client.serverName == server.name {
                                    connectionBadge
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                        .font(.footnote)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableGlassStyle())
                    }
                }
            } header: {
                Text("Available servers")
            } footer: {
                Text("Make sure your Mac is running Xremote Server and is on the same Wi-Fi network.")
            }

            Section {
                Label("How to set up", systemImage: "info.circle")
                    .font(.subheadline)
                Text("1. Install Xremote Server on your Mac.\n2. Grant Accessibility permission when prompted.\n3. The Mac will appear here. Tap it and enter the 6-digit PIN shown in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)  // let the glow show through the List
    }

    @ViewBuilder
    private var connectionBadge: some View {
        switch client.state {
        case .connecting:
            ProgressView().controlSize(.small)
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
                .labelStyle(.iconOnly)
        case .awaitingPin:
            Image(systemName: "key.fill").foregroundStyle(.orange)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }

    private var pinSheetBinding: Binding<Bool> {
        Binding(
            get: { if case .awaitingPin = client.state { true } else { false } },
            set: { presenting in
                if !presenting, case .awaitingPin = client.state {
                    client.disconnect()
                }
            }
        )
    }

    private var pinSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            Text("Enter pairing PIN")
                .font(.title2.weight(.semibold))
            Text("Find the 6-digit PIN in the Xremote Server menu on \(client.serverName).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextField("000000", text: $pinEntry)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                .tracking(8)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .focused($pinFocused)
                .onChange(of: pinEntry) { _, newValue in
                    pinEntry = String(newValue.filter(\.isNumber).prefix(6))
                    if pinEntry.count == 6 {
                        client.submitPin(pinEntry)
                        pinEntry = ""
                    }
                }

            Button("Cancel") {
                client.disconnect()
                pinEntry = ""
            }
            .padding(.top)
            Spacer()
        }
        .padding(.top, 40)
        .padding()
        .presentationDetents([.medium])
        .onAppear { pinFocused = true }
    }
}

#endif
