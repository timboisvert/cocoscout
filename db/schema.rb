# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_06_170200) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_stat_statements"
  enable_extension "pgcrypto"
  enable_extension "uuid-ossp"

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", limit: 8000, null: false
    t.bigint "record_id", null: false
    t.string "record_type", limit: 8000, null: false
    t.datetime "updated_at", null: false
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", limit: 8000, null: false
    t.bigint "record_id", null: false
    t.string "record_type", limit: 8000, null: false
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "advance_recoveries", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.bigint "person_advance_id", null: false
    t.bigint "show_payout_line_item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["person_advance_id", "show_payout_line_item_id"], name: "idx_advance_recoveries_unique", unique: true
    t.index ["person_advance_id"], name: "index_advance_recoveries_on_person_advance_id"
    t.index ["show_payout_line_item_id"], name: "index_advance_recoveries_on_show_payout_line_item_id"
  end

  create_table "agreement_requests", force: :cascade do |t|
    t.bigint "agreement_template_id"
    t.datetime "created_at", null: false
    t.bigint "person_id", null: false
    t.bigint "production_id", null: false
    t.integer "send_count", default: 1, null: false
    t.datetime "sent_at", null: false
    t.bigint "sent_by_id"
    t.datetime "updated_at", null: false
    t.index ["agreement_template_id"], name: "index_agreement_requests_on_agreement_template_id"
    t.index ["person_id"], name: "index_agreement_requests_on_person_id"
    t.index ["production_id", "person_id"], name: "index_agreement_requests_on_production_id_and_person_id", unique: true
    t.index ["production_id"], name: "index_agreement_requests_on_production_id"
    t.index ["sent_by_id"], name: "index_agreement_requests_on_sent_by_id"
  end

  create_table "agreement_signatures", force: :cascade do |t|
    t.bigint "agreement_template_id"
    t.text "content_snapshot", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.bigint "person_id", null: false
    t.bigint "production_id", null: false
    t.datetime "signed_at", null: false
    t.integer "template_version"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["agreement_template_id"], name: "index_agreement_signatures_on_agreement_template_id"
    t.index ["person_id", "production_id"], name: "index_agreement_signatures_on_person_id_and_production_id", unique: true
    t.index ["person_id"], name: "index_agreement_signatures_on_person_id"
    t.index ["production_id"], name: "index_agreement_signatures_on_production_id"
  end

  create_table "agreement_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["organization_id", "active"], name: "index_agreement_templates_on_organization_id_and_active"
    t.index ["organization_id"], name: "index_agreement_templates_on_organization_id"
  end

  create_table "answers", force: :cascade do |t|
    t.integer "audition_request_id", null: false
    t.datetime "created_at", null: false
    t.integer "question_id", null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["audition_request_id"], name: "index_answers_on_audition_request_id"
    t.index ["question_id"], name: "index_answers_on_question_id"
  end

  create_table "audition_cycles", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.boolean "allow_in_person_auditions", default: false, null: false
    t.boolean "allow_slot_changes", default: true, null: false
    t.boolean "allow_video_submissions", default: false, null: false
    t.string "audition_type", default: "in_person", null: false
    t.boolean "audition_voting_enabled", default: true, null: false
    t.text "availability_show_ids"
    t.datetime "casting_finalized_at"
    t.datetime "closes_at"
    t.datetime "created_at", null: false
    t.boolean "finalize_audition_invitations", default: false
    t.boolean "form_reviewed", default: false
    t.text "header_text"
    t.boolean "include_audition_availability_section", default: false
    t.boolean "include_availability_section", default: false
    t.boolean "listed_in_directory", default: true, null: false
    t.boolean "notify_on_submission", default: true, null: false
    t.datetime "opens_at"
    t.integer "production_id", null: false
    t.boolean "require_all_audition_availability", default: false
    t.boolean "require_all_availability", default: false
    t.boolean "resume_required", default: true, null: false
    t.string "reviewer_access_type", default: "managers", null: false
    t.string "signup_mode", default: "curated", null: false
    t.text "success_text"
    t.string "token"
    t.datetime "updated_at", null: false
    t.boolean "voting_enabled", default: true, null: false
    t.index ["production_id", "active"], name: "index_audition_cycles_on_production_id_and_active", unique: true, where: "(active = true)"
    t.index ["production_id"], name: "index_audition_cycles_on_production_id"
  end

  create_table "audition_email_assignments", force: :cascade do |t|
    t.integer "assignable_id"
    t.string "assignable_type"
    t.bigint "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.string "email_group_id"
    t.datetime "updated_at", null: false
    t.index ["assignable_type", "assignable_id", "audition_cycle_id"], name: "index_audition_email_assignments_on_assignable_and_cycle", unique: true
    t.index ["audition_cycle_id"], name: "index_audition_email_assignments_on_audition_cycle_id"
  end

  create_table "audition_request_votes", force: :cascade do |t|
    t.bigint "audition_request_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "vote", default: 0, null: false
    t.index ["audition_request_id", "user_id"], name: "index_audition_request_votes_unique", unique: true
    t.index ["audition_request_id"], name: "index_audition_request_votes_on_audition_request_id"
    t.index ["user_id"], name: "index_audition_request_votes_on_user_id"
  end

  create_table "audition_requests", force: :cascade do |t|
    t.datetime "archived_at"
    t.integer "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.datetime "invitation_notification_sent_at"
    t.boolean "notified_scheduled"
    t.integer "requestable_id"
    t.string "requestable_type"
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.string "video_url"
    t.index ["audition_cycle_id"], name: "index_audition_requests_on_audition_cycle_id"
    t.index ["requestable_type", "requestable_id", "created_at"], name: "index_ar_on_requestable_and_created"
    t.index ["requestable_type", "requestable_id"], name: "index_audition_requests_on_requestable_type_and_requestable_id"
  end

  create_table "audition_reviewers", force: :cascade do |t|
    t.bigint "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.bigint "person_id", null: false
    t.datetime "updated_at", null: false
    t.index ["audition_cycle_id"], name: "index_audition_reviewers_on_audition_cycle_id"
    t.index ["person_id"], name: "index_audition_reviewers_on_person_id"
  end

  create_table "audition_session_availabilities", force: :cascade do |t|
    t.bigint "audition_session_id", null: false
    t.bigint "available_entity_id", null: false
    t.string "available_entity_type", null: false
    t.datetime "created_at", null: false
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.index ["audition_session_id"], name: "index_audition_session_availabilities_on_audition_session_id"
    t.index ["available_entity_id", "available_entity_type", "audition_session_id"], name: "index_audition_session_avail_on_entity_and_session", unique: true
    t.index ["available_entity_type", "available_entity_id"], name: "index_audition_session_availabilities_on_available_entity"
  end

  create_table "audition_sessions", force: :cascade do |t|
    t.bigint "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.datetime "end_at"
    t.bigint "location_id"
    t.integer "maximum_auditionees"
    t.datetime "start_at"
    t.datetime "updated_at", null: false
    t.index ["audition_cycle_id"], name: "index_audition_sessions_on_audition_cycle_id"
    t.index ["location_id"], name: "index_audition_sessions_on_location_id"
  end

  create_table "audition_votes", force: :cascade do |t|
    t.bigint "audition_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.integer "vote", default: 0, null: false
    t.index ["audition_id", "user_id"], name: "index_audition_votes_unique", unique: true
    t.index ["audition_id"], name: "index_audition_votes_on_audition_id"
    t.index ["user_id"], name: "index_audition_votes_on_user_id"
  end

  create_table "audition_wizard_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "production_id", null: false
    t.jsonb "state", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["production_id", "user_id"], name: "idx_audition_wizard_states_on_production_user", unique: true
    t.index ["production_id"], name: "index_audition_wizard_states_on_production_id"
    t.index ["user_id"], name: "index_audition_wizard_states_on_user_id"
  end

  create_table "auditions", force: :cascade do |t|
    t.datetime "accepted_at"
    t.bigint "audition_request_id"
    t.bigint "audition_session_id"
    t.integer "auditionable_id"
    t.string "auditionable_type"
    t.datetime "created_at", null: false
    t.datetime "declined_at"
    t.datetime "updated_at", null: false
    t.index ["audition_request_id"], name: "index_auditions_on_audition_request_id"
    t.index ["audition_session_id"], name: "index_auditions_on_audition_session_id"
    t.index ["auditionable_type", "auditionable_id"], name: "index_auditions_on_auditionable"
  end

  create_table "balance_top_ups", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "error"
    t.bigint "organization_id", null: false
    t.jsonb "refund_request"
    t.bigint "requested_by_id"
    t.string "status", default: "pending", null: false
    t.string "stripe_payment_intent_id"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_balance_top_ups_on_organization_id"
    t.index ["requested_by_id"], name: "index_balance_top_ups_on_requested_by_id"
    t.index ["stripe_payment_intent_id"], name: "index_balance_top_ups_on_stripe_payment_intent_id", unique: true, where: "(stripe_payment_intent_id IS NOT NULL)"
  end

  create_table "balance_withdrawals", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.boolean "automatic", default: false, null: false
    t.datetime "created_at", null: false
    t.string "error"
    t.bigint "organization_id", null: false
    t.datetime "paid_at"
    t.bigint "requested_by_id"
    t.string "status", default: "pending", null: false
    t.string "stripe_payout_id"
    t.string "stripe_transfer_id"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_balance_withdrawals_on_organization_id"
    t.index ["requested_by_id"], name: "index_balance_withdrawals_on_requested_by_id"
    t.index ["stripe_transfer_id"], name: "index_balance_withdrawals_on_stripe_transfer_id"
  end

  create_table "billing_invoices", force: :cascade do |t|
    t.bigint "amount_due_cents", default: 0, null: false
    t.bigint "amount_paid_cents", default: 0, null: false
    t.bigint "amount_remaining_cents", default: 0, null: false
    t.datetime "bill_emailed_at"
    t.datetime "created_at", null: false
    t.datetime "failed_at"
    t.string "failure_message"
    t.datetime "finalized_at"
    t.string "hosted_invoice_url"
    t.string "invoice_pdf_url"
    t.string "kind", default: "other", null: false
    t.jsonb "lines", default: [], null: false
    t.string "number"
    t.bigint "organization_id", null: false
    t.datetime "paid_at"
    t.datetime "period_end"
    t.datetime "period_start"
    t.datetime "receipt_emailed_at"
    t.string "status", null: false
    t.string "stripe_invoice_id", null: false
    t.string "stripe_payment_intent_id"
    t.string "stripe_subscription_id"
    t.datetime "updated_at", null: false
    t.index ["organization_id", "period_start"], name: "index_billing_invoices_on_organization_id_and_period_start"
    t.index ["organization_id"], name: "index_billing_invoices_on_organization_id"
    t.index ["stripe_invoice_id"], name: "index_billing_invoices_on_stripe_invoice_id", unique: true
    t.index ["stripe_payment_intent_id"], name: "index_billing_invoices_on_stripe_payment_intent_id"
  end

  create_table "cast_assignment_stages", force: :cascade do |t|
    t.datetime "archived_at"
    t.integer "assignable_id"
    t.string "assignable_type"
    t.integer "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.integer "decision_type", default: 0, null: false
    t.string "email_group_id"
    t.text "notification_email"
    t.integer "status", default: 0, null: false
    t.bigint "talent_pool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assignable_type", "assignable_id"], name: "idx_on_assignable_type_assignable_id_366d98058e"
    t.index ["audition_cycle_id", "archived_at"], name: "idx_on_audition_cycle_id_archived_at_6df8d43e35"
    t.index ["audition_cycle_id", "talent_pool_id", "assignable_type", "assignable_id"], name: "index_cast_assignment_stages_unique", unique: true
    t.index ["audition_cycle_id"], name: "index_cast_assignment_stages_on_audition_cycle_id"
    t.index ["talent_pool_id"], name: "index_cast_assignment_stages_on_talent_pool_id"
  end

  create_table "casting_table_draft_assignments", force: :cascade do |t|
    t.bigint "assignable_id", null: false
    t.string "assignable_type", null: false
    t.bigint "casting_table_id", null: false
    t.datetime "created_at", null: false
    t.bigint "role_id", null: false
    t.bigint "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assignable_type", "assignable_id"], name: "index_casting_table_draft_assignments_on_assignable"
    t.index ["casting_table_id", "show_id", "role_id", "assignable_type", "assignable_id"], name: "idx_casting_table_draft_assignments_unique", unique: true
    t.index ["casting_table_id"], name: "index_casting_table_draft_assignments_on_casting_table_id"
    t.index ["role_id"], name: "index_casting_table_draft_assignments_on_role_id"
    t.index ["show_id"], name: "index_casting_table_draft_assignments_on_show_id"
  end

  create_table "casting_table_events", force: :cascade do |t|
    t.bigint "casting_table_id", null: false
    t.datetime "created_at", null: false
    t.bigint "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["casting_table_id", "show_id"], name: "idx_casting_table_events_unique", unique: true
    t.index ["casting_table_id"], name: "index_casting_table_events_on_casting_table_id"
    t.index ["show_id"], name: "index_casting_table_events_on_show_id"
  end

  create_table "casting_table_members", force: :cascade do |t|
    t.bigint "casting_table_id", null: false
    t.datetime "created_at", null: false
    t.bigint "memberable_id", null: false
    t.string "memberable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["casting_table_id", "memberable_type", "memberable_id"], name: "idx_casting_table_members_unique", unique: true
    t.index ["casting_table_id"], name: "index_casting_table_members_on_casting_table_id"
    t.index ["memberable_type", "memberable_id"], name: "index_casting_table_members_on_memberable"
  end

  create_table "casting_table_productions", force: :cascade do |t|
    t.bigint "casting_table_id", null: false
    t.datetime "created_at", null: false
    t.bigint "production_id", null: false
    t.datetime "updated_at", null: false
    t.index ["casting_table_id", "production_id"], name: "idx_casting_table_productions_unique", unique: true
    t.index ["casting_table_id"], name: "index_casting_table_productions_on_casting_table_id"
    t.index ["production_id"], name: "index_casting_table_productions_on_production_id"
  end

  create_table "casting_tables", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.datetime "finalized_at"
    t.bigint "finalized_by_id"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_casting_tables_on_created_by_id"
    t.index ["finalized_by_id"], name: "index_casting_tables_on_finalized_by_id"
    t.index ["organization_id"], name: "index_casting_tables_on_organization_id"
  end

  create_table "city_hub_memberships", force: :cascade do |t|
    t.bigint "city_hub_id", null: false
    t.datetime "created_at", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["city_hub_id", "user_id"], name: "index_city_hub_memberships_on_city_hub_id_and_user_id", unique: true
    t.index ["city_hub_id"], name: "index_city_hub_memberships_on_city_hub_id"
    t.index ["user_id"], name: "index_city_hub_memberships_on_user_id"
  end

  create_table "city_hubs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "default_radius_miles", default: 25, null: false
    t.text "intro_markdown"
    t.float "lat"
    t.float "lng"
    t.string "name", null: false
    t.string "slug", null: false
    t.string "state", null: false
    t.integer "status", default: 0, null: false
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_city_hubs_on_slug", unique: true
  end

  create_table "city_votes", force: :cascade do |t|
    t.string "city", null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "state", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["city", "state"], name: "index_city_votes_on_city_and_state"
    t.index ["user_id", "city", "state"], name: "index_city_votes_on_user_id_and_city_and_state", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["user_id"], name: "index_city_votes_on_user_id"
  end

  create_table "cocoscout_ledger_entries", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "usd", null: false
    t.string "description"
    t.string "entry_type", null: false
    t.datetime "occurred_at", null: false
    t.bigint "organization_id"
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.index ["entry_type"], name: "index_cocoscout_ledger_entries_on_entry_type"
    t.index ["occurred_at"], name: "index_cocoscout_ledger_entries_on_occurred_at"
    t.index ["organization_id"], name: "index_cocoscout_ledger_entries_on_organization_id"
    t.index ["source_type", "source_id", "entry_type"], name: "index_cocoscout_ledger_entries_on_source_and_type", unique: true
    t.index ["source_type", "source_id"], name: "index_cocoscout_ledger_entries_on_source"
  end

  create_table "content_templates", force: :cascade do |t|
    t.boolean "active", default: true
    t.jsonb "available_variables", default: []
    t.text "body", null: false
    t.string "category"
    t.string "channel", default: "email", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.string "mailer_action"
    t.string "mailer_class"
    t.text "message_body"
    t.string "name", null: false
    t.text "notes"
    t.string "subject", null: false
    t.string "template_type"
    t.datetime "updated_at", null: false
    t.jsonb "usage_locations"
    t.index ["active"], name: "index_content_templates_on_active"
    t.index ["category"], name: "index_content_templates_on_category"
    t.index ["key"], name: "index_content_templates_on_key", unique: true
  end

  create_table "contract_appendixes", force: :cascade do |t|
    t.bigint "contract_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["contract_id", "position"], name: "index_contract_appendixes_on_contract_id_and_position"
    t.index ["contract_id"], name: "index_contract_appendixes_on_contract_id"
  end

  create_table "contract_documents", force: :cascade do |t|
    t.bigint "contract_id", null: false
    t.bigint "contract_version_id"
    t.datetime "created_at", null: false
    t.string "document_type"
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.index ["contract_id"], name: "index_contract_documents_on_contract_id"
    t.index ["contract_version_id"], name: "index_contract_documents_on_contract_version_id"
  end

  create_table "contract_invoices", force: :cascade do |t|
    t.bigint "combined_into_payment_id"
    t.bigint "contract_payment_id"
    t.datetime "created_at", null: false
    t.datetime "issued_at", null: false
    t.integer "number", null: false
    t.bigint "organization_id", null: false
    t.string "payment_token"
    t.string "prefix", null: false
    t.datetime "receipt_emailed_at"
    t.datetime "sent_at"
    t.integer "sent_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "void_reason"
    t.datetime "voided_at"
    t.index ["contract_payment_id"], name: "index_contract_invoices_on_contract_payment_id", unique: true
    t.index ["organization_id", "number"], name: "index_contract_invoices_on_organization_id_and_number", unique: true
    t.index ["organization_id"], name: "index_contract_invoices_on_organization_id"
    t.index ["payment_token"], name: "index_contract_invoices_on_payment_token"
  end

  create_table "contract_payments", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.boolean "amount_tbd", default: false, null: false
    t.boolean "auto_shortfall", default: false, null: false
    t.jsonb "components", default: [], null: false
    t.bigint "contract_id", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "direction", null: false
    t.date "due_date", null: false
    t.text "notes"
    t.date "paid_date"
    t.string "payment_method"
    t.string "payment_token"
    t.string "reference_number"
    t.string "settlement_method", default: "direct", null: false
    t.bigint "show_id"
    t.string "status", default: "pending", null: false
    t.string "stripe_checkout_session_id"
    t.integer "stripe_fee_cents"
    t.string "stripe_payment_intent_id"
    t.datetime "updated_at", null: false
    t.index ["contract_id", "status"], name: "index_contract_payments_on_contract_id_and_status"
    t.index ["contract_id"], name: "index_contract_payments_on_contract_id"
    t.index ["due_date"], name: "index_contract_payments_on_due_date"
    t.index ["payment_token"], name: "index_contract_payments_on_payment_token", unique: true
    t.index ["show_id"], name: "index_contract_payments_on_show_id"
    t.index ["status"], name: "index_contract_payments_on_status"
    t.index ["stripe_checkout_session_id"], name: "index_contract_payments_on_stripe_checkout_session_id", unique: true
  end

  create_table "contract_service_options", force: :cascade do |t|
    t.string "booking_mode", default: "once", null: false
    t.datetime "created_at", null: false
    t.string "default_direction", default: "incoming", null: false
    t.integer "default_price_cents", default: 0, null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.integer "position", default: 0, null: false
    t.string "unit", default: "flat", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_contract_service_options_on_organization_id"
  end

  create_table "contract_signatures", force: :cascade do |t|
    t.text "content_snapshot", null: false
    t.bigint "contract_id", null: false
    t.bigint "contract_template_id"
    t.bigint "contract_version_id"
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.bigint "person_id"
    t.datetime "signed_at", null: false
    t.bigint "signed_by_user_id"
    t.string "signer_email"
    t.string "signer_name"
    t.string "signer_role", null: false
    t.integer "template_version"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["contract_id"], name: "index_contract_signatures_on_contract_id"
    t.index ["contract_template_id"], name: "index_contract_signatures_on_contract_template_id"
    t.index ["contract_version_id", "signer_role"], name: "index_contract_signatures_on_version_and_role", unique: true
    t.index ["contract_version_id"], name: "index_contract_signatures_on_contract_version_id"
    t.index ["person_id"], name: "index_contract_signatures_on_person_id"
    t.index ["signed_by_user_id"], name: "index_contract_signatures_on_signed_by_user_id"
  end

  create_table "contract_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["organization_id", "active"], name: "index_contract_templates_on_organization_id_and_active"
    t.index ["organization_id"], name: "index_contract_templates_on_organization_id"
  end

  create_table "contract_versions", force: :cascade do |t|
    t.text "change_summary"
    t.text "content_snapshot", null: false
    t.bigint "contract_id", null: false
    t.bigint "contract_template_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.jsonb "deal_snapshot", default: {}, null: false
    t.datetime "executed_at"
    t.datetime "expired_at"
    t.boolean "force_overlap", default: false, null: false
    t.datetime "last_nudged_at"
    t.integer "nudge_count", default: 0, null: false
    t.boolean "requires_signature", default: true, null: false
    t.datetime "sent_for_signature_at"
    t.datetime "signature_due_at"
    t.string "signing_token"
    t.jsonb "staged_amendment"
    t.integer "template_version"
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["contract_id", "version_number"], name: "index_contract_versions_on_contract_id_and_version_number", unique: true
    t.index ["contract_id"], name: "index_contract_versions_on_contract_id"
    t.index ["contract_template_id"], name: "index_contract_versions_on_contract_template_id"
    t.index ["created_by_id"], name: "index_contract_versions_on_created_by_id"
    t.index ["signature_due_at"], name: "index_contract_versions_on_signature_due_at"
    t.index ["signing_token"], name: "index_contract_versions_on_signing_token", unique: true
  end

  create_table "contractors", force: :cascade do |t|
    t.text "address"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name", null: false
    t.text "notes"
    t.bigint "organization_id", null: false
    t.boolean "payouts_enabled", default: false, null: false
    t.bigint "person_id"
    t.string "phone"
    t.string "stripe_account_id"
    t.string "stripe_account_status"
    t.datetime "stripe_account_synced_at"
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_contractors_on_organization_id_and_name"
    t.index ["organization_id"], name: "index_contractors_on_organization_id"
    t.index ["person_id"], name: "index_contractors_on_person_id"
    t.index ["stripe_account_id"], name: "index_contractors_on_stripe_account_id", unique: true, where: "(stripe_account_id IS NOT NULL)"
  end

  create_table "contracts", force: :cascade do |t|
    t.datetime "activated_at"
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.date "contract_end_date"
    t.date "contract_start_date"
    t.bigint "contract_template_id"
    t.text "contractor_address"
    t.string "contractor_email"
    t.bigint "contractor_id"
    t.string "contractor_name", null: false
    t.string "contractor_phone"
    t.datetime "created_at", null: false
    t.jsonb "draft_data", default: {}
    t.datetime "executed_at"
    t.text "notes"
    t.bigint "organization_id", null: false
    t.bigint "production_id"
    t.string "production_name"
    t.datetime "sent_for_signature_at"
    t.jsonb "services", default: []
    t.boolean "shares_ticket_sales", default: true, null: false
    t.string "signing_mode", default: "offline", null: false
    t.string "signing_state", default: "unsent", null: false
    t.string "signing_token"
    t.string "status", default: "draft", null: false
    t.text "terms"
    t.datetime "updated_at", null: false
    t.integer "wizard_step", default: 1, null: false
    t.index ["contract_template_id"], name: "index_contracts_on_contract_template_id"
    t.index ["contractor_id"], name: "index_contracts_on_contractor_id"
    t.index ["organization_id", "status"], name: "index_contracts_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_contracts_on_organization_id"
    t.index ["production_id"], name: "index_contracts_on_production_id"
    t.index ["signing_token"], name: "index_contracts_on_signing_token", unique: true
    t.index ["status"], name: "index_contracts_on_status"
  end

  create_table "course_offering_instructors", force: :cascade do |t|
    t.bigint "course_offering_id", null: false
    t.datetime "created_at", null: false
    t.boolean "hide_photo", default: false, null: false
    t.integer "payout_cents"
    t.decimal "payout_percentage", precision: 5, scale: 2
    t.string "payout_type", default: "none", null: false
    t.bigint "person_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["course_offering_id", "person_id"], name: "idx_course_offering_instructors_unique", unique: true
    t.index ["course_offering_id"], name: "index_course_offering_instructors_on_course_offering_id"
    t.index ["person_id"], name: "index_course_offering_instructors_on_person_id"
  end

  create_table "course_offering_payout_line_items", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.jsonb "calculation_details", default: {}
    t.bigint "course_offering_payout_id", null: false
    t.datetime "created_at", null: false
    t.string "label"
    t.boolean "manually_paid", default: false, null: false
    t.datetime "manually_paid_at"
    t.bigint "manually_paid_by_id"
    t.datetime "paid_at"
    t.bigint "payee_id"
    t.string "payee_type"
    t.string "payment_method"
    t.text "payment_notes"
    t.datetime "updated_at", null: false
    t.index ["course_offering_payout_id"], name: "idx_on_course_offering_payout_id_99f85e28a3"
    t.index ["manually_paid_by_id"], name: "index_course_offering_payout_line_items_on_manually_paid_by_id"
    t.index ["payee_type", "payee_id"], name: "idx_course_payout_line_items_payee"
  end

  create_table "course_offering_payouts", force: :cascade do |t|
    t.datetime "calculated_at"
    t.bigint "course_offering_id", null: false
    t.datetime "created_at", null: false
    t.integer "net_revenue_cents"
    t.text "notes"
    t.datetime "paid_at"
    t.string "payout_mode", default: "lump_sum", null: false
    t.integer "platform_fee_cents"
    t.string "status", default: "pending", null: false
    t.integer "total_payout_cents"
    t.integer "total_revenue_cents"
    t.integer "total_revenue_override_cents"
    t.datetime "updated_at", null: false
    t.index ["course_offering_id"], name: "index_course_offering_payouts_on_course_offering_id", unique: true
    t.index ["status"], name: "index_course_offering_payouts_on_status"
  end

  create_table "course_offerings", force: :cascade do |t|
    t.boolean "cancellation_notify_registrants", default: true, null: false
    t.datetime "cancelled_at"
    t.bigint "cancelled_by_user_id"
    t.integer "capacity"
    t.datetime "closes_at"
    t.bigint "contract_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.string "currency", default: "usd", null: false
    t.integer "delivery_delay_minutes"
    t.string "delivery_mode"
    t.datetime "delivery_scheduled_at"
    t.datetime "early_bird_deadline"
    t.integer "early_bird_price_cents"
    t.bigint "feature_credit_redemption_id"
    t.text "instruction_text"
    t.string "instructor_name"
    t.boolean "instructor_on_team", default: false, null: false
    t.bigint "instructor_person_id"
    t.boolean "listed_in_directory", default: true, null: false
    t.string "og_image_source", default: "auto", null: false
    t.datetime "opens_at"
    t.integer "price_cents", null: false
    t.bigint "production_id", null: false
    t.bigint "questionnaire_id"
    t.string "short_code", null: false
    t.boolean "show_group_bio", default: true, null: false
    t.boolean "show_group_photo", default: false, null: false
    t.boolean "show_individual_bios", default: true, null: false
    t.boolean "show_individual_photos", default: true, null: false
    t.string "status", default: "draft", null: false
    t.string "stripe_early_bird_price_id"
    t.string "stripe_price_id"
    t.string "stripe_product_id"
    t.string "subtitle"
    t.text "success_text"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["cancelled_by_user_id"], name: "index_course_offerings_on_cancelled_by_user_id"
    t.index ["contract_id"], name: "index_course_offerings_on_contract_id"
    t.index ["created_by_user_id"], name: "index_course_offerings_on_created_by_user_id"
    t.index ["feature_credit_redemption_id"], name: "index_course_offerings_on_feature_credit_redemption_id"
    t.index ["instructor_person_id"], name: "index_course_offerings_on_instructor_person_id"
    t.index ["production_id"], name: "index_course_offerings_on_production_id"
    t.index ["questionnaire_id"], name: "index_course_offerings_on_questionnaire_id"
    t.index ["short_code"], name: "index_course_offerings_on_short_code", unique: true
    t.index ["status"], name: "index_course_offerings_on_status"
  end

  create_table "course_registrations", force: :cascade do |t|
    t.bigint "added_by_id"
    t.integer "amount_cents", null: false
    t.jsonb "attended_show_ids", default: [], null: false
    t.datetime "cancelled_at"
    t.string "channel", default: "online", null: false
    t.integer "cocoscout_fee_cents"
    t.bigint "course_offering_id", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "usd", null: false
    t.datetime "expires_at"
    t.datetime "paid_at"
    t.string "paid_via"
    t.bigint "person_id", null: false
    t.datetime "refunded_at"
    t.datetime "registered_at", null: false
    t.jsonb "reminded_show_ids", default: [], null: false
    t.string "status", default: "pending", null: false
    t.string "stripe_charge_id"
    t.string "stripe_checkout_session_id"
    t.integer "stripe_fee_cents"
    t.string "stripe_payment_intent_id"
    t.string "stripe_refund_id"
    t.integer "tax_cents", default: 0, null: false
    t.string "token"
    t.jsonb "told_sessions", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["added_by_id"], name: "index_course_registrations_on_added_by_id"
    t.index ["course_offering_id", "person_id"], name: "idx_course_registrations_active_unique", unique: true, where: "((status)::text <> ALL (ARRAY[('cancelled'::character varying)::text, ('refunded'::character varying)::text, ('expired'::character varying)::text]))"
    t.index ["course_offering_id"], name: "index_course_registrations_on_course_offering_id"
    t.index ["expires_at"], name: "index_course_registrations_on_expires_at", where: "((status)::text = 'pending'::text)"
    t.index ["person_id"], name: "index_course_registrations_on_person_id"
    t.index ["status"], name: "index_course_registrations_on_status"
    t.index ["stripe_checkout_session_id"], name: "index_course_registrations_on_stripe_checkout_session_id", unique: true
    t.index ["token"], name: "index_course_registrations_on_token", unique: true
    t.index ["user_id"], name: "index_course_registrations_on_user_id"
  end

  create_table "demo_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "email", null: false
    t.string "name"
    t.text "notes"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_demo_users_on_email", unique: true
  end

  create_table "departments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.bigint "organization_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_departments_on_organization_id"
  end

  create_table "device_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "platform", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token", "platform"], name: "index_device_tokens_on_token_and_platform", unique: true
    t.index ["user_id"], name: "index_device_tokens_on_user_id"
  end

  create_table "document_productions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "production_document_id", null: false
    t.bigint "production_id", null: false
    t.datetime "updated_at", null: false
    t.index ["production_document_id", "production_id"], name: "idx_document_productions_unique", unique: true
    t.index ["production_document_id"], name: "index_document_productions_on_production_document_id"
    t.index ["production_id"], name: "index_document_productions_on_production_id"
  end

  create_table "document_shares", force: :cascade do |t|
    t.bigint "audience_id"
    t.string "audience_type", null: false
    t.datetime "created_at", null: false
    t.integer "permission", default: 0, null: false
    t.bigint "production_document_id", null: false
    t.datetime "updated_at", null: false
    t.index ["audience_type", "audience_id"], name: "index_document_shares_on_audience_type_and_audience_id"
    t.index ["production_document_id"], name: "index_document_shares_on_production_document_id"
  end

  create_table "email_batches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "mailer_action"
    t.string "mailer_class"
    t.integer "recipient_count"
    t.datetime "sent_at"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_email_batches_on_user_id"
  end

  create_table "email_drafts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "emailable_id"
    t.string "emailable_type"
    t.bigint "show_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["emailable_type", "emailable_id"], name: "index_email_drafts_on_emailable"
    t.index ["show_id"], name: "index_email_drafts_on_show_id"
  end

  create_table "email_groups", force: :cascade do |t|
    t.bigint "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.text "email_template"
    t.string "group_id"
    t.string "group_type"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["audition_cycle_id"], name: "index_email_groups_on_audition_cycle_id"
  end

  create_table "email_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "delivery_status", default: "pending"
    t.bigint "email_batch_id"
    t.text "error_message"
    t.string "mailer_action"
    t.string "mailer_class"
    t.string "message_id"
    t.bigint "organization_id"
    t.integer "production_id"
    t.string "recipient", null: false
    t.bigint "recipient_entity_id"
    t.string "recipient_entity_type"
    t.datetime "sent_at"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["email_batch_id"], name: "index_email_logs_on_email_batch_id"
    t.index ["message_id"], name: "index_email_logs_on_message_id"
    t.index ["organization_id"], name: "index_email_logs_on_organization_id"
    t.index ["production_id"], name: "index_email_logs_on_production_id"
    t.index ["recipient"], name: "index_email_logs_on_recipient"
    t.index ["recipient_entity_type", "recipient_entity_id"], name: "index_email_logs_on_recipient_entity"
    t.index ["sent_at", "user_id"], name: "index_email_logs_on_sent_at_desc_user_id", order: { sent_at: :desc }
    t.index ["sent_at"], name: "index_email_logs_on_sent_at"
    t.index ["user_id"], name: "index_email_logs_on_user_id"
  end

  create_table "event_linkages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.bigint "primary_show_id"
    t.bigint "production_id", null: false
    t.datetime "updated_at", null: false
    t.index ["primary_show_id"], name: "index_event_linkages_on_primary_show_id"
    t.index ["production_id"], name: "index_event_linkages_on_production_id"
  end

  create_table "expense_items", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "category", default: "other", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.integer "position", default: 0
    t.bigint "show_financials_id", null: false
    t.datetime "updated_at", null: false
    t.index ["show_financials_id", "position"], name: "index_expense_items_on_show_financials_id_and_position"
    t.index ["show_financials_id"], name: "index_expense_items_on_show_financials_id"
  end

  create_table "feature_credit_redemptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "feature_credit_id", null: false
    t.bigint "organization_id", null: false
    t.bigint "redeemable_id", null: false
    t.string "redeemable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["feature_credit_id"], name: "index_feature_credit_redemptions_on_feature_credit_id"
    t.index ["organization_id"], name: "index_feature_credit_redemptions_on_organization_id"
    t.index ["redeemable_type", "redeemable_id"], name: "idx_fcr_redeemable"
  end

  create_table "feature_credits", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.string "coverage_type", default: "full", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.text "description"
    t.datetime "expires_at"
    t.string "feature_type", default: "courses", null: false
    t.integer "max_uses", default: 1
    t.string "recipient_name"
    t.string "scope_type", default: "course_offering", null: false
    t.datetime "updated_at", null: false
    t.integer "uses_count", default: 0, null: false
    t.index ["active"], name: "index_feature_credits_on_active"
    t.index ["code"], name: "index_feature_credits_on_code", unique: true
    t.index ["feature_type"], name: "index_feature_credits_on_feature_type"
  end

  create_table "group_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "group_id", null: false
    t.integer "invited_by_person_id"
    t.string "name", null: false
    t.integer "permission_level", default: 2, null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_group_invitations_on_email"
    t.index ["group_id"], name: "index_group_invitations_on_group_id"
    t.index ["token"], name: "index_group_invitations_on_token", unique: true
  end

  create_table "group_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "group_id", null: false
    t.text "notification_preferences"
    t.integer "permission_level", default: 0, null: false
    t.bigint "person_id", null: false
    t.boolean "show_on_profile", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["group_id", "person_id"], name: "index_group_memberships_on_group_id_and_person_id", unique: true
    t.index ["group_id"], name: "index_group_memberships_on_group_id"
    t.index ["person_id"], name: "index_group_memberships_on_person_id"
  end

  create_table "groups", force: :cascade do |t|
    t.datetime "archived_at"
    t.text "bio"
    t.boolean "bio_visible", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.boolean "headshots_visible", default: true, null: false
    t.boolean "hide_contact_info", default: true, null: false
    t.string "name", null: false
    t.text "old_keys"
    t.boolean "performance_credits_visible", default: true, null: false
    t.string "phone"
    t.text "profile_visibility_settings", default: "{}"
    t.string "public_key", null: false
    t.datetime "public_key_changed_at"
    t.boolean "public_profile_enabled", default: true, null: false
    t.boolean "resumes_visible", default: true, null: false
    t.boolean "social_media_visible", default: true, null: false
    t.datetime "updated_at", null: false
    t.boolean "videos_visible", default: true, null: false
    t.string "website"
    t.index ["archived_at"], name: "index_groups_on_archived_at"
    t.index ["created_at"], name: "index_groups_on_created_at"
    t.index ["name"], name: "index_groups_on_name"
    t.index ["public_key"], name: "index_groups_on_public_key", unique: true
  end

  create_table "groups_organizations", id: false, force: :cascade do |t|
    t.integer "group_id", null: false
    t.integer "organization_id", null: false
    t.index ["group_id", "organization_id"], name: "index_groups_organizations_on_group_id_and_organization_id", unique: true
    t.index ["group_id"], name: "index_groups_organizations_on_group_id"
    t.index ["organization_id"], name: "index_groups_organizations_on_organization_id"
  end

  create_table "house_roles", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.integer "default_flat_rate_cents"
    t.integer "default_hourly_rate_cents"
    t.integer "default_required_count", default: 1, null: false
    t.boolean "include_in_role_call", default: true, null: false
    t.bigint "location_id"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.string "pay_type", default: "hourly", null: false
    t.integer "position", default: 0, null: false
    t.integer "role_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_house_roles_on_location_id"
    t.index ["organization_id", "archived_at", "position"], name: "idx_house_roles_org_position"
    t.index ["organization_id"], name: "index_house_roles_on_organization_id"
  end

  create_table "journal_entries", force: :cascade do |t|
    t.date "cash_date"
    t.datetime "created_at", null: false
    t.date "entry_date", null: false
    t.string "kind", null: false
    t.string "memo"
    t.bigint "organization_id", null: false
    t.datetime "posted_at", null: false
    t.bigint "reversal_of_id"
    t.datetime "reversed_at"
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.index ["organization_id", "cash_date"], name: "index_journal_entries_on_organization_id_and_cash_date"
    t.index ["organization_id", "entry_date"], name: "index_journal_entries_on_organization_id_and_entry_date"
    t.index ["reversal_of_id"], name: "index_journal_entries_on_reversal_of_id"
    t.index ["source_type", "source_id", "kind"], name: "idx_journal_entries_one_live_per_source_kind", unique: true, where: "((reversed_at IS NULL) AND (reversal_of_id IS NULL))"
  end

  create_table "journal_lines", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.bigint "fund_id"
    t.bigint "journal_entry_id", null: false
    t.bigint "ledger_account_id", null: false
    t.string "memo"
    t.bigint "organization_id", null: false
    t.bigint "payee_id"
    t.string "payee_type"
    t.bigint "production_id"
    t.bigint "show_id"
    t.datetime "updated_at", null: false
    t.index ["fund_id"], name: "index_journal_lines_on_fund_id"
    t.index ["journal_entry_id"], name: "index_journal_lines_on_journal_entry_id"
    t.index ["ledger_account_id"], name: "index_journal_lines_on_ledger_account_id"
    t.index ["organization_id", "ledger_account_id"], name: "index_journal_lines_on_organization_id_and_ledger_account_id"
    t.index ["payee_type", "payee_id"], name: "index_journal_lines_on_payee_type_and_payee_id"
    t.index ["production_id"], name: "index_journal_lines_on_production_id"
    t.index ["show_id"], name: "index_journal_lines_on_show_id"
  end

  create_table "ledger_accounts", force: :cascade do |t|
    t.string "account_type", null: false
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "key"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.string "subtype"
    t.boolean "system", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "code"], name: "index_ledger_accounts_on_organization_id_and_code", unique: true
    t.index ["organization_id", "key"], name: "index_ledger_accounts_on_organization_id_and_key", unique: true, where: "(key IS NOT NULL)"
  end

  create_table "location_spaces", force: :cascade do |t|
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.text "description"
    t.bigint "location_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id", "default"], name: "index_location_spaces_one_default_per_location", unique: true, where: "(\"default\" = true)"
    t.index ["location_id"], name: "index_location_spaces_on_location_id"
  end

  create_table "locations", force: :cascade do |t|
    t.string "address1"
    t.string "address2"
    t.string "city"
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.string "name"
    t.text "notes"
    t.bigint "organization_id"
    t.string "postal_code"
    t.string "state"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_locations_on_organization_id"
  end

  create_table "message_poll_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "message_poll_id", null: false
    t.integer "position", default: 0, null: false
    t.string "text", null: false
    t.datetime "updated_at", null: false
    t.index ["message_poll_id", "position"], name: "index_message_poll_options_on_message_poll_id_and_position"
    t.index ["message_poll_id"], name: "index_message_poll_options_on_message_poll_id"
  end

  create_table "message_poll_votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "message_poll_option_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["message_poll_option_id", "user_id"], name: "idx_poll_votes_unique", unique: true
    t.index ["message_poll_option_id"], name: "index_message_poll_votes_on_message_poll_option_id"
    t.index ["user_id"], name: "index_message_poll_votes_on_user_id"
  end

  create_table "message_polls", force: :cascade do |t|
    t.boolean "anonymous", default: false, null: false
    t.boolean "closed", default: false, null: false
    t.datetime "closes_at"
    t.datetime "created_at", null: false
    t.integer "max_votes", default: 1, null: false
    t.bigint "message_id", null: false
    t.string "question", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_message_polls_on_message_id", unique: true
  end

  create_table "message_reactions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "emoji", null: false
    t.bigint "message_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["message_id", "user_id", "emoji"], name: "index_message_reactions_on_message_id_and_user_id_and_emoji", unique: true
    t.index ["message_id"], name: "index_message_reactions_on_message_id"
    t.index ["user_id", "message_id"], name: "index_message_reactions_on_user_id_and_message_id", unique: true
    t.index ["user_id"], name: "index_message_reactions_on_user_id"
  end

  create_table "message_recipients", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.bigint "message_id", null: false
    t.datetime "read_at"
    t.bigint "recipient_id", null: false
    t.string "recipient_type", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "recipient_type", "recipient_id"], name: "idx_message_recipients_unique", unique: true
    t.index ["message_id"], name: "index_message_recipients_on_message_id"
    t.index ["recipient_type", "recipient_id", "read_at"], name: "idx_message_recipients_unread"
    t.index ["recipient_type", "recipient_id"], name: "index_message_recipients_on_recipient"
  end

  create_table "message_regards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "message_id", null: false
    t.integer "regardable_id", null: false
    t.string "regardable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "regardable_type", "regardable_id"], name: "index_message_regards_unique", unique: true
    t.index ["message_id"], name: "index_message_regards_on_message_id"
    t.index ["regardable_type", "regardable_id"], name: "index_message_regards_on_regardable"
  end

  create_table "message_subscriptions", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "last_read_at"
    t.bigint "message_id", null: false
    t.boolean "muted", default: false, null: false
    t.integer "unread_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["message_id", "muted"], name: "index_message_subscriptions_on_message_id_and_muted"
    t.index ["message_id"], name: "index_message_subscriptions_on_message_id"
    t.index ["user_id", "archived_at"], name: "index_message_subscriptions_on_user_id_and_archived_at"
    t.index ["user_id", "message_id"], name: "index_message_subscriptions_on_user_id_and_message_id", unique: true
    t.index ["user_id", "unread_count"], name: "index_message_subscriptions_on_user_id_and_unread_count"
    t.index ["user_id"], name: "index_message_subscriptions_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "message_type", null: false
    t.bigint "organization_id"
    t.integer "parent_message_id"
    t.bigint "production_id"
    t.bigint "sender_id"
    t.string "sender_type"
    t.bigint "show_id"
    t.boolean "skip_digest", default: false, null: false
    t.string "subject", null: false
    t.boolean "system_generated", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "private", null: false
    t.index ["parent_message_id"], name: "index_messages_on_parent_message_id"
    t.index ["production_id"], name: "index_messages_on_production_id"
    t.index ["sender_type", "sender_id"], name: "idx_messages_sender"
    t.index ["show_id"], name: "index_messages_on_show_id"
    t.index ["visibility", "production_id"], name: "idx_messages_visibility_production"
    t.index ["visibility", "show_id"], name: "idx_messages_visibility_show"
  end

  create_table "mic_announcements", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.bigint "mic_id", null: false
    t.boolean "notify_subscribers", default: false, null: false
    t.datetime "posted_at", null: false
    t.bigint "posted_by_user_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["mic_id", "posted_at"], name: "index_mic_announcements_on_mic_id_and_posted_at"
    t.index ["mic_id"], name: "index_mic_announcements_on_mic_id"
  end

  create_table "mic_challenges", force: :cascade do |t|
    t.bigint "adjudicator_user_id"
    t.bigint "challenger_user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.jsonb "evidence", default: {}, null: false
    t.bigint "mic_id", null: false
    t.text "reason"
    t.integer "status", default: 0, null: false
    t.bigint "target_user_id"
    t.datetime "updated_at", null: false
    t.index ["challenger_user_id"], name: "index_mic_challenges_on_challenger_user_id"
    t.index ["mic_id"], name: "index_mic_challenges_on_mic_id"
    t.index ["status"], name: "index_mic_challenges_on_status"
  end

  create_table "mic_claims", force: :cascade do |t|
    t.bigint "adjudicator_user_id"
    t.bigint "claimant_user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.bigint "mic_id", null: false
    t.jsonb "proof", default: {}, null: false
    t.text "reason"
    t.integer "role", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["claimant_user_id"], name: "index_mic_claims_on_claimant_user_id"
    t.index ["mic_id"], name: "index_mic_claims_on_mic_id"
    t.index ["status"], name: "index_mic_claims_on_status"
  end

  create_table "mic_edits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "editor_user_id"
    t.string "field"
    t.bigint "mic_id", null: false
    t.text "new_value"
    t.text "note"
    t.text "old_value"
    t.integer "source", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["editor_user_id"], name: "index_mic_edits_on_editor_user_id"
    t.index ["mic_id"], name: "index_mic_edits_on_mic_id"
  end

  create_table "mic_favorites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "mic_id", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["mic_id"], name: "index_mic_favorites_on_mic_id"
    t.index ["user_id", "mic_id"], name: "index_mic_favorites_on_user_id_and_mic_id", unique: true
  end

  create_table "mic_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "label"
    t.integer "link_type", default: 0, null: false
    t.bigint "mic_id", null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["mic_id", "link_type"], name: "index_mic_links_on_mic_id_and_link_type"
    t.index ["mic_id"], name: "index_mic_links_on_mic_id"
  end

  create_table "mic_occurrence_statuses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.bigint "mic_id", null: false
    t.text "note"
    t.date "occurs_on", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["mic_id", "occurs_on"], name: "index_mic_occurrence_statuses_on_mic_id_and_occurs_on", unique: true
    t.index ["mic_id"], name: "index_mic_occurrence_statuses_on_mic_id"
  end

  create_table "mic_owners", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.bigint "mic_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["mic_id", "user_id"], name: "index_mic_owners_on_mic_id_and_user_id", unique: true
    t.index ["mic_id"], name: "index_mic_owners_on_mic_id"
    t.index ["user_id"], name: "index_mic_owners_on_user_id"
  end

  create_table "mic_signup_alerts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.jsonb "channels", default: ["email"], null: false
    t.datetime "created_at", null: false
    t.integer "lead_time_minutes", default: 5, null: false
    t.bigint "mic_id", null: false
    t.datetime "next_target_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["mic_id"], name: "index_mic_signup_alerts_on_mic_id"
    t.index ["next_target_at"], name: "index_mic_signup_alerts_on_next_target_at", where: "(active = true)"
    t.index ["user_id", "mic_id"], name: "index_mic_signup_alerts_on_user_id_and_mic_id", unique: true
  end

  create_table "mic_suggestions", force: :cascade do |t|
    t.bigint "adjudicator_user_id"
    t.datetime "created_at", null: false
    t.datetime "decided_at"
    t.bigint "mic_id", null: false
    t.text "note"
    t.jsonb "payload", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.string "submitter_email"
    t.bigint "submitter_user_id"
    t.datetime "updated_at", null: false
    t.index ["mic_id"], name: "index_mic_suggestions_on_mic_id"
    t.index ["status"], name: "index_mic_suggestions_on_status"
  end

  create_table "mic_taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "mic_id", null: false
    t.bigint "mic_tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["mic_id", "mic_tag_id"], name: "index_mic_taggings_on_mic_id_and_mic_tag_id", unique: true
    t.index ["mic_id"], name: "index_mic_taggings_on_mic_id"
    t.index ["mic_tag_id"], name: "index_mic_taggings_on_mic_tag_id"
  end

  create_table "mic_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_mic_tags_on_slug", unique: true
  end

  create_table "mics", force: :cascade do |t|
    t.jsonb "accessibility", default: {}, null: false
    t.integer "age_requirement", default: 0, null: false
    t.text "blurb"
    t.boolean "bucket_draw", default: false, null: false
    t.date "canceled_until"
    t.datetime "claimed_at"
    t.integer "cost", default: 0, null: false
    t.integer "cover_amount_cents"
    t.datetime "created_at", null: false
    t.jsonb "custom_dates", default: [], null: false
    t.integer "day_of_week"
    t.integer "drink_minimum_amount_cents"
    t.integer "format", default: 0, null: false
    t.string "host_summary"
    t.datetime "last_verified_at"
    t.bigint "last_verified_by_user_id"
    t.bigint "lead_owner_user_id"
    t.integer "min_age"
    t.string "name", null: false
    t.text "pause_note"
    t.boolean "paused", default: false, null: false
    t.boolean "pending", default: false, null: false
    t.bigint "production_id"
    t.date "recurrence_anchor_date"
    t.integer "recurrence_day_of_month"
    t.integer "recurrence_interval", default: 1, null: false
    t.integer "recurrence_nth_week"
    t.jsonb "recurrence_nth_weeks", default: [], null: false
    t.integer "recurrence_pattern", default: 0, null: false
    t.string "signup_cap"
    t.integer "signup_method"
    t.text "signup_notes"
    t.string "signup_opens_at_text"
    t.string "signup_url"
    t.string "slug", null: false
    t.string "spot_length_minutes"
    t.time "starts_local_time"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "venue_id", null: false
    t.index ["age_requirement"], name: "index_mics_on_age_requirement"
    t.index ["lead_owner_user_id"], name: "index_mics_on_lead_owner_user_id"
    t.index ["paused"], name: "index_mics_on_paused"
    t.index ["pending"], name: "index_mics_on_pending", where: "(pending = true)"
    t.index ["production_id"], name: "index_mics_on_production_id", unique: true, where: "(production_id IS NOT NULL)"
    t.index ["slug"], name: "index_mics_on_slug", unique: true
    t.index ["status"], name: "index_mics_on_status"
    t.index ["venue_id"], name: "index_mics_on_venue_id"
  end

  create_table "org_cash_entries", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "usd", null: false
    t.string "description"
    t.string "entry_type", null: false
    t.datetime "occurred_at", null: false
    t.bigint "organization_id", null: false
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.index ["organization_id", "entry_type"], name: "index_org_cash_entries_on_organization_id_and_entry_type"
    t.index ["organization_id"], name: "index_org_cash_entries_on_organization_id"
    t.index ["source_type", "source_id", "entry_type"], name: "index_org_cash_entries_on_source_and_type", unique: true, where: "(source_id IS NOT NULL)"
  end

  create_table "org_payouts", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.bigint "course_offering_id"
    t.jsonb "covers_sessions", default: []
    t.datetime "created_at", null: false
    t.text "notes"
    t.bigint "organization_id", null: false
    t.datetime "paid_at"
    t.bigint "paid_by_user_id"
    t.string "payment_method", null: false
    t.string "payout_type", default: "custom", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["course_offering_id"], name: "index_org_payouts_on_course_offering_id"
    t.index ["organization_id"], name: "index_org_payouts_on_organization_id"
    t.index ["paid_by_user_id"], name: "index_org_payouts_on_paid_by_user_id"
    t.index ["payout_type"], name: "index_org_payouts_on_payout_type"
    t.index ["status"], name: "index_org_payouts_on_status"
  end

  create_table "org_statements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "emailed_at"
    t.datetime "generated_at"
    t.date "month", null: false
    t.bigint "organization_id", null: false
    t.jsonb "totals", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "month"], name: "index_org_statements_on_organization_id_and_month", unique: true
    t.index ["organization_id"], name: "index_org_statements_on_organization_id"
  end

  create_table "organization_roles", force: :cascade do |t|
    t.string "company_role", null: false
    t.datetime "created_at", null: false
    t.bigint "organization_id", null: false
    t.bigint "person_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["organization_id"], name: "index_organization_roles_on_organization_id"
    t.index ["user_id", "organization_id"], name: "index_organization_roles_on_user_id_and_organization_id", unique: true
    t.index ["user_id"], name: "index_organization_roles_on_user_id"
  end

  create_table "organization_staff_members", force: :cascade do |t|
    t.datetime "acknowledged_at"
    t.integer "agreed_agreement_version"
    t.boolean "agreement_exempt", default: false, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "department"
    t.boolean "excluded_from_pay", default: false, null: false
    t.string "first_name"
    t.integer "hourly_rate_cents"
    t.string "last_name"
    t.bigint "manager_id"
    t.string "middle_initial"
    t.string "onboarding_state", default: "added", null: false
    t.bigint "organization_id", null: false
    t.bigint "person_id", null: false
    t.string "personal_email"
    t.string "preferred_first_name"
    t.string "pronouns"
    t.bigint "staff_agreement_template_id"
    t.date "start_date"
    t.boolean "tax_form_exempt", default: false, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.datetime "w9_last_reminded_at"
    t.datetime "w9_requested_at"
    t.index ["manager_id"], name: "index_organization_staff_members_on_manager_id"
    t.index ["organization_id", "archived_at"], name: "idx_org_staff_members_org_archived"
    t.index ["organization_id", "person_id"], name: "idx_org_staff_members_unique", unique: true
    t.index ["organization_id"], name: "index_organization_staff_members_on_organization_id"
    t.index ["person_id"], name: "index_organization_staff_members_on_person_id"
    t.index ["staff_agreement_template_id"], name: "idx_on_staff_agreement_template_id_99dbeb01ea"
  end

  create_table "organization_tax_settings", force: :cascade do |t|
    t.string "address_line1"
    t.string "address_line2"
    t.string "city"
    t.datetime "created_at", null: false
    t.text "ein"
    t.string "ein_last4"
    t.string "legal_name"
    t.bigint "organization_id", null: false
    t.string "phone"
    t.string "state"
    t.datetime "updated_at", null: false
    t.boolean "w9_required", default: true, null: false
    t.string "zip"
    t.index ["organization_id"], name: "index_organization_tax_settings_on_organization_id", unique: true
  end

  create_table "organizations", force: :cascade do |t|
    t.boolean "alert_uncovered_show_roles", default: false, null: false
    t.boolean "comped_indefinitely", default: false, null: false
    t.datetime "comped_until"
    t.boolean "comped_usage", default: false, null: false
    t.jsonb "contract_notification_user_ids", default: [], null: false
    t.integer "course_reminder_days_before", default: 2
    t.datetime "created_at", null: false
    t.jsonb "default_contract_payment_methods", default: ["online"], null: false
    t.jsonb "enabled_offline_payout_methods", default: [], null: false
    t.string "funding_payment_method_id"
    t.string "funding_payment_method_label"
    t.string "funding_payment_method_type"
    t.jsonb "invoice_details", default: {}, null: false
    t.integer "invoice_next_number", default: 1, null: false
    t.string "invoice_prefix"
    t.string "invite_token"
    t.boolean "is_demo", default: false, null: false
    t.date "last_auto_payout_on"
    t.string "name"
    t.bigint "organization_talent_pool_id"
    t.bigint "owner_id", null: false
    t.string "payout_funding_method", default: "ach", null: false
    t.jsonb "payout_notification_user_ids", default: [], null: false
    t.string "payout_schedule", default: "manual", null: false
    t.integer "payout_schedule_day"
    t.boolean "payouts_enabled", default: false, null: false
    t.string "referral_source"
    t.bigint "required_staff_agreement_template_id"
    t.integer "signature_expiry_days", default: 14, null: false
    t.jsonb "staffing_day_parts", default: [], null: false
    t.jsonb "staffing_notification_user_ids", default: [], null: false
    t.boolean "staffing_regulars_enabled", default: false, null: false
    t.string "staffing_subscription_id"
    t.string "stripe_account_id"
    t.string "stripe_account_status"
    t.datetime "stripe_account_synced_at"
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.datetime "subscription_canceled_at"
    t.datetime "subscription_current_period_end"
    t.string "subscription_interval"
    t.string "subscription_status"
    t.string "subscription_tier", default: "free", null: false
    t.string "talent_pool_mode", default: "per_production", null: false
    t.datetime "updated_at", null: false
    t.index ["invite_token"], name: "index_organizations_on_invite_token", unique: true
    t.index ["organization_talent_pool_id"], name: "index_organizations_on_organization_talent_pool_id"
    t.index ["owner_id"], name: "index_organizations_on_owner_id"
    t.index ["referral_source"], name: "index_organizations_on_referral_source"
    t.index ["required_staff_agreement_template_id"], name: "index_organizations_on_required_staff_agreement_template_id"
    t.index ["staffing_subscription_id"], name: "index_organizations_on_staffing_subscription_id"
    t.index ["stripe_account_id"], name: "index_organizations_on_stripe_account_id", unique: true, where: "(stripe_account_id IS NOT NULL)"
    t.index ["stripe_customer_id"], name: "index_organizations_on_stripe_customer_id"
    t.index ["stripe_subscription_id"], name: "index_organizations_on_stripe_subscription_id"
    t.index ["talent_pool_mode"], name: "index_organizations_on_talent_pool_mode"
  end

  create_table "organizations_people", id: false, force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "person_id", null: false
    t.index ["organization_id", "person_id"], name: "index_organizations_people_on_organization_id_and_person_id"
    t.index ["person_id", "organization_id"], name: "index_organizations_people_on_person_id_and_organization_id"
  end

  create_table "payout_batch_items", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.text "error"
    t.datetime "paid_at"
    t.bigint "payee_id", null: false
    t.datetime "payee_notified_at"
    t.string "payee_type", null: false
    t.bigint "payout_batch_id", null: false
    t.string "status", default: "pending", null: false
    t.string "stripe_transfer_id"
    t.datetime "updated_at", null: false
    t.index ["payee_type", "payee_id"], name: "index_payout_batch_items_on_payee_type_and_payee_id"
    t.index ["payout_batch_id", "status"], name: "idx_payout_batch_items_batch_status"
    t.index ["payout_batch_id"], name: "index_payout_batch_items_on_payout_batch_id"
  end

  create_table "payout_batches", force: :cascade do |t|
    t.integer "balance_applied_cents", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.bigint "credit_applied_cents", default: 0, null: false
    t.integer "funding_attempts", default: 0, null: false
    t.string "funding_payment_intent_id"
    t.string "funding_status"
    t.string "kind", default: "balance", null: false
    t.bigint "organization_id", null: false
    t.date "payday"
    t.string "status", default: "draft", null: false
    t.bigint "total_cents", default: 0, null: false
    t.string "trigger", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_payout_batches_on_created_by_id"
    t.index ["organization_id", "status"], name: "idx_payout_batches_org_status"
    t.index ["organization_id"], name: "idx_payout_batches_one_open_run_per_org", unique: true, where: "(((status)::text = 'draft'::text) AND ((kind)::text <> 'course'::text))"
    t.index ["organization_id"], name: "index_payout_batches_on_organization_id"
  end

  create_table "payout_contributions", force: :cascade do |t|
    t.bigint "amount_cents", default: 0, null: false
    t.string "category", default: "performer", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.jsonb "details"
    t.boolean "excluded_from_payout", default: false, null: false
    t.string "label", null: false
    t.bigint "payee_id", null: false
    t.string "payee_type", null: false
    t.bigint "payout_batch_id", null: false
    t.bigint "payout_batch_item_id", null: false
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.jsonb "worksheet"
    t.index ["payee_type", "payee_id"], name: "index_payout_contributions_on_payee"
    t.index ["payout_batch_id"], name: "index_payout_contributions_on_payout_batch_id"
    t.index ["payout_batch_item_id"], name: "index_payout_contributions_on_payout_batch_item_id"
    t.index ["source_type", "source_id"], name: "index_payout_contributions_on_source"
    t.index ["source_type", "source_id"], name: "index_payout_contributions_on_source_unique", unique: true, where: "(source_id IS NOT NULL)"
  end

  create_table "payout_funding_credits", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.bigint "consumed_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "note"
    t.bigint "organization_id", null: false
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_payout_funding_credits_on_organization_id"
    t.index ["source_type", "source_id"], name: "index_payout_funding_credits_on_source"
  end

  create_table "payout_ledger_entries", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.string "category", default: "performer", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "usd", null: false
    t.string "description"
    t.string "entry_type", null: false
    t.datetime "occurred_at", null: false
    t.bigint "organization_id", null: false
    t.bigint "payee_id", null: false
    t.string "payee_type", null: false
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "updated_at", null: false
    t.index ["organization_id", "payee_type", "payee_id"], name: "index_payout_ledger_entries_on_org_and_payee"
    t.index ["organization_id"], name: "index_payout_ledger_entries_on_organization_id"
    t.index ["payee_type", "payee_id", "category"], name: "idx_ledger_entries_on_payee_and_category"
    t.index ["source_type", "source_id", "entry_type", "category"], name: "index_payout_ledger_entries_on_source_type_and_category", unique: true, where: "(source_id IS NOT NULL)"
  end

  create_table "payout_scheme_defaults", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "effective_from"
    t.bigint "payout_scheme_id", null: false
    t.bigint "production_id", null: false
    t.datetime "updated_at", null: false
    t.index ["payout_scheme_id", "production_id"], name: "idx_payout_defaults_scheme_prod"
    t.index ["payout_scheme_id"], name: "index_payout_scheme_defaults_on_payout_scheme_id"
    t.index ["production_id", "effective_from"], name: "idx_payout_defaults_prod_date", unique: true, where: "(production_id IS NOT NULL)"
    t.index ["production_id"], name: "index_payout_scheme_defaults_on_production_id"
  end

  create_table "payout_schemes", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.date "effective_from"
    t.boolean "is_default", default: false
    t.string "name", null: false
    t.bigint "organization_id"
    t.bigint "production_id"
    t.jsonb "rules", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "effective_from"], name: "index_payout_schemes_on_organization_id_and_effective_from"
    t.index ["organization_id", "is_default"], name: "index_payout_schemes_on_organization_id_and_is_default"
    t.index ["organization_id"], name: "index_payout_schemes_on_organization_id"
    t.index ["production_id", "effective_from"], name: "index_payout_schemes_on_production_id_and_effective_from"
    t.index ["production_id", "is_default"], name: "index_payout_schemes_on_production_id_and_is_default"
    t.index ["production_id"], name: "index_payout_schemes_on_production_id"
  end

  create_table "people", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "availability_confirmed_at"
    t.date "availability_confirmed_through"
    t.text "bio"
    t.boolean "bio_visible", default: true, null: false
    t.datetime "casting_notification_sent_at"
    t.datetime "created_at", null: false
    t.string "email"
    t.boolean "headshots_visible", default: true, null: false
    t.boolean "hide_contact_info", default: true, null: false
    t.datetime "last_email_changed_at"
    t.datetime "last_public_key_changed_at"
    t.string "name"
    t.integer "notified_for_audition_cycle_id"
    t.text "old_keys"
    t.boolean "payouts_enabled", default: false, null: false
    t.boolean "performance_credits_visible", default: true, null: false
    t.string "phone"
    t.boolean "profile_skills_visible", default: true, null: false
    t.text "profile_visibility_settings", default: "{}"
    t.string "pronouns"
    t.string "public_key"
    t.datetime "public_key_changed_at"
    t.boolean "public_profile_enabled", default: true, null: false
    t.boolean "resumes_visible", default: true, null: false
    t.boolean "social_media_visible", default: true, null: false
    t.string "stripe_account_id"
    t.string "stripe_account_status"
    t.datetime "stripe_account_synced_at"
    t.boolean "training_credits_visible", default: true, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.boolean "videos_visible", default: true, null: false
    t.index ["archived_at"], name: "index_people_on_archived_at"
    t.index ["created_at"], name: "index_people_on_created_at"
    t.index ["email"], name: "index_people_on_email"
    t.index ["name"], name: "index_people_on_name"
    t.index ["public_key"], name: "index_people_on_public_key", unique: true
    t.index ["stripe_account_id"], name: "index_people_on_stripe_account_id", unique: true, where: "(stripe_account_id IS NOT NULL)"
    t.index ["user_id"], name: "index_people_on_user_id"
  end

  create_table "performance_credits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "link_url"
    t.string "location", limit: 100
    t.text "notes"
    t.boolean "ongoing", default: false, null: false
    t.bigint "performance_section_id"
    t.integer "position", default: 0, null: false
    t.bigint "profileable_id", null: false
    t.string "profileable_type", null: false
    t.string "role", limit: 100
    t.string "section_name", limit: 50
    t.string "title", limit: 200, null: false
    t.datetime "updated_at", null: false
    t.integer "year_end"
    t.integer "year_start", null: false
    t.index ["performance_section_id"], name: "index_performance_credits_on_performance_section_id"
    t.index ["profileable_type", "profileable_id", "section_name", "position"], name: "index_performance_credits_on_profileable_and_section"
    t.index ["profileable_type", "profileable_id"], name: "index_performance_credits_on_profileable"
  end

  create_table "performance_sections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.bigint "profileable_id", null: false
    t.string "profileable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["profileable_type", "profileable_id", "position"], name: "idx_on_profileable_type_profileable_id_position_59d6099064"
    t.index ["profileable_type", "profileable_id"], name: "index_performance_sections_on_profileable"
  end

  create_table "performer_activations", force: :cascade do |t|
    t.date "billing_month", null: false
    t.datetime "created_at", null: false
    t.datetime "first_activated_at"
    t.bigint "organization_id", null: false
    t.bigint "person_id", null: false
    t.datetime "reported_at"
    t.datetime "updated_at", null: false
    t.index ["organization_id", "person_id", "billing_month"], name: "idx_performer_activations_unique", unique: true
    t.index ["organization_id"], name: "index_performer_activations_on_organization_id"
    t.index ["person_id"], name: "index_performer_activations_on_person_id"
  end

  create_table "person_advances", force: :cascade do |t|
    t.string "advance_type", default: "show", null: false
    t.datetime "created_at", null: false
    t.datetime "fully_recovered_at"
    t.datetime "issued_at", null: false
    t.bigint "issued_by_id", null: false
    t.text "notes"
    t.decimal "original_amount", precision: 10, scale: 2, null: false
    t.datetime "paid_at"
    t.bigint "paid_by_id"
    t.string "payment_method"
    t.bigint "person_id", null: false
    t.bigint "production_id", null: false
    t.decimal "remaining_balance", precision: 10, scale: 2, null: false
    t.bigint "show_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["issued_by_id"], name: "index_person_advances_on_issued_by_id"
    t.index ["paid_by_id"], name: "index_person_advances_on_paid_by_id"
    t.index ["person_id", "production_id", "status"], name: "idx_on_person_id_production_id_status_414a71ca7e"
    t.index ["person_id"], name: "index_person_advances_on_person_id"
    t.index ["production_id"], name: "index_person_advances_on_production_id"
    t.index ["show_id"], name: "index_person_advances_on_show_id_partial", where: "(show_id IS NOT NULL)"
  end

  create_table "person_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "declined_at"
    t.string "email", null: false
    t.bigint "organization_id"
    t.bigint "talent_pool_id"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_person_invitations_on_organization_id"
    t.index ["talent_pool_id"], name: "index_person_invitations_on_talent_pool_id"
    t.index ["token"], name: "index_person_invitations_on_token", unique: true
  end

  create_table "platform_reconciliations", force: :cascade do |t|
    t.datetime "checked_at", null: false
    t.date "checked_on", null: false
    t.bigint "cocoscout_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}, null: false
    t.bigint "difference_cents"
    t.integer "failed_webhook_count", default: 0, null: false
    t.bigint "held_for_orgs_cents", default: 0, null: false
    t.bigint "imported_net_cents", default: 0, null: false
    t.integer "mismatch_count", default: 0, null: false
    t.bigint "stripe_balance_cents"
    t.integer "unmatched_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["checked_on"], name: "index_platform_reconciliations_on_checked_on", unique: true
  end

  create_table "posters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_primary", default: false, null: false
    t.string "name"
    t.bigint "production_id", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id", "is_primary"], name: "index_posters_on_production_id_primary", unique: true, where: "(is_primary = true)"
    t.index ["production_id"], name: "index_posters_on_production_id"
  end

  create_table "production_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.bigint "production_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id", "position"], name: "index_production_documents_on_production_id_and_position"
    t.index ["production_id"], name: "index_production_documents_on_production_id"
  end

  create_table "production_expense_allocations", force: :cascade do |t|
    t.decimal "allocated_amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.boolean "is_override", default: false
    t.text "override_reason"
    t.bigint "production_expense_id", null: false
    t.bigint "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["production_expense_id", "show_id"], name: "idx_prod_exp_alloc_unique", unique: true
    t.index ["production_expense_id"], name: "index_production_expense_allocations_on_production_expense_id"
    t.index ["show_id"], name: "index_production_expense_allocations_on_show_id"
  end

  create_table "production_expenses", force: :cascade do |t|
    t.boolean "active", default: true
    t.string "category", default: "other"
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "event_type_filter", default: []
    t.boolean "exclude_canceled", default: true
    t.boolean "exclude_non_revenue", default: true
    t.string "name", null: false
    t.bigint "production_id", null: false
    t.date "purchase_date"
    t.jsonb "selected_show_ids", default: []
    t.date "spread_end_date"
    t.integer "spread_event_count"
    t.string "spread_method", default: "fixed_months", null: false
    t.integer "spread_months"
    t.date "spread_start_date"
    t.decimal "total_amount", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["production_id", "active"], name: "index_production_expenses_on_production_id_and_active"
    t.index ["production_id"], name: "index_production_expenses_on_production_id"
  end

  create_table "production_notification_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: false, null: false
    t.bigint "production_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["production_id", "user_id"], name: "idx_prod_notif_settings_on_prod_and_user", unique: true
    t.index ["production_id"], name: "index_production_notification_settings_on_production_id"
    t.index ["user_id"], name: "index_production_notification_settings_on_user_id"
  end

  create_table "production_permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "production_id", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["production_id"], name: "index_production_permissions_on_production_id"
    t.index ["user_id", "production_id"], name: "index_production_permissions_on_user_id_and_production_id", unique: true
    t.index ["user_id"], name: "index_production_permissions_on_user_id"
  end

  create_table "production_ticketing_products", force: :cascade do |t|
    t.boolean "counts_toward_ticket_revenue"
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_cents"
    t.bigint "production_ticketing_id", null: false
    t.bigint "ticket_product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["production_ticketing_id", "ticket_product_id"], name: "idx_production_ticketing_products_unique", unique: true
    t.index ["production_ticketing_id"], name: "index_production_ticketing_products_on_production_ticketing_id"
    t.index ["ticket_product_id"], name: "index_production_ticketing_products_on_ticket_product_id"
  end

  create_table "production_ticketing_shows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "production_ticketing_id", null: false
    t.bigint "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["production_ticketing_id", "show_id"], name: "index_production_ticketing_shows_once", unique: true
    t.index ["production_ticketing_id"], name: "index_production_ticketing_shows_on_production_ticketing_id"
    t.index ["show_id"], name: "index_production_ticketing_shows_on_show_id"
  end

  create_table "production_ticketings", force: :cascade do |t|
    t.string "accessibility_note"
    t.string "age_note"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "door_note"
    t.boolean "enabled", default: false, null: false
    t.string "event_matching", default: "all", null: false
    t.jsonb "event_type_filter", default: [], null: false
    t.string "fee_mode"
    t.integer "low_stock_threshold"
    t.integer "max_per_order"
    t.integer "online_close_minutes", default: 0, null: false
    t.integer "opens_days_before", default: 30, null: false
    t.bigint "organization_id", null: false
    t.boolean "own_product_prices", default: false, null: false
    t.bigint "production_id", null: false
    t.boolean "products_at_door", default: false, null: false
    t.string "schedule_mode", default: "relative", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_production_ticketings_on_organization_id"
    t.index ["production_id"], name: "index_production_ticketings_on_production_id", unique: true
  end

  create_table "productions", force: :cascade do |t|
    t.boolean "agreement_auto_send", default: false, null: false
    t.boolean "agreement_required", default: false, null: false
    t.bigint "agreement_template_id"
    t.datetime "archived_at"
    t.boolean "auto_create_event_pages", default: true
    t.string "auto_create_event_pages_mode", default: "all"
    t.text "cast_talent_pool_ids"
    t.string "casting_mode", default: "role_based", null: false
    t.boolean "casting_setup_completed", default: false, null: false
    t.string "casting_source", default: "talent_pool", null: false
    t.string "contact_email"
    t.datetime "created_at", null: false
    t.boolean "default_attendance_enabled", default: false, null: false
    t.boolean "default_signup_based_casting", default: false, null: false
    t.text "description"
    t.text "event_visibility_overrides"
    t.string "genre"
    t.string "name"
    t.text "old_keys"
    t.integer "organization_id", null: false
    t.boolean "pays_performers", default: true, null: false
    t.string "production_type", default: "in_house", null: false
    t.string "public_key"
    t.datetime "public_key_changed_at"
    t.boolean "public_profile_enabled", default: true
    t.boolean "show_cast_members", default: true, null: false
    t.text "show_upcoming_event_types"
    t.boolean "show_upcoming_events", default: true, null: false
    t.string "show_upcoming_events_mode", default: "all"
    t.datetime "updated_at", null: false
    t.index ["agreement_template_id"], name: "index_productions_on_agreement_template_id"
    t.index ["archived_at"], name: "index_productions_on_archived_at"
    t.index ["casting_mode"], name: "index_productions_on_casting_mode"
    t.index ["casting_source"], name: "index_productions_on_casting_source"
    t.index ["genre"], name: "index_productions_on_genre"
    t.index ["organization_id", "archived_at"], name: "idx_productions_org_archived"
    t.index ["organization_id"], name: "index_productions_on_organization_id"
    t.index ["production_type"], name: "index_productions_on_production_type"
    t.index ["public_key"], name: "index_productions_on_public_key", unique: true
  end

  create_table "profile_headshots", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.boolean "is_primary", default: false, null: false
    t.integer "position", default: 0, null: false
    t.bigint "profileable_id", null: false
    t.string "profileable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["profileable_type", "profileable_id", "position"], name: "idx_on_profileable_type_profileable_id_position_66776b16f6"
    t.index ["profileable_type", "profileable_id"], name: "index_profile_headshots_on_profileable"
  end

  create_table "profile_resumes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_primary", default: false, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.bigint "profileable_id", null: false
    t.string "profileable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["profileable_type", "profileable_id", "position"], name: "idx_on_profileable_type_profileable_id_position_656777844d"
    t.index ["profileable_type", "profileable_id"], name: "index_profile_resumes_on_profileable"
  end

  create_table "profile_skills", force: :cascade do |t|
    t.string "category", limit: 50, null: false
    t.datetime "created_at", null: false
    t.bigint "profileable_id", null: false
    t.string "profileable_type", null: false
    t.string "skill_name", limit: 50, null: false
    t.datetime "updated_at", null: false
    t.index ["profileable_type", "profileable_id", "category", "skill_name"], name: "index_profile_skills_unique", unique: true
    t.index ["profileable_type", "profileable_id"], name: "index_profile_skills_on_profileable"
  end

  create_table "profile_videos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.bigint "profileable_id", null: false
    t.string "profileable_type", null: false
    t.string "title", limit: 100
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.integer "video_type", default: 2, null: false
    t.index ["profileable_type", "profileable_id", "position"], name: "idx_on_profileable_type_profileable_id_position_7b4c262cd5"
    t.index ["profileable_type", "profileable_id"], name: "index_profile_videos_on_profileable"
  end

  create_table "question_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "question_id", null: false
    t.string "text"
    t.datetime "updated_at", null: false
    t.index ["question_id"], name: "index_question_options_on_question_id"
  end

  create_table "questionnaire_answers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "question_id", null: false
    t.bigint "questionnaire_response_id", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["question_id"], name: "index_questionnaire_answers_on_question_id"
    t.index ["questionnaire_response_id", "question_id"], name: "index_q_answers_on_response_and_question", unique: true
    t.index ["questionnaire_response_id"], name: "index_questionnaire_answers_on_questionnaire_response_id"
  end

  create_table "questionnaire_invitations", force: :cascade do |t|
    t.bigint "context_id"
    t.string "context_type"
    t.datetime "created_at", null: false
    t.integer "invitee_id"
    t.string "invitee_type"
    t.bigint "questionnaire_id", null: false
    t.datetime "updated_at", null: false
    t.index ["context_type", "context_id"], name: "index_questionnaire_invitations_on_context_type_and_context_id"
    t.index ["invitee_type", "invitee_id", "questionnaire_id", "context_type", "context_id"], name: "index_q_invitations_unique_with_context", unique: true
    t.index ["invitee_type", "invitee_id"], name: "index_questionnaire_invitations_on_invitee_type_and_invitee_id"
    t.index ["questionnaire_id"], name: "index_questionnaire_invitations_on_questionnaire_id"
  end

  create_table "questionnaire_responses", force: :cascade do |t|
    t.bigint "context_id"
    t.string "context_type"
    t.datetime "created_at", null: false
    t.bigint "questionnaire_id", null: false
    t.integer "respondent_id"
    t.string "respondent_type"
    t.datetime "updated_at", null: false
    t.index ["context_type", "context_id"], name: "index_questionnaire_responses_on_context_type_and_context_id"
    t.index ["questionnaire_id"], name: "index_questionnaire_responses_on_questionnaire_id"
    t.index ["respondent_type", "respondent_id", "questionnaire_id", "context_type", "context_id"], name: "index_q_responses_unique_with_context", unique: true
    t.index ["respondent_type", "respondent_id"], name: "idx_on_respondent_type_respondent_id_7f07f0f816"
  end

  create_table "questionnaires", force: :cascade do |t|
    t.boolean "accepting_responses", default: true, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.bigint "organization_id", null: false
    t.bigint "production_id"
    t.string "title", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_questionnaires_on_organization_id"
    t.index ["production_id", "title"], name: "index_questionnaires_on_production_id_and_title"
    t.index ["production_id"], name: "index_questionnaires_on_production_id"
    t.index ["token"], name: "index_questionnaires_on_token", unique: true
  end

  create_table "questions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position"
    t.string "question_type"
    t.integer "questionable_id", null: false
    t.string "questionable_type", null: false
    t.boolean "required", default: false, null: false
    t.string "text"
    t.datetime "updated_at", null: false
    t.index ["questionable_type", "questionable_id", "position"], name: "idx_qstnbl_type_id_pos"
    t.index ["questionable_type", "questionable_id"], name: "index_questions_on_questionable"
  end

  create_table "role_eligibilities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "member_id", null: false
    t.string "member_type", null: false
    t.bigint "role_id", null: false
    t.datetime "updated_at", null: false
    t.index ["member_id"], name: "index_role_eligibilities_on_member_id"
    t.index ["role_id", "member_type", "member_id"], name: "index_role_eligibilities_on_role_and_member", unique: true
    t.index ["role_id"], name: "index_role_eligibilities_on_role_id"
  end

  create_table "role_vacancies", force: :cascade do |t|
    t.datetime "closed_at"
    t.integer "closed_by_id"
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.datetime "filled_at"
    t.integer "filled_by_id"
    t.bigint "role_id"
    t.bigint "show_id", null: false
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.datetime "vacated_at"
    t.integer "vacated_by_id"
    t.string "vacated_by_type"
    t.index ["role_id"], name: "index_role_vacancies_on_role_id"
    t.index ["show_id", "role_id", "status"], name: "index_role_vacancies_on_show_id_and_role_id_and_status"
    t.index ["show_id"], name: "index_role_vacancies_on_show_id"
    t.index ["status"], name: "index_role_vacancies_on_status"
    t.index ["vacated_by_type", "vacated_by_id"], name: "index_role_vacancies_on_vacated_by"
  end

  create_table "role_vacancy_invitations", force: :cascade do |t|
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.datetime "declined_at"
    t.text "email_body"
    t.string "email_subject"
    t.datetime "invited_at"
    t.bigint "person_id", null: false
    t.bigint "role_vacancy_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_role_vacancy_invitations_on_person_id"
    t.index ["role_vacancy_id", "person_id"], name: "idx_vacancy_invitations_on_vacancy_and_person", unique: true
    t.index ["role_vacancy_id"], name: "index_role_vacancy_invitations_on_role_vacancy_id"
    t.index ["token"], name: "index_role_vacancy_invitations_on_token", unique: true
  end

  create_table "role_vacancy_shows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "role_vacancy_id", null: false
    t.bigint "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["role_vacancy_id", "show_id"], name: "index_role_vacancy_shows_on_role_vacancy_id_and_show_id", unique: true
    t.index ["role_vacancy_id"], name: "index_role_vacancy_shows_on_role_vacancy_id"
    t.index ["show_id"], name: "index_role_vacancy_shows_on_show_id"
  end

  create_table "roles", force: :cascade do |t|
    t.string "category", default: "performing", null: false
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "position"
    t.bigint "production_id", null: false
    t.integer "quantity", default: 1, null: false
    t.boolean "restricted", default: false, null: false
    t.integer "show_id"
    t.boolean "standing", default: false, null: false
    t.boolean "system_managed", default: false, null: false
    t.string "system_role_type"
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_roles_on_category"
    t.index ["production_id", "show_id", "name"], name: "index_roles_on_production_show_name"
    t.index ["show_id"], name: "index_roles_on_show_id"
  end

  create_table "rpush_apps", force: :cascade do |t|
    t.string "access_token"
    t.datetime "access_token_expiration"
    t.text "apn_key"
    t.string "apn_key_id"
    t.string "auth_key"
    t.string "bundle_id"
    t.text "certificate"
    t.string "client_id"
    t.string "client_secret"
    t.integer "connections", default: 1, null: false
    t.datetime "created_at", null: false
    t.string "environment"
    t.boolean "feedback_enabled", default: true
    t.string "firebase_project_id"
    t.text "json_key"
    t.string "name", null: false
    t.string "password"
    t.string "team_id"
    t.string "type", null: false
    t.datetime "updated_at", null: false
  end

  create_table "rpush_feedback", force: :cascade do |t|
    t.integer "app_id"
    t.datetime "created_at", null: false
    t.string "device_token"
    t.datetime "failed_at", precision: nil, null: false
    t.datetime "updated_at", null: false
    t.index ["device_token"], name: "index_rpush_feedback_on_device_token"
  end

  create_table "rpush_notifications", force: :cascade do |t|
    t.text "alert"
    t.boolean "alert_is_json", default: false, null: false
    t.integer "app_id", null: false
    t.integer "badge"
    t.string "category"
    t.string "collapse_key"
    t.boolean "content_available", default: false, null: false
    t.datetime "created_at", null: false
    t.text "data"
    t.boolean "delay_while_idle", default: false, null: false
    t.datetime "deliver_after", precision: nil
    t.boolean "delivered", default: false, null: false
    t.datetime "delivered_at", precision: nil
    t.string "device_token"
    t.boolean "dry_run", default: false, null: false
    t.integer "error_code"
    t.text "error_description"
    t.integer "expiry", default: 86400
    t.string "external_device_id"
    t.datetime "fail_after", precision: nil
    t.boolean "failed", default: false, null: false
    t.datetime "failed_at", precision: nil
    t.boolean "mutable_content", default: false, null: false
    t.text "notification"
    t.integer "priority"
    t.boolean "processing", default: false, null: false
    t.text "registration_ids"
    t.integer "retries", default: 0
    t.string "sound"
    t.boolean "sound_is_json", default: false
    t.string "thread_id"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.string "uri"
    t.text "url_args"
    t.index ["delivered", "failed", "processing", "deliver_after", "created_at"], name: "index_rpush_notifications_multi", where: "((NOT delivered) AND (NOT failed))"
  end

  create_table "scheduling_rules", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.integer "day_of_week"
    t.time "ends_local_time"
    t.bigint "house_role_id", null: false
    t.bigint "organization_id", null: false
    t.bigint "person_id", null: false
    t.bigint "production_id"
    t.integer "rule_type", default: 0, null: false
    t.time "starts_local_time"
    t.datetime "updated_at", null: false
    t.index ["house_role_id"], name: "index_scheduling_rules_on_house_role_id"
    t.index ["organization_id", "archived_at"], name: "index_scheduling_rules_on_organization_id_and_archived_at"
    t.index ["organization_id"], name: "index_scheduling_rules_on_organization_id"
    t.index ["person_id"], name: "index_scheduling_rules_on_person_id"
    t.index ["production_id"], name: "index_scheduling_rules_on_production_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "impersonator_user_id"
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["impersonator_user_id"], name: "index_sessions_on_impersonator_user_id"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shift_additional_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "house_role_id", null: false
    t.bigint "shift_id", null: false
    t.bigint "show_id"
    t.datetime "updated_at", null: false
    t.index ["house_role_id"], name: "index_shift_additional_roles_on_house_role_id"
    t.index ["shift_id", "house_role_id", "show_id"], name: "idx_shift_additional_roles_unique_per_show", unique: true, where: "(show_id IS NOT NULL)"
    t.index ["shift_id", "house_role_id"], name: "idx_shift_additional_roles_unique_all_shows", unique: true, where: "(show_id IS NULL)"
    t.index ["shift_id"], name: "index_shift_additional_roles_on_shift_id"
    t.index ["show_id"], name: "index_shift_additional_roles_on_show_id"
  end

  create_table "shift_assignments", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "decline_reason"
    t.datetime "declined_at"
    t.datetime "notified_at"
    t.bigint "person_id", null: false
    t.integer "position", default: 1, null: false
    t.bigint "shift_id", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_shift_assignments_on_person_id"
    t.index ["shift_id", "person_id"], name: "idx_shift_assignments_unique", unique: true
    t.index ["shift_id"], name: "index_shift_assignments_on_shift_id"
  end

  create_table "shift_shows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "shift_id", null: false
    t.bigint "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_id", "show_id"], name: "index_shift_shows_on_shift_id_and_show_id", unique: true
    t.index ["shift_id"], name: "index_shift_shows_on_shift_id"
    t.index ["show_id"], name: "index_shift_shows_on_show_id"
  end

  create_table "shifts", force: :cascade do |t|
    t.integer "coverage_mode", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.bigint "house_role_id", null: false
    t.text "notes"
    t.bigint "organization_id", null: false
    t.string "renter_name"
    t.integer "required_count", default: 1, null: false
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "starts_at", null: false
    t.datetime "updated_at", null: false
    t.index ["house_role_id", "source_type", "source_id", "starts_at", "ends_at"], name: "idx_shifts_no_dupe", unique: true
    t.index ["house_role_id"], name: "index_shifts_on_house_role_id"
    t.index ["organization_id", "starts_at"], name: "index_shifts_on_organization_id_and_starts_at"
    t.index ["organization_id"], name: "index_shifts_on_organization_id"
    t.index ["source_type", "source_id"], name: "index_shifts_on_source_type_and_source_id"
  end

  create_table "short_links", force: :cascade do |t|
    t.datetime "archived_at"
    t.integer "clicks_count", default: 0, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "kind", default: "canonical", null: false
    t.string "label"
    t.datetime "last_clicked_at"
    t.bigint "organization_id"
    t.jsonb "query", default: {}, null: false
    t.bigint "target_id"
    t.string "target_type"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_short_links_on_code", unique: true
    t.index ["created_by_id"], name: "index_short_links_on_created_by_id"
    t.index ["organization_id"], name: "index_short_links_on_organization_id"
    t.index ["target_type", "target_id"], name: "index_short_links_canonical_per_target", unique: true, where: "((kind)::text = 'canonical'::text)"
    t.index ["target_type", "target_id"], name: "index_short_links_on_target_type_and_target_id"
  end

  create_table "show_advance_waivers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.bigint "person_id", null: false
    t.string "reason", null: false
    t.bigint "show_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "waived_by_id", null: false
    t.index ["person_id"], name: "index_show_advance_waivers_on_person_id"
    t.index ["show_id", "person_id"], name: "index_show_advance_waivers_on_show_id_and_person_id", unique: true
    t.index ["show_id"], name: "index_show_advance_waivers_on_show_id"
    t.index ["waived_by_id"], name: "index_show_advance_waivers_on_waived_by_id"
  end

  create_table "show_attendance_records", force: :cascade do |t|
    t.datetime "checked_in_at"
    t.datetime "created_at", null: false
    t.text "notes"
    t.bigint "person_id"
    t.bigint "show_id", null: false
    t.bigint "show_person_role_assignment_id"
    t.bigint "sign_up_registration_id"
    t.string "status", default: "unknown", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_show_attendance_records_on_person_id"
    t.index ["show_id", "person_id"], name: "idx_attendance_by_walkin", unique: true, where: "(person_id IS NOT NULL)"
    t.index ["show_id", "show_person_role_assignment_id"], name: "idx_attendance_by_assignment", unique: true, where: "(show_person_role_assignment_id IS NOT NULL)"
    t.index ["show_id", "show_person_role_assignment_id"], name: "idx_attendance_show_assignment", unique: true
    t.index ["show_id", "sign_up_registration_id"], name: "idx_attendance_by_signup", unique: true, where: "(sign_up_registration_id IS NOT NULL)"
    t.index ["show_id"], name: "index_show_attendance_records_on_show_id"
    t.index ["show_person_role_assignment_id"], name: "idx_on_show_person_role_assignment_id_aacbb17773"
  end

  create_table "show_availabilities", force: :cascade do |t|
    t.integer "available_entity_id"
    t.string "available_entity_type"
    t.datetime "created_at", null: false
    t.string "note"
    t.bigint "show_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["available_entity_type", "available_entity_id", "show_id"], name: "index_show_availabilities_unique", unique: true
    t.index ["available_entity_type", "available_entity_id"], name: "index_show_availabilities_on_entity"
    t.index ["show_id"], name: "index_show_availabilities_on_show_id"
  end

  create_table "show_cast_notifications", force: :cascade do |t|
    t.bigint "assignable_id", null: false
    t.string "assignable_type", null: false
    t.datetime "created_at", null: false
    t.text "email_body"
    t.integer "notification_type", default: 0, null: false
    t.datetime "notified_at", null: false
    t.bigint "role_id"
    t.bigint "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assignable_type", "assignable_id"], name: "index_show_cast_notifications_on_assignable"
    t.index ["role_id"], name: "index_show_cast_notifications_on_role_id"
    t.index ["show_id", "assignable_type", "assignable_id", "role_id"], name: "idx_show_cast_notifications_unique", unique: true
    t.index ["show_id"], name: "index_show_cast_notifications_on_show_id"
  end

  create_table "show_financials", force: :cascade do |t|
    t.decimal "contractor_collected"
    t.datetime "contractor_reported_at"
    t.datetime "created_at", null: false
    t.boolean "data_confirmed"
    t.jsonb "expense_details", default: []
    t.decimal "expenses", precision: 10, scale: 2, default: "0.0"
    t.decimal "flat_fee", precision: 10, scale: 2
    t.boolean "non_revenue_override", default: false, null: false
    t.text "notes"
    t.decimal "other_revenue", precision: 10, scale: 2, default: "0.0"
    t.jsonb "other_revenue_details", default: []
    t.string "revenue_type", default: "ticket_sales"
    t.bigint "show_id", null: false
    t.integer "ticket_count", default: 0
    t.decimal "ticket_revenue", precision: 10, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.index ["show_id"], name: "index_show_financials_on_show_id", unique: true
  end

  create_table "show_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "show_id", null: false
    t.string "text"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["show_id"], name: "index_show_links_on_show_id"
  end

  create_table "show_payout_line_items", force: :cascade do |t|
    t.decimal "advance_deduction", precision: 10, scale: 2, default: "0.0"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.jsonb "calculation_details", default: {}
    t.datetime "created_at", null: false
    t.string "guest_name"
    t.boolean "is_guest", default: false, null: false
    t.boolean "is_individual_allocation", default: false, null: false
    t.boolean "manually_paid", default: false, null: false
    t.datetime "manually_paid_at"
    t.bigint "manually_paid_by_id"
    t.text "notes"
    t.datetime "paid_at"
    t.boolean "paid_independently", default: false
    t.bigint "payee_id"
    t.string "payee_type"
    t.string "payment_method"
    t.text "payment_notes"
    t.text "payout_error"
    t.string "payout_reference_id"
    t.string "payout_status"
    t.decimal "shares", precision: 10, scale: 2
    t.bigint "show_payout_id", null: false
    t.datetime "updated_at", null: false
    t.index ["manually_paid_by_id"], name: "index_show_payout_line_items_on_manually_paid_by_id"
    t.index ["payee_type", "payee_id"], name: "index_show_payout_line_items_on_payee"
    t.index ["payment_method"], name: "index_show_payout_line_items_on_payment_method"
    t.index ["payout_reference_id"], name: "index_show_payout_line_items_on_payout_reference_id", where: "(payout_reference_id IS NOT NULL)"
    t.index ["payout_status"], name: "index_show_payout_line_items_on_payout_status"
    t.index ["show_payout_id", "payee_type", "payee_id", "is_individual_allocation"], name: "idx_payout_line_items_unique_payee", unique: true
    t.index ["show_payout_id"], name: "index_show_payout_line_items_on_show_payout_id"
  end

  create_table "show_payouts", force: :cascade do |t|
    t.jsonb "act_counts", default: {}, null: false
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "calculated_at"
    t.datetime "created_at", null: false
    t.jsonb "override_rules"
    t.bigint "payout_scheme_id"
    t.bigint "show_id", null: false
    t.string "status", default: "draft", null: false
    t.decimal "total_payout", precision: 10, scale: 2
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_show_payouts_on_approved_by_id"
    t.index ["payout_scheme_id"], name: "index_show_payouts_on_payout_scheme_id"
    t.index ["show_id"], name: "index_show_payouts_on_show_id", unique: true
    t.index ["status"], name: "index_show_payouts_on_status"
  end

  create_table "show_person_role_assignments", force: :cascade do |t|
    t.bigint "assignable_id"
    t.string "assignable_type"
    t.datetime "created_at", null: false
    t.string "guest_email"
    t.string "guest_name"
    t.integer "person_id"
    t.integer "position", default: 0, null: false
    t.bigint "role_id"
    t.integer "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assignable_type", "assignable_id"], name: "index_show_role_assignments_on_assignable"
    t.index ["person_id"], name: "index_show_person_role_assignments_on_person_id"
    t.index ["role_id"], name: "index_show_person_role_assignments_on_role_id"
    t.index ["show_id", "role_id", "assignable_type", "assignable_id"], name: "idx_unique_show_role_assignable", unique: true, where: "(assignable_id IS NOT NULL)"
    t.index ["show_id", "role_id", "position"], name: "idx_assignments_show_role_position"
    t.index ["show_id"], name: "index_show_person_role_assignments_on_show_id"
  end

  create_table "shows", force: :cascade do |t|
    t.boolean "attendance_enabled", default: false, null: false
    t.datetime "call_time"
    t.boolean "call_time_enabled", default: false, null: false
    t.boolean "canceled", default: false, null: false
    t.boolean "casting_enabled", default: true, null: false
    t.datetime "casting_finalized_at"
    t.string "casting_mode"
    t.string "casting_source"
    t.bigint "course_offering_id"
    t.datetime "created_at", null: false
    t.datetime "date_and_time"
    t.integer "duration_minutes"
    t.bigint "event_linkage_id"
    t.string "event_type", default: "show", null: false
    t.boolean "is_online", default: false, null: false
    t.string "linkage_role"
    t.bigint "location_id"
    t.bigint "location_space_id"
    t.integer "mic_status"
    t.text "notes"
    t.string "online_location_info"
    t.integer "production_id", null: false
    t.boolean "public_profile_visible"
    t.string "recurrence_group_id"
    t.string "recurrence_pattern"
    t.string "secondary_name"
    t.boolean "signup_based_casting", default: false, null: false
    t.bigint "space_rental_id"
    t.jsonb "staffing_coverage_exempt_role_ids", default: [], null: false
    t.datetime "updated_at", null: false
    t.boolean "use_custom_roles", default: false, null: false
    t.index ["casting_mode"], name: "index_shows_on_casting_mode"
    t.index ["casting_source"], name: "index_shows_on_casting_source"
    t.index ["course_offering_id"], name: "index_shows_on_course_offering_id"
    t.index ["date_and_time"], name: "idx_shows_date_and_time"
    t.index ["event_linkage_id"], name: "index_shows_on_event_linkage_id"
    t.index ["location_id"], name: "index_shows_on_location_id"
    t.index ["location_space_id"], name: "index_shows_on_location_space_id"
    t.index ["mic_status"], name: "index_shows_on_mic_status", where: "(mic_status IS NOT NULL)"
    t.index ["production_id", "event_type", "canceled", "date_and_time"], name: "idx_shows_prod_type_canceled_date"
    t.index ["production_id"], name: "index_shows_on_production_id"
    t.index ["space_rental_id"], name: "index_shows_on_space_rental_id"
  end

  create_table "sign_up_form_holdouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "holdout_type", null: false
    t.integer "holdout_value", null: false
    t.string "reason"
    t.bigint "sign_up_form_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sign_up_form_id", "holdout_type"], name: "idx_on_sign_up_form_id_holdout_type_bd84302aad", unique: true
    t.index ["sign_up_form_id"], name: "index_sign_up_form_holdouts_on_sign_up_form_id"
  end

  create_table "sign_up_form_instances", force: :cascade do |t|
    t.datetime "closes_at"
    t.datetime "created_at", null: false
    t.datetime "edit_cutoff_at"
    t.datetime "opens_at"
    t.bigint "show_id"
    t.bigint "sign_up_form_id", null: false
    t.string "status", default: "scheduled", null: false
    t.datetime "updated_at", null: false
    t.index ["show_id", "status"], name: "index_sign_up_form_instances_on_show_id_and_status"
    t.index ["show_id"], name: "index_sign_up_form_instances_on_show_id"
    t.index ["sign_up_form_id", "show_id"], name: "index_sign_up_form_instances_on_sign_up_form_id_and_show_id", unique: true
    t.index ["sign_up_form_id"], name: "index_sign_up_form_instances_on_sign_up_form_id"
  end

  create_table "sign_up_form_shows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "show_id", null: false
    t.bigint "sign_up_form_id", null: false
    t.datetime "updated_at", null: false
    t.index ["show_id"], name: "index_sign_up_form_shows_on_show_id"
    t.index ["sign_up_form_id", "show_id"], name: "index_sign_up_form_shows_on_sign_up_form_id_and_show_id", unique: true
    t.index ["sign_up_form_id"], name: "index_sign_up_form_shows_on_sign_up_form_id"
  end

  create_table "sign_up_forms", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.boolean "allow_cancel", default: true
    t.boolean "allow_edit", default: true
    t.datetime "archived_at"
    t.integer "cancel_cutoff_days", default: 0
    t.integer "cancel_cutoff_hours", default: 2
    t.integer "cancel_cutoff_minutes", default: 0
    t.string "cancel_cutoff_mode"
    t.datetime "closes_at"
    t.integer "closes_hours_before", default: 2
    t.integer "closes_minutes_offset", default: 0
    t.string "closes_mode", default: "event_start", null: false
    t.string "closes_offset_unit", default: "hours"
    t.integer "closes_offset_value", default: 0
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "edit_cutoff_days", default: 0
    t.integer "edit_cutoff_hours", default: 24
    t.integer "edit_cutoff_minutes", default: 0
    t.string "edit_cutoff_mode"
    t.string "event_matching", default: "all"
    t.jsonb "event_type_filter", default: []
    t.string "hide_registrations_mode", default: "event_start"
    t.string "hide_registrations_offset_unit", default: "hours"
    t.integer "hide_registrations_offset_value", default: 2
    t.boolean "holdback_visible", default: true, null: false
    t.text "instruction_text"
    t.string "name", null: false
    t.boolean "notify_on_registration", default: false, null: false
    t.datetime "opens_at"
    t.integer "opens_days_before", default: 7
    t.integer "opens_hours_before", default: 0
    t.integer "opens_minutes_before", default: 0
    t.string "pre_registration_mode", default: "producers_only", null: false
    t.string "pre_registration_window_unit", default: "days", null: false
    t.integer "pre_registration_window_value", default: 45, null: false
    t.bigint "production_id", null: false
    t.boolean "queue_carryover", default: false, null: false
    t.integer "queue_limit"
    t.integer "registrations_per_person", default: 1
    t.boolean "require_login", default: false, null: false
    t.string "schedule_mode", default: "relative"
    t.string "scope", default: "single_event", null: false
    t.string "short_code"
    t.bigint "show_id"
    t.boolean "show_registrations", default: true
    t.integer "slot_capacity", default: 1
    t.integer "slot_count", default: 10
    t.string "slot_generation_mode", default: "numbered"
    t.boolean "slot_hold_enabled", default: true
    t.integer "slot_hold_seconds", default: 30
    t.integer "slot_interval_minutes"
    t.jsonb "slot_names", default: []
    t.string "slot_prefix", default: "Slot"
    t.string "slot_selection_mode", default: "choose"
    t.string "slot_start_time"
    t.integer "slots_per_registration", default: 1, null: false
    t.text "success_text"
    t.datetime "updated_at", null: false
    t.string "url_slug"
    t.index ["production_id", "active"], name: "index_sign_up_forms_on_production_id_and_active"
    t.index ["production_id", "scope"], name: "index_sign_up_forms_on_production_id_and_scope"
    t.index ["production_id"], name: "index_sign_up_forms_on_production_id"
    t.index ["short_code"], name: "index_sign_up_forms_on_short_code", unique: true
    t.index ["show_id"], name: "index_sign_up_forms_on_show_id"
    t.index ["url_slug"], name: "index_sign_up_forms_on_url_slug"
  end

  create_table "sign_up_registrations", force: :cascade do |t|
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.string "guest_email"
    t.string "guest_name"
    t.bigint "person_id"
    t.integer "position", null: false
    t.datetime "registered_at", null: false
    t.bigint "sign_up_form_instance_id"
    t.bigint "sign_up_slot_id"
    t.string "status", default: "confirmed", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "idx_sign_up_regs_person", where: "(person_id IS NOT NULL)"
    t.index ["person_id"], name: "index_sign_up_registrations_on_person_id"
    t.index ["sign_up_form_instance_id", "status"], name: "idx_registrations_instance_status"
    t.index ["sign_up_form_instance_id"], name: "index_sign_up_registrations_on_sign_up_form_instance_id"
    t.index ["sign_up_slot_id", "person_id"], name: "idx_sign_up_regs_slot_person_unique", unique: true, where: "((person_id IS NOT NULL) AND ((status)::text <> 'cancelled'::text))"
    t.index ["sign_up_slot_id", "position"], name: "index_sign_up_registrations_on_sign_up_slot_id_and_position"
    t.index ["sign_up_slot_id"], name: "index_sign_up_registrations_on_sign_up_slot_id"
  end

  create_table "sign_up_slots", force: :cascade do |t|
    t.integer "capacity", default: 1, null: false
    t.datetime "created_at", null: false
    t.string "held_reason"
    t.boolean "is_held", default: false, null: false
    t.string "name"
    t.integer "position", null: false
    t.bigint "role_id"
    t.bigint "sign_up_form_id", null: false
    t.bigint "sign_up_form_instance_id"
    t.datetime "updated_at", null: false
    t.index ["role_id"], name: "index_sign_up_slots_on_role_id"
    t.index ["sign_up_form_id", "position"], name: "index_sign_up_slots_on_sign_up_form_id_and_position"
    t.index ["sign_up_form_id"], name: "index_sign_up_slots_on_sign_up_form_id"
    t.index ["sign_up_form_instance_id"], name: "index_sign_up_slots_on_sign_up_form_instance_id"
  end

  create_table "socials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "handle", null: false
    t.string "name"
    t.string "platform", null: false
    t.integer "sociable_id"
    t.string "sociable_type"
    t.datetime "updated_at", null: false
    t.index ["sociable_type", "sociable_id"], name: "index_socials_on_sociable_type_and_sociable_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "space_rentals", force: :cascade do |t|
    t.boolean "confirmed", default: false, null: false
    t.bigint "contract_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.datetime "event_ends_at"
    t.datetime "event_starts_at"
    t.bigint "location_id", null: false
    t.bigint "location_space_id"
    t.text "notes"
    t.datetime "starts_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contract_id"], name: "index_space_rentals_on_contract_id"
    t.index ["location_id"], name: "index_space_rentals_on_location_id"
    t.index ["location_space_id", "starts_at", "ends_at"], name: "index_space_rentals_on_space_and_time"
    t.index ["location_space_id"], name: "index_space_rentals_on_location_space_id"
    t.index ["starts_at"], name: "index_space_rentals_on_starts_at"
  end

  create_table "staff_activations", force: :cascade do |t|
    t.date "billing_month", null: false
    t.datetime "created_at", null: false
    t.datetime "first_notified_at"
    t.bigint "organization_id", null: false
    t.bigint "person_id", null: false
    t.datetime "reported_at"
    t.datetime "updated_at", null: false
    t.index ["organization_id", "person_id", "billing_month"], name: "idx_staff_activations_unique", unique: true
    t.index ["organization_id"], name: "index_staff_activations_on_organization_id"
    t.index ["person_id"], name: "index_staff_activations_on_person_id"
  end

  create_table "staff_agreement_templates", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["organization_id"], name: "index_staff_agreement_templates_on_organization_id"
  end

  create_table "staff_availability_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.integer "day_of_week"
    t.integer "ends_minute", default: 1440, null: false
    t.date "ends_on"
    t.integer "kind", default: 0, null: false
    t.string "note", limit: 140
    t.bigint "person_id", null: false
    t.integer "polarity", default: 0, null: false
    t.integer "source", default: 0, null: false
    t.integer "starts_minute", default: 0, null: false
    t.date "starts_on"
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_staff_availability_entries_on_created_by_id"
    t.index ["person_id", "kind"], name: "index_staff_availability_entries_on_person_id_and_kind"
    t.index ["person_id", "starts_on", "ends_on"], name: "idx_staff_availability_dated_span", where: "(kind = 1)"
    t.index ["person_id"], name: "index_staff_availability_entries_on_person_id"
    t.check_constraint "ends_minute > starts_minute", name: "staff_availability_band_forward"
    t.check_constraint "ends_minute >= 1 AND ends_minute <= 2880", name: "staff_availability_ends_within_next_day"
    t.check_constraint "kind = 0 AND day_of_week >= 0 AND day_of_week <= 6 OR kind = 1 AND day_of_week IS NULL AND starts_on IS NOT NULL AND ends_on IS NOT NULL", name: "staff_availability_kind_shape"
    t.check_constraint "starts_minute >= 0 AND starts_minute <= 1440", name: "staff_availability_starts_in_day"
    t.check_constraint "starts_on IS NULL OR ends_on IS NULL OR ends_on >= starts_on", name: "staff_availability_dates_forward"
  end

  create_table "staff_role_qualifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "flat_rate_cents"
    t.integer "hourly_rate_cents"
    t.bigint "house_role_id", null: false
    t.bigint "organization_staff_member_id", null: false
    t.datetime "updated_at", null: false
    t.index ["house_role_id"], name: "index_staff_role_qualifications_on_house_role_id"
    t.index ["organization_staff_member_id", "house_role_id"], name: "idx_staff_role_qual_unique", unique: true
    t.index ["organization_staff_member_id"], name: "idx_staff_role_qual_member"
  end

  create_table "staff_schedule_removals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "location_name"
    t.datetime "notified_at"
    t.bigint "organization_id", null: false
    t.bigint "person_id", null: false
    t.string "shift_label"
    t.datetime "shift_starts_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "shift_starts_at"], name: "idx_on_organization_id_shift_starts_at_1d096fe153"
    t.index ["organization_id"], name: "index_staff_schedule_removals_on_organization_id"
    t.index ["person_id"], name: "index_staff_schedule_removals_on_person_id"
  end

  create_table "staff_time_entries", force: :cascade do |t|
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "created_at", null: false
    t.datetime "ended_at", null: false
    t.decimal "hours", precision: 6, scale: 2, null: false
    t.bigint "house_role_id"
    t.string "notes"
    t.bigint "offline_amount_cents"
    t.datetime "offline_paid_at"
    t.bigint "offline_paid_by_id"
    t.string "offline_payment_note"
    t.bigint "offline_reimbursement_cents"
    t.bigint "organization_id", null: false
    t.datetime "paid_at"
    t.bigint "payout_batch_id"
    t.bigint "person_id", null: false
    t.bigint "shift_assignment_id"
    t.string "source", default: "manual", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_staff_time_entries_on_approved_by_id"
    t.index ["house_role_id"], name: "index_staff_time_entries_on_house_role_id"
    t.index ["offline_paid_by_id"], name: "index_staff_time_entries_on_offline_paid_by_id"
    t.index ["organization_id", "approved_at"], name: "idx_staff_time_entries_org_unpaid", where: "((payout_batch_id IS NULL) AND (offline_paid_at IS NULL))"
    t.index ["organization_id", "started_at"], name: "idx_staff_time_entries_org_started"
    t.index ["organization_id"], name: "index_staff_time_entries_on_organization_id"
    t.index ["payout_batch_id"], name: "index_staff_time_entries_on_payout_batch_id"
    t.index ["person_id"], name: "index_staff_time_entries_on_person_id"
    t.index ["shift_assignment_id"], name: "idx_staff_time_entries_unique_assignment", unique: true, where: "(shift_assignment_id IS NOT NULL)"
    t.index ["shift_assignment_id"], name: "index_staff_time_entries_on_shift_assignment_id"
  end

  create_table "staffing_finalizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "finalized_at"
    t.bigint "finalized_by_id"
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.date "week_start", null: false
    t.index ["finalized_by_id"], name: "index_staffing_finalizations_on_finalized_by_id"
    t.index ["organization_id", "week_start"], name: "index_staffing_finalizations_on_organization_id_and_week_start", unique: true
    t.index ["organization_id"], name: "index_staffing_finalizations_on_organization_id"
  end

  create_table "stripe_balance_transactions", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.date "available_on"
    t.string "category", default: "unknown", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "usd", null: false
    t.string "description"
    t.bigint "expected_cents"
    t.datetime "explained_at"
    t.bigint "explained_by_id"
    t.bigint "fee_cents", default: 0, null: false
    t.string "match_status", default: "unmatched", null: false
    t.bigint "matched_id"
    t.string "matched_type"
    t.bigint "net_cents", null: false
    t.text "note"
    t.datetime "occurred_at", null: false
    t.bigint "organization_id"
    t.jsonb "refs", default: {}, null: false
    t.string "reporting_category"
    t.string "source_id"
    t.string "status"
    t.string "stripe_id", null: false
    t.string "txn_type", null: false
    t.datetime "updated_at", null: false
    t.index ["explained_by_id"], name: "index_stripe_balance_transactions_on_explained_by_id"
    t.index ["match_status"], name: "index_stripe_balance_transactions_on_match_status"
    t.index ["matched_type", "matched_id"], name: "index_stripe_balance_transactions_on_matched"
    t.index ["occurred_at"], name: "index_stripe_balance_transactions_on_occurred_at"
    t.index ["organization_id"], name: "index_stripe_balance_transactions_on_organization_id"
    t.index ["source_id"], name: "index_stripe_balance_transactions_on_source_id"
    t.index ["stripe_id"], name: "index_stripe_balance_transactions_on_stripe_id", unique: true
  end

  create_table "system_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_system_settings_on_key", unique: true
  end

  create_table "talent_pool_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "member_id", null: false
    t.string "member_type", null: false
    t.bigint "talent_pool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["member_type", "member_id", "talent_pool_id"], name: "index_tpm_on_member_and_pool"
    t.index ["member_type", "member_id"], name: "index_talent_pool_memberships_on_member_type_and_member_id"
    t.index ["talent_pool_id", "member_type", "member_id"], name: "index_talent_pool_memberships_unique", unique: true
    t.index ["talent_pool_id"], name: "index_talent_pool_memberships_on_talent_pool_id"
  end

  create_table "talent_pool_shares", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "production_id", null: false
    t.bigint "talent_pool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id"], name: "index_talent_pool_shares_on_production_id"
    t.index ["talent_pool_id", "production_id"], name: "index_talent_pool_shares_on_talent_pool_id_and_production_id", unique: true
    t.index ["talent_pool_id"], name: "index_talent_pool_shares_on_talent_pool_id"
  end

  create_table "talent_pools", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "production_id", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id"], name: "index_talent_pools_on_production_id"
  end

  create_table "tax_document_accesses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.bigint "organization_id", null: false
    t.bigint "user_id"
    t.bigint "w9_submission_id", null: false
    t.index ["organization_id"], name: "index_tax_document_accesses_on_organization_id"
    t.index ["user_id"], name: "index_tax_document_accesses_on_user_id"
    t.index ["w9_submission_id"], name: "index_tax_document_accesses_on_w9_submission_id"
  end

  create_table "tax_form_1099s", force: :cascade do |t|
    t.bigint "adjustment_cents", default: 0, null: false
    t.string "adjustment_note"
    t.bigint "corrects_id"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.bigint "federal_withheld_cents", default: 0, null: false
    t.datetime "filed_at"
    t.text "filing_notes"
    t.string "filing_reference"
    t.bigint "generated_by_id"
    t.bigint "nec_box1_cents", default: 0, null: false
    t.bigint "organization_id", null: false
    t.string "payer_address_line1", null: false
    t.string "payer_address_line2"
    t.string "payer_city", null: false
    t.string "payer_ein_last4", null: false
    t.string "payer_name", null: false
    t.string "payer_phone"
    t.string "payer_state", null: false
    t.string "payer_zip", null: false
    t.bigint "person_id", null: false
    t.string "recipient_address_line1", null: false
    t.string "recipient_address_line2"
    t.string "recipient_business_name"
    t.string "recipient_city", null: false
    t.boolean "recipient_e_delivery_consented", default: false, null: false
    t.string "recipient_name", null: false
    t.string "recipient_state", null: false
    t.string "recipient_tin_last4", null: false
    t.string "recipient_tin_type", null: false
    t.string "recipient_zip", null: false
    t.string "status", default: "draft", null: false
    t.integer "tax_year", null: false
    t.datetime "updated_at", null: false
    t.bigint "w9_submission_id"
    t.index ["corrects_id"], name: "index_tax_form_1099s_on_corrects_id"
    t.index ["generated_by_id"], name: "index_tax_form_1099s_on_generated_by_id"
    t.index ["organization_id", "tax_year", "status"], name: "idx_on_organization_id_tax_year_status_22b31fe756"
    t.index ["organization_id"], name: "index_tax_form_1099s_on_organization_id"
    t.index ["person_id", "tax_year"], name: "index_tax_form_1099s_on_person_id_and_tax_year"
    t.index ["person_id"], name: "index_tax_form_1099s_on_person_id"
    t.index ["w9_submission_id"], name: "index_tax_form_1099s_on_w9_submission_id"
  end

  create_table "tax_lines", force: :cascade do |t|
    t.integer "base_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "event_date"
    t.boolean "exempt", default: false, null: false
    t.string "exemption_reason"
    t.boolean "included", default: false, null: false
    t.string "jurisdiction"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.integer "rate_bps", default: 0, null: false
    t.string "remitter", default: "organization", null: false
    t.bigint "reversal_of_id"
    t.date "sale_date", null: false
    t.integer "tax_cents", default: 0, null: false
    t.bigint "tax_rate_id"
    t.bigint "taxable_id", null: false
    t.string "taxable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "event_date"], name: "index_tax_lines_on_organization_id_and_event_date"
    t.index ["organization_id", "sale_date"], name: "index_tax_lines_on_organization_id_and_sale_date"
    t.index ["organization_id"], name: "index_tax_lines_on_organization_id"
    t.index ["reversal_of_id"], name: "index_tax_lines_on_reversal_of_id"
    t.index ["tax_rate_id"], name: "index_tax_lines_on_tax_rate_id"
    t.index ["taxable_type", "taxable_id"], name: "index_tax_lines_on_taxable_type_and_taxable_id"
  end

  create_table "tax_rates", force: :cascade do |t|
    t.boolean "applies_to_fees", default: false, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.date "effective_from"
    t.date "effective_to"
    t.string "jurisdiction"
    t.string "kind", default: "sales", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.integer "rate_bps", null: false
    t.string "receipt_label"
    t.string "registration_number"
    t.string "remitter", default: "organization", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_tax_rates_on_organization_id"
  end

  create_table "tax_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "exempt", default: false, null: false
    t.string "exemption_reason"
    t.string "mode", default: "added", null: false
    t.string "money_kind", null: false
    t.bigint "organization_id", null: false
    t.bigint "scope_id"
    t.string "scope_type"
    t.jsonb "tax_rate_ids", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "money_kind", "scope_type", "scope_id"], name: "idx_tax_rules_one_per_scope", unique: true, where: "(scope_type IS NOT NULL)"
    t.index ["organization_id", "money_kind"], name: "idx_tax_rules_one_default", unique: true, where: "(scope_type IS NULL)"
    t.index ["organization_id"], name: "index_tax_rules_on_organization_id"
  end

  create_table "team_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "invitation_role", default: "viewer"
    t.bigint "organization_id", null: false
    t.bigint "person_id"
    t.bigint "production_id"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_team_invitations_on_organization_id"
    t.index ["production_id"], name: "index_team_invitations_on_production_id"
    t.index ["token"], name: "index_team_invitations_on_token", unique: true
  end

  create_table "ticket_discount_codes", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "amount_cents"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.datetime "ends_at"
    t.string "kind", default: "fixed", null: false
    t.integer "max_uses"
    t.bigint "organization_id", null: false
    t.decimal "percent", precision: 5, scale: 2
    t.bigint "production_id"
    t.datetime "starts_at"
    t.bigint "ticket_listing_id"
    t.jsonb "ticket_tier_ids", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "code"], name: "index_ticket_discount_codes_on_organization_id_and_code"
    t.index ["organization_id"], name: "index_ticket_discount_codes_on_organization_id"
    t.index ["production_id"], name: "index_ticket_discount_codes_on_production_id"
    t.index ["ticket_listing_id"], name: "index_ticket_discount_codes_on_ticket_listing_id"
  end

  create_table "ticket_exchanges", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "difference_cents", default: 0, null: false
    t.bigint "exchanged_by_id"
    t.integer "face_cents", default: 0, null: false
    t.integer "fees_cents", default: 0, null: false
    t.bigint "from_order_id", null: false
    t.integer "moved_cents", default: 0, null: false
    t.bigint "organization_id", null: false
    t.integer "tax_cents", default: 0, null: false
    t.jsonb "ticket_ids", default: [], null: false
    t.bigint "ticket_refund_id"
    t.bigint "to_order_id", null: false
    t.datetime "updated_at", null: false
    t.index ["exchanged_by_id"], name: "index_ticket_exchanges_on_exchanged_by_id"
    t.index ["from_order_id"], name: "index_ticket_exchanges_on_from_order_id"
    t.index ["organization_id"], name: "index_ticket_exchanges_on_organization_id"
    t.index ["ticket_refund_id"], name: "index_ticket_exchanges_on_ticket_refund_id"
    t.index ["to_order_id"], name: "index_ticket_exchanges_on_to_order_id", unique: true
  end

  create_table "ticket_listings", force: :cascade do |t|
    t.string "accessibility_note"
    t.string "age_note"
    t.bigint "contract_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "door_note"
    t.string "fee_mode"
    t.boolean "inherits_tiers", default: false, null: false
    t.integer "low_stock_threshold"
    t.integer "max_per_order"
    t.datetime "off_sale_at"
    t.datetime "on_sale_at"
    t.bigint "organization_id", null: false
    t.bigint "production_id", null: false
    t.datetime "released_at"
    t.boolean "sell_products", default: true, null: false
    t.bigint "show_id", null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["contract_id"], name: "index_ticket_listings_on_contract_id"
    t.index ["organization_id", "slug"], name: "index_ticket_listings_on_organization_id_and_slug", unique: true
    t.index ["organization_id", "status"], name: "index_ticket_listings_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_ticket_listings_on_organization_id"
    t.index ["production_id"], name: "index_ticket_listings_on_production_id"
    t.index ["show_id"], name: "index_ticket_listings_on_show_id", unique: true
  end

  create_table "ticket_order_items", force: :cascade do |t|
    t.boolean "counts_toward_ticket_revenue", default: false, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "fulfilled_at"
    t.bigint "fulfilled_by_id"
    t.integer "fulfilled_quantity", default: 0, null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "refunded_at"
    t.string "status", default: "reserved", null: false
    t.integer "tax_cents", default: 0, null: false
    t.bigint "ticket_listing_id", null: false
    t.bigint "ticket_order_id", null: false
    t.bigint "ticket_product_id", null: false
    t.integer "unit_price_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["fulfilled_by_id"], name: "index_ticket_order_items_on_fulfilled_by_id"
    t.index ["organization_id"], name: "index_ticket_order_items_on_organization_id"
    t.index ["ticket_listing_id", "status"], name: "index_ticket_order_items_on_ticket_listing_id_and_status"
    t.index ["ticket_listing_id"], name: "index_ticket_order_items_on_ticket_listing_id"
    t.index ["ticket_order_id"], name: "index_ticket_order_items_on_ticket_order_id"
    t.index ["ticket_product_id"], name: "index_ticket_order_items_on_ticket_product_id"
  end

  create_table "ticket_orders", force: :cascade do |t|
    t.string "buyer_email"
    t.integer "buyer_fee_cents", default: 0, null: false
    t.string "buyer_name"
    t.string "buyer_phone"
    t.datetime "canceled_at"
    t.string "channel", default: "online", null: false
    t.string "client_ip"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "discount_cents", default: 0, null: false
    t.bigint "exchanged_from_id"
    t.datetime "expires_at"
    t.string "external_order_id"
    t.string "fee_mode", null: false
    t.bigint "issued_by_id"
    t.boolean "marketing_opt_in", default: false, null: false
    t.string "money_path", default: "cocoscout", null: false
    t.string "note"
    t.integer "org_net_cents", default: 0, null: false
    t.bigint "organization_id", null: false
    t.datetime "paid_at"
    t.integer "platform_fee_cents", default: 0, null: false
    t.integer "processing_cents", default: 0, null: false
    t.string "referrer"
    t.datetime "refunded_at"
    t.integer "refunded_cents", default: 0, null: false
    t.datetime "reminded_at"
    t.boolean "reminders_opt_out", default: false, null: false
    t.bigint "short_link_id"
    t.string "status", default: "pending", null: false
    t.string "stripe_charge_id"
    t.string "stripe_dispute_id"
    t.integer "stripe_fee_cents"
    t.string "stripe_payment_intent_id"
    t.integer "subtotal_cents", default: 0, null: false
    t.integer "tax_cents", default: 0, null: false
    t.bigint "ticket_channel_id"
    t.bigint "ticket_discount_code_id"
    t.bigint "ticket_listing_id", null: false
    t.string "token", null: false
    t.bigint "told_location_id"
    t.bigint "told_location_space_id"
    t.datetime "told_starts_at"
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.jsonb "utm", default: {}, null: false
    t.index ["buyer_email"], name: "index_ticket_orders_on_buyer_email"
    t.index ["code"], name: "index_ticket_orders_on_code", unique: true
    t.index ["exchanged_from_id"], name: "index_ticket_orders_on_exchanged_from_id"
    t.index ["expires_at"], name: "index_ticket_orders_on_expires_at", where: "((status)::text = 'pending'::text)"
    t.index ["issued_by_id"], name: "index_ticket_orders_on_issued_by_id"
    t.index ["organization_id", "created_at"], name: "index_ticket_orders_on_organization_id_and_created_at"
    t.index ["organization_id"], name: "index_ticket_orders_on_organization_id"
    t.index ["short_link_id"], name: "index_ticket_orders_on_short_link_id"
    t.index ["stripe_payment_intent_id"], name: "index_ticket_orders_on_stripe_payment_intent_id", unique: true, where: "(stripe_payment_intent_id IS NOT NULL)"
    t.index ["ticket_discount_code_id"], name: "index_ticket_orders_on_ticket_discount_code_id"
    t.index ["ticket_listing_id", "status"], name: "index_ticket_orders_on_ticket_listing_id_and_status"
    t.index ["ticket_listing_id"], name: "index_ticket_orders_on_ticket_listing_id"
    t.index ["token"], name: "index_ticket_orders_on_token", unique: true
    t.index ["user_id"], name: "index_ticket_orders_on_user_id"
  end

  create_table "ticket_products", force: :cascade do |t|
    t.datetime "archived_at"
    t.boolean "counts_toward_ticket_revenue", default: false, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_cents", default: 0, null: false
    t.boolean "taxable", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_ticket_products_on_organization_id"
  end

  create_table "ticket_refunds", force: :cascade do |t|
    t.integer "amount_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "error"
    t.integer "face_cents", default: 0, null: false
    t.integer "fees_cents", default: 0, null: false
    t.jsonb "item_ids", default: [], null: false
    t.boolean "keep_fees", default: false, null: false
    t.integer "org_debit_cents", default: 0, null: false
    t.bigint "organization_id", null: false
    t.integer "platform_fee_waived_cents", default: 0, null: false
    t.integer "product_cents", default: 0, null: false
    t.string "reason"
    t.bigint "refunded_by_id"
    t.string "status", default: "pending", null: false
    t.string "stripe_refund_id"
    t.integer "tax_cents", default: 0, null: false
    t.jsonb "ticket_ids", default: [], null: false
    t.bigint "ticket_order_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_ticket_refunds_on_organization_id"
    t.index ["refunded_by_id"], name: "index_ticket_refunds_on_refunded_by_id"
    t.index ["ticket_order_id"], name: "index_ticket_refunds_on_ticket_order_id"
  end

  create_table "ticket_sales_lines", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.bigint "show_financials_id", null: false
    t.bigint "ticket_source_id"
    t.integer "tickets_sold", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["show_financials_id", "position"], name: "index_ticket_sales_lines_on_show_financials_id_and_position"
    t.index ["show_financials_id"], name: "index_ticket_sales_lines_on_show_financials_id"
    t.index ["ticket_source_id"], name: "index_ticket_sales_lines_on_ticket_source_id"
  end

  create_table "ticket_sales_viewers", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.boolean "daily_email", default: false, null: false
    t.bigint "granted_by_id"
    t.string "invitation_token"
    t.datetime "invited_at"
    t.string "invited_email"
    t.string "invited_name"
    t.bigint "organization_id", null: false
    t.datetime "revoked_at"
    t.bigint "revoked_by_id"
    t.bigint "scope_id", null: false
    t.string "scope_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["granted_by_id"], name: "index_ticket_sales_viewers_on_granted_by_id"
    t.index ["invitation_token"], name: "index_ticket_sales_viewers_on_invitation_token", unique: true
    t.index ["organization_id", "user_id", "scope_type", "scope_id"], name: "idx_ticket_sales_viewers_one_active", unique: true, where: "((revoked_at IS NULL) AND (user_id IS NOT NULL))"
    t.index ["organization_id"], name: "index_ticket_sales_viewers_on_organization_id"
    t.index ["revoked_by_id"], name: "index_ticket_sales_viewers_on_revoked_by_id"
    t.index ["scope_type", "scope_id"], name: "index_ticket_sales_viewers_on_scope"
    t.index ["user_id"], name: "index_ticket_sales_viewers_on_user_id"
  end

  create_table "ticket_sources", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.integer "position", default: 0, null: false
    t.string "system_key"
    t.datetime "updated_at", null: false
    t.index ["organization_id", "position"], name: "index_ticket_sources_on_organization_id_and_position"
    t.index ["organization_id", "system_key"], name: "index_ticket_sources_on_organization_id_and_system_key", unique: true, where: "(system_key IS NOT NULL)"
    t.index ["organization_id"], name: "index_ticket_sources_on_organization_id"
  end

  create_table "ticket_tiers", force: :cascade do |t|
    t.integer "admits", default: 1, null: false
    t.datetime "archived_at"
    t.bigint "bundle_of_tier_id"
    t.datetime "created_at", null: false
    t.string "description"
    t.boolean "hidden", default: false, null: false
    t.integer "max_per_order"
    t.integer "min_per_order", default: 1, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_cents", default: 0, null: false
    t.bigint "production_ticketing_id"
    t.integer "quantity"
    t.datetime "sales_end_at"
    t.datetime "sales_start_at"
    t.bigint "source_tier_id"
    t.bigint "ticket_listing_id"
    t.string "unlock_code"
    t.datetime "updated_at", null: false
    t.index ["bundle_of_tier_id"], name: "index_ticket_tiers_on_bundle_of_tier_id"
    t.index ["production_ticketing_id"], name: "index_ticket_tiers_on_production_ticketing_id"
    t.index ["source_tier_id"], name: "index_ticket_tiers_on_source_tier_id"
    t.index ["ticket_listing_id"], name: "index_ticket_tiers_on_ticket_listing_id"
  end

  create_table "ticketing_access_grants", force: :cascade do |t|
    t.datetime "accepted_at"
    t.string "access_level", default: "check_in", null: false
    t.datetime "created_at", null: false
    t.bigint "granted_by_id"
    t.string "invitation_token"
    t.datetime "invited_at"
    t.string "invited_email"
    t.string "invited_name"
    t.bigint "organization_id", null: false
    t.datetime "revoked_at"
    t.bigint "revoked_by_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["granted_by_id"], name: "index_ticketing_access_grants_on_granted_by_id"
    t.index ["invitation_token"], name: "index_ticketing_access_grants_on_invitation_token", unique: true
    t.index ["organization_id", "invited_email"], name: "idx_ticketing_access_grants_one_pending_invite", unique: true, where: "((revoked_at IS NULL) AND (user_id IS NULL))"
    t.index ["organization_id", "user_id"], name: "idx_ticketing_access_grants_one_active", unique: true, where: "(revoked_at IS NULL)"
    t.index ["organization_id"], name: "index_ticketing_access_grants_on_organization_id"
    t.index ["revoked_by_id"], name: "index_ticketing_access_grants_on_revoked_by_id"
    t.index ["user_id"], name: "index_ticketing_access_grants_on_user_id"
  end

  create_table "ticketing_notification_logs", force: :cascade do |t|
    t.bigint "about_id", default: 0, null: false
    t.string "about_type", default: "", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.string "occasion", default: "", null: false
    t.bigint "organization_id", null: false
    t.index ["organization_id", "kind", "about_type", "about_id", "occasion"], name: "index_ticketing_notification_logs_once", unique: true
    t.index ["organization_id"], name: "index_ticketing_notification_logs_on_organization_id"
  end

  create_table "ticketing_profiles", force: :cascade do |t|
    t.string "auto_withdraw", default: "off", null: false
    t.datetime "created_at", null: false
    t.string "default_fee_mode", default: "buyer", null: false
    t.integer "default_max_per_order", default: 10, null: false
    t.boolean "enabled", default: false, null: false
    t.jsonb "notification_emails", default: [], null: false
    t.jsonb "notification_rules", default: {}, null: false
    t.bigint "organization_id", null: false
    t.jsonb "previous_slugs", default: [], null: false
    t.boolean "refunds_after_show", default: false, null: false
    t.integer "reminder_days_before", default: 2
    t.string "slug", null: false
    t.string "support_email"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_ticketing_profiles_on_organization_id", unique: true
    t.index ["previous_slugs"], name: "index_ticketing_profiles_on_previous_slugs", using: :gin
    t.index ["slug"], name: "index_ticketing_profiles_on_slug", unique: true
  end

  create_table "tickets", force: :cascade do |t|
    t.bigint "bundle_tier_id"
    t.datetime "checked_in_at"
    t.bigint "checked_in_by_id"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "discount_cents", default: 0, null: false
    t.string "external_barcode"
    t.string "holder_name"
    t.integer "price_cents", default: 0, null: false
    t.datetime "refunded_at"
    t.string "status", default: "reserved", null: false
    t.integer "tax_cents", default: 0, null: false
    t.bigint "ticket_listing_id", null: false
    t.bigint "ticket_order_id", null: false
    t.bigint "ticket_tier_id", null: false
    t.datetime "updated_at", null: false
    t.index ["bundle_tier_id"], name: "index_tickets_on_bundle_tier_id"
    t.index ["checked_in_by_id"], name: "index_tickets_on_checked_in_by_id"
    t.index ["code"], name: "index_tickets_on_code", unique: true
    t.index ["ticket_listing_id", "external_barcode"], name: "index_tickets_on_ticket_listing_id_and_external_barcode", unique: true, where: "(external_barcode IS NOT NULL)"
    t.index ["ticket_listing_id", "status"], name: "index_tickets_on_ticket_listing_id_and_status"
    t.index ["ticket_order_id"], name: "index_tickets_on_ticket_order_id"
    t.index ["ticket_tier_id"], name: "index_tickets_on_ticket_tier_id"
  end

  create_table "training_credits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "institution", limit: 200, null: false
    t.string "location", limit: 100
    t.text "notes"
    t.boolean "ongoing", default: false, null: false
    t.bigint "person_id", null: false
    t.integer "position", default: 0, null: false
    t.string "program", limit: 200, null: false
    t.datetime "updated_at", null: false
    t.integer "year_end"
    t.integer "year_start", null: false
    t.index ["person_id", "position"], name: "index_training_credits_on_person_id_and_position"
    t.index ["person_id"], name: "index_training_credits_on_person_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "default_person_id"
    t.integer "digest_throttle_days", default: 1, null: false
    t.jsonb "dismissed_guides", default: {}, null: false
    t.string "email_address", null: false
    t.datetime "email_changed_at"
    t.integer "included_production_ids", default: [], null: false, array: true
    t.datetime "invitation_sent_at"
    t.string "invitation_token"
    t.datetime "last_inbox_visit_at"
    t.datetime "last_message_digest_sent_at"
    t.datetime "last_seen_at"
    t.datetime "last_unread_digest_sent_at"
    t.boolean "message_digest_enabled", default: true
    t.jsonb "notification_preferences", default: {}, null: false
    t.string "password_digest", null: false
    t.bigint "person_id"
    t.jsonb "recent_production_ids", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["default_person_id"], name: "index_users_on_default_person_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["last_seen_at"], name: "index_users_on_last_seen_at"
    t.index ["person_id"], name: "index_users_on_person_id"
  end

  create_table "venues", force: :cascade do |t|
    t.jsonb "accessibility", default: {}, null: false
    t.string "address1"
    t.string "address2"
    t.string "city", null: false
    t.bigint "city_hub_id"
    t.string "country", default: "US", null: false
    t.datetime "created_at", null: false
    t.string "geocode_error"
    t.datetime "geocoded_at"
    t.float "lat"
    t.float "lng"
    t.string "name", null: false
    t.string "neighborhood"
    t.string "postal_code"
    t.string "state", null: false
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.integer "venue_type", default: 0, null: false
    t.index ["city", "state"], name: "index_venues_on_city_and_state"
    t.index ["city_hub_id"], name: "index_venues_on_city_hub_id"
    t.index ["lat", "lng"], name: "index_venues_on_lat_and_lng"
  end

  create_table "w9_submissions", force: :cascade do |t|
    t.string "address_line1", null: false
    t.string "address_line2"
    t.string "business_name"
    t.string "city", null: false
    t.datetime "created_at", null: false
    t.datetime "e_delivery_consented_at"
    t.string "exempt_payee_code"
    t.string "fatca_code"
    t.string "form_revision", null: false
    t.string "legal_name", null: false
    t.string "llc_tax_class"
    t.bigint "organization_id", null: false
    t.bigint "organization_staff_member_id"
    t.string "other_classification"
    t.bigint "person_id", null: false
    t.string "signature_name"
    t.datetime "signed_at", null: false
    t.string "signed_ip"
    t.string "signed_user_agent"
    t.string "source", default: "online", null: false
    t.string "state", null: false
    t.boolean "subject_to_backup_withholding", default: false, null: false
    t.datetime "superseded_at"
    t.string "tax_classification", null: false
    t.text "tin", null: false
    t.string "tin_last4", null: false
    t.string "tin_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.string "zip", null: false
    t.index ["organization_id", "person_id"], name: "idx_w9_submissions_current", unique: true, where: "(superseded_at IS NULL)"
    t.index ["organization_id"], name: "index_w9_submissions_on_organization_id"
    t.index ["organization_staff_member_id"], name: "index_w9_submissions_on_organization_staff_member_id"
    t.index ["person_id"], name: "index_w9_submissions_on_person_id"
    t.index ["uploaded_by_id"], name: "index_w9_submissions_on_uploaded_by_id"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.integer "attempts", default: 1, null: false
    t.datetime "created_at", null: false
    t.text "error"
    t.string "event_id", null: false
    t.string "event_type"
    t.datetime "processed_at"
    t.string "provider", default: "stripe", null: false
    t.string "status", default: "processing", null: false
    t.datetime "updated_at"
    t.index ["created_at"], name: "index_webhook_events_on_created_at"
    t.index ["provider", "event_id"], name: "index_webhook_events_on_provider_and_event_id", unique: true
    t.index ["status"], name: "index_webhook_events_on_status", where: "((status)::text <> 'processed'::text)"
  end

  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "advance_recoveries", "person_advances"
  add_foreign_key "advance_recoveries", "show_payout_line_items"
  add_foreign_key "agreement_requests", "agreement_templates"
  add_foreign_key "agreement_requests", "people"
  add_foreign_key "agreement_requests", "productions"
  add_foreign_key "agreement_requests", "users", column: "sent_by_id"
  add_foreign_key "agreement_signatures", "agreement_templates"
  add_foreign_key "agreement_signatures", "people"
  add_foreign_key "agreement_signatures", "productions"
  add_foreign_key "agreement_templates", "organizations"
  add_foreign_key "answers", "audition_requests"
  add_foreign_key "answers", "questions"
  add_foreign_key "audition_cycles", "productions"
  add_foreign_key "audition_email_assignments", "audition_cycles"
  add_foreign_key "audition_request_votes", "audition_requests"
  add_foreign_key "audition_request_votes", "users"
  add_foreign_key "audition_requests", "audition_cycles"
  add_foreign_key "audition_reviewers", "audition_cycles"
  add_foreign_key "audition_reviewers", "people"
  add_foreign_key "audition_session_availabilities", "audition_sessions"
  add_foreign_key "audition_sessions", "audition_cycles"
  add_foreign_key "audition_sessions", "locations"
  add_foreign_key "audition_votes", "auditions"
  add_foreign_key "audition_votes", "users"
  add_foreign_key "audition_wizard_states", "productions"
  add_foreign_key "audition_wizard_states", "users"
  add_foreign_key "auditions", "audition_requests"
  add_foreign_key "auditions", "audition_sessions"
  add_foreign_key "balance_top_ups", "organizations"
  add_foreign_key "balance_top_ups", "users", column: "requested_by_id", on_delete: :nullify
  add_foreign_key "balance_withdrawals", "organizations"
  add_foreign_key "balance_withdrawals", "users", column: "requested_by_id", on_delete: :nullify
  add_foreign_key "billing_invoices", "organizations"
  add_foreign_key "cast_assignment_stages", "talent_pools"
  add_foreign_key "casting_table_draft_assignments", "casting_tables"
  add_foreign_key "casting_table_draft_assignments", "roles"
  add_foreign_key "casting_table_draft_assignments", "shows"
  add_foreign_key "casting_table_events", "casting_tables"
  add_foreign_key "casting_table_events", "shows"
  add_foreign_key "casting_table_members", "casting_tables"
  add_foreign_key "casting_table_productions", "casting_tables"
  add_foreign_key "casting_table_productions", "productions"
  add_foreign_key "casting_tables", "organizations"
  add_foreign_key "casting_tables", "users", column: "created_by_id"
  add_foreign_key "casting_tables", "users", column: "finalized_by_id"
  add_foreign_key "city_hub_memberships", "city_hubs"
  add_foreign_key "cocoscout_ledger_entries", "organizations"
  add_foreign_key "contract_appendixes", "contracts"
  add_foreign_key "contract_documents", "contract_versions"
  add_foreign_key "contract_documents", "contracts"
  add_foreign_key "contract_invoices", "contract_payments", on_delete: :nullify
  add_foreign_key "contract_invoices", "organizations"
  add_foreign_key "contract_payments", "contracts"
  add_foreign_key "contract_payments", "shows"
  add_foreign_key "contract_service_options", "organizations"
  add_foreign_key "contract_signatures", "contract_templates"
  add_foreign_key "contract_signatures", "contract_versions"
  add_foreign_key "contract_signatures", "contracts"
  add_foreign_key "contract_signatures", "people"
  add_foreign_key "contract_templates", "organizations"
  add_foreign_key "contract_versions", "contract_templates"
  add_foreign_key "contract_versions", "contracts"
  add_foreign_key "contract_versions", "users", column: "created_by_id"
  add_foreign_key "contractors", "organizations"
  add_foreign_key "contractors", "people"
  add_foreign_key "contracts", "contract_templates"
  add_foreign_key "contracts", "contractors"
  add_foreign_key "contracts", "organizations"
  add_foreign_key "contracts", "productions"
  add_foreign_key "course_offering_instructors", "course_offerings"
  add_foreign_key "course_offering_instructors", "people"
  add_foreign_key "course_offering_payout_line_items", "course_offering_payouts"
  add_foreign_key "course_offering_payout_line_items", "users", column: "manually_paid_by_id"
  add_foreign_key "course_offering_payouts", "course_offerings"
  add_foreign_key "course_offerings", "contracts"
  add_foreign_key "course_offerings", "feature_credit_redemptions"
  add_foreign_key "course_offerings", "people", column: "instructor_person_id", on_delete: :nullify
  add_foreign_key "course_offerings", "productions"
  add_foreign_key "course_offerings", "questionnaires"
  add_foreign_key "course_offerings", "users", column: "cancelled_by_user_id"
  add_foreign_key "course_offerings", "users", column: "created_by_user_id"
  add_foreign_key "course_registrations", "course_offerings"
  add_foreign_key "course_registrations", "people"
  add_foreign_key "course_registrations", "users"
  add_foreign_key "course_registrations", "users", column: "added_by_id"
  add_foreign_key "demo_users", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "departments", "organizations"
  add_foreign_key "device_tokens", "users"
  add_foreign_key "document_productions", "production_documents"
  add_foreign_key "document_productions", "productions"
  add_foreign_key "document_shares", "production_documents"
  add_foreign_key "email_batches", "users"
  add_foreign_key "email_drafts", "shows"
  add_foreign_key "email_groups", "audition_cycles"
  add_foreign_key "email_logs", "email_batches"
  add_foreign_key "email_logs", "organizations"
  add_foreign_key "email_logs", "users"
  add_foreign_key "event_linkages", "productions"
  add_foreign_key "event_linkages", "shows", column: "primary_show_id"
  add_foreign_key "expense_items", "show_financials", column: "show_financials_id"
  add_foreign_key "feature_credit_redemptions", "feature_credits"
  add_foreign_key "feature_credit_redemptions", "organizations"
  add_foreign_key "group_invitations", "groups"
  add_foreign_key "group_memberships", "groups"
  add_foreign_key "group_memberships", "people"
  add_foreign_key "house_roles", "locations"
  add_foreign_key "house_roles", "organizations"
  add_foreign_key "journal_entries", "journal_entries", column: "reversal_of_id"
  add_foreign_key "journal_entries", "organizations"
  add_foreign_key "journal_lines", "journal_entries"
  add_foreign_key "journal_lines", "ledger_accounts"
  add_foreign_key "journal_lines", "organizations"
  add_foreign_key "ledger_accounts", "organizations"
  add_foreign_key "location_spaces", "locations"
  add_foreign_key "locations", "organizations"
  add_foreign_key "message_poll_options", "message_polls"
  add_foreign_key "message_poll_votes", "message_poll_options"
  add_foreign_key "message_poll_votes", "users"
  add_foreign_key "message_polls", "messages"
  add_foreign_key "message_reactions", "messages"
  add_foreign_key "message_reactions", "users"
  add_foreign_key "message_recipients", "messages"
  add_foreign_key "message_subscriptions", "messages"
  add_foreign_key "message_subscriptions", "users"
  add_foreign_key "messages", "organizations"
  add_foreign_key "messages", "productions"
  add_foreign_key "messages", "shows"
  add_foreign_key "mic_announcements", "mics"
  add_foreign_key "mic_challenges", "mics"
  add_foreign_key "mic_claims", "mics"
  add_foreign_key "mic_edits", "mics"
  add_foreign_key "mic_favorites", "mics"
  add_foreign_key "mic_links", "mics"
  add_foreign_key "mic_occurrence_statuses", "mics"
  add_foreign_key "mic_owners", "mics"
  add_foreign_key "mic_signup_alerts", "mics"
  add_foreign_key "mic_suggestions", "mics"
  add_foreign_key "mic_taggings", "mic_tags"
  add_foreign_key "mic_taggings", "mics"
  add_foreign_key "mics", "productions"
  add_foreign_key "mics", "venues"
  add_foreign_key "org_cash_entries", "organizations"
  add_foreign_key "org_payouts", "course_offerings"
  add_foreign_key "org_payouts", "organizations"
  add_foreign_key "org_payouts", "users", column: "paid_by_user_id"
  add_foreign_key "org_statements", "organizations"
  add_foreign_key "organization_roles", "organizations"
  add_foreign_key "organization_roles", "users"
  add_foreign_key "organization_staff_members", "organization_staff_members", column: "manager_id", on_delete: :nullify
  add_foreign_key "organization_staff_members", "organizations"
  add_foreign_key "organization_staff_members", "people"
  add_foreign_key "organization_staff_members", "staff_agreement_templates"
  add_foreign_key "organization_tax_settings", "organizations"
  add_foreign_key "organizations", "talent_pools", column: "organization_talent_pool_id"
  add_foreign_key "organizations", "users", column: "owner_id"
  add_foreign_key "payout_batch_items", "payout_batches"
  add_foreign_key "payout_batches", "organizations"
  add_foreign_key "payout_batches", "users", column: "created_by_id"
  add_foreign_key "payout_contributions", "payout_batch_items"
  add_foreign_key "payout_contributions", "payout_batches"
  add_foreign_key "payout_funding_credits", "organizations"
  add_foreign_key "payout_ledger_entries", "organizations"
  add_foreign_key "payout_scheme_defaults", "payout_schemes"
  add_foreign_key "payout_scheme_defaults", "productions"
  add_foreign_key "payout_schemes", "organizations"
  add_foreign_key "payout_schemes", "productions"
  add_foreign_key "people", "users"
  add_foreign_key "performance_credits", "performance_sections"
  add_foreign_key "performer_activations", "organizations"
  add_foreign_key "performer_activations", "people"
  add_foreign_key "person_advances", "people"
  add_foreign_key "person_advances", "productions"
  add_foreign_key "person_advances", "shows"
  add_foreign_key "person_advances", "users", column: "issued_by_id"
  add_foreign_key "person_advances", "users", column: "paid_by_id"
  add_foreign_key "person_invitations", "organizations"
  add_foreign_key "person_invitations", "talent_pools"
  add_foreign_key "posters", "productions"
  add_foreign_key "production_documents", "productions"
  add_foreign_key "production_expense_allocations", "production_expenses"
  add_foreign_key "production_expense_allocations", "shows"
  add_foreign_key "production_expenses", "productions"
  add_foreign_key "production_notification_settings", "productions"
  add_foreign_key "production_notification_settings", "users"
  add_foreign_key "production_permissions", "productions"
  add_foreign_key "production_permissions", "users"
  add_foreign_key "production_ticketing_products", "production_ticketings"
  add_foreign_key "production_ticketing_products", "ticket_products"
  add_foreign_key "production_ticketing_shows", "production_ticketings"
  add_foreign_key "production_ticketing_shows", "shows"
  add_foreign_key "production_ticketings", "organizations"
  add_foreign_key "production_ticketings", "productions"
  add_foreign_key "productions", "agreement_templates"
  add_foreign_key "productions", "organizations"
  add_foreign_key "question_options", "questions"
  add_foreign_key "questionnaire_answers", "questionnaire_responses"
  add_foreign_key "questionnaire_answers", "questions"
  add_foreign_key "questionnaire_invitations", "questionnaires"
  add_foreign_key "questionnaire_responses", "questionnaires"
  add_foreign_key "questionnaires", "organizations"
  add_foreign_key "questionnaires", "productions"
  add_foreign_key "role_eligibilities", "roles"
  add_foreign_key "role_vacancies", "roles"
  add_foreign_key "role_vacancies", "shows"
  add_foreign_key "role_vacancy_invitations", "people"
  add_foreign_key "role_vacancy_invitations", "role_vacancies"
  add_foreign_key "role_vacancy_shows", "role_vacancies"
  add_foreign_key "role_vacancy_shows", "shows"
  add_foreign_key "roles", "productions"
  add_foreign_key "roles", "shows", on_delete: :cascade
  add_foreign_key "scheduling_rules", "house_roles"
  add_foreign_key "scheduling_rules", "organizations"
  add_foreign_key "scheduling_rules", "people"
  add_foreign_key "scheduling_rules", "productions"
  add_foreign_key "sessions", "users"
  add_foreign_key "shift_additional_roles", "house_roles"
  add_foreign_key "shift_additional_roles", "shifts"
  add_foreign_key "shift_additional_roles", "shows", on_delete: :cascade
  add_foreign_key "shift_assignments", "people"
  add_foreign_key "shift_assignments", "shifts"
  add_foreign_key "shift_shows", "shifts"
  add_foreign_key "shift_shows", "shows"
  add_foreign_key "shifts", "house_roles"
  add_foreign_key "shifts", "organizations"
  add_foreign_key "short_links", "organizations"
  add_foreign_key "short_links", "users", column: "created_by_id"
  add_foreign_key "show_advance_waivers", "people"
  add_foreign_key "show_advance_waivers", "shows"
  add_foreign_key "show_advance_waivers", "users", column: "waived_by_id"
  add_foreign_key "show_attendance_records", "people"
  add_foreign_key "show_attendance_records", "show_person_role_assignments"
  add_foreign_key "show_attendance_records", "shows"
  add_foreign_key "show_attendance_records", "sign_up_registrations"
  add_foreign_key "show_availabilities", "shows"
  add_foreign_key "show_cast_notifications", "roles"
  add_foreign_key "show_cast_notifications", "shows"
  add_foreign_key "show_financials", "shows"
  add_foreign_key "show_links", "shows"
  add_foreign_key "show_payout_line_items", "show_payouts"
  add_foreign_key "show_payout_line_items", "users", column: "manually_paid_by_id"
  add_foreign_key "show_payouts", "payout_schemes"
  add_foreign_key "show_payouts", "shows"
  add_foreign_key "show_payouts", "users", column: "approved_by_id"
  add_foreign_key "show_person_role_assignments", "people"
  add_foreign_key "show_person_role_assignments", "roles"
  add_foreign_key "show_person_role_assignments", "shows"
  add_foreign_key "shows", "course_offerings"
  add_foreign_key "shows", "event_linkages"
  add_foreign_key "shows", "location_spaces"
  add_foreign_key "shows", "locations"
  add_foreign_key "shows", "productions"
  add_foreign_key "shows", "space_rentals"
  add_foreign_key "sign_up_form_holdouts", "sign_up_forms"
  add_foreign_key "sign_up_form_instances", "shows"
  add_foreign_key "sign_up_form_instances", "sign_up_forms"
  add_foreign_key "sign_up_form_shows", "shows"
  add_foreign_key "sign_up_form_shows", "sign_up_forms"
  add_foreign_key "sign_up_forms", "productions"
  add_foreign_key "sign_up_forms", "shows"
  add_foreign_key "sign_up_registrations", "people"
  add_foreign_key "sign_up_registrations", "sign_up_form_instances"
  add_foreign_key "sign_up_registrations", "sign_up_slots"
  add_foreign_key "sign_up_slots", "roles"
  add_foreign_key "sign_up_slots", "sign_up_form_instances"
  add_foreign_key "sign_up_slots", "sign_up_forms"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "space_rentals", "contracts"
  add_foreign_key "space_rentals", "location_spaces"
  add_foreign_key "space_rentals", "locations"
  add_foreign_key "staff_activations", "organizations"
  add_foreign_key "staff_activations", "people"
  add_foreign_key "staff_agreement_templates", "organizations"
  add_foreign_key "staff_availability_entries", "people"
  add_foreign_key "staff_availability_entries", "users", column: "created_by_id"
  add_foreign_key "staff_role_qualifications", "house_roles"
  add_foreign_key "staff_role_qualifications", "organization_staff_members"
  add_foreign_key "staff_schedule_removals", "organizations"
  add_foreign_key "staff_schedule_removals", "people"
  add_foreign_key "staff_time_entries", "house_roles"
  add_foreign_key "staff_time_entries", "organizations"
  add_foreign_key "staff_time_entries", "payout_batches"
  add_foreign_key "staff_time_entries", "people"
  add_foreign_key "staff_time_entries", "shift_assignments"
  add_foreign_key "staff_time_entries", "users", column: "approved_by_id"
  add_foreign_key "staff_time_entries", "users", column: "offline_paid_by_id"
  add_foreign_key "staffing_finalizations", "organizations"
  add_foreign_key "staffing_finalizations", "users", column: "finalized_by_id"
  add_foreign_key "stripe_balance_transactions", "organizations"
  add_foreign_key "stripe_balance_transactions", "users", column: "explained_by_id"
  add_foreign_key "talent_pool_memberships", "talent_pools"
  add_foreign_key "talent_pool_shares", "productions"
  add_foreign_key "talent_pool_shares", "talent_pools"
  add_foreign_key "talent_pools", "productions"
  add_foreign_key "tax_document_accesses", "organizations"
  add_foreign_key "tax_document_accesses", "users", on_delete: :nullify
  add_foreign_key "tax_document_accesses", "w9_submissions"
  add_foreign_key "tax_form_1099s", "organizations"
  add_foreign_key "tax_form_1099s", "people"
  add_foreign_key "tax_form_1099s", "tax_form_1099s", column: "corrects_id", on_delete: :nullify
  add_foreign_key "tax_form_1099s", "users", column: "generated_by_id", on_delete: :nullify
  add_foreign_key "tax_form_1099s", "w9_submissions", on_delete: :nullify
  add_foreign_key "tax_lines", "organizations"
  add_foreign_key "tax_lines", "tax_lines", column: "reversal_of_id"
  add_foreign_key "tax_lines", "tax_rates"
  add_foreign_key "tax_rates", "organizations"
  add_foreign_key "tax_rules", "organizations"
  add_foreign_key "team_invitations", "organizations"
  add_foreign_key "team_invitations", "productions"
  add_foreign_key "ticket_discount_codes", "organizations"
  add_foreign_key "ticket_discount_codes", "productions"
  add_foreign_key "ticket_discount_codes", "ticket_listings"
  add_foreign_key "ticket_exchanges", "organizations"
  add_foreign_key "ticket_exchanges", "ticket_orders", column: "from_order_id"
  add_foreign_key "ticket_exchanges", "ticket_orders", column: "to_order_id"
  add_foreign_key "ticket_exchanges", "ticket_refunds"
  add_foreign_key "ticket_exchanges", "users", column: "exchanged_by_id"
  add_foreign_key "ticket_listings", "contracts", on_delete: :nullify
  add_foreign_key "ticket_listings", "organizations"
  add_foreign_key "ticket_listings", "productions"
  add_foreign_key "ticket_listings", "shows"
  add_foreign_key "ticket_order_items", "organizations"
  add_foreign_key "ticket_order_items", "ticket_listings"
  add_foreign_key "ticket_order_items", "ticket_orders"
  add_foreign_key "ticket_order_items", "ticket_products"
  add_foreign_key "ticket_order_items", "users", column: "fulfilled_by_id"
  add_foreign_key "ticket_orders", "organizations"
  add_foreign_key "ticket_orders", "short_links"
  add_foreign_key "ticket_orders", "ticket_discount_codes", on_delete: :nullify
  add_foreign_key "ticket_orders", "ticket_listings"
  add_foreign_key "ticket_orders", "ticket_orders", column: "exchanged_from_id"
  add_foreign_key "ticket_orders", "users", column: "issued_by_id", on_delete: :nullify
  add_foreign_key "ticket_orders", "users", on_delete: :nullify
  add_foreign_key "ticket_products", "organizations"
  add_foreign_key "ticket_refunds", "organizations"
  add_foreign_key "ticket_refunds", "ticket_orders"
  add_foreign_key "ticket_refunds", "users", column: "refunded_by_id", on_delete: :nullify
  add_foreign_key "ticket_sales_lines", "show_financials", column: "show_financials_id"
  add_foreign_key "ticket_sales_lines", "ticket_sources"
  add_foreign_key "ticket_sales_viewers", "organizations"
  add_foreign_key "ticket_sales_viewers", "users"
  add_foreign_key "ticket_sales_viewers", "users", column: "granted_by_id"
  add_foreign_key "ticket_sales_viewers", "users", column: "revoked_by_id"
  add_foreign_key "ticket_sources", "organizations"
  add_foreign_key "ticket_tiers", "production_ticketings"
  add_foreign_key "ticket_tiers", "ticket_listings"
  add_foreign_key "ticket_tiers", "ticket_tiers", column: "bundle_of_tier_id"
  add_foreign_key "ticket_tiers", "ticket_tiers", column: "source_tier_id"
  add_foreign_key "ticketing_access_grants", "organizations"
  add_foreign_key "ticketing_access_grants", "users", column: "granted_by_id", on_delete: :nullify
  add_foreign_key "ticketing_access_grants", "users", column: "revoked_by_id", on_delete: :nullify
  add_foreign_key "ticketing_access_grants", "users", on_delete: :cascade
  add_foreign_key "ticketing_notification_logs", "organizations"
  add_foreign_key "ticketing_profiles", "organizations"
  add_foreign_key "tickets", "ticket_listings"
  add_foreign_key "tickets", "ticket_orders"
  add_foreign_key "tickets", "ticket_tiers"
  add_foreign_key "tickets", "ticket_tiers", column: "bundle_tier_id"
  add_foreign_key "tickets", "users", column: "checked_in_by_id", on_delete: :nullify
  add_foreign_key "training_credits", "people"
  add_foreign_key "users", "people"
  add_foreign_key "users", "people", column: "default_person_id"
  add_foreign_key "venues", "city_hubs"
  add_foreign_key "w9_submissions", "organization_staff_members", on_delete: :nullify
  add_foreign_key "w9_submissions", "organizations"
  add_foreign_key "w9_submissions", "people"
  add_foreign_key "w9_submissions", "users", column: "uploaded_by_id"
end
