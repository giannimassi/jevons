package cli

import (
	"bytes"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewRootCmd(t *testing.T) {
	t.Parallel()

	cmd := NewRootCmd()
	require.NotNil(t, cmd)
	assert.Equal(t, "jevons", cmd.Use)
	assert.Equal(t, Version, cmd.Version)
}

func TestRootCmdShowsHelp(t *testing.T) {
	t.Parallel()

	cmd := NewRootCmd()
	buf := new(bytes.Buffer)
	cmd.SetOut(buf)
	cmd.SetErr(buf)
	cmd.SetArgs([]string{})

	err := cmd.Execute()
	require.NoError(t, err)
	assert.Contains(t, buf.String(), "jevons")
	assert.Contains(t, buf.String(), "aggregates token consumption")
}

func TestRootCmdSubcommands(t *testing.T) {
	t.Parallel()

	cmd := NewRootCmd()
	subCmds := make(map[string]bool)
	for _, sub := range cmd.Commands() {
		subCmds[sub.Name()] = true
	}

	expected := []string{"sync", "web", "app", "status", "doctor", "total", "graph"}
	for _, name := range expected {
		assert.True(t, subCmds[name], "root should have subcommand %q", name)
	}
}

func TestRootCmdVersionFlag(t *testing.T) {
	t.Parallel()

	cmd := NewRootCmd()
	buf := new(bytes.Buffer)
	cmd.SetOut(buf)
	cmd.SetArgs([]string{"--version"})

	err := cmd.Execute()
	require.NoError(t, err)
	assert.Contains(t, buf.String(), Version)
}
