import { describe, it, expect } from 'vitest'
import { p95 } from '../src/index'

describe('p95', () => {
  it('returns 0 for empty arrays', () => {
    expect(p95([])).toBe(0)
  })
  it('computes a stable percentile', () => {
    const arr = [10, 20, 30, 40, 50, 60, 70, 80, 90, 200]
    expect(p95(arr)).toBeGreaterThanOrEqual(90)
  })
})
