//go:build darwin

package cli

import (
	"context"
	"fmt"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"syscall"

	"fyne.io/systray"
	"github.com/giannimassi/jevons/internal/daemon"
	"github.com/giannimassi/jevons/internal/dashboard"
	"github.com/giannimassi/jevons/internal/menubar"
	internalSync "github.com/giannimassi/jevons/internal/sync"
	"github.com/giannimassi/jevons/pkg/model"
	"github.com/spf13/cobra"
	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	wailsruntime "github.com/wailsapp/wails/v2/pkg/runtime"
)

// App holds the native window app state.
type App struct {
	ctx      context.Context
	ctxReady chan struct{}
	syncFn   func()
}

func newAppCmd() *cobra.Command {
	defaults := model.DefaultConfig()
	var port int
	var interval int

	cmd := &cobra.Command{
		Use:   "app",
		Short: "Start menu bar app with native webview dashboard",
		Long:  "Start Jevons as a macOS menu bar app with a native webview window and background sync.",
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

			// Start HTTP server (goroutine)
			srv := &dashboard.Server{
				Port:     cfg.Port,
				DataRoot: cfg.DataRoot,
			}
			if err := srv.Start(); err != nil {
				return fmt.Errorf("start server: %w", err)
			}

			dashboardURL := fmt.Sprintf("http://127.0.0.1:%d/dashboard/index.html", cfg.Port)
			fmt.Printf("Dashboard URL: %s\n", dashboardURL)

			// Start daemon (goroutine)
			ctx, cancel := context.WithCancel(context.Background())
			d := &daemon.Daemon{
				Interval: cfg.Interval,
				DataRoot: cfg.DataRoot,
				SyncFn: func() error {
					_, err := internalSync.Run(cfg)
					return err
				},
			}
			go d.Run(ctx)

			// Create the app instance
			app := &App{
				ctxReady: make(chan struct{}),
				syncFn: func() {
					if _, err := internalSync.Run(cfg); err != nil {
						fmt.Fprintf(os.Stderr, "manual sync error: %v\n", err)
					}
				},
			}

			// Create reverse proxy to the HTTP server
			target, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", cfg.Port))
			proxy := httputil.NewSingleHostReverseProxy(target)
			proxy.FlushInterval = -1 // Immediate flush for SSE

			// Register systray (non-blocking — works with Wails' Cocoa event loop)
			systray.Register(func() {
				app.onSystrayReady()
			}, func() {
				cancel()
				srv.Stop(context.Background())
			})

			// Signal handler: route SIGINT/SIGTERM through Wails shutdown
			sigCh := make(chan os.Signal, 1)
			signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
			go func() {
				<-sigCh
				wailsruntime.Quit(app.ctx)
			}()

			// Start Wails on the main thread
			if err := wails.Run(&options.App{
				Title:             "Jevons",
				Width:             1200,
				Height:            800,
				MinWidth:          800,
				MinHeight:         500,
				DisableResize:     false,
				Frameless:         false,
				StartHidden:       true,
				HideWindowOnClose: true,
				OnStartup:         app.startup,
				OnShutdown: func(ctx context.Context) {
					cancel()
					srv.Stop(context.Background())
					systray.Quit()
				},
				AssetServer: &assetserver.Options{
					Handler: proxy,
				},
			}); err != nil {
				return fmt.Errorf("wails error: %w", err)
			}

			return nil
		},
	}

	cmd.Flags().IntVar(&port, "port", defaults.Port, "HTTP server port")
	cmd.Flags().IntVar(&interval, "interval", defaults.Interval, "Sync interval in seconds")
	return cmd
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	close(a.ctxReady)
}

func (a *App) onSystrayReady() {
	systray.SetTemplateIcon(menubar.GetIconData(), menubar.GetIconData())
	systray.SetTitle("Jevons")
	systray.SetTooltip("Jevons — AI usage monitor")

	mOpen := systray.AddMenuItem("Open Dashboard", "Show the dashboard window")
	mSync := systray.AddMenuItem("Sync Now", "Trigger immediate sync")
	systray.AddSeparator()
	mQuit := systray.AddMenuItem("Quit", "Quit Jevons")

	go func() {
		// Wait for Wails context to be available.
		<-a.ctxReady

		for {
			select {
			case <-mOpen.ClickedCh:
				wailsruntime.WindowShow(a.ctx)
			case <-mSync.ClickedCh:
				if a.syncFn != nil {
					go a.syncFn()
				}
			case <-mQuit.ClickedCh:
				wailsruntime.Quit(a.ctx)
			}
		}
	}()
}
