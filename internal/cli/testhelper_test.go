package cli

import (
	"bytes"
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

// captureStdout captures os.Stdout output from fn.
// Tests using this helper cannot use t.Parallel() since they mutate os.Stdout.
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()

	origStdout := os.Stdout
	r, w, err := os.Pipe()
	require.NoError(t, err)

	os.Stdout = w

	fn()

	w.Close()
	os.Stdout = origStdout

	var buf bytes.Buffer
	_, err = buf.ReadFrom(r)
	require.NoError(t, err)

	return buf.String()
}
