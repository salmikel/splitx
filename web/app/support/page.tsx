import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Support — SplitX',
  description: 'Get help with SplitX.',
}

const CONTACT_EMAIL = 'salvador.mikel@gmail.com'

export default function SupportPage() {
  return (
    <main style={styles.page}>
      <div style={styles.container}>
        <h1 style={styles.h1}>SplitX Support</h1>
        <p style={styles.p}>
          Need help with SplitX? We&rsquo;re happy to assist. Email us and we&rsquo;ll get back to you, usually
          within 1–2 business days.
        </p>
        <p style={styles.p}>
          <a style={styles.emailBtn} href={`mailto:${CONTACT_EMAIL}?subject=SplitX%20Support`}>
            Email {CONTACT_EMAIL}
          </a>
        </p>

        <h2 style={styles.h2}>Common questions</h2>

        <h3 style={styles.h3}>How do I create a group and add expenses?</h3>
        <p style={styles.p}>
          Open <strong>Settings</strong> (the gear icon) and tap <strong>New Group</strong>. Then use the{' '}
          <strong>Expense</strong> button on the dashboard to add a shared expense and choose how to split it.
        </p>

        <h3 style={styles.h3}>How do I invite someone to a group?</h3>
        <p style={styles.p}>
          Open a group&rsquo;s settings and use <strong>Invite Members</strong>. Group sharing is part of
          SplitX Premium.
        </p>

        <h3 style={styles.h3}>What&rsquo;s included in SplitX Premium?</h3>
        <p style={styles.p}>
          Premium ($4.99/year, with Family Sharing) adds group sharing, up to 1,000 transactions per year, and
          CSV import. The free version includes one group and up to 20 transactions. Subscriptions are
          purchased and managed through your Apple ID.
        </p>

        <h3 style={styles.h3}>How do I manage or cancel my subscription?</h3>
        <p style={styles.p}>
          On your device, go to <strong>Settings &rarr; [your name] &rarr; Subscriptions</strong> to manage or
          cancel SplitX Premium. Deleting the app does not cancel a subscription.
        </p>

        <h3 style={styles.h3}>How do I delete my account?</h3>
        <p style={styles.p}>
          In the app, go to <strong>Settings &rarr; Delete Account</strong>. This permanently removes your
          account and personal data. You can also email us to request deletion.
        </p>

        <h2 style={styles.h2}>Still need help?</h2>
        <p style={styles.p}>
          Email <a style={styles.a} href={`mailto:${CONTACT_EMAIL}?subject=SplitX%20Support`}>{CONTACT_EMAIL}</a>{' '}
          with a description of the issue and, if possible, your device model and iOS version.
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
  h1: { fontSize: 32, fontWeight: 700, margin: '0 0 16px' },
  h2: { fontSize: 20, fontWeight: 600, margin: '32px 0 8px' },
  h3: { fontSize: 16, fontWeight: 600, margin: '20px 0 4px' },
  p: { fontSize: 16, margin: '0 0 12px', color: '#3c3c43' },
  a: { color: '#007aff', textDecoration: 'none' },
  emailBtn: {
    display: 'inline-block',
    background: '#007aff',
    color: '#fff',
    fontSize: 16,
    fontWeight: 600,
    textDecoration: 'none',
    padding: '12px 22px',
    borderRadius: 12,
  },
}
