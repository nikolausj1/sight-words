import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Screen J — parent area (§6.12, near-clone of Math Tutor's ParentAreaView):
/// gear -> fullScreenCover; dimmed scrim; centered light card, two columns.
/// A year-of-birth gate wraps management/destructive actions; viewing the
/// dashboard stays open. Passing the gate once unlocks the rest of this
/// session's visit (judgment call: re-prompting per toggle would be
/// friction-heavy for a parent working through the word-lists/settings cards).
struct ParentAreaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]

    private var service: LearningService { LearningService(context: context) }
    private var active: Profile? { profiles.first(where: { $0.isActive }) }

    @State private var showGate = false
    @State private var pending: (() -> Void)?
    @State private var gateUnlocked = false

    @State private var showAddPlayer = false
    @State private var addName = ""
    @State private var addAvatar = AvatarCatalog.keys.randomElement()!
    @State private var addLevel = "K"

    @State private var renameTarget: Profile?
    @State private var renameText = ""
    @State private var deleteTarget: Profile?
    @State private var resetTarget: Profile?
    @State private var startOverTarget: Profile?

    @State private var newCustomWord = ""
    @State private var newCustomSentence = ""
    @State private var customWordMessage: String?
    @State private var showPasteSheet = false
    @State private var pasteText = ""
    @State private var pasteResultMessage: String?
    @State private var expandedCustomWordID: PersistentIdentifier?
    @State private var sentenceDrafts: [PersistentIdentifier: String] = [:]

    @State private var howOpen = false

    // Voice-check settings flow (§6.8): permission request happens right here,
    // never mid-session — see `VoiceCheckService.requestPermissions`.
    @State private var voiceCheckMicDenied = false
    private let voiceCheck = VoiceCheckService.shared

    private let levelOptions: [(label: String, code: String)] =
        [("Pre-K", "PreK"), ("K", "K"), ("1", "1"), ("2", "2"), ("3+", "3")]

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            card
                .frame(maxWidth: 1180, maxHeight: 850)
                .padding(.horizontal, 40)
                .padding(.vertical, 30)
            if showGate { gateOverlay.zIndex(5) }
        }
        .presentationBackground(.clear)
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-demoParent") || args.contains("-demoDashboard") {
                gateUnlocked = true
            }
            if args.contains("-demoDashboard"), let p = active {
                service.seedDashboardDemoData(for: p)
            }
        }
        .sheet(isPresented: $showAddPlayer) { addPlayerSheet }
        .sheet(isPresented: $showPasteSheet) { pasteSheet }
        .alert("Rename profile", isPresented: Binding(get: { renameTarget != nil },
                                                      set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { if let t = renameTarget { service.rename(t, to: renameText) }; renameTarget = nil }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .alert("Delete profile?", isPresented: Binding(get: { deleteTarget != nil },
                                                       set: { if !$0 { deleteTarget = nil } })) {
            Button("Delete", role: .destructive) { if let t = deleteTarget { service.delete(t) }; deleteTarget = nil }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { Text("This permanently removes the profile and all its progress.") }
        .alert("Reset progress?", isPresented: Binding(get: { resetTarget != nil },
                                                       set: { if !$0 { resetTarget = nil } })) {
            Button("Reset", role: .destructive) { if let t = resetTarget { service.resetProgress(t) }; resetTarget = nil }
            Button("Cancel", role: .cancel) { resetTarget = nil }
        } message: { Text("This returns the profile to brand-new. It cannot be undone.") }
        .alert("Start over?", isPresented: Binding(get: { startOverTarget != nil },
                                                   set: { if !$0 { startOverTarget = nil } })) {
            Button("Start over", role: .destructive) {
                let t = startOverTarget
                startOverTarget = nil
                performStartOver(t)
            }
            Button("Cancel", role: .cancel) { startOverTarget = nil }
        } message: { Text("Wipes progress AND name, avatar, and word lists — the app begins again with first-time setup. It cannot be undone.") }
    }

    /// Wipe identity + progress, tell the root to re-run onboarding, then close.
    private func performStartOver(_ profile: Profile?) {
        guard let profile else { return }
        service.startOver(profile)
        NotificationCenter.default.post(name: .startOverRequested, object: nil)
        dismiss()
    }

    private func gated(_ action: @escaping () -> Void) {
        if gateUnlocked { action(); return }
        pending = action
        showGate = true
    }

    private func sectionHeader(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Color.primary)
            Text(title.uppercased())
                .font(Theme.Font.label(13)).tracking(1.5)
                .foregroundStyle(Theme.Color.inkSoft)
        }
    }

    // MARK: The modal card — controls on the left, dashboard on the right

    private var card: some View {
        VStack(spacing: 0) {
            Text("Parent Area")
                .font(Theme.Font.display(30)).foregroundStyle(Theme.Color.ink)
                .padding(.top, 28).padding(.bottom, 24)
            HStack(alignment: .top, spacing: Theme.Metric.gap) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Metric.gap) {
                        profilesCard
                        wordListsCard
                        settingsCard
                        howItWorksCard
                    }
                    .padding(.bottom, Theme.Metric.pad)
                }
                .frame(width: 350)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Metric.gap) {
                        identityHeader
                        DashboardView(profile: active, service: service)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Theme.Metric.pad)
                }
            }
            .padding(.horizontal, Theme.Metric.pad)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.93, green: 0.95, blue: 0.98),
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
            .strokeBorder(.white.opacity(0.25), lineWidth: 1.5))
        .overlay(alignment: .topLeading) { ModalCloseButton { dismiss() }.padding(14) }
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
    }

    /// Who the dashboard is about: the active child's avatar, name, streak,
    /// and words-known capsule.
    private var identityHeader: some View {
        HStack(spacing: 14) {
            AvatarBadge(key: active?.avatarSymbol ?? AvatarCatalog.keys[0], size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(active?.name ?? "Reader")
                    .font(Theme.Font.display(26)).foregroundStyle(Theme.Color.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 12)
            statCapsule("flame.fill", "\(active?.streakDays ?? 0)-day streak",
                        Color(red: 0.93, green: 0.42, blue: 0.13))
            statCapsule("book.fill", "\(active.map { service.wordsKnownCount(for: $0) } ?? 0) words known",
                        Theme.Color.correct)
        }
        .padding(Theme.Metric.pad)
        .frame(maxWidth: 720)
        .cardSurface()
    }

    private func statCapsule(_ icon: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            Text(text).font(Theme.Font.label(14))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(tint.opacity(0.1), in: Capsule())
    }

    /// The year-of-birth gate as a small centered card over its own scrim.
    private var gateOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { showGate = false; pending = nil }
            ParentGateView(onPass: {
                showGate = false
                gateUnlocked = true
                pending?()
                pending = nil
            }, onCancel: { showGate = false; pending = nil })
                .background(Theme.Color.surface,
                            in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .compositingGroup()
                .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
        }
        .transition(.opacity)
    }

    // MARK: How progress works (parent explainer, ungated)

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { howOpen.toggle() }
            } label: {
                HStack {
                    sectionHeader("How it works", "questionmark.circle.fill")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Color.inkSoft)
                        .rotationEffect(.degrees(howOpen ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if howOpen { explainRows }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Metric.pad).cardSurface()
    }

    @ViewBuilder
    private var explainRows: some View {
        explainRow("sparkles",
                   "Every word starts New, then moves to Learning once it's been shown and scored at least once.")
        explainRow("hare.fill",
                   "A word read correctly and fast becomes Developing, then Fluent — and eventually Mastered once it's been read fast and correctly, first try, on 3 different days.")
        explainRow("arrow.uturn.backward",
                   "A missed word drops back to Learning and gets marked \"needs review,\" even if it was Mastered before — mastery has to hold up over time.")
        explainRow("chart.pie.fill",
                   "Each session mixes roughly 70% familiar words, 20% words still being learned, and 10% brand-new words (capped at 2 per session), so it never floods him.")
        explainRow("checkmark.seal.fill",
                   "Mastered means automatic recognition, not just \"got it once\" — that's why it takes several good days in a row, not one lucky session.")
        explainRow("arrow.clockwise",
                   "Deactivating a word list hides its words from sessions but keeps all the progress, so reactivating it later picks up right where you left off.")
    }

    private func explainRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.primary).frame(width: 22)
            Text(text).font(Theme.Font.label(13)).foregroundStyle(Theme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Profiles

    private var profilesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Players", "person.2.fill")
                Spacer()
                Button { gated { showAddPlayer = true } } label: { Label("Add", systemImage: "plus.circle.fill") }
                    .font(Theme.Font.label(14))
            }
            ForEach(profiles) { p in profileRow(p) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Metric.pad).cardSurface()
    }

    private func profileRow(_ p: Profile) -> some View {
        HStack(spacing: 10) {
            AvatarBadge(key: p.avatarSymbol, size: 32)
            Text(p.name).font(Theme.Font.label(16)).foregroundStyle(Theme.Color.ink)
                .lineLimit(1)
            if p.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.primary)
                    .accessibilityLabel("Active player")
            }
            Spacer()
            if !p.isActive {
                Button("Switch") { gated { service.switchTo(p) } }.font(Theme.Font.label(13)).buttonStyle(.bordered)
            }
            Menu {
                Button { gated { renameTarget = p; renameText = p.name } } label: { Label("Rename", systemImage: "pencil") }
                Button { gated { resetTarget = p } } label: { Label("Reset progress", systemImage: "arrow.counterclockwise") }
                Button { gated { startOverTarget = p } } label: { Label("Start over (redo onboarding)", systemImage: "arrow.uturn.backward") }
                if profiles.count > 1 {
                    Button(role: .destructive) { gated { deleteTarget = p } } label: { Label("Delete", systemImage: "trash") }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 22)).foregroundStyle(Theme.Color.inkSoft)
            }
        }
        .padding(.vertical, 4)
    }

    private var addPlayerSheet: some View {
        VStack(spacing: 20) {
            Text("New player").font(Theme.Font.display(24)).foregroundStyle(Theme.Color.ink)
            TextField("Name", text: $addName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .onChange(of: addName) { _, new in if new.count > 12 { addName = String(new.prefix(12)) } }
            AvatarCarousel(selected: $addAvatar, itemSize: 100)
            HStack(spacing: 10) {
                ForEach(levelOptions, id: \.code) { g in
                    Button(g.label) { addLevel = g.code }
                        .buttonStyle(.bordered)
                        .tint(addLevel == g.code ? Theme.Color.primary : Theme.Color.gentle)
                }
            }
            HStack(spacing: 14) {
                Button("Cancel") { showAddPlayer = false }.buttonStyle(.bordered)
                Button("Create") {
                    service.createProfile(name: addName.isEmpty ? "Player" : addName,
                                          avatar: addAvatar, level: addLevel)
                    addName = ""
                    showAddPlayer = false
                }
                .buttonStyle(.borderedProminent).tint(Theme.Color.correct)
            }
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 420)
    }

    // MARK: Word lists (gated)

    @ViewBuilder
    private var wordListsCard: some View {
        if gateUnlocked { wordListsCardOpen } else { lockedCard("Word lists", "book.closed.fill") }
    }

    private func lockedCard(_ title: String, _ icon: String) -> some View {
        Button { gated {} } label: {
            HStack {
                sectionHeader(title, icon)
                Spacer()
                Image(systemName: "lock.fill").foregroundStyle(Theme.Color.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Metric.pad)
        }
        .buttonStyle(.plain)
        .cardSurface()
    }

    private var wordListsCardOpen: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Word lists", "book.closed.fill")
            if let p = active {
                ForEach(LearningService.dolchListIDs, id: \.self) { listID in
                    let count = service.wordCount(listID: listID)
                    Toggle(isOn: Binding(
                        get: { p.activeListIDs.contains(listID) },
                        set: { on in
                            if on {
                                if !p.activeListIDs.contains(listID) { p.activeListIDs.append(listID) }
                            } else {
                                p.activeListIDs.removeAll { $0 == listID }
                            }
                            try? context.save()
                        })) {
                        Text("\(LearningService.listDisplayName(listID)) (\(count) words)")
                            .font(Theme.Font.label(14)).foregroundStyle(Theme.Color.ink)
                    }
                }
                Divider().padding(.vertical, 2)
                customListSection(profile: p)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Metric.pad).cardSurface()
        .tint(Theme.Color.primary)
    }

    private func customListSection(profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CUSTOM LIST").font(Theme.Font.label(12)).tracking(1.5).foregroundStyle(Theme.Color.inkSoft)
            HStack(spacing: 8) {
                TextField("Add a word", text: $newCustomWord)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { addOneCustomWord(profile: profile) }
                    .buttonStyle(.bordered)
                    .disabled(newCustomWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            TextField("Sentence (optional)", text: $newCustomSentence)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Font.label(13))
            if let msg = customWordMessage {
                Text(msg).font(Theme.Font.label(12)).foregroundStyle(Theme.Color.accent)
            }
            Button { showPasteSheet = true } label: {
                Label("Paste a list", systemImage: "doc.on.clipboard").font(Theme.Font.label(14))
            }
            .buttonStyle(.bordered)

            let customs = service.customWords()
            if !customs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(customs) { w in customWordRow(w) }
                }
                .padding(.top, 4)
            }
        }
    }

    private func addOneCustomWord(profile: Profile) {
        let sentence = newCustomSentence.trimmingCharacters(in: .whitespaces)
        let error = service.addCustomWord(text: newCustomWord, sentence: sentence.isEmpty ? nil : sentence,
                                          for: profile)
        switch error {
        case .duplicate(let listName):
            customWordMessage = "\"\(newCustomWord.trimmingCharacters(in: .whitespaces))\" is already in \(listName)."
        case .empty:
            customWordMessage = nil
        case nil:
            customWordMessage = nil
            newCustomWord = ""
            newCustomSentence = ""
        }
    }

    private func customWordRow(_ w: WordRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                let id = w.persistentModelID
                if expandedCustomWordID == id {
                    expandedCustomWordID = nil
                } else {
                    expandedCustomWordID = id
                    sentenceDrafts[id] = w.sentence ?? ""
                }
            } label: {
                HStack {
                    Text(w.text).font(Theme.Font.label(14)).foregroundStyle(Theme.Color.ink)
                    if w.sentence == nil {
                        Text("no sentence").font(Theme.Font.label(11)).foregroundStyle(Theme.Color.inkSoft)
                    }
                    Spacer()
                    Button {
                        service.deleteCustomWord(w)
                        expandedCustomWordID = nil
                    } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.Color.gentle)
                    }
                    .buttonStyle(.plain)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expandedCustomWordID == w.persistentModelID {
                HStack(spacing: 8) {
                    TextField("Sentence", text: Binding(
                        get: { sentenceDrafts[w.persistentModelID] ?? (w.sentence ?? "") },
                        set: { sentenceDrafts[w.persistentModelID] = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Font.label(13))
                    Button("Save") {
                        service.updateCustomWordSentence(w, sentence: sentenceDrafts[w.persistentModelID])
                        expandedCustomWordID = nil
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.leading, 4)
            }
        }
        .padding(.vertical, 2)
    }

    private var pasteSheet: some View {
        VStack(spacing: 16) {
            Text("Paste a list").font(Theme.Font.display(22)).foregroundStyle(Theme.Color.ink)
            Text("Separate words with commas, spaces, or new lines.")
                .font(Theme.Font.label(13)).foregroundStyle(Theme.Color.inkSoft)
            TextEditor(text: $pasteText)
                .font(Theme.Font.body())
                .frame(minHeight: 220)
                .padding(8)
                .background(Theme.Color.bg, in: RoundedRectangle(cornerRadius: 12))
            if let msg = pasteResultMessage {
                Text(msg).font(Theme.Font.label(13)).foregroundStyle(Theme.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                Button("Cancel") { showPasteSheet = false; pasteText = ""; pasteResultMessage = nil }
                    .buttonStyle(.bordered)
                Button("Add words") {
                    guard let p = active else { return }
                    let (added, rejected) = service.pasteWords(pasteText, for: p)
                    var parts: [String] = []
                    if added > 0 { parts.append("Added \(added) word\(added == 1 ? "" : "s").") }
                    if !rejected.isEmpty {
                        let names = rejected.prefix(4).map { "\($0.word) (already in \($0.listName))" }
                        parts.append("Skipped: \(names.joined(separator: ", "))" + (rejected.count > 4 ? ", …" : "."))
                    }
                    pasteResultMessage = parts.isEmpty ? "No words found." : parts.joined(separator: " ")
                    pasteText = ""
                }
                .buttonStyle(.borderedProminent).tint(Theme.Color.correct)
            }
        }
        .padding(28)
        .frame(minWidth: 460, minHeight: 460)
    }

    // MARK: Settings (gated)

    @ViewBuilder
    private var settingsCard: some View {
        if gateUnlocked { settingsCardOpen } else { lockedCard("Settings", "gearshape.fill") }
    }

    private var settingsCardOpen: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Settings", "gearshape.fill")
            if let a = active {
                Toggle("Sound effects", isOn: Binding(
                    get: { a.soundOn },
                    set: { a.soundOn = $0; Feedback.soundEnabled = $0; try? context.save() }))
                voiceCheckToggle(profile: a)
                Divider().padding(.vertical, 2)
                Text("Session length").font(Theme.Font.label(14)).foregroundStyle(Theme.Color.ink)
                Picker("Session length", selection: Binding(
                    get: { a.sessionSize },
                    set: { a.sessionSize = $0; try? context.save() })) {
                    Text("10").tag(10)
                    Text("12").tag(12)
                    Text("15").tag(15)
                }
                .pickerStyle(.segmented)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Metric.pad).cardSurface()
        .tint(Theme.Color.primary)
    }

    /// The voice-check toggle's extended flow (§6.8): permission requested
    /// right here on ON, snaps back off with a deep link on denial; disabled
    /// entirely (with a one-line reason) when the recognizer itself is
    /// unsupported on this device/locale — independent of permission status.
    @ViewBuilder
    private func voiceCheckToggle(profile: Profile) -> some View {
        let unsupported = !voiceCheck.recognizerSupported()
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Voice-check", isOn: Binding(
                get: { profile.voiceCheckOn },
                set: { newValue in
                    guard newValue else {
                        profile.voiceCheckOn = false
                        voiceCheckMicDenied = false
                        try? context.save()
                        return
                    }
                    voiceCheck.requestPermissions { granted in
                        if granted {
                            profile.voiceCheckOn = true
                            voiceCheckMicDenied = false
                            try? context.save()
                        } else {
                            // Snap back off — never left in a half-permitted state.
                            profile.voiceCheckOn = false
                            voiceCheckMicDenied = true
                            try? context.save()
                        }
                    }
                }))
                .disabled(unsupported)
            if unsupported {
                Text("Voice-check isn't available on this device.")
                    .font(Theme.Font.label(12)).foregroundStyle(Theme.Color.inkSoft)
            } else {
                Text("Listens while your child reads on their own.")
                    .font(Theme.Font.label(12)).foregroundStyle(Theme.Color.inkSoft)
                if voiceCheckMicDenied {
                    HStack(spacing: 10) {
                        Text("Microphone access is off — enable it in the Settings app.")
                            .font(Theme.Font.label(12)).foregroundStyle(Theme.Color.gentle)
                        Button("Open Settings") {
                            #if canImport(UIKit)
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                            #endif
                        }
                        .font(Theme.Font.label(12))
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

/// The parent gate: "enter your year of birth" — accepts any year implying an
/// adult (18–100 years old).
struct ParentGateView: View {
    let onPass: () -> Void
    let onCancel: () -> Void

    @State private var entry = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Parents only").font(Theme.Font.display(24)).foregroundStyle(Theme.Color.ink)
            Text("Please enter your year of birth").font(Theme.Font.body()).foregroundStyle(Theme.Color.inkSoft)
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    Text(i < entry.count ? String(Array(entry)[i]) : "")
                        .font(Theme.Font.number(30)).foregroundStyle(Theme.Color.ink)
                        .frame(width: 52, height: 62)
                        .background(Theme.Color.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(i == entry.count ? Theme.Color.primary : .clear, lineWidth: 2))
                }
            }
            if wrong { Text("Not quite — try again").font(Theme.Font.label()).foregroundStyle(Theme.Color.gentle) }
            NumberPadView(enterEnabled: entry.count == 4,
                          onDigit: { d in if entry.count < 4 { entry.append(String(d)) } },
                          onDelete: { _ = entry.popLast() },
                          onEnter: check,
                          keyTint: Theme.Color.primary)
            Button("Cancel", action: onCancel).font(Theme.Font.label()).padding(.top, 4)
        }
        .padding(Theme.Metric.pad)
        .frame(maxWidth: 460)
    }

    private func check() {
        let currentYear = Calendar.current.component(.year, from: .now)
        if let y = Int(entry), ((currentYear - 100)...(currentYear - 18)).contains(y) {
            onPass()
        } else {
            wrong = true; entry = ""
        }
    }
}
