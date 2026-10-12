import SwiftUI
import UIKit

/// The full-screen menu the pink button opens: a pink card on top (CocoScout,
/// who's signed in, Sign out, and the close X), then every My item as a tile
/// with its badge. The items come from the server (NativeAppHelper), so who
/// sees what matches the website.
final class MenuViewController: UIHostingController<MenuView> {
    enum Action {
        case open(MenuItem)
        case signOut
    }

    init(items: [MenuItem], person: MenuPerson?, onAction: @escaping (Action) -> Void) {
        super.init(rootView: MenuView(items: items, person: person, onAction: onAction))
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("Use init(items:person:onAction:)")
    }
}

struct MenuView: View {
    let items: [MenuItem]
    let person: MenuPerson?
    let onAction: (MenuViewController.Action) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let pink = Color(AppConfig.pink)
    /// pink-500 → pink-600, the gradient every CocoScout modal header uses.
    private let headerGradient = LinearGradient(colors: [Tailwind.pink500, Tailwind.pink600], startPoint: .leading, endPoint: .trailing)

    /// About you rather than everyday work: these sit in the pink card, as
    /// buttons under who's signed in, instead of among the tiles.
    private static let accountIDs: Set<String> = ["profile", "groups", "settings"]
    private var accountItems: [MenuItem] { items.filter { Self.accountIDs.contains($0.id) } }
    private var everydayItems: [MenuItem] { items.filter { !Self.accountIDs.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(everydayItems) { item in
                        Button { onAction(.open(item)) } label: { tile(item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: The pink card

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                Text("CocoScout")
                    .font(Font(AppConfig.coustard(26)))
                    .foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.white.opacity(0.2)))
                }
                .accessibilityLabel("Close")
            }

            if let person {
                HStack(spacing: 12) {
                    avatar(person)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Signed in as")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(person.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(person.email)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button("Sign out") { onAction(.signOut) }
                        .buttonStyle(SharedButtonStyle(variant: .secondary, size: .small))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.15)))
            }

            if !accountItems.isEmpty {
                HStack(spacing: 8) {
                    ForEach(accountItems) { item in
                        Button { onAction(.open(item)) } label: {
                            Label(item.title, systemImage: item.icon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SharedButtonStyle(variant: .secondary, size: .small))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(headerGradient)
    }

    private func avatar(_ person: MenuPerson) -> some View {
        let initials = Text(person.initials)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.25)))
        return Group {
            if let url = person.headshotURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initials
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                initials
            }
        }
    }

    // MARK: Tiles

    private func tile(_ item: MenuItem) -> some View {
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
