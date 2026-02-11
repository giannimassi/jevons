package model

// TokenEvent represents a single token usage event from an AI session log.
// Fields match the TSV schema: ts_epoch, ts_iso, project_slug, session_id,
// input, output, cache_read, cache_create, billable, total_with_cache,
// content_type, signature.
type TokenEvent struct {
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

// LiveEvent extends TokenEvent with a prompt preview column.
type LiveEvent struct {
	TokenEvent
	PromptPreview string `json:"prompt_preview"`
}
