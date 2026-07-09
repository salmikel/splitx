import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Terms of Use — SplitX',
  description: 'The terms governing your use of SplitX.',
}

const LAST_UPDATED = 'July 7, 2026'
const CONTACT_EMAIL = 'salvador.mikel@gmail.com'

export default function TermsPage() {
  return (
    <main style={styles.page}>
      <div style={styles.container}>
        <h1 style={styles.h1}>Terms of Use</h1>
        <p style={styles.meta}>Last updated: {LAST_UPDATED}</p>

        <p style={styles.p}>
          These Terms of Use (&ldquo;Terms&rdquo;) govern your use of the SplitX app. By using SplitX, you
          agree to these Terms. If you do not agree, please do not use the app.
        </p>

        <h2 style={styles.h2}>Using SplitX</h2>
        <p style={styles.p}>
          SplitX is a tool to record and split shared expenses among people you choose. You are responsible
          for the accuracy of the information you enter and for any decisions you make based on it. SplitX does
          not process, hold, or transfer money between users.
        </p>

        <h2 style={styles.h2}>Your account</h2>
        <p style={styles.p}>
          You must provide a valid email address to create an account and are responsible for activity under
          your account. You may delete your account at any time from Settings within the app.
        </p>

        <h2 style={styles.h2}>Subscriptions</h2>
        <ul style={styles.ul}>
          <li>SplitX Premium is offered as an auto-renewing annual subscription that removes ads.</li>
          <li>
            Payment is charged to your Apple ID account at confirmation of purchase. The subscription
            automatically renews for the same period unless you cancel at least 24 hours before the end of the
            current period.
          </li>
          <li>Your account is charged for renewal within 24 hours before the end of the current period.</li>
          <li>
            You can manage or cancel your subscription in your device&rsquo;s{' '}
            <strong>Settings &rarr; Apple ID &rarr; Subscriptions</strong> at any time. Deleting the app does
            not cancel a subscription.
          </li>
          <li>Prices are shown in the app before purchase and may vary by region.</li>
        </ul>

        <h2 style={styles.h2}>Acceptable use</h2>
        <p style={styles.p}>
          You agree not to misuse the app, attempt to disrupt or reverse-engineer it, or use it for any
          unlawful purpose.
        </p>

        <h2 style={styles.h2}>Disclaimer</h2>
        <p style={styles.p}>
          SplitX is provided &ldquo;as is&rdquo; without warranties of any kind. To the maximum extent
          permitted by law, we are not liable for any indirect or consequential damages arising from your use
          of the app, including any financial disputes between users.
        </p>

        <h2 style={styles.h2}>Changes</h2>
        <p style={styles.p}>
          We may update these Terms from time to time. Continued use of the app after changes constitutes
          acceptance of the revised Terms.
        </p>

        <h2 style={styles.h2}>Contact</h2>
        <p style={styles.p}>
          Questions about these Terms? Email{' '}
          <a style={styles.a} href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
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
