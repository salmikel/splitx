'use client'

import { useEffect, useState, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

function InvitePage() {
  const router = useRouter()
  const params = useSearchParams()
  const token = params.get('token')
  const supabase = createClient()

  const [status, setStatus] = useState<'loading' | 'needs_login' | 'joining' | 'done' | 'error'>('loading')
  const [message, setMessage] = useState('')

  useEffect(() => {
    async function handle() {
      if (!token) { setStatus('error'); setMessage('Invalid invitation link.'); return }

      const { data: { user } } = await supabase.auth.getUser()
      if (!user) { setStatus('needs_login'); return }

      // Find invitation by token
      const { data: inv } = await supabase
        .from('invitations')
        .select('*')
        .eq('token', token)
        .eq('status', 'pending')
        .single()

      if (!inv) { setStatus('error'); setMessage('This invitation is invalid or has expired.'); return }
      if (new Date(inv.expires_at) < new Date()) { setStatus('error'); setMessage('This invitation has expired.'); return }

      setStatus('joining')

      // Add user to group
      const { error: memberErr } = await supabase
        .from('group_members')
        .upsert({ group_id: inv.group_id, user_id: user.id }, { onConflict: 'group_id,user_id' })

      if (memberErr) { setStatus('error'); setMessage(memberErr.message); return }

      // Mark invitation accepted
      await supabase.from('invitations').update({ status: 'accepted' }).eq('id', inv.id)

      setStatus('done')
      setTimeout(() => router.push('/dashboard'), 1500)
    }
    handle()
  }, [token, supabase, router])

  const containerStyle: React.CSSProperties = {
    minHeight: '100dvh',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 32,
    background: 'var(--ios-bg)',
    textAlign: 'center',
    gap: 16,
  }

  if (status === 'needs_login') {
    return (
      <div style={containerStyle}>
        <div style={{ fontSize: 48 }}>✉️</div>
        <h2 style={{ fontSize: 22, fontWeight: 700 }}>You've been invited!</h2>
        <p style={{ color: 'var(--ios-label-2)', fontSize: 15 }}>Sign in with your email to accept the invitation.</p>
        <button className="btn-primary" style={{ maxWidth: 300 }} onClick={() => router.push(`/auth/login?next=/invite?token=${token}`)}>
          Sign In to Accept
        </button>
      </div>
    )
  }

  if (status === 'done') {
    return (
      <div style={containerStyle}>
        <div style={{ fontSize: 48 }}>🎉</div>
        <h2 style={{ fontSize: 22, fontWeight: 700 }}>You're in!</h2>
        <p style={{ color: 'var(--ios-label-2)', fontSize: 15 }}>Taking you to your group…</p>
      </div>
    )
  }

  if (status === 'error') {
    return (
      <div style={containerStyle}>
        <div style={{ fontSize: 48 }}>❌</div>
        <h2 style={{ fontSize: 22, fontWeight: 700 }}>Invitation Error</h2>
        <p style={{ color: 'var(--ios-label-2)', fontSize: 15 }}>{message}</p>
        <button className="btn-secondary" style={{ maxWidth: 300 }} onClick={() => router.push('/')}>Go Home</button>
      </div>
    )
  }

  return (
    <div style={containerStyle}>
      <div style={{ fontSize: 15, color: 'var(--ios-label-2)' }}>
        {status === 'joining' ? 'Joining group…' : 'Checking invitation…'}
      </div>
    </div>
  )
}

export default function InvitePageWrapper() {
  return <Suspense><InvitePage /></Suspense>
}
