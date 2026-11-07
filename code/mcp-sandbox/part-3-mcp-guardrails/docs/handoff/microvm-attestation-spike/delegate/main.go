// Spike: delegate. It sends one pid to the admin socket of the SPIRE agent and
// prints what comes back. It never prints the private key.
package main

import (
	"context"
	"crypto/x509"
	"flag"
	"fmt"
	"os"
	"time"

	delegatedidentityv1 "github.com/spiffe/spire-api-sdk/proto/spire/api/agent/delegatedidentity/v1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	sock := flag.String("socket", "", "admin socket path")
	pid := flag.Int("pid", 0, "pid to attest")
	flag.Parse()

	conn, err := grpc.NewClient("unix://"+*sock, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		fail(err)
	}
	defer conn.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	stream, err := delegatedidentityv1.NewDelegatedIdentityClient(conn).
		SubscribeToX509SVIDs(ctx, &delegatedidentityv1.SubscribeToX509SVIDsRequest{Pid: int32(*pid)})
	if err != nil {
		fail(err)
	}
	resp, err := stream.Recv()
	if err != nil {
		fail(err)
	}
	fmt.Printf("svids=%d\n", len(resp.X509Svids))
	for _, s := range resp.X509Svids {
		cert, err := x509.ParseCertificate(s.X509Svid.CertChain[0])
		if err != nil {
			fail(err)
		}
		key, err := x509.ParsePKCS8PrivateKey(s.X509SvidKey)
		if err != nil {
			fail(err)
		}
		fmt.Printf("spiffe_id=spiffe://%s%s\nnot_after=%s\nkey_parsed=%T\nuri_san=%v\n",
			s.X509Svid.Id.TrustDomain, s.X509Svid.Id.Path, cert.NotAfter.UTC().Format(time.RFC3339), key, cert.URIs)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "ERROR:", err)
	os.Exit(1)
}
