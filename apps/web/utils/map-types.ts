export type ActivityCategory =
  | 'walking'
  | 'sport'
  | 'travel'
  | 'music'
  | 'games'
  | 'food'
  | 'education'
  | 'animals'
  | 'help'
  | 'event'
  | 'other'

export const CATEGORIES: { value: ActivityCategory; label: string; emoji: string }[] = [
  { value: 'walking', label: 'Прогулка', emoji: '🚶' },
  { value: 'sport', label: 'Спорт', emoji: '⚽' },
  { value: 'travel', label: 'Путешествия', emoji: '✈️' },
  { value: 'music', label: 'Музыка', emoji: '🎵' },
  { value: 'games', label: 'Игры', emoji: '🎮' },
  { value: 'food', label: 'Еда', emoji: '🍕' },
  { value: 'education', label: 'Обучение', emoji: '📚' },
  { value: 'animals', label: 'Животные', emoji: '🐾' },
  { value: 'help', label: 'Помощь', emoji: '🤝' },
  { value: 'event', label: 'Мероприятие', emoji: '🎉' },
  { value: 'other', label: 'Другое', emoji: '📌' },
]

export const CATEGORY_COLORS: Record<ActivityCategory, string> = {
  walking: '#22c55e',
  sport: '#ef4444',
  travel: '#3b82f6',
  music: '#a855f7',
  games: '#6366f1',
  food: '#f97316',
  help: '#14b8a6',
  education: '#a16207',
  animals: '#34d399',
  event: '#ec4899',
  other: '#6b7280',
}

export interface MapActivity {
  id: string
  title: string
  category: ActivityCategory
  coordinate: { latitude: number; longitude: number }
  startsAt: string
  participantCount: number
  participantLimit: number | null
  distanceMeters: number | null
  imageUrl: string | null
  isJoined: boolean
}

export interface MapActivitiesEnvelope {
  data: {
    activities: MapActivity[]
    viewport: { south: number; west: number; north: number; east: number }
  }
  meta: {
    count: number
    truncated: boolean
    nextCursor: string | null
  }
}

export interface MapFilterState {
  categories: Set<ActivityCategory>
  onlyAvailable: boolean
}

export const CATEGORY_LABELS: Record<ActivityCategory, string> = Object.fromEntries(
  CATEGORIES.map((c) => [c.value, c.label]),
) as Record<ActivityCategory, string>
