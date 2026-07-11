import SwiftUI
import SwiftData

/// Screen I — kid profile overlay (§6.11): a simplified port of Math Tutor's
/// trophy room, same dark-card style over a scrim, but with no guardian
/// gallery and no XP — just the avatar, name, and two stat tiles.
///
/// Shown as an in-hierarchy overlay (NOT a fullScreenCover): a cover's hosting
/// layer ignores `ignoresSafeArea(.keyboard)` and shoves the card around when
/// the name field focuses. In the normal hierarchy the keyboard changes nothing.
struct KidProfileView: View {
    var onClose: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Profile> { $0.isActive }) private var activeProfiles: [Profile]

    @State private var editingName = false
    @State private var draftName = ""
    @State private var pickingAvatar = false
    @FocusState private var nameFocused: Bool

    private var profile: Profile? { activeProfiles.first }
    private var service: LearningService { LearningService(context: context) }
    private static let sheetBG = Color(red: 0.09, green: 0.10, blue: 0.14)

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
            card
                .frame(maxWidth: 640)
                .padding(.vertical, 26)
        }
        // The keyboard must not move the GUI — the name field is in the card's
        // top row and stays visible on its own.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-demoKidProfile") {
                // Nothing extra to seed — the overlay itself is the screenshot target.
            }
        }
    }

    private var card: some View {
        VStack(spacing: 22) {
            hero
            statTiles
        }
        .padding(Theme.Metric.pad)
        .overlay(alignment: .topLeading) { ModalCloseButton { onClose() }.padding(14) }
        .background(Self.sheetBG, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
            .strokeBorder(.white.opacity(0.12), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
        .overlay {
            if pickingAvatar { avatarPickerOverlay }
        }
    }

    // MARK: Hero — avatar + name

    private var hero: some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                Button {
                    pickingAvatar = true
                    Feedback.fire(.keyTap)
                } label: {
                    AvatarBadge(key: profile?.avatarSymbol ?? "avatar1", size: 96)
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white, Theme.Color.primary)
                                .background(Circle().fill(Self.sheetBG).frame(width: 22, height: 22))
                        }
                }
                .accessibilityLabel("Change avatar")

                if editingName {
                    TextField("", text: $draftName)
                        .font(Theme.Font.display(38)).foregroundStyle(.white)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(saveName)
                        .onChange(of: draftName) { _, new in
                            if new.count > 12 { draftName = String(new.prefix(12)) }
                        }
                        .frame(maxWidth: 300)
                        .padding(.vertical, 6).padding(.horizontal, 14)
                        .background(Color.white.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 14))
                } else {
                    HStack(spacing: 12) {
                        Text(profile?.name ?? "Reader")
                            .font(Theme.Font.display(38)).foregroundStyle(.white)
                        Button {
                            draftName = profile?.name ?? ""
                            editingName = true
                            nameFocused = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .font(Theme.Font.label(14))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(.white.opacity(0.15)))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
                        }
                        .accessibilityLabel("Change name")
                    }
                }
            }
        }
    }

    // MARK: Stat tiles — exactly two (§6.11): day streak, words I know.

    private var statTiles: some View {
        HStack(spacing: 14) {
            statTile {
                Image(systemName: "flame.fill").font(.system(size: 34))
                    .foregroundStyle(Theme.Color.accent)
            } value: {
                "\(profile?.streakDays ?? 0)"
            } label: {
                "day streak"
            }
            statTile {
                Image(systemName: "book.fill").font(.system(size: 32))
                    .foregroundStyle(Theme.Color.correct)
            } value: {
                "\(profile.map { service.wordsKnownCount(for: $0) } ?? 0)"
            } label: {
                "words I know"
            }
        }
    }

    private func statTile(@ViewBuilder icon: () -> some View,
                          value: () -> String, label: () -> String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                icon()
                Text(value()).font(Theme.Font.number(40)).foregroundStyle(.white)
            }
            Text(label()).font(Theme.Font.label(16)).foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 128)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
    }

    // MARK: Avatar picker overlay

    private var avatarPickerOverlay: some View {
        VStack(spacing: 14) {
            Text("Pick your reader")
                .font(Theme.Font.display(22)).foregroundStyle(.white)
            AvatarCarousel(selected: Binding(
                get: { profile?.avatarSymbol ?? "avatar1" },
                set: { new in
                    profile?.avatarSymbol = new
                    try? context.save()
                }), itemSize: 120)
            Button {
                pickingAvatar = false
            } label: {
                Text("Done")
                    .font(Theme.Font.display(18))
                    .padding(.horizontal, 34).padding(.vertical, 11)
            }
            .buttonStyle(ChunkyKeyStyle(base: Theme.Color.correct,
                                        deep: Theme.Color.correct.shaded(by: -0.35),
                                        corner: Theme.Metric.corner))
            .padding(.top, 16)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.sheetBG.opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func saveName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { profile?.name = String(trimmed.prefix(12)); try? context.save() }
        editingName = false
    }
}
