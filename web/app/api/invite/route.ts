import { NextRequest, NextResponse } from 'next/server'
import { createClient as createBrowserSessionClient } from '@/lib/supabase/server'
import { createClient as createTokenClient } from '@supabase/supabase-js'

const APP_URL = 'https://splitx.salvador-mikel.workers.dev'

// Bump this string whenever the route changes so a deploy can be verified by
// visiting /api/invite in a browser (GET). If the browser shows an older
// version (or 404/405), the Worker is still running stale code.
const ROUTE_VERSION = 'invite-v2-bearer'

// Deployment check: GET /api/invite returns the running route version.
export function GET() {
  return NextResponse.json({ version: ROUTE_VERSION })
}

/// Escapes user-supplied text before embedding it in the invitation email HTML.
function escapeHtml(input: string): string {
  return input
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

export async function POST(req: NextRequest) {
  const { email, groupId, groupName, inviterName } = await req.json()

  if (!email || !groupId || !groupName) {
    return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
  }

  // The web app authenticates via session cookies; the native iOS app sends its
  // Supabase access token as a Bearer header (it has no cookies). Support both,
  // so RLS is enforced as the calling user in either case.
  const authz = req.headers.get('authorization') ?? ''
  const hasBearer = authz.startsWith('Bearer ')
  const supabase = hasBearer
    ? createTokenClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          global: { headers: { Authorization: authz } },
          auth: { persistSession: false, autoRefreshToken: false },
        }
      )
    : await createBrowserSessionClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) {
    // Distinguish "the app never sent a token" from "the token was rejected"
    // so a failed invite tells us which side is stale.
    const reason = hasBearer
      ? 'Unauthorized: session token was rejected (expired or invalid)'
      : 'Unauthorized: no credentials received (app sent no Bearer token)'
    return NextResponse.json({ error: reason }, { status: 401 })
  }

  // Create the invitation record
  const { data: inv, error: invErr } = await supabase
    .from('invitations')
    .insert({ group_id: groupId, invited_by: user.id, email: email.trim().toLowerCase() })
    .select('token')
    .single()

  if (invErr || !inv) {
    return NextResponse.json({ error: invErr?.message ?? 'Failed to create invitation' }, { status: 400 })
  }

  const inviteUrl = `${APP_URL}/invite?token=${inv.token}`
  const safeGroupName = escapeHtml(groupName)
  const safeInviter = escapeHtml(inviterName ?? 'A friend')

  // Send email via Resend API
  const resendKey = process.env.RESEND_API_KEY
  if (!resendKey) {
    return NextResponse.json({ error: 'Email service not configured' }, { status: 500 })
  }

  const emailRes = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'SplitX <noreply@salescalamity.com>',
      to: [email.trim()],
      subject: `${inviterName ?? 'Someone'} invited you to join ${groupName} on SplitX`,
      html: `
        <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;max-width:480px;margin:0 auto;padding:32px 24px;background:#f2f2f7;border-radius:16px;">
          <h1 style="font-size:24px;font-weight:700;color:#1c1c1e;margin:0 0 8px;">You're invited!</h1>
          <p style="font-size:16px;color:#3c3c43;margin:0 0 24px;">
            <strong>${safeInviter}</strong> invited you to join the <strong>${safeGroupName}</strong> expense group on SplitX.
          </p>
          <a href="${inviteUrl}"
             style="display:inline-block;background:#007aff;color:#fff;font-size:17px;font-weight:600;text-decoration:none;padding:14px 28px;border-radius:12px;">
            Accept Invitation
          </a>
          <p style="font-size:13px;color:#8e8e93;margin:24px 0 0;">
            This invitation expires in 7 days. If you don't have a SplitX account yet, you'll be prompted to create one.
          </p>
        </div>
      `,
    }),
  })

  if (!emailRes.ok) {
    const body = await emailRes.json().catch(() => ({}))
    return NextResponse.json(
      { error: `Email delivery failed: ${(body as { message?: string }).message ?? emailRes.statusText}` },
      { status: 500 }
    )
  }

  return NextResponse.json({ success: true })
}
