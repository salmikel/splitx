// Supabase Edge Function: delete-account
//
// Permanently deletes the authenticated user's account.
//
// Deleting an auth user requires the service-role key, which must NEVER be
// shipped in the client app — so this runs server-side. The caller is
// identified from their own JWT (passed in the Authorization header); we only
// ever delete *that* user, never an arbitrary id supplied by the client.
//
// Because `public.profiles.id` references `auth.users(id) ON DELETE CASCADE`,
// and `group_members` / `transaction_splits` cascade from `profiles`, removing
// the auth user also removes the user's profile, memberships, and split rows.
// Shared rows in other members' groups are preserved (their `paid_by` /
// `created_by` / `invited_by` foreign keys are `ON DELETE SET NULL`).
//
// Required for App Store Guideline 5.1.1(v): apps that create accounts must
// let users delete them from within the app.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return json({ error: 'Missing authorization header' }, 401)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: 'Server not configured' }, 500)
  }

  // Identify the caller from their own JWT — this is the only user we delete.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  })
  const { data: { user }, error: userErr } = await userClient.auth.getUser()
  if (userErr || !user) {
    return json({ error: 'Unauthorized' }, 401)
  }

  // Delete the auth user with the service role; FK cascades handle the rest.
  const admin = createClient(supabaseUrl, serviceKey)
  const { error: delErr } = await admin.auth.admin.deleteUser(user.id)
  if (delErr) {
    return json({ error: delErr.message }, 500)
  }

  return json({ success: true }, 200)
})
