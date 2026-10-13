// Supabase Edge Function — scaffold only, implemented in Phase 11.
//
// Purpose: receives a carrierId, loads that carrier's truck + location +
// history from Postgres, loads open cargo rows, calls the OpenAI API with
// a structured prompt (never free-text guessing) and returns a ranked
// match list which the client then persists to public.ai_matches.
//
// This is the ONLY place the OpenAI API key is used — it is read from
// `Deno.env.get('OPENAI_API_KEY')` (a Supabase secret), never shipped to
// the Flutter client.
//
// Deploy: supabase functions deploy ai-match
// Secret:  supabase secrets set OPENAI_API_KEY=sk-...

// @ts-nocheck
import { serve } from 'https://deno.land/std@0.203.0/http/server.ts';

serve(async (req) => {
  return new Response(
    JSON.stringify({ error: 'Not implemented yet — see Phase 11: AI matching engine.' }),
    { status: 501, headers: { 'Content-Type': 'application/json' } },
  );
});
