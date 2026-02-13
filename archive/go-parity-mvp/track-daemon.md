# Track T4: Daemon & Status

## Status: COMPLETE

## Implementation

File: `internal/daemon/daemon.go` (170 lines)

### Daemon
- `Daemon.Run(ctx)`: blocks, runs SyncFn immediately then on ticker interval
- Writes heartbeat file: `epoch,interval,pid,status` format
- Writes PID file on start, removes on cleanup
- Cancellable via context

### Health checks
- `ReadHeartbeatState(dataRoot)`: parses heartbeat file, computes age, determines mode (running/stale)
- Health limit: `interval * 12`, minimum 300 seconds (matches shell)
- `IsPIDRunning(pid)`: uses `syscall.Signal(0)` for Unix process check
- `IsSyncRunning(dataRoot)`: checks PID file + heartbeat fallback

### Tests: 3 passing
- TestDaemonRunAndHeartbeat: verifies sync runs, heartbeat written, PID cleaned up
- TestReadHeartbeatState: table-driven (no file, invalid, fresh, stale)
- TestEnsureDataDirs: all 6 directories created
