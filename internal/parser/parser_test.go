package parser

import (
	"path/filepath"
	"runtime"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func testdataPath(name string) string {
	_, file, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(file), "testdata", name)
}

func TestParseSessionFile(t *testing.T) {
	tests := []struct {
		name        string
		fixture     string
		slug        string
		sessionID   string
		wantCount   int
		wantErr     bool
		checkEvents func(t *testing.T, events []TokenEventResult)
	}{
		{
			name:      "basic session with two events",
			fixture:   "basic_session.jsonl",
			slug:      "test-project",
			sessionID: "session-001",
			wantCount: 2,
			checkEvents: func(t *testing.T, events []TokenEventResult) {
				e0 := events[0]
				assert.Equal(t, int64(100), e0.Input)
				assert.Equal(t, int64(50), e0.Output)
				assert.Equal(t, int64(20), e0.CacheRead)
				assert.Equal(t, int64(10), e0.CacheCreate)
				assert.Equal(t, int64(150), e0.Billable, "billable = input + output")
				assert.Equal(t, int64(180), e0.TotalWithCache, "total = input + output + cache_read + cache_create")
				assert.Equal(t, "100|50|20|10", e0.Signature)
				assert.Equal(t, "text", e0.ContentType)
				assert.Equal(t, "test-project", e0.ProjectSlug)
				assert.Equal(t, "session-001", e0.SessionID)
				assert.Equal(t, "2025-01-15T10:30:00.123Z", e0.TSISO)
				assert.NotZero(t, e0.TSEpoch)

				e1 := events[1]
				assert.Equal(t, int64(200), e1.Input)
				assert.Equal(t, int64(150), e1.Output)
				assert.Equal(t, "200|150|40|15", e1.Signature)
			},
		},
		{
			name:      "tool use session",
			fixture:   "tool_use_session.jsonl",
			slug:      "tool-project",
			sessionID: "session-002",
			wantCount: 2,
			checkEvents: func(t *testing.T, events []TokenEventResult) {
				assert.Equal(t, "tool_use", events[0].ContentType)
				assert.Equal(t, "text", events[1].ContentType)
				// Second assistant response should still emit because tool_result
				// user message is NOT a human prompt (all tool_result), so pending_human stays false.
				// But the signature differs (300|80|50|0 vs 400|120|60|5), so it emits anyway.
				assert.Equal(t, int64(300), events[0].Input)
				assert.Equal(t, int64(400), events[1].Input)
			},
		},
		{
			name:      "empty session",
			fixture:   "empty_session.jsonl",
			slug:      "empty",
			sessionID: "session-003",
			wantCount: 0,
		},
		{
			name:      "malformed session skips bad lines",
			fixture:   "malformed_session.jsonl",
			slug:      "malformed",
			sessionID: "session-004",
			wantCount: 1,
			checkEvents: func(t *testing.T, events []TokenEventResult) {
				// Only the valid assistant line should be parsed
				assert.Equal(t, int64(50), events[0].Input)
				assert.Equal(t, int64(25), events[0].Output)
			},
		},
		{
			name:      "duplicate signature dedup",
			fixture:   "duplicate_sig_session.jsonl",
			slug:      "dedup",
			sessionID: "session-005",
			wantCount: 2,
			checkEvents: func(t *testing.T, events []TokenEventResult) {
				// First event: emitted (first occurrence after human prompt)
				assert.Equal(t, "100|50|20|10", events[0].Signature)
				// Second assistant with same sig, no human between → SKIPPED
				// Third assistant with same sig, but human spoke → EMITTED
				assert.Equal(t, "100|50|20|10", events[1].Signature)
				// Timestamps should differ
				assert.NotEqual(t, events[0].TSISO, events[1].TSISO)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			events, err := ParseSessionFile(testdataPath(tt.fixture), tt.slug, tt.sessionID)
			if tt.wantErr {
				require.Error(t, err)
				return
			}
			require.NoError(t, err)
			assert.Len(t, events, tt.wantCount)
			if tt.checkEvents != nil && len(events) == tt.wantCount {
				results := make([]TokenEventResult, len(events))
				for i, e := range events {
					results[i] = TokenEventResult(e)
				}
				tt.checkEvents(t, results)
			}
		})
	}
}

