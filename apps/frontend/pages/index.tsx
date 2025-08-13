import { useEffect, useState } from 'react'

export default function Home() {
  const [health, setHealth] = useState<string>("loading...")
  const [runId, setRunId] = useState<string>("")
  const [runItem, setRunItem] = useState<any>(null)

  const apiBase = (() => {
    if (typeof window === 'undefined') return process.env.NEXT_PUBLIC_API_BASE
    const host = window.location.hostname
    const isLocal = host === 'localhost' || host === '127.0.0.1' || host === '::1' || host === '[::1]'
    return isLocal ? 'http://localhost:8000' : process.env.NEXT_PUBLIC_API_BASE
  })()

  useEffect(() => {
    fetch(apiBase + "/healthz")
      .then(r => r.json())
      .then(j => setHealth(JSON.stringify(j)))
      .catch(e => setHealth("error: " + e.message))
  }, [])

  const startRun = async () => {
    const r = await fetch(apiBase + "/api/runs", {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ graph_version_id: 'gv_015', dataset_id: 'ds_demo', config: {}, phi_mode: 'deidentified' })
    })
    const j = await r.json()
    setRunId(j.run_id)
  }

  const fetchItem = async () => {
    const r = await fetch(apiBase + "/api/run_items/sample")
    const j = await r.json()
    setRunItem(j)
  }

  return (
    <div style={{ padding: 24, fontFamily: 'system-ui, sans-serif' }}>
      <h1>ClinTestbench</h1>
      <p>API health: {health}</p>
      <div style={{ display: 'flex', gap: 12 }}>
        <button onClick={startRun}>Start Run</button>
        <button onClick={fetchItem}>Fetch Run Item</button>
      </div>
      {runId && <p>Started run: {runId}</p>}
      {runItem && (
        <pre style={{ background: '#f5f5f5', padding: 12, marginTop: 12 }}>
          {JSON.stringify(runItem, null, 2)}
        </pre>
      )}
    </div>
  )
}
