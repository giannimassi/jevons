package main

import "github.com/giannimassi/jevons/internal/cli"

var version = "dev"

func main() {
	cli.Version = version
	cli.Execute()
}
