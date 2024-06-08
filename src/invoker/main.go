// This program will listen on a socket and send commands to bin/console using the php with env
// it is started by prepare.sh script with the user defined in container env
package main

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
)

func main() {
	// this var lets us authenticate that messages come from the php app
	psk := os.Getenv("INVOKER_PSK")
	socketPath := "/run/invoker/invoker.sock"

	// Remove the socket if it already exists
	if err := os.RemoveAll(socketPath); err != nil {
		fmt.Println("Error removing existing socket:", err)
		return
	}

	// Listen on the Unix socket
	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		fmt.Println("Error listening on Unix socket:", err)
		return
	}
	defer listener.Close()

	log("info", "listening on "+socketPath)

	var wg sync.WaitGroup
	var mu sync.Mutex

	for {
		conn, err := listener.Accept()
		if err != nil {
			log("error", fmt.Sprint("Error accepting connection:", err))
			continue
		}

		wg.Add(1)
		go func(c net.Conn) {
			defer wg.Done()
			handleConnection(c, &mu, psk)
		}(conn)
	}

	wg.Wait()
}

// log prints a log message with the current timestamp in ISO 8601 format
func log(level, message string) {
	now := time.Now()
	timestamp := now.Format(time.RFC3339)
	fmt.Printf("[%s] invoker: %s: %s\n", timestamp, level, message)
}

func handleConnection(conn net.Conn, mu *sync.Mutex, psk string) {
	defer conn.Close()
	scanner := bufio.NewScanner(conn)

	for scanner.Scan() {
		cmdStr := scanner.Text()

		// Extract the PSK from the message
		parts := strings.SplitN(cmdStr, "|", 2)
		if len(parts) != 2 || parts[0] != psk {
			log("error", "invalid or missing PSK")
			continue
		}

		// Extract the actual command
		actualCmd := parts[1]
		log("info", "received command: "+actualCmd)

		// track the time it takes to run the command, so start a timer
		start := time.Now()
		// we only want to process one command at the time
		mu.Lock()
		// split received command into arguments before passing it to exec.Command
		args := strings.Fields(actualCmd)
		cmd := exec.Command("/usr/bin/php", append([]string{"/elabftw/bin/console"}, args...)...)
		output, err := cmd.CombinedOutput()
		// stop timer
		elapsed := time.Since(start)
		elapsedFormatted := fmt.Sprintf("%dm%02ds", int(elapsed.Minutes()), int(elapsed.Seconds())%60)
		log("info", fmt.Sprintf("finished processing: %s in %s", actualCmd, elapsedFormatted))
		mu.Unlock()

		if err != nil {
			fmt.Fprintf(conn, "Error executing command: %v\n", err)
		} else {
			fmt.Fprintf(conn, "Output:\n%s\n", output)
		}
	}

	if err := scanner.Err(); err != nil {
		fmt.Println("Error reading from connection:", err)
	}
}
