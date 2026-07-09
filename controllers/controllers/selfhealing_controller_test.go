package controllers

import (
	"os"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestOwnerDeployment(t *testing.T) {
	cases := []struct {
		name string
		pod  corev1.Pod
		want string
	}{
		{
			name: "replicaset owner strips hash suffix",
			pod: corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					OwnerReferences: []metav1.OwnerReference{
						{Kind: "ReplicaSet", Name: "demo-api-6f9c9d8b7"},
					},
				},
			},
			want: "demo-api",
		},
		{
			name: "no owner references",
			pod:  corev1.Pod{},
			want: "",
		},
		{
			name: "owner is not a replicaset",
			pod: corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{
					OwnerReferences: []metav1.OwnerReference{
						{Kind: "DaemonSet", Name: "kured"},
					},
				},
			},
			want: "",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := ownerDeployment(&tc.pod)
			if got != tc.want {
				t.Errorf("ownerDeployment() = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestLoadConfigFromEnvDefaults(t *testing.T) {
	for _, key := range []string{
		"MEMORY_THRESHOLD_PERCENT", "RESTART_AFTER",
		"MAX_FAILED_PODS_BEFORE_ROLLBACK", "ROLLBACK_WINDOW",
		"UNHEALTHY_NODE_CONDITIONS",
	} {
		os.Unsetenv(key)
	}

	cfg := LoadConfigFromEnv()
	if cfg.MemoryThresholdPercent != 90 {
		t.Errorf("MemoryThresholdPercent default = %d, want 90", cfg.MemoryThresholdPercent)
	}
	if cfg.RestartAfter != 2*time.Minute {
		t.Errorf("RestartAfter default = %v, want 2m", cfg.RestartAfter)
	}
	if cfg.MaxFailedPodsBeforeRollback != 3 {
		t.Errorf("MaxFailedPodsBeforeRollback default = %d, want 3", cfg.MaxFailedPodsBeforeRollback)
	}
}

func TestLoadConfigFromEnvOverrides(t *testing.T) {
	os.Setenv("MEMORY_THRESHOLD_PERCENT", "75")
	os.Setenv("RESTART_AFTER", "90s")
	defer os.Unsetenv("MEMORY_THRESHOLD_PERCENT")
	defer os.Unsetenv("RESTART_AFTER")

	cfg := LoadConfigFromEnv()
	if cfg.MemoryThresholdPercent != 75 {
		t.Errorf("MemoryThresholdPercent = %d, want 75", cfg.MemoryThresholdPercent)
	}
	if cfg.RestartAfter != 90*time.Second {
		t.Errorf("RestartAfter = %v, want 90s", cfg.RestartAfter)
	}
}
