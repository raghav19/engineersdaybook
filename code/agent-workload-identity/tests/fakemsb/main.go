//go:build ignore

// This program is a fake msb. tests/e2e.sh builds it under the name msb and
// starts it with the command line of a real VMM. It ignores its arguments and
// sleeps. It has the exe name and the command line of the VMM, but msb.db has
// no run row for it.
package main

import "time"

func main() {
	time.Sleep(time.Hour)
}