// TokenEventResult is an alias for readable test assertions.
type TokenEventResult = struct {
	TSEpoch        int64  `json:"ts_epoch"`
	TSISO          string `json:"ts_iso"`
	ProjectSlug    string `json:"project_slug"`
	SessionID      string `json:"session_id"`
	Input          int64  `json:"input"`
	Output         int64  `json:"output"`
	CacheRead      int64  `json:"cache_read"`
	CacheCreate    int64  `json:"cache_create"`
	Billable       int64  `json:"billable"`
	TotalWithCache int64  `json:"total_with_cache"`
	ContentType    string `json:"content_type"`
	Signature      string `json:"signature"`
}

func TestParseSessionFileLive(t *testing.T) {
	tests := []struct {
		name      string
		fixture   string
		slug      string
		sessionID string
		wantCount int
		checkFn   func(t *testing.T, events []liveEventResult)
	}{
		{
			name:      "basic session captures prompt previews",
			fixture:   "basic_session.jsonl",
			slug:      "test-project",
			sessionID: "session-001",
			wantCount: 2,
			checkFn: func(t *testing.T, events []liveEventResult) {
				assert.Equal(t, "Hello, help me with Go", events[0].PromptPreview)
				assert.Equal(t, "Now write tests", events[1].PromptPreview)
			},
		},
		{
			name:      "tool use session prompt previews",
			fixture:   "tool_use_session.jsonl",
			slug:      "tool-project",
			sessionID: "session-002",
			wantCount: 2,
			checkFn: func(t *testing.T, events []liveEventResult) {
				assert.Equal(t, "Read this file", events[0].PromptPreview)
				// tool_result message is not a human prompt, so preview stays same
				assert.Equal(t, "Read this file", events[1].PromptPreview)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			events, err := ParseSessionFileLive(testdataPath(tt.fixture), tt.slug, tt.sessionID)
			require.NoError(t, err)
			assert.Len(t, events, tt.wantCount)
			if tt.checkFn != nil && len(events) == tt.wantCount {
				results := make([]liveEventResult, len(events))
				for i, e := range events {
					results[i] = liveEventResult{
						TokenEventResult: TokenEventResult(e.TokenEvent),
						PromptPreview:    e.PromptPreview,
					}
				}
				tt.checkFn(t, results)
			}
		})
	}
}

type liveEventResult struct {
	TokenEventResult
	PromptPreview string
}

func TestExtractProjectPath(t *testing.T) {
	tests := []struct {
		name    string
		fixture string
		want    string
	}{
		{
			name:    "session with cwd",
			fixture: "cwd_session.jsonl",
			want:    "/Users/test/projects/my-app",
		},
		{
			name:    "session without cwd",
			fixture: "basic_session.jsonl",
			want:    "",
		},
		{
			name:    "empty session",
			fixture: "empty_session.jsonl",
			want:    "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ExtractProjectPath(testdataPath(tt.fixture))
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestParseEpoch(t *testing.T) {
	tests := []struct {
		name string
		ts   string
		want int64
	}{
		{name: "with fractional Z", ts: "2025-01-15T10:30:00.123Z", want: 1736937000},
		{name: "without fractional", ts: "2025-01-15T10:30:00Z", want: 1736937000},
		{name: "with timezone offset", ts: "2025-01-15T11:30:00.456+01:00", want: 1736937000},
		{name: "empty string", ts: "", want: 0},
		{name: "invalid", ts: "not-a-date", want: 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseEpoch(tt.ts)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestIsHumanPrompt(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want bool
	}{
		{name: "string content", raw: `"hello"`, want: true},
		{name: "text block", raw: `[{"type":"text","text":"hello"}]`, want: true},
		{name: "all tool_result", raw: `[{"type":"tool_result","tool_use_id":"t1","content":"data"}]`, want: false},
		{name: "mixed content", raw: `[{"type":"text","text":"hi"},{"type":"tool_result","tool_use_id":"t1","content":"data"}]`, want: true},
		{name: "empty array", raw: `[]`, want: true},
		{name: "null", raw: `null`, want: true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := isHumanPrompt([]byte(tt.raw))
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestCleanText(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{name: "tabs and newlines", input: "hello\tworld\nfoo", want: "hello world foo"},
		{name: "multiple spaces", input: "hello   world", want: "hello world"},
		{name: "leading trailing", input: "  hello  ", want: "hello"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.want, cleanText(tt.input))
		})
	}
}
