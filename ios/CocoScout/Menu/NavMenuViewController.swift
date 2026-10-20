import SwiftUI
import UIKit

/// The V1.1 menu (navigation canvas, app row), for generation-2 builds: a
/// plain outlined card for you on top, with the close button in its corner
/// and Profile, Settings and Sign out under it (not pink: pink bars are
/// things to do); in production mode the organization on soft pink; the
/// tiles; then Work the door (black) and the mode switch (CocoScout pink)
/// pinned to the bottom (Tim, 2026-10-20). Messages and Notifications aren't
/// tiles: they're icons in the nav bar.
final class NavMenuViewController: UIHostingController<NavMenuView> {
    init(nav: NavData, person: MenuPerson?, onOpen: @escaping (String) -> Void, onSignOut: @escaping () -> Void) {
        super.init(rootView: NavMenuView(nav: nav, person: person, onOpen: onOpen, onSignOut: onSignOut))
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("Use init(nav:person:onOpen:onSignOut:)")
    }
}

struct NavMenuView: View {
    let nav: NavData
    let person: MenuPerson?
    let onOpen: (String) -> Void
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss
    private let pink = Color(AppConfig.pink)

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: nav.isProduction ? 4 : 3)
    }

    var body: some View {
        VStack(spacing: 10) {
            personCard
            if let organization = nav.organization {
                Button { onOpen(organization.sheetPath) } label: { organizationRow(organization) }
                    .buttonStyle(.plain)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(nav.sections.enumerated()), id: \.offset) { _, section in
                        if let label = section.label {
                            Text(label.uppercased())
                                .font(.caption2.weight(.bold))
                                .kerning(0.8)
                                .foregroundStyle(Tailwind.gray500)
                                .padding(.top, 4)
                        }
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(section.items) { item in
                                Button { onOpen(item.path) } label: { tile(item) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            if let door = nav.door {
                Button { onOpen(door.path) } label: { doorBar(door) }
                    .buttonStyle(.plain)
            }
            if let modeSwitch = nav.modeSwitch {
                Button { onOpen(modeSwitch.path) } label: { switchBar(modeSwitch) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: You

    private var personCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let person { avatar(person) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(person?.name ?? "CocoScout")
                        .font(.headline)
                        .foregroundStyle(Tailwind.gray900)
                        .lineLimit(1)
                    if let email = person?.email {
                        Text(email)
                            .font(.footnote)
                            .foregroundStyle(Tailwind.gray500)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Tailwind.gray700)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color(.systemGray6)))
                }
                .accessibilityLabel("Close")
            }
            .padding(14)
            Divider()
            HStack(spacing: 0) {
                cardLink("Profile", systemImage: "person.crop.circle") { onOpen(nav.profilePath) }
                Divider().frame(height: 28)
                cardLink("Settings", systemImage: "gearshape") { onOpen(nav.settingsPath) }
                Divider().frame(height: 28)
                cardLink("Sign out", systemImage: "rectangle.portrait.and.arrow.right") { onSignOut() }
            }
            .frame(minHeight: 46)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tailwind.gray200))
    }

    private func cardLink(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Tailwind.gray900)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func avatar(_ person: MenuPerson) -> some View {
        let initials = Text(person.initials)
            .font(.headline)
            .foregroundStyle(Tailwind.pink700)
            .frame(width: 48, height: 48)
            .background(RoundedRectangle(cornerRadius: 10).fill(Tailwind.pink50))
        return Group {
            if let url = person.headshotURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { initials }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                initials
            }
        }
    }

    // MARK: Production mode

    private func organizationRow(_ organization: NavData.Organization) -> some View {
        HStack(spacing: 10) {
            Text(organization.initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Tailwind.pink600))
            Text(organization.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Tailwind.gray900)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Tailwind.pink700)
            Spacer(minLength: 8)
            Text("PRODUCTION MODE")
                .font(.system(size: 10, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(Tailwind.pink700)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 14).fill(Tailwind.pink50))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tailwind.pink200))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Production mode, \(organization.name). Change organization")
    }

    // MARK: Tiles

    private func tile(_ item: NavData.NavItem) -> some View {
        VStack(spacing: 6) {
            Image(systemName: item.icon)
                .font(.system(size: nav.isProduction ? 20 : 24, weight: .regular))
                .foregroundStyle(item.locked == true ? Tailwind.gray500 : pink)
                .frame(height: 26)
            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Tailwind.gray900)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 3)
        }
        .frame(maxWidth: .infinity, minHeight: nav.isProduction ? 66 : 80)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tailwind.gray200))
        .overlay(alignment: .topTrailing) {
            if item.locked == true {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Tailwind.gray500)
                    .padding(7)
            } else if let badge = AppShell.badgeText(item.badge ?? 0) {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(Tailwind.pink600))
                    .padding(5)
            }
        }
    }

    // MARK: The bars at the bottom

    /// Work the door: black.
    private func doorBar(_ item: NavData.NavItem) -> some View {
        bar(icon: "qrcode.viewfinder", title: item.title, subtitle: item.subtitle, fill: Tailwind.gray900)
    }

    /// Enter or Exit production mode: CocoScout pink with white words, never
    /// dark pink (Tim, 2026-10-20).
    private func switchBar(_ modeSwitch: NavData.ModeSwitch) -> some View {
        bar(icon: modeSwitch.enter ? "building.2" : "rectangle.portrait.and.arrow.right",
            title: modeSwitch.label, subtitle: modeSwitch.subtitle, fill: Tailwind.pink500)
    }

    private func bar(icon: String, title: String, subtitle: String?, fill: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 14).fill(fill))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
