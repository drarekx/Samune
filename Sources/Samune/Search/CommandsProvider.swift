import Foundation

/// Samune's own commands (settings, reload integrations, quit…).
@MainActor
final class CommandsProvider: SearchProvider {
    let priority = 5

    private struct Command {
        let id: String
        let title: String
        let symbol: String
    }

    /// Ids match the performers `AppDelegate` registers in `SearchEngine.shared.performers`.
    private var commands: [Command] {
        [
            Command(id: "settings", title: tr("Ajustes de %@", AppInfo.name), symbol: "gearshape"),
            Command(id: "reloadIntegrations", title: tr("Recargar integraciones"), symbol: "arrow.clockwise"),
            Command(id: "openIntegrationsFolder", title: tr("Abrir la carpeta de integraciones"), symbol: "folder"),
            Command(id: "checkForUpdates", title: tr("Buscar actualizaciones…"), symbol: "arrow.down.circle"),
            Command(id: "quit", title: tr("Salir de %@", AppInfo.name), symbol: "power"),
        ]
    }

    func search(_ query: String) async -> ProviderResponse {
        let items = commands.compactMap { command -> ResultItem? in
            guard let score = Fuzzy.score(query, command.title) else { return nil }
            let id = "command:\(command.id)"
            return ResultItem(id: id, title: command.title, subtitle: nil, icon: .symbol(command.symbol),
                              kind: tr("Comando"), action: .perform(id: command.id),
                              score: score + Frecency.shared.boost(id))
        }
        return ProviderResponse(items: items)
    }
}
