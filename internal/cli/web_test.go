package cli

import (
	"bytes"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestWebCmdHelp(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		want string
	}{
		{"mentions HTTP dashboard", "HTTP dashboard server"},
		{"port flag", "--port"},
		{"interval flag", "--interval"},
		{"mentions sync loop", "sync loop"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			cmd := NewRootCmd()
			buf := new(bytes.Buffer)
			cmd.SetOut(buf)
			cmd.SetErr(buf)
			cmd.SetArgs([]string{"web", "--help"})

			err := cmd.Execute()
			require.NoError(t, err)
			assert.Contains(t, buf.String(), tt.want)
		})
	}
}

func TestWebCmdFlags(t *testing.T) {
	t.Parallel()

	cmd := newWebCmd()

	portFlag := cmd.Flags().Lookup("port")
	require.NotNil(t, portFlag)
	assert.Equal(t, "8765", portFlag.DefValue)

	intervalFlag := cmd.Flags().Lookup("interval")
	require.NotNil(t, intervalFlag)
	assert.Equal(t, "15", intervalFlag.DefValue)
}
