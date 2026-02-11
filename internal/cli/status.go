package cli

import (
	"fmt"

	"github.com/spf13/cobra"
)

func newStatusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Show sync and server status",
		Long:  "Display the current state of the sync daemon and web server.",
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Println("status: not yet implemented")
			return nil
		},
	}
}
