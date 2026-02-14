package cli

import (
	"bytes"
	"runtime"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAppCmdHelp(t *testing.T) {
	t.Parallel()

	cmd := NewRootCmd()
	buf := new(bytes.Buffer)
	cmd.SetOut(buf)
	cmd.SetErr(buf)
	cmd.SetArgs([]string{"app", "--help"})

	err := cmd.Execute()
	require.NoError(t, err)

	out := buf.String()
	assert.Contains(t, out, "menu bar")
}

func TestAppCmdExists(t *testing.T) {
	t.Parallel()

	cmd := NewRootCmd()
	appCmd, _, err := cmd.Find([]string{"app"})
	require.NoError(t, err)
	assert.Equal(t, "app", appCmd.Name())
}

func TestAppCmdFlagsOnDarwin(t *testing.T) {
	t.Parallel()

	if runtime.GOOS != "darwin" {
		t.Skip("app flags only present on darwin")
	}

	cmd := newAppCmd()
	portFlag := cmd.Flags().Lookup("port")
	require.NotNil(t, portFlag)
	assert.Equal(t, "8765", portFlag.DefValue)

	intervalFlag := cmd.Flags().Lookup("interval")
	require.NotNil(t, intervalFlag)
	assert.Equal(t, "15", intervalFlag.DefValue)
}
