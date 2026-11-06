package sub

import (
	"encoding/base64"
	"encoding/json"
	"net/url"
	"strings"
	"testing"

	"github.com/m2dumpling/ArgoV/core/internal/config"
)

func TestArgoLinksFollowPresentInbounds(t *testing.T) {
	for _, tc := range []struct {
		name                 string
		tags                 []string
		mode                 string
		wantVLESS, wantVMess bool
	}{
		{"both", []string{"vless-ws", "vmess-ws"}, "temp", true, true},
		{"only vless", []string{"vless-ws"}, "temp", true, false},
		{"only vmess", []string{"vmess-ws"}, "fixed-token", false, true},
		{"removed", nil, "temp", false, false},
		{"skipped", []string{"vless-ws", "vmess-ws"}, "skip", false, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			settings := map[string]string{"NODE_NAME": `节点 "one" #1`, "ARGO_MODE": tc.mode,
				"LAST_ARGO_DOMAIN": "temp.example.com", "ARGO_FIXED_DOMAIN": "fixed.example.com"}
			xray := &config.XrayConfig{}
			for _, tag := range tc.tags {
				xray.Inbounds = append(xray.Inbounds, config.Inbound{Tag: tag, StreamSettings: config.StreamSettings{
					WSSettings: &config.WSSettings{Path: "/custom-" + tag},
				}})
			}
			raw, err := base64.StdEncoding.DecodeString(GenerateLinks(config.User{Name: "default", UUID: "test-uuid"}, settings, xray, ""))
			if err != nil {
				t.Fatal(err)
			}
			var gotVLESS, gotVMess bool
			for _, line := range strings.Split(string(raw), "\n") {
				if strings.HasPrefix(line, "vless://") {
					gotVLESS = true
					u, err := url.Parse(line)
					if err != nil || u.Query().Get("path") != "/custom-vless-ws?ed=2560" {
						t.Fatalf("incorrect VLESS path: %s (%v)", line, err)
					}
				}
				if strings.HasPrefix(line, "vmess://") {
					gotVMess = true
					data, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(line, "vmess://"))
					if err != nil {
						t.Fatal(err)
					}
					var vmess map[string]string
					if err := json.Unmarshal(data, &vmess); err != nil {
						t.Fatal(err)
					}
					if vmess["path"] != "/custom-vmess-ws?ed=2560" || vmess["ps"] != settings["NODE_NAME"]+"-VMess" {
						t.Fatalf("incorrect VMess parameters: %v", vmess)
					}
					if tc.mode == "fixed-token" && vmess["host"] != settings["ARGO_FIXED_DOMAIN"] {
						t.Fatal("fixed host changed")
					}
				}
			}
			if gotVLESS != tc.wantVLESS || gotVMess != tc.wantVMess {
				t.Fatalf("got VLESS=%v VMess=%v, want %v %v", gotVLESS, gotVMess, tc.wantVLESS, tc.wantVMess)
			}
		})
	}
}

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
