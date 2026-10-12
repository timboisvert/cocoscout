import SwiftUI
import UIKit

/// The full-screen menu (one-button and mix styles): every My item as a tile,
/// with badges, then Sign out. The items come from the server
/// (NativeAppHelper#native_menu), so who sees what matches the website.
final class MenuViewController: UIHostingController<MenuView> {
    enum Action {
        case open(TabSpec)
        case signOut
        case style(NavStyle)
    }

    init(items: [TabSpec], style: NavStyle, onAction: @escaping (Action) -> Void) {
        super.init(rootView: MenuView(items: items, style: style, onAction: onAction))
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("Use init(items:style:onAction:)")
    }
}

struct MenuView: View {
    let items: [TabSpec]
    @State var style: NavStyle
    let onAction: (MenuViewController.Action) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let pink = Color(AppConfig.pink)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items) { item in
                        Button { onAction(.open(item)) } label: { tile(item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)

                Button { onAction(.signOut) } label: {
                    Text("Sign out")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                #if DEBUG
                VStack(alignment: .leading, spacing: 8) {
                    Text("Navigation (trying out)").font(.footnote).foregroundStyle(.secondary)
                    Picker("Navigation", selection: $style) {
                        ForEach(NavStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: style) { _, newStyle in onAction(.style(newStyle)) }
                }
                .padding(16)
                #endif
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("CocoScout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .tint(pink)
    }

    private func tile(_ item: TabSpec) -> some View {
        VStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(pink)
                .frame(height: 30)
            Text(item.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 92)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator).opacity(0.6)))
        .overlay(alignment: .topTrailing) {
            if let badge = AppShell.badgeText(item.badge ?? 0) {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(Color.red))
                    .padding(6)
            }
        }
    }
}
