package config

import (
	"encoding/json"
	"io"
	"os"
	"sync"
)

// ArgovUsers struct represents the root of argov_users.json
type ArgovUsers struct {
	Users []User `json:"users"`
}

// User struct represents individual user settings in argov_users.json
type User struct {
	UUID       string `json:"uuid"`
	Name       string `json:"name"`
	Token      string `json:"token"`
	QuotaBytes int64  `json:"quota_bytes"`
	UsedUp     int64  `json:"used_up"`
	UsedDown   int64  `json:"used_down"`
	ResetDay   int    `json:"reset_day"`
	Enabled    bool   `json:"enabled"`
}

var (
	usersFileMutex sync.RWMutex
	UsersFilePath  = "/etc/xray/argov_users.json"
)

// ReadUsers reads the users database safely
func ReadUsers() (*ArgovUsers, error) {
	usersFileMutex.RLock()
	defer usersFileMutex.RUnlock()

	f, err := os.Open(UsersFilePath)
	if err != nil {
		if os.IsNotExist(err) {
			return &ArgovUsers{Users: []User{}}, nil
		}
		return nil, err
	}
	defer f.Close()

	bytes, err := io.ReadAll(f)
	if err != nil {
		return nil, err
	}

	var data ArgovUsers
	if err := json.Unmarshal(bytes, &data); err != nil {
		return nil, err
	}

	return &data, nil
}

// WriteUsers writes the users database safely
func WriteUsers(data *ArgovUsers) error {
	usersFileMutex.Lock()
	defer usersFileMutex.Unlock()

	bytes, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(UsersFilePath, bytes, 0600)
}
