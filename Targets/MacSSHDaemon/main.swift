import Darwin
import Dispatch
import Foundation

// Ignore SIGPIPE to avoid daemon termination on broken socket writes
signal(SIGPIPE, SIG_IGN)

// Ensure child processes (shells) are not auto-reaped by SIG_IGN, enabling waitpid()
signal(SIGCHLD, SIG_DFL)

let server = DaemonServer()
do {
    try server.start()
} catch {
    let msg = "macsshd: fatal startup error: \(error.localizedDescription)\n"
    fputs(msg, stderr)
    Darwin.exit(1)
}

dispatchMain()
