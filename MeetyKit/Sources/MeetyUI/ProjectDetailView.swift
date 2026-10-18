import MeetyCore
import SwiftUI

/// Um projeto: nome, totais e as reuniões alocadas. Clicar numa reunião abre a reunião.
struct ProjectDetailView: View {
    @Bindable var model: AppModel
    let project: Project
    @State private var name = ""
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var showNew = false
    @FocusState private var nameFocused: Bool

    var meetings: [Meeting] { model.library.meetings(in: project) }
    var others: [Meeting] { model.library.meetings.filter { $0.projectID != project.id } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.meety.separator)
            if meetings.isEmpty { empty } else { list }
        }
        .toolbar { toolbar }
        .onAppear { name = project.name }
        .confirmationDialog(String(localized: "Delete this project?", bundle: .module), isPresented: $confirmDelete) {
            Button(String(localized: "Delete project", bundle: .module), role: .destructive) { model.deleteProject(project) }
        } message: { Text(String(localized: "The meetings stay in your library, just without a project.", bundle: .module)) }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Circle().fill(Color.meety.speaker(project.colorIndex)).frame(width: 14, height: 14)
                if editing {
                    TextField(String(localized: "Project name", bundle: .module), text: $name)
                        .textFieldStyle(.plain).font(MeetyFont.windowTitle).focused($nameFocused)
                        .onSubmit { commit() }
                        .onChange(of: nameFocused) { _, f in if !f { commit() } }
                } else {
                    Text(project.name).font(MeetyFont.windowTitle)
                        .onTapGesture { name = project.name; editing = true; nameFocused = true }
                        .help(String(localized: "Click to rename", bundle: .module))
                }
            }
            Text(summaryLine).font(.system(size: 14)).foregroundStyle(Color.meety.textSecondary)
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var summaryLine: String {
        let total = meetings.compactMap(\.duration).reduce(0, +)
        var parts = [String(localized: "\(meetings.count) meetings", bundle: .module)]
        if total > 0 { parts.append(MeetyFormat.duration(total)) }
        if let last = meetings.first { parts.append(String(localized: "last on \(MeetyFormat.dayAndTime(last.createdAt))", bundle: .module)) }
        return parts.joined(separator: " · ")
    }

    func commit() {
        editing = false
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != project.name else { return }
        model.library.updateProject(project.id) { $0.name = n }
    }

    var list: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(meetings) { m in
                    Button { model.sidebarMode = .recordings; model.selectedMeetingID = m.id } label: {
                        MeetingRow(model: model, meeting: m)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.meety.elevated, in: RoundedRectangle(cornerRadius: MeetyRadius.card, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: MeetyRadius.card, style: .continuous).stroke(Color.meety.separator))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(String(localized: "Remove from project", bundle: .module)) { model.library.assign(m.id, to: nil) }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    var empty: some View {
        VStack(spacing: 0) {
            Spacer()
            HeroIcon(systemName: "folder", size: 96, tint: Color.meety.speaker(project.colorIndex), background: Color.meety.speaker(project.colorIndex).opacity(0.14))
            Text(String(localized: "No meetings in this project", bundle: .module)).font(MeetyFont.stateTitle).padding(.top, 24)
            Text(String(localized: "Add meetings with the button above, or drag recordings onto the project in the sidebar.", bundle: .module))
                .font(.system(size: 14)).lineSpacing(3).foregroundStyle(Color.meety.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                .padding(.top, 10)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Menu {
                if others.isEmpty {
                    Text(String(localized: "Every meeting is already here", bundle: .module))
                } else {
                    ForEach(others) { m in
                        Button { model.library.assign(m.id, to: project.id) } label: {
                            Text(m.title)
                            Text(MeetyFormat.dayAndTime(m.createdAt))
                        }
                    }
                }
            } label: {
                Label(String(localized: "Add meetings", bundle: .module), systemImage: "plus").labelStyle(.titleAndIcon)
            }
            Menu {
                Button(String(localized: "Rename", bundle: .module)) { name = project.name; editing = true; nameFocused = true }
                Divider()
                Button(String(localized: "Delete project", bundle: .module), role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis") }
        }
    }
}
