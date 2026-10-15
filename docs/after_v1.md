# After V1: the list

Work Tim has decided on, to start once the iOS app's V1 is submitted
(2026-10-15). Not the app roadmap (that's in CLAUDE.md): these are fixes
that came up while finishing V1.

## 1. Sign-up question answers (build it properly)

Custom questions on sign-up forms are switched off
(`SignUpForm::CUSTOM_QUESTIONS = false`, 2026-10-15). The sign-up page showed
them, but nothing saved what people typed: the questions sat outside the
submitted form, and `SignUpRegistration` has no answers (see the TODO in
`app/models/sign_up_registration.rb`). Only the demo organization had
questions, so no real answers were lost.

To build:
- Store answers for a registration (the `answers` table, made polymorphic, as
  the TODO describes), for members and guests.
- Put the questions inside the sign-up form (`my/sign_ups/form.html.erb`) and
  save them in `My::SignUpsController#submit_form`, required ones enforced.
- Show each person's answers to producers next to their sign-up (the roster
  and the printed list).
- Then set `CUSTOM_QUESTIONS` back to true (it brings back the Questions tab).

## 2. Payee details asked once, up front

Stripe wants date of birth and the last four of the SSN from each person
CocoScout pays once they've been paid $3,000; the app only asks for what's
due now, so their pay would pause then. 129 accounts were flagged on
2026-10-15; nobody was near $3,000 (highest about $1,400).

- Sign-up for getting paid asks for everything at the start: change
  `collection_options` in `StripeConnectService#onboarding_link` to collect
  `eventually_due`.
- People already set up: a quiet heads-up on My Payments once they've been
  paid about $2,000, with a button to add the two details. No emails.
- Copy never says "Stripe": "our payment provider" (Tim).

## 3. Door messages that say "Stripe"

Reword for door staff, per the same rule: "Stripe hasn't confirmed the
payment yet", "Stripe took $X, not this sale's total", "Stripe couldn't start
that sale" (`app/services/tap_to_pay.rb`, `app/controllers/door_controller.rb`)
and "Confirming with Stripe…" (`door_tap_controller.js`).
