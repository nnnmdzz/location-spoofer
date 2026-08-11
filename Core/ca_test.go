package main

import (
	"crypto/x509"
	"encoding/pem"
	"testing"
	"time"
)

func TestGenerateCA(t *testing.T) {
	certPEM, keyPEM, err := generateCA()
	if err != nil {
		t.Fatal(err)
	}
	if len(certPEM) == 0 || len(keyPEM) == 0 {
		t.Fatal("empty CA output")
	}
	cert := parseCertificatePEM(t, certPEM)
	if !cert.IsCA {
		t.Fatal("certificate is not a CA")
	}
	if cert.Subject.CommonName != "Location Spoofer CA" {
		t.Fatalf("unexpected CA common name: %q", cert.Subject.CommonName)
	}
	if len(cert.Subject.Organization) != 1 || cert.Subject.Organization[0] != "Location Spoofer" {
		t.Fatalf("unexpected CA organization: %v", cert.Subject.Organization)
	}
	if time.Until(cert.NotAfter).Hours() < 360*24 {
		t.Fatal("CA validity is too short")
	}
	if _, err := parseCA(certPEM, keyPEM); err != nil {
		t.Fatal(err)
	}
}

func TestGenerateCAUsesUniquePrivateKeysAndSerialNumbers(t *testing.T) {
	firstCertPEM, firstKey, err := generateCA()
	if err != nil {
		t.Fatal(err)
	}
	secondCertPEM, secondKey, err := generateCA()
	if err != nil {
		t.Fatal(err)
	}
	if string(firstKey) == string(secondKey) {
		t.Fatal("generated CA private keys must not be deterministic")
	}
	firstCert := parseCertificatePEM(t, firstCertPEM)
	secondCert := parseCertificatePEM(t, secondCertPEM)
	if firstCert.SerialNumber.Cmp(secondCert.SerialNumber) == 0 {
		t.Fatal("generated CA serial numbers must not be deterministic")
	}
}

func parseCertificatePEM(t *testing.T, certPEM []byte) *x509.Certificate {
	t.Helper()
	block, _ := pem.Decode(certPEM)
	if block == nil {
		t.Fatal("invalid cert PEM")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	return cert
}
