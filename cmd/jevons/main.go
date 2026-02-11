package main

import "github.com/OWNER/jevons/internal/cli"

var version = "dev"

func main() {
	cli.Version = version
	cli.Execute()
}
