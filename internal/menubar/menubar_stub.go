//go:build !darwin

package menubar

import "fmt"

func openBrowser(url string) error {
	return fmt.Errorf("openBrowser not supported on this platform")
}
