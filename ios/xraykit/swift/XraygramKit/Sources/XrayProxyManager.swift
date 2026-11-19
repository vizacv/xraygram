import Foundation
import XraygramCore

/// Краткое описание сервера из share-ссылки (для превью и подписи в списке прокси).
public struct XrayLinkInfo: Equatable {
    public let protocolName: String
    public let address: String
    public let port: Int
    public let name: String

    public init(protocolName: String, address: String, port: Int, name: String) {
        self.protocolName = protocolName
        self.address = address
        self.port = port
        self.name = name
    }

    /// Имя из `#fragment`, иначе хост сервера (FEAT-02: порт в списке не показываем).
    public var title: String {
        if !self.name.isEmpty {
            return self.name
        }
        return self.address
    }

    /// `vless · host:443 · имя`
    public var summary: String {
        var parts = [self.protocolName, self.port > 0 ? "\(self.address):\(self.port)" : self.address]
        if !self.name.isEmpty {
            parts.append(self.name)
        }
        return parts.joined(separator: " · ")
    }
}

public struct XrayError: Error, Equatable {
    /// Код ошибки из ядра (PAR-03): по нему UI выбирает понятный текст (таблица FEAT-01).
    public enum Code: String {
        case empty
        case webLink = "web_link"
        case unsupported
        case incomplete
        case startFailed = "start_failed"
        case noPort = "no_port"
        case other
    }

    public let code: Code
    /// Сырой текст ядра — для логов и для «прочих» ошибок в скобках.
    public let message: String

    public init(code: Code = .other, _ message: String) {
        self.code = code
        self.message = message
    }

    /// Понятный текст для пользователя (FEAT-01, «Понятные ошибки»; FEAT-02, причины статуса).
    public func userMessage(_ strings: XrayStrings) -> String {
        let en = strings.english
        switch self.code {
        case .empty:
            return en ? "Paste the server link" : "Вставьте ссылку на сервер"
        case .webLink:
            return en ? "This is a web or subscription link. A single-server link is needed: vless://, vmess://, trojan://, ss:// or hysteria2://" : "Это ссылка на сайт или подписку. Нужна ссылка на один сервер: vless://, vmess://, trojan://, ss:// или hysteria2://"
        case .unsupported:
            return en ? "This is not a server link. Use vless://, vmess://, trojan://, ss:// or hysteria2://" : "Это не ссылка на сервер. Нужна ссылка vless://, vmess://, trojan://, ss:// или hysteria2://"
        case .incomplete:
            return en ? "The link is incomplete (address, port, key or parameters). Copy the whole link again" : "В ссылке не хватает данных (адрес, порт, ключ или параметры). Скопируйте её целиком ещё раз"
        case .startFailed:
            return en ? "failed to start" : "не удалось запустить"
        case .noPort:
            return en ? "no free local port" : "нет свободного локального порта"
        case .other:
            return en ? "Link not recognized (\(self.message))" : "Ссылка не распознана (\(self.message))"
        }
    }
}

/// Тексты Xraygram (product/features/FEAT-01…04, FEAT-15), RU/EN.
/// Язык: русский, если язык приложения русский, или если в приложении язык по умолчанию (en), а система —
/// на русском (до входа Telegram ещё не предлагал сменить язык). Иначе английский.
public struct XrayStrings {
    public let english: Bool

    public init(english: Bool) {
        self.english = english
    }

    public init(appLanguageCode: String) {
        let app = appLanguageCode.lowercased()
        if app.hasPrefix("ru") {
            self.english = false
        } else if app.isEmpty || app == "en" {
            if let chosen = XraygramIntro.chosenLanguage {
                // Выбор во вступлении (FEAT-19 §2): пакет строк Telegram придёт позже, через XRAY.
                self.english = chosen != "ru"
            } else {
                let system = (Locale.preferredLanguages.first ?? "").lowercased()
                self.english = !system.hasPrefix("ru")
            }
        } else {
            self.english = true
        }
    }

    // FEAT-19 §2: вступление.
    public var introTitle: String { return "XRAYGRAM" }
    public var introSubtitle: String { return self.t("Неофициальный клиент Telegram, который подключается через ваш сервер XRAY.", "An unofficial Telegram client that connects through your own XRAY server.") }
    public var introStart: String { return self.t("Начать", "Start") }

