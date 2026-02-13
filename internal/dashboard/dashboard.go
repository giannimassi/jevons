package dashboard

import (
	"context"
	"embed"
	"fmt"
	"io/fs"
	"net"
	"net/http"
)

//go:embed assets/index.html
var dashboardFS embed.FS

// Server serves the dashboard and data files.
type Server struct {
	Port     int
	DataRoot string
	server   *http.Server
}

// Start starts the HTTP server.
// Routes:
//   - /dashboard/ → embedded dashboard HTML
//   - / → data files from DataRoot (events.tsv, projects.json, etc.)
func (s *Server) Start() error {
	mux := http.NewServeMux()

	sub, err := fs.Sub(dashboardFS, "assets")
	if err != nil {
		return fmt.Errorf("embed sub: %w", err)
	}
	mux.Handle("/dashboard/", http.StripPrefix("/dashboard/", http.FileServer(http.FS(sub))))
	mux.Handle("/", http.FileServer(http.Dir(s.DataRoot)))

	s.server = &http.Server{
		Addr:    fmt.Sprintf("127.0.0.1:%d", s.Port),
		Handler: mux,
	}

	ln, err := net.Listen("tcp", s.server.Addr)
	if err != nil {
		return fmt.Errorf("listen on port %d: %w", s.Port, err)
	}

	go s.server.Serve(ln)
	return nil
}

// Stop gracefully shuts down the server.
func (s *Server) Stop(ctx context.Context) error {
	if s.server != nil {
		return s.server.Shutdown(ctx)
	}
	return nil
}
