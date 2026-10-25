package libv2ray

// Дополнение к 2dust/AndroidLibXrayLite: API защиты сокетов, которое ожидает
// плагин flutter_v2ray_client (Libv2ray.useProtector / setProtectorServer).
// Каждый исходящий и слушающий сокет ядра помечается через VpnService.protect(),
// чтобы трафик ядра не зацикливался обратно в туннель.

import (
	"sync"
	"syscall"

	"github.com/xtls/xray-core/transport/internet"
)

// V2RayProtector реализуется на стороне Java (VpnService.protect).
type V2RayProtector interface {
	Protect(fd int64) bool
}

var (
	protectorMu   sync.RWMutex
	protector     V2RayProtector
	protectorOnce sync.Once
)

func protectRaw(network, address string, c syscall.RawConn) error {
	protectorMu.RLock()
	p := protector
	protectorMu.RUnlock()
	if p == nil {
		return nil
	}
	return c.Control(func(fd uintptr) {
		p.Protect(int64(fd))
	})
}

// UseProtector регистрирует защитник сокетов (вызывается один раз при старте).
func UseProtector(p V2RayProtector) {
	protectorMu.Lock()
	protector = p
	protectorMu.Unlock()
	protectorOnce.Do(func() {
		_ = internet.RegisterDialerController(protectRaw)
		_ = internet.RegisterListenerController(protectRaw)
	})
}

// SetProtectorServer оставлен для совместимости: защищаются все сокеты ядра.
func SetProtectorServer(server string, enabled bool) {}
