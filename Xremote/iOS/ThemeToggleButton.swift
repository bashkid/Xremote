//
//  ThemeToggleButton.swift
//  Persisted light/dark toggle reused in both top bars.
//

#if os(iOS)

import SwiftUI

/// Tri-state theme preference: follow system, force light, force dark.
enum AppTheme: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light:  "sun.max.fill"
        case .dark:   "moon.fill"
        }
    }

    func next() -> AppTheme {
        switch self {
        case .system: .light
        case .light:  .dark
        case .dark:   .system
        }
    }
}

struct ThemeToggleButton: View {
    @AppStorage("XRAppTheme") private var stored: String = AppTheme.system.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: stored) ?? .system
    }

    var body: some View {
        Button {
            Haptic.soft()
            stored = theme.next().rawValue
        } label: {
            Image(systemName: theme.icon)
                .symbolRenderingMode(.hierarchical)
                .accessibilityLabel("Theme: \(theme.rawValue)")
        }
    }
}

#endif
