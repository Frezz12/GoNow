export interface User {
  id: string
  email: string
  displayName: string
  emailVerified: boolean
  birthDate: string | null
  city: string | null
  occupation: string | null
  bio: string | null
  interests: string[]
  rating: number
  relationshipStatus: string | null
  locationLabel: string | null
  latitude: number | null
  longitude: number | null
  showDistance: boolean
  profileComplete: boolean
  createdAt: string
}

export interface AuthData {
  user: User
  tokens: {
    accessToken: string
    refreshToken: string
    accessTokenExpiresAt: string
  }
}

export interface Device {
  deviceId: string
  deviceName: string
  platform: 'web'
}

export interface ApiErrorBody {
  code: string
  message: string
  fields?: Record<string, string>
  requestId: string
}

export interface ApiResponse<T> {
  data: T
  meta?: Record<string, unknown>
}
