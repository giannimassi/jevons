package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDoctorCmdHelp(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		want string
	}{
		{"mentions environment", "environment"},
		{"fix flag", "--fix"},
		{"mentions diagnostic", "diagnostic"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			cmd := NewRootCmd()
			buf := new(bytes.Buffer)
			cmd.SetOut(buf)
			cmd.SetErr(buf)
			cmd.SetArgs([]string{"doctor", "--help"})

			err := cmd.Execute()
			require.NoError(t, err)
			assert.Contains(t, buf.String(), tt.want)
		})
	}
}

func TestDoctorCmdFlags(t *testing.T) {
	t.Parallel()

	cmd := newDoctorCmd()

	fixFlag := cmd.Flags().Lookup("fix")
	require.NotNil(t, fixFlag)
	assert.Equal(t, "false", fixFlag.DefValue)
}

func TestDoctorCmdRuns(t *testing.T) {
	tmpDir := t.TempDir()
	t.Setenv("CLAUDE_USAGE_DATA_DIR", tmpDir)
	t.Setenv("CLAUDE_USAGE_SOURCE_DIR", filepath.Join(tmpDir, "source"))

	out := captureStdout(t, func() {
		cmd := NewRootCmd()
		cmd.SetArgs([]string{"doctor"})
		err := cmd.Execute()
		require.NoError(t, err)
	})

	assert.Contains(t, out, "Source dir:")
	assert.Contains(t, out, "Data dir:")
}

func TestDoctorCmdWithExistingDirs(t *testing.T) {
	tmpDir := t.TempDir()
	sourceDir := filepath.Join(tmpDir, "source")
	dataDir := filepath.Join(tmpDir, "data")
	require.NoError(t, os.MkdirAll(sourceDir, 0755))
	require.NoError(t, os.MkdirAll(dataDir, 0755))
	// Create events.tsv so all core checks pass
	require.NoError(t, os.WriteFile(filepath.Join(dataDir, "events.tsv"), []byte("header\n"), 0644))

	t.Setenv("CLAUDE_USAGE_DATA_DIR", dataDir)
	t.Setenv("CLAUDE_USAGE_SOURCE_DIR", sourceDir)

	out := captureStdout(t, func() {
		cmd := NewRootCmd()
		cmd.SetArgs([]string{"doctor"})
		err := cmd.Execute()
		require.NoError(t, err)
	})

	assert.Contains(t, out, "[OK]")
	assert.Contains(t, out, "All checks passed")
}

func TestDoctorCmdFixCreatesDataDir(t *testing.T) {
	tmpDir := t.TempDir()
	dataDir := filepath.Join(tmpDir, "nonexistent-data")
	t.Setenv("CLAUDE_USAGE_DATA_DIR", dataDir)
	t.Setenv("CLAUDE_USAGE_SOURCE_DIR", filepath.Join(tmpDir, "source"))

	out := captureStdout(t, func() {
		cmd := NewRootCmd()
		cmd.SetArgs([]string{"doctor", "--fix"})
		err := cmd.Execute()
		require.NoError(t, err)
	})

	assert.Contains(t, out, "[FIXED]")

	// Verify directory was created
	info, err := os.Stat(dataDir)
	require.NoError(t, err)
	assert.True(t, info.IsDir())
}
