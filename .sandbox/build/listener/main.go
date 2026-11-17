// The build listener, written in Go. It takes one build at a time from the socket build.sock.
// Lesson 1: accept connections one at a time. Read the first line and send it back.
package main

import (
	"bufio"
	"fmt"
	"log"
	"net"
	"os"
)

func main() {
	// The test and the justfile set SANDBOX_BUILD_SOCKET. Without it, the socket is in the folder of the proxy socket.
	socket := os.Getenv("SANDBOX_BUILD_SOCKET")
	if socket == "" {
		socket = os.Getenv("XDG_RUNTIME_DIR") + "/sandbox/build.sock"
	}
	// An old socket file from an earlier run makes Listen fail. Remove it. If there is none, the error does not matter.
	_ = os.Remove(socket)

	listener, err := net.Listen("unix", socket)
	if err != nil {
		log.Fatal(err)
	}
	defer listener.Close()
	// The folder of the socket is below the 0700 folder of your session. Only your user and the sandbox reach it.
	if err := os.Chmod(socket, 0o666); err != nil {
		log.Fatal(err)
	}
	log.Println("the listener waits on", socket)

	// One connection at a time. The other agents wait in the listen queue of the socket.
	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Fatal(err)
		}
		handle(conn)
	}
}

// handle reads the first line of one connection and sends it back.
func handle(conn net.Conn) {
	defer conn.Close()
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		log.Println("no spec:", err)
		return
	}
	fmt.Fprintf(conn, "got: %s", line)
}
