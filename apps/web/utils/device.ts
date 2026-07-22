import type { Device } from './types'

function getOrCreateDeviceId(): string {
  if (import.meta.server) return 'ssr'
  const key = 'gonow_device_id'
  let id = localStorage.getItem(key)
  if (!id) {
    id = crypto.randomUUID()
    localStorage.setItem(key, id)
  }
  return id
}

export function getDevice(): Device {
  return {
    deviceId: getOrCreateDeviceId(),
    deviceName: 'Web Browser',
    platform: 'web',
  }
}
