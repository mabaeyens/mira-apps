import SwiftUI

// ── ViewModel ─────────────────────────────────────────────────────────────────

@Observable @MainActor
final class MemoriesViewModel {
    var memories: [MemoryItem] = []
    var isLoading = false
    var errorMessage: String? = nil

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            memories = try await APIClient.shared.fetchMemories()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func add(_ text: String) async {
        do {
            let item = try await APIClient.shared.addMemory(text)
            memories.insert(item, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(at offsets: IndexSet) async {
        let toDelete = offsets.map { memories[$0] }
        memories.remove(atOffsets: offsets)
        for item in toDelete {
            try? await APIClient.shared.deleteMemory(id: item.id)
        }
    }
}

// ── Main view ─────────────────────────────────────────────────────────────────

struct MemoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm = MemoriesViewModel()
    @State private var showingAddSheet = false
    @State private var prefillText = ""

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.memories.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.memories.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(vm.memories) { item in
                            Text(item.text)
                                .font(.subheadline)
                                .foregroundStyle(Color.textPrimary)
                                .padding(.vertical, 2)
                        }
                        .onDelete { offsets in
                            Task { await vm.delete(at: offsets) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Memories")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        prefillText = ""
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(vm.memories.count >= 30)
                }
            }
            .background(Color.appBg)
            .task { await vm.load() }
            .sheet(isPresented: $showingAddSheet) {
                AddMemorySheet(prefill: prefillText) { text in
                    Task { await vm.add(text) }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.system(size: 40))
                .foregroundStyle(Color.textSecondary.opacity(0.5))
            Text("No memories yet")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Add facts about yourself so Mira can personalise responses across all conversations.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// ── Add sheet ─────────────────────────────────────────────────────────────────

struct AddMemorySheet: View {
    let prefill: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    init(prefill: String, onSave: @escaping (String) -> Void) {
        self.prefill = prefill
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add a fact Mira should always remember — your name, role, preferences, or any context that applies to all conversations.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                TextEditor(text: $text)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.surfaceBg)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .frame(minHeight: 120)

                Spacer()
            }
            .navigationTitle("New Memory")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .background(Color.appBg)
            .onAppear { text = prefill }
        }
    }
}

// ── Remember-this sheet (presented from ChatView) ─────────────────────────────

struct RememberThisSheet: View {
    let messageText: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit the text below down to the key fact you want Mira to remember.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal)
                    .padding(.top, 8)

                TextEditor(text: $text)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.surfaceBg)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .frame(minHeight: 120)

                Spacer()
            }
            .navigationTitle("Remember This")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .background(Color.appBg)
            .onAppear { text = messageText }
        }
    }
}