    // FEAT-20: значок статуса XRAY над списком чатов.
    public var statusNoNetwork: String { return self.t("Нет сети", "No network") }
    public var statusDirect: String { return self.t("Напрямую, без XRAY", "Direct, without XRAY") }
    public var statusOtherProxy: String { return self.t("Прокси без XRAY", "Proxy without XRAY") }
    public func statusNoConnection(_ name: String) -> String { return "XRAY · \(XrayStrings.statusName(name)) · " + self.t("нет связи", "no connection") }
    public func statusConnecting(_ name: String) -> String { return "XRAY · \(XrayStrings.statusName(name)) · " + self.t("подключение…", "connecting…") }
    public func statusConnected(_ name: String, pingMs: Int?) -> String {
        if let pingMs {
            return "XRAY · \(XrayStrings.statusName(name)) · \(pingMs) " + self.t("мс", "ms")
        }
        return "XRAY · \(XrayStrings.statusName(name))"
    }
    public var statusOpenProxySettings: String { return self.t("Открыть настройки прокси", "Open proxy settings") }
    /// Имя записи в значке: длиннее 16 символов — обрезать с «…» (F20-12).
    public static func statusName(_ name: String) -> String {
        if name.count > 16 {
            return String(name.prefix(15)) + "…"
        }
        return name
    }

    // FEAT-20 п. 13: экран и окно XRAY.
    public var gateOverline: String { return "XRAY · VLESS" }

    // FEAT-19 §4: строка версии внизу настроек и диалог.
    public func versionRow(version: String) -> String { return self.t("Xraygram для iOS \(version) · неофициальный клиент Telegram", "Xraygram for iOS \(version) · unofficial Telegram client") }
    public func aboutTitle(version: String) -> String { return "Xraygram \(version)" }
    public func aboutText(upstreamVersion: String) -> String { return self.t("Неофициальный клиент Telegram, который подключается через ваш сервер XRAY.\n\nНа основе Telegram iOS \(upstreamVersion). Исходный код: github.com/vizacv/xraygram", "An unofficial Telegram client that connects through your own XRAY server.\n\nBased on Telegram iOS \(upstreamVersion). Source code: github.com/vizacv/xraygram") }
    public var aboutSourceCode: String { return self.t("Исходный код", "Source code") }
    public var ok: String { return "OK" }

    private func t(_ ru: String, _ en: String) -> String {
        return self.english ? en : ru
    }

    // FEAT-01: окно прокси.
    public var typeTitle: String { return "XRAY (VLESS)" }
    public var linkHeader: String { return self.t("ССЫЛКА", "LINK") }
    public var linkPlaceholder: String { return "vless://…" }
    public var linkHint: String { return self.t("Ссылка на ваш сервер: vless://, vmess://, trojan://, ss:// или hysteria2://. Вставьте её кнопкой «Вставить» выше или долгим нажатием в поле.", "Link to your server: vless://, vmess://, trojan://, ss:// or hysteria2://. Paste it with the Paste button above or by long-pressing the field.") }
    public var pasteButton: String { return self.t("Вставить ссылку из буфера", "Paste link from clipboard") }
    public func serverPreview(_ info: XrayLinkInfo) -> String { return "✓ " + self.t("Сервер: ", "Server: ") + info.summary }
    public func errorPreview(_ error: XrayError) -> String { return self.t("Ошибка: ", "Error: ") + error.userMessage(self) }
    public func entryStatus(_ error: XrayError) -> String { return "XRAY: " + error.userMessage(self) }

    // FEAT-02: удаление последней записи.
    public var deleteLastTitle: String { return self.t("Удалить последнюю XRAY-запись?", "Delete the last XRAY entry?") }
    public var deleteLastText: String { return self.t("Без неё Xraygram не будет подключаться к Telegram, пока вы не добавите ссылку или явно не выберете подключение напрямую. Ссылка останется в сохранённых серверах.", "Without it Xraygram will not connect to Telegram until you add a link or explicitly choose a direct connection. The link stays in saved servers.") }
    public var delete: String { return self.t("Удалить", "Delete") }
    public var cancel: String { return self.t("Отмена", "Cancel") }

