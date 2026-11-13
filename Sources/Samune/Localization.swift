import Combine
import Foundation

/// Languages the UI is translated to. Spanish strings are the keys.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, es, ca
    var id: String { rawValue }

    /// Shown in its own language, so anyone can find theirs.
    var nativeName: String {
        switch self {
        case .system: return tr("Sistema")
        case .en: return "English"
        case .es: return "Español"
        case .ca: return "Català"
        }
    }
}

final class Localizer: ObservableObject {
    static let shared = Localizer()

    @Published var choice: AppLanguage {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: "appLanguage") }
    }

    private init() {
        choice = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
    }

    /// The language actually used: the chosen one, or the first supported system language (English otherwise).
    var language: AppLanguage {
        if choice != .system { return choice }
        for preferred in Locale.preferredLanguages {
            let code = String(preferred.prefix(2))
            if let match = AppLanguage(rawValue: code), match != .system { return match }
        }
        return .en
    }

    var locale: Locale { Locale(identifier: language.rawValue) }

    func translate(_ key: String) -> String {
        switch language {
        case .en: return Translations.allEn[key] ?? key
        case .ca: return Translations.allCa[key] ?? key
        default: return key
        }
    }
}

/// Translated UI text. `key` is the Spanish text.
func tr(_ key: String) -> String {
    Localizer.shared.translate(key)
}

/// Translated format string (`%@`, `%d`) with arguments.
func tr(_ key: String, _ args: CVarArg...) -> String {
    String(format: Localizer.shared.translate(key), locale: Localizer.shared.locale, arguments: args)
}

private enum Translations {
    /// Common strings below plus one table per area (`Strings/Strings+*.swift`).
    static let allEn = [PanelStrings.en, SearchStrings.en, IntegrationsStrings.en, CalculatorStrings.en, NotesStrings.en]
        .reduce(en) { $0.merging($1) { first, _ in first } }
    static let allCa = [PanelStrings.ca, SearchStrings.ca, IntegrationsStrings.ca, CalculatorStrings.ca, NotesStrings.ca]
        .reduce(ca) { $0.merging($1) { first, _ in first } }

    static let en: [String: String] = [
        "%@ %@ está disponible": "%@ %@ is available",
        "%@ está actualizado": "%@ is up to date",
        "Abrir %@": "Open %@",
        "Abrir al iniciar sesión": "Open at login",
        "Acerca de %@": "About %@",
        "Actualizaciones": "Updates",
        "Actualizando…": "Updating…",
        "Actualizar ahora": "Update Now",
        "Ajustes": "Settings",
        "Ajustes de %@": "%@ Settings",
        "Ajustes…": "Settings…",
        "Al abrir la app y una vez al día, desde GitHub (%@).": "At launch and once a day, from GitHub (%@).",
        "Buscando…": "Checking…",
        "Buscar actualizaciones automáticamente": "Check for updates automatically",
        "Buscar actualizaciones…": "Check for Updates…",
        "Buscar ahora": "Check Now",
        "Cerrar ventana": "Close Window",
        "Colores": "Colours",
        "Copiar": "Copy",
        "Cortar": "Cut",
        "Deshacer": "Undo",
        "Edición": "Edit",
        "El archivo descargado no coincide con su huella SHA-256. No se ha instalado nada.": "The downloaded file doesn't match its SHA-256 checksum. Nothing was installed.",
        "Es gratis y sin anuncios. Si te ahorra tiempo, puedes invitarme a un café.": "It's free and ad-free. If it saves you time, you can buy me a coffee.",
        "General": "General",
        "GitHub no respondió correctamente. Inténtalo más tarde.": "GitHub didn't respond correctly. Try again later.",
        "Idioma": "Language",
        "Invítame a un café…": "Buy Me a Coffee…",
        "La actualización falló": "The update failed",
        "La descarga no contiene una versión válida de %@.": "The download doesn't contain a valid version of %@.",
        "La versión %@ no incluye los archivos de actualización.": "Version %@ doesn't include the update files.",
        "Minimizar": "Minimize",
        "Mostrar todo": "Show All",
        "Mueve %@ a la carpeta Aplicaciones, ábrela de nuevo y vuelve a intentarlo.": "Move %@ to the Applications folder, open it again and retry.",
        "Más tarde": "Later",
        "No hay permiso para escribir en %@.\nUsa el instalador:\n\n%@": "No permission to write to %@.\nUse the installer:\n\n%@",
        "No se pudo buscar actualizaciones": "Couldn't check for updates",
        "No se pudo cambiar: %@": "Couldn't change it: %@",
        "No se pudo descomprimir la actualización.": "Couldn't unzip the update.",
        "No se puede actualizar": "Can't update",
        "No se puede actualizar desde aquí": "Can't update from here",
        "Ocultar %@": "Hide %@",
        "Ocultar otras": "Hide Others",
        "Omitir esta versión": "Skip This Version",
        "Original (por defecto)": "Original (default)",
        "Pegar": "Paste",
        "Rehacer": "Redo",
        "Salir de %@": "Quit %@",
        "Seleccionar todo": "Select All",
        "Sistema": "System",
        "Temas clásicos de editores y terminales, con sus colores oficiales.": "Classic editor and terminal themes, with their official colours.",
        "Tienes la versión %@.": "You have version %@.",
        "Tienes la última versión (%@).": "You have the latest version (%@).",
        "Ventana": "Window",
        "Versión %@": "Version %@",
        "Lanzador para buscar apps, archivos y contenido de tus servicios": "Launcher to search apps, files and content from your services",
        "¿Te es útil %@?": "Is %@ useful to you?",
        "Recargar integraciones": "Reload Integrations",
        "Abrir la carpeta de integraciones": "Open Integrations Folder",
        "Carpeta de integraciones…": "Integrations Folder…",
        "Comando": "Command",
    ]

