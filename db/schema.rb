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

ActiveRecord::Schema[8.0].define(version: 2025_09_19_130000) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "answers", force: :cascade do |t|
    t.integer "question_id", null: false
    t.integer "audition_request_id", null: false
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["audition_request_id"], name: "index_answers_on_audition_request_id"
    t.index ["question_id"], name: "index_answers_on_question_id"
  end

  create_table "audition_requests", force: :cascade do |t|
    t.integer "call_to_audition_id", null: false
    t.integer "person_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 0
    t.index ["call_to_audition_id"], name: "index_audition_requests_on_call_to_audition_id"
    t.index ["person_id"], name: "index_audition_requests_on_person_id"
  end

  create_table "audition_sessions", force: :cascade do |t|
    t.integer "production_id", null: false
    t.datetime "start_at"
    t.datetime "end_at"
    t.integer "maximum_auditionees"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id"], name: "index_audition_sessions_on_production_id"
  end

  create_table "audition_sessions_auditions", id: false, force: :cascade do |t|
    t.integer "audition_session_id", null: false
    t.integer "audition_id", null: false
    t.index ["audition_id", "audition_session_id"], name: "idx_on_audition_id_audition_session_id_8976785be4"
    t.index ["audition_id"], name: "index_audition_sessions_auditions_on_audition_id"
    t.index ["audition_session_id", "audition_id"], name: "idx_on_audition_session_id_audition_id_25fccc3f8f"
    t.index ["audition_session_id"], name: "index_audition_sessions_auditions_on_audition_session_id"
  end

  create_table "auditions", force: :cascade do |t|
    t.integer "person_id", null: false
    t.integer "audition_request_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["audition_request_id"], name: "index_auditions_on_audition_request_id"
    t.index ["person_id"], name: "index_auditions_on_person_id"
  end

  create_table "call_to_auditions", force: :cascade do |t|
    t.integer "production_id", null: false
    t.datetime "opens_at"
    t.datetime "closes_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "hex_code"
    t.text "header_text"
    t.text "success_text"
    t.index ["production_id"], name: "index_call_to_auditions_on_production_id"
  end

  create_table "casts", force: :cascade do |t|
    t.integer "production_id", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id"], name: "index_casts_on_production_id"
  end

  create_table "casts_people", id: false, force: :cascade do |t|
    t.integer "cast_id"
    t.integer "person_id"
    t.index ["cast_id"], name: "index_casts_people_on_cast_id"
    t.index ["person_id"], name: "index_casts_people_on_person_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.integer "production_company_id", null: false
    t.string "email", null: false
    t.string "token", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["production_company_id"], name: "index_invitations_on_production_company_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "notify_mes", force: :cascade do |t|
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "people", force: :cascade do |t|
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "stage_name"
    t.string "pronouns"
    t.string "socials"
    t.integer "user_id"
    t.index ["user_id"], name: "index_people_on_user_id"
  end

  create_table "posters", force: :cascade do |t|
    t.string "name"
    t.integer "production_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id"], name: "index_posters_on_production_id"
  end

  create_table "production_companies", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "productions", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "production_company_id", null: false
    t.index ["production_company_id"], name: "index_productions_on_production_company_id"
  end

  create_table "question_options", force: :cascade do |t|
    t.integer "question_id", null: false
    t.string "text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["question_id"], name: "index_question_options_on_question_id"
  end

  create_table "questions", force: :cascade do |t|
    t.string "text"
    t.string "question_type"
    t.string "questionable_type", null: false
    t.integer "questionable_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["questionable_type", "questionable_id"], name: "index_questions_on_questionable"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "production_id", null: false
    t.index ["production_id"], name: "index_roles_on_production_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "show_person_role_assignments", force: :cascade do |t|
    t.integer "show_id", null: false
    t.integer "person_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "role_id", null: false
    t.index ["person_id"], name: "index_show_person_role_assignments_on_person_id"
    t.index ["role_id"], name: "index_show_person_role_assignments_on_role_id"
    t.index ["show_id"], name: "index_show_person_role_assignments_on_show_id"
  end

  create_table "shows", force: :cascade do |t|
    t.string "secondary_name"
    t.datetime "date_and_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "production_id", null: false
    t.index ["production_id"], name: "index_shows_on_production_id"
  end

  create_table "user_roles", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "production_company_id", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["production_company_id"], name: "index_user_roles_on_production_company_id"
    t.index ["user_id", "production_company_id"], name: "index_user_roles_on_user_id_and_production_company_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "person_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["person_id"], name: "index_users_on_person_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "answers", "audition_requests"
  add_foreign_key "answers", "questions"
  add_foreign_key "audition_requests", "call_to_auditions"
  add_foreign_key "audition_requests", "people"
  add_foreign_key "audition_sessions", "productions"
  add_foreign_key "audition_sessions_auditions", "audition_sessions"
  add_foreign_key "audition_sessions_auditions", "auditions"
  add_foreign_key "auditions", "audition_requests"
  add_foreign_key "auditions", "people"
  add_foreign_key "call_to_auditions", "productions"
  add_foreign_key "casts", "productions"
  add_foreign_key "invitations", "production_companies"
  add_foreign_key "people", "users"
  add_foreign_key "posters", "productions"
  add_foreign_key "productions", "production_companies"
  add_foreign_key "question_options", "questions"
  add_foreign_key "roles", "productions"
  add_foreign_key "sessions", "users"
  add_foreign_key "show_person_role_assignments", "people"
  add_foreign_key "show_person_role_assignments", "roles"
  add_foreign_key "show_person_role_assignments", "shows"
  add_foreign_key "shows", "productions"
  add_foreign_key "user_roles", "production_companies"
  add_foreign_key "user_roles", "users"
  add_foreign_key "users", "people"
end
