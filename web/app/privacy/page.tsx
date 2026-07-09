import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Privacy Policy — SplitX',
  description: 'How SplitX collects, uses, and protects your data.',
}

const LAST_UPDATED = 'July 7, 2026'
const CONTACT_EMAIL = 'salvador.mikel@gmail.com'

export default function PrivacyPage() {
  return (
    <main style={styles.page}>
      <div style={styles.container}>
        <h1 style={styles.h1}>Privacy Policy</h1>
        <p style={styles.meta}>Last updated: {LAST_UPDATED}</p>

        <p style={styles.p}>
          SplitX (&ldquo;we&rdquo;, &ldquo;us&rdquo;, or the &ldquo;app&rdquo;) helps you track and split
          shared expenses. This policy explains what we collect, how we use it, and the choices you have.
        </p>

        <h2 style={styles.h2}>Information we collect</h2>
        <ul style={styles.ul}>
          <li><strong>Account information:</strong> your email address and, optionally, your display name.</li>
          <li><strong>Content you create:</strong> groups, expenses, payments, and split details you enter.</li>
          <li>
            <strong>Sign in with Apple:</strong> if you use Apple to sign in, we receive the name and email
            you choose to share (which may be a private relay email).
          </li>
        </ul>

        <h2 style={styles.h2}>How we use your information</h2>
        <ul style={styles.ul}>
          <li>To provide the core service: authentication, storing your groups and transactions, and syncing across your devices.</li>
          <li>To send transactional emails, such as group invitations you initiate.</li>
          <li>To send you local notifications about activity in your groups (only if you grant permission).</li>
        </ul>
        <p style={styles.p}>
          We do not sell your personal information, and we do not use it to track you across other companies&rsquo;
          apps or websites.
        </p>

        <h2 style={styles.h2}>Advertising</h2>
        <p style={styles.p}>
          The free version of SplitX displays ads provided by Google AdMob. AdMob may collect certain device
          information to deliver and measure ads. We request non-personalized (non-tracking) ads by default.
          You can remove all ads by subscribing to SplitX Premium. Learn more about how Google uses data at{' '}
          <a style={styles.a} href="https://policies.google.com/technologies/partner-sites">
            policies.google.com/technologies/partner-sites
          </a>.
        </p>

        <h2 style={styles.h2}>Service providers</h2>
        <ul style={styles.ul}>
          <li><strong>Supabase</strong> — authentication and database hosting for your account and content.</li>
          <li><strong>Resend</strong> — delivery of invitation emails.</li>
          <li><strong>Google AdMob</strong> — advertising in the free version.</li>
          <li><strong>Apple</strong> — Sign in with Apple and subscription processing.</li>
        </ul>

        <h2 style={styles.h2}>Data retention and deletion</h2>
        <p style={styles.p}>
          You can permanently delete your account at any time from{' '}
          <strong>Settings &rarr; Delete Account</strong> in the app. This removes your profile, group
          memberships, and personal data. Transactions in groups shared with other people may be retained for
          those members so their balances stay accurate, but are no longer linked to your identity. You may
          also request deletion by emailing us at{' '}
          <a style={styles.a} href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
        </p>

        <h2 style={styles.h2}>Children</h2>
        <p style={styles.p}>
          SplitX is not directed to children under 13, and we do not knowingly collect personal information
          from them.
        </p>

        <h2 style={styles.h2}>Changes to this policy</h2>
        <p style={styles.p}>
          We may update this policy from time to time. Material changes will be reflected by the &ldquo;Last
          updated&rdquo; date above.
        </p>

        <h2 style={styles.h2}>Contact</h2>
        <p style={styles.p}>
          Questions? Email <a style={styles.a} href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
        </p>
      </div>
    </main>
  )
}

const styles: Record<string, React.CSSProperties> = {
  page: {
    minHeight: '100vh',
    background: '#f2f2f7',
    padding: '48px 20px',
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    color: '#1c1c1e',
  },
  container: { maxWidth: 680, margin: '0 auto', lineHeight: 1.6 },
  h1: { fontSize: 32, fontWeight: 700, margin: '0 0 4px' },
  h2: { fontSize: 20, fontWeight: 600, margin: '32px 0 8px' },
  meta: { color: '#8e8e93', fontSize: 14, margin: '0 0 24px' },
  p: { fontSize: 16, margin: '0 0 12px', color: '#3c3c43' },
  ul: { fontSize: 16, margin: '0 0 12px', paddingLeft: 22, color: '#3c3c43' },
  a: { color: '#007aff', textDecoration: 'none' },
}
