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

ActiveRecord::Schema[8.1].define(version: 2025_11_18_203859) do
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
    t.string "audition_type", default: "in_person", null: false
    t.text "availability_show_ids"
    t.datetime "casting_finalized_at"
    t.datetime "closes_at"
    t.datetime "created_at", null: false
    t.boolean "finalize_audition_invitations", default: false
    t.boolean "form_reviewed", default: false
    t.text "header_text"
    t.boolean "include_availability_section", default: false
    t.datetime "opens_at"
    t.integer "production_id", null: false
    t.boolean "require_all_availability", default: false
    t.text "success_text"
    t.string "token"
    t.datetime "updated_at", null: false
    t.index ["production_id", "active"], name: "index_audition_cycles_on_production_id_and_active", unique: true, where: "active = true"
    t.index ["production_id"], name: "index_audition_cycles_on_production_id"
  end

  create_table "audition_email_assignments", force: :cascade do |t|
    t.integer "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.string "email_group_id"
    t.integer "person_id", null: false
    t.datetime "updated_at", null: false
    t.index ["audition_cycle_id"], name: "index_audition_email_assignments_on_audition_cycle_id"
    t.index ["person_id"], name: "index_audition_email_assignments_on_person_id"
  end

  create_table "audition_requests", force: :cascade do |t|
    t.integer "audition_cycle_id", null: false
    t.datetime "created_at", null: false
    t.datetime "invitation_notification_sent_at"
    t.boolean "notified_scheduled"
    t.string "notified_status"
    t.integer "person_id", null: false
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.string "video_url"
    t.index ["audition_cycle_id"], name: "index_audition_requests_on_audition_cycle_id"
    t.index ["person_id"], name: "index_audition_requests_on_person_id"
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

  create_table "auditions", force: :cascade do |t|
    t.integer "audition_request_id", null: false
    t.integer "audition_session_id"
    t.datetime "created_at", null: false
    t.integer "person_id", null: false
    t.datetime "updated_at", null: false
    t.index ["audition_request_id"], name: "index_auditions_on_audition_request_id"
    t.index ["audition_session_id"], name: "index_auditions_on_audition_session_id"
    t.index ["person_id"], name: "index_auditions_on_person_id"
  end

  create_table "cast_assignment_stages", force: :cascade do |t|
    t.integer "audition_cycle_id", null: false
    t.integer "cast_id", null: false
    t.datetime "created_at", null: false
    t.string "email_group_id"
    t.text "notification_email"
    t.integer "person_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["audition_cycle_id"], name: "index_cast_assignment_stages_on_audition_cycle_id"
    t.index ["cast_id", "person_id"], name: "index_cast_assignment_stages_unique", unique: true
    t.index ["cast_id"], name: "index_cast_assignment_stages_on_cast_id"
    t.index ["person_id"], name: "index_cast_assignment_stages_on_person_id"
  end

  create_table "casts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "production_id", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id"], name: "index_casts_on_production_id"
  end

  create_table "casts_people", id: false, force: :cascade do |t|
    t.integer "cast_id"
    t.integer "person_id"
    t.index ["cast_id"], name: "index_casts_people_on_cast_id"
    t.index ["person_id"], name: "index_casts_people_on_person_id"
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
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "delivery_status", default: "pending"
    t.text "error_message"
    t.string "mailer_action"
    t.string "mailer_class"
    t.string "message_id"
    t.string "recipient", null: false
    t.datetime "sent_at"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["message_id"], name: "index_email_logs_on_message_id"
    t.index ["recipient"], name: "index_email_logs_on_recipient"
    t.index ["sent_at"], name: "index_email_logs_on_sent_at"
    t.index ["user_id"], name: "index_email_logs_on_user_id"
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

  create_table "notify_mes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "updated_at", null: false
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
    t.datetime "casting_notification_sent_at"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.integer "notified_for_audition_cycle_id"
    t.string "pronouns"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["user_id"], name: "index_people_on_user_id"
  end

  create_table "person_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.integer "organization_id", null: false
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
    t.integer "production_id", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["production_id"], name: "index_production_permissions_on_production_id"
    t.index ["user_id", "production_id"], name: "index_production_permissions_on_user_id_and_production_id", unique: true
    t.index ["user_id"], name: "index_production_permissions_on_user_id"
  end

  create_table "productions", force: :cascade do |t|
    t.string "contact_email"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.integer "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_productions_on_organization_id"
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
    t.string "value"
    t.index ["question_id"], name: "index_questionnaire_answers_on_question_id"
    t.index ["questionnaire_response_id", "question_id"], name: "index_q_answers_on_response_and_question", unique: true
    t.index ["questionnaire_response_id"], name: "index_questionnaire_answers_on_questionnaire_response_id"
  end

  create_table "questionnaire_invitations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "person_id", null: false
    t.integer "questionnaire_id", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_questionnaire_invitations_on_person_id"
    t.index ["questionnaire_id", "person_id"], name: "index_q_invitations_on_questionnaire_and_person", unique: true
    t.index ["questionnaire_id"], name: "index_questionnaire_invitations_on_questionnaire_id"
  end

  create_table "questionnaire_responses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "person_id", null: false
    t.integer "questionnaire_id", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_questionnaire_responses_on_person_id"
    t.index ["questionnaire_id", "person_id"], name: "idx_on_questionnaire_id_person_id_14b49cba13", unique: true
    t.index ["questionnaire_id"], name: "index_questionnaire_responses_on_questionnaire_id"
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

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "position"
    t.integer "production_id", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id"], name: "index_roles_on_production_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "show_availabilities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "person_id", null: false
    t.integer "show_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["person_id", "show_id"], name: "index_show_availabilities_on_person_id_and_show_id", unique: true
    t.index ["person_id"], name: "index_show_availabilities_on_person_id"
    t.index ["show_id"], name: "index_show_availabilities_on_show_id"
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
    t.datetime "created_at", null: false
    t.integer "person_id", null: false
    t.integer "role_id", null: false
    t.integer "show_id", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_show_person_role_assignments_on_person_id"
    t.index ["role_id"], name: "index_show_person_role_assignments_on_role_id"
    t.index ["show_id"], name: "index_show_person_role_assignments_on_show_id"
  end

  create_table "shows", force: :cascade do |t|
    t.boolean "canceled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "date_and_time"
    t.string "event_type"
    t.integer "location_id"
    t.integer "production_id", null: false
    t.string "recurrence_group_id"
    t.string "secondary_name"
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_shows_on_location_id"
    t.index ["production_id"], name: "index_shows_on_production_id"
  end

  create_table "socials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "handle", null: false
    t.integer "person_id", null: false
    t.string "platform", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_socials_on_person_id"
  end

  create_table "team_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.integer "organization_id", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_team_invitations_on_organization_id"
    t.index ["token"], name: "index_team_invitations_on_token", unique: true
  end

  create_table "user_roles", force: :cascade do |t|
    t.string "company_role", null: false
    t.datetime "created_at", null: false
    t.integer "organization_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["organization_id"], name: "index_user_roles_on_organization_id"
    t.index ["user_id", "organization_id"], name: "index_user_roles_on_user_id_and_organization_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.datetime "invitation_sent_at"
    t.string "invitation_token"
    t.string "password_digest", null: false
    t.datetime "password_reset_sent_at"
    t.string "password_reset_token"
    t.integer "person_id"
    t.datetime "updated_at", null: false
    t.datetime "welcomed_at"
    t.datetime "welcomed_production_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["invitation_token"], name: "index_users_on_invitation_token", unique: true
    t.index ["password_reset_token"], name: "index_users_on_password_reset_token", unique: true
    t.index ["person_id"], name: "index_users_on_person_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "answers", "audition_requests"
  add_foreign_key "answers", "questions"
  add_foreign_key "audition_cycles", "productions"
  add_foreign_key "audition_email_assignments", "audition_cycles"
  add_foreign_key "audition_email_assignments", "people"
  add_foreign_key "audition_requests", "audition_cycles"
  add_foreign_key "audition_requests", "people"
  add_foreign_key "audition_sessions", "audition_cycles"
  add_foreign_key "audition_sessions", "locations"
  add_foreign_key "auditions", "audition_requests"
  add_foreign_key "auditions", "audition_sessions"
  add_foreign_key "auditions", "people"
  add_foreign_key "cast_assignment_stages", "casts"
  add_foreign_key "cast_assignment_stages", "people"
  add_foreign_key "casts", "productions"
  add_foreign_key "email_groups", "audition_cycles"
  add_foreign_key "email_logs", "users"
  add_foreign_key "invitations", "organizations"
  add_foreign_key "invitations", "users"
  add_foreign_key "locations", "organizations"
  add_foreign_key "organizations", "users", column: "owner_id"
  add_foreign_key "people", "users"
  add_foreign_key "person_invitations", "organizations"
  add_foreign_key "posters", "productions"
  add_foreign_key "production_permissions", "productions"
  add_foreign_key "production_permissions", "users"
  add_foreign_key "productions", "organizations"
  add_foreign_key "question_options", "questions"
  add_foreign_key "questionnaire_answers", "questionnaire_responses"
  add_foreign_key "questionnaire_answers", "questions"
  add_foreign_key "questionnaire_invitations", "people"
  add_foreign_key "questionnaire_invitations", "questionnaires"
  add_foreign_key "questionnaire_responses", "people"
  add_foreign_key "questionnaire_responses", "questionnaires"
  add_foreign_key "questionnaires", "productions"
  add_foreign_key "roles", "productions"
  add_foreign_key "sessions", "users"
  add_foreign_key "show_availabilities", "people"
  add_foreign_key "show_availabilities", "shows"
  add_foreign_key "show_links", "shows"
  add_foreign_key "show_person_role_assignments", "people"
  add_foreign_key "show_person_role_assignments", "roles"
  add_foreign_key "show_person_role_assignments", "shows"
  add_foreign_key "shows", "locations"
  add_foreign_key "shows", "productions"
  add_foreign_key "socials", "people"
  add_foreign_key "team_invitations", "organizations"
  add_foreign_key "user_roles", "organizations"
  add_foreign_key "user_roles", "users"
  add_foreign_key "users", "people"
end
