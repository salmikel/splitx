import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

const APP_URL = 'https://splitx.salvador-mikel.workers.dev'

export async function POST(req: NextRequest) {
  const { email, groupId, groupName, inviterName } = await req.json()

  if (!email || !groupId || !groupName) {
    return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
  }

  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

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
            <strong>${inviterName ?? 'A friend'}</strong> invited you to join the <strong>${groupName}</strong> expense group on SplitX.
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
