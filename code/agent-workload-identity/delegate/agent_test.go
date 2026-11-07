package main

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	delegatedidentityv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/agent/delegatedidentity/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	vmA = "spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/vm-a"
	vmB = "spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/vm-b"
)

var expiry = time.Date(2030, 1, 2, 3, 4, 5, 0, time.UTC)

// fakeAgent is a fake DelegatedIdentity server on a Unix socket.
type fakeAgent struct {
	delegatedidentityv1.UnimplementedDelegatedIdentityServer
	resp *delegatedidentityv1.SubscribeToX509SVIDsResponse
	err  error

	mu   sync.Mutex
	pids []int32
}

func startFakeAgent(t *testing.T, resp *delegatedidentityv1.SubscribeToX509SVIDsResponse, err error) (*fakeAgent, string) {
	t.Helper()
	f := &fakeAgent{resp: resp, err: err}
	socket := filepath.Join(t.TempDir(), "admin.sock")
	lis, lerr := net.Listen("unix", socket)
	if lerr != nil {
		t.Fatal(lerr)
	}
	srv := grpc.NewServer()
	delegatedidentityv1.RegisterDelegatedIdentityServer(srv, f)
	go func() { _ = srv.Serve(lis) }()
	t.Cleanup(srv.Stop)
	return f, socket
}

func (f *fakeAgent) SubscribeToX509SVIDs(req *delegatedidentityv1.SubscribeToX509SVIDsRequest, stream grpc.ServerStreamingServer[delegatedidentityv1.SubscribeToX509SVIDsResponse]) error {
	f.mu.Lock()
	f.pids = append(f.pids, req.Pid)
	f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	return stream.Send(f.resp)
}

// answer is the answer of an agent with one SVID for each id, in order.
func answer(ids ...string) *delegatedidentityv1.SubscribeToX509SVIDsResponse {
	resp := &delegatedidentityv1.SubscribeToX509SVIDsResponse{}
	for _, id := range ids {
		u, _ := url.Parse(id)
		resp.X509Svids = append(resp.X509Svids, &delegatedidentityv1.X509SVIDWithKey{
			X509Svid: &types.X509SVID{
				CertChain: [][]byte{[]byte("cert of " + id)},
				Id:        &types.SPIFFEID{TrustDomain: u.Host, Path: u.Path},
				ExpiresAt: expiry.Unix(),
			},
			X509SvidKey: []byte("secret key of " + id),
		})
	}
	return resp
}

func TestFetchSVID(t *testing.T) {
	tests := []struct {
		name    string
		resp    *delegatedidentityv1.SubscribeToX509SVIDsResponse
		err     error
		wantIs  error
		wantErr []string // every text must be in the error
	}{
		{name: "one SVID with the expected ID", resp: answer(vmA)},
		{name: "the expected SVID is the second", resp: answer(vmB, vmA)},
		{name: "only the SVID of another VM", resp: answer(vmB), wantIs: errIDMismatch, wantErr: []string{vmA, vmB}},
		{name: "zero SVIDs", resp: answer(), wantIs: errRefused},
		{name: "permission denied", err: status.Error(codes.PermissionDenied, "no identity issued"), wantErr: []string{"no identity issued"}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			fake, socket := startFakeAgent(t, tc.resp, tc.err)

			got, err := fetchSVID(t.Context(), socket, 4242, vmA)

			if len(fake.pids) != 1 || fake.pids[0] != 4242 {
				t.Fatalf("pids sent to the agent = %v, want [4242]", fake.pids)
			}
			if tc.wantIs != nil && !errors.Is(err, tc.wantIs) {
				t.Fatalf("error = %v, want %v", err, tc.wantIs)
			}
			if tc.wantIs != nil || len(tc.wantErr) > 0 {
				if err == nil || got != nil {
					t.Fatalf("got %v and error %v, want an error and no SVID", got, err)
				}
				for _, w := range tc.wantErr {
					if !strings.Contains(err.Error(), w) {
						t.Errorf("error = %v, want text %q", err, w)
					}
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if got.id != vmA || !got.notAfter.Equal(expiry) || string(got.key) != "secret key of "+vmA {
				t.Errorf("got id %q, notAfter %v, key %q", got.id, got.notAfter, got.key)
			}
		})
	}
}

func TestSVIDFormatHidesKey(t *testing.T) {
	s := svid{id: vmA, notAfter: expiry, key: []byte("secret key")}
	for _, verb := range []string{"%v", "%+v", "%#v", "%s"} {
		for _, v := range []any{s, &s} {
			if out := fmt.Sprintf(verb, v); strings.Contains(out, "secret") {
				t.Errorf("%s output shows the key: %s", verb, out)
			}
		}
	}
}
