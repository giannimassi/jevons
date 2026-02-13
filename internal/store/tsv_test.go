package store

import (
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
