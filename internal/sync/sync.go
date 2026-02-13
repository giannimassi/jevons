package sync

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/giannimassi/jevons/internal/parser"
	"github.com/giannimassi/jevons/internal/store"
	"github.com/giannimassi/jevons/pkg/model"
)

// Result contains the outcome of a sync operation.
type Result struct {
	SessionFiles  int
	EventRows     int
	LiveEventRows int
	SourceRoot    string
}

// Run executes the full sync pipeline.
func Run(cfg model.Config) (*Result, error) {
	if err := ensureDataDirs(cfg.DataRoot); err != nil {
		return nil, fmt.Errorf("create data dirs: %w", err)
	}

	sessionFiles, err := discoverSessionFiles(cfg.SourceDir)
	if err != nil {
		return nil, fmt.Errorf("discover sessions: %w", err)
	}

	var allEvents []model.TokenEvent
	var allLiveEvents []model.LiveEvent

	var projects []projectEntry

	for _, sf := range sessionFiles {
		slug := filepath.Base(filepath.Dir(sf))
		sessionID := strings.TrimSuffix(filepath.Base(sf), ".jsonl")

		projectPath := parser.ExtractProjectPath(sf)
		if projectPath == "" {
			projectPath = fmt.Sprintf("/unknown/%s", slug)
		}
		projects = append(projects, projectEntry{Slug: slug, Path: projectPath})

		events, err := parser.ParseSessionFile(sf, slug, sessionID)
		if err != nil {
			continue
		}
		allEvents = append(allEvents, events...)

		liveEvents, err := parser.ParseSessionFileLive(sf, slug, sessionID)
		if err != nil {
			continue
		}
		allLiveEvents = append(allLiveEvents, liveEvents...)
	}

	// Sort events (stable for deterministic output with equal keys)
	sort.SliceStable(allEvents, func(i, j int) bool {
		a, b := allEvents[i], allEvents[j]
		if a.TSEpoch != b.TSEpoch {
			return a.TSEpoch < b.TSEpoch
		}
		if a.TSISO != b.TSISO {
			return a.TSISO < b.TSISO
		}
		if a.ProjectSlug != b.ProjectSlug {
			return a.ProjectSlug < b.ProjectSlug
		}
		if a.SessionID != b.SessionID {
			return a.SessionID < b.SessionID
		}
		return a.Signature < b.Signature
	})
	allEvents = dedupEvents(allEvents)

	sort.SliceStable(allLiveEvents, func(i, j int) bool {
		a, b := allLiveEvents[i], allLiveEvents[j]
		if a.TSEpoch != b.TSEpoch {
			return a.TSEpoch < b.TSEpoch
		}
		if a.TSISO != b.TSISO {
			return a.TSISO < b.TSISO
		}
		if a.ProjectSlug != b.ProjectSlug {
			return a.ProjectSlug < b.ProjectSlug
		}
		if a.SessionID != b.SessionID {
			return a.SessionID < b.SessionID
		}
		return a.Signature < b.Signature
	})
	allLiveEvents = dedupLiveEvents(allLiveEvents)

	if err := writeEventsTSV(filepath.Join(cfg.DataRoot, "events.tsv"), allEvents); err != nil {
		return nil, fmt.Errorf("write events.tsv: %w", err)
	}
	if err := writeLiveEventsTSV(filepath.Join(cfg.DataRoot, "live-events.tsv"), allLiveEvents); err != nil {
		return nil, fmt.Errorf("write live-events.tsv: %w", err)
	}
	if err := writeProjectsJSON(filepath.Join(cfg.DataRoot, "projects.json"), projects); err != nil {
		return nil, fmt.Errorf("write projects.json: %w", err)
	}

	writeAccountJSON(filepath.Join(cfg.DataRoot, "account.json"))

	now := time.Now()
	result := &Result{
		SessionFiles:  len(sessionFiles),
		EventRows:     len(allEvents),
		LiveEventRows: len(allLiveEvents),
		SourceRoot:    cfg.SourceDir,
	}
	if err := writeSyncStatus(filepath.Join(cfg.DataRoot, "sync-status.json"), now, result); err != nil {
		return nil, fmt.Errorf("write sync-status.json: %w", err)
	}

	return result, nil
}

func ensureDataDirs(dataRoot string) error {
	for _, sub := range []string{"", "pids", "logs", "heartbeat", "web", "dashboard"} {
		if err := os.MkdirAll(filepath.Join(dataRoot, sub), 0755); err != nil {
			return err
		}
	}
	return nil
}

func discoverSessionFiles(sourceDir string) ([]string, error) {
	if _, err := os.Stat(sourceDir); os.IsNotExist(err) {
		return nil, nil
	}

	pattern := filepath.Join(sourceDir, "*", "*.jsonl")
	matches, err := filepath.Glob(pattern)
	if err != nil {
		return nil, err
	}
	sort.Strings(matches)
	return matches, nil
}

