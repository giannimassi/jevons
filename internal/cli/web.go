package cli

import (
	"fmt"

	"github.com/OWNER/jevons/pkg/model"
	"github.com/spf13/cobra"
)

func newWebCmd() *cobra.Command {
	defaults := model.DefaultConfig()
	var port int
	var interval int

	cmd := &cobra.Command{
		Use:   "web",
		Short: "Start dashboard and background sync",
		Long:  "Start the HTTP dashboard server and a background sync loop.",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Printf("web: not yet implemented (port=%d, interval=%d)\n", port, interval)
			return nil
		},
	}

	cmd.Flags().IntVar(&port, "port", defaults.Port, "HTTP server port")
	cmd.Flags().IntVar(&interval, "interval", defaults.Interval, "Sync interval in seconds")

	return cmd
}
