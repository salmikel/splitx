'use client'

import { useEffect, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Transaction, Profile, GroupMember, Group, Balance } from '@/lib/types'
import { formatCurrency, formatDate, computeBalances, displayName } from '@/lib/utils'
import BottomNav from '@/components/BottomNav'

export default function DashboardPage() {
  const router = useRouter()
  const supabase = createClient()

  const [currentUser, setCurrentUser] = useState<Profile | null>(null)
  const [group, setGroup] = useState<Group | null>(null)
  const [members, setMembers] = useState<Profile[]>([])
  const [transactions, setTransactions] = useState<Transaction[]>([])
  const [balances, setBalances] = useState<Balance[]>([])
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return

    const { data: profile } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .single()
    if (profile) setCurrentUser(profile)

    // Get first group the user belongs to
    const { data: gm } = await supabase
      .from('group_members')
      .select('group_id')
      .eq('user_id', user.id)
      .order('joined_at')
      .limit(1)
      .single()

    if (!gm) { setLoading(false); return }

    const { data: grp } = await supabase
      .from('groups')
      .select('*')
      .eq('id', gm.group_id)
      .single()
    if (grp) setGroup(grp)

    const { data: memberRows } = await supabase
      .from('group_members')
      .select('*, profile:profiles(*)')
      .eq('group_id', gm.group_id)

    const memberProfiles = (memberRows ?? []).map((m: GroupMember & { profile: Profile }) => m.profile)
    setMembers(memberProfiles)

    const { data: txRows } = await supabase
      .from('transactions')
      .select('*, splits:transaction_splits(*, profile:profiles(*))')
      .eq('group_id', gm.group_id)
      .order('date', { ascending: false })
      .order('created_at', { ascending: false })

    const txs = (txRows ?? []).map((t: Transaction & { splits: (TransactionSplitWithProfile)[] }) => ({
      ...t,
      splits: t.splits?.map((s) => ({ ...s, profile: (s as TransactionSplitWithProfile).profile })),
    }))
    setTransactions(txs)
    setBalances(computeBalances(txs, memberProfiles))
    setLoading(false)
  }, [supabase])

  useEffect(() => { load() }, [load])

  if (loading) {
    return (
      <div style={{ minHeight: '100dvh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--ios-bg)' }}>
        <div style={{ color: 'var(--ios-label-2)', fontSize: 15 }}>Loading…</div>
      </div>
    )
  }

  if (!group) {
    return (
      <div style={{ minHeight: '100dvh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 24, background: 'var(--ios-bg)', gap: 16 }}>
        <div style={{ fontSize: 56 }}>💸</div>
        <h2 style={{ fontSize: 22, fontWeight: 700, textAlign: 'center' }}>Welcome to SplitX</h2>
        <p style={{ color: 'var(--ios-label-2)', textAlign: 'center', fontSize: 15 }}>
          Create a group to start splitting expenses.
        </p>
        <button className="btn-primary" style={{ maxWidth: 300 }} onClick={() => router.push('/settings?create=1')}>
          Create a Group
        </button>
        <BottomNav active="dashboard" groupId={null} />
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
        padding: '12px 20px 12px',
        paddingTop: 'calc(env(safe-area-inset-top, 0px) + 12px)',
        position: 'sticky',
        top: 0,
        zIndex: 40,
      }}>
        <div style={{ fontSize: 28, fontWeight: 700 }}>{group.name}</div>
        <div style={{ fontSize: 13, color: 'var(--ios-label-2)', marginTop: 2 }}>
          {members.length} members
        </div>
      </div>

      <div className="safe-bottom" style={{ padding: '20px 16px' }}>
        {/* Balance summary */}
        {balances.length > 0 && (
          <section style={{ marginBottom: 28 }}>
            <div className="section-header" style={{ paddingLeft: 0 }}>Balances</div>
            <div className="card">
              {balances.map((b, i) => {
                const iOwe = b.fromUserId === currentUser?.id
                const theyOwe = b.toUserId === currentUser?.id
                return (
                  <div key={i} className="list-row" style={{ cursor: 'default' }}>
                    <div style={{ flex: 1 }}>
                      {iOwe ? (
                        <span>You owe <strong>{displayName(b.toProfile)}</strong></span>
                      ) : theyOwe ? (
                        <span><strong>{displayName(b.fromProfile)}</strong> owes you</span>
                      ) : (
                        <span><strong>{displayName(b.fromProfile)}</strong> owes <strong>{displayName(b.toProfile)}</strong></span>
                      )}
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
          <div className="card" style={{ padding: 16, marginBottom: 28, textAlign: 'center', color: 'var(--ios-green)', fontWeight: 600 }}>
            ✓ All settled up!
          </div>
        )}

        {/* Add buttons */}
        <div style={{ display: 'flex', gap: 12, marginBottom: 28 }}>
          <button
            className="btn-primary"
            onClick={() => router.push(`/transactions/new?group=${group.id}&type=expense`)}
          >
            + Expense
          </button>
          <button
            className="btn-secondary"
            onClick={() => router.push(`/transactions/new?group=${group.id}&type=payment`)}
          >
            ↑ Payment
          </button>
        </div>

        {/* Transactions */}
        {transactions.length > 0 ? (
          <section>
            <div className="section-header" style={{ paddingLeft: 0 }}>Transactions</div>
            <div className="card">
              {transactions.map((tx) => (
                <div key={tx.id} className="list-row" onClick={() => router.push(`/transactions/${tx.id}`)}>
                  <div style={{
                    width: 40,
                    height: 40,
                    borderRadius: 10,
                    background: tx.type === 'payment' ? 'rgba(52,199,89,0.12)' : 'rgba(0,122,255,0.12)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontSize: 20,
                    flexShrink: 0,
                  }}>
                    {tx.type === 'payment' ? '↑' : '💳'}
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontWeight: 500, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {tx.description}
                    </div>
                    <div style={{ fontSize: 13, color: 'var(--ios-label-2)', marginTop: 2 }}>
                      {formatDate(tx.date)} · {displayName(members.find(m => m.id === tx.paid_by))} paid
                    </div>
                  </div>
                  <div style={{ textAlign: 'right', flexShrink: 0 }}>
                    <div style={{ fontWeight: 600 }}>{formatCurrency(tx.amount)}</div>
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

type TransactionSplitWithProfile = {
  id: string
  transaction_id: string
  user_id: string
  percentage: number
  amount: number
  profile: Profile
}
