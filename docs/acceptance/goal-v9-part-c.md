# Goal 9 Part C phase report

> Status: the client-identity difference has been implemented as approved by the
> user; both the deterministic gate and the real-OAuth hard gate pass.

## 1. Approved difference

The `originator` in the OpenAI authorize query and in the Codex Responses header
changes from the baseline's `pi` to `cadr`. That field is used for third-party
client attribution; it does not change the provider identity `openai-codex`, the
OAuth parameters, the credential store, the Responses payload or the event
semantics.

The production value is centralized in `+openai-originator+` in
`src/cadr-ai/oauth.lisp`, referenced jointly by the authorize URL and the
Responses transport, so that the two identity paths do not diverge again.

## 2. Tests first and the deterministic gates

The red phase, produced by changing the assertions first while keeping the
production value at `pi`:

- `OPENAI-AUTHORIZATION-URL-USES-APPROVED-CADR-ORIGINATOR-DIFFERENCE`:
  `9 checks / 7 pass / 2 fail`, with the actual URL still `originator=pi`.
- `OPENAI-OAUTH-USES-CODEX-URL-AND-APPROVED-CADR-ORIGINATOR-HEADER`:
  `5 checks / 4 pass / 1 fail`, with the actual header being `pi`.

After implementation the two are `9/9` and `5/5` respectively. The end-to-end
deterministic gate
`LOGIN-OPENAI-TEMP-STORE-DEFAULT-RESOLVER-ROUTES-CODEX-REQUEST` uses a temporary
auth store, a temporary configuration and an HTTP stub to prove that
`/login openai` is stored as `openai-codex`, that the default route enters the
Codex transport without provider/model arguments, and that the header is
`originator=cadr`; the result is `12/12`.

An audit of `test/fixtures/` and `scripts/export-ts-payloads.ts` found no
`originator`: the existing cross-implementation comparison fixtures serialize
only the request body and do not contain the authorize URL or HTTP headers. The
number of affected fixtures is therefore `0`, and no fixture was silently
rewritten or left un-updated.

## 3. Real-OAuth hard gate

On 2026-08-01, the `./cadr --no-tui` newly built in this Part was used to
execute the following in one and the same process:

1. the real authorize URL displayed by `/login openai` contains
   `originator=cadr`;
2. the callback succeeds and prints
   `openai-codex login stored in /root/.cadr/auth.json`;
3. without passing `--provider` or `--model`, sending
   `Reply with exactly CADR_ORIGINATOR_OK and nothing else.`;
4. the actual response is verbatim `assistant> CADR_ORIGINATOR_OK`;
5. the mode of `~/.cadr/auth.json` is `0600`.

No originator rejection occurred, and there was no fallback to `pi`.

## 4. Closeout evidence

- New third-party dependencies: `0`.
- Part duration: about 1 hour, including waiting for manual browser
  authorization.
- token: the product does not provide an auditable exact token count for this
  Part; no estimate was fabricated.
- Commit: this Part is committed separately.
