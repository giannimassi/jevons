package cli

import (
	"bytes"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSyncCmdHelp(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		want string
	}{
		{"mentions JSONL", "JSONL"},
		{"mentions deduplicate", "deduplicate"},
		{"mentions TSV", "TSV"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			cmd := NewRootCmd()
			buf := new(bytes.Buffer)
			cmd.SetOut(buf)
			cmd.SetErr(buf)
			cmd.SetArgs([]string{"sync", "--help"})

			err := cmd.Execute()
			require.NoError(t, err)
			assert.Contains(t, buf.String(), tt.want)
		})
	}
}

func TestSyncCmdNoFlags(t *testing.T) {
	t.Parallel()

	cmd := newSyncCmd()
	// sync has no custom flags
	assert.Empty(t, cmd.Flags().FlagUsages())
}
