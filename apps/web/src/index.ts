export function p95(latencies: number[]): number {
  if (!Array.isArray(latencies) || latencies.length === 0) return 0
  const s = [...latencies].sort((a, b) => a - b)
  const idx = Math.min(s.length - 1, Math.floor(0.95 * (s.length - 1)))
  return s[idx]
}
