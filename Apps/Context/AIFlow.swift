import AppKit
import ContextAI
import ContextDomain
import ContextStore

/// Where an accepted proposal lands.
struct AITarget: Equatable {
    var pad: Pad
    var noteID: UUID
    var label: String
}

enum AIState: Equatable {
    case idle
    case thinking(String)
    case ready(Proposal, AITarget)
    case failed(String)
}

extension ContextWindowController {
    /// AI actions that make sense on the current pad.
    var aiActions: [AIAction] {
        if pad.isProject { return [.summarize, .tidy, .compact] }
        return [.summarize, .tidy] + workspace.projects.map { AIAction.extract(project: $0) }
    }

    func runAI(_ action: AIAction) {
        flushNow()
        aiTask?.cancel()
        let text = note.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            aiState = .failed("This note is empty.")
            render(preservingFocus: true)
            return
        }
        var target = AITarget(pad: pad, noteID: noteID, label: "this note")
        var projectContext: String?
        if case .extract(let project) = action {
            let store = workspace.store(for: .project(project))
            let contextNote = store.liveNotes.first ?? store.create()
            target = AITarget(pad: .project(project), noteID: contextNote.id, label: "\(project)'s context")
            projectContext = contextNote.text
        }
        aiState = .thinking("\(action.title) with \(AIConfig.model.model)…")
        render(preservingFocus: true)
        let actions = AIActions(client: AIConfig.client)
        aiTask = Task { @MainActor [weak self] in
            do {
                let proposal = try await actions.propose(action, note: text, projectContext: projectContext)
                guard !Task.isCancelled, let self else { return }
                self.aiState = proposal.isNoChange
                    ? .failed("\(action.title): nothing to change.")
                    : .ready(proposal, target)
            } catch is CancellationError {
                return
            } catch let error as ModelError {
                self?.aiState = .failed(error.message)
            } catch {
                self?.aiState = .failed("The AI request failed.")
            }
            self?.render(preservingFocus: true)
        }
    }

    func cancelAI() {
        aiTask?.cancel()
        aiTask = nil
        aiState = .idle
        render(preservingFocus: true)
    }

    /// Applies the proposal as one undoable edit. For the open note the
    /// edit goes through the text view, so ⌘Z undoes it natively; for
    /// another pad it goes through the command path with a registered
    /// undo. If the target changed while the model was thinking, nothing
    /// is applied.
    func acceptProposal() {
        guard case .ready(let proposal, let target) = aiState else { return }
        flushNow()
        let store = workspace.store(for: target.pad)
        guard store.note(id: target.noteID)?.text == proposal.original else {
            aiState = .failed("\(target.label.capitalized) changed while the AI was working. Run it again.")
            render(preservingFocus: true)
            return
        }
        if target.pad == pad, target.noteID == noteID, let tv = ContextTextView.active, tv.string == proposal.original {
            let all = NSRange(location: 0, length: (tv.string as NSString).length)
            tv.window?.makeFirstResponder(tv)
            if tv.shouldChangeText(in: all, replacementString: proposal.proposed) {
                tv.replaceCharacters(in: all, with: proposal.proposed)
                tv.didChangeText()
                tv.undoManager?.setActionName(proposal.action.title)
            }
        } else {
            apply(.setText(target.pad, id: target.noteID, text: proposal.proposed))
            let undo = window.undoManager
            undo?.registerUndo(withTarget: self) { controller in
                controller.apply(.setText(target.pad, id: target.noteID, text: proposal.original))
                controller.projectChanged()
            }
            undo?.setActionName(proposal.action.title)
            if target.pad.isProject { projects.refreshSoon(workspace.project(target.pad.title), workspace: workspace) }
        }
        aiState = .idle
        render(preservingFocus: true)
    }

    func rejectProposal() {
        aiState = .idle
        render(preservingFocus: true)
    }
}
