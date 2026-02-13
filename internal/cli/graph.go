package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/giannimassi/jevons/pkg/model"
	"github.com/spf13/cobra"
)

func newGraphCmd() *cobra.Command {
	var metric string
	var rangeFlag string
	var points int
	var bucket int

	cmd := &cobra.Command{
		Use:   "graph",
		Short: "Display ASCII usage graph",
		Long:  "Render an ASCII graph of token usage over time.",
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

			buckets := make(map[int64]int64)
			for _, e := range events {
				if cutoff > 0 && e.TSEpoch < cutoff {
					continue
				}
				val := metricValue(e, metric)
				b := (e.TSEpoch / int64(bucket)) * int64(bucket)
				buckets[b] += val
			}

			if len(buckets) == 0 {
				fmt.Println("No data in selected range.")
				return nil
			}

			keys := make([]int64, 0, len(buckets))
			for k := range buckets {
				keys = append(keys, k)
			}
			sort.Slice(keys, func(i, j int) bool { return keys[i] < keys[j] })

			// Take last N points
			if len(keys) > points {
				keys = keys[len(keys)-points:]
			}

			var maxVal int64 = 1
			for _, k := range keys {
				if buckets[k] > maxVal {
					maxVal = buckets[k]
				}
			}

			fmt.Printf("metric=%s range_buckets=%d bucket_seconds=%d max=%d\n", metric, len(keys), bucket, maxVal)

			for _, k := range keys {
				v := buckets[k]
				barLen := int(float64(v) / float64(maxVal) * 60)
				bar := strings.Repeat("#", barLen)
				t := time.Unix(k, 0).UTC()
				fmt.Printf("%s | %-60s %d\n", t.Format("15:04"), bar, v)
			}

			return nil
		},
	}

	cmd.Flags().StringVar(&metric, "metric", "billable", "Metric to graph (billable, input, output, cache_read, cache_create, total_with_cache)")
	cmd.Flags().StringVar(&rangeFlag, "range", "24h", "Time range (e.g., 1h, 24h, 7d)")
	cmd.Flags().IntVar(&points, "points", 80, "Number of buckets to render")
	cmd.Flags().IntVar(&bucket, "bucket", 900, "Bucket width in seconds")

	return cmd
}

func metricValue(e model.TokenEvent, metric string) int64 {
	switch metric {
	case "input":
		return e.Input
	case "output":
		return e.Output
	case "cache_read":
		return e.CacheRead
	case "cache_create":
		return e.CacheCreate
	case "billable":
		return e.Billable
	case "total_with_cache":
		return e.TotalWithCache
	default:
		return e.Billable
	}
}
