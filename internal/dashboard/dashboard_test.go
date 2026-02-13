package dashboard

import (
	"context"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// C6: Validate embedded HTML structure
func TestEmbeddedHTMLValid(t *testing.T) {
	sub, err := fs.Sub(dashboardFS, "assets")
	require.NoError(t, err)

	f, err := sub.Open("index.html")
	require.NoError(t, err)
	defer f.Close()

	data, err := io.ReadAll(f)
	require.NoError(t, err)

	content := string(data)
	assert.True(t, strings.HasPrefix(strings.ToLower(content), "<!doctype html>"),
		"HTML should start with <!doctype html>")
	assert.True(t, strings.HasSuffix(strings.TrimSpace(content), "</html>"),
		"HTML should end with </html>")
	assert.Greater(t, len(data), 30000,
		"HTML should be at least 30KB to catch accidental truncation")
}

// C7: HTTP route integration tests
func TestServerRoutes(t *testing.T) {
	dataRoot := t.TempDir()

	// Create mock data files
	require.NoError(t, os.WriteFile(
		filepath.Join(dataRoot, "events.tsv"),
		[]byte("ts_epoch\tts_iso\n1234\t2025-01-01T00:00:00Z\n"),
		0644,
	))
	require.NoError(t, os.WriteFile(
		filepath.Join(dataRoot, "projects.json"),
		[]byte(`[{"slug":"test","path":"/test"}]`),
		0644,
	))

	srv := &Server{Port: 0, DataRoot: dataRoot}

	// Use port 0 for test — need to find a free port
	port := findFreePort(t)
	srv.Port = port

	require.NoError(t, srv.Start())
	defer srv.Stop(context.Background())

	// Give server time to start
	time.Sleep(50 * time.Millisecond)

	baseURL := fmt.Sprintf("http://127.0.0.1:%d", port)

	tests := []struct {
		name       string
		path       string
		wantStatus int
		wantBody   string
	}{
		{
			name:       "dashboard HTML served",
			path:       "/dashboard/index.html",
			wantStatus: http.StatusOK,
			wantBody:   "<!doctype html>",
		},
		{
			name:       "events.tsv from data root",
			path:       "/events.tsv",
			wantStatus: http.StatusOK,
			wantBody:   "ts_epoch",
		},
		{
			name:       "projects.json from data root",
			path:       "/projects.json",
			wantStatus: http.StatusOK,
			wantBody:   "test",
		},
		{
			name:       "nonexistent file returns 404",
			path:       "/nonexistent.txt",
			wantStatus: http.StatusNotFound,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			resp, err := http.Get(baseURL + tt.path)
			require.NoError(t, err)
			defer resp.Body.Close()

			assert.Equal(t, tt.wantStatus, resp.StatusCode)

			if tt.wantBody != "" {
				body, err := io.ReadAll(resp.Body)
				require.NoError(t, err)
				assert.Contains(t, strings.ToLower(string(body)), strings.ToLower(tt.wantBody))
			}
		})
	}
}

func findFreePort(t *testing.T) int {
	t.Helper()
	// Start from a high port range to avoid conflicts
	for port := 19876; port < 19900; port++ {
		conn, err := http.Get(fmt.Sprintf("http://127.0.0.1:%d", port))
		if err != nil {
			return port
		}
		conn.Body.Close()
	}
	t.Fatal("could not find free port")
	return 0
}
