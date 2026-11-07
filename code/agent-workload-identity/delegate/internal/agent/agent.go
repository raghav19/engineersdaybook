// Package agent asks the host SPIRE agent for the SVID of one process.
package agent

import (
	"context"
	"crypto"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"time"

	delegatedidentityv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/agent/delegatedidentity/v1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// ErrRefused means that the agent answered with zero SVIDs. The agent does
// this when no registration entry matches the process.
var ErrRefused = errors.New("agent returned zero SVIDs")

// SVID is one X.509 SVID with its private key.
type SVID struct {
	ID       string // SPIFFE ID, for example spiffe://mcp.local/node/n/vm/v
	NotAfter time.Time
	Chain    []*x509.Certificate // leaf first
	Key      crypto.PrivateKey   // parsed from PKCS#8
}

// Format prints the SVID without the private key, for all verbs.
func (s SVID) Format(f fmt.State, _ rune) {
	fmt.Fprintf(f, "SVID{ID: %s, NotAfter: %s}", s.ID, s.NotAfter.UTC().Format(time.RFC3339))
}

// FetchX509SVIDs sends the pid to the Delegated Identity API on the Unix
// socket and reads the first response. It returns all SVIDs of that response,
// in order. It returns ErrRefused if the response has no SVID.
func FetchX509SVIDs(ctx context.Context, socket string, pid int) ([]*SVID, error) {
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
		return nil, ErrRefused
	}
	if err != nil {
		return nil, fmt.Errorf("read SVIDs: %w", err)
	}
	if len(resp.X509Svids) == 0 {
		return nil, ErrRefused
	}
	svids := make([]*SVID, 0, len(resp.X509Svids))
	for _, in := range resp.X509Svids {
		svid, err := parse(in)
		if err != nil {
			return nil, err
		}
		svids = append(svids, svid)
	}
	return svids, nil
}

func parse(in *delegatedidentityv1.X509SVIDWithKey) (*SVID, error) {
	if in.X509Svid == nil || len(in.X509Svid.CertChain) == 0 {
		return nil, errors.New("parse certificate: the chain is empty")
	}
	chain := make([]*x509.Certificate, 0, len(in.X509Svid.CertChain))
	for _, der := range in.X509Svid.CertChain {
		c, err := x509.ParseCertificate(der)
		if err != nil {
			return nil, fmt.Errorf("parse certificate: %w", err)
		}
		chain = append(chain, c)
	}
	key, err := x509.ParsePKCS8PrivateKey(in.X509SvidKey)
	if err != nil {
		return nil, fmt.Errorf("parse key: %w", err)
	}
	id := in.X509Svid.Id
	if id == nil {
		return nil, errors.New("parse SVID: the response has no SPIFFE ID")
	}
	return &SVID{
		ID:       "spiffe://" + id.TrustDomain + id.Path,
		NotAfter: chain[0].NotAfter,
		Chain:    chain,
		Key:      key,
	}, nil
}
