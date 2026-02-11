package model

import (
	"os"
	"path/filepath"
)

// Config holds runtime configuration for jevons.
type Config struct {
	DataRoot  string // Where events, dashboard, PIDs, and logs live
	SourceDir string // Where AI session JSONL files are read from
	Port      int    // HTTP server port
	Interval  int    // Sync interval in seconds
}

// DefaultConfig returns a Config with sensible defaults.
func DefaultConfig() Config {
	home, _ := os.UserHomeDir()
	return Config{
		DataRoot:  filepath.Join(home, "dev", ".claude-usage"),
		SourceDir: filepath.Join(home, ".claude", "projects"),
		Port:      8765,
		Interval:  15,
	}
}
