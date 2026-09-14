import SwiftUI
import SwiftData

/// Turn some borks into one link.
///
/// Three from Instagram, four from YouTube, one from X — picked in the
/// Library's select mode or handed over whole by a topic page — become
/// `bookmarker.lol/c/<slug>`: a page anyone can open, no account needed, with
/// a "Get bookmarker" button on it. The collection is a server row
/// (`collection_create`, migration 0012), which is why the sheet's job before
/// it can make the link is to get every bork *onto* the server: sign-in if
/// there is none, then a full sync, then the RPC. Each step says what it is
/// doing and, when it cannot, why — a link that silently came out empty would
/// be the worst outcome here, so nothing here is silent.
struct CollectSheet: View {
    /// What goes in. Any mix of sources — that is the point.
    let bookmarks: [Bookmark]
    /// "Fitness › Mobility" when this came from a topic page; `nil` from the
    /// Library, where the default name is a plain count.
    var presetName: String? = nil
    /// Passed through to the server as the collection's topic when it has one.
    var categoryID: String? = nil
    var account: Account?
    /// Called once, when a link has been made — the Library uses it to leave
    /// select mode.
    var onCreated: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context

    @State private var name: String
    @State private var note = ""
    @State private var expiry: CollectionShare.Expiry = .never
    /// The name the page prints. `nil` until the profile has been read;
    /// `""` when the profile has none and the sheet has to ask.
    @State private var displayName: String?
    @State private var displayNameDraft = ""
    @State private var stage = Stage.form
    /// What the sheet is doing right now, while it is doing it.
    @State private var progress = ""
    /// Why the last attempt did not work. A sentence, never a code.
    @State private var message: String?
    @State private var created: CollectionShare.Created?
    @State private var copied = false
    @State private var showingAuth = false
    @State private var authMode = AuthSheet.Mode.signUp
    @State private var showingList = false

    enum Stage { case form, working, done }

    /// The server's cap on one collection (`collection_items_cap`).
    static let itemLimit = 200

    init(bookmarks: [Bookmark], presetName: String? = nil, categoryID: String? = nil,
         account: Account? = nil, onCreated: @escaping () -> Void = {}) {
        self.bookmarks = bookmarks
        self.presetName = presetName
        self.categoryID = categoryID
        self.account = account
        self.onCreated = onCreated
        _name = State(initialValue: CollectionShare.defaultName(topic: presetName, count: bookmarks.count))
    }

