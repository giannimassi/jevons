package cli

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/giannimassi/jevons/internal/store"
	"github.com/giannimassi/jevons/pkg/model"
)

// rangeToSeconds converts a human-readable range string to seconds.
func rangeToSeconds(r string) (int64, error) {
	switch r {
	case "1h":
		return 3600, nil
	case "3h":
		return 10800, nil
	case "6h":
		return 21600, nil
	case "12h":
		return 43200, nil
	case "24h":
		return 86400, nil
	case "30h":
		return 108000, nil
	case "48h":
		return 172800, nil
	case "7d":
		return 604800, nil
	case "14d":
		return 1209600, nil
	case "30d":
		return 2592000, nil
	case "all":
		return 0, nil
	default:
		return 0, fmt.Errorf("unknown range: %s", r)
	}
}

// readEventsFromTSV reads all token events from a TSV file.
func readEventsFromTSV(path string) ([]model.TokenEvent, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var events []model.TokenEvent
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	// Skip header
	if scanner.Scan() {
		// consumed
	}

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		event, err := store.UnmarshalTokenEvent(line)
		if err != nil {
			continue
		}
		events = append(events, event)
	}

	return events, scanner.Err()
}
