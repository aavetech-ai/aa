# WhatsApp Sales Assistant — a complete small-business sales system

A production-shaped WhatsApp chatbot that doesn't just answer questions — it **sells**:
it shows the menu, upsells, handles "it's too expensive", collects delivery details,
closes the order, takes payment, sends a receipt, asks for a rating, and chases
customers who go quiet.

Built for a small Kerala food business ("Amma's Kitchen") but every business detail lives
in **one JSON file** — change the config, and it's your shop.

![Live console](docs/console_preview.png)

![Hosted checkout](docs/checkout_preview.png)

*Left: the console at `/console` (real engine behind it, live KPIs on the right).
Right: the payment page a customer lands on from the WhatsApp CTA button.*

```
config/business.json     ← catalog, prices, policies, offers, payment keys
app/nlu.py               ← intent + entity understanding (EN / Hinglish / Malayalam)
app/replies.py           ← every word the customer sees, in 3 languages
app/engine.py            ← the conversation state machine (the sales brain)
app/payments.py          ← payment links (mock checkout or Razorpay)
app/whatsapp.py          ← WhatsApp Cloud API adapter
app/store.py             ← SQLite: sessions, orders, payments, follow-ups
app/main.py              ← FastAPI: webhooks, chat API, checkout page, metrics
app/static/console.html  ← live chat console you can click through
tests/test_flows.py      ← 45 assertions across 10 end-to-end scenarios
docs/sample_conversation.md ← real transcripts generated from the engine
```

---

## Quick start

```bash
cd whatsapp-bot
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Open **http://localhost:8000/console** — a WhatsApp-style simulator with the real bot
behind it, clickable reply buttons, scripted demo scenarios, and live sales KPIs
(revenue, paid orders, conversion, average order).

Run the test suite:

```bash
python3 tests/test_flows.py      # replays 10 conversations, asserts on money + state
```

---

## The sales flow the bot runs

| Stage | What the bot does | Why it matters |
|---|---|---|
| **1. Open** | Greets by name, shows the menu as a numbered list *and* tappable buttons | Zero-typing first step |
| **2. Sell** | Item cards, add-to-cart, **pairing upsell** ("most people add unnakkaya"), **free-delivery nudge** ("₹60 away") | Raises AOV before checkout |
| **3. Handle "no"** | Price objection → quality story → **3-step concession ladder**: free delivery → +4% → +cap (10%). Coupon codes, "ask the owner" fallback | Recovers the deal without wrecking margin |
| **4. Close** | Fulfilment (delivery/pickup) → name → validated address (pincode + zone check) → time slot → **order review** → confirm | Short, linear, one question at a time |
| **5. Collect money** | Generates a payment link, sends a CTA button, auto-confirms on webhook, offers **cash on delivery** as a fallback, verifies "I've paid" | Never loses an order to payment friction |
| **6. After the sale** | Receipt, order status, cancellation, rating ask (5⭐ → coupon, low → owner alert), reorder | Turns one sale into the next |
| **7. Recover** | Abandoned-cart nudge, unpaid-order reminder, review nudge — scheduled jobs | Money that would otherwise leak away |
| **8. Escalate** | Human handoff, complaint handling with replacement/refund promise, owner alerts for complaints, COD orders, cancellations, 1–3⭐ | Keeps a human in the loop where it counts |

The exact transcripts are in [`docs/sample_conversation.md`](docs/sample_conversation.md).

---

## Commercial guardrails (all configurable)

- `min_order_value` — below it, the bot offers one-tap ways to clear the gap instead of dead-ending.
- `free_delivery_above` — used as the upsell trigger, not just a rule.
- `max_discount_pct` — the concession ladder is hard-capped here; beyond it the bot says
  "that needs the owner" and offers a **Talk to a human** button.
- `delivery_zones` + pincode check — out-of-zone addresses get pickup offered, not a dead end.
- Follow-up timing (`FOLLOWUP_CART_SECONDS`, `FOLLOWUP_PAYMENT_SECONDS`) so you nudge without spamming.
- `stop` / `unsubscribe` opts the customer out and cancels all queued nudges instantly.

---

## Going live on WhatsApp (Cloud API)

1. Create a Meta app → add the **WhatsApp** product → get a test number.
2. Set env vars:

```bash
export WA_TOKEN="EAAG..."           # permanent token
export WA_PHONE_ID="1234567890"     # phone number id
export WA_VERIFY_TOKEN="my-secret"  # any string, paste the same in Meta
export WA_APP_SECRET="..."          # optional, enables signature checks
export PUBLIC_BASE_URL="https://your-domain.com"
```

3. Expose the server (e.g. `ngrok http 8000`) and set the webhook URL to
   `https://your-domain.com/webhooks/whatsapp`, subscribe to the **messages** field.
4. Customise `config/business.json`, restart, message your number.

Without those env vars the adapter runs in **dry-run mode**: it logs exactly what it would
send and the local console stays fully usable.

**Note on copy:** the engine emits WhatsApp-native shapes — `text`, `interactive/button`
(max 3 reply buttons), and `interactive/cta_url` for the payment link — so nothing needs
rewriting at the adapter layer. Long bodies are truncated to Meta's 1024-char limit.

---

## Taking payments

Two providers, one interface (`payments.create_payment_link`):