func dedupEvents(events []model.TokenEvent) []model.TokenEvent {
	if len(events) == 0 {
		return events
	}
	seen := make(map[string]bool)
	result := make([]model.TokenEvent, 0, len(events))
	for _, e := range events {
		line := store.MarshalTokenEvent(e)
		if !seen[line] {
			seen[line] = true
			result = append(result, e)
		}
	}
	return result
}

func dedupLiveEvents(events []model.LiveEvent) []model.LiveEvent {
	if len(events) == 0 {
		return events
	}
	seen := make(map[string]bool)
	result := make([]model.LiveEvent, 0, len(events))
	for _, e := range events {
		line := store.MarshalLiveEvent(e)
		if !seen[line] {
			seen[line] = true
			result = append(result, e)
		}
	}
	return result
}

// atomicWriteFile writes data to a temp file then renames atomically (matching shell behavior).
func atomicWriteFile(path string, data []byte) error {
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func writeEventsTSV(path string, events []model.TokenEvent) error {
	var b strings.Builder
	b.WriteString(store.EventsTSVHeader)
	b.WriteByte('\n')
	for _, e := range events {
		b.WriteString(store.MarshalTokenEvent(e))
		b.WriteByte('\n')
	}
	return atomicWriteFile(path, []byte(b.String()))
}

func writeLiveEventsTSV(path string, events []model.LiveEvent) error {
	var b strings.Builder
	b.WriteString(store.LiveEventsTSVHeader)
	b.WriteByte('\n')
	for _, e := range events {
		b.WriteString(store.MarshalLiveEvent(e))
		b.WriteByte('\n')
	}
	return atomicWriteFile(path, []byte(b.String()))
}

func writeProjectsJSON(path string, entries []projectEntry) error {
	if len(entries) == 0 {
		return os.WriteFile(path, []byte("[]\n"), 0644)
	}

	// Sort entries for deterministic grouping (matches shell's LC_ALL=C sort -u)
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].Slug != entries[j].Slug {
			return entries[i].Slug < entries[j].Slug
		}
		return entries[i].Path < entries[j].Path
	})

	// Group by slug, prefer non-/unknown/ paths
	grouped := make(map[string][]string)
	for _, e := range entries {
		grouped[e.Slug] = append(grouped[e.Slug], e.Path)
	}

	type projectOut struct {
		Slug string `json:"slug"`
		Path string `json:"path"`
	}

	var result []projectOut
	for slug, paths := range grouped {
		chosen := paths[0]
		for _, p := range paths {
			if !strings.HasPrefix(p, "/unknown/") {
				chosen = p
				break
			}
		}
		result = append(result, projectOut{Slug: slug, Path: chosen})
	}

	sort.Slice(result, func(i, j int) bool {
		return result[i].Path < result[j].Path
	})

	data, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0644)
}

func writeAccountJSON(path string) {
	home, _ := os.UserHomeDir()
	writeAccountJSONFrom(path, filepath.Join(home, ".claude.json"))
}

func writeAccountJSONFrom(outPath string, claudeJSONPath string) {
	data, err := os.ReadFile(claudeJSONPath)
	if err != nil {
		os.WriteFile(outPath, []byte("{}\n"), 0644)
		return
	}

	var raw map[string]any
	if err := json.Unmarshal(data, &raw); err != nil {
		os.WriteFile(outPath, []byte("{}\n"), 0644)
		return
	}

	oauth, _ := raw["oauthAccount"].(map[string]any)
	if oauth == nil {
		os.WriteFile(outPath, []byte("{}\n"), 0644)
		return
	}

	account := map[string]any{
		"display_name":               oauth["displayName"],
		"email":                      oauth["emailAddress"],
		"billing_type":               oauth["billingType"],
		"account_uuid":               oauth["accountUuid"],
		"organization_uuid":          oauth["organizationUuid"],
		"has_extra_usage_enabled":    oauth["hasExtraUsageEnabled"],
		"account_created_at":         oauth["accountCreatedAt"],
		"subscription_created_at":    oauth["subscriptionCreatedAt"],
		"has_available_subscription": raw["hasAvailableSubscription"],
		"has_opus_plan_default":      raw["hasOpusPlanDefault"],
		"user_id":                    raw["userID"],
		"generated_at":               time.Now().UTC().Format(time.RFC3339),
	}

	out, _ := json.MarshalIndent(account, "", "  ")
	os.WriteFile(outPath, append(out, '\n'), 0644)
}

func writeSyncStatus(path string, now time.Time, result *Result) error {
	status := map[string]any{
		"last_sync_epoch": now.Unix(),
		"last_sync_iso":   now.UTC().Format("2006-01-02T15:04:05Z"),
		"source_root":     result.SourceRoot,
		"session_files":   result.SessionFiles,
		"event_rows":      result.EventRows,
		"live_event_rows": result.LiveEventRows,
	}
	data, err := json.MarshalIndent(status, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0644)
}

// projectEntry holds a slug→path mapping (package-level for reuse).
type projectEntry struct {
	Slug string `json:"slug"`
	Path string `json:"path"`
}
