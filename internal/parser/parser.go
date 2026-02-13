package parser

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/giannimassi/jevons/pkg/model"
)

// jsonRow represents a single line from a JSONL session log.
type jsonRow struct {
	Type              string          `json:"type"`
	Timestamp         string          `json:"timestamp"`
	CWD               string          `json:"cwd"`
	IsApiErrorMessage *bool           `json:"isApiErrorMessage"`
	Message           *messageWrapper `json:"message"`
}

type messageWrapper struct {
	Role    string          `json:"role"`
	Content json.RawMessage `json:"content"`
	Usage   *usageBlock     `json:"usage"`
}

type usageBlock struct {
	InputTokens              int64 `json:"input_tokens"`
	OutputTokens             int64 `json:"output_tokens"`
	CacheReadInputTokens     int64 `json:"cache_read_input_tokens"`
	CacheCreationInputTokens int64 `json:"cache_creation_input_tokens"`
}

type contentBlock struct {
	Type      string `json:"type"`
	Text      string `json:"text"`
	ToolUseID string `json:"tool_use_id"`
}

// ParseSessionFile reads a JSONL session file and returns token events.
func ParseSessionFile(path string, projectSlug string, sessionID string) ([]model.TokenEvent, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var events []model.TokenEvent
	var pendingHuman bool
	var lastSig string

	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 1024*1024), 10*1024*1024)

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}

		var row jsonRow
		if err := json.Unmarshal([]byte(line), &row); err != nil {
			continue
		}

		if row.Message == nil {
			continue
		}

		switch row.Type {
		case "user":
			if isHumanPrompt(row.Message.Content) {
				pendingHuman = true
			}

		case "assistant":
			if row.Message.Usage == nil {
				continue
			}
			if row.IsApiErrorMessage != nil && *row.IsApiErrorMessage {
				continue
			}

			u := row.Message.Usage
			sig := fmt.Sprintf("%d|%d|%d|%d", u.InputTokens, u.OutputTokens, u.CacheReadInputTokens, u.CacheCreationInputTokens)

			if sig == lastSig && !pendingHuman {
				lastSig = sig
				continue
			}

			epoch := parseEpoch(row.Timestamp)
			billable := u.InputTokens + u.OutputTokens
			totalWithCache := billable + u.CacheReadInputTokens + u.CacheCreationInputTokens

			events = append(events, model.TokenEvent{
				TSEpoch:        epoch,
				TSISO:          row.Timestamp,
				ProjectSlug:    projectSlug,
				SessionID:      sessionID,
				Input:          u.InputTokens,
				Output:         u.OutputTokens,
				CacheRead:      u.CacheReadInputTokens,
				CacheCreate:    u.CacheCreationInputTokens,
				Billable:       billable,
				TotalWithCache: totalWithCache,
				ContentType:    contentType(row.Message.Content),
				Signature:      sig,
			})

			lastSig = sig
			pendingHuman = false
		}
	}

	return events, scanner.Err()
}

// ParseSessionFileLive reads a JSONL session file and returns live events with prompt previews.
func ParseSessionFileLive(path string, projectSlug string, sessionID string) ([]model.LiveEvent, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var events []model.LiveEvent
	var pendingHuman bool
	var lastSig string
	var lastPrompt = "-"

	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 1024*1024), 10*1024*1024)

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}

		var row jsonRow
		if err := json.Unmarshal([]byte(line), &row); err != nil {
			continue
		}

		if row.Message == nil {
			continue
		}

		switch row.Type {
		case "user":
			if isHumanPrompt(row.Message.Content) {
				pendingHuman = true
				lastPrompt = promptPreview(row.Message.Content)
			}

		case "assistant":
			if row.Message.Usage == nil {
				continue
			}
			if row.IsApiErrorMessage != nil && *row.IsApiErrorMessage {
				continue
			}

			u := row.Message.Usage
			sig := fmt.Sprintf("%d|%d|%d|%d", u.InputTokens, u.OutputTokens, u.CacheReadInputTokens, u.CacheCreationInputTokens)

			if sig == lastSig && !pendingHuman {
				lastSig = sig
				continue
			}

			epoch := parseEpoch(row.Timestamp)
			billable := u.InputTokens + u.OutputTokens
			totalWithCache := billable + u.CacheReadInputTokens + u.CacheCreationInputTokens

			events = append(events, model.LiveEvent{
				TokenEvent: model.TokenEvent{
					TSEpoch:        epoch,
					TSISO:          row.Timestamp,
					ProjectSlug:    projectSlug,
					SessionID:      sessionID,
					Input:          u.InputTokens,
					Output:         u.OutputTokens,
					CacheRead:      u.CacheReadInputTokens,
					CacheCreate:    u.CacheCreationInputTokens,
					Billable:       billable,
					TotalWithCache: totalWithCache,
					ContentType:    contentType(row.Message.Content),
					Signature:      sig,
				},
				PromptPreview: lastPrompt,
			})

			lastSig = sig
			pendingHuman = false
		}
	}

	return events, scanner.Err()
}

