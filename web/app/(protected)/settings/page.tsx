'use client'

import { useEffect, useState, Suspense } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Profile, Group, GroupMember } from '@/lib/types'
import { displayName, isPremium, FREE_GROUP_LIMIT } from '@/lib/utils'
import BottomNav from '@/components/BottomNav'

const STORAGE_KEY = 'splitx_active_group'

function SettingsContent() {
  const router = useRouter()
  const supabase = createClient()

  const [currentUser, setCurrentUser] = useState<Profile | null>(null)
  const [groups, setGroups] = useState<Group[]>([])
  const [loading, setLoading] = useState(true)

  // Profile
  const [displayNameVal, setDisplayNameVal] = useState('')
  const [savingProfile, setSavingProfile] = useState(false)

  // Create group
  const [showCreateGroup, setShowCreateGroup] = useState(false)
  const [newGroupName, setNewGroupName] = useState('')
  const [savingGroup, setSavingGroup] = useState(false)
  const [groupError, setGroupError] = useState('')

  // Delete account
  const [confirmingDelete, setConfirmingDelete] = useState(false)
  const [deletingAccount, setDeletingAccount] = useState(false)
  const [deleteError, setDeleteError] = useState('')

  async function load() {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    const { data: profile } = await supabase.from('profiles').select('*').eq('id', user.id).single()
    if (profile) { setCurrentUser(profile); setDisplayNameVal(profile.display_name ?? '') }

    const { data: gmRows } = await supabase
      .from('group_members').select('group_id').eq('user_id', user.id).order('joined_at')

    if (gmRows && gmRows.length > 0) {
      const groupIds = gmRows.map((g: { group_id: string }) => g.group_id)
      const { data: grpRows } = await supabase.from('groups').select('*').in('id', groupIds)
      setGroups(grpRows ?? [])
    }

    setLoading(false)
  }

  useEffect(() => { load() }, [])

  async function handleSaveProfile(e: React.FormEvent) {
    e.preventDefault()
    setSavingProfile(true)
    const { data: { user } } = await supabase.auth.getUser()
    if (user) await supabase.from('profiles').update({ display_name: displayNameVal.trim() || null }).eq('id', user.id)
    setSavingProfile(false)
    await load()
  }

  async function handleCreateGroup(e: React.FormEvent) {
    e.preventDefault()
    setGroupError('')
    if (!newGroupName.trim()) return
    if (!isPremium(currentUser) && groups.length >= FREE_GROUP_LIMIT) {
      setGroupError('The free plan includes one group. Subscribe in the SplitX iOS app for more.')
      return
    }
    setSavingGroup(true)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { setGroupError('Not signed in.'); setSavingGroup(false); return }

    const { data: grp, error: grpErr } = await supabase
      .from('groups').insert({ name: newGroupName.trim(), created_by: user.id })
      .select().single()
    if (grpErr || !grp) { setGroupError(grpErr?.message ?? 'Failed to create group.'); setSavingGroup(false); return }

    const { error: memberErr } = await supabase
      .from('group_members').insert({ group_id: grp.id, user_id: user.id })
    if (memberErr) { setGroupError('Group created but could not add you: ' + memberErr.message); setSavingGroup(false); return }

    setSavingGroup(false)
    setShowCreateGroup(false)
    setNewGroupName('')
    localStorage.setItem(STORAGE_KEY, grp.id)
    await load()
    router.push(`/settings/group/${grp.id}`)
  }

  async function handleSignOut() {
    await supabase.auth.signOut()
    router.push('/auth/login')
  }

  async function handleDeleteAccount() {
    setDeletingAccount(true)
    setDeleteError('')
    // Same edge function the iOS app uses; the browser session attaches the
    // user's token, and the function deletes only that user (RLS cascades).
    const { error } = await supabase.functions.invoke('delete-account', { method: 'POST' })
    if (error) {
      setDeleteError(error.message || 'Could not delete your account. Please try again.')
      setDeletingAccount(false)
      return
    }
    await supabase.auth.signOut()
    router.push('/auth/login')
  }

  if (loading) return (
    <div style={{ minHeight: '100dvh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--ios-bg)' }}>
      <div style={{ color: 'var(--ios-label-2)' }}>Loading…</div>
    </div>
  )

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--ios-bg)' }}>
      <div style={{
        background: 'rgba(255,255,255,0.85)', backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
        borderBottom: '0.5px solid var(--ios-separator)',
        paddingTop: 'calc(env(safe-area-inset-top, 0px) + 12px)',
        position: 'sticky', top: 0, zIndex: 40,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', padding: '0 16px 12px' }}>
          <button onClick={() => router.push('/dashboard')}
            style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 4, color: 'var(--ios-blue)', display: 'flex', alignItems: 'center', gap: 4, fontFamily: 'inherit', fontSize: 17, flexShrink: 0 }}>
            <svg width="10" height="16" viewBox="0 0 10 16" fill="none">
              <path d="M8 2L2 8L8 14" stroke="var(--ios-blue)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
            </svg>
            Home
          </button>
          <div style={{ flex: 1, textAlign: 'center', fontSize: 20, fontWeight: 700 }}>Settings</div>
          <div style={{ width: 60, flexShrink: 0 }} />
        </div>
      </div>

      <div className="safe-bottom" style={{ padding: '20px 16px' }}>

        {/* ── Profile ── */}
        <div className="section-header" style={{ paddingLeft: 0 }}>Profile</div>
        <form onSubmit={handleSaveProfile}>
          <div className="card" style={{ marginBottom: 8 }}>
            <div className="list-row" style={{ cursor: 'default' }}>
              <label style={{ color: 'var(--ios-label-2)', fontSize: 15, minWidth: 80 }}>Name</label>
              <input className="ios-input" placeholder="Your name" value={displayNameVal} onChange={e => setDisplayNameVal(e.target.value)} />
            </div>
            <div className="list-row" style={{ cursor: 'default' }}>
              <label style={{ color: 'var(--ios-label-2)', fontSize: 15, minWidth: 80 }}>Email</label>
              <span style={{ fontSize: 15, color: 'var(--ios-label-2)' }}>{currentUser?.email}</span>
            </div>
          </div>
          <button className="btn-secondary" type="submit" disabled={savingProfile} style={{ marginBottom: 28 }}>
            {savingProfile ? 'Saving…' : 'Save Profile'}
          </button>
        </form>

        {/* ── Groups ── */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
          <div className="section-header" style={{ paddingLeft: 0, marginBottom: 0 }}>Groups</div>
          {(isPremium(currentUser) || groups.length < FREE_GROUP_LIMIT) && (
            <button
              onClick={() => { setShowCreateGroup(v => !v); setGroupError('') }}
              style={{ background: 'none', border: 'none', color: 'var(--ios-blue)', fontSize: 15, fontWeight: 500, cursor: 'pointer', fontFamily: 'inherit' }}
            >
              {showCreateGroup ? 'Cancel' : '+ New Group'}
            </button>
          )}
        </div>

        {showCreateGroup && (
          <form onSubmit={handleCreateGroup} style={{ marginBottom: 16 }}>
            <div className="card" style={{ marginBottom: 8 }}>
              <div className="list-row" style={{ cursor: 'default' }}>
                <input className="ios-input" placeholder="Group name" value={newGroupName}
                  onChange={e => setNewGroupName(e.target.value)} autoFocus />
              </div>
            </div>
            <button className="btn-primary" type="submit" disabled={savingGroup || !newGroupName.trim()}>
              {savingGroup ? 'Creating…' : 'Create Group'}
            </button>
            {groupError && <p style={{ fontSize: 13, color: 'var(--ios-red)', marginTop: 8 }}>{groupError}</p>}
          </form>
        )}

        {groups.length > 0 ? (
          <div className="card" style={{ marginBottom: 28 }}>
            {groups.map((g, i) => (
              <div key={g.id} className="list-row"
                style={{ cursor: 'pointer', borderBottom: i < groups.length - 1 ? '0.5px solid var(--ios-separator)' : 'none' }}
                onClick={() => router.push(`/settings/group/${g.id}`)}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 15, fontWeight: 500 }}>{g.name}</div>
                </div>
                <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                  <path d="M6 4L10 8L6 12" stroke="var(--ios-label-3)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
              </div>
            ))}
          </div>
        ) : (
          !showCreateGroup && (
            <div style={{ color: 'var(--ios-label-2)', fontSize: 15, marginBottom: 28, padding: '12px 0' }}>
              No groups yet. Create one to start splitting.
            </div>
          )
        )}

        {/* ── Subscription ── */}
        <div className="section-header" style={{ paddingLeft: 0 }}>Subscription</div>
        <div className="card" style={{ marginBottom: 28, padding: 16 }}>
          {isPremium(currentUser) ? (
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <span style={{ fontSize: 15, fontWeight: 500 }}>✨ SplitX Premium</span>
              <span style={{ fontSize: 13, color: '#34c759', fontWeight: 500 }}>Active</span>
            </div>
          ) : (
            <>
              <div style={{ fontSize: 15, fontWeight: 500, marginBottom: 6 }}>Upgrade to SplitX Premium</div>
              <p style={{ fontSize: 14, color: 'var(--ios-label-2)', margin: 0, lineHeight: 1.5 }}>
                Share groups and add up to 1,000 transactions per year, shared with your Apple Family.
                Subscriptions are available in the <strong>SplitX iOS app</strong> — open it on your iPhone
                and go to <strong>Settings → Upgrade to SplitX Premium</strong>.
              </p>
            </>
          )}
        </div>

        {/* ── Sign out ── */}
        <div style={{ marginTop: 16 }}>
          <button onClick={handleSignOut} style={{
            width: '100%', padding: '14px', background: 'var(--ios-surface)', border: 'none',
            borderRadius: 'var(--radius)', color: 'var(--ios-red)', fontSize: 17, fontWeight: 500,
            cursor: 'pointer', fontFamily: 'inherit',
          }}>
            Sign Out
          </button>
        </div>

        {/* ── Delete account ── */}
        <div style={{ marginTop: 12 }}>
          {!confirmingDelete ? (
            <button onClick={() => { setConfirmingDelete(true); setDeleteError('') }} style={{
              width: '100%', padding: '14px', background: 'none', border: 'none',
              color: 'var(--ios-red)', fontSize: 15, cursor: 'pointer', fontFamily: 'inherit',
            }}>
              Delete Account
            </button>
          ) : (
            <div className="card" style={{ padding: 16 }}>
              <p style={{ fontSize: 14, color: 'var(--ios-label-2)', margin: '0 0 12px', lineHeight: 1.5 }}>
                This permanently deletes your account and personal data. Shared transactions in groups you belong to will remain for the other members. This can&apos;t be undone.
              </p>
              <button onClick={handleDeleteAccount} disabled={deletingAccount} style={{
                width: '100%', padding: '14px', background: 'var(--ios-red)', border: 'none',
                borderRadius: 'var(--radius)', color: '#fff', fontSize: 17, fontWeight: 600,
                cursor: deletingAccount ? 'default' : 'pointer', fontFamily: 'inherit', marginBottom: 8, opacity: deletingAccount ? 0.7 : 1,
              }}>
                {deletingAccount ? 'Deleting…' : 'Permanently Delete Account'}
              </button>
              <button onClick={() => setConfirmingDelete(false)} disabled={deletingAccount} style={{
                width: '100%', padding: '12px', background: 'none', border: 'none',
                color: 'var(--ios-blue)', fontSize: 15, cursor: 'pointer', fontFamily: 'inherit',
              }}>
                Cancel
              </button>
              {deleteError && <p style={{ fontSize: 13, color: 'var(--ios-red)', marginTop: 8 }}>{deleteError}</p>}
            </div>
          )}
        </div>
      </div>

      <BottomNav active="settings" groupId={groups[0]?.id ?? null} />
    </div>
  )
}

export default function SettingsPage() {
  return <Suspense><SettingsContent /></Suspense>
}
