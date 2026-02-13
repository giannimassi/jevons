package sync

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/giannimassi/jevons/pkg/model"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func setupTestFixtures(t *testing.T, sourceDir string) {
	t.Helper()

	// Create project directory structure: sourceDir/<slug>/<session>.jsonl
	slug := "-Users-test-my-project"
	projectDir := filepath.Join(sourceDir, slug)
	require.NoError(t, os.MkdirAll(projectDir, 0755))

	// Session 1: basic events
	session1 := `{"cwd":"/Users/test/my-project","type":"user","message":{"role":"user","content":"Hello"},"timestamp":"2025-01-15T10:00:00.000Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hi!"}],"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20,"cache_creation_input_tokens":10}},"timestamp":"2025-01-15T10:00:10.000Z","isApiErrorMessage":false}
{"type":"user","message":{"role":"user","content":"Write code"},"timestamp":"2025-01-15T10:01:00.000Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Here's code"}],"usage":{"input_tokens":200,"output_tokens":150,"cache_read_input_tokens":40,"cache_creation_input_tokens":15}},"timestamp":"2025-01-15T10:01:10.000Z","isApiErrorMessage":false}
`
	require.NoError(t, os.WriteFile(filepath.Join(projectDir, "session-001.jsonl"), []byte(session1), 0644))

	// Session 2: different session
	session2 := `{"type":"user","message":{"role":"user","content":"Fix bug"},"timestamp":"2025-01-15T11:00:00.000Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Fixed!"}],"usage":{"input_tokens":300,"output_tokens":100,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}},"timestamp":"2025-01-15T11:00:05.000Z","isApiErrorMessage":false}
`
	require.NoError(t, os.WriteFile(filepath.Join(projectDir, "session-002.jsonl"), []byte(session2), 0644))
}

func TestSyncRun(t *testing.T) {
	tmpDir := t.TempDir()
	sourceDir := filepath.Join(tmpDir, "source")
	dataDir := filepath.Join(tmpDir, "data")

	setupTestFixtures(t, sourceDir)

	cfg := model.Config{
		DataRoot:  dataDir,
		SourceDir: sourceDir,
	}

	result, err := Run(cfg)
	require.NoError(t, err)

	assert.Equal(t, 2, result.SessionFiles)
	assert.Equal(t, 3, result.EventRows, "2 events from session-001 + 1 from session-002")
	assert.Equal(t, 3, result.LiveEventRows)
	assert.Equal(t, sourceDir, result.SourceRoot)

	// Verify events.tsv
	eventsData, err := os.ReadFile(filepath.Join(dataDir, "events.tsv"))
	require.NoError(t, err)
	lines := strings.Split(strings.TrimSpace(string(eventsData)), "\n")
	assert.Equal(t, 4, len(lines), "1 header + 3 data lines")
	assert.Contains(t, lines[0], "ts_epoch\tts_iso\tproject_slug")

	// Verify events are sorted by epoch
	// session-001 events at 10:00:10 and 10:01:10, session-002 at 11:00:05
	assert.Contains(t, lines[1], "session-001")
	assert.Contains(t, lines[2], "session-001")
	assert.Contains(t, lines[3], "session-002")

	// Verify live-events.tsv
	liveData, err := os.ReadFile(filepath.Join(dataDir, "live-events.tsv"))
	require.NoError(t, err)
	liveLines := strings.Split(strings.TrimSpace(string(liveData)), "\n")
	assert.Equal(t, 4, len(liveLines))
	assert.Contains(t, liveLines[0], "prompt_preview")

	// Verify projects.json
	projectsData, err := os.ReadFile(filepath.Join(dataDir, "projects.json"))
	require.NoError(t, err)
	var projects []struct {
		Slug string `json:"slug"`
		Path string `json:"path"`
	}
	require.NoError(t, json.Unmarshal(projectsData, &projects))
	assert.Len(t, projects, 1)
	assert.Equal(t, "-Users-test-my-project", projects[0].Slug)
	assert.Equal(t, "/Users/test/my-project", projects[0].Path, "should prefer cwd path over /unknown/")

	// Verify sync-status.json
	statusData, err := os.ReadFile(filepath.Join(dataDir, "sync-status.json"))
	require.NoError(t, err)
	var status map[string]interface{}
	require.NoError(t, json.Unmarshal(statusData, &status))
	assert.Equal(t, float64(2), status["session_files"])
	assert.Equal(t, float64(3), status["event_rows"])
}

