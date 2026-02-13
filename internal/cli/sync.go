package cli

import (
	"fmt"

	internalSync "github.com/giannimassi/jevons/internal/sync"
	"github.com/giannimassi/jevons/pkg/model"
	"github.com/spf13/cobra"
)

func newSyncCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "sync",
		Short: "Sync session logs into event stores",
		Long:  "Read AI session JSONL files, extract token events, deduplicate, and write to TSV event stores.",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := model.DefaultConfig()
			result, err := internalSync.Run(cfg)
			if err != nil {
				return fmt.Errorf("sync failed: %w", err)
			}
			fmt.Printf("sync_ok session_files=%d event_rows=%d live_rows=%d source_root=%s\n",
				result.SessionFiles, result.EventRows, result.LiveEventRows, result.SourceRoot)
			return nil
		},
	}
}
