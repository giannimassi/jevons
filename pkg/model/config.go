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
// Respects CLAUDE_USAGE_DATA_DIR and CLAUDE_USAGE_SOURCE_DIR environment variables.
func DefaultConfig() Config {
	home, _ := os.UserHomeDir()

	dataRoot := os.Getenv("CLAUDE_USAGE_DATA_DIR")
	if dataRoot == "" {
		dataRoot = filepath.Join(home, "dev", ".claude-usage")
	}

	sourceDir := os.Getenv("CLAUDE_USAGE_SOURCE_DIR")
	if sourceDir == "" {
		sourceDir = filepath.Join(home, ".claude", "projects")
	}

	return Config{
		DataRoot:  dataRoot,
		SourceDir: sourceDir,
		Port:      8765,
		Interval:  15,
	}
}
