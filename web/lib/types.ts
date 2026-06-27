export interface Profile {
  id: string
  email: string
  display_name: string | null
  created_at: string
}

export interface Group {
  id: string
  name: string
  created_by: string | null
  created_at: string
  default_paid_by: string | null
  default_splits: Record<string, number>
}

export interface GroupMember {
  id: string
  group_id: string
  user_id: string
  joined_at: string
  profile?: Profile
}

export interface Invitation {
  id: string
  group_id: string
  invited_by: string | null
  email: string
  token: string
  status: 'pending' | 'accepted' | 'expired'
  created_at: string
  expires_at: string
}

export interface Transaction {
  id: string
  group_id: string
  description: string
  amount: number
  paid_by: string | null
  type: 'expense' | 'payment'
  date: string
  created_at: string
  updated_at: string
  splits?: TransactionSplit[]
  paid_by_profile?: Profile
}

export interface TransactionSplit {
  id: string
  transaction_id: string
  user_id: string
  percentage: number
  amount: number
  profile?: Profile
}

export interface Balance {
  fromUserId: string
  toUserId: string
  fromProfile: Profile
  toProfile: Profile
  amount: number
}
