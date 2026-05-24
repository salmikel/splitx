'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [sent, setSent] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const supabase = createClient()

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!email.trim()) return
    setLoading(true)
    setError('')

    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim().toLowerCase(),
      options: {
        emailRedirectTo: `${location.origin}/auth/callback`,
      },
    })

    setLoading(false)
    if (error) setError(error.message)
    else setSent(true)
  }

  return (
    <div
      style={{
        minHeight: '100dvh',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '32px 20px',
        paddingTop: 'env(safe-area-inset-top, 32px)',
        background: 'var(--ios-bg)',
      }}
    >
      {/* Logo / wordmark */}
      <div style={{ marginBottom: 48, textAlign: 'center' }}>
        <div
          style={{
            width: 72,
            height: 72,
            borderRadius: 18,
            background: 'var(--ios-blue)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            margin: '0 auto 16px',
          }}
        >
          <span style={{ fontSize: 36, color: 'white', fontWeight: 700 }}>S</span>
        </div>
        <h1 style={{ fontSize: 28, fontWeight: 700, marginBottom: 4 }}>SplitX</h1>
        <p style={{ color: 'var(--ios-label-2)', fontSize: 15 }}>Split expenses effortlessly</p>
      </div>

      {sent ? (
        <div className="card" style={{ width: '100%', maxWidth: 380, padding: 24, textAlign: 'center' }}>
          <div style={{ fontSize: 48, marginBottom: 16 }}>✉️</div>
          <h2 style={{ fontSize: 20, fontWeight: 600, marginBottom: 8 }}>Check your email</h2>
          <p style={{ color: 'var(--ios-label-2)', fontSize: 15, lineHeight: 1.5 }}>
            We sent a magic link to <strong>{email}</strong>. Tap the link to sign in.
          </p>
          <button
            onClick={() => setSent(false)}
            style={{ marginTop: 20, color: 'var(--ios-blue)', background: 'none', border: 'none', fontSize: 15, cursor: 'pointer' }}
          >
            Use a different email
          </button>
        </div>
      ) : (
        <form onSubmit={handleSubmit} style={{ width: '100%', maxWidth: 380 }}>
          <div className="card" style={{ marginBottom: 16 }}>
            <div className="list-row" style={{ cursor: 'default' }}>
              <label style={{ color: 'var(--ios-label-2)', fontSize: 15, minWidth: 52 }}>Email</label>
              <input
                className="ios-input"
                type="email"
                placeholder="you@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoFocus
                autoComplete="email"
                inputMode="email"
              />
            </div>
          </div>

          {error && (
            <p style={{ color: 'var(--ios-red)', fontSize: 13, marginBottom: 12, paddingLeft: 4 }}>
              {error}
            </p>
          )}

          <button className="btn-primary" type="submit" disabled={loading || !email.trim()}>
            {loading ? 'Sending…' : 'Continue with Email'}
          </button>

          <p style={{ textAlign: 'center', color: 'var(--ios-label-3)', fontSize: 13, marginTop: 16 }}>
            We'll send you a magic link — no password needed.
          </p>
        </form>
      )}
    </div>
  )
}
