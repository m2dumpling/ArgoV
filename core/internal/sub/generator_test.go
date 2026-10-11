package sub

import (
	"encoding/base64"
	"net/url"
	"strings"
	"testing"

	"github.com/m2dumpling/ArgoV/core/internal/config"
)

func TestHY2LegacyIdentityAndClientOptions(t *testing.T) {
	settings := map[string]string{
		"NODE_NAME": "旧节点 #1", "HY2_SNI": "old.example.com",
		"HY2_PIN_SHA256": strings.Repeat("AB:", 31) + "AB",
		"HY2_CONGESTION": "brutal", "HY2_UP_MBPS": "80", "HY2_DOWN_MBPS": "120",
	}
	xray := &config.XrayConfig{Inbounds: []config.Inbound{{
		Tag: "hy2", Port: 24567, StreamSettings: config.StreamSettings{
			TLSSettings: &config.TLSSettings{ServerName: "deployed.example.com"},
		},
	}}}
	user := config.User{Name: "default", UUID: "11111111-1111-4111-8111-111111111111"}
	raw, err := base64.StdEncoding.DecodeString(GenerateLinks(user, settings, xray, "2001:db8::1"))
	if err != nil {
		t.Fatal(err)
	}
	var link *url.URL
	for _, line := range strings.Split(string(raw), "\n") {
		if strings.HasPrefix(line, "hysteria2://") {
			link, err = url.Parse(line)
		}
	}
	if err != nil || link == nil {
		t.Fatalf("missing HY2 link: %v", err)
	}
	if link.Hostname() != "2001:db8::1" || link.Port() != "24567" || link.User.Username() != user.UUID {
		t.Fatal("deployed identity changed")
	}
	for key, expected := range map[string]string{
		"sni": "deployed.example.com", "pinSHA256": strings.Repeat("AB", 32),
		"insecure": "1", "allowInsecure": "0", "up": "120mbps", "down": "80mbps",
	} {
		if link.Query().Get(key) != expected {
			t.Errorf("%s: got %q, want %q", key, link.Query().Get(key), expected)
		}
	}
	if link.Fragment != "旧节点 #1-Hy2" || settings["HY2_SNI"] != "old.example.com" {
		t.Fatal("name or saved settings changed")
	}
}

func TestHY2InvalidPinDoesNotEnableRemovedOption(t *testing.T) {
	if got := hy2ClientOptions(map[string]string{"HY2_PIN_SHA256": "invalid"}, nil); got != "" {
		t.Fatalf("invalid pin exported: %q", got)
	}
}