    private var signedIn: Bool { account?.isSignedIn ?? false }
    /// Only a bork the server has can be in a collection. A waiting one is
    /// saved but deliberately never uploaded (`Account.push`) — signing in
    /// admits every one of them, so this only bites on the signed-out form.
    private var shareable: [Bookmark] { bookmarks.filter { !$0.isWaiting } }
    private var needsDisplayName: Bool { signedIn && displayName == "" }
    private var overLimit: Bool { bookmarks.count > Self.itemLimit }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch stage {
                    case .form: form
                    case .working: working
                    case .done: done
                    }
                    if let message {
                        Text(message)
                            .font(Typo.ui(12.5))
                            .foregroundStyle(Tokens.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(Tokens.paper)
            .navigationTitle(stage == .done ? "Your link is ready" : "Share as one link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(stage == .done ? "Done" : "Cancel") { dismiss() }
                        .disabled(stage == .working)
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
        .interactiveDismissDisabled(stage == .working)
        .task(id: signedIn) {
            await loadDisplayName()
            #if DEBUG
            // `-collectNow`: the form's one button, pressed by the launch
            // argument — the only way to run the whole create path in a
            // simulator without a finger. See `CollectionsDebug`.
            if CollectionsDebug.createNow, signedIn, stage == .form { await create() }
            #endif
        }
        .sheet(isPresented: $showingAuth) {
            if let account {
                AuthSheet(account: account, mode: authMode)
                    .environment(\.accent, accent)
            }
        }
        .sheet(isPresented: $showingList) {
            CollectionsList(account: account)
                .environment(\.accent, accent)
        }
        // Signing in happened inside the auth sheet. Once it is gone, carry on
        // from where the tap left off — the person asked for a link, not for
        // an account, and should not have to ask twice.
        .onChange(of: showingAuth) { _, showing in
            guard !showing, signedIn, stage == .form else { return }
            Task { await continueAfterSignIn() }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            whatGoesIn

            field("Name") {
                TextField("Name this link", text: $name)
                    .font(Typo.ui(16, .semibold))
                    .submitLabel(.done)
            }

            field("A line under the title", optional: true) {
                TextField("Why these, or who they're for", text: $note, axis: .vertical)
                    .font(Typo.ui(15))
                    .lineLimit(1...4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Link open for")
                    .font(Typo.ui(12, .heavy)).tracking(0.4)
                    .foregroundStyle(Tokens.mutedHeading)
                Picker("Link open for", selection: $expiry) {
                    ForEach(CollectionShare.Expiry.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                Text(expiry.explanation)
                    .font(Typo.ui(12.5))
                    .foregroundStyle(Tokens.inkMeta)
            }

            if needsDisplayName {
                field("Your name") {
                    TextField("How the page should say who shared it", text: $displayNameDraft)
                        .font(Typo.ui(16, .semibold))
                        .textContentType(.name)
                        .submitLabel(.done)
                }
                Text("The page prints “by \(CollectionShare.cleanDisplayName(displayNameDraft) ?? "you")”. Asked once; change it on the web any time.")
                    .font(Typo.ui(12.5))
                    .foregroundStyle(Tokens.inkMeta)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -8)
            }

            // What `collection_by_slug` serves: the bork's public face and the
            // post's own text — never `note_text`, which is yours.
            Text("Anyone with the link can see these \(Copy.countedBorks(shareable.count)) — titles, links, covers and the posts' own text. Never your notes. You can turn the link off any time.")
                .font(Typo.ui(12.5))
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            actions
        }
    }

    /// The count, and where it comes from. Mixed sources are the reason this
    /// exists, so say them.
    private var whatGoesIn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Copy.countedBorks(shareable.count))
                .font(Typo.display(22, .heavy))
                .tracking(-0.4)
                .foregroundStyle(Tokens.ink)
            if let line = sourcesLine {
                Text(line)
                    .font(Typo.ui(13, .medium))
                    .foregroundStyle(Tokens.inkMeta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if shareable.count < bookmarks.count {
                Text("\(bookmarks.count - shareable.count) of the ones you picked are still waiting for an account. Sign up and they'll be included.")
                    .font(Typo.ui(12.5))
                    .foregroundStyle(Tokens.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    /// "3 from Instagram, 4 from YouTube, 1 from X".
    private var sourcesLine: String? {
        let counts = Dictionary(grouping: shareable, by: \.platform).mapValues(\.count)
        let parts = Platform.ordered.compactMap { platform in
            counts[platform].map { "\($0) from \(platform.name)" }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var actions: some View {
        if overLimit {
            Text("A link holds at most \(Self.itemLimit) borks — you've picked \(bookmarks.count). Take some out and try again.")
                .font(Typo.ui(13, .semibold))
                .foregroundStyle(Tokens.destructive)
                .fixedSize(horizontal: false, vertical: true)
        } else if signedIn {
            primaryButton("Make the link", enabled: canCreate) { Task { await create() } }
        } else {
            // Plain words for what each button does. A link needs an account
            // because the page is served from the server, and the server can
            // only show borks it has.
            Text("A link needs a free account — the page is built from your backed-up borks, so they have to be backed up first.")
                .font(Typo.ui(13))
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    authMode = .signUp
                    showingAuth = true
                } label: {
                    Text("Sign up")
                        .font(Typo.ui(15, .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(accent.base, in: Capsule())
                }
                .buttonStyle(PressableStyle())

                Button {
                    authMode = .signIn
                    showingAuth = true
                } label: {
                    Text("Sign in")
                        .font(Typo.ui(15, .bold))
                        .foregroundStyle(accent.deep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(accent.tint, in: Capsule())
                        .overlay(Capsule().stroke(accent.base.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private var canCreate: Bool {
        !CollectionShare.cleanName(name).isEmpty
            && !shareable.isEmpty
            && (!needsDisplayName || CollectionShare.cleanDisplayName(displayNameDraft) != nil)
    }

    // MARK: - Working

    private var working: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProgressView().tint(accent.base)
                Text(progress)
                    .font(Typo.ui(15, .semibold))
                    .foregroundStyle(Tokens.ink)
            }
            Text("Every bork in a link has to be on the server first, so a first share can take a moment.")
                .font(Typo.ui(12.5))
                .foregroundStyle(Tokens.inkMeta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: - Done

    @ViewBuilder
    private var done: some View {
        if let created {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(Typo.display(22, .heavy))
                        .tracking(-0.4)
                        .foregroundStyle(Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(Copy.countedBorks(created.added)) on the page · \(CollectionShare.openUntilLine(expiresAt: created.expiresAt))")
                        .font(Typo.ui(13, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if created.added < shareable.count {
                    Text("\(shareable.count - created.added) of the \(shareable.count) you picked weren't on the server yet, so they're not on the page. Back up again from the You tab and make a new link to include them.")
                        .font(Typo.ui(12.5, .semibold))
                        .foregroundStyle(Tokens.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Text(created.url)
                        .font(Typo.mono(13))
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button {
                        UIPasteboard.general.string = created.url
                        Haptics.tap()
                        withAnimation(Motion.gentle) { copied = true }
                    } label: {
                        Text(copied ? "Copied" : "Copy")
                            .font(Typo.ui(13, .bold))
                            .foregroundStyle(copied ? Tokens.inkSecondary : accent.deep)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(copied ? Tokens.mutedControl : accent.tint, in: Capsule())
                    }
                    .buttonStyle(ChipStyle())
                    .accessibilityLabel(copied ? "Link copied" : "Copy link")
                }
                .padding(14)
                .cardSurface(radius: 16)

                ShareLink(item: shareMessage, subject: Text(name)) {
                    Label("Share the link", systemImage: "square.and.arrow.up")
                        .font(Typo.ui(15.5, .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                }
                .buttonStyle(PressableStyle())

                Button("See all the links you've shared") { showingList = true }
                    .font(Typo.ui(13.5, .semibold))
                    .foregroundStyle(accent.deep)
            }
        }
    }

    private var shareMessage: String {
        guard let created else { return "" }
        return CollectionShare.message(name: name, count: created.added,
                                       url: created.url, expiresAt: created.expiresAt)
    }

    // MARK: - Pieces

    private func field<Content: View>(_ label: String, optional: Bool = false,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(label.uppercased())
                    .font(Typo.ui(10, .heavy)).tracking(0.6)
                    .foregroundStyle(Tokens.mutedHeading)
                if optional {
                    Text("optional")
                        .font(Typo.ui(10, .medium))
                        .foregroundStyle(Tokens.inkFaint)
                }
            }
            content()
                .padding(14)
                .cardSurface(radius: 16)
        }
    }

    /// `enabled` is drawn, not just enforced: `PressableStyle` does not dim a
    /// disabled button on its own, and a full-colour button that ignores a
    /// tap reads as broken rather than as waiting for a field.
    private func primaryButton(_ title: String, enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typo.ui(15.5, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    // MARK: - The steps

    /// The name on the page, read once per sign-in. A failure leaves it
    /// unknown rather than blocking the link: "by Someone" is a cosmetic
    /// fallback the page already has, and a link is the point.
    private func loadDisplayName() async {
        guard let account, signedIn, let session = await account.currentSession() else {
            displayName = nil
            return
        }
        guard let data = try? await Supabase.get(
            path: CollectionShare.profileQuery(userID: session.userID), session: session
        ) else { return }
        displayName = CollectionShare.displayName(from: data) ?? ""
    }

    private func continueAfterSignIn() async {
        message = nil
        await loadDisplayName()
        if needsDisplayName {
            // One more thing to ask, and it is asked on the form rather than
            // in a second sheet. The button is right there under it.
            message = nil
            return
        }
        await create()
    }

    private func create() async {
        guard let account, signedIn else {
            authMode = .signUp
            showingAuth = true
            return
        }
        let cleanName = CollectionShare.cleanName(name)
        guard !cleanName.isEmpty else {
            message = "Give the link a name."
            return
        }
        name = cleanName
        message = nil
        stage = .working

        do {
            if needsDisplayName {
                guard let chosen = CollectionShare.cleanDisplayName(displayNameDraft) else {
                    throw Problem("Add your name — it's what the page says the borks are from.")
                }
                progress = "Saving your name…"
                try await saveDisplayName(chosen, account: account)
            }

            progress = "Backing up your borks first…"
            if let error = await account.syncAndWait(context: context) {
                throw Problem("Couldn't back up your borks first: \(error) A link is built from the backed-up copies, so try again in a moment.")
            }

            let ids = shareable.map(\.id)
            guard !ids.isEmpty else { throw Problem("None of these borks can go in a link yet.") }
            guard let session = await account.currentSession() else {
                throw Problem("You're signed out. Sign in and try again.")
            }

            progress = "Making the link…"
            let body = try CollectionShare.createBody(
                name: cleanName,
                note: CollectionShare.cleanNote(note),
                categoryID: categoryID,
                expiry: expiry,
                bookmarkIDs: ids
            )
            let reply = try await Supabase.rpc("collection_create", bodyJSON: body, session: session)
            created = try CollectionShare.created(from: reply)
            Haptics.success()
            withAnimation(Motion.gentle) { stage = .done }
            onCreated()
        } catch let problem as Problem {
            fail(problem.text)
        } catch {
            fail("Couldn't make the link: \(error.localizedDescription)")
        }
    }

    private func saveDisplayName(_ chosen: String, account: Account) async throws {
        guard let session = await account.currentSession() else {
            throw Problem("You're signed out. Sign in and try again.")
        }
        let reply = try await Supabase.patch(
            path: "profiles?id=eq.\(session.userID)",
            bodyJSON: try CollectionShare.displayNameBody(chosen),
            session: session
        )
        guard CollectionShare.rowsChanged(in: reply) > 0 else {
            throw Problem("Couldn't save your name — the server didn't take it. Try again, or set it on the web.")
        }
        displayName = chosen
    }

    private func fail(_ text: String) {
        message = text
        withAnimation(Motion.gentle) { stage = .form }
    }

    /// A sentence for the person, thrown from the step that knows it.
    private struct Problem: Error {
        let text: String
        init(_ text: String) { self.text = text }
    }
}

// MARK: - The Library's selection bar

/// What select mode puts at the bottom of the Library: how many are picked,
/// the one thing to do with them, and the way out.
struct SelectionBar: View {
    let count: Int
    let onShare: () -> Void
    let onCancel: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 6) {
        if count == 0 {
            Text("Tap borks to pick them")
                .font(Typo.ui(12.5, .medium))
                .foregroundStyle(Tokens.inkMeta)
        }
        HStack(spacing: 12) {
            Button("Cancel", action: onCancel)
                .font(Typo.ui(14, .semibold))
                .foregroundStyle(Tokens.inkSecondary)
                .frame(minHeight: 44)

            Spacer(minLength: 0)

            Button(action: onShare) {
                Text(count == 0 ? "Share link" : "Share link (\(count))")
                    .font(Typo.ui(14, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(count == 0 ? Tokens.inkFaint : accent.base, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(count == 0)
        }
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Tokens.dockRadius, style: .continuous)
                .fill(Tokens.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.dockRadius, style: .continuous)
                        .stroke(Tokens.hairline, lineWidth: 1)
                )
                .shadow(color: Color(hex: "191510").opacity(0.18), radius: 18, y: 10)
        )
        .padding(.horizontal, 14)
    }
}

// MARK: - The account, for screens RootView does not build

/// The signed-in state for a screen that is pushed rather than composed by
/// `RootView` — the topic page arrives through Browse's navigation stack and
/// has no `account` of its own. `nil` where nothing injected one, which the
/// sheet treats as signed out.
private struct AccountKey: EnvironmentKey {
    static var defaultValue: Account? { nil }
}

extension EnvironmentValues {
    var account: Account? {
        get { self[AccountKey.self] }
        set { self[AccountKey.self] = newValue }
    }
}
