package testutil

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"math/big"
	"net"
	"net/url"
	"path/filepath"
	"sync"
	"testing"
	"time"

	delegatedidentityv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/agent/delegatedidentity/v1"
	"github.com/spiffe/spire-api-sdk/proto/spire/api/types"
	"google.golang.org/grpc"
)

// FakeAgent is a fake DelegatedIdentity server on a Unix socket.
// Set Response or Err before the first call.
type FakeAgent struct {
	delegatedidentityv1.UnimplementedDelegatedIdentityServer

	Socket   string
	Response *delegatedidentityv1.SubscribeToX509SVIDsResponse
	Err      error

	mu   sync.Mutex
	pids []int32
}

// StartFakeAgent starts the fake server. The test stops it at the end.
func StartFakeAgent(t *testing.T) *FakeAgent {
	t.Helper()
	f := &FakeAgent{Socket: filepath.Join(t.TempDir(), "admin.sock")}
	lis, err := net.Listen("unix", f.Socket)
	if err != nil {
		t.Fatal(err)
	}
	srv := grpc.NewServer()
	delegatedidentityv1.RegisterDelegatedIdentityServer(srv, f)
	go func() { _ = srv.Serve(lis) }()
	t.Cleanup(srv.Stop)
	return f
}

// Calls returns the pids of all requests that the server got.
func (f *FakeAgent) Calls() []int32 {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]int32(nil), f.pids...)
}

func (f *FakeAgent) SubscribeToX509SVIDs(req *delegatedidentityv1.SubscribeToX509SVIDsRequest, stream grpc.ServerStreamingServer[delegatedidentityv1.SubscribeToX509SVIDsResponse]) error {
	f.mu.Lock()
	f.pids = append(f.pids, req.Pid)
	f.mu.Unlock()
	if f.Err != nil {
		return f.Err
	}
	return stream.Send(f.Response)
}

// NewSVID makes a self-signed certificate with the URI SAN id and an ECDSA
// key. It returns the answer of an agent with this one SVID, the DER
// certificate and the PKCS#8 key.
func NewSVID(t *testing.T, id *url.URL, notAfter time.Time) (resp *delegatedidentityv1.SubscribeToX509SVIDsResponse, certDER, keyDER []byte) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "test svid"},
		NotBefore:    notAfter.Add(-time.Hour),
		NotAfter:     notAfter,
		URIs:         []*url.URL{id},
	}
	certDER, err = x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	keyDER, err = x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	resp = &delegatedidentityv1.SubscribeToX509SVIDsResponse{
		X509Svids: []*delegatedidentityv1.X509SVIDWithKey{{
			X509Svid: &types.X509SVID{
				CertChain: [][]byte{certDER},
				Id:        &types.SPIFFEID{TrustDomain: id.Host, Path: id.Path},
				ExpiresAt: notAfter.Unix(),
			},
			X509SvidKey: keyDER,
		}},
	}
	return resp, certDER, keyDER
}

// NewSVIDs makes an answer of an agent with one SVID for each id, in order.
func NewSVIDs(t *testing.T, ids []*url.URL, notAfter time.Time) *delegatedidentityv1.SubscribeToX509SVIDsResponse {
	t.Helper()
	out := &delegatedidentityv1.SubscribeToX509SVIDsResponse{}
	for _, id := range ids {
		resp, _, _ := NewSVID(t, id, notAfter)
		out.X509Svids = append(out.X509Svids, resp.X509Svids...)
	}
	return out
}
