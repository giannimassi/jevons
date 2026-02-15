package cli

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var Version = "dev"

func NewRootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:   "jevons",
		Short: "Local AI usage monitor and dashboard",
		Long:  "Jevons reads session logs from AI coding tools, aggregates token consumption, and serves an interactive dashboard.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return cmd.Help()
		},
	}

	root.AddCommand(
		newSyncCmd(),
		newWebCmd(),
		newAppCmd(),
		newStatusCmd(),
		newDoctorCmd(),
		newTotalCmd(),
		newGraphCmd(),
	)

	root.Version = Version
	root.SetVersionTemplate(fmt.Sprintf("jevons %s\n", Version))

	return root
}

func Execute() {
	if err := NewRootCmd().Execute(); err != nil {
		os.Exit(1)
	}
}
