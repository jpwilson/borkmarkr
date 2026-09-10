import SwiftUI
import SwiftData

/// The links you've shared: every collection you made, whether its link is
/// on, off or run out, and the three things to do about one — copy it, turn
/// it off, delete it — plus how long it stays open.
///
/// Read from the server every time, never cached: a collection is a server
/// row, the web app edits the same rows, and a list that was right an hour
/// ago is the kind of wrong that makes someone re-send a dead link.
struct CollectionsList: View {
    var account: Account?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent

    @State private var rows: [CollectionShare.Owned] = []
    @State private var loaded = false
    @State private var busy = false
    @State private var message: String?
    @State private var confirmingDelete: CollectionShare.Owned?
    @State private var copiedID: String?
    @State private var showingAuth = false

    private var signedIn: Bool { account?.isSignedIn ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(18)
                .padding(.bottom, 24)
            }
            .background(Tokens.paper)
            .navigationTitle("Links you've shared")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await load() }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
        .task(id: signedIn) { await load() }
        .sheet(isPresented: $showingAuth) {
            if let account {
                AuthSheet(account: account, mode: .signIn)
                    .environment(\.accent, accent)
            }
        }
        .confirmationDialog(
            "Delete this link?",
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = confirmingDelete { Task { await delete(target) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The link stops working for good. Your borks stay in your library.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if !signedIn {
            explainer(
                symbol: "person.crop.circle",
                title: "Sign in to see the links you've shared",
                body: "Shared links are made from your backed-up borks, so they live with your account."
            )
            Button("Sign in") { showingAuth = true }
                .font(Typo.ui(15, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(accent.base, in: Capsule())
                .buttonStyle(PressableStyle())
        } else if let message {
            explainer(symbol: "wifi.exclamationmark", title: "Couldn't load your links", body: message)
            Button("Try again") { Task { await load() } }
                .font(Typo.ui(14, .bold))
                .foregroundStyle(accent.deep)
        } else if !loaded {
            HStack(spacing: 10) {
                ProgressView().tint(accent.base)
                Text("Loading…").font(Typo.ui(14)).foregroundStyle(Tokens.inkMeta)
            }
            .padding(.top, 8)
        } else if rows.isEmpty {
            explainer(
                symbol: "link",
                title: "Nothing shared yet",
                body: "Pick some borks in your Library with the tick button, or open a topic and choose “Share as a web page”. Each one becomes a link you can send to anyone."
            )
        } else {
            Text("\(rows.count) link\(rows.count == 1 ? "" : "s")")
                .font(Typo.ui(12, .heavy)).tracking(0.4)
                .foregroundStyle(Tokens.mutedHeading)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Tokens.divider.frame(height: 1).padding(.leading, 14)
                    }
                    self.row(row)
                }
            }
            .cardSurface(radius: Tokens.cardRadius)
            .opacity(busy ? 0.6 : 1)
            .disabled(busy)
        }
    }

    private func row(_ row: CollectionShare.Owned) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(row.isOpen() ? accent.deep : Tokens.inkFaint)
                .frame(width: 32, height: 32)
                .background(row.isOpen() ? accent.tint : Tokens.mutedControl,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(Typo.ui(14.5, .semibold))
                    .foregroundStyle(Tokens.ink)
                    .lineLimit(2)
                Text("\(Copy.countedBorks(row.count)) · \(row.statusLine())")
                    .font(Typo.ui(12, .medium))
                    .foregroundStyle(row.isOpen() ? Tokens.inkMeta : Tokens.inkFaint)
                    .lineLimit(2)
                if copiedID == row.id {
                    Text("Link copied")
                        .font(Typo.ui(11.5, .bold))
                        .foregroundStyle(accent.deep)
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 4)

            Menu {
                if row.isOpen(), let url = row.url {
                    Button {
                        UIPasteboard.general.string = url
                        Haptics.tap()
                        withAnimation(Motion.gentle) { copiedID = row.id }
                    } label: {
                        Label("Copy link", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: CollectionShare.message(
                        name: row.name, count: row.count, url: url, expiresAt: row.expiresAt
                    ), subject: Text(row.name)) {
                        Label("Share the link", systemImage: "square.and.arrow.up")
                    }
                }

                if row.isExpired() {
                    Menu("Open it again for…") { expiryChoices(row) }
                } else {
                    Button {
                        Task { await setLink(row, on: !row.isLinkOn) }
                    } label: {
                        Label(row.isLinkOn ? "Turn the link off" : "Turn the link on",
                              systemImage: row.isLinkOn ? "eye.slash" : "eye")
                    }
                    Menu("Link open for…") { expiryChoices(row) }
                }

                Button(role: .destructive) { confirmingDelete = row } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Tokens.inkSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(row.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func expiryChoices(_ row: CollectionShare.Owned) -> some View {
        ForEach(CollectionShare.Expiry.allCases) { choice in
            Button {
                Task { await setExpiry(row, to: choice) }
            } label: {
                if isCurrent(choice, for: row) {
                    Label(choice.label, systemImage: "checkmark")
                } else {
                    Text(choice.label)
                }
            }
        }
    }

    /// Whether a segment is the one the row carries, for the tick in the
    /// menu. Counted from the row's last change, so it is only exact for a
    /// link made or changed here or on the sheet; a date the web app set by
    /// hand matches none of the three, and none is ticked.
    private func isCurrent(_ choice: CollectionShare.Expiry, for row: CollectionShare.Owned) -> Bool {
        guard !row.isExpired() else { return false }
        guard let expiresAt = row.expiresAt else { return choice == .never }
        guard let updatedAt = row.updatedAt else { return false }
        let days = Int((expiresAt.timeIntervalSince(updatedAt) / 86_400).rounded())
        return choice.days == days
    }

    private func explainer(symbol: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(accent.base.opacity(0.8))
            Text(title)
                .font(Typo.display(18, .bold))
                .foregroundStyle(Tokens.ink)
            Text(body)
                .font(Typo.ui(13.5))
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: - Requests

    private func load() async {
        guard let account, signedIn else {
            rows = []
            loaded = false
            return
        }
        message = nil
        guard let session = await account.currentSession() else {
            message = "You're signed out. Sign in and try again."
            return
        }
        do {
            let data = try await Supabase.get(path: CollectionShare.listQuery, session: session)
            rows = try CollectionShare.owned(from: data)
            loaded = true
        } catch {
            message = error.localizedDescription
        }
    }

    private func setLink(_ row: CollectionShare.Owned, on: Bool) async {
        await patch(row, body: { try CollectionShare.Patch.visibility(on: on) },
                    failure: on ? "Couldn't turn the link on" : "Couldn't turn the link off")
    }

    private func setExpiry(_ row: CollectionShare.Owned, to expiry: CollectionShare.Expiry) async {
        await patch(row, body: { try CollectionShare.Patch.expiry(expiry) },
                    failure: "Couldn't change how long the link stays open")
    }

    private func delete(_ row: CollectionShare.Owned) async {
        await patch(row, body: { try CollectionShare.Patch.delete() }, failure: "Couldn't delete the link")
    }

    /// One change, then the list again from the server — what it shows is
    /// what the server has, not what this screen hoped it did.
    private func patch(_ row: CollectionShare.Owned, body: () throws -> Data, failure: String) async {
        guard let account, let session = await account.currentSession() else {
            message = "You're signed out. Sign in and try again."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let reply = try await Supabase.patch(
                path: "collections?id=eq.\(row.id)", bodyJSON: try body(), session: session
            )
            guard CollectionShare.rowsChanged(in: reply) > 0 else {
                throw Supabase.Failure.http(200, "the server didn't change it")
            }
            Haptics.tap()
            copiedID = nil
            await load()
        } catch {
            message = "\(failure): \(error.localizedDescription)"
        }
    }
}

// MARK: - The You tab's row

/// One row for the You tab that opens the list. Built here so the tab can
/// take it in one line; the tab itself is another PR's this round.
struct CollectionsEntry: View {
    var account: Account?
    @Environment(\.accent) private var accent
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent.deep)
                    .frame(width: 32, height: 32)
                    .background(accent.tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Links you've shared")
                        .font(Typo.ui(14, .semibold))
                        .foregroundStyle(Tokens.ink)
                    Text("Copy, turn off or delete any link you've made")
                        .font(Typo.ui(11.5, .medium))
                        .foregroundStyle(Tokens.inkMeta)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Tokens.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .cardSurface(radius: Tokens.cardRadius)
        .sheet(isPresented: $showing) {
            CollectionsList(account: account).environment(\.accent, accent)
        }
    }
}

// MARK: - A link someone sent you

/// What opens when a `bookmarker://c/<slug>` link is tapped: the collection
/// as the public page shows it, and one button to copy every bork in it
/// into your own library.
///
/// Reads through `collection_by_slug`, the one anonymous door, so it works
/// signed out — the same `null` the web page gets for a wrong slug, a link
/// that was turned off, a deleted collection and an expired one, and the
/// same one sentence for all four.
struct SharedCollectionSheet: View {
    let slug: String
    var account: Account?
    /// How many were added, once they have been — the caller shows the toast.
    var onSaved: (Int) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @State private var state = LoadState.loading
    @State private var saving = false
    @State private var saved: CollectionShare.Saved?
    @State private var message: String?
    @State private var showingAuth = false
    @State private var authMode = AuthSheet.Mode.signUp

    enum LoadState { case loading, found(CollectionShare.Shared), gone, failed(String) }

    private var signedIn: Bool { account?.isSignedIn ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch state {
                    case .loading: loading
                    case .found(let shared): found(shared)
                    case .gone: gone
                    case .failed(let why): failed(why)
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
            .navigationTitle("Shared with you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved == nil ? "Close" : "Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
        .task { await load() }
        .sheet(isPresented: $showingAuth) {
            if let account {
                AuthSheet(account: account, mode: authMode)
                    .environment(\.accent, accent)
            }
        }
        .onChange(of: showingAuth) { _, showing in
            guard !showing, signedIn, saved == nil else { return }
            Task { await save() }
        }
    }

    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView().tint(accent.base)
            Text("Opening the link…").font(Typo.ui(14)).foregroundStyle(Tokens.inkMeta)
        }
        .padding(.top, 8)
    }

    private func found(_ shared: CollectionShare.Shared) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(shared.name)
                    .font(Typo.display(24, .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(Copy.countedBorks(shared.items.count)) · from \(shared.ownerName)")
                    .font(Typo.ui(13, .medium))
                    .foregroundStyle(Tokens.inkMeta)
                if let note = shared.note {
                    Text(note)
                        .font(Typo.ui(14))
                        .foregroundStyle(Tokens.bodyOnWhite)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                if let expiresAt = shared.expiresAt {
                    Text(CollectionShare.openUntilLine(expiresAt: expiresAt))
                        .font(Typo.ui(12, .medium))
                        .foregroundStyle(Tokens.inkFaint)
                }
            }

            saveControls(shared)

            if !shared.items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(shared.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Tokens.divider.frame(height: 1).padding(.leading, 58)
                        }
                        itemRow(item)
                    }
                }
                .cardSurface(radius: Tokens.cardRadius)
            }

            Button {
                if let url = URL(string: CollectionShare.publicURL(slug: slug)) { openURL(url) }
            } label: {
                Label("Open on the web", systemImage: "safari")
                    .font(Typo.ui(13, .semibold))
                    .foregroundStyle(accent.deep)
            }
        }
    }

    @ViewBuilder
    private func saveControls(_ shared: CollectionShare.Shared) -> some View {
        if let saved {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(accent.base)
                Text(saved.line)
                    .font(Typo.ui(14, .semibold))
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .cardSurface(radius: 16)
        } else if signedIn {
            primaryButton(saving ? "Saving…" : "Save all \(shared.items.count) to my library",
                          enabled: !saving && !shared.items.isEmpty) {
                Task { await save() }
            }
            Text("Copies, filed under the same topics. Your notes stay yours; theirs stay theirs.")
                .font(Typo.ui(12.5))
                .foregroundStyle(Tokens.inkMeta)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Sign up (free) and these go straight into your library — backed up, filed, and searchable.")
                .font(Typo.ui(13))
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    authMode = .signUp
                    showingAuth = true
                } label: {
                    Text("Sign up and save these")
                        .font(Typo.ui(14.5, .bold))
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
                        .font(Typo.ui(14.5, .bold))
                        .foregroundStyle(accent.deep)
                        .padding(.horizontal, 18)
                        .frame(height: 50)
                        .background(accent.tint, in: Capsule())
                        .overlay(Capsule().stroke(accent.base.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func itemRow(_ item: CollectionShare.SharedItem) -> some View {
        let platform = Platform(rawValue: item.platform) ?? .web
        let pageURL = URL(string: item.url)
        return Button {
            if let pageURL { openURL(pageURL) }
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    CoverImage(url: item.imageURL.flatMap(URL.init(string:)), palette: NeutralPalette.value)
                    if item.imageURL == nil {
                        PlatformBadge(platform: platform, size: 22, pageURL: pageURL)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.isEmpty ? item.url : CollectionShare.displayTitle(item.title, platform: item.platform))
                        .font(Typo.ui(13.5, .semibold))
                        .foregroundStyle(Tokens.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        if item.imageURL != nil {
                            PlatformBadge(platform: platform, size: 14, pageURL: pageURL)
                        }
                        Text(item.author.flatMap { Platform.isSiteName($0) ? nil : $0 } ?? platform.name)
                            .font(Typo.ui(11, .medium))
                            .foregroundStyle(Tokens.inkMeta)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tokens.inkFaint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var gone: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Tokens.inkFaint)
            Text("This link has expired or was turned off.")
                .font(Typo.display(18, .bold))
                .foregroundStyle(Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Whoever sent it can share it again from their bookmarker.")
                .font(Typo.ui(13.5))
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private func failed(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Tokens.inkFaint)
            Text("Couldn't open this link")
                .font(Typo.display(18, .bold))
                .foregroundStyle(Tokens.ink)
            Text(why)
                .font(Typo.ui(13.5))
                .foregroundStyle(Tokens.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") { Task { await load() } }
                .font(Typo.ui(14, .bold))
                .foregroundStyle(accent.deep)
                .padding(.top, 4)
        }
        .padding(.top, 8)
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

    // MARK: - Requests

    private func load() async {
        state = .loading
        do {
            let body = try JSONSerialization.data(withJSONObject: ["p_slug": slug])
            // Anonymous on purpose, signed in or not: the door is the same one
            // the web page uses, and a session adds nothing to what it shows.
            let data = try await Supabase.rpc("collection_by_slug", bodyJSON: body, session: nil)
            if let shared = try CollectionShare.shared(from: data) {
                state = .found(shared)
            } else {
                state = .gone
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func save() async {
        guard let account, let session = await account.currentSession() else {
            authMode = .signUp
            showingAuth = true
            return
        }
        saving = true
        message = nil
        defer { saving = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["p_slug": slug])
            let data = try await Supabase.rpc("collection_save", bodyJSON: body, session: session)
            guard let result = try CollectionShare.saved(from: data) else {
                state = .gone
                return
            }
            // The copies are server rows now; the pull brings them down. Waited
            // on, not fired: a sync foreground started a moment ago would make
            // `sync` a no-op and the copies would land after the toast said
            // they had. A failed pull is not a failed save — the rows exist —
            // so its error is not shown; the next sync brings them.
            _ = await account.syncAndWait(context: context)
            Haptics.success()
            withAnimation(Motion.gentle) { saved = result }
            onSaved(result.added)
        } catch {
            message = "Couldn't save these: \(error.localizedDescription)"
        }
    }
}

#if DEBUG
/// Launch arguments for screenshots, in the pattern of `ScreenshotDefaults`.
/// Kept here rather than there this round because that file is another PR's;
/// fold them in the next time it is open.
///
///   -select 3      start the Library in select mode with the first three picked
///   -collect       …and open the share sheet over them
///   -collectNow    …and press "Make the link" the moment the sheet is up
///   -collections   open the list of links you've shared
///   -openCollection <slug>   behave as if bookmarker://c/<slug> had been tapped
///
/// `xcrun simctl openurl <udid> bookmarker://c/<slug>` exercises the real
/// path, but the OS asks "Open in bookmarker?" first and nothing can tap it,
/// so the last argument feeds the same handler from the launch instead.
enum CollectionsDebug {
    static var preselect: Int? {
        guard let index = CommandLine.arguments.firstIndex(of: "-select"),
              index + 1 < CommandLine.arguments.count else { return nil }
        return Int(CommandLine.arguments[index + 1])
    }

    static var openCollect: Bool { CommandLine.arguments.contains("-collect") }
    static var createNow: Bool { CommandLine.arguments.contains("-collectNow") }
    static var openList: Bool { CommandLine.arguments.contains("-collections") }

    static var incomingSlug: String? {
        guard let index = CommandLine.arguments.firstIndex(of: "-openCollection"),
              index + 1 < CommandLine.arguments.count,
              let url = URL(string: CollectionShare.appURL(slug: CommandLine.arguments[index + 1]))
        else { return nil }
        return CollectionShare.slug(from: url)
    }
}
#endif
