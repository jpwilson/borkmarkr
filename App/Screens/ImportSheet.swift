import SwiftUI
import SwiftData
import StoreKit
import UniformTypeIdentifiers

/// Turn an export file into a library.
///
/// The flow is deliberately: pick file → **review what we found** → import.
/// Never import silently. Dropping 1,400 items into someone's library without
/// showing them first is the kind of thing that makes people delete an app.
struct ImportSheet: View {
    let onDone: (Int) -> Void

    @Environment(\.accent) private var accent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    enum Stage { case pick, reviewing, importing, done }

    @State private var stage = Stage.pick
    @State private var picking = false
    @State private var outcome = Importer.Outcome()
    @State private var progress = 0.0
    @State private var imported = 0
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            ClaySheetHeader(title: "Import your saves") {
                if stage == .done { onDone(imported) }
                dismiss()
            }
            .padding(.horizontal, Tokens.gutter)
            Group {
                switch stage {
                case .pick: pickStage
                case .reviewing: reviewStage
                case .importing: importingStage
                case .done: doneStage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Tokens.paper)
        .fileImporter(
            isPresented: $picking,
            allowedContentTypes: [.json, .html, .commaSeparatedText, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            handle(result)
        }
        .alert("Couldn't read that file", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .presentationDetents([.large])
        .claySheet()
    }

    // MARK: Pick

    private var pickStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("You've already saved thousands of things.")
                            .textRole(.sectionTitle, color: Tokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Every app has to give you your data. Download it, drop the file here, and it all becomes searchable at once.")
                            .textRole(.body, color: Tokens.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ClayArtImage(source: .quest(.scroll))
                        .frame(width: 72, height: 72)
                        .background(Tokens.clayGround)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button { picking = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder").font(.system(size: 15, weight: .semibold))
                        Text("Choose a file")
                    }
                }
                .buttonStyle(.clayPrimary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Where to get it")
                        .textRole(.label, color: Tokens.inkSecondary)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(Importer.Format.allCases.enumerated()), id: \.element) { index, format in
                            if index > 0 { Tokens.hairline.frame(height: 1).padding(.leading, 16) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(format.label)
                                    .textRole(.cardTitle, color: Tokens.ink)
                                Text(format.howTo)
                                    .textRole(.meta)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .cardSurface()
                }
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    // MARK: Review

    private var reviewStage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(outcome.candidates.count)")
                            .font(.custom("Bricolage Grotesque", size: 40, relativeTo: .largeTitle).weight(.bold))
                            .foregroundStyle(accent.deep)
                            .monospacedDigit()
                        VStack(alignment: .leading, spacing: 1) {
                            Text("links found")
                                .textRole(.cardTitle, color: Tokens.ink)
                            if let format = outcome.format {
                                Text(format.label).textRole(.meta)
                            }
                            if outcome.skipped > 0 {
                                Text("\(outcome.skipped) skipped (not links)").textRole(.meta)
                            }
                        }
                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()

                    Text("A sample")
                        .textRole(.label, color: Tokens.inkSecondary)
                        .padding(.leading, 4)
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(outcome.candidates.prefix(8).enumerated()), id: \.element.id) { index, candidate in
                            if index > 0 { Tokens.hairline.frame(height: 1).padding(.leading, 54) }
                            HStack(spacing: 12) {
                                PlatformBadge(platform: Platform.detect(from: candidate.url), size: 26, pageURL: candidate.url)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(candidate.title ?? candidate.url.host ?? "Link")
                                        .textRole(.cardTitle, color: Tokens.ink)
                                        .lineLimit(1)
                                    Text(candidate.url.absoluteString)
                                        .textRole(.meta)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
                    .cardSurface()

                    if outcome.candidates.count > 8 {
                        Text("…and \(outcome.candidates.count - 8) more")
                            .textRole(.meta)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }

            Button("Import \(Copy.countedBorks(outcome.candidates.count))", action: runImport)
                .buttonStyle(.clayPrimary)
                .disabled(outcome.candidates.isEmpty)
                .padding(.horizontal, Tokens.gutter)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Tokens.paper)
                .overlay(alignment: .top) { Tokens.hairline.frame(height: 1) }
        }
    }

    // MARK: Importing / done

    private var importingStage: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView(value: progress)
                .tint(accent.base)
                .padding(.horizontal, 40)
            Text("Filing \(Copy.countedBorks(outcome.candidates.count))…")
                .textRole(.cardTitle, color: Tokens.ink)
            Text("Titles and thumbnails fill in afterwards.")
                .textRole(.meta)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var doneStage: some View {
        VStack(spacing: 12) {
            Spacer()
            ClayArtImage(source: .quest(.scroll))
                .frame(width: 132, height: 132)
                .background(Tokens.clayGround)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            Text("\(Copy.countedBorks(imported)) imported")
                .textRole(.screenTitle, color: Tokens.ink)
                .padding(.top, 8)
            Text("They're sorted into topics already. Titles and thumbnails will keep filling in while you browse.")
                .textRole(.body, color: Tokens.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("See them") {
                onDone(imported)
                dismiss()
            }
            .buttonStyle(.clayPrimary)
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { ReviewPrompter.reached(.importFinished(count: imported), requestReview) }
    }

    // MARK: Actions

    private func handle(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let failure):
            error = failure.localizedDescription
        case .success(let urls):
            guard let file = urls.first else { return }
            // Files from the document picker live outside our sandbox.
            let scoped = file.startAccessingSecurityScopedResource()
            defer { if scoped { file.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: file) else {
                error = "Couldn't open that file."
                return
            }

            var parsed = Importer.parse(data: data, filename: file.lastPathComponent)
            parsed.candidates = Importer.dedupe(parsed.candidates)

            guard !parsed.candidates.isEmpty else {
                error = "No links in that file. If it's a zip, unzip it first and pick the .json or .html inside."
                return
            }

            outcome = parsed
            withAnimation(.easeOut(duration: 0.2)) { stage = .reviewing }
        }
    }

    private func runImport() {
        stage = .importing
        Task { @MainActor in
            let total = max(1, outcome.candidates.count)
            var count = 0

            for (index, candidate) in outcome.candidates.enumerated() {
                let platform = Platform.detect(from: candidate.url)
                let title = candidate.title ?? Categorizer.fallbackTitle(for: candidate.url)
                let suggestion = Categorizer.suggest(url: candidate.url, title: title, text: candidate.text)

                let draft = BookmarkDraft(
                    url: candidate.url,
                    title: title,
                    author: candidate.author ?? Categorizer.fallbackAuthor(for: candidate.url),
                    platform: platform,
                    kind: platform.defaultKind,
                    categoryID: suggestion.categoryID,
                    subcategory: suggestion.subcategory,
                    tags: suggestion.tags,
                    text: candidate.text
                )

                if let saved = try? Store.save(draft, in: context) {
                    // Preserve when it was originally saved, so an imported
                    // library has real history instead of everything landing
                    // "Today" and destroying the ordering.
                    if let originalDate = candidate.savedAt {
                        saved.savedAt = originalDate
                    }
                    count += 1
                }

                // Yield periodically so the progress bar actually moves and the
                // UI stays responsive on a few thousand items.
                if index % 25 == 0 {
                    progress = Double(index) / Double(total)
                    await Task.yield()
                }
            }

            try? context.save()
            imported = count
            progress = 1
            withAnimation(.easeOut(duration: 0.25)) { stage = .done }
        }
    }
}