func TestSyncIdempotent(t *testing.T) {
	tmpDir := t.TempDir()
	sourceDir := filepath.Join(tmpDir, "source")
	dataDir := filepath.Join(tmpDir, "data")

	setupTestFixtures(t, sourceDir)

	cfg := model.Config{
		DataRoot:  dataDir,
		SourceDir: sourceDir,
	}

	// Run sync twice
	result1, err := Run(cfg)
	require.NoError(t, err)

	result2, err := Run(cfg)
	require.NoError(t, err)

	// Should produce identical results
	assert.Equal(t, result1.EventRows, result2.EventRows, "re-sync should produce same event count")
	assert.Equal(t, result1.LiveEventRows, result2.LiveEventRows)

	// Verify no duplicate rows
	eventsData, err := os.ReadFile(filepath.Join(dataDir, "events.tsv"))
	require.NoError(t, err)
	lines := strings.Split(strings.TrimSpace(string(eventsData)), "\n")
	assert.Equal(t, 4, len(lines), "still 1 header + 3 data lines after re-sync")
}

// C13: Account JSON generation tests
func TestWriteAccountJSON(t *testing.T) {
	tests := []struct {
		name       string
		claudeJSON string
		wantFields []string
		wantEmpty  bool
	}{
		{
			name:      "missing claude.json writes empty object",
			wantEmpty: true,
		},
		{
			name:       "invalid JSON writes empty object",
			claudeJSON: `{not valid json`,
			wantEmpty:  true,
		},
		{
			name:       "no oauthAccount writes empty object",
			claudeJSON: `{"someOtherField": true}`,
			wantEmpty:  true,
		},
		{
			name:       "null oauthAccount writes empty object",
			claudeJSON: `{"oauthAccount": null}`,
			wantEmpty:  true,
		},
		{
			name: "valid oauthAccount extracts fields",
			claudeJSON: `{
				"oauthAccount": {
					"displayName": "Test User",
					"emailAddress": "test@example.com",
					"billingType": "pro",
					"accountUuid": "uuid-123"
				},
				"hasAvailableSubscription": true,
				"userID": "user-456"
			}`,
			wantFields: []string{"display_name", "email", "billing_type", "account_uuid", "generated_at"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tmpDir := t.TempDir()
			outPath := filepath.Join(tmpDir, "account.json")
			claudePath := filepath.Join(tmpDir, ".claude.json")

			if tt.claudeJSON != "" {
				require.NoError(t, os.WriteFile(claudePath, []byte(tt.claudeJSON), 0644))
			}

			writeAccountJSONFrom(outPath, claudePath)

			data, err := os.ReadFile(outPath)
			require.NoError(t, err)

			if tt.wantEmpty {
				assert.Equal(t, "{}\n", string(data))
				return
			}

			var result map[string]any
			require.NoError(t, json.Unmarshal(data, &result))
			for _, field := range tt.wantFields {
				assert.Contains(t, result, field, "should contain field %s", field)
			}

			// Verify specific values
			if tt.name == "valid oauthAccount extracts fields" {
				assert.Equal(t, "Test User", result["display_name"])
				assert.Equal(t, "test@example.com", result["email"])
				assert.Equal(t, "pro", result["billing_type"])
				assert.Equal(t, true, result["has_available_subscription"])
				assert.Equal(t, "user-456", result["user_id"])
			}
		})
	}
}

func TestSyncEmptySource(t *testing.T) {
	tmpDir := t.TempDir()
	dataDir := filepath.Join(tmpDir, "data")

	cfg := model.Config{
		DataRoot:  dataDir,
		SourceDir: filepath.Join(tmpDir, "nonexistent"),
	}

	result, err := Run(cfg)
	require.NoError(t, err)
	assert.Equal(t, 0, result.SessionFiles)
	assert.Equal(t, 0, result.EventRows)
}

// Issue 12: Non-.jsonl files are ignored by sync discovery
func TestSyncIgnoresNonJSONL(t *testing.T) {
	tmpDir := t.TempDir()
	sourceDir := filepath.Join(tmpDir, "source")
	dataDir := filepath.Join(tmpDir, "data")

	// Create a project dir with a non-.jsonl file
	projectDir := filepath.Join(sourceDir, "test-project")
	require.NoError(t, os.MkdirAll(projectDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(projectDir, "session.txt"), []byte("not jsonl"), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(projectDir, "notes.md"), []byte("# notes"), 0644))

	cfg := model.Config{DataRoot: dataDir, SourceDir: sourceDir}
	result, err := Run(cfg)
	require.NoError(t, err)
	assert.Equal(t, 0, result.SessionFiles, "non-.jsonl files should be ignored")
}
