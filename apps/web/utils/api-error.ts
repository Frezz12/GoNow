import type { ApiErrorBody } from './types'

export class ApiError extends Error {
  code: string
  fields?: Record<string, string>
  requestId?: string
  status: number

  constructor(status: number, body: ApiErrorBody) {
    super(body.message)
    this.status = status
    this.code = body.code
    this.fields = body.fields
    this.requestId = body.requestId
  }
}
