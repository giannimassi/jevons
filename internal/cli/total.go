package cli

import (
	"fmt"

	"github.com/spf13/cobra"
)

func newTotalCmd() *cobra.Command {
	var rangeFlag string

	cmd := &cobra.Command{
		Use:   "total",
		Short: "Show token usage totals",
		Long:  "Display aggregated token usage totals as JSON.",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Printf("total: not yet implemented (range=%s)\n", rangeFlag)
			return nil
		},
	}

	cmd.Flags().StringVar(&rangeFlag, "range", "24h", "Time range (e.g., 1h, 24h, 7d)")

	return cmd
}
