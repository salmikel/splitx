'use client'

import { useEffect, useState, useRef, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Profile, Group, Invitation } from '@/lib/types'
import { displayName } from '@/lib/utils'
import BottomNav from '@/components/BottomNav'

function SettingsContent() {
  const router = useRouter()
  const params = useSearchParams()
  const supabase = createClient()

  const [currentUser, setCurrentUser] = useState<Profile | null>(null)
  const [group, setGroup] = useState<Group | null>(null)
  const [members, setMembers] = useState<Profile[]>([])
  const [invitations, setInvitations] = useState<Invitation[]>([])
  const [loading, setLoading] = useState(true)

  const [inviteEmail, setInviteEmail] = useState('')
  const [inviting, setInviting] = useState(false)
  const [inviteMsg, setInviteMsg] = useState('')

  const [groupName, setGroupName] = useState('')
  const [creatingGroup, setCreatingGroup] = useState(params.get('create') === '1')
  const [newGroupName, setNewGroupName] = useState('')
  const [savingGroup, setSavingGroup] = useState(false)

  const [displayNameVal, setDisplayNameVal] = useState('')
  const [savingProfile, setSavingProfile] = useState(false)

  const [csvMsg, setCsvMsg] = useState('')
  const [csvLoading, setCsvLoading] = useState(false)
  const fileRef = useRef<HTMLInputElement>(null)

  async function load() {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    const { data: profile } = await supabase.from('profiles').select('*').eq('id', user.id).single()
    if (profile) { setCurrentUser(profile); setDisplayNameVal(profile.display_name ?? '') }

    const { data: gm } = await supabase
      .from('group_members').select('group_id').eq('user_id', user.id).order('joined_at').limit(1).single()

    if (!gm) { setLoading(false); return }

    const { data: grp } = await supabase.from('groups').select('*').eq('id', gm.group_id).single()
    if (grp) { setGroup(grp); setGroupName(grp.name) }

    const { data: memberRows } = await supabase
      .from('group_members').select('*, profile:profiles(*)').eq('group_id', gm.group_id)
    setMembers((memberRows ?? []).map((m: { profile: Profile }) => m.profile))

    const { data: invs } = await supabase
      .from('invitations').select('*').eq('group_id', gm.group_id).eq('status', 'pending')
    setInvitations(invs ?? [])

    setLoading(false)
  }

  useEffect(() => { load() }, [])

  async function handleInvite(e: React.FormEvent) {
    e.preventDefault()
    if (!inviteEmail.trim() || !group) return
    setInviting(true)
    setInviteMsg('')

    const { error } = await supabase.from('invitations').insert({
      group_id: group.id,
      invited_by: currentUser?.id,
      email: inviteEmail.trim().toLowerCase(),
    })

    setInviting(false)
    if (error) { setInviteMsg('Error: ' + error.message); return }
    setInviteMsg('Invitation sent to ' + inviteEmail.trim())
    setInviteEmail('')
    await load()
  }

  async function handleCreateGroup(e: React.FormEvent) {
    e.preventDefault()
    if (!newGroupName.trim() || !currentUser) return
    setSavingGroup(true)

    const { data: grp, error: grpErr } = await supabase
      .from('groups')
      .insert({ name: newGroupName.trim(), created_by: currentUser.id })
      .select().single()

    if (grpErr || !grp) { setSavingGroup(false); return }

    await supabase.from('group_members').insert({ group_id: grp.id, user_id: currentUser.id })
    setSavingGroup(false)
    setCreatingGroup(false)
    await load()
    router.push('/dashboard')
  }

  async function handleSaveProfile(e: React.FormEvent) {
    e.preventDefault()
    if (!currentUser) return
    setSavingProfile(true)
    await supabase.from('profiles').update({ display_name: displayNameVal.trim() || null }).eq('id', currentUser.id)
    setSavingProfile(false)
    await load()
  }

  async function handleSignOut() {
    await supabase.auth.signOut()
    router.push('/auth/login')
  }

  async function handleCSV(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file || !group) return
    setCsvLoading(true)
    setCsvMsg('')

    const text = await file.text()
    const lines = text.split('\n').map((l) => l.trim()).filter(Boolean)
    if (lines.length < 2) { setCsvMsg('CSV is empty'); setCsvLoading(false); return }

    const headers = lines[0].split(',').map((h) => h.trim())
    const dateIdx = headers.findIndex((h) => /date/i.test(h))
    const descIdx = headers.findIndex((h) => /desc/i.test(h))
    const amtIdx = headers.findIndex((h) => /amount/i.test(h))
    const paidIdx = headers.findIndex((h) => /paid.?by/i.test(h))

    // Find all "Percentage Owed by UserX" columns
    const pctCols: { idx: number; name: string }[] = []
    headers.forEach((h, i) => {
      const m = h.match(/percentage owed by (.+)/i)
      if (m) pctCols.push({ idx: i, name: m[1].trim() })
    })

    if (dateIdx < 0 || descIdx < 0 || amtIdx < 0 || paidIdx < 0) {
      setCsvMsg('Missing required columns: Date, Description, Amount, Paid By')
      setCsvLoading(false)
      return
    }

    let imported = 0
    let skipped = 0

    for (let i = 1; i < lines.length; i++) {
      const cols = lines[i].split(',').map((c) => c.trim())
      const desc = cols[descIdx]
      const amt = parseFloat(cols[amtIdx])
      const rawDate = cols[dateIdx]
      const paidByName = cols[paidIdx]

      if (!desc || !amt || !rawDate) { skipped++; continue }

      // Parse date
      let parsedDate = rawDate
      const dateObj = new Date(rawDate)
      if (!isNaN(dateObj.getTime())) {
        parsedDate = dateObj.toISOString().slice(0, 10)
      }

      // Resolve paid_by profile
      const paidProfile = members.find((m) =>
        displayName(m).toLowerCase() === paidByName.toLowerCase() ||
        m.email.toLowerCase() === paidByName.toLowerCase()
      )

      const { data: tx, error: txErr } = await supabase
        .from('transactions')
        .insert({ group_id: group.id, description: desc, amount: amt, paid_by: paidProfile?.id ?? null, type: 'expense', date: parsedDate })
        .select().single()

      if (txErr || !tx) { skipped++; continue }

      // Build splits from percentage columns
      if (pctCols.length > 0) {
        const splitRows = pctCols.map(({ idx, name }) => {
          const pct = parseFloat(cols[idx]) || 0
          const profile = members.find((m) =>
            displayName(m).toLowerCase() === name.toLowerCase() ||
            m.email.toLowerCase() === name.toLowerCase()
          )
          return {
            transaction_id: tx.id,
            user_id: profile?.id ?? members[0]?.id,
            percentage: pct,
            amount: parseFloat(((pct / 100) * amt).toFixed(2)),
          }
        }).filter((s) => s.user_id)

        if (splitRows.length > 0) {
          await supabase.from('transaction_splits').insert(splitRows)
        }
      }
      imported++
    }

    setCsvMsg(`Imported ${imported} transaction${imported !== 1 ? 's' : ''}${skipped > 0 ? `, skipped ${skipped}` : ''}.`)
    setCsvLoading(false)
    if (fileRef.current) fileRef.current.value = ''
  }

  if (loading) {
    return (
      <div style={{ minHeight: '100dvh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--ios-bg)' }}>
        <div style={{ color: 'var(--ios-label-2)' }}>Loading…</div>
      </div>
    )
  }

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--ios-bg)' }}>
      {/* Header */}
      <div style={{
        background: 'rgba(255,255,255,0.85)',
        backdropFilter: 'blur(20px)',
        WebkitBackdropFilter: 'blur(20px)',
        borderBottom: '0.5px solid var(--ios-separator)',
        padding: '12px 20px',
        paddingTop: 'calc(env(safe-area-inset-top, 0px) + 12px)',
        position: 'sticky',
        top: 0,
        zIndex: 40,
      }}>
        <div style={{ fontSize: 28, fontWeight: 700 }}>Settings</div>
      </div>

      <div className="safe-bottom" style={{ padding: '20px 16px' }}>
        {/* Profile */}
        <div className="section-header" style={{ paddingLeft: 0 }}>Profile</div>
        <form onSubmit={handleSaveProfile}>
          <div className="card" style={{ marginBottom: 8 }}>
            <div className="list-row" style={{ cursor: 'default' }}>
              <label style={{ color: 'var(--ios-label-2)', fontSize: 15, minWidth: 80 }}>Name</label>
              <input className="ios-input" placeholder="Your name" value={displayNameVal} onChange={(e) => setDisplayNameVal(e.target.value)} />
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

        {/* Group */}
        {group ? (
          <>
            <div className="section-header" style={{ paddingLeft: 0 }}>Group · {group.name}</div>
            <div className="card" style={{ marginBottom: 8 }}>
              {members.map((m) => (
                <div key={m.id} className="list-row" style={{ cursor: 'default' }}>
                  <div style={{
                    width: 36, height: 36, borderRadius: 18,
                    background: 'var(--ios-blue)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    color: 'white', fontWeight: 600, fontSize: 15, flexShrink: 0,
                  }}>
                    {(m.display_name ?? m.email)[0].toUpperCase()}
                  </div>
                  <div>
                    <div style={{ fontWeight: 500 }}>{displayName(m)}</div>
                    <div style={{ fontSize: 13, color: 'var(--ios-label-2)' }}>{m.email}</div>
                  </div>
                  {m.id === currentUser?.id && (
                    <div style={{ marginLeft: 'auto', fontSize: 12, color: 'var(--ios-blue)', background: 'rgba(0,122,255,0.1)', padding: '2px 8px', borderRadius: 10 }}>You</div>
                  )}
                </div>
              ))}
            </div>

            {/* Invite */}
            <div className="section-header" style={{ paddingLeft: 0, marginTop: 20 }}>Invite Members</div>
            <form onSubmit={handleInvite}>
              <div className="card" style={{ marginBottom: 8 }}>
                <div className="list-row" style={{ cursor: 'default' }}>
                  <input
                    className="ios-input"
                    type="email"
                    inputMode="email"
                    placeholder="friend@example.com"
                    value={inviteEmail}
                    onChange={(e) => setInviteEmail(e.target.value)}
                  />
                </div>
              </div>
              <button className="btn-primary" type="submit" disabled={inviting || !inviteEmail.trim()} style={{ marginBottom: 8 }}>
                {inviting ? 'Sending…' : 'Send Invite'}
              </button>
            </form>
            {inviteMsg && (
              <p style={{ fontSize: 13, color: inviteMsg.startsWith('Error') ? 'var(--ios-red)' : 'var(--ios-green)', marginBottom: 12 }}>
                {inviteMsg}
              </p>
            )}

            {invitations.length > 0 && (
              <>
                <div className="section-header" style={{ paddingLeft: 0 }}>Pending Invites</div>
                <div className="card" style={{ marginBottom: 28 }}>
                  {invitations.map((inv) => (
                    <div key={inv.id} className="list-row" style={{ cursor: 'default' }}>
                      <div style={{ flex: 1 }}>
                        <div style={{ fontSize: 15 }}>{inv.email}</div>
                        <div style={{ fontSize: 12, color: 'var(--ios-label-3)' }}>
                          Expires {new Date(inv.expires_at).toLocaleDateString()}
                        </div>
                      </div>
                      <div style={{ fontSize: 12, color: 'var(--ios-orange)', background: 'rgba(255,149,0,0.12)', padding: '2px 8px', borderRadius: 10 }}>
                        Pending
                      </div>
                    </div>
                  ))}
                </div>
              </>
            )}

            {/* CSV Import */}
            <div className="section-header" style={{ paddingLeft: 0 }}>Import CSV</div>
            <div className="card" style={{ marginBottom: 8 }}>
              <div style={{ padding: 16 }}>
                <p style={{ fontSize: 13, color: 'var(--ios-label-2)', marginBottom: 12, lineHeight: 1.5 }}>
                  Columns: <strong>Date, Description, Amount, Paid By</strong>,
                  then <strong>Percentage Owed by [Name]</strong> for each member.
                </p>
                <input
                  ref={fileRef}
                  type="file"
                  accept=".csv,text/csv"
                  onChange={handleCSV}
                  disabled={csvLoading}
                  style={{ fontSize: 14, color: 'var(--ios-blue)', display: 'block', width: '100%' }}
                />
                {csvLoading && <p style={{ fontSize: 13, color: 'var(--ios-label-2)', marginTop: 8 }}>Importing…</p>}
                {csvMsg && (
                  <p style={{ fontSize: 13, color: csvMsg.startsWith('Error') || csvMsg.includes('Missing') ? 'var(--ios-red)' : 'var(--ios-green)', marginTop: 8 }}>
                    {csvMsg}
                  </p>
                )}
              </div>
            </div>
          </>
        ) : (
          <>
            <div className="section-header" style={{ paddingLeft: 0 }}>Group</div>
            {creatingGroup ? (
              <form onSubmit={handleCreateGroup}>
                <div className="card" style={{ marginBottom: 8 }}>
                  <div className="list-row" style={{ cursor: 'default' }}>
                    <input className="ios-input" placeholder="Group name" value={newGroupName} onChange={(e) => setNewGroupName(e.target.value)} autoFocus />
                  </div>
                </div>
                <div style={{ display: 'flex', gap: 12 }}>
                  <button className="btn-secondary" type="button" onClick={() => setCreatingGroup(false)}>Cancel</button>
                  <button className="btn-primary" type="submit" disabled={savingGroup || !newGroupName.trim()}>
                    {savingGroup ? 'Creating…' : 'Create'}
                  </button>
                </div>
              </form>
            ) : (
              <button className="btn-primary" onClick={() => setCreatingGroup(true)} style={{ marginBottom: 28 }}>
                Create a Group
              </button>
            )}
          </>
        )}

        {/* Sign out */}
        <div style={{ marginTop: 32 }}>
          <button
            onClick={handleSignOut}
            style={{
              width: '100%',
              padding: '14px',
              background: 'var(--ios-surface)',
              border: 'none',
              borderRadius: 'var(--radius)',
              color: 'var(--ios-red)',
              fontSize: 17,
              fontWeight: 500,
              cursor: 'pointer',
              fontFamily: 'inherit',
            }}
          >
            Sign Out
          </button>
        </div>
      </div>

      <BottomNav active="settings" groupId={group?.id ?? null} />
    </div>
  )
}

export default function SettingsPage() {
  return (
    <Suspense>
      <SettingsContent />
    </Suspense>
  )
}
