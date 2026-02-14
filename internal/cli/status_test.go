package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestStatusCmdHelp(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		want string
	}{
		{"mentions sync", "sync"},
		{"mentions daemon", "daemon"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			cmd := NewRootCmd()
			buf := new(bytes.Buffer)
			cmd.SetOut(buf)
			cmd.SetErr(buf)
			cmd.SetArgs([]string{"status", "--help"})

			err := cmd.Execute()
			require.NoError(t, err)
			assert.Contains(t, buf.String(), tt.want)
		})
	}
}

func TestStatusCmdRuns(t *testing.T) {
	tmpDir := t.TempDir()
	t.Setenv("CLAUDE_USAGE_DATA_DIR", tmpDir)

	// status command writes to os.Stdout via fmt.Printf
	// Capture stdout to verify output
	out := captureStdout(t, func() {
		cmd := NewRootCmd()
		cmd.SetArgs([]string{"status"})
		err := cmd.Execute()
		require.NoError(t, err)
	})

	assert.Contains(t, out, "sync_status=stopped")
	assert.Contains(t, out, "sync_heartbeat=none")
	assert.Contains(t, out, "events_file=")
}

func TestStatusCmdWithSyncStatus(t *testing.T) {
	tmpDir := t.TempDir()
	t.Setenv("CLAUDE_USAGE_DATA_DIR", tmpDir)

	// Write sync-status.json
	statusJSON := `{"last_sync":"2025-01-15T10:30:00Z","status":"ok"}`
	require.NoError(t, os.WriteFile(filepath.Join(tmpDir, "sync-status.json"), []byte(statusJSON), 0644))

	out := captureStdout(t, func() {
		cmd := NewRootCmd()
		cmd.SetArgs([]string{"status"})
		err := cmd.Execute()
		require.NoError(t, err)
	})

	assert.Contains(t, out, "sync_last_status_json=")
	assert.Contains(t, out, "last_sync")
}
