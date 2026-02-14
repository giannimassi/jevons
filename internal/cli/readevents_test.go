package cli

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestReadEventsFromTSV(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		content    string
		wantCount  int
		wantErr    bool
		wantInput0 int64
	}{
		{
			name:      "empty file with header only",
			content:   "ts_epoch\tts_iso\tproject_slug\tsession_id\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature\n",
			wantCount: 0,
		},
		{
			name: "single event",
			content: "ts_epoch\tts_iso\tproject_slug\tsession_id\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature\n" +
				"1736937000\t2025-01-15T10:30:00Z\ttest\ts1\t100\t50\t20\t10\t150\t180\ttext\tsig\n",
			wantCount:  1,
			wantInput0: 100,
		},
		{
			name: "multiple events",
			content: "ts_epoch\tts_iso\tproject_slug\tsession_id\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature\n" +
				"1736937000\t2025-01-15T10:30:00Z\ttest\ts1\t100\t50\t20\t10\t150\t180\ttext\tsig1\n" +
				"1736937060\t2025-01-15T10:31:00Z\ttest\ts2\t200\t75\t30\t15\t275\t320\ttext\tsig2\n",
			wantCount:  2,
			wantInput0: 100,
		},
		{
			name: "skips blank lines",
			content: "header\n" +
				"\n" +
				"1736937000\t2025-01-15T10:30:00Z\ttest\ts1\t100\t50\t20\t10\t150\t180\ttext\tsig\n" +
				"\n",
			wantCount:  1,
			wantInput0: 100,
		},
		{
			name: "skips malformed lines",
			content: "header\n" +
				"bad\tdata\n" +
				"1736937000\t2025-01-15T10:30:00Z\ttest\ts1\t100\t50\t20\t10\t150\t180\ttext\tsig\n",
			wantCount:  1,
			wantInput0: 100,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			tmpDir := t.TempDir()
			path := filepath.Join(tmpDir, "events.tsv")
			require.NoError(t, os.WriteFile(path, []byte(tt.content), 0644))

			events, err := readEventsFromTSV(path)
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)
			assert.Len(t, events, tt.wantCount)

			if tt.wantCount > 0 {
				assert.Equal(t, tt.wantInput0, events[0].Input)
			}
		})
	}
}

func TestReadEventsFromTSV_FileNotFound(t *testing.T) {
	t.Parallel()

	_, err := readEventsFromTSV("/nonexistent/path/events.tsv")
	assert.Error(t, err)
}
