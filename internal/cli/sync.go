package cli

import (
	"fmt"

	"github.com/spf13/cobra"
)

func newSyncCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "sync",
		Short: "Sync session logs into event stores",
		Long:  "Read AI session JSONL files, extract token events, deduplicate, and write to TSV event stores.",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Println("sync: not yet implemented")
			return nil
		},
	}
}