    static let ca: [String: String] = [
        "%@ %@ está disponible": "%@ %@ està disponible",
        "%@ está actualizado": "%@ està actualitzada",
        "Abrir %@": "Obre %@",
        "Abrir al iniciar sesión": "Obre en iniciar la sessió",
        "Acerca de %@": "Quant a %@",
        "Actualizaciones": "Actualitzacions",
        "Actualizando…": "Actualitzant…",
        "Actualizar ahora": "Actualitza ara",
        "Ajustes": "Configuració",
        "Ajustes de %@": "Configuració de %@",
        "Ajustes…": "Configuració…",
        "Al abrir la app y una vez al día, desde GitHub (%@).": "En obrir l'app i un cop al dia, des de GitHub (%@).",
        "Buscando…": "Cercant…",
        "Buscar actualizaciones automáticamente": "Cerca actualitzacions automàticament",
        "Buscar actualizaciones…": "Cerca actualitzacions…",
        "Buscar ahora": "Cerca ara",
        "Cerrar ventana": "Tanca la finestra",
        "Colores": "Colors",
        "Copiar": "Copia",
        "Cortar": "Retalla",
        "Deshacer": "Desfés",
        "Edición": "Edició",
        "El archivo descargado no coincide con su huella SHA-256. No se ha instalado nada.": "El fitxer baixat no coincideix amb la seva empremta SHA-256. No s'ha instal·lat res.",
        "Es gratis y sin anuncios. Si te ahorra tiempo, puedes invitarme a un café.": "És gratis i sense anuncis. Si t'estalvia temps, em pots convidar a un cafè.",
        "General": "General",
        "GitHub no respondió correctamente. Inténtalo más tarde.": "GitHub no ha respost correctament. Torna-ho a provar més tard.",
        "Idioma": "Idioma",
        "Invítame a un café…": "Convida'm a un cafè…",
        "La actualización falló": "L'actualització ha fallat",
        "La descarga no contiene una versión válida de %@.": "La baixada no conté una versió vàlida de %@.",
        "La versión %@ no incluye los archivos de actualización.": "La versió %@ no inclou els fitxers d'actualització.",
        "Minimizar": "Minimitza",
        "Mostrar todo": "Mostra-ho tot",
        "Mueve %@ a la carpeta Aplicaciones, ábrela de nuevo y vuelve a intentarlo.": "Mou %@ a la carpeta Aplicacions, torna-la a obrir i torna-ho a provar.",
        "Más tarde": "Més tard",
        "No hay permiso para escribir en %@.\nUsa el instalador:\n\n%@": "No hi ha permís per escriure a %@.\nFes servir l'instal·lador:\n\n%@",
        "No se pudo buscar actualizaciones": "No s'han pogut cercar actualitzacions",
        "No se pudo cambiar: %@": "No s'ha pogut canviar: %@",
        "No se pudo descomprimir la actualización.": "No s'ha pogut descomprimir l'actualització.",
        "No se puede actualizar": "No es pot actualitzar",
        "No se puede actualizar desde aquí": "No es pot actualitzar des d'aquí",
        "Ocultar %@": "Amaga %@",
        "Ocultar otras": "Amaga les altres",
        "Omitir esta versión": "Omet aquesta versió",
        "Original (por defecto)": "Original (per defecte)",
        "Pegar": "Enganxa",
        "Rehacer": "Refés",
        "Salir de %@": "Surt de %@",
        "Seleccionar todo": "Selecciona-ho tot",
        "Sistema": "Sistema",
        "Temas clásicos de editores y terminales, con sus colores oficiales.": "Temes clàssics d'editors i terminals, amb els seus colors oficials.",
        "Tienes la versión %@.": "Tens la versió %@.",
        "Tienes la última versión (%@).": "Tens l'última versió (%@).",
        "Ventana": "Finestra",
        "Versión %@": "Versió %@",
        "Lanzador para buscar apps, archivos y contenido de tus servicios": "Llançador per cercar apps, fitxers i contingut dels teus serveis",
        "¿Te es útil %@?": "T'és útil %@?",
        "Recargar integraciones": "Recarrega les integracions",
        "Abrir la carpeta de integraciones": "Obre la carpeta d'integracions",
        "Carpeta de integraciones…": "Carpeta d'integracions…",
        "Comando": "Ordre",
    ]
}
