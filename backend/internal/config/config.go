package config

import (
	"errors"
	"net"
	"net/url"
	"strconv"
	"strings"
)

type Config struct {
	Address, DatabaseURL, Environment string
	RealtimeOrigins                   []string
}

// ParseRealtimeOrigins accepts exact serialized HTTP origins, never patterns.
func ParseRealtimeOrigins(raw string) ([]string, error) {
	if strings.TrimSpace(raw) == "" {
		return nil, nil
	}
	var origins []string
	for _, part := range strings.Split(raw, ",") {
		origin := strings.TrimSpace(part)
		u, err := url.Parse(origin)
		if err != nil || u == nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" || u.User != nil || u.Path != "" || u.RawQuery != "" || u.ForceQuery || u.Fragment != "" || strings.ContainsAny(origin, "*#\\") || origin != u.Scheme+"://"+u.Host {
			return nil, errors.New("REALTIME_ORIGINS must contain exact http(s) origins")
		}
		if port := u.Port(); port != "" {
			n, err := strconv.Atoi(port)
			if err != nil || n < 1 || n > 65535 {
				return nil, errors.New("invalid REALTIME_ORIGINS port")
			}
		}
		origins = append(origins, origin)
	}
	return origins, nil
}

func Load(getenv func(string) string) (Config, error) {
	env := getenv("APP_ENV")
	if env == "" {
		env = "development"
	}
	if env != "development" && env != "production" && env != "test" {
		return Config{}, errors.New("APP_ENV must be development, test or production")
	}
	host := getenv("HOST")
	if host == "" {
		host = "127.0.0.1"
	}
	port := getenv("PORT")
	if port == "" {
		port = "8080"
	}
	n, err := strconv.Atoi(port)
	if err != nil || n < 1 || n > 65535 {
		return Config{}, errors.New("PORT must be between 1 and 65535")
	}
	databaseURL := getenv("DATABASE_URL")
	if databaseURL != "" {
		u, err := url.Parse(databaseURL)
		if err != nil || (u.Scheme != "postgres" && u.Scheme != "postgresql") || u.Hostname() == "" {
			return Config{}, errors.New("DATABASE_URL must be a PostgreSQL URL")
		}
	}
	if env == "production" && databaseURL == "" {
		return Config{}, errors.New("DATABASE_URL required in production")
	}
	origins, err := ParseRealtimeOrigins(getenv("REALTIME_ORIGINS"))
	if err != nil {
		return Config{}, err
	}
	return Config{Address: net.JoinHostPort(host, port), DatabaseURL: databaseURL, Environment: env, RealtimeOrigins: origins}, nil
}
