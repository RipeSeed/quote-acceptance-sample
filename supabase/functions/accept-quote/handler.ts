export type AcceptOutcome = 'accepted' | 'not_found' | 'already_accepted' | 'expired' | 'not_open';

export interface AcceptResult {
  outcome: AcceptOutcome;
  quoteNumber: string | null;
  acceptedAt: string | null;
}

export type AcceptQuote = (token: string) => Promise<AcceptResult>;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const outcomeResponses: Record<AcceptOutcome, { status: number; message: string }> = {
  accepted: { status: 200, message: 'Quote accepted. Thank you!' },
  not_found: { status: 404, message: 'Quote not found.' },
  already_accepted: { status: 409, message: 'This quote has already been accepted.' },
  expired: { status: 410, message: 'This quote has expired. Please contact us for a new one.' },
  not_open: { status: 409, message: 'This quote is not open for acceptance.' },
};

export async function handleAcceptQuote(request: Request, acceptQuote: AcceptQuote): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return json(405, { error: 'Method not allowed.' }, { Allow: 'POST, OPTIONS' });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: 'Request body must be valid JSON.' });
  }

  const token = readToken(body);
  if (!token) {
    return json(400, { error: 'A valid quote token is required.' });
  }

  try {
    const result = await acceptQuote(token);
    const { status, message } = outcomeResponses[result.outcome];
    return json(status, {
      outcome: result.outcome,
      message,
      quoteNumber: result.quoteNumber,
      acceptedAt: result.acceptedAt,
    });
  } catch (error) {
    console.error('accept-quote failed', error);
    return json(500, { error: 'Something went wrong. Please try again later.' });
  }
}

function readToken(body: unknown): string | null {
  if (typeof body !== 'object' || body === null || !('token' in body)) {
    return null;
  }
  const { token } = body;
  return typeof token === 'string' && UUID_PATTERN.test(token) ? token : null;
}

function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json', ...headers },
  });
}
