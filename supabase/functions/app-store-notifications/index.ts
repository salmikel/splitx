// Supabase Edge Function: app-store-notifications
//
// Receives App Store Server Notifications V2 from Apple, verifies the signed
// JWS (x5c certificate chain anchored to Apple Root CA - G3, then the ES256
// signature), and updates `profiles.premium_until` with the service role.
//
// This is the *secure* source of truth for the Premium entitlement: because the
// payload is cryptographically verified as coming from Apple, a client cannot
// forge it. Map to a user via `appAccountToken` (the iOS app sets it to the
// user's Supabase UUID at purchase time).
//
// Deploy with verify_jwt = false — Apple does not send a Supabase JWT; trust
// comes entirely from the Apple signature verified below. Fails closed: any
// verification error rejects the request and never grants entitlement.
//
// NOTE: the JWS/x509 verification path cannot be unit-tested here. Validate it
// with App Store Connect's sandbox notifications (and the "Request a Test
// Notification" button) before locking down writes (migration 013).

import { createClient } from 'jsr:@supabase/supabase-js@2'
import * as jose from 'https://esm.sh/jose@5.9.6'
import * as x509 from 'https://esm.sh/@peculiar/x509@1.12.3'

x509.cryptoProvider.set(crypto)

// Apple Root CA - G3 (public), base64 DER. Anchors the notification chain.
const APPLE_ROOT_CA_G3_B64 =
  'MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA=='

const EXPECTED_BUNDLE_ID = 'yourcompany.SharedExpenses'

const appleRoot = new x509.X509Certificate(APPLE_ROOT_CA_G3_B64)

function buffersEqual(a: ArrayBuffer, b: ArrayBuffer): boolean {
  const ua = new Uint8Array(a), ub = new Uint8Array(b)
  if (ua.length !== ub.length) return false
  let diff = 0
  for (let i = 0; i < ua.length; i++) diff |= ua[i] ^ ub[i]
  return diff === 0
}

// Verify an Apple-signed JWS and return its decoded JSON payload.
async function verifyAppleJWS(jws: string): Promise<Record<string, unknown>> {
  const header = jose.decodeProtectedHeader(jws)
  const x5c = header.x5c as string[] | undefined
  if (!x5c || x5c.length < 2) throw new Error('missing x5c chain')

  const certs = x5c.map((b64) => new x509.X509Certificate(b64))
  const now = new Date()

  // 1. Every cert must be within its validity window.
  for (const cert of certs) {
    if (now < cert.notBefore || now > cert.notAfter) throw new Error('certificate not currently valid')
  }
  // 2. Each cert must be signed by the next one in the chain.
  for (let i = 0; i < certs.length - 1; i++) {
    const issuerKey = await certs[i + 1].publicKey.export()
    const ok = await certs[i].verify({ publicKey: issuerKey, signatureOnly: true })
    if (!ok) throw new Error(`chain signature invalid at index ${i}`)
  }
  // 3. The chain must terminate at Apple Root CA - G3 (byte-identical).
  if (!buffersEqual(certs[certs.length - 1].rawData, appleRoot.rawData)) {
    throw new Error('chain does not terminate at Apple Root CA - G3')
  }

  // 4. Verify the JWS signature with the (now-trusted) leaf public key.
  const leafKey = await certs[0].publicKey.export()
  const { payload } = await jose.compactVerify(jws, leafKey)
  return JSON.parse(new TextDecoder().decode(payload))
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  let signedPayload: string
  try {
    const body = await req.json()
    signedPayload = body.signedPayload
    if (!signedPayload) return json({ error: 'missing signedPayload' }, 400)
  } catch {
    return json({ error: 'invalid body' }, 400)
  }

  let notification: Record<string, unknown>
  try {
    notification = await verifyAppleJWS(signedPayload)
  } catch (e) {
    console.error('notification verification FAILED:', (e as Error).message)
    return json({ error: 'verification failed' }, 401)
  }
  console.log('notification VERIFIED — type:', notification.notificationType, 'subtype:', notification.subtype)

  const data = notification.data as Record<string, unknown> | undefined
  if (!data) {
    console.log('no data payload (e.g. TEST notification) — JWS verification works')
    return json({ ok: true, note: 'no data (e.g. TEST notification)' })
  }

  if (typeof data.bundleId === 'string' && data.bundleId !== EXPECTED_BUNDLE_ID) {
    return json({ error: 'unexpected bundle id' }, 400)
  }

  const signedTx = data.signedTransactionInfo as string | undefined
  if (!signedTx) return json({ ok: true, note: 'no transaction info in notification' })

  let tx: Record<string, unknown>
  try {
    tx = await verifyAppleJWS(signedTx)
  } catch (e) {
    console.error('transaction verification failed:', (e as Error).message)
    return json({ error: 'transaction verification failed' }, 401)
  }

  const userId = tx.appAccountToken as string | undefined
  if (!userId) {
    console.warn('notification has no appAccountToken; cannot map to a user')
    return json({ ok: true, note: 'no appAccountToken' })
  }

  // Entitlement window: cleared on revocation/refund, else the expiry date.
  const premiumUntil = tx.revocationDate
    ? null
    : (typeof tx.expiresDate === 'number' ? new Date(tx.expiresDate).toISOString() : null)

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )
  const { error } = await supabase.from('profiles').update({ premium_until: premiumUntil }).eq('id', userId)
  if (error) {
    console.error('failed to update profile:', error.message)
    return json({ error: 'db update failed' }, 500)
  }

  console.log('UPDATED profile', userId, '-> premium_until =', premiumUntil, '(', notification.notificationType, ')')
  return json({ ok: true, notificationType: notification.notificationType, premium_until: premiumUntil })
})
