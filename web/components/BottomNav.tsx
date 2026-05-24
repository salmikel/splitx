'use client'

import Link from 'next/link'

interface Props {
  active: 'dashboard' | 'settings'
  groupId: string | null
}

export default function BottomNav({ active, groupId }: Props) {
  return (
    <nav className="bottom-nav">
      <Link
        href="/dashboard"
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '8px 0',
          gap: 2,
          textDecoration: 'none',
          color: active === 'dashboard' ? 'var(--ios-blue)' : 'var(--ios-label-3)',
        }}
      >
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
          <path d="M3 12L12 3L21 12V20C21 20.5523 20.5523 21 20 21H15V16H9V21H4C3.44772 21 3 20.5523 3 20V12Z"
            fill={active === 'dashboard' ? 'var(--ios-blue)' : 'none'}
            stroke={active === 'dashboard' ? 'var(--ios-blue)' : 'var(--ios-label-3)'}
            strokeWidth="1.5" strokeLinejoin="round"
          />
        </svg>
        <span style={{ fontSize: 10, fontWeight: active === 'dashboard' ? 600 : 400 }}>Home</span>
      </Link>

      <Link
        href="/settings"
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '8px 0',
          gap: 2,
          textDecoration: 'none',
          color: active === 'settings' ? 'var(--ios-blue)' : 'var(--ios-label-3)',
        }}
      >
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
          <circle cx="12" cy="12" r="3"
            fill={active === 'settings' ? 'var(--ios-blue)' : 'none'}
            stroke={active === 'settings' ? 'var(--ios-blue)' : 'var(--ios-label-3)'}
            strokeWidth="1.5"
          />
          <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"
            stroke={active === 'settings' ? 'var(--ios-blue)' : 'var(--ios-label-3)'}
            strokeWidth="1.5"
          />
        </svg>
        <span style={{ fontSize: 10, fontWeight: active === 'settings' ? 600 : 400 }}>Settings</span>
      </Link>
    </nav>
  )
}
