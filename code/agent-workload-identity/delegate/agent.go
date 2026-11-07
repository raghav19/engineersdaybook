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
	id       string
	notAfter time.Time
	chain    [][]byte // DER certificates, leaf first
	key      []byte   // DER PKCS#8
}

// Format prints the SVID without the key, for all verbs.
func (s svid) Format(f fmt.State, _ rune) {
	fmt.Fprintf(f, "svid{id: %s, notAfter: %s}", s.id, s.notAfter.UTC().Format(time.RFC3339))
}

// fetchSVID sends the pid to the Delegated Identity API on the Unix socket and
// reads the first answer. The agent answers with the SVIDs of all entries that
// match the process. fetchSVID returns the one whose ID is wantID. It never
// takes the first one, and it fails if there is none. This check is the
// delegate's own. The agent does not know which VM the delegate meant.
func fetchSVID(ctx context.Context, socket string, pid int, wantID string) (*svid, error) {
	conn, err := grpc.NewClient("unix:"+socket, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, fmt.Errorf("connect to agent: %w", err)
	}
	defer conn.Close()

	ctx, cancel := context.WithCancel(ctx)
	defer cancel() // ends the stream
	stream, err := delegatedidentityv1.NewDelegatedIdentityClient(conn).
		SubscribeToX509SVIDs(ctx, &delegatedidentityv1.SubscribeToX509SVIDsRequest{Pid: int32(pid)})
	if err != nil {
		return nil, fmt.Errorf("subscribe to SVIDs: %w", err)
	}
	resp, err := stream.Recv()
	if errors.Is(err, io.EOF) {
		return nil, errRefused
	}
	if err != nil {
		return nil, fmt.Errorf("read SVIDs: %w", err)
	}
	if len(resp.GetX509Svids()) == 0 {
		return nil, errRefused
	}
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
	return nil, fmt.Errorf("%w %s, the agent returned: %s", errIDMismatch, wantID, strings.Join(got, ", "))
}
