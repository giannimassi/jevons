package cli

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/giannimassi/jevons/pkg/model"
	"github.com/spf13/cobra"
)

func newDoctorCmd() *cobra.Command {
	var fix bool

	cmd := &cobra.Command{
		Use:   "doctor",
		Short: "Check environment and dependencies",
		Long:  "Run diagnostic checks on the environment and optionally fix issues.",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := model.DefaultConfig()
			coreOK := true

			// Check source directory (CORE)
			fmt.Printf("Source dir: %s\n", cfg.SourceDir)
			if info, err := os.Stat(cfg.SourceDir); err != nil || !info.IsDir() {
				fmt.Println("  [WARN] Source directory does not exist")
				coreOK = false
			} else {
				entries, _ := filepath.Glob(filepath.Join(cfg.SourceDir, "*", "*.jsonl"))
				fmt.Printf("  [OK] Found %d session files\n", len(entries))
			}

			// Check data directory (CORE)
			fmt.Printf("Data dir: %s\n", cfg.DataRoot)
			if info, err := os.Stat(cfg.DataRoot); err != nil || !info.IsDir() {
				fmt.Println("  [WARN] Data directory does not exist")
				if fix {
					if err := os.MkdirAll(cfg.DataRoot, 0755); err != nil {
						fmt.Printf("  [FAIL] Could not create: %v\n", err)
					} else {
						fmt.Println("  [FIXED] Created data directory")
					}
				}
				coreOK = false
			} else {
				fmt.Println("  [OK] Exists")
			}

			// Check events.tsv (CORE)
			eventsPath := filepath.Join(cfg.DataRoot, "events.tsv")
			if info, err := os.Stat(eventsPath); err == nil {
				fmt.Printf("  events.tsv: %d bytes\n", info.Size())
			} else {
				fmt.Println("  events.tsv: not found (run: jevons sync)")
				coreOK = false
			}

			// Check shell dependencies (INFORMATIONAL ONLY — not required by Go binary)
			fmt.Println("\nOptional (legacy shell script only):")
			for _, dep := range []string{"jq", "python3", "curl"} {
				if _, err := exec.LookPath(dep); err != nil {
					fmt.Printf("  %s: [WARN] not found\n", dep)
				} else {
					fmt.Printf("  %s: [OK]\n", dep)
				}
			}

			if coreOK {
				fmt.Println("\nAll checks passed.")
			} else {
				fmt.Println("\nSome checks failed. Run with --fix to attempt repairs.")
			}

			return nil
		},
	}

	cmd.Flags().BoolVar(&fix, "fix", false, "Attempt to auto-fix detected issues")

	return cmd
}
