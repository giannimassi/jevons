package daemon

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// HeartbeatState represents the parsed state of a heartbeat file.
type HeartbeatState struct {
	Mode     string // "running" or "stale"
	PID      string
	Interval int
	Age      int
	Status   string // "ok", "working", "error"
}

// SyncFunc is the function called on each sync iteration.
type SyncFunc func() error

// Daemon runs a background sync loop with heartbeat monitoring.
type Daemon struct {
	Interval int
	DataRoot string
	SyncFn   SyncFunc
}

func (d *Daemon) heartbeatPath() string {
	return filepath.Join(d.DataRoot, "heartbeat", "sync.txt")
}

func (d *Daemon) pidPath() string {
	return filepath.Join(d.DataRoot, "pids", "sync.pid")
}

// WriteHeartbeat writes a heartbeat entry: epoch,interval,pid,status
func (d *Daemon) WriteHeartbeat(status string) error {
	path := d.heartbeatPath()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	content := fmt.Sprintf("%d,%d,%d,%s\n", time.Now().Unix(), d.Interval, os.Getpid(), status)
	return os.WriteFile(path, []byte(content), 0644)
}

// WritePID writes the current process PID to the PID file.
func (d *Daemon) WritePID() error {
	path := d.pidPath()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(fmt.Sprintf("%d", os.Getpid())), 0644)
}

// Run starts the sync loop. It blocks until the context is cancelled.
func (d *Daemon) Run(ctx context.Context) error {
	for _, dir := range []string{"heartbeat", "pids", "logs"} {
		if err := os.MkdirAll(filepath.Join(d.DataRoot, dir), 0755); err != nil {
			return fmt.Errorf("create %s dir: %w", dir, err)
		}
	}

	if err := d.WritePID(); err != nil {
		return fmt.Errorf("write PID: %w", err)
	}

	// Run sync immediately
	d.runOnce()

	// If interval is 0, just block until context is cancelled (no periodic sync)
	if d.Interval <= 0 {
		<-ctx.Done()
		d.cleanup()
		return nil
	}

	ticker := time.NewTicker(time.Duration(d.Interval) * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			d.cleanup()
			return nil
		case <-ticker.C:
			d.runOnce()
		}
	}
}

func (d *Daemon) runOnce() {
	_ = d.WriteHeartbeat("working")
	if err := d.SyncFn(); err != nil {
		_ = d.WriteHeartbeat("error")
	} else {
		_ = d.WriteHeartbeat("ok")
	}
}

func (d *Daemon) cleanup() {
	os.Remove(d.pidPath())
}

// ReadHeartbeatState reads and parses the heartbeat file.
func ReadHeartbeatState(dataRoot string) *HeartbeatState {
	path := filepath.Join(dataRoot, "heartbeat", "sync.txt")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}

	line := strings.TrimSpace(string(data))
	parts := strings.SplitN(line, ",", 4)
	if len(parts) < 4 {
		return nil
	}

	epoch, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return nil
	}

	interval, _ := strconv.Atoi(parts[1])
	pid := parts[2]
	status := parts[3]

	now := time.Now().Unix()
	age := int(now - epoch)

	healthyLimit := interval * 12
	if healthyLimit < 300 {
		healthyLimit = 300
	}

	mode := "stale"
	if interval > 0 && age <= healthyLimit {
		mode = "running"
	}

	return &HeartbeatState{
		Mode:     mode,
		PID:      pid,
		Interval: interval,
		Age:      age,
		Status:   status,
	}
}

// IsPIDRunning checks if a process with the given PID is running.
func IsPIDRunning(pid int) bool {
	if pid <= 0 {
		return false
	}
	proc, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	err = proc.Signal(syscall.Signal(0))
	return err == nil
}

// IsSyncRunning checks if the sync daemon is running via PID file or heartbeat.
func IsSyncRunning(dataRoot string) bool {
	pidPath := filepath.Join(dataRoot, "pids", "sync.pid")
	data, err := os.ReadFile(pidPath)
	if err == nil {
		pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
		if err == nil && IsPIDRunning(pid) {
			return true
		}
	}

	hb := ReadHeartbeatState(dataRoot)
	return hb != nil && hb.Mode == "running"
}

// EnsureDataDirs creates all required data directories.
func EnsureDataDirs(dataRoot string) error {
	dirs := []string{
		dataRoot,
		filepath.Join(dataRoot, "pids"),
		filepath.Join(dataRoot, "logs"),
		filepath.Join(dataRoot, "heartbeat"),
		filepath.Join(dataRoot, "web"),
		filepath.Join(dataRoot, "dashboard"),
	}
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("create dir %s: %w", dir, err)
		}
	}
	return nil
}