// ExtractProjectPath reads a session file and returns the cwd field if present.
func ExtractProjectPath(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 1024*1024), 10*1024*1024)

	for scanner.Scan() {
		var row jsonRow
		if err := json.Unmarshal(scanner.Bytes(), &row); err != nil {
			continue
		}
		if row.CWD != "" {
			return row.CWD
		}
	}
	return ""
}

// parseEpoch parses an ISO timestamp to Unix epoch.
// Handles fractional seconds by stripping them before parsing.
func parseEpoch(ts string) int64 {
	if ts == "" {
		return 0
	}
	// Strip fractional seconds: "2025-01-15T10:30:00.123Z" → "2025-01-15T10:30:00Z"
	// Also handle timezone offsets: "2025-01-15T10:30:00.123+01:00" → "2025-01-15T10:30:00+01:00"
	cleaned := ts
	if dotIdx := strings.Index(ts, "."); dotIdx != -1 {
		// Find where the fractional part ends (Z or + or -)
		rest := ts[dotIdx+1:]
		for i, c := range rest {
			if c == 'Z' || c == '+' || c == '-' {
				cleaned = ts[:dotIdx] + rest[i:]
				break
			}
		}
		if cleaned == ts {
			// No timezone suffix found — malformed timestamp, return 0 (matches shell behavior)
			return 0
		}
	}

	t, err := time.Parse(time.RFC3339, cleaned)
	if err != nil {
		return 0
	}
	return t.Unix()
}

// isHumanPrompt checks if a user message content represents a human prompt
// (not just tool_result responses).
func isHumanPrompt(raw json.RawMessage) bool {
	if len(raw) == 0 {
		return true
	}

	// Check if it's a string
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		return true
	}

	// Check if it's an array
	var blocks []contentBlock
	if err := json.Unmarshal(raw, &blocks); err == nil {
		if len(blocks) == 0 {
			return true
		}
		// If ALL blocks are tool_result, it's not a human prompt
		allToolResult := true
		for _, b := range blocks {
			if b.Type != "tool_result" {
				allToolResult = false
				break
			}
		}
		return !allToolResult
	}

	return true
}

// contentType extracts the content type from an assistant message's content.
func contentType(raw json.RawMessage) string {
	if len(raw) == 0 {
		return "-"
	}

	// Check if string
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		return "text"
	}

	// Check if array
	var blocks []contentBlock
	if err := json.Unmarshal(raw, &blocks); err == nil {
		if len(blocks) > 0 && blocks[0].Type != "" {
			return blocks[0].Type
		}
		return "-"
	}

	return "-"
}

// promptPreview extracts and cleans prompt text from a user message.
func promptPreview(raw json.RawMessage) string {
	text := promptText(raw)
	cleaned := cleanText(text)
	if cleaned == "" {
		return "-"
	}
	if len(cleaned) > 180 {
		return cleaned[:177] + "..."
	}
	return cleaned
}

// promptText extracts text content from a user message.
func promptText(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}

	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		return s
	}

	var blocks []contentBlock
	if err := json.Unmarshal(raw, &blocks); err == nil {
		var parts []string
		for _, b := range blocks {
			if b.Type == "text" {
				parts = append(parts, b.Text)
			}
		}
		return strings.Join(parts, " ")
	}

	return ""
}

// cleanText normalizes whitespace in text.
func cleanText(s string) string {
	// Replace tabs, carriage returns, newlines with spaces
	replacer := strings.NewReplacer("\t", " ", "\r", " ", "\n", " ")
	s = replacer.Replace(s)
	// Collapse multiple spaces
	for strings.Contains(s, "  ") {
		s = strings.ReplaceAll(s, "  ", " ")
	}
	return strings.TrimSpace(s)
}
