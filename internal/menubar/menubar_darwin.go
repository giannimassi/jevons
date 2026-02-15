//go:build darwin

package menubar

import "os/exec"

func openBrowser(url string) error {
	return exec.Command("open", url).Start()
}
