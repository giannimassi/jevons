package cli

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/giannimassi/jevons/internal/daemon"
	"github.com/giannimassi/jevons/pkg/model"
	"github.com/spf13/cobra"
)

func newStatusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Show sync and server status",
		Long:  "Display the current state of the sync daemon and web server.",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := model.DefaultConfig()

			// Sync status
			hb := daemon.ReadHeartbeatState(cfg.DataRoot)
			if hb != nil && hb.Mode == "running" {
				fmt.Printf("sync_status=running pid=%s source=heartbeat age=%ds interval=%ds status=%s\n",
					hb.PID, hb.Age, hb.Interval, hb.Status)
			} else if daemon.IsSyncRunning(cfg.DataRoot) {
				fmt.Println("sync_status=running")
			} else {
				fmt.Println("sync_status=stopped")
			}

			// Heartbeat
			hbPath := filepath.Join(cfg.DataRoot, "heartbeat", "sync.txt")
			if data, err := os.ReadFile(hbPath); err == nil {
				fmt.Printf("sync_heartbeat=%s\n", strings.TrimSpace(string(data)))
			} else {
				fmt.Println("sync_heartbeat=none")
			}

			// Last sync status
			statusPath := filepath.Join(cfg.DataRoot, "sync-status.json")
			if data, err := os.ReadFile(statusPath); err == nil {
				fmt.Printf("sync_last_status_json=%s\n", strings.TrimSpace(string(data)))
			} else {
				fmt.Println("sync_last_status_json=none")
			}

			// Events file path
			fmt.Printf("events_file=%s\n", filepath.Join(cfg.DataRoot, "events.tsv"))

			return nil
		},
	}
}
