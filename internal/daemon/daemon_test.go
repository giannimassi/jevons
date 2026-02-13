package daemon

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestDaemonRunAndHeartbeat(t *testing.T) {
	tmpDir := t.TempDir()

	var syncCount atomic.Int32
	d := &Daemon{
		Interval: 1,
		DataRoot: tmpDir,
		SyncFn: func() error {
			syncCount.Add(1)
			return nil
		},
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2500*time.Millisecond)
	defer cancel()

	err := d.Run(ctx)
	require.NoError(t, err)

	// Should have run sync at least twice (immediate + ticker)
	assert.GreaterOrEqual(t, syncCount.Load(), int32(2))

	// Heartbeat file should exist with "ok" status
	hb := ReadHeartbeatState(tmpDir)
	require.NotNil(t, hb)
	assert.Equal(t, "ok", hb.Status)

	// PID file should be cleaned up after Run exits
	_, err = os.ReadFile(filepath.Join(tmpDir, "pids", "sync.pid"))
	assert.True(t, os.IsNotExist(err), "PID file should be removed after daemon stops")
}

func TestReadHeartbeatState(t *testing.T) {
	tests := []struct {
		name     string
		content  string
		wantNil  bool
		wantMode string
	}{
		{
			name:    "no file",
			wantNil: true,
		},
		{
			name:    "invalid format",
			content: "garbage",
			wantNil: true,
		},
		{
			name:     "valid recent heartbeat",
			content:  "", // will be set dynamically
			wantMode: "running",
		},
		{
			name:     "stale heartbeat",
			content:  "1000000000,15,12345,ok\n",
			wantMode: "stale",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpDir := t.TempDir()
			hbDir := filepath.Join(tmpDir, "heartbeat")
			require.NoError(t, os.MkdirAll(hbDir, 0755))

			if tt.content != "" {
				require.NoError(t, os.WriteFile(filepath.Join(hbDir, "sync.txt"), []byte(tt.content), 0644))
			} else if tt.wantMode == "running" {
				// Write a fresh heartbeat
				now := time.Now().Unix()
				content := []byte(fmt.Sprintf("%d,15,%d,ok\n", now, os.Getpid()))
				require.NoError(t, os.WriteFile(filepath.Join(hbDir, "sync.txt"), content, 0644))
			}

			hb := ReadHeartbeatState(tmpDir)
			if tt.wantNil {
				assert.Nil(t, hb)
				return
			}
			require.NotNil(t, hb)
			assert.Equal(t, tt.wantMode, hb.Mode)
		})
	}
}

func TestEnsureDataDirs(t *testing.T) {
	tmpDir := t.TempDir()
	dataRoot := filepath.Join(tmpDir, "data")

	require.NoError(t, EnsureDataDirs(dataRoot))

	for _, sub := range []string{"", "pids", "logs", "heartbeat", "web", "dashboard"} {
		info, err := os.Stat(filepath.Join(dataRoot, sub))
		require.NoError(t, err, "dir %s should exist", sub)
		assert.True(t, info.IsDir())
	}
}
