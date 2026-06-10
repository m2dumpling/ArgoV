package sub

import (
	"encoding/base64"
	"fmt"
	"os"
	"strings"

	"github.com/m2dumpling/ArgoV/core/internal/config"
)

// GenerateLinks builds the proxy links based on current configs
func GenerateLinks(user config.User, argov map[string]string, xray *config.XrayConfig, serverIP string) string {
	links := ""
	uuid := user.UUID
	nodeName := argov["NODE_NAME"]
	if nodeName == "" {
		nodeName = "ArgoV"
	}

	// 1. Generate Fake Nodes for non-default users
	if user.Name != "default" {
		totalUsed := user.UsedUp + user.UsedDown
		remStr := "无限"
		if user.QuotaBytes > 0 {
			rem := user.QuotaBytes - totalUsed
			if rem < 0 {
				rem = 0
			}
			remStr = formatBytes(rem)
		}
		links += fmt.Sprintf("vless://00000000-0000-0000-0000-000000000000@127.0.0.1:443?encryption=none&security=tls&type=ws#🎯剩余流量: %s\n", remStr)
		// simplified reset day
		if user.ResetDay > 0 {
			links += fmt.Sprintf("vless://00000000-0000-0000-0000-000000000000@127.0.0.1:443?encryption=none&security=tls&type=ws#距离重置日: %d 号\n", user.ResetDay)
		}
	}

	// 2. Generate actual links (VLESS/VMESS/Reality/Hysteria2/SS)
	// Example VLESS WS
	argoDomain := argov["LAST_ARGO_DOMAIN"]
	if argov["ARGO_MODE"] == "fixed-token" {
		argoDomain = argov["ARGO_FIXED_DOMAIN"]
	}
	cdnDomain := argov["CDN_DOMAIN"]
	cdnPort := argov["CDN_PORT"]
	if cdnDomain == "" {
		cdnDomain = argoDomain
	}
	if cdnPort == "" {
		cdnPort = "443"
	}
	if argoDomain != "" {
		// VLESS
		vless := fmt.Sprintf("vless://%s@%s:%s?encryption=none&security=tls&sni=%s&type=ws&host=%s&path=%%2Fvless-argo%%3Fed%%3D2560#%s-VLESS",
			uuid, cdnDomain, cdnPort, argoDomain, argoDomain, nodeName)
		links += vless + "\n"

		// VMESS
		vmessJson := fmt.Sprintf(`{"v":"2","ps":"%s-VMess","add":"%s","port":"%s","id":"%s","aid":"0","scy":"none","net":"ws","type":"none","host":"%s","path":"/vmess-argo?ed=2560","tls":"tls","sni":"%s","alpn":"","fp":""}`,
			nodeName, cdnDomain, cdnPort, uuid, argoDomain, argoDomain)
		links += "vmess://" + base64.StdEncoding.EncodeToString([]byte(vmessJson)) + "\n"
	}

	// Reality
	if xray != nil {
		for _, inbound := range xray.Inbounds {
			if inbound.Tag == "reality" && inbound.StreamSettings.RealitySettings != nil {
				rport := inbound.Port
				rs := ""
				if len(inbound.StreamSettings.RealitySettings.ServerNames) > 0 {
					rs = inbound.StreamSettings.RealitySettings.ServerNames[0]
				}
				rpub := inbound.StreamSettings.RealitySettings.PublicKey
				rsid := ""
				if len(inbound.StreamSettings.RealitySettings.ShortIds) > 0 {
					rsid = inbound.StreamSettings.RealitySettings.ShortIds[0]
				}
				rsidQuery := ""
				if rsid != "" {
					rsidQuery = "&sid=" + rsid
				}
				if rport != nil && serverIP != "" {
					links += fmt.Sprintf("vless://%s@%s:%v?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=%s&pbk=%s&fp=chrome%s#%s-Reality\n",
						uuid, serverIP, rport, rs, rpub, rsidQuery, nodeName)
				}
			}

			// Hysteria2
			if inbound.Tag == "hy2" {
				hport := inbound.Port
				hsni := "www.bing.com"
				if inbound.StreamSettings.TLSSettings != nil && inbound.StreamSettings.TLSSettings.ServerName != "" {
					hsni = inbound.StreamSettings.TLSSettings.ServerName
				}
				// Hysteria port hopping
				hmport := ""
				if inbound.StreamSettings.Finalmask != nil && inbound.StreamSettings.Finalmask.QuicParams != nil && inbound.StreamSettings.Finalmask.QuicParams.UDPHop != nil && inbound.StreamSettings.Finalmask.QuicParams.UDPHop.Ports != nil {
					hmport = fmt.Sprintf("%v", inbound.StreamSettings.Finalmask.QuicParams.UDPHop.Ports)
				} else if inbound.StreamSettings.HysteriaSettings != nil && inbound.StreamSettings.HysteriaSettings.QuicParams != nil && inbound.StreamSettings.HysteriaSettings.QuicParams.UDPHop != nil && inbound.StreamSettings.HysteriaSettings.QuicParams.UDPHop.Ports != nil {
					// ports could be an array or string
					portsVal := inbound.StreamSettings.HysteriaSettings.QuicParams.UDPHop.Ports
					if arr, ok := portsVal.([]interface{}); ok && len(arr) > 0 {
						hmport = fmt.Sprintf("%v", arr[0])
					} else {
						hmport = fmt.Sprintf("%v", portsVal)
					}
				}
				hmportQs := ""
				if hmport != "" {
					hmportQs = "&mport=" + hmport
				}
				if hport != nil && serverIP != "" {
					links += fmt.Sprintf("hysteria2://%s@%s:%v?sni=%s&insecure=1&allowInsecure=1&alpn=h3%s#%s-Hy2\n",
						uuid, serverIP, hport, hsni, hmportQs, nodeName)
				}
			}
		}
	}

	// Custom Links (only for default user)
	if user.Name == "default" {
		customLinksPath := "/etc/xray/custom_links.txt"
		if data, err := os.ReadFile(customLinksPath); err == nil {
			lines := strings.Split(string(data), "\n")
			for _, line := range lines {
				line = strings.TrimSpace(line)
				if line != "" {
					links += line + "\n"
				}
			}
		}
	}

	return base64.StdEncoding.EncodeToString([]byte(strings.TrimSpace(links)))
}

func formatBytes(b int64) string {
	if b == 0 {
		return "0 B"
	}
	if b >= 1073741824 {
		return fmt.Sprintf("%.2f GB", float64(b)/1073741824)
	}
	if b >= 1048576 {
		return fmt.Sprintf("%.2f MB", float64(b)/1048576)
	}
	if b >= 1024 {
		return fmt.Sprintf("%.2f KB", float64(b)/1024)
	}
	return fmt.Sprintf("%d B", b)
}
