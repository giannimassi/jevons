package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestTotalCmdHelp(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		want string
	}{
		{"mentions JSON", "JSON"},
		{"range flag", "--range"},
		{"mentions totals", "totals"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			cmd := NewRootCmd()
			buf := new(bytes.Buffer)
			cmd.SetOut(buf)
			cmd.SetErr(buf)
			cmd.SetArgs([]string{"total", "--help"})

			err := cmd.Execute()
			require.NoError(t, err)
			assert.Contains(t, buf.String(), tt.want)
		})
	}
}

func TestTotalCmdFlags(t *testing.T) {
	t.Parallel()

	cmd := newTotalCmd()

	rangeFlag := cmd.Flags().Lookup("range")
	require.NotNil(t, rangeFlag)
	assert.Equal(t, "24h", rangeFlag.DefValue)
}

func TestTotalCmdMissingEventsFile(t *testing.T) {
	tmpDir := t.TempDir()
	t.Setenv("CLAUDE_USAGE_DATA_DIR", tmpDir)

	cmd := NewRootCmd()
	cmd.SetArgs([]string{"total"})

	err := cmd.Execute()
	assert.Error(t, err)
}

func TestTotalCmdWithEvents(t *testing.T) {
	tmpDir := t.TempDir()
	t.Setenv("CLAUDE_USAGE_DATA_DIR", tmpDir)

	eventsPath := filepath.Join(tmpDir, "events.tsv")
	header := "ts_epoch\tts_iso\tproject_slug\tsession_id\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature\n"
	row := "9999999999\t2286-11-20T17:46:39Z\ttest\ts1\t100\t50\t20\t10\t150\t180\ttext\tsig\n"
	require.NoError(t, os.WriteFile(eventsPath, []byte(header+row), 0644))

	// total writes JSON to os.Stdout via json.NewEncoder(os.Stdout)
	out := captureStdout(t, func() {
		cmd := NewRootCmd()
		cmd.SetArgs([]string{"total", "--range", "all"})
		err := cmd.Execute()
		require.NoError(t, err)
	})

	assert.Contains(t, out, `"events": 1`)
	assert.Contains(t, out, `"input": 100`)
	assert.Contains(t, out, `"output": 50`)
	assert.Contains(t, out, `"billable": 150`)
}

func TestTotalCmdInvalidRange(t *testing.T) {
	tmpDir := t.TempDir()
	t.Setenv("CLAUDE_USAGE_DATA_DIR", tmpDir)

	eventsPath := filepath.Join(tmpDir, "events.tsv")
	require.NoError(t, os.WriteFile(eventsPath, []byte("header\n"), 0644))

	cmd := NewRootCmd()
	cmd.SetArgs([]string{"total", "--range", "bogus"})

	err := cmd.Execute()
	assert.Error(t, err)
}
