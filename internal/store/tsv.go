package store

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/OWNER/jevons/pkg/model"
)

// TSV header for events.tsv
const EventsTSVHeader = "ts_epoch\tts_iso\tproject_slug\tsession_id\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature"

// TSV header for live-events.tsv
const LiveEventsTSVHeader = "ts_epoch\tts_iso\tproject_slug\tsession_id\tprompt_preview\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature"

// MarshalTokenEvent serializes a TokenEvent to a TSV line.
func MarshalTokenEvent(e model.TokenEvent) string {
	return fmt.Sprintf("%d\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s",
		e.TSEpoch, e.TSISO, e.ProjectSlug, e.SessionID,
		e.Input, e.Output, e.CacheRead, e.CacheCreate,
		e.Billable, e.TotalWithCache, e.ContentType, e.Signature,
	)
}

// UnmarshalTokenEvent parses a TSV line into a TokenEvent.
func UnmarshalTokenEvent(line string) (model.TokenEvent, error) {
	fields := strings.Split(line, "\t")
	if len(fields) < 12 {
		return model.TokenEvent{}, fmt.Errorf("expected 12 fields, got %d", len(fields))
	}

	epoch, err := strconv.ParseInt(fields[0], 10, 64)
	if err != nil {
		return model.TokenEvent{}, fmt.Errorf("invalid ts_epoch: %w", err)
	}

	input, err := strconv.ParseInt(fields[4], 10, 64)
	if err != nil {
		return model.TokenEvent{}, fmt.Errorf("invalid input: %w", err)
	}

	output, err := strconv.ParseInt(fields[5], 10, 64)
	if err != nil {
		return model.TokenEvent{}, fmt.Errorf("invalid output: %w", err)
	}

	cacheRead, err := strconv.ParseInt(fields[6], 10, 64)
	if err != nil {
		return model.TokenEvent{}, fmt.Errorf("invalid cache_read: %w", err)
	}

	cacheCreate, err := strconv.ParseInt(fields[7], 10, 64)
	if err != nil {
		return model.TokenEvent{}, fmt.Errorf("invalid cache_create: %w", err)
	}

	billable, err := strconv.ParseInt(fields[8], 10, 64)
	if err != nil {
		return model.TokenEvent{}, fmt.Errorf("invalid billable: %w", err)
	}

	totalWithCache, err := strconv.ParseInt(fields[9], 10, 64)
	if err != nil {
		return model.TokenEvent{}, fmt.Errorf("invalid total_with_cache: %w", err)
	}

	return model.TokenEvent{
		TSEpoch:        epoch,
		TSISO:          fields[1],
		ProjectSlug:    fields[2],
		SessionID:      fields[3],
		Input:          input,
		Output:         output,
		CacheRead:      cacheRead,
		CacheCreate:    cacheCreate,
		Billable:       billable,
		TotalWithCache: totalWithCache,
		ContentType:    fields[10],
		Signature:      fields[11],
	}, nil
}

// MarshalLiveEvent serializes a LiveEvent to a TSV line.
func MarshalLiveEvent(e model.LiveEvent) string {
	return fmt.Sprintf("%d\t%s\t%s\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s",
		e.TSEpoch, e.TSISO, e.ProjectSlug, e.SessionID, e.PromptPreview,
		e.Input, e.Output, e.CacheRead, e.CacheCreate,
		e.Billable, e.TotalWithCache, e.ContentType, e.Signature,
	)
}
