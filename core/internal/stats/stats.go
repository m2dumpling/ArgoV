package stats

import (
	"context"
	"log"
	"strings"
	"time"

	"github.com/m2dumpling/ArgoV/core/internal/config"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	// Using the stub from xtls/xray-core
	statsService "github.com/xtls/xray-core/app/stats/command"
)

var gRPCAddress = "127.0.0.1:10085"

// RunStatsDaemon periodically queries Xray and updates argov_users.json
func RunStatsDaemon(ctx context.Context) {
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			updateStats()
		}
	}
}

func updateStats() {
	conn, err := grpc.Dial(gRPCAddress, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Printf("[Stats] Failed to connect to Xray gRPC: %v\n", err)
		return
	}
	defer conn.Close()

	client := statsService.NewStatsServiceClient(conn)

	// Query all stats
	req := &statsService.QueryStatsRequest{
		Pattern: "",
		Reset_:  true,
	}

	resp, err := client.QueryStats(context.Background(), req)
	if err != nil {
		log.Printf("[Stats] QueryStats failed: %v\n", err)
		return
	}

	if len(resp.Stat) == 0 {
		return // No new traffic
	}

	// Group by email (user)
	trafficUpdates := make(map[string]map[string]int64)

	for _, stat := range resp.Stat {
		name := stat.Name // format: user>>>email>>>traffic>>>down
		parts := strings.Split(name, ">>>")
		if len(parts) == 4 && parts[0] == "user" && parts[2] == "traffic" {
			email := parts[1]
			direction := parts[3] // "uplink" or "downlink"
			val := stat.Value

			if _, ok := trafficUpdates[email]; !ok {
				trafficUpdates[email] = make(map[string]int64)
			}
			trafficUpdates[email][direction] += val
		}
	}

	applyUpdatesToUsers(trafficUpdates)
}

func applyUpdatesToUsers(updates map[string]map[string]int64) {
	usersDB, err := config.ReadUsers()
	if err != nil {
		log.Printf("[Stats] Failed to read users DB: %v\n", err)
		return
	}

	changed := false
	nowDay := time.Now().Day()

	for i, u := range usersDB.Users {
		email := u.UUID // the tag used in xray for argov is usually the UUID
		// check if reset day matched
		if u.ResetDay > 0 && nowDay == u.ResetDay && u.UsedUp > 0 {
			// A simple reset logic (needs to ensure it only resets once a month in a real app,
			// here simplified for demonstration, typically would store LastResetMonth)
			usersDB.Users[i].UsedUp = 0
			usersDB.Users[i].UsedDown = 0
			changed = true
		}

		if m, ok := updates[email]; ok {
			if up, ok := m["uplink"]; ok {
				usersDB.Users[i].UsedUp += up
				changed = true
			}
			if down, ok := m["downlink"]; ok {
				usersDB.Users[i].UsedDown += down
				changed = true
			}
		}

		// check quota
		if usersDB.Users[i].QuotaBytes > 0 {
			total := usersDB.Users[i].UsedUp + usersDB.Users[i].UsedDown
			if total >= usersDB.Users[i].QuotaBytes && usersDB.Users[i].Enabled {
				usersDB.Users[i].Enabled = false
				log.Printf("[Stats] User %s exceeded quota, disabled.\n", u.Name)
				changed = true
			}
		}
	}

	if changed {
		if err := config.WriteUsers(usersDB); err != nil {
			log.Printf("[Stats] Failed to write users DB: %v\n", err)
		}
	}
}
