# frozen_string_literal: true

class Contract < ApplicationRecord
  belongs_to :organization
  belongs_to :contractor, optional: true

  has_many :contract_documents, dependent: :destroy
  has_many :contract_payments, dependent: :destroy
  has_many :space_rentals, dependent: :destroy
  # A contract is FOR one production (the real-world show). A production can be the
  # subject of many contracts over time — see Production#contracts.
  belongs_to :production, optional: true
  # The template whose wording rendered this contract's signable document (only
  # set for e-sign contracts; offline contracts never pick one).
  belongs_to :contract_template, optional: true
  has_many :course_offerings, dependent: :nullify
  has_many :contract_signatures, dependent: :destroy
  has_many :contract_versions, dependent: :destroy
  has_many :contract_appendixes, dependent: :destroy

  # Status enum
  enum :status, {
    draft: "draft",
    active: "active",
    completed: "completed",
    cancelled: "cancelled"
  }, default: :draft, prefix: :status

  # How this contract's signature is handled. :offline is the classic behavior
  # (signed elsewhere, PDF optionally uploaded) and the default for every existing
  # contract. :esign engages CocoScout's native create → send → sign → PDF flow.
  enum :signing_mode, {
    offline: "offline",
    esign: "esign"
  }, default: :offline, prefix: :signing_mode

  # Native-signing lifecycle (esign contracts only):
  #   unsent → awaiting_send → out_for_signature → executed
  # unsent: still being prepared/signed by the org side (wizard Prepare/Sign steps).
  # awaiting_send: the org has signed; the document is locked and ready to send.
  # out_for_signature: sent to the counterparty. executed: they signed.
  # Independent of :status (draft/active/…) — execution auto-activates the contract.
  enum :signing_state, {
    unsent: "unsent",
    awaiting_send: "awaiting_send",
    out_for_signature: "out_for_signature",
    executed: "executed"
  }, default: :unsent, prefix: :signing

  validates :contractor_name, presence: true

  # Merge tokens a template can drop inside its own wording to place deal content
  # inline, instead of relying on the Deal Terms schedule appended at the end.
  # {{license_schedule}} → the dates/stage/rent grid; {{services}} → the service
  # line items. When a template uses either, the appended block is suppressed so
  # nothing is duplicated — see #render_document_for.
  LICENSE_SCHEDULE_TOKEN = "{{license_schedule}}"
  SERVICES_TOKEN = "{{services}}"
  APPENDIXES_TOKEN = "{{appendixes}}"

  # Ways money can reach us that aren't the online pay link. Each must be
  # allowed on the contract before a manager may record one.
  OFFLINE_PAYMENT_METHODS = %w[check bank_transfer cash].freeze

  # Labels for the offline methods, in the order they're offered.
  OFFLINE_PAYMENT_METHOD_LABELS = {
    "check" => "Check",
    "bank_transfer" => "Bank transfer",
    "cash" => "Cash"
  }.freeze

  # Callbacks to sync contractor data
  before_save :sync_contractor_info

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :upcoming, -> { status_active.where("contract_end_date >= ?", Date.current).order(:contract_start_date) }
  scope :past, -> { where("contract_end_date < ?", Date.current).order(contract_end_date: :desc) }

  # Allow overlap flag - when true, skip overlap validation on space rentals
  attr_accessor :allow_overlap

  # Lifecycle methods
  def activate!
    activated = false

    # Lock the row for the whole activation so two concurrent activate requests
    # (double-click, or the wizard + money endpoints firing together) can't both
    # pass the draft check and each create a duplicate production/shows/payments.
    # The second caller blocks here, then sees status == active and no-ops.
    with_lock do
      next unless status_draft?
      next unless valid_for_activation?

      create_records_from_draft!

      update!(
        status: :active,
        activated_at: Time.current,
        skip_event_creation: false
        # Keep draft_data - it contains the full contract config (services, payment_config, etc.)
      )
      activated = true
    end

    activated
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end

  def complete!
    return false unless status_active?

    transaction do
      update!(
        status: :completed,
        completed_at: Time.current
      )

      # Archive the production only if no OTHER active contract still uses it
      # (a production can be shared by several contracts over time).
      if production && production.contracts.status_active.where.not(id: id).none? && !production.archived?
        production.update!(archived_at: Time.current)
      end
    end

    true
  end

  # Reverse a completion so the contract can be extended again — e.g. a teacher
  # ran a course in June and you now want to add August dates and reuse the
  # contract. Flips completed → active and un-archives the production that was
  # archived on completion, so amending (and selecting it for a new course) works.
  def reopen!
    return false unless status_completed?

    transaction do
      update!(status: :active, completed_at: nil)
      production.update!(archived_at: nil) if production&.archived?
    end

    true
  end

  def cancel!(delete_events: false)
    return false if status_cancelled?

    transaction do
      if delete_events
        # Remove only THIS contract's shows (the production may be shared with
        # other contracts, so we never destroy the whole production here).
        # Unlink referencing payments first — contract_payments.show_id has a FK
        # that blocks deleting a referenced show (and those payments may belong
        # to other contracts, so we drop the link, not the payment).
        show_ids = contract_shows.pluck(:id)
        ContractPayment.where(show_id: show_ids).update_all(show_id: nil) if show_ids.any?
        # Suppress the per-show payment sync while destroying — it re-links a
        # payment to the show being deleted, violating the FK we just cleared.
        Show.without_contract_payment_sync { contract_shows.destroy_all }
      else
        contract_shows.update_all(canceled: true)
      end

      update!(
        status: :cancelled,
        cancelled_at: Time.current
      )
    end

    true
  end

  # ─── Native e-signature ─────────────────────────────────────────────────────

  # The counterparty's CocoScout member Person, if they already have a login — so
  # we can tell them the contract will also appear in their My Contracts. Resolves
  # the linked contractor Person, else matches an org Person by email; returns it
  # only when it's a real member (has a user account). Never creates anything.
  def signer_member_person
    person = contractor&.person
    person ||= organization.people.where("LOWER(email) = ?", contractor_email.to_s.downcase).first if contractor_email.present?
    person if person&.user_id.present?
  end

  def signer_is_member?
    signer_member_person.present?
  end

  # The CocoScout Person this contract is (or would be) sent to — the contractor's
  # linked person, else an org person matching the contractor email. Unlike
  # #signer_member_person this doesn't require them to have accepted a login yet;
  # it's the "is there a CocoScout user attached?" gate for sending.
  def signer_person_record
    return contractor.person if contractor&.person
    return nil if contractor_email.blank?

    organization.people.where("LOWER(email) = ?", contractor_email.to_s.downcase).first
  end

  # Of the CURRENT version — an internal-correction version carries the last
  # signed version's signatures forward for display.
  def organization_signature
    current_version&.effective_signatures&.find(&:role_organization?)
  end

  def contractor_signature
    current_version&.effective_signatures&.find(&:role_contractor?)
  end

  # The generated (or uploaded) signed-contract PDF, if one is attached. Uses the
  # loaded association (so a preloaded index doesn't re-query per card).
  # The last fully executed version's PDF. While a newer version is out for
  # re-signature it must still return the previous one, or the page claims the
  # PDF is perpetually "being generated".
  def signed_pdf_document
    latest_executed_version&.pdf_document ||
      contract_documents.to_a.select { |d| d.document_type == "signed_contract" && d.contract_version_id.nil? }
                        .detect { |d| d.file.attached? }
  end

  # Kick off signed-PDF generation if this is executed but has none yet. Safe to
  # call from a view/GET — the job is idempotent and no-ops when a PDF exists.
  def ensure_signed_pdf!
    version = latest_executed_version
    GenerateContractPdfJob.perform_later(id, version.id) if version && version.pdf_document.nil?
  end

  # Mint a fresh public signing token (rotates any prior one — an old link dies).
  def regenerate_signing_token!
    update!(signing_token: SecureRandom.urlsafe_base64(24))
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Prepare (wizard "Prepare" step): lock in the template whose wording will render
  # the document. The producer previews the rendered contract before this. Idempotent
  # — they can re-pick and re-preview until they sign.
  def prepare_for_signature!(template:)
    raise ArgumentError, "not an e-sign contract" unless signing_mode_esign?
    raise ArgumentError, "template required" if template.nil?
    return false if signing_executed? || signing_out_for_signature?

    update!(contract_template: template)
    true
  end

  # Org signs (wizard "Sign" step): the org's own deliberate signature, stamped with
  # the producer + timestamp + IP, over the locked document snapshot. Moves the
  # contract to awaiting_send — nothing has gone to the counterparty yet.
  def sign_by_org!(signer_name:, signed_by:, request:)
    raise ArgumentError, "choose a template first" if contract_template.nil?
    return false if signing_executed? || signing_out_for_signature?

    transaction do
      # Cut (or refresh) the version this signature is against, and sign THAT
      # text — the two must be byte-identical, so never render twice.
      version = current_version&.refreshable? ? refresh_version!(current_version) : cut_version!(requires_signature: true, created_by: signed_by)
      snapshot = version.content_snapshot
      # Scoped to this version. Unscoped, re-signing v2 would delete v1's
      # historical signature — the whole point of keeping versions.
      version.contract_signatures.role_organization.destroy_all
      version.contract_signatures.create!(
        contract: self,
        signer_role: "organization",
        signer_name: signer_name.presence || signed_by&.person&.name.presence || organization.name,
        signer_email: signed_by&.person&.email.presence || signed_by&.email_address,
        signed_by_user: signed_by,
        person: signed_by&.person,
        signed_at: Time.current,
        ip_address: request&.remote_ip,
        user_agent: request&.user_agent&.truncate(500),
        content_snapshot: snapshot,
        contract_template: contract_template,
        template_version: contract_template.version
      )
      update!(signing_state: :awaiting_send)
    end
    true
  end

  # Send (wizard "Send" step): the org has signed; now mint a fresh link and put it
  # out for the counterparty to sign. (Templated email + in-app message are enqueued
  # by the caller.)
  def send_for_signature!(expiry_days: nil)
    return false unless signing_awaiting_send?

    regenerate_signing_token!
    update!(signing_state: :out_for_signature, sent_for_signature_at: Time.current)
    # Record which token this version went out with, so a link the counterparty
    # kept can be recognised as superseded rather than dying as "invalid" — and
    # start its clock.
    days = (expiry_days.presence || organization.signature_expiry_days).to_i
    current_version&.update!(
      signing_token: signing_token,
      sent_for_signature_at: Time.current,
      signature_due_at: days.days.from_now.end_of_day,
      expired_at: nil,
      last_nudged_at: nil,
      nudge_count: 0
    )
    true
  end

  # Pull back a sent-but-unsigned request: the link dies. The org's signature and
  # locked document are kept, so it drops back to awaiting_send — re-send in one
  # click, or step back to change the data / template and re-sign first.
  def revoke_signing!
    return false unless signing_out_for_signature?

    update!(signing_state: :awaiting_send, signing_token: nil, sent_for_signature_at: nil)
    current_version&.update!(signing_token: nil, sent_for_signature_at: nil)
    true
  end

  # The deadline passed. The link dies and the request drops back to
  # ready-to-send — the org's signature, the locked document and any staged
  # amendment all survive, so re-sending is one click rather than a rebuild.
  def expire_signature_request!
    return false unless signing_out_for_signature?

    transaction do
      update!(signing_state: :awaiting_send, signing_token: nil, sent_for_signature_at: nil)
      current_version&.update!(expired_at: Time.current, signing_token: nil)
    end
    true
  end

  # Counterparty agrees on the public sign page → contract is executed. Both
  # parties' snapshots are the identical document the org sent. Executing an
  # esign contract also activates it (creates its operational records).
  def execute_by_signature!(signer_name:, signer_email:, request:, person: nil)
    return false unless signing_out_for_signature?

    transaction do
      version = current_version || cut_version!(requires_signature: true)
      snapshot = version.content_snapshot
      version.contract_signatures.role_contractor.destroy_all
      version.contract_signatures.create!(
        contract: self,
        signer_role: "contractor",
        signer_name: signer_name,
        signer_email: signer_email,
        person: person,
        signed_at: Time.current,
        ip_address: request.remote_ip,
        user_agent: request.user_agent&.truncate(500),
        content_snapshot: snapshot,
        contract_template: contract_template,
        template_version: contract_template&.version
      )
      version.update!(executed_at: Time.current)
      # This is the moment a staged amendment becomes real. Until now the live
      # contract described the deal actually in force; their signature is what
      # changes it.
      if version.staged_amendment.present?
        apply_amendment!(version.staged_amendment, force_overlap: version.force_overlap?)
        clear_amend_data
      end
      # Keep the token alive after execution so the signer can return to their
      # link for the signed PDF; only revoke nulls it.
      update!(signing_state: :executed, executed_at: executed_at || Time.current)
    end

    # Best-effort: a fully-signed contract becomes operational. If activation
    # can't complete (e.g. a booking conflict), it stays executed-but-draft for
    # the producer to resolve — the signature record is already safe.
    activate! if status_draft?
    # Generate the signed PDF off the request thread.
    GenerateContractPdfJob.perform_later(id)
    # Tell the org's chosen managers it was signed (in-app message only).
    ContractSignedNotificationJob.perform_later(id)
    true
  end

  # The merge values a contract template renders against.
  def signing_variables
    {
      contractor_name: contractor_name,
      organization_name: organization.name,
      production_name: production_name.presence || production&.name,
      contract_start_date: contract_start_date&.strftime("%B %-d, %Y"),
      contract_end_date: contract_end_date&.strftime("%B %-d, %Y"),
      current_date: Date.current.strftime("%B %-d, %Y")
    }
  end

  # The full signable document for the locked template: the wording (merge-filled)
  # followed by a system-generated "Deal Terms" schedule so the concrete
  # dates/money/services are always accurate regardless of what the author wrote.
  def render_signable_document
    render_document_for(contract_template)
  end

  # Same, for an arbitrary template — used to preview before locking one in.
  # Interpolate (don't use +) so the safe template HTML and the Deal Terms HTML are
  # joined as plain strings and neither half gets auto-escaped; mark the whole safe.
  #
  # If the template drops an inline token ({{license_schedule}} and/or {{services}})
  # in its wording, it's placing that deal content itself, so we fill the tokens
  # inline (raw HTML, not escaped) and skip the appended Deal Terms block — the
  # template's prose already carries the money terms. Templates without any inline
  # token keep the classic append. gsub is a no-op when a token is absent, so both
  # substitutions run unconditionally.
  def render_document_for(template)
    body = template ? template.render_content(signing_variables).to_s : ""
    uses_inline = body.include?(LICENSE_SCHEDULE_TOKEN) || body.include?(SERVICES_TOKEN)
    uses_appendix_token = body.include?(APPENDIXES_TOKEN)
    body = body.gsub(LICENSE_SCHEDULE_TOKEN, license_schedule_html)
    body = body.gsub(SERVICES_TOKEN, license_services_html)
    body = body.gsub(APPENDIXES_TOKEN, appendixes_html)
    main = uses_inline ? body : "#{body}#{deal_terms_html}"
    # Appended last unless the template placed them itself. "Above the signature
    # block" comes free: the signatures aren't part of the body — the signing
    # page and ContractPdf both render them after it.
    (uses_appendix_token ? main : "#{main}#{appendixes_html}").html_safe
  end

  # The appendixes as document HTML. Escaped titles; bodies are ActionText,
  # already sanitised.
  def appendixes_html
    sections = contract_appendixes.ordered.to_a
    return "" if sections.empty?

    parts = sections.map do |appendix|
      "<hr><h3>#{ERB::Util.html_escape(appendix.heading)}</h3>#{appendix.body_html}"
    end
    parts.join
  end

  # Draft data helpers
  def draft_bookings
    draft_data["bookings"] || []
  end

  def draft_booking_rules
    draft_data["booking_rules"] || {}
  end

  def draft_payments
    draft_data["payments"] || []
  end

  def draft_payment_structure
    draft_data["payment_structure"] || "flat_fee"
  end

  def draft_payment_config
    draft_data["payment_config"] || {}
  end

  def draft_ticketing
    draft_data["ticketing"] || {}
  end

  # Discount codes on a ticketing hash, as an array. Ticketing used to hold one
  # `discount`; it now holds a `discounts` list. Normalizes either shape so
  # readers don't have to care which a given contract was saved with.
  def self.ticketing_discounts(ticketing)
    ticketing ||= {}
    list = ticketing["discounts"]
    return list if list.is_a?(Array) && list.any?

    single = ticketing["discount"]
    single.is_a?(Hash) && single["code"].present? ? [ single ] : []
  end

  def draft_tech
    draft_data["tech"] || {}
  end

  # Per-contract service line items: [{ "name", "quantity", "unit_price", "direction" }].
  def draft_services
    draft_data["services"] || []
  end

  # Normalize the wizard/amend services form rows into draft_services line
  # hashes. One parser for both paths, so amendment can't drift (it used to
  # silently drop the settlement choice). Per-event rows carry their selected
  # dates + hours; everything else keeps the flat quantity.
  def self.normalize_service_rows(rows)
    raw = rows.respond_to?(:values) ? rows.values : Array(rows)
    raw.filter_map do |row|
      row = row.to_unsafe_h if row.respond_to?(:to_unsafe_h)
      row = row.stringify_keys
      name = row["name"].to_s.strip
      next if name.blank? || row["include"] != "1"

      line = {
        "name" => name,
        "unit" => row["unit"].presence || "flat",
        "unit_price" => row["unit_price"].to_f,
        "direction" => row["direction"].presence || "incoming",
        "settlement" => ContractPayment::SETTLEMENT_METHODS.include?(row["settlement"].to_s) ? row["settlement"].to_s : "direct"
      }

      events_raw = row["events"]
      events_raw = events_raw.values if events_raw.respond_to?(:values) && !events_raw.is_a?(Array)
      events = Array(events_raw).filter_map do |ev|
        ev = ev.to_unsafe_h if ev.respond_to?(:to_unsafe_h)
        ev = ev.stringify_keys
        next unless ev["include"] == "1" && ev["starts_at"].present?

        hours = ev["hours"].to_f
        hours = 1 if hours <= 0
        { "starts_at" => ev["starts_at"].to_s, "hours" => hours }
      end

      if row["per_event"] == "1" && events.any?
        line["per_event"] = true
        line["events"] = events
        line["quantity"] = events.sum { |e| e["hours"] }.round(2)
      else
        quantity = row["quantity"].to_f
        quantity = 1 if quantity <= 0
        line["quantity"] = quantity
      end
      line
    end
  end

  # Turn a set of service line items into billable ContractPayments. A flat
  # line bills once, due at contract end; a per-event line bills one payment
  # per selected date — due on the event's date, tied to the show when one
  # exists (billing runs after show creation at activation). Used at
  # activation and re-billing on amendment.
  def bill_services!(services)
    shows_by_date = service_shows_by_date
    # Charges that have already been settled — paid, or netted out of a payout
    # run. Re-billing on an amendment must not raise them a second time.
    already_billed = contract_payments.select { |p| p.status_paid? || p.in_payout_run? }
                                      .map { |p| [ p.description, p.due_date ] }.to_set

    Array(services).each do |service|
      direction = service["direction"].presence || "incoming"
      # "Taken out of their payout" only makes sense for money they owe us;
      # outgoing services are always paid directly.
      settlement = direction == "incoming" ? (service["settlement"].presence || "direct") : "direct"

      if service["per_event"] && service["events"].present?
        Array(service["events"]).each do |event|
          starts_at = (Time.zone.parse(event["starts_at"].to_s) rescue nil)
          next unless starts_at

          amount = if service["unit"] == "hourly"
            (event["hours"].to_f * service["unit_price"].to_f).round(2)
          else
            service["unit_price"].to_f.round(2)
          end
          next unless amount.positive?

          description = "#{service['name']} — #{starts_at.strftime('%b %-d, %Y')}"
          next if already_billed.include?([ description, starts_at.to_date ])

          contract_payments.create!(
            description: description,
            amount: amount,
            direction: direction,
            settlement_method: settlement,
            due_date: starts_at.to_date,
            show_id: shows_by_date[starts_at.to_date]&.first&.id
          )
        end
      else
        amount = (service["quantity"].to_f * service["unit_price"].to_f).round(2)
        next unless amount.positive?

        due = contract_end_date || Date.current
        next if already_billed.include?([ service["name"], due ])

        contract_payments.create!(
          description: service["name"],
          amount: amount,
          direction: direction,
          settlement_method: settlement,
          due_date: due
        )
      end
    end
  end

  # This contract's shows keyed by date, for tying a per-event service payment
  # to its show. Empty (harmlessly) before activation creates them.
  def service_shows_by_date
    return {} unless production

    production.shows.group_by { |s| s.date_and_time.to_date }
  end

  # Re-bill services when a contract is amended: drop the still-pending payments
  # for the current set, record the new set, and bill it. Paid service payments
  # are never touched, so nothing that's already been settled is disturbed.
  def reconcile_service_payments!(new_services)
    old_names = draft_services.map { |s| s["name"] }.compact
    if old_names.any?
      # Per-event lines billed as "Name — Oct 16, 2026", so match the bare
      # name and its dated variants.
      conditions = old_names.map { "(description = ? OR description LIKE ?)" }.join(" OR ")
      binds = old_names.flat_map { |n| [ n, "#{n} — %" ] }
      # Pending only, and never one already committed to a payout run — that
      # money is spoken for, and destroying it would strand the run's contribution.
      contract_payments.status_pending.where(conditions, *binds)
                       .reject(&:in_payout_run?).each(&:destroy!)
    end
    update_draft_step(:services, Array(new_services))
    bill_services!(draft_services)
  end

  # Amend: apply a freshly-edited payment list (the deal-derived payments plus any
  # by-hand extras, produced by the same Financials editor as create) to an active
  # contract.
  #
  # This reconciles by DIFF. It used to destroy every pending payment and rebuild
  # from the staged list, which had three bad consequences: it invented a second
  # payment for any date that had already been settled (a show that had happened,
  # sold tickets and been paid still got a fresh "due" row beside the paid one);
  # it could destroy a payment already committed to a payout run; and it threw
  # away every choice a manager had made by hand — settling out of the payout, a
  # hand-set amount, an already-issued pay link.
  #
  # A payment's identity is its SLOT: which way the money goes and when it's due.
  # Two payments in the same slot are the same payment as far as an amendment is
  # concerned, however the deal has re-worded or re-priced them. Slots that
  # already carry settled money are closed — nothing is ever created for them.
  def reconcile_amended_payments!(staged_payments)
    staged = Array(staged_payments).filter_map { |row| staged_payment_attributes(row) }
    # Service charges are billed by reconcile_service_payments!, never staged
    # by the Financials editor — so to this reconcile they all look like rows
    # the deal no longer produces. Leave them out entirely, or an amendment
    # that adds a service destroys its own charges moments after billing them.
    existing = contract_payments.to_a.reject { |p| service_charge?(p) }

    settled_slots = existing.select { |p| p.status_paid? || p.in_payout_run? }
                            .map { |p| payment_slot(p) }.to_set
    # Only pending rows that aren't committed to a run are ours to change.
    unclaimed = existing.select { |p| p.status_pending? && !p.in_payout_run? }
    kept = []

    # Two passes: an exact match first, then the same slot with different
    # wording — that's a re-priced fee, not a new payment.
    [ ->(attrs, p) { payment_slot(p) == attrs[:slot] && p.description == attrs[:description] },
      ->(attrs, p) { payment_slot(p) == attrs[:slot] } ].each do |matches|
      staged.each do |attrs|
        next if attrs[:claimed]

        match = unclaimed.detect { |p| matches.call(attrs, p) }
        next unless match

        unclaimed.delete(match)
        attrs[:claimed] = true
        # Only the deal's own fields are rewritten. settlement_method,
        # payment_token and show_id belong to the manager, and survive.
        match.update!(attrs[:values])
        kept << match
      end
    end

    staged.each do |attrs|
      next if attrs[:claimed]
      # The guard that stops an amendment inventing money for a closed date.
      next if settled_slots.include?(attrs[:slot])

      kept << contract_payments.create!(attrs[:values])
    end

    # Pending, uncommitted rows the amended deal no longer produces.
    unclaimed.each(&:destroy!)

    link_payments_to_shows(kept, contract_shows.order(:date_and_time).to_a)
  end

  # The payment schedule with deduction-settled charges folded into the
  # settlement that nets them out.
  #
  # A weekly ticket-revenue deal with a booth tech billed per show produced six
  # separate "$50, they pay us" rows beside two weekly settlements — six things
  # that look like invoices to chase, when they're actually one deduction
  # against each week's payment. Each charge attaches to the first settlement
  # due on or after it; a charge with no settlement to hide behind stays a row
  # of its own.
  #
  # Returns [{ payment:, deductions: [ContractPayment], deduction_total: Float }]
  def payment_schedule_groups(payments = nil)
    rows = payments || contract_payments.by_due_date.to_a
    # A charge settled by payout deduction never has money of its own — no
    # standalone "Paid" row, ever. It stays folded into the settlement it
    # netted (or will net) against.
    deductible, rest = rows.partition do |p|
      p.direction_incoming? &&
        ((p.status_pending? && p.deduct_from_payout?) ||
         (p.status_paid? && p.payment_method == "payout_deduction"))
    end
    settlements = rest.select { |p| p.direction_outgoing? }.sort_by(&:due_date)
    pending_settlements = settlements.select(&:status_pending?)

    attached = Hash.new { |h, k| h[k] = [] }
    orphans = []
    deductible.each do |charge|
      # A pending charge can only net against a settlement that hasn't happened
      # yet; an already-deducted one belongs to the settlement it rode out on.
      # Both match by date: a fee deducts at its own event's settlement.
      pool = charge.status_paid? ? settlements : pending_settlements
      host = pool.detect { |s| s.due_date >= charge.due_date } || pool.last
      host ? attached[host.id] << charge : orphans << charge
    end

    (rest + orphans).sort_by(&:due_date).map do |payment|
      charges = attached[payment.id].sort_by(&:due_date)
      { payment: payment, deductions: charges, deduction_total: charges.sum { |c| c.amount.to_f } }
    end
  end

  # --- Versions ---------------------------------------------------------------
  # A version is the document at a moment. It is history, not a restore point:
  # shows, rentals, payments and payouts are live shared records and are never
  # rolled back by looking at an old version.

  def current_version
    contract_versions.ordered.last
  end

  def latest_executed_version
    contract_versions.where.not(executed_at: nil).ordered.last
  end

  def fully_executed?
    current_version&.executed_at.present?
  end

  # An amendment has been applied and is waiting on a fresh signature.
  def awaiting_resignature?
    v = current_version
    v.present? && v.version_number > 1 && v.requires_signature? && v.executed_at.nil?
  end

  # Capture the pre-amendment state as v1 for a contract that was never signed
  # through CocoScout — otherwise its first amendment would be labelled "v1",
  # which reads as a lie about what came before.
  def ensure_baseline_version!(created_by: nil)
    return current_version if contract_versions.any?

    cut_version!(requires_signature: false, created_by: created_by,
                 change_summary: "Baseline — the contract as it stood before this amendment")
  end

  def cut_version!(requires_signature:, created_by: nil, change_summary: nil, amendment_data: {})
    with_lock do
      next_number = (contract_versions.maximum(:version_number) || 0) + 1
      contract_versions.create!(
        version_number: next_number,
        content_snapshot: render_signable_document.to_s,
        deal_snapshot: version_deal_snapshot,
        contract_template: contract_template,
        template_version: contract_template&.version,
        requires_signature: requires_signature,
        change_summary: change_summary,
        # A correction nobody has to sign takes effect the moment it's applied.
        executed_at: requires_signature ? nil : Time.current,
        created_by: created_by
      )
    end
  end

  # Re-render a version that hasn't been signed or sent yet, rather than cutting
  # another one — repeated edits before sending shouldn't inflate the number.
  def refresh_version!(version)
    version.update!(content_snapshot: render_signable_document.to_s,
                    deal_snapshot: version_deal_snapshot,
                    contract_template: contract_template,
                    template_version: contract_template&.version)
    version
  end

  def version_deal_snapshot
    {
      "draft_data" => draft_data.except("amend"),
      "appendixes" => contract_appendixes.ordered.map { |a| { "title" => a.title, "position" => a.position, "body_html" => a.body_html } }
    }
  end

  # --- Applying an amendment ---------------------------------------------------
  # Extracted from the controller so it can run twice: once inside a rolled-back
  # transaction to render the document the counterparty is being asked to sign,
  # and once for real when they sign it.
  #
  # Every side effect on Show and SpaceRental is after_commit, so the preview
  # pass leaves nothing behind — no calendar syncs, no sign-up form instances,
  # no contract-payment syncs.
  def apply_amendment!(amend = amend_data, force_overlap: false)
    new_bookings = amend["new_bookings"] || []
    removed_rental_ids = amend["removed_rental_ids"] || []
    staged_name = amend["production_name"].to_s.strip

    # The deal config first, so payments derive the right direction.
    update_draft_step(:payment_structure, amend["payment_structure"]) if amend.key?("payment_structure")
    update_draft_step(:payment_config, amend["payment_config"]) if amend.key?("payment_config")
    update_draft_step(:ticketing, amend["ticketing"]) if amend.key?("ticketing")
    reconcile_service_payments!(amend["services"]) if amend.key?("services")

    if staged_name.present? && staged_name != production_name.to_s
      update!(production_name: staged_name)
      production&.update!(name: staged_name)
    end

    if removed_rental_ids.any?
      Show.where(space_rental_id: removed_rental_ids).destroy_all
      space_rentals.where(id: removed_rental_ids).destroy_all
    end

    event_type = (draft_data["production"] || {})["event_type"].presence || "show"
    new_bookings.each { |booking| create_amended_booking!(booking, event_type, force_overlap) }

    # After shows exist, so per-event payments can link to them.
    reconcile_amended_payments!(amend["payments"]) if amend.key?("payments")

    rentals = space_rentals.reload
    if rentals.any?
      update!(
        contract_start_date: [ contract_start_date, rentals.minimum(:starts_at)&.to_date ].compact.min,
        contract_end_date: [ contract_end_date, rentals.maximum(:ends_at)&.to_date ].compact.max
      )
    end
    true
  end

  # What the amended contract WOULD look like, without leaving a trace. Applied
  # inside a savepoint and rolled back, so the document we send for signature
  # describes the proposed deal while the live records still describe the
  # current one.
  def preview_amendment(amend = amend_data, force_overlap: false)
    document = nil
    snapshot = nil
    transaction(requires_new: true) do
      apply_amendment!(amend, force_overlap: force_overlap)
      document = render_signable_document.to_s
      snapshot = version_deal_snapshot
      raise ActiveRecord::Rollback
    end
    reload
    [ document, snapshot ]
  end

  # An amendment is staged and waiting on a signature. Nothing about it has
  # touched the live contract yet.
  def amendment_pending?
    v = current_version
    v.present? && v.requires_signature? && v.executed_at.nil? && v.staged_amendment.present?
  end

  def create_amended_booking!(booking, event_type, force_overlap)
    starts_at = Time.zone.parse(booking["starts_at"])
    ends_at = starts_at + (booking["duration"] || 2).to_f.hours

    rental = space_rentals.create!(
      location_id: booking["location_id"],
      location_space_id: booking["space_id"].presence,
      starts_at: starts_at,
      ends_at: ends_at,
      event_starts_at: booking["event_starts_at"].present? ? Time.zone.parse(booking["event_starts_at"]) : nil,
      event_ends_at: booking["event_ends_at"].present? ? Time.zone.parse(booking["event_ends_at"]) : nil,
      notes: booking["notes"],
      confirmed: true,
      allow_overlap: force_overlap
    )

    return unless production

    production.shows.create!(
      date_and_time: rental.effective_event_starts_at,
      duration_minutes: rental.effective_duration_minutes,
      location: rental.location,
      location_space: rental.location_space,
      space_rental: rental,
      event_type: event_type
    )
  end

  # Re-derive the contract's span from the dates it actually holds. Called after
  # dates are added, removed or moved.
  def refresh_dates_from_rentals!
    starts = space_rentals.minimum(:starts_at)
    ends = space_rentals.maximum(:ends_at)
    return if starts.nil? || ends.nil?

    update!(contract_start_date: starts.to_date, contract_end_date: ends.to_date)
  end

  # Which way the money goes and when it's due — see reconcile_amended_payments!.
  def payment_slot(payment)
    [ payment.direction, payment.due_date ]
  end

  # A payment billed from the services list: named for the service, bare or
  # with its event date ("Booth Tech" / "Booth Tech — Aug 9, 2026") — the same
  # shapes bill_services! writes and reconcile_service_payments! matches.
  def service_charge?(payment)
    draft_services.any? do |s|
      name = s["name"].to_s
      name.present? && (payment.description == name || payment.description.to_s.start_with?("#{name} — "))
    end
  end

  def staged_payment_attributes(row)
    tbd = row["amount_tbd"] == true || row["amount_tbd"] == "true"
    amount = row["amount"].to_f
    return nil if amount <= 0 && !tbd

    direction = row["direction"].presence || settlement_direction
    due_date = row["due_date"].present? ? Date.parse(row["due_date"].to_s) : (contract_end_date || Date.current)

    {
      slot: [ direction, due_date ],
      description: row["description"],
      claimed: false,
      values: {
        description: row["description"],
        amount: amount,
        amount_tbd: tbd,
        direction: direction,
        due_date: due_date,
        notes: row["notes"]
      }
    }
  end

  def update_draft_step(step_name, data)
    self.draft_data = draft_data.merge(step_name.to_s => data)
    save!
  end

  # Amend data helpers (for amending existing active contracts)
  def amend_data
    draft_data["amend"] || {}
  end

  def update_amend_data(data)
    self.draft_data = draft_data.merge("amend" => data)
    save!
  end

  def clear_amend_data
    new_data = draft_data.except("amend")
    self.draft_data = new_data
    save!
  end

  # Validation for activation
  def valid_for_activation?
    errors.clear

    errors.add(:base, "Must have at least one booking") if draft_bookings.empty? && space_rentals.empty?
    errors.add(:base, "Contract start date is required") if contract_start_date.blank?
    errors.add(:base, "Contract end date is required") if contract_end_date.blank?

    errors.empty?
  end

  # How this contract's money maps into the org's Money totals, so contract money
  # isn't siloed — it flows into revenue and payout totals like everything else.
  #
  # Gross model: when WE sell the tickets, the full ticket revenue is money coming
  # in and the contractor's share is a payout going out (profit = our cut). When
  # THEY sell, we only ever see our cut (money in, nothing out). Flat deals fall
  # back to the contract's own payments by direction.
  #
  # Returns { money_in:, money_out: } in dollars.
  def money_summary
    if revenue_share?
      summary = revenue_share_summary
      return { money_in: 0.0, money_out: 0.0 } unless summary

      if who_sells_tickets == "org"
        { money_in: summary[:confirmed_revenue], money_out: summary[:contractor_share] }
      else
        { money_in: summary[:our_share], money_out: 0.0 }
      end
    elsif ticket_revenue_minus_fee?
      summary = flat_fee_revenue_summary
      return { money_in: 0.0, money_out: 0.0 } unless summary

      # We sell, keep a fee, hand back the rest: full revenue in, their remainder out.
      { money_in: summary[:confirmed_revenue], money_out: summary[:contractor_share] }
    else
      # Flat deals: the contract's own payments are the money, by direction.
      {
        money_in: contract_payments.where(direction: "incoming").sum(:amount).to_f,
        money_out: contract_payments.where(direction: "outgoing").sum(:amount).to_f
      }
    end
  end

  # What this contract has made us vs cost us, for display. A revenue-share
  # deal where WE sell isn't "-$155" — it made us the ticket revenue on its
  # shows and cost us the contractor's share; a rental made us the rent. Wraps
  # money_summary (which already knows this per contract type) and flags shows
  # whose financials aren't in yet, so a low "made" reads as "so far".
  #
  # Returns { made:, cost:, net:, pending_shows: } in dollars.
  def money_display
    summary = money_summary
    pending =
      if revenue_share?
        revenue_share_summary&.dig(:pending_count).to_i
      elsif ticket_revenue_minus_fee?
        flat_fee_revenue_summary&.dig(:pending_count).to_i
      else
        0
      end

    made = summary[:money_in].to_f
    cost = summary[:money_out].to_f
    { made: made, cost: cost, net: made - cost, pending_shows: pending }
  end

  # Financial summary
  def total_incoming
    contract_payments.where(direction: "incoming", status: "paid").sum(:amount)
  end

  def total_outgoing
    contract_payments.where(direction: "outgoing").sum(:amount)
  end

  def net_amount
    total_incoming - total_outgoing
  end

  def pending_payments
    contract_payments.where(status: "pending")
  end

  def overdue_payments
    contract_payments.where(status: "pending").where("due_date < ?", Date.current)
  end

  # Shows covered by THIS contract. When the production is shared by several
  # contracts, each contract only "owns" the shows booked through its own space
  # rentals. When the production belongs to only this contract, all of its shows
  # are this contract's (covers any show created without an explicit rental).
  def contract_shows
    rental_show_ids = Show.where(space_rental_id: space_rentals.select(:id)).select(:id)

    if production_id.present? && production && production.contracts.count <= 1
      Show.where(production_id: production_id).or(Show.where(id: rental_show_ids))
    else
      Show.where(id: rental_show_ids)
    end
  end

  # Revenue share financial helpers — calculates from show-level financials
  def contractor_share_percentage
    return nil unless revenue_share?
    100.0 - revenue_share_percentage
  end

  # Returns { confirmed_revenue: X, tbd_count: N, contractor_share: Y }
  def revenue_share_summary
    return nil unless revenue_share?

    all_shows = contract_shows.where(canceled: false).includes(:show_financials).to_a
    confirmed_shows = all_shows.select { |s| s.show_financials&.has_data? }
    pending_shows = all_shows - confirmed_shows

    confirmed_revenue = confirmed_shows.sum { |s| s.show_financials.total_revenue }
    our_share_amount = (confirmed_revenue * revenue_share_percentage / 100.0).round(2)
    contractor_share_amount = (confirmed_revenue * contractor_share_percentage / 100.0).round(2)

    {
      confirmed_revenue: confirmed_revenue,
      confirmed_count: confirmed_shows.count,
      pending_count: pending_shows.count,
      our_share: our_share_amount,
      contractor_share: contractor_share_amount,
      total_shows: all_shows.count
    }
  end

  # Returns financial summary for ticket_revenue_minus_fee contracts
  def flat_fee_revenue_summary
    return nil unless ticket_revenue_minus_fee?

    all_shows = contract_shows.where(canceled: false).includes(:show_financials).to_a
    confirmed_shows = all_shows.select { |s| s.show_financials&.has_data? }
    pending_shows = all_shows - confirmed_shows

    confirmed_revenue = confirmed_shows.sum { |s| s.show_financials.total_revenue }
    # The fee is charged per show, so what we've actually earned so far tracks
    # the shows whose numbers are in — it doesn't sit at the full contract fee
    # while half the run is still unreported.
    fee = flat_fee_for_shows(confirmed_shows.count)
    contractor_amount = [ confirmed_revenue - fee, 0 ].max

    {
      confirmed_revenue: confirmed_revenue,
      confirmed_count: confirmed_shows.count,
      pending_count: pending_shows.count,
      our_share: fee,
      contractor_share: contractor_amount,
      total_shows: all_shows.count
    }
  end

  # The fee due across a given number of shows. A per-show deal is simply the
  # price times the count; a whole-contract total is allocated proportionally,
  # and lands on exactly flat_fee_amount once every show is counted so a run
  # never over- or under-charges by a rounding cent.
  def flat_fee_for_shows(count)
    count = count.to_i
    return 0.0 unless count.positive?
    return (flat_fee_per_show * count).round(2) if flat_fee_basis == "per_show"

    total = contract_shows.where(canceled: false).count
    return 0.0 if total.zero?
    return flat_fee_amount.round(2) if count >= total

    (flat_fee_amount * count / total).round(2)
  end

  # The payments that carry this contract's core settlement, oldest first.
  # Revenue splits can run either direction and are named for the split;
  # minus-fee settlements are always us paying them and are named for the fee.
  def settlement_payments
    if ticket_revenue_minus_fee?
      contract_payments.where(direction: "outgoing")
                       .where("amount_tbd = ? OR description LIKE ?", true, "Ticket revenue%")
                       .order(:due_date)
    else
      contract_payments.where(amount_tbd: true)
                       .or(contract_payments.where("description LIKE ?", "%Revenue Share%"))
                       .order(:due_date)
    end
  end

  # Find the matching ContractPayment for a given show based on settlement frequency
  def find_payment_for_show(show)
    return nil unless revenue_share? || ticket_revenue_minus_fee?

    # First, try direct show_id link
    direct = contract_payments.find_by(show_id: show.id)
    return direct if direct

    # A deal that settles once has a single payment covering every show, so
    # there's no per-show payment to find.
    return nil unless settles_periodically?

    settlement = settlement_cadence
    # Direction-agnostic: contracts can be incoming (contractor pays us) or outgoing (we pay contractor)
    revenue_payments = settlement_payments

    payment = case settlement
    when "per_event", "next_day", "same_day"
      # A per-event payment is due on its event's date, so match on that.
      # Positional pairing (kept as a fallback for deals whose due dates sit
      # off the event dates) drifts as soon as any settled payment drops out
      # of settlement_payments, linking a show to its neighbor's payment.
      revenue_payments.detect { |p| p.due_date == show.date_and_time.to_date } ||
        begin
          all_shows = contract_shows.order(:date_and_time).to_a
          show_index = all_shows.index { |s| s.id == show.id }
          show_index ? revenue_payments.to_a[show_index] : nil
        end
    when "weekly"
      show_week_start = show.date_and_time.to_date.beginning_of_week
      revenue_payments.find { |p| p.due_date.beginning_of_week == show_week_start }
    else # monthly
      show_month = show.date_and_time.to_date.beginning_of_month
      revenue_payments.find { |p| p.due_date.beginning_of_month == show_month }
    end

    # Link the show_id for future lookups if we found a match — but never to a
    # show that's been destroyed (the after_destroy sync lands here), which
    # would violate the contract_payments→shows FK.
    if payment && payment.show_id.nil? && !show.destroyed?
      payment.update_column(:show_id, show.id)
    end

    payment
  end

  # Get all shows that map to a given ContractPayment
  def shows_for_payment(payment)
    # If payment has a direct show link, use it
    if payment.show_id.present?
      show = Show.includes(:show_financials).find_by(id: payment.show_id)
      return show ? [ show ] : []
    end

    settlement = settlement_cadence
    all_shows = contract_shows.includes(:show_financials).order(:date_and_time).to_a

    # One settlement at the end covers the whole run.
    return all_shows unless settles_periodically?

    case settlement
    when "per_event", "next_day", "same_day"
      # A per-event payment is due on its event's date, so match on that;
      # positional pairing stays only as a fallback (see find_payment_for_show).
      show = all_shows.find { |s| s.date_and_time.to_date == payment.due_date }
      if show.nil?
        revenue_payments = settlement_payments.to_a
        payment_index = revenue_payments.index { |p| p.id == payment.id }
        show = payment_index ? all_shows[payment_index] : nil
      end
      if show
        # Link for future lookups
        payment.update_column(:show_id, show.id) if payment.show_id.nil?
        [ show ]
      else
        []
      end
    when "weekly"
      week_start = payment.due_date.beginning_of_week
      all_shows.select { |s| s.date_and_time.to_date.beginning_of_week == week_start }
    else # monthly
      month_start = payment.due_date.beginning_of_month
      all_shows.select { |s| s.date_and_time.to_date.beginning_of_month == month_start }
    end
  end

  # Display helpers
  def display_name
    production_name.presence || contractor_name
  end

  def date_range
    return nil if contract_start_date.blank? || contract_end_date.blank?

    if contract_start_date == contract_end_date
      contract_start_date.strftime("%B %d, %Y")
    else
      "#{contract_start_date.strftime('%B %d')} - #{contract_end_date.strftime('%B %d, %Y')}"
    end
  end

  # Revenue projection helpers. These read the v2 settlement_basis, which falls
  # back to the legacy payment_structure — so old and migrated contracts both work.
  def revenue_share?
    settlement_basis == "revenue_share"
  end

  def ticket_revenue_minus_fee?
    settlement_basis == "revenue_minus_fee"
  end

  def flat_fee_amount
    draft_payment_config["flat_fee_amount"].to_f
  end

  # --- Ticket-revenue-minus-fee: what the fee means and how often we settle ---

  # Whether flat_fee_amount is a per-show price or one whole-contract total.
  # "contract" is the default so contracts written before this existed keep
  # their meaning.
  def flat_fee_basis
    # New contracts default to per_show in the wizard UI and save it
    # explicitly. The fallback here stays "contract" on purpose: it's the
    # legacy interpretation for deals saved before the basis existed, and
    # flipping it would silently re-price their fee as per-show.
    draft_payment_config["flat_fee_basis"].presence || "contract"
  end

  # How often we hand back the remainder: "once" (one settlement at the end),
  # "per_event", "weekly" or "monthly". Defaults to "once" for the same reason.
  def flat_fee_settlement
    draft_payment_config["flat_fee_settlement"].presence || "once"
  end

  # The fee attributable to a single show. Every settlement deducts this times
  # the number of shows it covers, which is what makes a per-show fee and a
  # whole-contract total the same arithmetic: on a contract-total deal we just
  # spread the total across the shows first, so a run of N shows still deducts
  # exactly flat_fee_amount in the end.
  #
  # Canceled shows fall out of the denominator, so a contract-total fee stays
  # whole when a date drops while a per-show fee simply isn't charged for it.
  def flat_fee_per_show
    return flat_fee_amount if flat_fee_basis == "per_show"

    count = contract_shows.where(canceled: false).count
    return 0.0 if count.zero?

    (flat_fee_amount / count).round(2)
  end

  # How often the core settlement pays out, whichever basis this contract uses.
  # Revenue splits and minus-fee deals ask the same question in two different
  # config keys, so payment lookup can stay written once.
  def settlement_cadence
    if ticket_revenue_minus_fee?
      flat_fee_settlement
    else
      draft_payment_config["revenue_settlement"] || "monthly"
    end
  end

  # True when the deal settles show-by-show or period-by-period rather than in
  # a single payment at the end.
  def settles_periodically?
    settlement_cadence != "once"
  end

  def settlement_cadence_label
    case settlement_cadence
    when "per_event", "same_day" then "After each show"
    when "next_day"              then "The day after each show"
    when "weekly"                then "Weekly"
    when "monthly"               then "Monthly"
    else                              "Once, at the end of the run"
    end
  end

  def revenue_share_percentage
    return nil unless revenue_share?
    draft_payment_config["revenue_our_share"].to_f
  end

  # --- Payment model v2: who sells tickets + settlement basis ---
  # Every contract's money flow is two orthogonal choices. Stored in
  # draft_payment_config; these getters fall back to the legacy payment_structure
  # so existing contracts keep working until the backfill task migrates them.

  # Who sells the tickets: "org" (we do), "contractor" (they do), or nil (this
  # deal doesn't involve tickets at all).
  #
  # This is a separate question from how the deal settles. We might sell the
  # tickets and keep every penny while they simply pay us a flat rental — so
  # this says who holds the ticket money and whether we need ticket tiers, not
  # who owes whom.
  def who_sells_tickets
    draft_payment_config["who_sells_tickets"].presence || legacy_who_sells_tickets
  end

  # True when we're the ones selling, so this contract needs ticketing set up.
  def org_sells_tickets?
    who_sells_tickets == "org"
  end

  # Case 2: the contractor sells their own tickets on a revenue split, so they
  # self-report the sales and then owe us our cut. This is the only case where a
  # contractor enters ticket numbers themselves.
  def contractor_reports_sales?
    who_sells_tickets == "contractor" && revenue_share?
  end

  # True only when there's actually something left to report: a contractor-sells
  # revenue-share contract with at least one show whose sales aren't confirmed
  # yet. Once every show's sales are in (data_confirmed), we stop nagging — even
  # if the org, not the contractor, entered them. Drives the "report your sales"
  # prompt so it never appears on already-settled contracts.
  def pending_sales_report?
    return false unless contractor_reports_sales?

    contract_shows.any? do |show|
      financials = show.show_financials
      financials.nil? || !financials.data_confirmed?
    end
  end

  # "revenue_share" | "revenue_minus_fee" | "flat".
  def settlement_basis
    draft_payment_config["settlement_basis"].presence || legacy_settlement_basis
  end

  # Which way money flows for the core settlement.
  #
  # For a ticket split, it follows whoever holds the ticket money: we sell, so we
  # pay them their share (outgoing); they sell, so they pay us ours (incoming).
  # Ticket-revenue-minus-fee is always us selling and handing back the remainder.
  # A flat fee is independent of ticketing — a rental where we still sell the
  # tickets is money coming IN — so it uses its own stated direction.
  def settlement_direction
    case settlement_basis
    when "revenue_share"
      who_sells_tickets == "org" ? "outgoing" : "incoming"
    when "revenue_minus_fee"
      "outgoing"
    else
      dir = draft_payment_config["flat_fee_direction"]
      dir.in?(%w[incoming outgoing]) ? dir : "incoming"
    end
  end

  # --- How they're allowed to pay us -----------------------------------------
  # Online is always available (that's the Stripe pay link). The rest are ways
  # money can reach us outside CocoScout, and each has to be allowed explicitly
  # before we'll let anyone record one by hand.

  # Ways a contractor may pay us, defaulting to the org's policy.
  def accepted_payment_methods
    configured = draft_payment_config["accepted_payment_methods"]
    configured = organization&.default_contract_payment_methods if configured.blank?
    ([ "online" ] + (Array(configured) & OFFLINE_PAYMENT_METHODS)).uniq
  end

  # The allowed offline methods, in the order they're offered.
  def offline_payment_methods
    accepted_payment_methods - [ "online" ]
  end

  # True when this contract allows money to reach us outside Stripe, so a
  # manager may record a payment by hand.
  def offline_payments_allowed?
    offline_payment_methods.any?
  end

  # A plain-English summary of the deal for the review step — every term that
  # was set on Financials, so nobody has to click back to check. Returns an
  # array of { label:, value: } with money pre-formatted.
  def deal_summary
    cfg = draft_payment_config
    lines = []

    who_sells_label = case who_sells_tickets
    when "org" then "We do"
    when "contractor" then "They do — they report their sales"
    else "No tickets on this deal"
    end
    lines << { label: "Who sells the tickets", value: who_sells_label }

    case draft_payment_structure
    when "flat_fee"
      deal_summary_flat_fee(cfg, lines)
    when "per_event"
      deal_summary_per_event(cfg, lines)
    when "revenue_share"
      deal_summary_revenue_share(cfg, lines)
    end

    methods = accepted_payment_methods.map do |m|
      m == "online" ? "online" : OFFLINE_PAYMENT_METHOD_LABELS[m]&.downcase
    end.compact
    lines << { label: "They may pay us by", value: methods.to_sentence }

    lines
  end

  # Flat-fee entries — supports one whole-contract fee, a uniform per-event fee,
  # or a per-event fee with a different price per event. Returns an array of
  # { "amount", "due_date", "show_index" } (show_index nil = whole contract).
  def flat_fee_entries
    entries = draft_payment_config["flat_fee_entries"]
    return entries if entries.is_a?(Array) && entries.any?

    [ { "amount" => flat_fee_amount, "due_date" => nil, "show_index" => nil } ]
  end

  def legacy_settlement_basis
    case draft_payment_structure
    when "revenue_share" then "revenue_share"
    when "flat_fee"
      draft_payment_config["flat_fee_direction"] == "ticket_revenue_minus_fee" ? "revenue_minus_fee" : "flat"
    else "flat" # per_event / custom → a list of flat amounts
    end
  end

  def legacy_who_sells_tickets
    case legacy_settlement_basis
    when "revenue_minus_fee" then "org"     # we sell, keep a fee, pay them the rest
    when "revenue_share" then "contractor"  # legacy rev-share was generated as incoming (they pay us)
    end
  end

  def has_revenue_projection?
    revenue_projections.present? && revenue_projections["scenarios"].present?
  end

  def revenue_projection_scenario(name = "default")
    return nil unless has_revenue_projection?
    revenue_projections["scenarios"]&.find { |s| s["name"] == name }
  end

  def set_revenue_projection(ticket_price_low:, ticket_price_high:, tickets_sold_low:, tickets_sold_high:, notes: nil, scenario_name: "default")
    scenarios = (revenue_projections["scenarios"] || []).reject { |s| s["name"] == scenario_name }
    scenarios << {
      "name" => scenario_name,
      "ticket_price_low" => ticket_price_low.to_f,
      "ticket_price_high" => ticket_price_high.to_f,
      "tickets_sold_low" => tickets_sold_low.to_i,
      "tickets_sold_high" => tickets_sold_high.to_i,
      "notes" => notes,
      "updated_at" => Time.current.iso8601
    }
    update!(revenue_projections: revenue_projections.merge("scenarios" => scenarios))
  end

  def projected_gross_revenue_range(scenario_name = "default")
    scenario = revenue_projection_scenario(scenario_name)
    return nil unless scenario

    low = scenario["ticket_price_low"].to_f * scenario["tickets_sold_low"].to_i
    high = scenario["ticket_price_high"].to_f * scenario["tickets_sold_high"].to_i
    { low: low, high: high }
  end

  def projected_our_revenue_range(scenario_name = "default")
    gross = projected_gross_revenue_range(scenario_name)
    return nil unless gross && revenue_share_percentage

    share = revenue_share_percentage / 100.0
    { low: (gross[:low] * share).round(2), high: (gross[:high] * share).round(2) }
  end

  def total_received_payments
    contract_payments.where(direction: "incoming", status: "paid").sum(:amount)
  end

  def total_pending_payments
    contract_payments.where(direction: "incoming", status: "pending").sum(:amount)
  end

  # Sync paid course offering payouts to contract payments
  def sync_course_payouts_to_payments
    return if course_offerings.empty?

    # Find all paid line items from course offering payouts
    paid_items = CourseOfferingPayoutLineItem
      .joins(course_offering_payout: :course_offering)
      .where(course_offering_payout: { course_offering_id: course_offerings.ids })
      .where(payee_type: "Contractor", payee_id: contractor_id)
      .where(manually_paid: true)

    paid_items.each do |item|
      # Find matching pending ContractPayment (outgoing, for this contractor)
      payments_to_sync = contract_payments
        .where(direction: "outgoing", status: "pending")
        .select { |p| p.description&.downcase&.include?("revenue share") }

      payments_to_sync.each do |payment|
        payment.mark_paid!(
          paid_on: item.paid_at.to_date,
          method: item.payment_method,
          reference: "Course offering payout",
          amount: item.amount_cents / 100.0
        )
      end
    end
  end

  private

  def deal_money(value)
    format("$%.2f", value.to_f)
  end

  # System-generated "Deal Terms" schedule appended to every signable document —
  # the concrete term, money terms, payment schedule, and services, straight from
  # the contract's own data so the numbers can't drift from a template's wording.
  def deal_terms_html
    esc = ->(s) { ERB::Util.html_escape(s.to_s) }
    out = +%(<hr><h3>Deal Terms</h3>)

    if contract_start_date && contract_end_date
      out << %(<p><strong>Term:</strong> #{esc.(contract_start_date.strftime("%B %-d, %Y"))} – #{esc.(contract_end_date.strftime("%B %-d, %Y"))}</p>)
    end

    summary_lines = (deal_summary rescue [])
    if summary_lines.any?
      out << "<ul>"
      summary_lines.each { |l| out << %(<li><strong>#{esc.(l[:label])}:</strong> #{esc.(l[:value])}</li>) }
      out << "</ul>"
    end

    payments = (draft_payments rescue [])
    if payments.any?
      out << "<h4>Payment schedule</h4><table><thead><tr><th>Item</th><th>Direction</th><th>Amount</th><th>Due</th></tr></thead><tbody>"
      payments.each do |p|
        direction = p["direction"] == "outgoing" ? "We pay them" : "They pay us"
        amount = p["amount_tbd"] ? "TBD" : deal_money(p["amount"])
        due = p["due_date"].present? ? esc.(p["due_date"]) : "—"
        out << %(<tr><td>#{esc.(p["description"].presence || "Payment")}</td><td>#{direction}</td><td>#{amount}</td><td>#{due}</td></tr>)
      end
      out << "</tbody></table>"
    end

    services = (draft_services rescue [])
    if services.any?
      out << "<h4>Services</h4><ul>"
      services.each do |s|
        qty = s["quantity"].to_f
        qty_label = qty > 1 ? " × #{qty.to_i == qty ? qty.to_i : qty}" : ""
        out << %(<li>#{esc.(s["name"])}#{qty_label} — #{deal_money(s["unit_price"])}#{s["unit"] == "hourly" ? "/hr" : ""}</li>)
      end
      out << "</ul>"
    end

    out
  end

  # The inline "License Period and Fees" grid — the dates/stage/rent table a
  # template places itself via {{license_schedule}}. Built entirely from the
  # contract's own bookings + rent so it can't drift, and emitted as a plain
  # <table> the signing view and the PDF walker both already render.
  def license_schedule_html
    esc = ->(s) { ERB::Util.html_escape(s.to_s) }
    rows = license_schedule_rows
    out = +%(<table><thead><tr><th>Dates</th><th>Event</th><th>Start</th><th>End</th><th>Stage</th><th>Rent</th></tr></thead><tbody>)
    if rows.empty?
      out << %(<tr><td colspan="6">Dates to be confirmed.</td></tr>)
    else
      rows.each do |r|
        out << "<tr>"
        out << %(<td>#{esc.(r[:date])}</td><td>#{esc.(r[:event])}</td><td>#{esc.(r[:start])}</td>)
        out << %(<td>#{esc.(r[:end])}</td><td>#{esc.(r[:stage])}</td><td>#{esc.(r[:rent])}</td>)
        out << "</tr>"
      end
    end
    out << "</tbody></table>"
    out << license_payment_schedule_html
    out
  end

  # A second grid, placed just below the dates/rent grid, listing when payments
  # fall due — deposits, installments, "half up front / half on opening". Rendered
  # only when there's a real dated schedule beyond the per-date rent already shown
  # above: pure revenue splits (TBD) don't count, and a per-event rent whose
  # payments all land on the booking dates is already visible in the Rent column,
  # so simple deals get no redundant table.
  def license_payment_schedule_html
    payments = license_concrete_payments
    return "" if payments.empty?

    booking_dates = license_booking_dates
    # Everything already shown as per-date rent above → nothing to add.
    return "" unless payments.any? { |p| booking_dates.exclude?(p[:due]) }

    esc = ->(s) { ERB::Util.html_escape(s.to_s) }
    out = +%(<h4>Payment schedule</h4><table><thead><tr><th>Payment</th><th>Amount</th><th>Due</th></tr></thead><tbody>)
    payments.each do |p|
      out << %(<tr><td>#{esc.(p[:label])}</td><td>#{esc.(p[:amount])}</td><td>#{esc.(p[:due_label])}</td></tr>)
    end
    out << "</tbody></table>"
    out
  end

  # Concrete scheduled payments (real amount, real due date — not TBD revenue-share
  # placeholders), oldest first, shaped for the payment-schedule grid.
  def license_concrete_payments
    draft_payments.filter_map do |p|
      next if p["amount_tbd"]

      amount = p["amount"].to_f
      next unless amount.positive?

      due = parse_booking_time(p["due_date"])&.to_date
      next unless due

      { label: p["description"].presence || "Payment", amount: deal_money(amount),
        due: due, due_label: due.strftime("%b %-d, %Y") }
    end.sort_by { |p| p[:due] }
  end

  # The set of dates the bookings fall on (the rental date) — used to tell whether a
  # payment is "extra" (a deposit/installment worth its own row) or just per-date rent.
  def license_booking_dates
    draft_bookings.filter_map { |b| parse_booking_time(b["starts_at"])&.to_date }
  end

  # The services being rendered on this contract, for the {{services}} token — the
  # deal's own service line items with quantity and rate. Renders its own heading
  # and nothing at all when there are no services, so the token leaves no orphan
  # header behind on a contract without any.
  def license_services_html
    services = (draft_services rescue [])
    return "" if services.blank?

    esc = ->(s) { ERB::Util.html_escape(s.to_s) }
    out = +%(<h4>Services</h4><ul>)
    services.each do |s|
      per = s["unit"] == "hourly" ? "/hr" : ""
      if s["per_event"] && s["events"].present?
        events = Array(s["events"])
        hours = events.sum { |e| e["hours"].to_f }
        detail = s["unit"] == "hourly" ? "#{events.size} events, #{hours.to_i == hours ? hours.to_i : hours} hrs total" : "#{events.size} events"
        out << %(<li>#{esc.(s["name"])} — #{detail} — #{deal_money(s["unit_price"])}#{per}</li>)
      else
        qty = s["quantity"].to_f
        qty_label = qty > 1 ? " × #{qty.to_i == qty ? qty.to_i : qty}" : ""
        out << %(<li>#{esc.(s["name"])}#{qty_label} — #{deal_money(s["unit_price"])}#{per}</li>)
      end
    end
    out << "</ul>"
    out
  end

  # One grid row per booking (date-ordered), drawing only on data the contract
  # already holds. Rent per row is a concrete dated amount when the schedule has
  # one; otherwise it falls back to the deal's pricing expressed in words — a flat
  # fee, a per-event amount, or a revenue share ("50% of ticket sales"). Never
  # "TBD": the Rent cell always states how the money works.
  def license_schedule_rows
    rent_by_date = license_concrete_rent_by_date
    space_names = license_space_names
    rent_label = license_rent_label

    draft_bookings.filter_map do |b|
      # The contract covers the whole booked slot (e.g. 8–11 PM), not the show's own
      # time within it (e.g. 9–10:30) — the rental time is what's being licensed, so
      # the grid shows the booking's start/end, not the event's.
      starts_at = parse_booking_time(b["starts_at"])
      next unless starts_at

      ends_at = booking_end(b, starts_at)
      space_id = (b["location_space_id"].presence || b["space_id"].presence)&.to_i

      {
        date: starts_at.strftime("%a %b %-d, %Y"),
        event: license_event_label(b),
        start: starts_at.strftime("%-l:%M %p"),
        end: ends_at ? ends_at.strftime("%-l:%M %p") : "—",
        stage: space_id ? (space_names[space_id] || "Stage") : "Entire venue",
        rent: rent_by_date[starts_at.to_date] || rent_label
      }
    end
  end

  def parse_booking_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def booking_end(booking, starts_at)
    if booking["ends_at"].present?
      parse_booking_time(booking["ends_at"])
    elsif booking["duration"].present?
      starts_at + booking["duration"].to_f.hours
    end
  end

  # A readable event name for the grid: the booking's own event_type when it's a
  # real label, otherwise the production/show name, else a generic fallback.
  def license_event_label(booking)
    raw = booking["event_type"].to_s.strip
    return raw.tr("_", " ").split.map(&:capitalize).join(" ") if raw.present? && raw != "show"

    production_name.presence || production&.name.presence || "Performance"
  end

  # Concrete rent keyed by date, from the payment schedule. Per-event payments
  # carry a due_date on the event date, so this lines each booking up with its own
  # dollar figure. Only real, settled-in amounts land here — TBD/revenue-share
  # placeholders are skipped so they fall through to the worded pricing label.
  def license_concrete_rent_by_date
    draft_payments.each_with_object({}) do |payment, map|
      next if payment["amount_tbd"]

      amount = payment["amount"].to_f
      next unless amount.positive?

      date = parse_booking_time(payment["due_date"])&.to_date
      next unless date

      map[date] ||= deal_money(amount)
    end
  end

  # How the rent reads when there's no concrete dated amount — the deal's pricing
  # stated plainly, per payment structure. Never "TBD".
  def license_rent_label
    cfg = draft_payment_config
    case draft_payment_structure
    when "per_event"
      cfg["per_event_amount"].to_f.positive? ? deal_money(cfg["per_event_amount"]) : "—"
    when "flat_fee"
      license_flat_fee_rent(cfg)
    when "revenue_share"
      license_revenue_share_rent(cfg)
    else
      "—"
    end
  end

  # A flat fee shows the fee itself; the ticket-revenue-minus-fee variant says so.
  def license_flat_fee_rent(cfg)
    return "—" unless cfg["flat_fee_amount"].to_f.positive?

    if cfg["flat_fee_direction"] == "ticket_revenue_minus_fee"
      per = flat_fee_basis == "per_show" ? " per show" : ""
      "Ticket revenue less #{deal_money(cfg['flat_fee_amount'])}#{per} fee"
    else
      deal_money(cfg["flat_fee_amount"])
    end
  end

  # A revenue share reads as the venue's cut, e.g. "50% of ticket sales".
  def license_revenue_share_rent(cfg)
    share = (cfg["revenue_our_share"].presence || 50).to_i
    source = {
      "ticket_sales" => "ticket sales", "door_sales" => "door sales",
      "bar_sales" => "bar & concessions", "merchandise" => "merchandise",
      "total_revenue" => "total revenue"
    }[cfg["revenue_source"]] || "ticket sales"
    "#{share}% of #{source}"
  end

  # Names for the stages referenced by the bookings, in one query.
  def license_space_names
    ids = draft_bookings.filter_map { |b| (b["location_space_id"].presence || b["space_id"].presence)&.to_i }.uniq
    return {} if ids.empty?

    LocationSpace.where(id: ids).pluck(:id, :name).to_h
  end

  def deal_summary_flat_fee(cfg, lines)
    if cfg["flat_fee_direction"] == "ticket_revenue_minus_fee"
      fee = deal_money(cfg["flat_fee_amount"])
      fee = "#{fee} per show" if flat_fee_basis == "per_show"
      lines << { label: "How the money works",
                 value: "They keep the ticket revenue, less our #{fee} fee" }
      lines << { label: "Settled", value: settlement_cadence_label }
      return
    end

    direction = cfg["flat_fee_direction"] == "outgoing" ? "we pay them" : "they pay us"
    lines << { label: "How the money works", value: "Flat fee of #{deal_money(cfg['flat_fee_amount'])} — #{direction}" }

    return unless cfg["flat_fee_has_deposit"].to_s == "true"

    deposit = if cfg["flat_fee_deposit_amount"].to_f.positive?
      deal_money(cfg["flat_fee_deposit_amount"])
    elsif cfg["flat_fee_deposit_percent"].to_f.positive?
      "#{cfg['flat_fee_deposit_percent']}%"
    end
    lines << { label: "Deposit", value: [ deposit, "upfront" ].compact.join(" ") } if deposit
  end

  def deal_summary_per_event(cfg, lines)
    direction = cfg["per_event_direction"] == "outgoing" ? "we pay them" : "they pay us"
    lines << { label: "How the money works", value: "#{deal_money(cfg['per_event_amount'])} per event — #{direction}" }

    timing = cfg["per_event_timing"] == "upfront" ? "All upfront" : "Event by event"
    lines << { label: "Paid", value: timing }

    if cfg["per_event_has_discount"].to_s == "true" && cfg["per_event_discount_percent"].to_f.positive?
      lines << { label: "Volume discount", value: "#{cfg['per_event_discount_percent']}% off" }
    end
  end

  def deal_summary_revenue_share(cfg, lines)
    our = cfg["revenue_our_share"].presence || 50
    their = cfg["revenue_their_share"].presence || (100 - our.to_i)
    source = {
      "ticket_sales" => "ticket sales", "door_sales" => "door sales",
      "bar_sales" => "bar and concessions", "merchandise" => "merchandise",
      "total_revenue" => "all revenue"
    }[cfg["revenue_source"]] || "ticket sales"
    lines << { label: "How the money works", value: "Revenue share on #{source} — we keep #{our}%, they keep #{their}%" }

    if cfg["revenue_guarantee"].to_s == "true" && cfg["revenue_guarantee_amount"].to_f.positive?
      lines << { label: "Minimum guarantee", value: "They take home at least #{deal_money(cfg['revenue_guarantee_amount'])}" }
    end

    settlement = {
      "same_day" => "Settled same day", "next_day" => "Settled next business day",
      "weekly" => "Settled weekly", "monthly" => "Settled monthly"
    }[cfg["revenue_settlement"]]
    lines << { label: "Settlement", value: settlement } if settlement
  end

  def sync_contractor_info
    return unless contractor_id.present?

    # If contractor is set, ensure contractor_name comes from the contractor
    self.contractor_name = contractor.name if contractor_name.blank? || contractor_id_changed?

    # Optionally sync contact info from contractor if not set on contract
    if contractor_email.blank? && contractor.email.present?
      self.contractor_email = contractor.email
    end
    if contractor_phone.blank? && contractor.phone.present?
      self.contractor_phone = contractor.phone
    end
    if contractor_address.blank? && contractor.address.present?
      self.contractor_address = contractor.address
    end
  end

  def create_records_from_draft!
    rentals = []

    draft_bookings.each do |booking|
      starts_at = Time.zone.parse(booking["starts_at"])

      # Handle both data formats: ends_at directly, or duration-based calculation
      ends_at = if booking["ends_at"].present?
        Time.zone.parse(booking["ends_at"])
      else
        duration_hours = booking["duration"].to_f
        starts_at + duration_hours.hours
      end

      # Get location_id (required) and space_id (optional for "Entire venue")
      location_id = booking["location_id"]
      space_id = booking["location_space_id"] || booking["space_id"]
      space_id = nil if space_id.blank? # Convert empty string to nil

      # Handle event_starts_at if different from rental start
      event_starts_at = booking["event_starts_at"].present? ? Time.zone.parse(booking["event_starts_at"]) : nil
      event_ends_at = booking["event_ends_at"].present? ? Time.zone.parse(booking["event_ends_at"]) : nil

      rental = space_rentals.create!({
        location_id: location_id,
        location_space_id: space_id,
        starts_at: starts_at,
        ends_at: ends_at,
        event_starts_at: event_starts_at,
        event_ends_at: event_ends_at,
        notes: booking["notes"],
        confirmed: true,
        # Honor an override chosen in the wizard. Offline activation sets the
        # transient attr; e-sign persists it in draft_data because the rentals
        # aren't created until the counterparty signs, long after that choice.
        allow_overlap: allow_overlap || draft_data["allow_overlap"] == true
      })

      event_type = booking["event_type"] || "show"
      rentals << { rental: rental, event_type: event_type }
    end

    # Create payments from draft payments
    created_payments = []
    draft_payments.each do |payment|
      created_payments << contract_payments.create!(
        description: payment["description"],
        amount: payment["amount"],
        amount_tbd: payment["amount_tbd"] || false,
        direction: payment["direction"],
        due_date: payment["due_date"],
        notes: payment["notes"]
      )
    end

    # Always create a production and shows for all bookings
    created_shows = []
    if rentals.any?
      prod_data = draft_data["production"] || {}
      # Reuse an existing production rather than creating a duplicate:
      #   1. one already attached to this contract, or
      #   2. one the user explicitly chose to link when starting the contract.
      # Only create a fresh third_party production when neither exists.
      linked_production_id = draft_data["link_production_id"].presence
      production = self.production
      production ||= organization.productions.find_by(id: linked_production_id) if linked_production_id
      production ||= organization.productions.create!(
        name: production_name.presence || prod_data["name"].presence || contractor_name,
        production_type: "third_party",
        contact_email: contractor_email
      )

      # Attach this contract to that production (a production can carry many contracts).
      update!(production: production) unless self.production_id == production.id

      rentals.each do |info|
        rental = info[:rental]
        # The show represents the event, so it runs at the event time when one
        # was set within the booked slot — not the whole slot.
        show = production.shows.create!(
          date_and_time: rental.effective_event_starts_at,
          duration_minutes: rental.effective_duration_minutes,
          location: rental.location,
          location_space: rental.location_space,
          space_rental: rental,
          event_type: info[:event_type]
        )
        created_shows << show
      end
    end

    # Services become their own billable payments (this is what "Tech" never
    # did). Billed AFTER show creation so per-event service payments can carry
    # their show's id and land on the event's date.
    bill_services!(draft_services)

    # Link per-event payments to their corresponding shows
    link_payments_to_shows(created_payments, created_shows)
  end

  # Link per-event contract payments to their corresponding shows by matching dates
  def link_payments_to_shows(payments, shows)
    return if payments.empty? || shows.empty?

    settlement = draft_payment_config["revenue_settlement"] || "monthly"
    structure = draft_payment_structure

    # Only link for per-event or per-event revenue share settlements
    per_event_structures = %w[per_event]
    per_event_settlements = %w[per_event same_day next_day]

    should_link = per_event_structures.include?(structure) ||
                  (structure == "revenue_share" && per_event_settlements.include?(settlement))
    return unless should_link

    sorted_shows = shows.sort_by(&:date_and_time)
    # Per-event payments are named for their event date now (e.g. "Jul 1 event"),
    # so match the word case-insensitively; revenue-share ones are amount_tbd.
    sorted_payments = payments.select { |p| p.amount_tbd? || p.description&.downcase&.include?("event") || p.description&.downcase&.include?("revenue share") }
                              .sort_by(&:due_date)

    # Pair each payment with the show on its due date — a per-event payment is
    # due on its event's date. Pairing by position corrupted amended contracts:
    # the amendment relinks only PENDING payments while `shows` is the whole
    # run, so with one show already settled every later payment linked to the
    # show one slot back — and the financials sync then wrote one show's money
    # onto the next show's payment. Links a payment already carries (from the
    # sync or a manager) are kept, not rewritten.
    linked_show_ids = sorted_payments.filter_map(&:show_id).to_set
    unclaimed_shows = sorted_shows.reject { |s| linked_show_ids.include?(s.id) }
    matched = sorted_payments.filter_map do |payment|
      next if payment.show_id.present?

      show = unclaimed_shows.find { |s| s.date_and_time.to_date == payment.due_date }
      next unless show

      unclaimed_shows.delete(show)
      [ payment, show ]
    end

    # A deal whose due dates don't sit on event dates still pairs 1:1 when the
    # lists line up exactly (the create path always passes complete lists).
    if matched.empty? && linked_show_ids.empty? && sorted_payments.size == sorted_shows.size
      matched = sorted_payments.zip(sorted_shows)
    end

    matched.each { |payment, show| payment.update_column(:show_id, show.id) }
  end
end
