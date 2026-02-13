package cli

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRangeToSeconds(t *testing.T) {
	tests := []struct {
		input   string
		want    int64
		wantErr bool
	}{
		{input: "1h", want: 3600},
		{input: "3h", want: 10800},
		{input: "6h", want: 21600},
		{input: "12h", want: 43200},
		{input: "24h", want: 86400},
		{input: "30h", want: 108000},
		{input: "48h", want: 172800},
		{input: "7d", want: 604800},
		{input: "14d", want: 1209600},
		{input: "30d", want: 2592000},
		{input: "all", want: 0},
		{input: "invalid", wantErr: true},
		{input: "", wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got, err := rangeToSeconds(tt.input)
			if tt.wantErr {
				assert.Error(t, err)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}
