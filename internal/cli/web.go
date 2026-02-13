package cli

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/giannimassi/jevons/internal/daemon"
	"github.com/giannimassi/jevons/internal/dashboard"
	internalSync "github.com/giannimassi/jevons/internal/sync"
	"github.com/giannimassi/jevons/pkg/model"
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
			cfg := model.DefaultConfig()
			cfg.Port = port
			cfg.Interval = interval

			if err := daemon.EnsureDataDirs(cfg.DataRoot); err != nil {
				return err
			}

			// Initial sync
			if _, err := internalSync.Run(cfg); err != nil {
				fmt.Fprintf(os.Stderr, "initial sync warning: %v\n", err)
			}

			// Start HTTP server
			srv := &dashboard.Server{
				Port:     cfg.Port,
				DataRoot: cfg.DataRoot,
			}
			if err := srv.Start(); err != nil {
				return fmt.Errorf("start server: %w", err)
			}

			url := fmt.Sprintf("http://127.0.0.1:%d/dashboard/index.html", cfg.Port)
			fmt.Printf("Dashboard URL: %s\n", url)
			fmt.Printf("Auto-sync interval: %ds\n", cfg.Interval)

			// Start background sync daemon
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()

			d := &daemon.Daemon{
				Interval: cfg.Interval,
				DataRoot: cfg.DataRoot,
				SyncFn: func() error {
					_, err := internalSync.Run(cfg)
					return err
				},
			}

			sigCh := make(chan os.Signal, 1)
			signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

			go func() {
				<-sigCh
				cancel()
				srv.Stop(context.Background())
			}()

			return d.Run(ctx)
		},
	}

	cmd.Flags().IntVar(&port, "port", defaults.Port, "HTTP server port")
	cmd.Flags().IntVar(&interval, "interval", defaults.Interval, "Sync interval in seconds")

	return cmd
}
