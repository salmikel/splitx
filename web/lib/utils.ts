import { Transaction, TransactionSplit, Balance, Profile } from './types'

export function formatCurrency(amount: number): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
  }).format(amount)
}

export function formatDate(dateStr: string): string {
  return new Date(dateStr + 'T00:00:00').toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })
}

export function computeBalances(
  transactions: Transaction[],
  members: Profile[]
): Balance[] {
  // net[userId] = amount they are owed (positive) or owe (negative)
  const net: Record<string, Record<string, number>> = {}

  members.forEach((m) => {
    net[m.id] = {}
    members.forEach((m2) => {
      if (m.id !== m2.id) net[m.id][m2.id] = 0
    })
  })

  for (const tx of transactions) {
    if (!tx.splits || !tx.paid_by) continue

    for (const split of tx.splits) {
      if (split.user_id === tx.paid_by) continue
      // split.user_id owes tx.paid_by split.amount
      if (net[split.user_id] && net[split.user_id][tx.paid_by] !== undefined) {
        net[split.user_id][tx.paid_by] += split.amount
      }
      if (net[tx.paid_by] && net[tx.paid_by][split.user_id] !== undefined) {
        net[tx.paid_by][split.user_id] -= split.amount
      }
    }
  }

  const balances: Balance[] = []
  const profileMap = new Map(members.map((m) => [m.id, m]))

  const seen = new Set<string>()
  members.forEach((a) => {
    members.forEach((b) => {
      if (a.id === b.id) return
      const key = [a.id, b.id].sort().join(':')
      if (seen.has(key)) return
      seen.add(key)

      const aOwesB = net[a.id]?.[b.id] ?? 0
      const bOwesA = net[b.id]?.[a.id] ?? 0
      const netAmount = aOwesB - bOwesA

      if (Math.abs(netAmount) < 0.01) return

      const fromProfile = netAmount > 0 ? profileMap.get(a.id) : profileMap.get(b.id)
      const toProfile = netAmount > 0 ? profileMap.get(b.id) : profileMap.get(a.id)
      if (!fromProfile || !toProfile) return

      balances.push({
        fromUserId: fromProfile.id,
        toUserId: toProfile.id,
        fromProfile,
        toProfile,
        amount: Math.abs(netAmount),
      })
    })
  })

  return balances
}

export function displayName(profile: Profile | undefined | null): string {
  if (!profile) return 'Unknown'
  return profile.display_name || profile.email.split('@')[0]
}
