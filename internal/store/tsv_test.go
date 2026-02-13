package store

import (
	"strings"
	"testing"

	"github.com/giannimassi/jevons/pkg/model"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMarshalUnmarshalTokenEvent(t *testing.T) {
	tests := []struct {
		name  string
		event model.TokenEvent
	}{
		{
			name: "basic event",
			event: model.TokenEvent{
				TSEpoch:        1736937000,
				TSISO:          "2025-01-15T10:30:00.123Z",
				ProjectSlug:    "test-project",
				SessionID:      "session-001",
				Input:          100,
				Output:         50,
				CacheRead:      20,
				CacheCreate:    10,
				Billable:       150,
				TotalWithCache: 180,
				ContentType:    "text",
				Signature:      "100|50|20|10",
			},
		},
		{
			name: "zero cache values",
			event: model.TokenEvent{
				TSEpoch:        1736937060,
				TSISO:          "2025-01-15T10:31:00Z",
				ProjectSlug:    "-Users-test-app",
				SessionID:      "abc123",
				Input:          300,
				Output:         100,
				CacheRead:      0,
				CacheCreate:    0,
				Billable:       400,
				TotalWithCache: 400,
				ContentType:    "tool_use",
				Signature:      "300|100|0|0",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			line := MarshalTokenEvent(tt.event)
			got, err := UnmarshalTokenEvent(line)
			require.NoError(t, err)
			assert.Equal(t, tt.event, got)
		})
	}
}

func TestUnmarshalTokenEventErrors(t *testing.T) {
	tests := []struct {
		name string
		line string
	}{
		{name: "too few fields", line: "1\t2\t3"},
		{name: "bad epoch", line: "abc\tiso\tslug\tsid\t1\t2\t3\t4\t5\t6\ttype\tsig"},
		{name: "bad input", line: "1\tiso\tslug\tsid\tabc\t2\t3\t4\t5\t6\ttype\tsig"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := UnmarshalTokenEvent(tt.line)
			assert.Error(t, err)
		})
	}
}

func TestMarshalLiveEvent(t *testing.T) {
	e := model.LiveEvent{
		TokenEvent: model.TokenEvent{
			TSEpoch:        1736937000,
			TSISO:          "2025-01-15T10:30:00Z",
			ProjectSlug:    "test",
			SessionID:      "s1",
			Input:          100,
			Output:         50,
			CacheRead:      20,
			CacheCreate:    10,
			Billable:       150,
			TotalWithCache: 180,
			ContentType:    "text",
			Signature:      "100|50|20|10",
		},
		PromptPreview: "Hello world",
	}

	line := MarshalLiveEvent(e)
	assert.Contains(t, line, "Hello world")
	assert.Contains(t, line, "1736937000")
}

// C9: Validate TSV header format matches shell script exactly
func TestTSVHeaderFormat(t *testing.T) {
	// Shell script expected headers (from claude-usage-tracker.sh lines ~510-515)
	shellEventsHeader := "ts_epoch\tts_iso\tproject_slug\tsession_id\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature"
	shellLiveHeader := "ts_epoch\tts_iso\tproject_slug\tsession_id\tprompt_preview\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature"

	assert.Equal(t, shellEventsHeader, EventsTSVHeader, "events.tsv header must match shell script")
	assert.Equal(t, shellLiveHeader, LiveEventsTSVHeader, "live-events.tsv header must match shell script")

	// Verify field counts
	eventsFields := strings.Split(EventsTSVHeader, "\t")
	assert.Len(t, eventsFields, 12, "events.tsv should have 12 columns")

	liveFields := strings.Split(LiveEventsTSVHeader, "\t")
	assert.Len(t, liveFields, 13, "live-events.tsv should have 13 columns")

	// Verify prompt_preview is the 5th field (index 4) in live-events
	assert.Equal(t, "prompt_preview", liveFields[4], "prompt_preview should be 5th column in live-events")
}

// C12: Validate billable = input + output and totalWithCache = billable + cache_read + cache_create
func TestBillableCalculation(t *testing.T) {
	tests := []struct {
		name        string
		input       int64
		output      int64
		cacheRead   int64
		cacheCreate int64
	}{
		{name: "basic", input: 100, output: 50, cacheRead: 20, cacheCreate: 10},
		{name: "zero cache", input: 300, output: 100, cacheRead: 0, cacheCreate: 0},
		{name: "large values", input: 50000, output: 25000, cacheRead: 100000, cacheCreate: 5000},
		{name: "all zero", input: 0, output: 0, cacheRead: 0, cacheCreate: 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := model.TokenEvent{
				TSEpoch:        1736937000,
				TSISO:          "2025-01-15T10:30:00Z",
				ProjectSlug:    "test",
				SessionID:      "s1",
				Input:          tt.input,
				Output:         tt.output,
				CacheRead:      tt.cacheRead,
				CacheCreate:    tt.cacheCreate,
				Billable:       tt.input + tt.output,
				TotalWithCache: tt.input + tt.output + tt.cacheRead + tt.cacheCreate,
				ContentType:    "text",
				Signature:      "sig",
			}

			// Marshal and unmarshal to verify calculation survives round-trip
			line := MarshalTokenEvent(e)
			got, err := UnmarshalTokenEvent(line)
			require.NoError(t, err)

			assert.Equal(t, got.Input+got.Output, got.Billable,
				"billable must equal input + output")
			assert.Equal(t, got.Billable+got.CacheRead+got.CacheCreate, got.TotalWithCache,
				"total_with_cache must equal billable + cache_read + cache_create")
		})
	}
}
