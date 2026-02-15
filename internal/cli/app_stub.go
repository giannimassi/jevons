//go:build !darwin

package cli

import (
	"fmt"

	"github.com/spf13/cobra"
)

func newAppCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "app",
		Short: "Start menu bar app (macOS only)",
		Long:  "Start Jevons as a macOS menu bar application. This command is only available on macOS.",
		RunE: func(cmd *cobra.Command, args []string) error {
			return fmt.Errorf("jevons app is only available on macOS.\n\nUse 'jevons web' for the browser-based dashboard on any platform.")
		},
	}
}
