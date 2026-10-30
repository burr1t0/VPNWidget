import SwiftUI
import VPNCore

struct SettingsView: View {
    @State private var url = ""
    @State private var pinned = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("VPN Widget").font(.title2.bold())
            Text("Виджет следит за Happ и показывает пинги. Сам туннель по-прежнему держит Happ.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Ссылка подписки").font(.headline)
                SecureField("https://…", text: $url).textFieldStyle(.roundedBorder)
                Text("Хранится только на этом Маке в личной папке приложения.").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Основной сервер").font(.headline)
                TextField("например, Эстония", text: $pinned).textFieldStyle(.roundedBorder)
                Text("Часть названия. Его пинг показывается в верхней строке виджета.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Сохранить и обновить") { save() }.keyboardShortcut(.defaultAction)
                if saved { Label("Сохранено", systemImage: "checkmark").foregroundStyle(.green) }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            let c = Storage.loadConfig()
            url = c.subscriptionURL ?? ""
            pinned = c.pinned ?? ""
        }
    }

    private func save() {
        var c = Storage.loadConfig()
        c.subscriptionURL = url.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        c.pinned = pinned.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        Storage.save(c, to: Paths.config)
        saved = true
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