| Provider | Setup | Behaviour |
|---|---|---|
| `mock` (default) | nothing | Serves `GET /pay/{order_id}` — a real checkout page with the order summary and a **Pay ₹X** button. Paying calls the engine's `on_payment_success()`, so the WhatsApp confirmation fires exactly like production. |
| `razorpay` | `PAYMENT_PROVIDER=razorpay`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` | Creates a real Razorpay **Payment Link** (UPI/GPay/PhonePe/card/netbanking), sends it as a WhatsApp CTA button, and confirms on the `payment_link.paid` webhook. Falls back to the mock link if the API call fails — a sale is never blocked by a payment outage. |

Cash on delivery is a first-class path: `update_order(status="cod")`, payment reminders cancelled,
the customer is told the exact amount to keep ready, and the owner gets an alert.

To add Stripe/PhonePe/PayU: write one function returning `(url, provider_ref)` and route it
in `create_payment_link()` — nothing else changes.

---

## Two modes: retail shop and professional services

The same engine runs two very different businesses:

| | **Retail mode** (Amma's Kitchen, bakery, fish, clinic packages) | **Service mode** (AAVETech) |
|---|---|---|
| Flow | menu → cart → delivery/pickup → address → slot → pay → receipt → rating | service → urgency → remote/on-site → org + domain → scope → call slot → **40% advance** → booked |
| Payment | full amount, COD allowed | advance only, no COD, balance on delivery |
| Special path | — | **incident triage**: "hacked/ransomware/UPI fraud" skips selling entirely, returns containment steps + 24/7 line + owner alert |
| Copy | delivery, pincode, review ask | engagement, consultant call, compliance reminder (never share passwords/OTPs) |

Service mode is switched on by `"flow": {"mode": "service"}` in the client config.

**AAVETech handover:** `docs/aavetech_handover.md` · transcripts: `docs/aavetech_conversations.md`

```bash
python3 tools/switch_client.py aavetech      # AAVETech service bot
python3 tools/switch_client.py --list
python3 tests/test_service_flow.py           # service-mode test suite
python3 tests/test_flows.py                  # retail test suite
```

## Selling this to clients (multi-tenant demos)

The engine is config-driven, so one install can demo any business. Ready-made client profiles live in
`config/clients/`:

```bash
python3 tools/switch_client.py --list        # bakery | fresh_fish | ayurveda_clinic
python3 tools/switch_client.py bakery        # load the bakery shop
./run.sh                                     # restart; console now shows their catalogue
python3 tools/switch_client.py --default     # back to Amma's Kitchen
```

Fit analysis, scored prospect list and pricing guidance: see `../client-fit-report.md` and
`../prospects.csv` in the parent folder.

## Making it *your* shop

Everything customer-facing is data or copy, not code:

- **Catalog / prices / policies** → `config/business.json`
- **Any sentence the bot says** → `app/replies.py` (`COPY` for messages, `LABELS` for buttons),
  keyed by language with automatic English fallback. Add a language by adding a key.
- **Sales behaviour** → `app/engine.py`: the concession ladder (`_negotiate`), upsell rules
  (`_add_products`), and the state machine (`_start_checkout` → `_review` → `_send_payment_link`).
- **Payments** → `app/payments.py`.
- **Channel** → the engine returns channel-agnostic action dicts, so a Telegram/Instagram/web-widget
  adapter is a ~100-line file next to `whatsapp.py`.

### Using an LLM instead of the rule-based NLU

`app/nlu.py` is deliberately deterministic (regex + multilingual keywords): cheap, instant,
offline, and testable. If you want free-form understanding later, replace `classify()` with a
model call that returns the same `(intent, entities)` tuple — the engine is unchanged. Keep the
regex layer as the fallback for when the model is slow or down.

---

## API surface

| Endpoint | Purpose |
|---|---|
| `POST /api/chat` | `{wa_id, text?/button_id?}` → outbound actions. Powers the console, a website widget, or any channel. |
| `GET /webhooks/whatsapp` / `POST` | Meta verification + inbound messages (HMAC verified). |
| `POST /webhooks/razorpay` | Payment success webhook. |
| `GET /pay/{order_id}` | Hosted checkout page (mock provider). |
| `POST /api/mock/pay/{order_id}` | Simulates a successful payment. |
| `GET /api/metrics` | Revenue, paid orders, awaiting payment, conversion %, AOV, discount given. |
| `GET /api/orders`, `GET /api/sessions` | Owner dashboard feeds. |
| `GET /api/transcript/{wa_id}` | Full conversation log (used for the live poll in the console). |
| `POST /api/followups/run` | Force due nudges to send now (handy for demos). |
| `GET /healthz` | Liveness + business name. |

---

## Deploy

**Render (one-click blueprint):** `render.yaml` is included — New + → Blueprint → pick the repo.
Full walkthrough, env-var table, WhatsApp webhook setup, free-tier caveats and troubleshooting:
**[`docs/DEPLOY_RENDER.md`](docs/DEPLOY_RENDER.md)**.

**Anywhere with Docker:**

```bash
docker build -t wa-sales-bot .
docker run -p 8000:8000 --env-file .env -v $(pwd)/data:/app/data wa-sales-bot
```

> The dashboard is protected by `ADMIN_TOKEN` (HTTP Basic). Webhooks, `/healthz` and the customer
> payment page stay public by design. Set it before you put this on a public URL.

SQLite lives in `data/bot.db` — volume-mount it. For multi-instance deployments swap
`app/store.py` onto Postgres (the module is the only place that touches the DB), and move the
follow-up scheduler (`_followup_loop` in `main.py`) to a cron/queue worker.

---

## What to change before real customers

1. Replace the demo catalog, prices, UPI id, and the owner alert number (`_notify_owner` currently logs — wire it to the owner's WhatsApp or Slack).
2. Put real legal copy behind `returns` and add your GST/address details to receipts.
3. Turn on `WA_APP_SECRET` + `RAZORPAY_WEBHOOK_SECRET` and verify both webhooks.
4. Add real inventory decrement on payment (stock numbers exist in the config but are static).
