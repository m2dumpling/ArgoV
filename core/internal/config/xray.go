package config

import (
	"encoding/json"
	"io"
	"os"
)

type XrayConfig struct {
	Inbounds []Inbound `json:"inbounds"`
	// ... other fields can be ignored for now
}

type Inbound struct {
	Port           interface{}    `json:"port"` // can be int or string
	Protocol       string         `json:"protocol"`
	Tag            string         `json:"tag"`
	Settings       Settings       `json:"settings"`
	StreamSettings StreamSettings `json:"streamSettings"`
}

type Settings struct {
	Clients []Client `json:"clients"`
}

type Client struct {
	ID    string `json:"id"`
	Email string `json:"email"`
}

type StreamSettings struct {
	TLSSettings      *TLSSettings      `json:"tlsSettings"`
	HysteriaSettings *HysteriaSettings `json:"hysteriaSettings"`
	RealitySettings  *RealitySettings  `json:"realitySettings"`
	Finalmask        *Finalmask        `json:"finalmask"`
}

type TLSSettings struct {
	ServerName string `json:"serverName"`
}

type RealitySettings struct {
	ServerNames []string `json:"serverNames"`
	PublicKey   string   `json:"publicKey"`
	ShortIds    []string `json:"shortIds"`
}

type HysteriaSettings struct {
	QuicParams *QuicParams `json:"quicParams"`
}

type Finalmask struct {
	QuicParams *QuicParams `json:"quicParams"`
}

type QuicParams struct {
	UDPHop *UDPHop `json:"udpHop"`
}

type UDPHop struct {
	Ports interface{} `json:"ports"` // can be string or array
}

var XrayConfigPath = "/etc/xray/config.json"

func ReadXrayConfig() (*XrayConfig, error) {
	f, err := os.Open(XrayConfigPath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	bytes, err := io.ReadAll(f)
	if err != nil {
		return nil, err
	}

	var data XrayConfig
	if err := json.Unmarshal(bytes, &data); err != nil {
		return nil, err
	}

	return &data, nil
}
