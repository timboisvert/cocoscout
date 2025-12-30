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

ActiveRecord::Schema[8.1].define(version: 2025_12_29_230624) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
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
    t.datetime "opens_at"
    t.integer "production_id", null: false
    t.boolean "require_all_audition_availability", default: false
    t.boolean "require_all_availability", default: false
    t.string "reviewer_access_type", default: "managers", null: false
    t.text "success_text"
    t.string "token"
    t.datetime "updated_at", null: false
    t.boolean "voting_enabled", default: true, null: false
    t.index ["production_id", "active"], name: "index_audition_cycles_on_production_id_and_active", unique: true, where: "active = true"
    t.index ["production_id"], name: "index_audition_cycles_on_production_id"
  end

  create_table "audition_email_assignments", force: :cascade do |t|
    t.integer "assignable_id"
    t.string "assignable_type"
    t.integer "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.string "email_group_id"
    t.datetime "updated_at", null: false
    t.index ["assignable_type", "assignable_id", "audition_cycle_id"], name: "index_audition_email_assignments_on_assignable_and_cycle", unique: true
    t.index ["audition_cycle_id"], name: "index_audition_email_assignments_on_audition_cycle_id"
  end

  create_table "audition_request_votes", force: :cascade do |t|
    t.integer "audition_request_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "vote", default: 0, null: false
    t.index ["audition_request_id", "user_id"], name: "index_audition_request_votes_unique", unique: true
    t.index ["audition_request_id"], name: "index_audition_request_votes_on_audition_request_id"
    t.index ["user_id"], name: "index_audition_request_votes_on_user_id"
  end

  create_table "audition_requests", force: :cascade do |t|
    t.integer "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.datetime "invitation_notification_sent_at"
    t.boolean "notified_scheduled"
    t.string "notified_status"
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
    t.integer "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.integer "person_id", null: false
    t.datetime "updated_at", null: false
    t.index ["audition_cycle_id"], name: "index_audition_reviewers_on_audition_cycle_id"
    t.index ["person_id"], name: "index_audition_reviewers_on_person_id"
  end

  create_table "audition_session_availabilities", force: :cascade do |t|
    t.integer "audition_session_id", null: false
    t.integer "available_entity_id", null: false
    t.string "available_entity_type", null: false
    t.datetime "created_at", null: false
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.index ["audition_session_id"], name: "index_audition_session_availabilities_on_audition_session_id"
    t.index ["available_entity_id", "available_entity_type", "audition_session_id"], name: "index_audition_session_avail_on_entity_and_session", unique: true
    t.index ["available_entity_type", "available_entity_id"], name: "index_audition_session_availabilities_on_available_entity"
  end

  create_table "audition_sessions", force: :cascade do |t|
    t.integer "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.datetime "end_at"
    t.integer "location_id"
    t.integer "maximum_auditionees"
    t.datetime "start_at"
    t.datetime "updated_at", null: false
    t.index ["audition_cycle_id"], name: "index_audition_sessions_on_audition_cycle_id"
    t.index ["location_id"], name: "index_audition_sessions_on_location_id"
  end

  create_table "audition_votes", force: :cascade do |t|
    t.integer "audition_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "vote", default: 0, null: false
    t.index ["audition_id", "user_id"], name: "index_audition_votes_unique", unique: true
    t.index ["audition_id"], name: "index_audition_votes_on_audition_id"
    t.index ["user_id"], name: "index_audition_votes_on_user_id"
  end

  create_table "auditions", force: :cascade do |t|
    t.integer "audition_request_id", null: false
    t.integer "audition_session_id"
    t.integer "auditionable_id"
    t.string "auditionable_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["audition_request_id"], name: "index_auditions_on_audition_request_id"
    t.index ["audition_session_id"], name: "index_auditions_on_audition_session_id"
    t.index ["auditionable_type", "auditionable_id"], name: "index_auditions_on_auditionable"
  end

  create_table "calendar_events", force: :cascade do |t|
    t.integer "calendar_subscription_id", null: false
    t.datetime "created_at", null: false
    t.string "last_sync_hash"
    t.datetime "last_synced_at"
    t.string "provider_event_id", null: false
    t.integer "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["calendar_subscription_id", "show_id"], name: "index_calendar_events_on_calendar_subscription_id_and_show_id", unique: true
    t.index ["calendar_subscription_id"], name: "index_calendar_events_on_calendar_subscription_id"
    t.index ["provider_event_id"], name: "index_calendar_events_on_provider_event_id"
    t.index ["show_id"], name: "index_calendar_events_on_show_id"
  end

  create_table "calendar_subscriptions", force: :cascade do |t|
    t.text "access_token_ciphertext"
    t.string "calendar_id"
    t.datetime "created_at", null: false
    t.string "email"
    t.boolean "enabled", default: true, null: false
    t.string "ical_token"
    t.text "last_sync_error"
    t.datetime "last_synced_at"
    t.integer "person_id", null: false
    t.string "provider", null: false
    t.text "refresh_token_ciphertext"
    t.json "sync_entities", default: []
    t.string "sync_scope", default: "assigned", null: false
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.index ["ical_token"], name: "index_calendar_subscriptions_on_ical_token", unique: true
    t.index ["person_id", "provider"], name: "index_calendar_subscriptions_on_person_id_and_provider", unique: true
    t.index ["person_id"], name: "index_calendar_subscriptions_on_person_id"
  end

  create_table "cast_assignment_stages", force: :cascade do |t|
    t.integer "assignable_id"
    t.string "assignable_type"
    t.integer "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.string "email_group_id"
    t.text "notification_email"
    t.integer "status", default: 0, null: false
    t.integer "talent_pool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assignable_type", "assignable_id"], name: "idx_on_assignable_type_assignable_id_366d98058e"
    t.index ["audition_cycle_id", "talent_pool_id", "assignable_type", "assignable_id"], name: "index_cast_assignment_stages_unique", unique: true
    t.index ["audition_cycle_id"], name: "index_cast_assignment_stages_on_audition_cycle_id"
    t.index ["talent_pool_id"], name: "index_cast_assignment_stages_on_talent_pool_id"
  end

  create_table "email_batches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "mailer_action"
    t.string "mailer_class"
    t.integer "recipient_count"
    t.datetime "sent_at"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_email_batches_on_user_id"
  end

  create_table "email_drafts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "emailable_id"
    t.string "emailable_type"
    t.integer "show_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["emailable_type", "emailable_id"], name: "index_email_drafts_on_emailable"
    t.index ["show_id"], name: "index_email_drafts_on_show_id"
  end

  create_table "email_groups", force: :cascade do |t|
    t.integer "audition_cycle_id", null: false
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
    t.integer "email_batch_id"
    t.text "error_message"
    t.string "mailer_action"
    t.string "mailer_class"
    t.string "message_id"
    t.integer "organization_id"
    t.string "recipient", null: false
    t.integer "recipient_entity_id"
    t.string "recipient_entity_type"
    t.datetime "sent_at"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["email_batch_id"], name: "index_email_logs_on_email_batch_id"
    t.index ["message_id"], name: "index_email_logs_on_message_id"
    t.index ["organization_id"], name: "index_email_logs_on_organization_id"
    t.index ["recipient"], name: "index_email_logs_on_recipient"
    t.index ["recipient_entity_type", "recipient_entity_id"], name: "index_email_logs_on_recipient_entity"
    t.index ["sent_at", "user_id"], name: "index_email_logs_on_sent_at_desc_user_id", order: { sent_at: :desc }
    t.index ["sent_at"], name: "index_email_logs_on_sent_at"
    t.index ["user_id"], name: "index_email_logs_on_user_id"
  end

  create_table "event_linkages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "primary_show_id"
    t.integer "production_id", null: false
    t.datetime "updated_at", null: false
    t.index ["primary_show_id"], name: "index_event_linkages_on_primary_show_id"
    t.index ["production_id"], name: "index_event_linkages_on_production_id"
  end

  create_table "group_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.integer "group_id", null: false
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
    t.integer "group_id", null: false
    t.text "notification_preferences"
    t.integer "permission_level", default: 0, null: false
    t.integer "person_id", null: false
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

  create_table "invitations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.integer "organization_id", null: false
    t.integer "status", default: 0, null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["organization_id"], name: "index_invitations_on_organization_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
    t.index ["user_id"], name: "index_invitations_on_user_id"
  end

  create_table "locations", force: :cascade do |t|
    t.string "address1"
    t.string "address2"
    t.string "city"
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.string "name"
    t.text "notes"
    t.integer "organization_id"
    t.string "postal_code"
    t.string "state"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_locations_on_organization_id"
  end

  create_table "organization_roles", force: :cascade do |t|
    t.string "company_role", null: false
    t.datetime "created_at", null: false
    t.boolean "notifications_enabled"
    t.integer "organization_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["organization_id"], name: "index_organization_roles_on_organization_id"
    t.index ["user_id", "organization_id"], name: "index_organization_roles_on_user_id_and_organization_id", unique: true
    t.index ["user_id"], name: "index_organization_roles_on_user_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "owner_id", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_organizations_on_owner_id"
  end

  create_table "organizations_people", id: false, force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "person_id", null: false
    t.index ["organization_id", "person_id"], name: "index_organizations_people_on_organization_id_and_person_id"
    t.index ["person_id", "organization_id"], name: "index_organizations_people_on_person_id_and_organization_id"
  end

  create_table "people", force: :cascade do |t|
    t.datetime "archived_at"
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
    t.boolean "performance_credits_visible", default: true, null: false
    t.string "phone"
    t.boolean "profile_skills_visible", default: true, null: false
    t.text "profile_visibility_settings", default: "{}"
    t.datetime "profile_welcomed_at"
    t.string "pronouns"
    t.string "public_key"
    t.datetime "public_key_changed_at"
    t.boolean "public_profile_enabled", default: true, null: false
    t.boolean "resumes_visible", default: true, null: false
    t.boolean "social_media_visible", default: true, null: false
    t.boolean "training_credits_visible", default: true, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.boolean "videos_visible", default: true, null: false
    t.index ["archived_at"], name: "index_people_on_archived_at"
    t.index ["created_at"], name: "index_people_on_created_at"
    t.index ["email"], name: "index_people_on_email"
    t.index ["name"], name: "index_people_on_name"
    t.index ["public_key"], name: "index_people_on_public_key", unique: true
    t.index ["user_id"], name: "index_people_on_user_id"
  end

  create_table "performance_credits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "link_url"
    t.string "location", limit: 100
    t.text "notes", limit: 1000
    t.boolean "ongoing", default: false, null: false
    t.integer "performance_section_id"
    t.integer "position", default: 0, null: false
    t.integer "profileable_id", null: false
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
    t.integer "profileable_id", null: false
    t.string "profileable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["profileable_type", "profileable_id", "position"], name: "idx_on_profileable_type_profileable_id_position_59d6099064"
    t.index ["profileable_type", "profileable_id"], name: "index_performance_sections_on_profileable"
  end

  create_table "person_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "declined_at"
    t.string "email", null: false
    t.integer "organization_id"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_person_invitations_on_organization_id"
    t.index ["token"], name: "index_person_invitations_on_token", unique: true
  end

  create_table "posters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_primary", default: false, null: false
    t.string "name"
    t.integer "production_id", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id", "is_primary"], name: "index_posters_on_production_id_primary", unique: true, where: "is_primary = true"
    t.index ["production_id"], name: "index_posters_on_production_id"
  end

  create_table "production_permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "notifications_enabled"
    t.integer "production_id", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["production_id"], name: "index_production_permissions_on_production_id"
    t.index ["user_id", "production_id"], name: "index_production_permissions_on_user_id_and_production_id", unique: true
    t.index ["user_id"], name: "index_production_permissions_on_user_id"
  end

  create_table "productions", force: :cascade do |t|
    t.boolean "auto_create_event_pages", default: true
    t.string "auto_create_event_pages_mode", default: "all"
    t.text "cast_talent_pool_ids"
    t.string "contact_email"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "event_visibility_overrides"
    t.string "name"
    t.text "old_keys"
    t.integer "organization_id", null: false
    t.string "public_key"
    t.datetime "public_key_changed_at"
    t.boolean "public_profile_enabled", default: true
    t.boolean "show_cast_members", default: true, null: false
    t.text "show_upcoming_event_types"
    t.boolean "show_upcoming_events", default: true, null: false
    t.string "show_upcoming_events_mode", default: "all"
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_productions_on_organization_id"
    t.index ["public_key"], name: "index_productions_on_public_key", unique: true
  end

  create_table "profile_headshots", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.boolean "is_primary", default: false, null: false
    t.integer "position", default: 0, null: false
    t.integer "profileable_id", null: false
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
    t.integer "profileable_id", null: false
    t.string "profileable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["profileable_type", "profileable_id", "position"], name: "idx_on_profileable_type_profileable_id_position_656777844d"
    t.index ["profileable_type", "profileable_id"], name: "index_profile_resumes_on_profileable"
  end

  create_table "profile_skills", force: :cascade do |t|
    t.string "category", limit: 50, null: false
    t.datetime "created_at", null: false
    t.integer "profileable_id", null: false
    t.string "profileable_type", null: false
    t.string "skill_name", limit: 50, null: false
    t.datetime "updated_at", null: false
    t.index ["profileable_type", "profileable_id", "category", "skill_name"], name: "index_profile_skills_unique", unique: true
    t.index ["profileable_type", "profileable_id"], name: "index_profile_skills_on_profileable"
  end

  create_table "profile_videos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.integer "profileable_id", null: false
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
    t.integer "question_id", null: false
    t.integer "questionnaire_response_id", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["question_id"], name: "index_questionnaire_answers_on_question_id"
    t.index ["questionnaire_response_id", "question_id"], name: "index_q_answers_on_response_and_question", unique: true
    t.index ["questionnaire_response_id"], name: "index_questionnaire_answers_on_questionnaire_response_id"
  end

  create_table "questionnaire_invitations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "invitee_id"
    t.string "invitee_type"
    t.integer "questionnaire_id", null: false
    t.datetime "updated_at", null: false
    t.index ["invitee_type", "invitee_id", "questionnaire_id"], name: "index_questionnaire_invitations_unique", unique: true
    t.index ["invitee_type", "invitee_id"], name: "index_questionnaire_invitations_on_invitee_type_and_invitee_id"
    t.index ["questionnaire_id"], name: "index_questionnaire_invitations_on_questionnaire_id"
  end

  create_table "questionnaire_responses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "questionnaire_id", null: false
    t.integer "respondent_id"
    t.string "respondent_type"
    t.datetime "updated_at", null: false
    t.index ["questionnaire_id"], name: "index_questionnaire_responses_on_questionnaire_id"
    t.index ["respondent_type", "respondent_id", "questionnaire_id"], name: "index_questionnaire_responses_unique", unique: true
    t.index ["respondent_type", "respondent_id"], name: "idx_on_respondent_type_respondent_id_7f07f0f816"
  end

  create_table "questionnaires", force: :cascade do |t|
    t.boolean "accepting_responses", default: true, null: false
    t.datetime "archived_at"
    t.text "availability_show_ids"
    t.datetime "created_at", null: false
    t.boolean "include_availability_section", default: false, null: false
    t.integer "production_id", null: false
    t.boolean "require_all_availability", default: false, null: false
    t.string "title", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
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
    t.integer "member_id", null: false
    t.string "member_type", null: false
    t.integer "role_id", null: false
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
    t.integer "role_id"
    t.integer "show_id", null: false
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
    t.integer "person_id", null: false
    t.integer "role_vacancy_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_role_vacancy_invitations_on_person_id"
    t.index ["role_vacancy_id", "person_id"], name: "idx_vacancy_invitations_on_vacancy_and_person", unique: true
    t.index ["role_vacancy_id"], name: "index_role_vacancy_invitations_on_role_vacancy_id"
    t.index ["token"], name: "index_role_vacancy_invitations_on_token", unique: true
  end

  create_table "role_vacancy_shows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "role_vacancy_id", null: false
    t.integer "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["role_vacancy_id", "show_id"], name: "index_role_vacancy_shows_on_role_vacancy_id_and_show_id", unique: true
    t.index ["role_vacancy_id"], name: "index_role_vacancy_shows_on_role_vacancy_id"
    t.index ["show_id"], name: "index_role_vacancy_shows_on_show_id"
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "position"
    t.integer "production_id", null: false
    t.boolean "restricted", default: false, null: false
    t.integer "show_id"
    t.datetime "updated_at", null: false
    t.index ["production_id", "show_id", "name"], name: "index_roles_on_production_show_name", unique: true
    t.index ["show_id"], name: "index_roles_on_show_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shoutouts", force: :cascade do |t|
    t.integer "author_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "replaces_shoutout_id"
    t.integer "shoutee_id", null: false
    t.string "shoutee_type", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id", "created_at"], name: "index_shoutouts_on_author_and_created"
    t.index ["author_id"], name: "index_shoutouts_on_author_id"
    t.index ["replaces_shoutout_id"], name: "index_shoutouts_on_replaces_shoutout_id"
    t.index ["shoutee_type", "shoutee_id", "created_at"], name: "index_shoutouts_on_shoutee_and_created"
    t.index ["shoutee_type", "shoutee_id"], name: "index_shoutouts_on_shoutee"
  end

  create_table "show_availabilities", force: :cascade do |t|
    t.integer "available_entity_id"
    t.string "available_entity_type"
    t.datetime "created_at", null: false
    t.integer "show_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["available_entity_type", "available_entity_id", "show_id"], name: "index_show_availabilities_unique", unique: true
    t.index ["available_entity_type", "available_entity_id"], name: "index_show_availabilities_on_entity"
    t.index ["show_id"], name: "index_show_availabilities_on_show_id"
  end

  create_table "show_cast_notifications", force: :cascade do |t|
    t.integer "assignable_id", null: false
    t.string "assignable_type", null: false
    t.datetime "created_at", null: false
    t.text "email_body"
    t.integer "notification_type", default: 0, null: false
    t.datetime "notified_at", null: false
    t.integer "role_id", null: false
    t.integer "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assignable_type", "assignable_id"], name: "index_show_cast_notifications_on_assignable"
    t.index ["role_id"], name: "index_show_cast_notifications_on_role_id"
    t.index ["show_id", "assignable_type", "assignable_id", "role_id"], name: "idx_show_cast_notifications_unique", unique: true
    t.index ["show_id"], name: "index_show_cast_notifications_on_show_id"
  end

  create_table "show_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "show_id", null: false
    t.string "text"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["show_id"], name: "index_show_links_on_show_id"
  end

  create_table "show_person_role_assignments", force: :cascade do |t|
    t.bigint "assignable_id"
    t.string "assignable_type"
    t.datetime "created_at", null: false
    t.integer "person_id"
    t.integer "role_id"
    t.integer "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assignable_type", "assignable_id"], name: "index_show_role_assignments_on_assignable"
    t.index ["person_id"], name: "index_show_person_role_assignments_on_person_id"
    t.index ["role_id"], name: "index_show_person_role_assignments_on_role_id"
    t.index ["show_id"], name: "index_show_person_role_assignments_on_show_id"
  end

  create_table "shows", force: :cascade do |t|
    t.datetime "call_time"
    t.boolean "call_time_enabled", default: false, null: false
    t.boolean "canceled", default: false, null: false
    t.boolean "casting_enabled", default: true, null: false
    t.datetime "casting_finalized_at"
    t.datetime "created_at", null: false
    t.datetime "date_and_time"
    t.integer "event_linkage_id"
    t.string "event_type"
    t.boolean "is_online", default: false, null: false
    t.string "linkage_role"
    t.integer "location_id"
    t.string "online_location_info"
    t.integer "production_id", null: false
    t.boolean "public_profile_visible"
    t.string "recurrence_group_id"
    t.string "secondary_name"
    t.datetime "updated_at", null: false
    t.boolean "use_custom_roles", default: false, null: false
    t.index ["event_linkage_id"], name: "index_shows_on_event_linkage_id"
    t.index ["location_id"], name: "index_shows_on_location_id"
    t.index ["production_id"], name: "index_shows_on_production_id"
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

  create_table "talent_pool_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "member_id", null: false
    t.string "member_type", null: false
    t.integer "talent_pool_id", null: false
    t.datetime "updated_at", null: false
    t.index ["member_type", "member_id", "talent_pool_id"], name: "index_tpm_on_member_and_pool"
    t.index ["member_type", "member_id"], name: "index_talent_pool_memberships_on_member_type_and_member_id"
    t.index ["talent_pool_id", "member_type", "member_id"], name: "index_talent_pool_memberships_unique", unique: true
    t.index ["talent_pool_id"], name: "index_talent_pool_memberships_on_talent_pool_id"
  end

  create_table "talent_pools", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "production_id", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id"], name: "index_talent_pools_on_production_id"
  end

  create_table "team_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.boolean "invitation_notifications_enabled", default: true
    t.string "invitation_role", default: "viewer"
    t.integer "organization_id", null: false
    t.integer "production_id"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_team_invitations_on_organization_id"
    t.index ["production_id"], name: "index_team_invitations_on_production_id"
    t.index ["token"], name: "index_team_invitations_on_token", unique: true
  end

  create_table "training_credits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "institution", limit: 200, null: false
    t.string "location", limit: 100
    t.text "notes", limit: 1000
    t.boolean "ongoing", default: false, null: false
    t.integer "person_id", null: false
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
    t.integer "default_person_id"
    t.string "email_address", null: false
    t.datetime "email_changed_at"
    t.datetime "invitation_sent_at"
    t.string "invitation_token"
    t.datetime "last_seen_at"
    t.string "password_digest", null: false
    t.datetime "password_reset_sent_at"
    t.string "password_reset_token"
    t.integer "person_id"
    t.datetime "updated_at", null: false
    t.datetime "welcomed_at"
    t.datetime "welcomed_production_at"
    t.index ["default_person_id"], name: "index_users_on_default_person_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["last_seen_at"], name: "index_users_on_last_seen_at"
    t.index ["password_reset_token"], name: "index_users_on_password_reset_token", unique: true
    t.index ["person_id"], name: "index_users_on_person_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
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
  add_foreign_key "auditions", "audition_requests"
  add_foreign_key "auditions", "audition_sessions"
  add_foreign_key "calendar_events", "calendar_subscriptions"
  add_foreign_key "calendar_events", "shows"
  add_foreign_key "calendar_subscriptions", "people"
  add_foreign_key "cast_assignment_stages", "talent_pools"
  add_foreign_key "email_batches", "users"
  add_foreign_key "email_drafts", "shows"
  add_foreign_key "email_groups", "audition_cycles"
  add_foreign_key "email_logs", "email_batches"
  add_foreign_key "email_logs", "organizations"
  add_foreign_key "email_logs", "users"
  add_foreign_key "event_linkages", "productions"
  add_foreign_key "event_linkages", "shows", column: "primary_show_id"
  add_foreign_key "group_invitations", "groups"
  add_foreign_key "group_memberships", "groups"
  add_foreign_key "group_memberships", "people"
  add_foreign_key "invitations", "organizations"
  add_foreign_key "invitations", "users"
  add_foreign_key "locations", "organizations"
  add_foreign_key "organization_roles", "organizations"
  add_foreign_key "organization_roles", "users"
  add_foreign_key "organizations", "users", column: "owner_id"
  add_foreign_key "people", "users"
  add_foreign_key "performance_credits", "performance_sections"
  add_foreign_key "person_invitations", "organizations"
  add_foreign_key "posters", "productions"
  add_foreign_key "production_permissions", "productions"
  add_foreign_key "production_permissions", "users"
  add_foreign_key "productions", "organizations"
  add_foreign_key "question_options", "questions"
  add_foreign_key "questionnaire_answers", "questionnaire_responses"
  add_foreign_key "questionnaire_answers", "questions"
  add_foreign_key "questionnaire_invitations", "questionnaires"
  add_foreign_key "questionnaire_responses", "questionnaires"
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
  add_foreign_key "sessions", "users"
  add_foreign_key "shoutouts", "people", column: "author_id"
  add_foreign_key "show_availabilities", "shows"
  add_foreign_key "show_cast_notifications", "roles"
  add_foreign_key "show_cast_notifications", "shows"
  add_foreign_key "show_links", "shows"
  add_foreign_key "show_person_role_assignments", "people"
  add_foreign_key "show_person_role_assignments", "roles"
  add_foreign_key "show_person_role_assignments", "shows"
  add_foreign_key "shows", "event_linkages"
  add_foreign_key "shows", "locations"
  add_foreign_key "shows", "productions"
  add_foreign_key "talent_pool_memberships", "talent_pools"
  add_foreign_key "talent_pools", "productions"
  add_foreign_key "team_invitations", "organizations"
  add_foreign_key "team_invitations", "productions"
  add_foreign_key "training_credits", "people"
  add_foreign_key "users", "people"
  add_foreign_key "users", "people", column: "default_person_id"
end
