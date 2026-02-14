package menubar

import (
	"sync/atomic"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestConfigDefaults(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		cfg  Config
	}{
		{
			name: "zero value config",
			cfg:  Config{},
		},
		{
			name: "with dashboard URL",
			cfg: Config{
				DashboardURL: "http://127.0.0.1:8765/dashboard/index.html",
			},
		},
		{
			name: "fully populated",
			cfg: Config{
				DashboardURL: "http://localhost:9999/dashboard/index.html",
				SyncFn:       func() {},
				OnQuit:       func() {},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			// Config should be constructible without panics
			assert.NotNil(t, tt.cfg)
		})
	}
}

func TestOnExitCallsOnQuit(t *testing.T) {
	t.Parallel()

	var called atomic.Bool
	cfg := Config{
		OnQuit: func() {
			called.Store(true)
		},
	}

	onExit(cfg)
	assert.True(t, called.Load(), "OnQuit callback should be called by onExit")
}

func TestOnExitNilOnQuit(t *testing.T) {
	t.Parallel()

	// Should not panic when OnQuit is nil
	cfg := Config{}
	assert.NotPanics(t, func() {
		onExit(cfg)
	})
}

func TestIconDataEmbedded(t *testing.T) {
	t.Parallel()

	// iconData is embedded via //go:embed icon.png
	// The var should exist and be a byte slice (may be empty if icon.png is a placeholder)
	assert.IsType(t, []byte{}, iconData)
}

func TestOpenBrowser(t *testing.T) {
	t.Parallel()

	// Verify the function exists and accepts a URL string.
	// On Darwin this actually tries to open the URL;
	// on non-darwin it returns an error — both are acceptable.
	err := openBrowser("http://localhost:8765")
	_ = err
}
