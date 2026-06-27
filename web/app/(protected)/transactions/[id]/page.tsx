'use client'

import { useEffect, useState } from 'react'
import { useRouter, useParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Profile, Transaction, TransactionSplit } from '@/lib/types'
import { displayName, formatCurrency } from '@/lib/utils'

export default function EditTransactionPage() {
  const router = useRouter()
  const { id } = useParams<{ id: string }>()
  const supabase = createClient()

  const [currentUser, setCurrentUser] = useState<Profile | null>(null)
  const [members, setMembers] = useState<Profile[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [showDelete, setShowDelete] = useState(false)

  const [description, setDescription] = useState('')
  const [amount, setAmount] = useState('')
  const [date, setDate] = useState('')
  const [paidBy, setPaidBy] = useState('')
  const [type, setType] = useState<'expense' | 'payment'>('expense')
  const [splits, setSplits] = useState<Record<string, string>>({})
  const [error, setError] = useState('')

  useEffect(() => {
    async function load() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data: profile } = await supabase.from('profiles').select('*').eq('id', user.id).single()
      if (profile) setCurrentUser(profile)

      const { data: tx } = await supabase
        .from('transactions')
        .select('*, splits:transaction_splits(*)')
        .eq('id', id)
        .single()

      if (!tx) { router.back(); return }

      setDescription(tx.description)
      setAmount(String(tx.amount))
      setDate(tx.date)
      setPaidBy(tx.paid_by ?? '')
      setType(tx.type)

      const { data: memberRows } = await supabase
        .from('group_members')
        .select('*, profile:profiles(*)')
        .eq('group_id', tx.group_id)

      const profiles: Profile[] = (memberRows ?? []).map((m: { profile: Profile }) => m.profile)
      setMembers(profiles)

      const splitMap: Record<string, string> = {}
      profiles.forEach((p) => { splitMap[p.id] = '0' })
      ;(tx.splits ?? []).forEach((s: TransactionSplit) => {
        splitMap[s.user_id] = String(s.percentage)
      })
      setSplits(splitMap)

      setLoading(false)
    }
    load()
  }, [id, supabase, router])

  function totalSplitPct() {
    return Object.values(splits).reduce((sum, v) => sum + (parseFloat(v) || 0), 0)
  }

  async function handleSave() {
    setError('')
    if (!description.trim()) { setError('Description is required'); return }
    const amt = parseFloat(amount)
    if (!amt || amt <= 0) { setError('Enter a valid amount'); return }
    if (type === 'expense') {
      const total = totalSplitPct()
      if (Math.abs(total - 100) > 0.1) { setError(`Splits must add up to 100% (currently ${total.toFixed(1)}%)`); return }
    }

    setSaving(true)
    const { error: txErr } = await supabase
      .from('transactions')
      .update({ description: description.trim(), amount: amt, paid_by: paidBy, type, date })
      .eq('id', id)

    if (txErr) { setError(txErr.message); setSaving(false); return }

    // Replace splits
    await supabase.from('transaction_splits').delete().eq('transaction_id', id)

    if (type === 'expense') {
      const splitRows = members.map((m) => ({
        transaction_id: id,
        user_id: m.id,
        percentage: parseFloat(splits[m.id] ?? '0') || 0,
        amount: parseFloat(((parseFloat(splits[m.id] ?? '0') / 100) * amt).toFixed(2)),
      }))
      await supabase.from('transaction_splits').insert(splitRows)
    } else {
      const others = members.filter((m) => m.id !== paidBy)
      const payee = others[0]
      if (payee) {
        await supabase.from('transaction_splits').insert([
          { transaction_id: id, user_id: paidBy, percentage: 0, amount: 0 },
          { transaction_id: id, user_id: payee.id, percentage: 100, amount: amt },
        ])
      }
    }

    router.push('/dashboard')
  }

  async function handleDelete() {
    setDeleting(true)
    await supabase.from('transactions').delete().eq('id', id)
    router.push('/dashboard')
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
      {/* Nav */}
      <div style={{
        background: 'rgba(255,255,255,0.85)',
        backdropFilter: 'blur(20px)',
        WebkitBackdropFilter: 'blur(20px)',
        borderBottom: '0.5px solid var(--ios-separator)',
        padding: '12px 20px',
        paddingTop: 'calc(env(safe-area-inset-top, 0px) + 12px)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        position: 'sticky',
        top: 0,
        zIndex: 40,
      }}>
        <button onClick={() => router.back()} style={{ color: 'var(--ios-blue)', background: 'none', border: 'none', fontSize: 17, cursor: 'pointer' }}>
          ‹ Back
        </button>
        <span style={{ fontWeight: 600, fontSize: 17 }}>Edit Transaction</span>
        <button
          onClick={handleSave}
          disabled={saving}
          style={{ color: saving ? 'var(--ios-label-3)' : 'var(--ios-blue)', background: 'none', border: 'none', fontSize: 17, fontWeight: 600, cursor: saving ? 'not-allowed' : 'pointer' }}
        >
          {saving ? 'Saving…' : 'Save'}
        </button>
      </div>

      <div style={{ padding: '20px 16px', paddingBottom: 'calc(env(safe-area-inset-bottom, 0px) + 20px)' }}>
        {/* Type toggle */}
        <div style={{ display: 'flex', background: 'var(--ios-fill)', borderRadius: 8, padding: 2, marginBottom: 24 }}>
          {(['expense', 'payment'] as const).map((t) => (
            <button
              key={t}
              onClick={() => setType(t)}
              style={{
                flex: 1,
                padding: '7px 0',
                borderRadius: 6,
                border: 'none',
                background: type === t ? 'white' : 'transparent',
                color: type === t ? 'var(--ios-label)' : 'var(--ios-label-2)',
                fontWeight: type === t ? 600 : 400,
                fontSize: 15,
                cursor: 'pointer',
                boxShadow: type === t ? '0 1px 3px rgba(0,0,0,0.12)' : 'none',
                fontFamily: 'inherit',
                textTransform: 'capitalize',
              }}
            >
              {t === 'expense' ? '💳 Expense' : '↑ Payment'}
            </button>
          ))}
        </div>

        <div className="section-header" style={{ paddingLeft: 0 }}>Details</div>
        <div className="card" style={{ marginBottom: 24 }}>
          <div className="list-row" style={{ cursor: 'default' }}>
            <label style={{ color: 'var(--ios-label-2)', fontSize: 15, minWidth: 90 }}>Description</label>
            <input className="ios-input" value={description} onChange={(e) => setDescription(e.target.value)} />
          </div>
          <div className="list-row" style={{ cursor: 'default' }}>
            <label style={{ color: 'var(--ios-label-2)', fontSize: 15, minWidth: 90 }}>Amount</label>
            <span style={{ color: 'var(--ios-label-2)', marginRight: 4 }}>$</span>
            <input className="ios-input" type="number" inputMode="decimal" min="0" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </div>
          <div className="list-row" style={{ cursor: 'default' }}>
            <label style={{ color: 'var(--ios-label-2)', fontSize: 15, minWidth: 90 }}>Date</label>
            <input className="ios-input" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </div>
          <div className="list-row" style={{ cursor: 'default' }}>
            <label style={{ color: 'var(--ios-label-2)', fontSize: 15, minWidth: 90 }}>Paid by</label>
            <select className="ios-input" value={paidBy} onChange={(e) => setPaidBy(e.target.value)} style={{ cursor: 'pointer' }}>
              {members.map((m) => (
                <option key={m.id} value={m.id}>
                  {displayName(m)}{m.id === currentUser?.id ? ' (you)' : ''}
                </option>
              ))}
            </select>
          </div>
        </div>

        {type === 'expense' && (
          <>
            <div className="section-header" style={{ paddingLeft: 0 }}>
              Split — {totalSplitPct().toFixed(1)}% of 100%
            </div>
            <div className="card" style={{ marginBottom: 24 }}>
              {members.map((m) => (
                <div key={m.id} className="list-row" style={{ cursor: 'default' }}>
                  <div style={{ flex: 1, fontSize: 15 }}>
                    {displayName(m)}{m.id === currentUser?.id ? ' (you)' : ''}
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                    <input
                      type="number" inputMode="decimal" min="0" max="100" step="0.01"
                      value={splits[m.id] ?? '0'}
                      onChange={(e) => setSplits((prev) => ({ ...prev, [m.id]: e.target.value }))}
                      style={{ width: 70, textAlign: 'right', border: 'none', outline: 'none', fontSize: 17, background: 'transparent', fontFamily: 'inherit', color: 'var(--ios-label)' }}
                    />
                    <span style={{ color: 'var(--ios-label-2)', fontSize: 15 }}>%</span>
                  </div>
                </div>
              ))}
            </div>
          </>
        )}

        {/* Per-user dollar amounts */}
        {type === 'expense' && parseFloat(amount) > 0 && (
          <>
            <div className="section-header" style={{ paddingLeft: 0 }}>Amount per Person</div>
            <div className="card" style={{ marginBottom: 24 }}>
              {members.map((m) => {
                const pct = parseFloat(splits[m.id] ?? '0') || 0
                const share = (pct / 100) * (parseFloat(amount) || 0)
                return (
                  <div key={m.id} className="list-row" style={{ cursor: 'default' }}>
                    <div style={{ flex: 1, fontSize: 15, color: 'var(--ios-label-2)' }}>
                      {displayName(m)}{m.id === currentUser?.id ? ' (you)' : ''}
                    </div>
                    <span style={{ fontWeight: 600, fontSize: 17 }}>{formatCurrency(share)}</span>
                  </div>
                )
              })}
            </div>
          </>
        )}

        {error && <p style={{ color: 'var(--ios-red)', fontSize: 13, marginBottom: 16 }}>{error}</p>}

        <button className="btn-primary" onClick={handleSave} disabled={saving} style={{ marginBottom: 12 }}>
          {saving ? 'Saving…' : 'Save Changes'}
        </button>

        {!showDelete ? (
          <button className="btn-secondary" onClick={() => setShowDelete(true)} style={{ color: 'var(--ios-red)' }}>
            Delete Transaction
          </button>
        ) : (
          <div className="card" style={{ padding: 16 }}>
            <p style={{ textAlign: 'center', marginBottom: 12, color: 'var(--ios-label-2)', fontSize: 15 }}>
              Delete this transaction permanently?
            </p>
            <div style={{ display: 'flex', gap: 12 }}>
              <button className="btn-secondary" onClick={() => setShowDelete(false)} style={{ flex: 1 }}>Cancel</button>
              <button className="btn-destructive" onClick={handleDelete} disabled={deleting} style={{ flex: 1 }}>
                {deleting ? 'Deleting…' : 'Delete'}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
