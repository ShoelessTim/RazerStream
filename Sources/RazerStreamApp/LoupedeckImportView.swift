import SwiftUI

// The import flow: pick one of the Loupedeck profiles found on this Mac,
// see exactly what will come across and what will not, then commit.
//
// The review step exists because the translation is honestly lossy: actions
// that belonged to a Loupedeck plugin (Twitch, Spotify, OBS) have no
// equivalent here. Rather than dropping those tiles or guessing at a
// replacement, they arrive labelled but unbound, and are listed here so the
// user knows what to reassign before anything touches their profiles.

struct LoupedeckImportView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var deviceManager: DeviceManager
    @Environment(\.dismiss) private var dismiss

    /// Where the imported pages should land. Appending is the default: most
    /// people are migrating onto a deck they have already set up, and adding
    /// pages leaves everything they have built alone.
    private enum Destination: Hashable {
        case appendToCurrent
        case newProfile
    }

    @State private var found: [LoupedeckImport.Discovered] = []
    @State private var selection: LoupedeckImport.Discovered?
    @State private var result: LoupedeckImport.ImportResult?
    @State private var loadError: String?
    @State private var destination: Destination = .appendToCurrent

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if found.isEmpty {
                empty
            } else {
                HSplitView {
                    sourceList
                        .frame(minWidth: 210, idealWidth: 240, maxWidth: 300)
                    detail
                        .frame(minWidth: 380)
                }
            }

            Divider()
            footer
        }
        .frame(width: 720, height: 520)
        .onAppear(perform: reload)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import from Loupedeck").font(.headline)
                Text("Brings over pages, tile labels, and everything with an equivalent here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("No Loupedeck profiles found").font(.headline)
            Text("RazerStream looks in Application Support for profiles saved by the Loupedeck software for this device.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Source list

    private var sourceList: some View {
        List(found, selection: Binding(
            get: { selection },
            set: { newValue in selection = newValue; rebuild() }
        )) { item in
            VStack(alignment: .leading, spacing: 2) {
                Text(item.appName).font(.body)
                Text(item.profileName).font(.caption).foregroundStyle(.secondary)
            }
            .tag(item)
            .contentShape(Rectangle())
            .onTapGesture { selection = item; rebuild() }
        }
        .listStyle(.sidebar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let loadError {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text("Could not read that profile").font(.headline)
                Text(loadError).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let result {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary(result)
                    if result.review.isEmpty {
                        Label("Everything translated; nothing needs your attention.",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    } else {
                        reviewList(result)
                    }
                }
                .padding(12)
            }
        } else {
            VStack {
                Spacer()
                Text("Select a profile to see what will be imported.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func summary(_ r: LoupedeckImport.ImportResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(r.profile.pages.count) page\(r.profile.pages.count == 1 ? "" : "s") to import")
                .font(.headline)
            HStack(spacing: 14) {
                tally("\(r.mappedCount)", "ready", .green)
                if r.approximateCount > 0 { tally("\(r.approximateCount)", "check these", .orange) }
                if r.unmappedCount > 0 { tally("\(r.unmappedCount)", "need reassigning", .secondary) }
            }
            Text(r.profile.pages.map(\.name).joined(separator: "  ·  "))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tally(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.title3).bold().foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func reviewList(_ r: LoupedeckImport.ImportResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Needs your attention").font(.subheadline).bold()
            Text("These come across with their labels so you can see what they were; assign the actions afterwards.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(groupedReview(r), id: \.0) { pageName, items in
                VStack(alignment: .leading, spacing: 4) {
                    Text(pageName).font(.caption).bold().foregroundStyle(.secondary)
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.isApproximate ? "exclamationmark.circle" : "circle.dashed")
                                .foregroundStyle(item.isApproximate ? .orange : .secondary)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(item.label)  ·  \(item.location)").font(.callout)
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func groupedReview(_ r: LoupedeckImport.ImportResult) -> [(String, [LoupedeckImport.ReviewItem])] {
        var order: [String] = []
        var byPage: [String: [LoupedeckImport.ReviewItem]] = [:]
        for item in r.review {
            if byPage[item.pageName] == nil { order.append(item.pageName) }
            byPage[item.pageName, default: []].append(item)
        }
        return order.map { ($0, byPage[$0] ?? []) }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if result != nil {
                Picker("", selection: $destination) {
                    Text("Add to \"\(store.activeProfile.name)\"").tag(Destination.appendToCurrent)
                    Text("Create a new profile").tag(Destination.newProfile)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack {
                Text(destinationExplanation)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button(destination == .appendToCurrent ? "Add Pages" : "Import") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(result == nil)
            }
        }
        .padding(12)
    }

    private var destinationExplanation: String {
        guard let result else { return "" }
        let n = result.profile.pages.count
        let pages = "\(n) page\(n == 1 ? "" : "s")"
        switch destination {
        case .appendToCurrent:
            return "Adds \(pages) after your existing ones; nothing you have now is changed."
        case .newProfile:
            return "Creates a separate profile with \(pages); your current profile is untouched."
        }
    }

    // MARK: Actions

    private func reload() {
        found = LoupedeckImport.scan()
        if selection == nil { selection = found.first }
        rebuild()
    }

    private func rebuild() {
        loadError = nil
        result = nil
        guard let selection else { return }
        do {
            let source = try LoupedeckImport.load(profileAt: selection.profileURL)
            let name = selection.isDefaultApp
                ? "Loupedeck Import"
                : "\(selection.appName) (Loupedeck)"
            result = LoupedeckImport.convert(source, named: name)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Either appends the imported pages to the profile in use, or adds the
    /// whole thing as a separate profile. Both are additive: no existing page
    /// or profile is modified or removed, and either way the save snapshots a
    /// version that Settings > History can restore.
    private func commit() {
        guard let result else { return }
        switch destination {
        case .appendToCurrent:
            store.appendPages(result.profile.pages)
        case .newProfile:
            store.addImportedProfile(result.profile)
        }
        deviceManager.pushCurrentPage()
        dismiss()
    }
}
