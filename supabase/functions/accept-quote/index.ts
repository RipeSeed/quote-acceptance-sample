import { createClient } from 'npm:@supabase/supabase-js@2';
import { handleAcceptQuote, type AcceptOutcome, type AcceptResult } from './handler.ts';

interface AcceptQuoteRow {
  outcome: AcceptOutcome;
  quote_number: string | null;
  accepted_at: string | null;
}

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

async function acceptQuote(token: string): Promise<AcceptResult> {
  const { data, error } = await supabase
    .rpc('accept_quote', { p_token: token })
    .single<AcceptQuoteRow>();

  if (error) {
    throw new Error(`accept_quote failed: ${error.message}`);
  }

  return {
    outcome: data.outcome,
    quoteNumber: data.quote_number,
    acceptedAt: data.accepted_at,
  };
}

Deno.serve((request) => handleAcceptQuote(request, acceptQuote));
