package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/giannimassi/jevons/pkg/model"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGraphCmdHelp(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		want string
	}{
		{"mentions ASCII", "ASCII"},
		{"metric flag", "--metric"},
		{"range flag", "--range"},
		{"points flag", "--points"},
		{"bucket flag", "--bucket"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			cmd := NewRootCmd()
			buf := new(bytes.Buffer)
			cmd.SetOut(buf)
			cmd.SetErr(buf)
			cmd.SetArgs([]string{"graph", "--help"})

			err := cmd.Execute()
			require.NoError(t, err)
			assert.Contains(t, buf.String(), tt.want)
		})
	}
}

func TestGraphCmdFlags(t *testing.T) {
	t.Parallel()

	cmd := newGraphCmd()

	tests := []struct {
		name     string
		flag     string
		defValue string
	}{
		{"metric", "metric", "billable"},
		{"range", "range", "24h"},
		{"points", "points", "80"},
		{"bucket", "bucket", "900"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			f := cmd.Flags().Lookup(tt.flag)
			require.NotNil(t, f, "flag %q should exist", tt.flag)
			assert.Equal(t, tt.defValue, f.DefValue)
		})
	}
}

func TestGraphCmdMissingEventsFile(t *testing.T) {
	tmpDir := t.TempDir()
	t.Setenv("CLAUDE_USAGE_DATA_DIR", tmpDir)

	cmd := NewRootCmd()
	cmd.SetArgs([]string{"graph"})

	err := cmd.Execute()
	assert.Error(t, err)
}

func TestGraphCmdNoDataInRange(t *testing.T) {
	tmpDir := t.TempDir()
	t.Setenv("CLAUDE_USAGE_DATA_DIR", tmpDir)

	eventsPath := filepath.Join(tmpDir, "events.tsv")
	header := "ts_epoch\tts_iso\tproject_slug\tsession_id\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature\n"
	require.NoError(t, os.WriteFile(eventsPath, []byte(header), 0644))

	out := captureStdout(t, func() {
		cmd := NewRootCmd()
		cmd.SetArgs([]string{"graph", "--range", "all"})
		err := cmd.Execute()
		require.NoError(t, err)
	})

	assert.Contains(t, out, "No data")
}

func TestMetricValue(t *testing.T) {
	t.Parallel()

	e := model.TokenEvent{
		Input:          100,
		Output:         50,
		CacheRead:      20,
		CacheCreate:    10,
		Billable:       150,
		TotalWithCache: 180,
	}

	tests := []struct {
		metric string
		want   int64
	}{
		{"input", 100},
		{"output", 50},
		{"cache_read", 20},
		{"cache_create", 10},
		{"billable", 150},
		{"total_with_cache", 180},
		{"unknown_metric", 150}, // defaults to billable
	}

	for _, tt := range tests {
		t.Run(tt.metric, func(t *testing.T) {
			t.Parallel()
			assert.Equal(t, tt.want, metricValue(e, tt.metric))
		})
	}
}