    // FEAT-03: экран «Подключение через XRAY» и «напрямую».
    public var gateTitle: String { return self.t("Подключение через XRAY", "Connect through XRAY") }
    public var gateTextNoSaved: String { return self.t("Xraygram подключается к Telegram только через ваш сервер XRAY. Вставьте ссылку на него: vless://, vmess://, trojan://, ss:// или hysteria2://. Пока ссылки нет, Xraygram никуда не подключается.", "Xraygram connects to Telegram only through your XRAY server. Paste its link: vless://, vmess://, trojan://, ss:// or hysteria2://. Until there is a link, Xraygram does not connect anywhere.") }
    public var gateTextSaved: String { return self.t("Xraygram подключается к Telegram только через ваш сервер XRAY. Выберите сохранённый сервер или вставьте новую ссылку. До этого Xraygram никуда не подключается.", "Xraygram connects to Telegram only through your XRAY server. Choose a saved server or paste a new link. Until then Xraygram does not connect anywhere.") }
    public var savedServers: String { return self.t("СОХРАНЁННЫЕ СЕРВЕРЫ", "SAVED SERVERS") }
    public var newLink: String { return self.t("Новая ссылка", "New link") }
    public var connect: String { return self.t("Подключить", "Connect") }
    public var connectDirectLink: String { return self.t("Подключиться без XRAY (напрямую)", "Connect without XRAY (direct)") }
    public var directTitle: String { return self.t("Подключиться напрямую?", "Connect directly?") }
    public var directText: String { return self.t("Xraygram подключится к Telegram без XRAY: провайдер увидит это соединение, а там, где Telegram блокируют, связи не будет. Вернуться к XRAY: Настройки → Данные и память → Прокси.", "Xraygram will connect to Telegram without XRAY: your provider will see this connection, and where Telegram is blocked it will not work. To go back to XRAY: Settings → Data and Storage → Proxy.") }
    public var connectDirect: String { return self.t("Подключиться напрямую", "Connect directly") }
    public var proxyButton: String { return self.t("Прокси", "Proxy") }

    // FEAT-04: перед групповым звонком.
    public var withoutXrayTitle: String { return self.t("Без XRAY", "Without XRAY") }
    public var withoutXrayText: String { return self.t("Групповые звонки, видеочаты и конференции пока идут напрямую, без XRAY: провайдер увидит соединение с серверами Telegram, а при блокировке звонок может не соединиться.\n\nСообщения и звонки один на один по-прежнему идут через XRAY.", "Group calls, video chats and conferences currently go directly, without XRAY: your provider will see a connection to Telegram servers, and where Telegram is blocked the call may not connect.\n\nMessages and one-on-one calls still go through XRAY.") }
    public var proceed: String { return self.t("Продолжить", "Continue") }

    // FEAT-15: поделиться сервером.
    public var shareServer: String { return self.t("Поделиться сервером", "Share server") }
    public var shareWarningTitle: String { return self.t("Поделиться сервером?", "Share server?") }
    public var shareWarningText: String { return self.t("Кто получит эту ссылку, сможет пользоваться вашим сервером XRAY. Отправляйте её только тем, кому доверяете.", "Anyone who gets this link can use your XRAY server. Send it only to people you trust.") }
    public var show: String { return self.t("Показать", "Show") }
    public var shareCaption: String { return self.t("Отсканируйте камерой телефона, затем вставьте ссылку в Xraygram", "Scan with a phone camera, then paste the link into Xraygram") }
    public var copyLink: String { return self.t("Копировать ссылку", "Copy link") }
    public var send: String { return self.t("Отправить…", "Send…") }
    public var close: String { return self.t("Закрыть", "Close") }
    public var linkCopied: String { return self.t("Ссылка скопирована", "Link copied") }
}

public enum XrayLink {
    /// Подпись записи в списке прокси: `XRAY · <имя>`.
    public static func displayTitle(_ link: String) -> String {
        switch XrayLink.check(link) {
        case let .success(info):
            return "XRAY · \(info.title)"
        case .failure:
            return "XRAY"
        }
    }

    /// Схемы, которые понимает libXray `share` (`socks://` не берём — у Телеги свой SOCKS5).
    public static let schemes: [String] = ["vless", "vmess", "trojan", "ss", "hysteria2", "hy2"]

