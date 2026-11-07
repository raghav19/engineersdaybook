package agent_test

import (
	"crypto/ecdsa"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"testing"
	"time"

	delegatedidentityv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/agent/delegatedidentity/v1"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/agent"
	"github.com/raghav19/engineersdaybook/code/agent-workload-identity/delegate/internal/testutil"
)

const spiffeID = "spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/vm-a"

func TestFetchX509SVID(t *testing.T) {
	id, _ := url.Parse(spiffeID)
	notAfter := time.Date(2030, 1, 2, 3, 4, 5, 0, time.UTC)
	good, certDER, _ := testutil.NewSVID(t, id, notAfter)

	tests := []struct {
		name    string
		resp    *delegatedidentityv1.SubscribeToX509SVIDsResponse
		err     error
		wantErr func(error) bool
	}{
		{name: "one SVID", resp: good},
		{
			name:    "zero SVIDs",
			resp:    &delegatedidentityv1.SubscribeToX509SVIDsResponse{},
			wantErr: func(err error) bool { return errors.Is(err, agent.ErrRefused) },
		},
		{
			name: "permission denied",
			err:  status.Error(codes.PermissionDenied, "no identity issued"),
			wantErr: func(err error) bool {
				return status.Code(errors.Unwrap(err)) == codes.PermissionDenied && !errors.Is(err, agent.ErrRefused)
			},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			fake := testutil.StartFakeAgent(t)
			fake.Response, fake.Err = tc.resp, tc.err

			all, err := agent.FetchX509SVIDs(t.Context(), fake.Socket, 4242)
			if calls := fake.Calls(); len(calls) != 1 || calls[0] != 4242 {
				t.Fatalf("pids sent to the agent = %v, want [4242]", calls)
			}
			if tc.wantErr != nil {
				if err == nil || !tc.wantErr(err) {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if len(all) != 1 {
				t.Fatalf("got %d SVIDs, want 1", len(all))
			}
			got := all[0]
			if got.ID != spiffeID {
				t.Errorf("ID = %q, want %q", got.ID, spiffeID)
			}
			if !got.NotAfter.Equal(notAfter) {
				t.Errorf("NotAfter = %v, want %v", got.NotAfter, notAfter)
			}
			if len(got.Chain) != 1 || string(got.Chain[0].Raw) != string(certDER) {
				t.Errorf("chain does not hold the certificate of the agent")
			}
			if len(got.Chain[0].URIs) != 1 || got.Chain[0].URIs[0].String() != spiffeID {
				t.Errorf("URI SAN = %v, want %s", got.Chain[0].URIs, spiffeID)
			}
			if _, ok := got.Key.(*ecdsa.PrivateKey); !ok {
				t.Errorf("key type = %T, want *ecdsa.PrivateKey", got.Key)
			}
		})
	}
}

func TestFetchX509SVIDBadData(t *testing.T) {
	id, _ := url.Parse(spiffeID)

	tests := []struct {
		name   string
		mutate func(*delegatedidentityv1.X509SVIDWithKey)
		want   string
	}{
		{"bad certificate", func(s *delegatedidentityv1.X509SVIDWithKey) { s.X509Svid.CertChain[0] = []byte("x") }, "certificate"},
		{"empty chain", func(s *delegatedidentityv1.X509SVIDWithKey) { s.X509Svid.CertChain = nil }, "certificate"},
		{"bad key", func(s *delegatedidentityv1.X509SVIDWithKey) { s.X509SvidKey = []byte("x") }, "key"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			fake := testutil.StartFakeAgent(t)
			resp, _, _ := testutil.NewSVID(t, id, time.Now().Add(time.Hour))
			tc.mutate(resp.X509Svids[0])
			fake.Response = resp
			_, err := agent.FetchX509SVIDs(t.Context(), fake.Socket, 1)
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error = %v, want text %q", err, tc.want)
			}
		})
	}
}

func TestSVIDFormatHidesKey(t *testing.T) {
	id, _ := url.Parse(spiffeID)
	fake := testutil.StartFakeAgent(t)
	var keyDER []byte
	fake.Response, _, keyDER = testutil.NewSVID(t, id, time.Now().Add(time.Hour))
	all, err := agent.FetchX509SVIDs(t.Context(), fake.Socket, 1)
	if err != nil {
		t.Fatal(err)
	}
	got := all[0]
	key := got.Key.(*ecdsa.PrivateKey)
	for _, verb := range []string{"%v", "%+v", "%#v", "%s"} {
		for _, v := range []any{got, *got} {
			out := fmt.Sprintf(verb, v)
			if strings.Contains(out, key.D.String()) || strings.Contains(out, string(keyDER)) {
				t.Errorf("%s output shows the private key", verb)
			}
		}
	}
}

func TestFetchX509SVIDsReturnsAllInOrder(t *testing.T) {
	var ids []*url.URL
	for _, s := range []string{spiffeID, "spiffe://mcp.local/other", "spiffe://mcp.local/third"} {
		u, _ := url.Parse(s)
		ids = append(ids, u)
	}
	fake := testutil.StartFakeAgent(t)
	fake.Response = testutil.NewSVIDs(t, ids, time.Now().Add(time.Hour))

	got, err := agent.FetchX509SVIDs(t.Context(), fake.Socket, 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != len(ids) {
		t.Fatalf("got %d SVIDs, want %d", len(got), len(ids))
	}
	for i := range ids {
		if got[i].ID != ids[i].String() {
			t.Errorf("SVID %d has ID %q, want %q", i, got[i].ID, ids[i])
		}
	}
}
