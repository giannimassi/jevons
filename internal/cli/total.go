package cli

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/giannimassi/jevons/pkg/model"
	"github.com/spf13/cobra"
)

func newTotalCmd() *cobra.Command {
	var rangeFlag string

	cmd := &cobra.Command{
		Use:   "total",
		Short: "Show token usage totals",
		Long:  "Display aggregated token usage totals as JSON.",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := model.DefaultConfig()
			eventsPath := filepath.Join(cfg.DataRoot, "events.tsv")

			if _, err := os.Stat(eventsPath); os.IsNotExist(err) {
				return fmt.Errorf("no synced events found. Run: jevons sync")
			}

			rangeSec, err := rangeToSeconds(rangeFlag)
			if err != nil {
				return err
			}

			now := time.Now().Unix()
			var cutoff int64
			if rangeSec > 0 {
				cutoff = now - rangeSec
			}

			events, err := readEventsFromTSV(eventsPath)
			if err != nil {
				return fmt.Errorf("read events: %w", err)
			}

			var n, inputSum, outputSum, cacheReadSum, cacheCreateSum, billableSum, totalWithCacheSum int64
			for _, e := range events {
				if cutoff > 0 && e.TSEpoch < cutoff {
					continue
				}
				n++
				inputSum += e.Input
				outputSum += e.Output
				cacheReadSum += e.CacheRead
				cacheCreateSum += e.CacheCreate
				billableSum += e.Billable
				totalWithCacheSum += e.TotalWithCache
			}

			result := map[string]any{
				"range":            rangeFlag,
				"project_slug":     nil,
				"events":           n,
				"input":            inputSum,
				"output":           outputSum,
				"cache_read":       cacheReadSum,
				"cache_create":     cacheCreateSum,
				"billable":         billableSum,
				"total_with_cache": totalWithCacheSum,
			}

			enc := json.NewEncoder(os.Stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(result)
		},
	}

	cmd.Flags().StringVar(&rangeFlag, "range", "24h", "Time range (e.g., 1h, 24h, 7d)")
	return cmd
}
