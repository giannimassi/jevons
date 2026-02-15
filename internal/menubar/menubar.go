package menubar

import "fyne.io/systray"

// Config holds the menubar application configuration.
type Config struct {
	DashboardURL string
	SyncFn       func()
	OnQuit       func()
}

// Run starts the systray application. It blocks until systray.Quit() is called.
func Run(cfg Config) error {
	systray.Run(
		func() { onReady(cfg) },
		func() { onExit(cfg) },
	)
	return nil
}

// GetIconData returns the embedded icon data for use in systray setup.
func GetIconData() []byte {
	return iconData
}

func onReady(cfg Config) {
	if len(iconData) > 0 {
		systray.SetTemplateIcon(iconData, iconData)
	}
	systray.SetTitle("Jevons")
	systray.SetTooltip("Jevons — AI usage monitor")

	mOpen := systray.AddMenuItem("Open Dashboard", "Open dashboard in browser")
	mSync := systray.AddMenuItem("Sync Now", "Trigger immediate sync")
	systray.AddSeparator()
	mQuit := systray.AddMenuItem("Quit", "Quit Jevons")

	go func() {
		for {
			select {
			case <-mOpen.ClickedCh:
				openBrowser(cfg.DashboardURL)
			case <-mSync.ClickedCh:
				if cfg.SyncFn != nil {
					go cfg.SyncFn()
				}
			case <-mQuit.ClickedCh:
				systray.Quit()
			}
		}
	}()
}

func onExit(cfg Config) {
	if cfg.OnQuit != nil {
		cfg.OnQuit()
	}
}
