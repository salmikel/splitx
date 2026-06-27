'use client'

import { useEffect, useState, useRef } from 'react'
import { useRouter, useParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Profile, Group, GroupMember, Invitation } from '@/lib/types'
import { displayName } from '@/lib/utils'

export default function GroupSettingsPage() {
  const router = useRouter()
  const { id } = useParams<{ id: string }>()
  const supabase = createClient()

  const [currentUser, setCurrentUser] = useState<Profile | null>(null)
  const [group, setGroup] = useState<Group | null>(null)
  const [members, setMembers] = useState<Profile[]>([])
  const [invitations, setInvitations] = useState<Invitation[]>([])
  const [loading, setLoading] = useState(true)

  // Defaults
  const [defaultPaidBy, setDefaultPaidBy] = useState('')
  const [defaultSplits, setDefaultSplits] = useState<Record<string, string>>({})
  const [savingDefaults, setSavingDefaults] = useState(false)
  const [defaultsMsg, setDefaultsMsg] = useState('')

  // Invite
  const [inviteEmail, setInviteEmail] = useState('')
  const [inviting, setInviting] = useState(false)
  const [inviteMsg, setInviteMsg] = useState('')

  // CSV Import
  const [csvGroup, setCsvGroup] = useState(id)
  const [allGroups, setAllGroups] = useState<Group[]>([])
  const [csvMsg, setCsvMsg] = useState('')
  const [csvLoading, setCsvLoading] = useState(false)
  const [csvFileName, setCsvFileName] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)

  // Remove member
  const [memberToRemove, setMemberToRemove] = useState<Profile | null>(null)
  const [replacementId, setReplacementId] = useState('')
  const [removingMember, setRemovingMember] = useState(false)
  const [removeError, setRemoveError] = useState('')

  // CSV Export
  const [exportLoading, setExportLoading] = useState(false)
  const [exportMsg, setExportMsg] = useState('')

  async function load() {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    const { data: profile } = await supabase.from('profiles').select('*').eq('id', user.id).single()
    if (profile) setCurrentUser(profile)

    const { data: grp } = await supabase.from('groups').select('*').eq('id', id).single()
    if (!grp) { router.push('/settings'); return }
    setGroup(grp)

    const { data: memberRows } = await supabase
      .from('group_members').select('*, profile:profiles(*)').eq('group_id', id)
    const profiles: Profile[] = (memberRows ?? [])
      .map((m: GroupMember & { profile: Profile }) => m.profile).filter(Boolean)
    setMembers(profiles)

    const { data: invs } = await supabase
      .from('invitations').select('*').eq('group_id', id).eq('status', 'pending')
    setInvitations(invs ?? [])

    // Defaults.
    // If the group already has split assignments for some members, any member
    // not yet listed gets 0% — prevents the total from exceeding 100% when
    // a new member joins a group that already has a full 100% allocation.
    setDefaultPaidBy(grp.default_paid_by ?? '')
    const hasExistingDefaults = grp.default_splits && Object.keys(grp.default_splits).length > 0
    const even = profiles.length > 0 ? (100 / profiles.length).toFixed(2) : '0'
    const dSplits: Record<string, string> = {}
    profiles.forEach(p => {
      dSplits[p.id] = grp.default_splits?.[p.id] != null
        ? String(grp.default_splits[p.id])
        : (hasExistingDefaults ? '0' : even)
    })
    setDefaultSplits(dSplits)

    // All groups for CSV target selector
    const { data: gmRows } = await supabase
      .from('group_members').select('group_id').eq('user_id', user.id)
    if (gmRows && gmRows.length > 0) {
      const groupIds = gmRows.map((g: { group_id: string }) => g.group_id)
      const { data: grpRows } = await supabase.from('groups').select('*').in('id', groupIds)
      setAllGroups(grpRows ?? [])
    }

    setLoading(false)
  }

  useEffect(() => { load() }, [id])

  async function handleSaveDefaults(e: React.FormEvent) {
    e.preventDefault()
    if (!group) return
    setDefaultsMsg('')
    setSavingDefaults(true)
    const splitsObj: Record<string, number> = {}
    members.forEach(m => { splitsObj[m.id] = parseFloat(defaultSplits[m.id] ?? '0') || 0 })
    const { error } = await supabase.from('groups').update({
      default_paid_by: defaultPaidBy || null,
      default_splits: splitsObj,
    }).eq('id', group.id)
    setSavingDefaults(false)
    if (error) { setDefaultsMsg('Error: ' + error.message); return }
    setDefaultsMsg('Defaults saved.')
    await load()
  }

  async function handleInvite(e: React.FormEvent) {
    e.preventDefault()
    if (!inviteEmail.trim() || !group) return
    setInviting(true); setInviteMsg('')
    const res = await fetch('/api/invite', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: inviteEmail.trim(), groupId: group.id, groupName: group.name,
        inviterName: currentUser ? (currentUser.display_name ?? currentUser.email) : 'A friend',
      }),
    })
    const body = await res.json()
    setInviting(false)
    if (!res.ok) { setInviteMsg('Error: ' + body.error); return }
    setInviteMsg('Invitation sent to ' + inviteEmail.trim())
    setInviteEmail('')
    await load()
  }

  async function handleRemoveMember() {
    if (!memberToRemove || !replacementId || !group) return
    setRemovingMember(true)
    setRemoveError('')

    // 1. Reassign paid_by on transactions
    await supabase.from('transactions')
      .update({ paid_by: replacementId })
      .eq('group_id', group.id)
      .eq('paid_by', memberToRemove.id)

    // 2. Reassign / merge transaction splits
    const { data: txRows } = await supabase
      .from('transactions').select('id').eq('group_id', group.id)

    if (txRows && txRows.length > 0) {
      const txIds = txRows.map((t: { id: string }) => t.id)

      const { data: removedSplits } = await supabase
        .from('transaction_splits')
        .select('id,transaction_id,percentage,amount')
        .eq('user_id', memberToRemove.id)
        .in('transaction_id', txIds)

      if (removedSplits && removedSplits.length > 0) {
        const { data: replacementSplits } = await supabase
          .from('transaction_splits')
          .select('id,transaction_id,percentage,amount')
          .eq('user_id', replacementId)
          .in('transaction_id', txIds)

        type SplitRecord = { id: string; transaction_id: string; percentage: number; amount: number }
        const repMap: Record<string, SplitRecord> =
          Object.fromEntries((replacementSplits ?? []).map((s: SplitRecord) => [s.transaction_id, s]))

        // Partition into conflicts and clean reassigns
        const nonConflictIds: string[] = []
        const removedConflictIds: string[] = []
        const conflictPairs: { removed: SplitRecord; replacement: SplitRecord }[] = []

        for (const removed of removedSplits as SplitRecord[]) {
          const existing = repMap[removed.transaction_id]
          if (existing) {
            conflictPairs.push({ removed, replacement: existing })
            removedConflictIds.push(removed.id)
          } else {
            nonConflictIds.push(removed.id)
          }
        }

        // One bulk UPDATE for all clean reassigns
        if (nonConflictIds.length > 0) {
          await supabase.from('transaction_splits')
            .update({ user_id: replacementId })
            .in('id', nonConflictIds)
        }

        // Merge conflicting splits (parallel per-row updates, then one bulk delete)
        await Promise.all(conflictPairs.map(({ removed, replacement }) =>
          supabase.from('transaction_splits')
            .update({ percentage: replacement.percentage + removed.percentage, amount: replacement.amount + removed.amount })
            .eq('id', replacement.id)
        ))
        if (removedConflictIds.length > 0) {
          await supabase.from('transaction_splits').delete().in('id', removedConflictIds)
        }
      }
    }

    // 3. Update group defaults
    const newDefaultPaidBy = group.default_paid_by === memberToRemove.id ? replacementId : group.default_paid_by
    const newDefaultSplits: Record<string, number> = { ...(group.default_splits ?? {}) }
    if (memberToRemove.id in newDefaultSplits) {
      const removedPct = newDefaultSplits[memberToRemove.id]
      delete newDefaultSplits[memberToRemove.id]
      newDefaultSplits[replacementId] = (newDefaultSplits[replacementId] ?? 0) + removedPct
    }
    await supabase.from('groups')
      .update({ default_paid_by: newDefaultPaidBy, default_splits: newDefaultSplits })
      .eq('id', group.id)

    // 4. Remove from group_members
    const { error } = await supabase.from('group_members')
      .delete()
      .eq('group_id', group.id)
      .eq('user_id', memberToRemove.id)

    setRemovingMember(false)
    if (error) { setRemoveError(error.message); return }
    setMemberToRemove(null)
    await load()
  }

  function downloadBlob(content: string, filename: string) {
    const blob = new Blob([content], { type: 'text/csv;charset=utf-8;' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = filename; a.click()
    URL.revokeObjectURL(url)
  }

  async function handleExport() {
    setExportLoading(true); setExportMsg('')
    const { data: txRows } = await supabase
      .from('transactions')
      .select('*, splits:transaction_splits(*)')
      .eq('group_id', id)
      .order('date', { ascending: false })
      .order('created_at', { ascending: false })

    if (!txRows || txRows.length === 0) {
      setExportMsg('No transactions to export.')
      setExportLoading(false); return
    }

    const headers = ['Date', 'Description', 'Amount', 'Paid By',
      ...members.map(m => `Percentage Owed by ${displayName(m)}`)]

    const rows = txRows.map((tx: { date: string; description: string; amount: number; paid_by: string | null; splits: { user_id: string; percentage: number }[] }) => {
      const paidProfile = members.find(m => m.id === tx.paid_by)
      const pctCols = members.map(m => {
        const split = (tx.splits ?? []).find((s: { user_id: string }) => s.user_id === m.id)
        return split ? String((split as { user_id: string; percentage: number }).percentage) : '0'
      })
      return [tx.date, tx.description, String(tx.amount), paidProfile ? displayName(paidProfile) : '', ...pctCols]
    })

    const csv = [headers, ...rows].map(r => r.map(c => `"${String(c).replace(/"/g, '""')}"`).join(',')).join('\n')
    downloadBlob(csv, `${group?.name ?? 'expenses'}-export.csv`)
    setExportMsg(`Exported ${txRows.length} transaction${txRows.length !== 1 ? 's' : ''}.`)
    setExportLoading(false)
  }

  function handleDownloadTemplate() {
    const headers = ['Date', 'Description', 'Amount', 'Paid By',
      ...members.map(m => `Percentage Owed by ${displayName(m)}`)]
    const even = members.length > 0 ? (100 / members.length).toFixed(2) : '0'
    const sample = ['2025-01-15', 'Sample expense', '100.00',
      members[0] ? displayName(members[0]) : 'Name',
      ...members.map(() => even)]
    const csv = [headers, sample].map(r => r.map(c => `"${c}"`).join(',')).join('\n')
    downloadBlob(csv, `${group?.name ?? 'group'}-template.csv`)
  }

  async function handleCSV(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setCsvFileName(file.name)
    const targetGroupId = csvGroup

    // Load members for the target group
    const { data: memberRows } = await supabase
      .from('group_members').select('*, profile:profiles(*)').eq('group_id', targetGroupId)
    const targetMembers: Profile[] = (memberRows ?? [])
      .map((m: GroupMember & { profile: Profile }) => m.profile).filter(Boolean)

    setCsvLoading(true); setCsvMsg('')
    const text = await file.text()

    // Normalise line endings (Windows \r\n → \n, old Mac \r → \n)
    const lines = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n')
      .split('\n').map(l => l.trim()).filter(Boolean)
    if (lines.length < 2) { setCsvMsg('CSV is empty'); setCsvLoading(false); return }

    // Use a proper quoted-CSV parser so quote-wrapped fields (as produced by
    // the exporter) and commas inside values are handled correctly.
    const headers = parseCSVRow(lines[0])
    const dateIdx = headers.findIndex(h => /date/i.test(h))
    const descIdx = headers.findIndex(h => /desc/i.test(h))
    const amtIdx  = headers.findIndex(h => /amount/i.test(h))
    const paidIdx = headers.findIndex(h => /paid.?by/i.test(h))

    // Resolve "Percentage Owed by <Name>" columns to member profiles upfront
    const pctCols: { idx: number; profile: Profile }[] = []
    headers.forEach((h, i) => {
      const m = h.match(/percentage owed by (.+)/i)
      if (!m) return
      const name = m[1].trim()
      const profile = targetMembers.find(p =>
        displayName(p).toLowerCase() === name.toLowerCase() ||
        p.email.toLowerCase() === name.toLowerCase()
      )
      if (profile) pctCols.push({ idx: i, profile })
    })

    if (dateIdx < 0 || descIdx < 0 || amtIdx < 0 || paidIdx < 0) {
      setCsvMsg('Missing required columns: Date, Description, Amount, Paid By')
      setCsvLoading(false); return
    }

    let imported = 0, skipped = 0
    for (let i = 1; i < lines.length; i++) {
      const cols = parseCSVRow(lines[i])
      const desc = cols[descIdx]
      // Strip currency symbols and thousands separators before parsing
      const amt = parseFloat((cols[amtIdx] ?? '').replace(/[$,]/g, ''))
      const rawDate = cols[dateIdx]
      const paidByName = cols[paidIdx]
      if (!desc || !amt || !rawDate) { skipped++; continue }

      let parsedDate = rawDate
      const dateObj = new Date(rawDate)
      if (!isNaN(dateObj.getTime())) parsedDate = dateObj.toISOString().slice(0, 10)

      const paidProfile = targetMembers.find(m =>
        displayName(m).toLowerCase() === paidByName.toLowerCase() ||
        m.email.toLowerCase() === paidByName.toLowerCase()
      )

      const { data: tx, error: txErr } = await supabase.from('transactions')
        .insert({ group_id: targetGroupId, description: desc, amount: amt, paid_by: paidProfile?.id ?? null, type: 'expense', date: parsedDate })
        .select().single()
      if (txErr || !tx) { skipped++; continue }

      if (pctCols.length > 0) {
        const splitRows = pctCols.map(({ idx, profile }) => {
          const pct = parseFloat(cols[idx] ?? '0') || 0
          return { transaction_id: tx.id, user_id: profile.id, percentage: pct, amount: parseFloat(((pct / 100) * amt).toFixed(2)) }
        })
        if (splitRows.length > 0) await supabase.from('transaction_splits').insert(splitRows)
      }
      imported++
    }

    setCsvMsg(`Imported ${imported} transaction${imported !== 1 ? 's' : ''}${skipped > 0 ? `, skipped ${skipped}` : ''}.`)
    setCsvLoading(false)
    if (fileRef.current) fileRef.current.value = ''
    setCsvFileName('')
  }

  // RFC-4180 quoted-CSV row parser.
  // Strips surrounding quotes, handles commas inside quoted fields,
  // and converts "" escape sequences to literal quote characters.
  function parseCSVRow(line: string): string[] {
    const fields: string[] = []
    let field = ''
    let inQuotes = false
    let i = 0
    while (i < line.length) {
      const ch = line[i]
      if (inQuotes) {
        if (ch === '"') {
          if (line[i + 1] === '"') { field += '"'; i += 2 } // escaped quote
          else { inQuotes = false; i++ }                     // closing quote
        } else { field += ch; i++ }
      } else {
        if (ch === '"') { inQuotes = true; i++ }
        else if (ch === ',') { fields.push(field.trim()); field = ''; i++ }
        else { field += ch; i++ }
      }
    }
    fields.push(field.trim())
    return fields
  }

  if (loading) return (
    <div style={{ minHeight: '100dvh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--ios-bg)' }}>
      <div style={{ color: 'var(--ios-label-2)' }}>Loading…</div>
    </div>
  )

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--ios-bg)', paddingBottom: 'calc(env(safe-area-inset-bottom,0px) + 80px)' }}>
      {/* Nav */}
      <div style={{
        background: 'rgba(255,255,255,0.85)', backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
        borderBottom: '0.5px solid var(--ios-separator)', padding: '12px 20px',
        paddingTop: 'calc(env(safe-area-inset-top, 0px) + 12px)', position: 'sticky', top: 0, zIndex: 40,
        display: 'flex', alignItems: 'center', gap: 12,
      }}>
        <button onClick={() => router.push('/settings')} style={{ background: 'none', border: 'none', color: 'var(--ios-blue)', fontSize: 17, cursor: 'pointer', padding: 0, fontFamily: 'inherit', display: 'flex', alignItems: 'center', gap: 4 }}>
          <svg width="10" height="16" viewBox="0 0 10 16" fill="none">
            <path d="M8 2L2 8L8 14" stroke="var(--ios-blue)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
          Settings
        </button>
        <div style={{ flex: 1, textAlign: 'center', fontWeight: 600, fontSize: 17 }}>{group?.name}</div>
        <div style={{ width: 70 }} />
      </div>

      <div style={{ padding: '20px 16px' }}>

        {/* ── Members ── */}
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 6 }}>
          <div className="section-header" style={{ paddingLeft: 0, marginBottom: 0 }}>Members</div>
          {group?.created_by === currentUser?.id && members.length < 3 && (
            <span style={{ fontSize: 12, color: 'var(--ios-label-3)' }}>Need 3+ members to remove</span>
          )}
        </div>
        <div className="card" style={{ marginBottom: 28 }}>
          {members.map(m => (
            <div key={m.id} className="list-row" style={{ cursor: 'default' }}>
              <div style={{ width: 36, height: 36, borderRadius: 18, background: 'var(--ios-blue)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'white', fontWeight: 600, fontSize: 15, flexShrink: 0 }}>
                {(m.display_name ?? m.email)[0].toUpperCase()}
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 500 }}>{displayName(m)}</div>
                <div style={{ fontSize: 13, color: 'var(--ios-label-2)' }}>{m.email}</div>
              </div>
              {m.id === currentUser?.id ? (
                <div style={{ fontSize: 12, color: 'var(--ios-blue)', background: 'rgba(0,122,255,0.1)', padding: '2px 8px', borderRadius: 10, flexShrink: 0 }}>You</div>
              ) : group?.created_by === currentUser?.id && members.length >= 3 ? (
                <button
                  onClick={() => {
                    setRemoveError('')
                    setReplacementId(members.find(x => x.id !== m.id)?.id ?? '')
                    setMemberToRemove(m)
                  }}
                  style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--ios-red)', padding: '4px 8px', fontSize: 20, lineHeight: 1, display: 'flex', alignItems: 'center', flexShrink: 0 }}
                  title={`Remove ${displayName(m)}`}
                >
                  ⊖
                </button>
              ) : null}
            </div>
          ))}
        </div>

        {/* ── Defaults ── */}
        <div className="section-header" style={{ paddingLeft: 0 }}>Default Settings</div>
        <form onSubmit={handleSaveDefaults}>
          <div className="card" style={{ marginBottom: 8 }}>
            <div className="list-row" style={{ cursor: 'default' }}>
              <label style={{ color: 'var(--ios-label-2)', fontSize: 15, minWidth: 80 }}>Paid by</label>
              <select className="ios-input" value={defaultPaidBy} onChange={e => setDefaultPaidBy(e.target.value)} style={{ cursor: 'pointer' }}>
                <option value="">— None —</option>
                {members.map(m => (
                  <option key={m.id} value={m.id}>{displayName(m)}{m.id === currentUser?.id ? ' (you)' : ''}</option>
                ))}
              </select>
            </div>
            {members.map(m => (
              <div key={m.id} className="list-row" style={{ cursor: 'default' }}>
                <div style={{ flex: 1, fontSize: 15 }}>{displayName(m)}{m.id === currentUser?.id ? ' (you)' : ''}</div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                  <input type="number" inputMode="decimal" min="0" max="100" step="0.01"
                    value={defaultSplits[m.id] ?? '0'}
                    onChange={e => setDefaultSplits(prev => ({ ...prev, [m.id]: e.target.value }))}
                    style={{ width: 70, textAlign: 'right', border: 'none', outline: 'none', fontSize: 17, background: 'transparent', fontFamily: 'inherit', color: 'var(--ios-label)' }}
                  />
                  <span style={{ color: 'var(--ios-label-2)', fontSize: 15 }}>%</span>
                </div>
              </div>
            ))}
          </div>
          <button className="btn-secondary" type="submit" disabled={savingDefaults} style={{ marginBottom: 4 }}>
            {savingDefaults ? 'Saving…' : 'Save Defaults'}
          </button>
          {defaultsMsg && (
            <p style={{ fontSize: 13, color: defaultsMsg.startsWith('Error') ? 'var(--ios-red)' : 'var(--ios-green)', marginBottom: 12 }}>{defaultsMsg}</p>
          )}
        </form>

        {/* ── Invite ── */}
        <div className="section-header" style={{ paddingLeft: 0, marginTop: 20 }}>Invite Members</div>
        <form onSubmit={handleInvite}>
          <div className="card" style={{ marginBottom: 8 }}>
            <div className="list-row" style={{ cursor: 'default' }}>
              <input className="ios-input" type="email" inputMode="email" placeholder="friend@example.com"
                value={inviteEmail} onChange={e => setInviteEmail(e.target.value)} />
            </div>
          </div>
          <button className="btn-primary" type="submit" disabled={inviting || !inviteEmail.trim()} style={{ marginBottom: 8 }}>
            {inviting ? 'Sending…' : 'Send Invite'}
          </button>
        </form>
        {inviteMsg && (
          <p style={{ fontSize: 13, color: inviteMsg.startsWith('Error') ? 'var(--ios-red)' : 'var(--ios-green)', marginBottom: 12 }}>{inviteMsg}</p>
        )}

        {/* ── Pending Invites ── */}
        {invitations.length > 0 && (
          <>
            <div className="section-header" style={{ paddingLeft: 0 }}>Pending Invites</div>
            <div className="card" style={{ marginBottom: 28 }}>
              {invitations.map(inv => (
                <div key={inv.id} className="list-row" style={{ cursor: 'default' }}>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 15 }}>{inv.email}</div>
                    <div style={{ fontSize: 12, color: 'var(--ios-label-3)' }}>Expires {new Date(inv.expires_at).toLocaleDateString()}</div>
                  </div>
                  <button onClick={async () => { await supabase.from('invitations').delete().eq('id', inv.id); await load() }}
                    style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--ios-red)', fontSize: 13, fontWeight: 500, padding: '4px 8px', fontFamily: 'inherit' }}>
                    Revoke
                  </button>
                </div>
              ))}
            </div>
          </>
        )}

        {/* ── Export ── */}
        <div className="section-header" style={{ paddingLeft: 0, marginTop: 8 }}>Export</div>
        <div style={{ display: 'flex', gap: 10, marginBottom: 8 }}>
          <button className="btn-secondary" onClick={handleExport} disabled={exportLoading} style={{ flex: 1 }}>
            {exportLoading ? 'Exporting…' : '↓ Export Expenses'}
          </button>
          <button className="btn-secondary" onClick={handleDownloadTemplate} style={{ flex: 1 }}>
            ↓ Download Template
          </button>
        </div>
        {exportMsg && (
          <p style={{ fontSize: 13, color: exportMsg.startsWith('No') ? 'var(--ios-label-2)' : 'var(--ios-green)', marginBottom: 12 }}>{exportMsg}</p>
        )}

        {/* ── CSV Import ── */}
        <div className="section-header" style={{ paddingLeft: 0, marginTop: 12 }}>Import CSV</div>
        <div className="card" style={{ marginBottom: 8 }}>
          <div style={{ padding: 16 }}>
            {allGroups.length > 1 && (
              <div style={{ marginBottom: 16 }}>
                <label style={{ fontSize: 13, color: 'var(--ios-label-2)', display: 'block', marginBottom: 6 }}>Import into group</label>
                <select
                  className="ios-input"
                  value={csvGroup}
                  onChange={e => setCsvGroup(e.target.value)}
                  style={{ cursor: 'pointer', width: '100%' }}
                >
                  {allGroups.map(g => <option key={g.id} value={g.id}>{g.name}</option>)}
                </select>
              </div>
            )}
            <p style={{ fontSize: 13, color: 'var(--ios-label-2)', marginBottom: 14, lineHeight: 1.5 }}>
              Columns: <strong>Date, Description, Amount, Paid By</strong>, then <strong>Percentage Owed by [Name]</strong> for each member.
            </p>
            {/* Hidden native file input */}
            <input ref={fileRef} type="file" accept=".csv,text/csv" onChange={handleCSV} disabled={csvLoading}
              style={{ display: 'none' }} />
            {/* Styled file picker row */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <button
                type="button"
                onClick={() => fileRef.current?.click()}
                disabled={csvLoading}
                style={{
                  padding: '8px 16px', borderRadius: 8, border: '1px solid var(--ios-separator)',
                  background: 'var(--ios-surface)', color: 'var(--ios-blue)', fontSize: 15,
                  fontWeight: 500, cursor: csvLoading ? 'not-allowed' : 'pointer',
                  fontFamily: 'inherit', flexShrink: 0,
                }}
              >
                Choose File
              </button>
              <span style={{ fontSize: 14, color: csvFileName ? 'var(--ios-label)' : 'var(--ios-label-3)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {csvFileName || 'No file chosen'}
              </span>
            </div>
            {csvLoading && <p style={{ fontSize: 13, color: 'var(--ios-label-2)', marginTop: 10 }}>Importing…</p>}
            {csvMsg && (
              <p style={{ fontSize: 13, color: csvMsg.startsWith('Error') || csvMsg.includes('Missing') ? 'var(--ios-red)' : 'var(--ios-green)', marginTop: 10 }}>{csvMsg}</p>
            )}
          </div>
        </div>

      </div>

      {/* ── Remove Member Modal ── */}
      {memberToRemove && (
        <div style={{
          position: 'fixed', inset: 0, zIndex: 200,
          background: 'rgba(0,0,0,0.4)',
          display: 'flex', alignItems: 'flex-end', justifyContent: 'center',
        }}
          onClick={e => { if (e.target === e.currentTarget && !removingMember) setMemberToRemove(null) }}
        >
          <div style={{
            background: 'var(--ios-surface)', borderRadius: '16px 16px 0 0',
            width: '100%', maxWidth: 480, padding: '24px 20px',
            paddingBottom: 'calc(env(safe-area-inset-bottom,0px) + 24px)',
          }}>
            <div style={{ fontWeight: 700, fontSize: 18, marginBottom: 6 }}>
              Remove {displayName(memberToRemove)}
            </div>
            <p style={{ fontSize: 14, color: 'var(--ios-label-2)', marginBottom: 20, lineHeight: 1.5 }}>
              All of their paid transactions and split shares will be transferred to the selected member.
            </p>

            <label style={{ fontSize: 13, color: 'var(--ios-label-2)', display: 'block', marginBottom: 6 }}>
              Transfer to
            </label>
            <select
              className="ios-input"
              value={replacementId}
              onChange={e => setReplacementId(e.target.value)}
              disabled={removingMember}
              style={{ width: '100%', marginBottom: 20, cursor: 'pointer' }}
            >
              {members
                .filter(m => m.id !== memberToRemove.id)
                .map(m => (
                  <option key={m.id} value={m.id}>
                    {displayName(m)}{m.id === currentUser?.id ? ' (you)' : ''}
                  </option>
                ))}
            </select>

            {removeError && (
              <p style={{ fontSize: 13, color: 'var(--ios-red)', marginBottom: 12 }}>{removeError}</p>
            )}

            <div style={{ display: 'flex', gap: 12 }}>
              <button
                className="btn-secondary"
                onClick={() => { setMemberToRemove(null); setRemoveError('') }}
                disabled={removingMember}
                style={{ flex: 1 }}
              >
                Cancel
              </button>
              <button
                onClick={handleRemoveMember}
                disabled={removingMember || !replacementId}
                style={{
                  flex: 1, padding: '12px 0', borderRadius: 12, border: 'none',
                  background: removingMember ? 'var(--ios-label-3)' : 'var(--ios-red)',
                  color: 'white', fontWeight: 600, fontSize: 16,
                  cursor: removingMember ? 'not-allowed' : 'pointer', fontFamily: 'inherit',
                }}
              >
                {removingMember ? 'Removing…' : 'Remove'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
