import SwiftUI
import SwiftData
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

    enum Stage { case pick, reviewing, importing, done }

    @State private var stage = Stage.pick
    @State private var picking = false
    @State private var outcome = Importer.Outcome()
    @State private var progress = 0.0
    @State private var imported = 0
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .pick: pickStage
                case .reviewing: reviewStage
                case .importing: importingStage
                case .done: doneStage
                }
            }
            .background(Tokens.paper)
            .navigationTitle("Import your saves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(stage == .done ? "Done" : "Cancel") {
                        if stage == .done { onDone(imported) }
                        dismiss()
                    }
                }
            }
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
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Tokens.sheetRadius)
    }

    // MARK: Pick

    private var pickStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You've already saved thousands of things.")
                        .font(Typo.display(21, .heavy))
                        .foregroundStyle(Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Every app has to give you your data. Download it, drop the file here, and it all becomes searchable at once.")
                        .font(Typo.ui(14))
                        .foregroundStyle(Tokens.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button { picking = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        Text("Choose a file").font(Typo.ui(15, .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
                    .shadow(color: accent.base.opacity(0.34), radius: 16, y: 8)
                }
                .buttonStyle(.plain)

                Text("WHERE TO GET IT")
                    .font(Typo.ui(10, .heavy)).tracking(0.6)
                    .foregroundStyle(Tokens.mutedHeading)
                    .padding(.top, 4)

                VStack(spacing: 9) {
                    ForEach(Importer.Format.allCases, id: \.self) { format in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(format.label)
                                .font(Typo.ui(13.5, .bold))
                                .foregroundStyle(Tokens.ink)
                            Text(format.howTo)
                                .font(Typo.ui(12))
                                .foregroundStyle(Tokens.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .cardSurface(radius: 16)
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
    }

    // MARK: Review

    private var reviewStage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Text("\(outcome.candidates.count)")
                            .font(Typo.display(38, .heavy))
                            .foregroundStyle(accent.base)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("links found")
                                .font(Typo.ui(14, .bold))
                                .foregroundStyle(Tokens.ink)
                            if let format = outcome.format {
                                Text(format.label)
                                    .font(Typo.ui(12, .medium))
                                    .foregroundStyle(Tokens.inkMeta)
                            }
                            if outcome.skipped > 0 {
                                Text("\(outcome.skipped) skipped (not links)")
                                    .font(Typo.ui(11.5))
                                    .foregroundStyle(Tokens.inkFaint)
                            }
                        }
                        Spacer()
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(radius: 18)

                    Text("A SAMPLE")
                        .font(Typo.ui(10, .heavy)).tracking(0.6)
                        .foregroundStyle(Tokens.mutedHeading)

                    ForEach(outcome.candidates.prefix(8)) { candidate in
                        HStack(spacing: 10) {
                            PlatformBadge(platform: Platform.detect(from: candidate.url), size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.title ?? candidate.url.host ?? "Link")
                                    .font(Typo.ui(13, .semibold))
                                    .foregroundStyle(Tokens.ink)
                                    .lineLimit(1)
                                Text(candidate.url.absoluteString)
                                    .font(Typo.mono(10.5))
                                    .foregroundStyle(Tokens.inkFaint)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(11)
                        .cardSurface(radius: 14)
                    }

                    if outcome.candidates.count > 8 {
                        Text("…and \(outcome.candidates.count - 8) more")
                            .font(Typo.ui(12.5, .medium))
                            .foregroundStyle(Tokens.inkMeta)
                    }
                }
                .padding(18)
            }

            Button(action: runImport) {
                Text("Import \(Copy.countedBorks(outcome.candidates.count))")
                    .font(Typo.ui(15.5, .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(accent.base, in: RoundedRectangle(cornerRadius: Tokens.buttonRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(outcome.candidates.isEmpty)
            .padding(18)
        }
    }

    // MARK: Importing / done

    private var importingStage: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .tint(accent.base)
                .padding(.horizontal, 40)
            Text("Filing \(Copy.countedBorks(outcome.candidates.count))…")
                .font(Typo.ui(14, .semibold))
                .foregroundStyle(Tokens.inkSecondary)
            Text("Titles and thumbnails fill in afterwards.")
                .font(Typo.ui(12))
                .foregroundStyle(Tokens.inkFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var doneStage: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(accent.base)
            Text("\(Copy.countedBorks(imported)) imported")
                .font(Typo.display(21, .heavy))
                .foregroundStyle(Tokens.ink)
            Text("They're sorted into topics already. Titles and thumbnails will keep filling in while you browse.")
                .font(Typo.ui(13.5))
                .foregroundStyle(Tokens.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)

            Button {
                onDone(imported)
                dismiss()
            } label: {
                Text("See them")
                    .font(Typo.ui(15, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 26)
                    .frame(height: 48)
                    .background(accent.base, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
