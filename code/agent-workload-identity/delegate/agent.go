// File agent.go talks to the SPIRE agent.
//
// The SPIRE agent has an admin socket, admin.sock. A program in the list
// authorized_delegates of the agent can call the Delegated Identity API on it.
// The delegate sends the pid of the VMM. The agent attests that process with
// its own attestors, and it answers with the SVIDs of the entries that match.
// An SVID is the short-lived certificate of a SPIFFE ID. The answer also holds
// the private key of each SVID.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	delegatedidentityv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/agent/delegatedidentity/v1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

var (
	// errRefused means that the agent answered with zero SVIDs. The agent does
	// this when no registration entry matches the process.
	errRefused = errors.New("agent returned zero SVIDs")
	// errIDMismatch means that no SVID in the answer has the expected ID.
	errIDMismatch = errors.New("no SVID has the expected ID")
)

// svid is one SVID with its private key. The delegate holds it in memory.
type svid struct {
	id       string    // the SPIFFE ID, for example spiffe://mcp.local/node/n/user/u/vm/v
	notAfter time.Time // the end of the life of the SVID
	chain    [][]byte  // DER certificates, leaf first
	key      []byte    // DER PKCS#8
}

// Format prints the SVID without the key, for all verbs. A call such as
// fmt.Println(svid) cannot leak the key by mistake.
func (s svid) Format(f fmt.State, _ rune) {
	fmt.Fprintf(f, "svid{id: %s, notAfter: %s}", s.id, s.notAfter.UTC().Format(time.RFC3339))
}

// fetchSVID sends the pid to the Delegated Identity API on the Unix socket and
// reads the first answer. The agent answers with the SVIDs of all entries that
// match the process. fetchSVID returns the one whose ID is wantID. It never
// takes the first one, and it fails if there is none. This check is the
// delegate's own. The agent does not know which VM the delegate meant.
func fetchSVID(ctx context.Context, socket string, pid int, wantID string) (*svid, error) {
	// Connect to admin.sock. The socket is a local Unix socket. The operating
	// system controls who can open it, so the connection has no TLS.
	conn, err := grpc.NewClient("unix:"+socket, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, fmt.Errorf("connect to agent: %w", err)
	}
	defer conn.Close()

	// SubscribeToX509SVIDs is a stream. The agent can send new answers when it
	// renews an SVID. This delegate reads the first answer only. The cancel
	// below ends the stream.
	ctx, cancel := context.WithCancel(ctx)
	defer cancel() // ends the stream
	stream, err := delegatedidentityv1.NewDelegatedIdentityClient(conn).
		SubscribeToX509SVIDs(ctx, &delegatedidentityv1.SubscribeToX509SVIDsRequest{Pid: int32(pid)})
	if err != nil {
		return nil, fmt.Errorf("subscribe to SVIDs: %w", err)
	}
	resp, err := stream.Recv()
	// The agent can end the stream with no answer. This also means a refusal.
	if errors.Is(err, io.EOF) {
		return nil, errRefused
	}
	if err != nil {
		return nil, fmt.Errorf("read SVIDs: %w", err)
	}
	// An answer with no SVID is the refusal of the agent. It is not a gRPC
	// error. The caller must treat it as a failure.
	if len(resp.GetX509Svids()) == 0 {
		return nil, errRefused
	}
	// The agent answers with the SVIDs of all entries that match the process.
	// Look at each one. The first one is not always the one that we asked for.
	var got []string
	for _, in := range resp.GetX509Svids() {
		id := "spiffe://" + in.GetX509Svid().GetId().GetTrustDomain() + in.GetX509Svid().GetId().GetPath()
		if id == wantID {
			return &svid{
				id:       id,
				notAfter: time.Unix(in.GetX509Svid().GetExpiresAt(), 0).UTC(),
				chain:    in.GetX509Svid().GetCertChain(),
				key:      in.GetX509SvidKey(),
			}, nil
		}
		got = append(got, id)
	}
	// No SVID has the expected ID. The agent answered about a process that is
	// not the VM that we meant. Report both IDs, so that the cause is clear.
	return nil, fmt.Errorf("%w %s, the agent returned: %s", errIDMismatch, wantID, strings.Join(got, ", "))
}
