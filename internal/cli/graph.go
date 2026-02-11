package cli

import (
	"fmt"

	"github.com/spf13/cobra"
)

func newGraphCmd() *cobra.Command {
	var metric string
	var rangeFlag string

	cmd := &cobra.Command{
		Use:   "graph",
		Short: "Display ASCII usage graph",
		Long:  "Render an ASCII graph of token usage over time.",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Printf("graph: not yet implemented (metric=%s, range=%s)\n", metric, rangeFlag)
			return nil
		},
	}

	cmd.Flags().StringVar(&metric, "metric", "billable", "Metric to graph (billable, input, output, total_with_cache)")
	cmd.Flags().StringVar(&rangeFlag, "range", "24h", "Time range (e.g., 1h, 24h, 7d)")

	return cmd
}
