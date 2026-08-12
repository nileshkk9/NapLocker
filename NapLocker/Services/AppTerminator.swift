import AppKit

/// Terminates a launched application. Abstracted so `LockManager` can assert on
/// termination in tests without killing real processes.
protocol AppTerminating {
    func terminate(_ app: LaunchedApp)
}

/// Asks the app to quit, then escalates to a force-kill if it is still alive
/// after a short grace period. A graceful `terminate()` first avoids data-loss
/// prompts on well-behaved apps; the escalation guarantees the lock holds.
final class RunningAppTerminator: AppTerminating {
    private let graceInterval: TimeInterval

    init(graceInterval: TimeInterval = 1.5) {
        self.graceInterval = graceInterval
    }

    func terminate(_ app: LaunchedApp) {
        guard let running = app as? NSRunningApplication else { return }
        running.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + graceInterval) {
            if !running.isTerminated {
                running.forceTerminate()
            }
        }
    }
}