    /// Первая строка текста, если это share-ссылка поддерживаемой схемы (для подстановки из буфера).
    public static func extract(from text: String?) -> String? {
        guard let text = text else {
            return nil
        }
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let range = candidate.range(of: "://") else {
                continue
            }
            let scheme = candidate[candidate.startIndex ..< range.lowerBound].lowercased()
            if XrayLink.schemes.contains(scheme) {
                return candidate
            }
        }
        return nil
    }

    public static func isLink(_ text: String) -> Bool {
        return XrayLink.extract(from: text) == text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let cacheLock = NSLock()
    private static var cache: [String: Result<XrayLinkInfo, XrayError>] = [:]

    /// Разбор ссылки ядром (то же, что `xraygram-core check` на macOS). Быстро, без сети;
    /// результат кэшируется (зовётся при каждой отрисовке списка прокси).
    public static func check(_ link: String) -> Result<XrayLinkInfo, XrayError> {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        XrayLink.cacheLock.lock()
        let cached = XrayLink.cache[link]
        XrayLink.cacheLock.unlock()
        if let cached = cached {
            return cached
        }
        let result = XrayLink.checkUncached(link)
        XrayLink.cacheLock.lock()
        if XrayLink.cache.count > 64 {
            XrayLink.cache.removeAll()
        }
        XrayLink.cache[link] = result
        XrayLink.cacheLock.unlock()
        return result
    }

    private static func checkUncached(_ link: String) -> Result<XrayLinkInfo, XrayError> {
        if link.isEmpty {
            return .failure(XrayError(code: .empty, "empty link"))
        }
        guard let json = XrayCoreCall.json(link.withCString { XGCheck(UnsafeMutablePointer(mutating: $0)) }) else {
            return .failure(XrayError("internal error"))
        }
        if json["ok"] as? Bool == true {
            return .success(XrayLinkInfo(
                protocolName: json["protocol"] as? String ?? "",
                address: json["address"] as? String ?? "",
                port: (json["port"] as? NSNumber)?.intValue ?? 0,
                name: json["name"] as? String ?? ""
            ))
        }
        return .failure(XrayError(code: XrayError.Code(rawValue: json["code"] as? String ?? "") ?? .other, json["error"] as? String ?? "invalid link"))
    }

    /// Версия Xray-core внутри приложения.
    public static var coreVersion: String {
        return XrayCoreCall.string(XGVersion()) ?? "?"
    }
}

enum XrayCoreCall {
    static func string(_ value: UnsafeMutablePointer<CChar>?) -> String? {
        guard let value = value else {
            return nil
        }
        defer {
            XGFree(value)
        }
        return String(cString: value)
    }

