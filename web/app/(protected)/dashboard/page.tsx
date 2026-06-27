'use client'

import { useEffect, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Transaction, Profile, GroupMember, Group, Balance } from '@/lib/types'
import { formatCurrency, formatDate, computeBalances, displayName } from '@/lib/utils'
import BottomNav from '@/components/BottomNav'

type TransactionSplitWithProfile = {
  id: string; transaction_id: string; user_id: string
  percentage: number; amount: number; profile: Profile
}

const STORAGE_KEY = 'splitx_active_group'

export default function DashboardPage() {
  const router = useRouter()
  const supabase = createClient()

  const [currentUser, setCurrentUser] = useState<Profile | null>(null)
  const [groups, setGroups] = useState<Group[]>([])
  const [group, setGroup] = useState<Group | null>(null)
  const [members, setMembers] = useState<Profile[]>([])
  const [transactions, setTransactions] = useState<Transaction[]>([])
  const [balances, setBalances] = useState<Balance[]>([])
  const [loading, setLoading] = useState(true)
  const [showGroupPicker, setShowGroupPicker] = useState(false)

  const loadGroup = useCallback(async (grp: Group, userId: string) => {
    const { data: memberRows } = await supabase
      .from('group_members').select('*, profile:profiles(*)').eq('group_id', grp.id)
    const memberProfiles = (memberRows ?? [])
      .map((m: GroupMember & { profile: Profile }) => m.profile).filter(Boolean)
    setMembers(memberProfiles)

    const { data: txRows } = await supabase
      .from('transactions')
      .select('*, splits:transaction_splits(*, profile:profiles(*))')
      .eq('group_id', grp.id)
      .order('date', { ascending: false })
      .order('created_at', { ascending: false })

    const txs = (txRows ?? []).map((t: Transaction & { splits: TransactionSplitWithProfile[] }) => ({
      ...t, splits: t.splits?.map((s) => ({ ...s, profile: s.profile })),
    }))
    setTransactions(txs)
    setBalances(computeBalances(txs, memberProfiles))
    void userId
  }, [supabase])

  const load = useCallback(async () => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    const { data: profile } = await supabase.from('profiles').select('*').eq('id', user.id).single()
    if (profile) setCurrentUser(profile)

    const { data: gmRows } = await supabase
      .from('group_members').select('group_id').eq('user_id', user.id).order('joined_at')

    if (!gmRows || gmRows.length === 0) { setLoading(false); return }

    const groupIds = gmRows.map((g: { group_id: string }) => g.group_id)
    const { data: grpRows } = await supabase.from('groups').select('*').in('id', groupIds)
    const allGroups: Group[] = grpRows ?? []
    setGroups(allGroups)

    const stored = localStorage.getItem(STORAGE_KEY)
    const active = allGroups.find(g => g.id === stored) ?? allGroups[0]
    setGroup(active)
    localStorage.setItem(STORAGE_KEY, active.id)

    await loadGroup(active, user.id)
    setLoading(false)
  }, [supabase, loadGroup])

  useEffect(() => { load() }, [load])

  function switchGroup(g: Group) {
    setGroup(g)
    localStorage.setItem(STORAGE_KEY, g.id)
    setShowGroupPicker(false)
    setLoading(true)
    supabase.auth.getUser().then(({ data: { user } }) => {
      if (user) loadGroup(g, user.id).then(() => setLoading(false))
    })
  }

  if (loading) return (
    <div style={{ minHeight: '100dvh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--ios-bg)' }}>
      <div style={{ color: 'var(--ios-label-2)', fontSize: 15 }}>Loading…</div>
    </div>
  )

  if (!group) return (
    <div style={{ minHeight: '100dvh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 24, background: 'var(--ios-bg)', gap: 16 }}>
      <div style={{ fontSize: 56 }}>💸</div>
      <h2 style={{ fontSize: 22, fontWeight: 700, textAlign: 'center' }}>Welcome to SplitX</h2>
      <p style={{ color: 'var(--ios-label-2)', textAlign: 'center', fontSize: 15 }}>Create a group to start splitting expenses.</p>
      <button className="btn-primary" style={{ maxWidth: 300 }} onClick={() => router.push('/settings?create=1')}>Create a Group</button>
      <BottomNav active="dashboard" groupId={null} />
    </div>
  )

  async function handleSignOut() {
    await supabase.auth.signOut()
    router.push('/auth/login')
  }

  return (
    // Full-height column: header + fixed-content + scrollable-transactions
    <div style={{ height: '100dvh', display: 'flex', flexDirection: 'column', background: 'var(--ios-bg)', overflow: 'hidden' }}>

      {/* ── Header ───────────────────────────────────────────────── */}
      <div style={{
        background: 'rgba(255,255,255,0.85)', backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
        borderBottom: showGroupPicker ? 'none' : '0.5px solid var(--ios-separator)',
        paddingTop: 'calc(env(safe-area-inset-top, 0px) + 12px)',
        flexShrink: 0, position: 'relative', zIndex: 40,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', padding: '0 16px 12px' }}>
          <div style={{ width: 30, flexShrink: 0 }} />
          <div style={{ flex: 1, textAlign: 'center' }}>
            {groups.length > 1 ? (
              <button onClick={() => setShowGroupPicker(v => !v)}
                style={{ background: 'none', border: 'none', cursor: 'pointer', fontFamily: 'inherit', padding: 0, display: 'inline-flex', alignItems: 'center', gap: 5 }}>
                <span style={{ fontSize: 20, fontWeight: 700, color: 'var(--ios-label)' }}>{group.name}</span>
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none"
                  style={{ transform: showGroupPicker ? 'rotate(180deg)' : 'none', transition: 'transform 0.2s' }}>
                  <path d="M3 5L7 9L11 5" stroke="var(--ios-blue)" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
              </button>
            ) : (
              <span style={{ fontSize: 20, fontWeight: 700 }}>{group.name}</span>
            )}
            <div style={{ fontSize: 12, color: 'var(--ios-label-2)', marginTop: 1 }}>{members.length} members</div>
          </div>
          <button onClick={handleSignOut} title="Sign out"
            style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 4, color: 'var(--ios-label-3)', flexShrink: 0 }}>
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
              <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
              <polyline points="16 17 21 12 16 7" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
              <line x1="21" y1="12" x2="9" y2="12" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
            </svg>
          </button>
        </div>
        {showGroupPicker && (
          <div style={{ borderTop: '0.5px solid var(--ios-separator)', background: 'rgba(255,255,255,0.97)', boxShadow: '0 4px 16px rgba(0,0,0,0.10)', position: 'absolute', left: 0, right: 0, zIndex: 41 }}>
            {groups.map((g, i) => (
              <button key={g.id} onClick={() => switchGroup(g)}
                style={{
                  display: 'flex', alignItems: 'center', width: '100%', padding: '14px 20px',
                  background: g.id === group.id ? 'rgba(0,122,255,0.06)' : 'none',
                  border: 'none', borderBottom: i < groups.length - 1 ? '0.5px solid var(--ios-separator)' : 'none',
                  cursor: 'pointer', fontFamily: 'inherit',
                }}>
                <span style={{ flex: 1, textAlign: 'left', fontSize: 16, fontWeight: g.id === group.id ? 600 : 400, color: g.id === group.id ? 'var(--ios-blue)' : 'var(--ios-label)' }}>
                  {g.name}
                </span>
                {g.id === group.id && (
                  <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
                    <path d="M3.5 9L7.5 13L14.5 5" stroke="var(--ios-blue)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
                  </svg>
                )}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Tap-away backdrop for group picker */}
      {showGroupPicker && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 39 }} onClick={() => setShowGroupPicker(false)} />
      )}

      {/* ── Fixed: balances + action buttons ─────────────────────── */}
      <div style={{ flexShrink: 0, padding: '16px 16px 0' }}>
        {balances.length > 0 && (
          <section style={{ marginBottom: 16 }}>
            <div className="section-header" style={{ paddingLeft: 0 }}>Balances</div>
            <div className="card">
              {balances.map((b, i) => {
                const iOwe = b.fromUserId === currentUser?.id
                const theyOwe = b.toUserId === currentUser?.id
                return (
                  <div key={i} className="list-row" style={{ cursor: 'default' }}>
                    <div style={{ flex: 1 }}>
                      {iOwe ? <span>You owe <strong>{displayName(b.toProfile)}</strong></span>
                        : theyOwe ? <span><strong>{displayName(b.fromProfile)}</strong> owes you</span>
                        : <span><strong>{displayName(b.fromProfile)}</strong> owes <strong>{displayName(b.toProfile)}</strong></span>}
                    </div>
                    <span style={{ fontWeight: 600, color: iOwe ? 'var(--ios-red)' : theyOwe ? 'var(--ios-green)' : 'var(--ios-label)' }}>
                      {formatCurrency(b.amount)}
                    </span>
                  </div>
                )
              })}
            </div>
          </section>
        )}
        {balances.length === 0 && transactions.length > 0 && (
          <div className="card" style={{ padding: 16, marginBottom: 16, textAlign: 'center', color: 'var(--ios-green)', fontWeight: 600 }}>✓ All settled up!</div>
        )}
        <div style={{ display: 'flex', gap: 12, paddingBottom: 16 }}>
          <button className="btn-primary" onClick={() => router.push(`/transactions/new?group=${group.id}&type=expense`)}>+ Expense</button>
          <button className="btn-secondary" onClick={() => router.push(`/transactions/new?group=${group.id}&type=payment`)}>↑ Payment</button>
        </div>
        <div style={{ height: '0.5px', background: 'var(--ios-separator)', margin: '0 -16px' }} />
      </div>

      {/* ── Scrollable: transactions list ────────────────────────── */}
      <div style={{ flex: 1, overflowY: 'auto', padding: '16px 16px', paddingBottom: 'calc(env(safe-area-inset-bottom, 0px) + 80px)' }}>
        {transactions.length > 0 ? (
          <section>
            <div className="section-header" style={{ paddingLeft: 0 }}>Transactions</div>
            <div className="card">
              {transactions.map((tx) => (
                <div key={tx.id} className="list-row" onClick={() => router.push(`/transactions/${tx.id}`)}>
                  <div style={{ width: 40, height: 40, borderRadius: 10, background: tx.type === 'payment' ? 'rgba(52,199,89,0.12)' : 'rgba(0,122,255,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, flexShrink: 0 }}>
                    {tx.type === 'payment' ? '↑' : '💳'}
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontWeight: 500, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{tx.description}</div>
                    <div style={{ fontSize: 13, color: 'var(--ios-label-2)', marginTop: 2 }}>
                      {formatDate(tx.date)} · {displayName(members.find(m => m.id === tx.paid_by))} paid
                    </div>
                  </div>
                  <div style={{ textAlign: 'right', flexShrink: 0 }}>
                    <div style={{ fontWeight: 600, color: tx.type === 'payment' ? 'var(--ios-green)' : 'var(--ios-label)' }}>{formatCurrency(tx.amount)}</div>
                    <div style={{ fontSize: 11, color: 'var(--ios-label-3)', marginTop: 2 }}>›</div>
                  </div>
                </div>
              ))}
            </div>
          </section>
        ) : (
          <div style={{ textAlign: 'center', padding: '32px 0', color: 'var(--ios-label-2)' }}>
            <div style={{ fontSize: 40, marginBottom: 8 }}>📋</div>
            <div>No transactions yet</div>
          </div>
        )}
      </div>

      <BottomNav active="dashboard" groupId={group.id} />
    </div>
  )
}
