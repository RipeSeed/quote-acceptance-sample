import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  handleAcceptQuote,
  type AcceptOutcome,
  type AcceptQuote,
} from '../supabase/functions/accept-quote/handler.ts';

const TOKEN = '11111111-1111-4111-8111-111111111111';
const ENDPOINT = 'http://localhost/functions/v1/accept-quote';

function postRequest(body: string): Request {
  return new Request(ENDPOINT, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
}

function fakeAcceptQuote(outcome: AcceptOutcome = 'accepted') {
  return vi.fn<AcceptQuote>(async () => ({
    outcome,
    quoteNumber: outcome === 'not_found' ? null : 'Q-2026-0001',
    acceptedAt: outcome === 'accepted' ? '2026-11-11T09:00:00.000Z' : null,
  }));
}

describe('handleAcceptQuote', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('answers CORS preflight requests without touching the database', async () => {
    const acceptQuote = fakeAcceptQuote();

    const response = await handleAcceptQuote(new Request(ENDPOINT, { method: 'OPTIONS' }), acceptQuote);

    expect(response.status).toBe(204);
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe('*');
    expect(response.headers.get('Access-Control-Allow-Methods')).toContain('POST');
    expect(acceptQuote).not.toHaveBeenCalled();
  });

  it('rejects methods other than POST', async () => {
    const acceptQuote = fakeAcceptQuote();

    const response = await handleAcceptQuote(new Request(ENDPOINT, { method: 'GET' }), acceptQuote);

    expect(response.status).toBe(405);
    expect(response.headers.get('Allow')).toBe('POST, OPTIONS');
    expect(acceptQuote).not.toHaveBeenCalled();
  });

  it('rejects a body that is not JSON', async () => {
    const acceptQuote = fakeAcceptQuote();

    const response = await handleAcceptQuote(postRequest('token=abc'), acceptQuote);

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: 'Request body must be valid JSON.' });
    expect(acceptQuote).not.toHaveBeenCalled();
  });

  it.each([
    ['a missing token', '{}'],
    ['a null body', 'null'],
    ['a token that is not a UUID', '{"token":"not-a-uuid"}'],
    ['a token that is not a string', '{"token":12345}'],
  ])('rejects %s', async (_case, body) => {
    const acceptQuote = fakeAcceptQuote();

    const response = await handleAcceptQuote(postRequest(body), acceptQuote);

    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: 'A valid quote token is required.' });
    expect(acceptQuote).not.toHaveBeenCalled();
  });

  it('passes the token to acceptQuote', async () => {
    const acceptQuote = fakeAcceptQuote();

    await handleAcceptQuote(postRequest(JSON.stringify({ token: TOKEN })), acceptQuote);

    expect(acceptQuote).toHaveBeenCalledOnce();
    expect(acceptQuote).toHaveBeenCalledWith(TOKEN);
  });

  it.each<[AcceptOutcome, number]>([
    ['accepted', 200],
    ['not_found', 404],
    ['already_accepted', 409],
    ['expired', 410],
    ['not_open', 409],
  ])('maps the %s outcome to HTTP %i', async (outcome, status) => {
    const response = await handleAcceptQuote(
      postRequest(JSON.stringify({ token: TOKEN })),
      fakeAcceptQuote(outcome),
    );

    expect(response.status).toBe(status);
    expect(response.headers.get('Access-Control-Allow-Origin')).toBe('*');
    expect(await response.json()).toMatchObject({ outcome, message: expect.any(String) });
  });

  it('returns the quote number and acceptance time when accepted', async () => {
    const response = await handleAcceptQuote(
      postRequest(JSON.stringify({ token: TOKEN })),
      fakeAcceptQuote('accepted'),
    );

    expect(await response.json()).toEqual({
      outcome: 'accepted',
      message: 'Quote accepted. Thank you!',
      quoteNumber: 'Q-2026-0001',
      acceptedAt: '2026-11-11T09:00:00.000Z',
    });
  });

  it('turns an unexpected error into a 500 without leaking details', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {});
    const acceptQuote = vi.fn<AcceptQuote>(async () => {
      throw new Error('connection to db-internal:5432 refused');
    });

    const response = await handleAcceptQuote(postRequest(JSON.stringify({ token: TOKEN })), acceptQuote);
    const text = await response.text();

    expect(response.status).toBe(500);
    expect(JSON.parse(text)).toEqual({ error: 'Something went wrong. Please try again later.' });
    expect(text).not.toContain('db-internal');
    expect(consoleError).toHaveBeenCalled();
  });
});
