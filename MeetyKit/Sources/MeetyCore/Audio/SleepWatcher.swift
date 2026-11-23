import Foundation
import IOKit
import IOKit.pwr_mgt

/// Avisa quando o Mac vai dormir (tampa fechada, menu Repouso, repouso por inatividade) e SEGURA o
/// repouso até quem pediu terminar o que precisa, como fechar os arquivos de uma gravação.
///
/// Usa o `IORegisterForSystemPower` do IOKit: o sistema só dorme depois do `IOAllowPowerChange`
/// (ou depois de uns 30 s, que é o limite dele). Damos no máximo 20 s ao trabalho e respondemos de
/// qualquer jeito, para nunca travar o repouso. Fica registrado pela vida do app: quem usa decide,
/// no `onWillSleep`, se há algo a fazer.
final class SleepWatcher: @unchecked Sendable {

    /// Recebe a função `done`, que deve ser chamada (uma vez, de qualquer fila) quando terminar.
    private let onWillSleep: (@escaping @Sendable () -> Void) -> Void
    private let queue = DispatchQueue(label: "dev.oka.sleepwatcher")
    private var rootPort: io_connect_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    // iokit_common_msg(0x270) e (0x280): o Swift não importa essas macros.
    private static let canSystemSleep: natural_t = 0xE000_0270
    private static let systemWillSleep: natural_t = 0xE000_0280

    init(onWillSleep: @escaping (@escaping @Sendable () -> Void) -> Void) {
        self.onWillSleep = onWillSleep
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(refcon, &notifyPort, { refcon, _, type, argument in
            guard let refcon else { return }
            Unmanaged<SleepWatcher>.fromOpaque(refcon).takeUnretainedValue().handle(type, argument)
        }, &notifier)
        if rootPort != 0, let notifyPort { IONotificationPortSetDispatchQueue(notifyPort, queue) }
    }

    deinit {
        if notifier != 0 { IODeregisterForSystemPower(&notifier) }
        if rootPort != 0 { IOServiceClose(rootPort) }
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
    }

    /// Roda na `queue`.
    private func handle(_ type: natural_t, _ argument: UnsafeMutableRawPointer?) {
        let id = Int(bitPattern: argument)
        switch type {
        case Self.canSystemSleep:
            IOAllowPowerChange(rootPort, id)
        case Self.systemWillSleep:
            let port = rootPort
            let queue = queue
            let answered = Answered()
            let done: @Sendable () -> Void = {
                queue.async {
                    guard !answered.value else { return }
                    answered.value = true
                    IOAllowPowerChange(port, id)
                }
            }
            queue.asyncAfter(deadline: .now() + 20, execute: done)
            onWillSleep(done)
        default:
            break
        }
    }

    /// Lido e escrito só na `queue`.
    private final class Answered: @unchecked Sendable { var value = false }
}
