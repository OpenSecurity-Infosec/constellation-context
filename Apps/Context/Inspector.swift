import AppKit
import ContextDomain
import ContextStore
import SwiftUI

/// The overlay's settings panel. It slides in from the right edge (⌥⌘I or
/// ⋯ › Inspector) with the current pad's project, delivery, AI, and look.
/// The window grows to make room, so the text stays where it was. It
/// replaces the nested Project › Deliver To menus for everyday use.
struct NoteInspector: View {
    static let width: CGFloat = 280

    weak var controller: ContextWindowController?
    var pad: Pad
    var project: ProjectInfo?
    /// Esc closes the panel unless an AI card is using it.
    var escCloses: Bool

    @State private var fontSize = Double(ContextSettings.shared.fontSize)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(pad.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    closeButton
                }
                if let project {
                    projectSection(project)
                    deliverySection(project)
                }
                aiSection
                lookSection
                Text(BuildInfo.label(from: Bundle.main.infoDictionary ?? [:]))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("inspector.build")
            }
            .padding(.horizontal, 18)
            .padding(.top, 34)
            .padding(.bottom, 18)
        }
        .frame(width: Self.width)
        .background(Color.ctxPanelBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 0.5)
        }
        .accessibilityIdentifier("overlay.inspector")
    }

    @ViewBuilder
    private var closeButton: some View {
        let button = Button {
            controller?.toggleInspector()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Close (esc)")
        .accessibilityIdentifier("overlay.inspector.close")
        if escCloses {
            button.keyboardShortcut(.cancelAction)
        } else {
            button
        }
    }

    // MARK: - Sections

    private func projectSection(_ info: ProjectInfo) -> some View {
        section("Project") {
            row("Documents") {
                Text("\(info.documents.count)").foregroundStyle(.secondary)
                Button("Add…") { controller?.addProjectDocument() }
            }
            row("Linked notes") {
                Text("\(info.references.count)").foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Copy as Context") { controller?.copyProjectContext() }
                Button("Copy Import Line") { controller?.copyImportLine() }
            }
            .padding(.top, 4)
        }
    }

    private func deliverySection(_ info: ProjectInfo) -> some View {
        section("Delivery") {
            row("Context file") {
                Button("Reveal") { controller?.revealProjectFile() }
            }
            ForEach(HarnessKind.allCases, id: \.self) { kind in
                switchRow(kind.displayName, isOn: Binding(
                    get: { info.harnesses.contains(kind) },
                    set: { _ in controller?.toggleHarness(kind) }
                ))
            }
            switchRow("Router", isOn: Binding(get: { info.routerSync }, set: { _ in controller?.toggleRouterSync() }))
            Button("Deliver Now") { controller?.deliverNow() }
                .padding(.top, 4)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private var aiSection: some View {
        section("AI") {
            row("Model") { Text(AIConfig.model.model).foregroundStyle(.secondary) }
            row("Endpoint") { Text(AIConfig.model.baseURL.host() ?? "").foregroundStyle(.secondary) }
            Button("AI Settings…") { controller?.openSettings() }
                .padding(.top, 4)
        }
    }

    private var lookSection: some View {
        section("Look") {
            row("Text size") {
                Text("\(Int(fontSize))").foregroundStyle(.secondary).monospacedDigit()
                Stepper("", value: $fontSize, in: 11...22, step: 1).labelsHidden()
            }
            .onChange(of: fontSize) {
                ContextSettings.shared.fontSize = CGFloat(fontSize)
                ContextSettings.shared.save()
                ThemeRelayer.lookChanged()
            }
        }
    }

    // MARK: - Pieces

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            content()
        }
        .font(.system(size: 12))
        .controlSize(.small)
    }

    private func row(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 22)
    }

    /// A delivery target that isn't built yet: the switch records intent.
    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        row(title) {
            Text("not built yet").foregroundStyle(.secondary).lineLimit(1)
            Toggle("", isOn: isOn).labelsHidden()
        }
        .help("\(title) delivery isn't built yet. The context file is kept current.")
    }
}
