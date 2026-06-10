package config

import (
	"bufio"
	"os"
	"strings"
)

var ArgovConfPath = "/etc/xray/argov.conf"

func ReadArgovConf() (map[string]string, error) {
	f, err := os.Open(ArgovConfPath)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	env := make(map[string]string)
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			k := strings.TrimSpace(parts[0])
			v := strings.TrimSpace(parts[1])
			// remove quotes if present
			if len(v) >= 2 && ((strings.HasPrefix(v, `"`) && strings.HasSuffix(v, `"`)) || (strings.HasPrefix(v, `'`) && strings.HasSuffix(v, `'`))) {
				v = v[1 : len(v)-1]
			}
			env[k] = v
		}
	}
	return env, scanner.Err()
}