    static func json(_ value: UnsafeMutablePointer<CChar>?) -> [String: Any]? {
        guard let text = XrayCoreCall.string(value), let data = text.data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// Держит экземпляры xray внутри процесса: по одному на ссылку, каждый — SOCKS5 на 127.0.0.1
/// со своим портом, логином (по ссылке) и паролем (случайный на процесс). Сетевой код Телеги
/// (MtProtoKit / Rust-движок, звонки) ходит в этот SOCKS5 как в обычный прокси.
///
/// Жизненный цикл: `endpoint(for:)` поднимает экземпляр (если нужно) и возвращает адрес;
/// `retain`/`release` — счётчик пользователей (активный прокси сети, проверка в списке).
/// Экземпляр без пользователей гасится через `idleTimeout`.
///
/// iOS может отобрать слушающий сокет у приостановленного приложения (TN2277), поэтому
/// при возврате на передний план зовите `handleWillEnterForeground()`: он проверяет порты
/// и перезапускает умершие экземпляры на тех же портах.
public final class XrayProxyManager: @unchecked Sendable {
    public static let shared = XrayProxyManager()

    public struct Endpoint: Equatable {
        public let host: String
        public let port: UInt16
        public let username: String
        public let password: String
    }

    private final class Instance {
        let id: String
        var endpoint: Endpoint
        var info: XrayLinkInfo?
        var refs: Int = 0
        var generation: Int = 0

        init(id: String, endpoint: Endpoint) {
            self.id = id
            self.endpoint = endpoint
        }
    }

    public static let listenHost = "127.0.0.1"
    /// Порт, на котором заведомо никто не слушает: так выглядит «сломанная» XRAY-запись для MTProto.
    private static let deadPort: UInt16 = 9

    public var idleTimeout: TimeInterval = 15.0
    /// Мягкий лимит памяти Go-рантайма. Главному приложению iOS хватает; экстеншенам — нет
    /// (там ядро не используем).
    public var memoryLimitBytes: Int64 = 64 * 1024 * 1024

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "xraygram.proxy-manager")
    private var instances: [String: Instance] = [:]
    private var lastErrors: [String: XrayError] = [:]
    /// Порт, который ссылка получила в этом процессе: при повторном запуске берём его же,
    /// чтобы MTSocksProxySettings не менялись и сеть не переподключалась зря.
    private var rememberedPorts: [String: UInt16] = [:]
    private let password: String
    private var didConfigureRuntime = false

    /// Шлётся (на любом потоке), когда экземпляр пришлось перезапустить на другом порту:
    /// сеть должна заново взять `endpoint(for:)` активной записи.
    public static let endpointsChangedNotification = Notification.Name("XrayProxyManagerEndpointsChanged")

    private init() {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for i in 0 ..< bytes.count {
                bytes[i] = UInt8.random(in: 0 ... 255)
            }
        }
        self.password = bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func username(for link: String) -> String {
        // FNV-1a 64: стабильный короткий хэш ссылки. Логин разный у разных ссылок, поэтому
        // MTSocksProxySettings разных XRAY-записей никогда не равны (сеть переподключается).
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in link.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "xg" + String(hash, radix: 16)
    }

    /// Адрес локального SOCKS5 для ссылки; поднимает xray, если он ещё не запущен.
    public func endpoint(for link: String) -> Endpoint {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        if let instance = self.instances[link], self.isRunningLocked(instance) {
            return instance.endpoint
        }
        return self.startLocked(link: link, preferredPort: self.instances[link]?.endpoint.port ?? self.rememberedPorts[link])
    }

    public func retain(_ link: String) {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lock.lock()
        if self.instances[link] == nil {
            let _ = self.startLocked(link: link, preferredPort: self.rememberedPorts[link])
        }
        if let instance = self.instances[link] {
            instance.refs += 1
            instance.generation += 1
        }
        self.lock.unlock()
    }

    public func release(_ link: String) {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lock.lock()
        guard let instance = self.instances[link] else {
            self.lock.unlock()
            return
        }
        instance.refs = max(0, instance.refs - 1)
        instance.generation += 1
        let generation = instance.generation
        let shouldSchedule = instance.refs == 0
        self.lock.unlock()

        if shouldSchedule {
            self.queue.asyncAfter(deadline: .now() + self.idleTimeout) { [weak self] in
                self?.stopIfIdle(link: link, generation: generation)
            }
        }
    }

    /// Последняя ошибка запуска для ссылки (для UI).
    public func lastError(for link: String) -> XrayError? {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.lastErrors[link]
    }

    public func stopAll() {
        self.lock.lock()
        self.instances.removeAll()
        XGStopAll()
        self.lock.unlock()
    }

    /// Проверить, живы ли слушающие сокеты, и перезапустить умершие (после фона).
    public func handleWillEnterForeground() {
        self.queue.async { [weak self] in
            self?.revalidate()
        }
    }

    private func revalidate() {
        var portChanged = false
        self.lock.lock()
        for (link, instance) in self.instances {
            if self.isRunningLocked(instance) && XrayProxyManager.canConnect(port: instance.endpoint.port) {
                continue
            }
            let oldPort = instance.endpoint.port
            let endpoint = self.startLocked(link: link, preferredPort: oldPort)
            if endpoint.port != oldPort {
                portChanged = true
            }
        }
        self.lock.unlock()
        if portChanged {
            NotificationCenter.default.post(name: XrayProxyManager.endpointsChangedNotification, object: self)
        }
    }

    private func stopIfIdle(link: String, generation: Int) {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        guard let instance = self.instances[link], instance.refs == 0, instance.generation == generation else {
            return
        }
        instance.id.withCString { XGStop(UnsafeMutablePointer(mutating: $0)) }
        self.instances.removeValue(forKey: link)
    }

    private func isRunningLocked(_ instance: Instance) -> Bool {
        if instance.endpoint.port == XrayProxyManager.deadPort {
            return false
        }
        return instance.id.withCString { XGIsRunning(UnsafeMutablePointer(mutating: $0)) } != 0
    }

    private func configureRuntimeLocked() {
        if self.didConfigureRuntime {
            return
        }
        self.didConfigureRuntime = true
        XGSetMemoryLimit(self.memoryLimitBytes, 50)
    }

    private func startLocked(link: String, preferredPort: UInt16?) -> Endpoint {
        self.configureRuntimeLocked()
        let username = XrayProxyManager.username(for: link)
        let id = username
        var attempts: [UInt16] = []
        if let preferredPort = preferredPort, preferredPort != XrayProxyManager.deadPort {
            attempts.append(preferredPort)
        }
        attempts.append(0)

        var lastError = XrayError(code: .startFailed, "failed to start")
        for port in attempts {
            let result = XrayCoreCall.json(
                id.withCString { idPtr in
                    link.withCString { linkPtr in
                        XrayProxyManager.listenHost.withCString { hostPtr in
                            username.withCString { userPtr in
                                self.password.withCString { passPtr in
                                    XGStart(
                                        UnsafeMutablePointer(mutating: idPtr),
                                        UnsafeMutablePointer(mutating: linkPtr),
                                        UnsafeMutablePointer(mutating: hostPtr),
                                        Int32(port),
                                        UnsafeMutablePointer(mutating: userPtr),
                                        UnsafeMutablePointer(mutating: passPtr)
                                    )
                                }
                            }
                        }
                    }
                }
            )
            if let result = result, result["ok"] as? Bool == true, let started = (result["port"] as? NSNumber)?.intValue {
                let endpoint = Endpoint(host: XrayProxyManager.listenHost, port: UInt16(clamping: started), username: username, password: self.password)
                let instance = self.instances[link] ?? Instance(id: id, endpoint: endpoint)
                instance.endpoint = endpoint
                instance.info = XrayLinkInfo(
                    protocolName: result["protocol"] as? String ?? "",
                    address: result["address"] as? String ?? "",
                    port: (result["serverPort"] as? NSNumber)?.intValue ?? 0,
                    name: result["name"] as? String ?? ""
                )
                self.instances[link] = instance
                self.rememberedPorts[link] = endpoint.port
                self.lastErrors.removeValue(forKey: link)
                return endpoint
            }
            if let result = result {
                lastError = XrayError(code: XrayError.Code(rawValue: result["code"] as? String ?? "") ?? .other, result["error"] as? String ?? "failed to start")
            }
        }

        // Ссылка битая или ядро не стартовало: отдаём «мёртвый» порт, MTProto покажет «Соединение…».
        let endpoint = Endpoint(host: XrayProxyManager.listenHost, port: XrayProxyManager.deadPort, username: username, password: self.password)
        let instance = self.instances[link] ?? Instance(id: id, endpoint: endpoint)
        instance.endpoint = endpoint
        self.instances[link] = instance
        self.lastErrors[link] = lastError
        return endpoint
    }

    /// Неблокирующий connect() к 127.0.0.1:port с таймаутом.
    static func canConnect(port: UInt16, timeout: TimeInterval = 0.5) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 {
            return false
        }
        defer {
            close(fd)
        }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL, 0)
        let _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr(XrayProxyManager.listenHost)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 {
            return true
        }
        if errno != EINPROGRESS {
            return false
        }
        var pollDescriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        if poll(&pollDescriptor, 1, Int32(timeout * 1000.0)) <= 0 {
            return false
        }
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
        return error == 0
    }
}

/// FEAT-19 §2: состояние вступления. Язык, выбранный во вступлении («Русский · English»), и флаг «пройдено»
/// (после «Начать» показывается экран XRAY). Пакет строк Telegram для выбранного языка скачивается после
/// подключения через XRAY (`pendingLanguage`).
public enum XraygramIntro {
    public static let sourceCodeURL = "https://github.com/vizacv/xraygram"
    private static let languageKey = "xg.introLanguage"
    private static let pendingKey = "xg.introPendingLanguage"

    public static var chosenLanguage: String? {
        get { return UserDefaults.standard.string(forKey: languageKey) }
        set { UserDefaults.standard.set(newValue, forKey: languageKey) }
    }

    /// Язык, пакет которого ещё надо скачать и применить (nil — ничего не нужно).
    public static var pendingLanguage: String? {
        get { return UserDefaults.standard.string(forKey: pendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
    }

    /// Язык вступления по умолчанию — по правилу языка (FEAT-01): русский, если система на русском.
    public static var defaultLanguage: String {
        if let chosen = chosenLanguage {
            return chosen
        }
        return (Locale.preferredLanguages.first ?? "").lowercased().hasPrefix("ru") ? "ru" : "en"
    }
}
