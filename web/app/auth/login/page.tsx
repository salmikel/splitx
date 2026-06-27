'use client'

import Image from 'next/image'
import { useState } from 'react'
import { useSearchParams } from 'next/navigation'
import { Suspense } from 'react'
import { createClient } from '@/lib/supabase/client'

function LoginForm() {
  const searchParams = useSearchParams()
  const next = searchParams.get('next') ?? '/dashboard'
  const [email, setEmail] = useState('')
  const [sent, setSent] = useState(false)
  const [loading, setLoading] = useState(false)
  const [appleLoading, setAppleLoading] = useState(false)
  // Pre-populate error from URL params (set by /auth/callback on OAuth failure)
  const [error, setError] = useState(searchParams.get('error') ?? '')
  const supabase = createClient()

  async function handleAppleSignIn() {
    setAppleLoading(true)
    setError('')
    const callbackUrl = `${location.origin}/auth/callback?next=${encodeURIComponent(next)}`
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'apple',
      options: { redirectTo: callbackUrl },
    })
    if (error) { setError(error.message); setAppleLoading(false) }
    // on success the page redirects, so no need to reset loading
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!email.trim()) return
    setLoading(true)
    setError('')
    const callbackUrl = `${location.origin}/auth/callback?next=${encodeURIComponent(next)}`
    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim().toLowerCase(),
      options: { emailRedirectTo: callbackUrl },
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
      {/* Logo */}
      <div style={{ marginBottom: 48, textAlign: 'center' }}>
        <Image
          src="/logo.png"
          alt="SplitX"
          width={90}
          height={90}
          style={{ borderRadius: 20, margin: '0 auto 16px', display: 'block' }}
        />
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
        <div style={{ width: '100%', maxWidth: 380 }}>
          {/* Sign in with Apple */}
          <button
            onClick={handleAppleSignIn}
            disabled={appleLoading}
            style={{
              width: '100%',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 10,
              padding: '14px 20px',
              background: '#000',
              color: '#fff',
              border: 'none',
              borderRadius: 12,
              fontSize: 17,
              fontWeight: 600,
              cursor: appleLoading ? 'default' : 'pointer',
              opacity: appleLoading ? 0.6 : 1,
            }}
          >
            <svg width="18" height="22" viewBox="0 0 814 1000" fill="white" xmlns="http://www.w3.org/2000/svg">
              <path d="M788.1 340.9c-5.8 4.5-108.2 62.2-108.2 190.5 0 148.4 130.3 200.9 134.2 202.2-.6 3.2-20.7 71.9-68.7 141.9-42.8 61.6-87.5 123.1-155.5 123.1s-85.5-39.5-164-39.5c-76 0-103.7 40.8-165.9 40.8s-105-57.8-155.5-127.4C46 383.7 0 273.6 0 168.1 0 100.4 25.8 35.7 73.2-5.8 110.6-39.5 167.5-60 220.5-60c65.8 0 117.4 39.5 156.8 39.5 37.2 0 95.2-42 165-42 27.7 0 129.9 3.2 198.9 94.4zm-234-181.5c31.1-36.9 53.1-88.1 53.1-139.3 0-7.1-.6-14.3-1.9-20.1-50.6 1.9-110.8 33.7-147.1 75.8-28.5 32.4-55.1 83.6-55.1 135.5 0 7.8 1.3 15.6 1.9 18.1 3.2.6 8.4 1.3 13.6 1.3 45.4 0 102.5-30.4 135.5-71.3z"/>
            </svg>
            {appleLoading ? 'Redirecting…' : 'Sign in with Apple'}
          </button>

          {/* Divider */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, margin: '20px 0' }}>
            <div style={{ flex: 1, height: 1, background: 'var(--ios-separator)' }} />
            <span style={{ color: 'var(--ios-label-3)', fontSize: 13 }}>or</span>
            <div style={{ flex: 1, height: 1, background: 'var(--ios-separator)' }} />
          </div>

          {/* Email form */}
          <form onSubmit={handleSubmit}>
            <div className="card" style={{ marginBottom: 16 }}>
              <div className="list-row" style={{ cursor: 'default' }}>
                <label style={{ color: 'var(--ios-label-2)', fontSize: 15, minWidth: 52 }}>Email</label>
                <input
                  className="ios-input"
                  type="email"
                  placeholder="you@example.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
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

            <p style={{ textAlign: 'center', color: 'var(--ios-label-3)', fontSize: 13, marginTop: 12 }}>
              We'll send you a magic link — no password needed.
            </p>
          </form>
        </div>
      )}
    </div>
  )
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  )
}
