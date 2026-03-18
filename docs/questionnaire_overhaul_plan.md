# Questionnaire Overhaul + Cocobase Removal

Replace Cocobases with enhanced Questionnaires. Add file_upload + url question types (with audio/image/YouTube/Spotify support from Cocobases), remove availability section, add course integration via FK, build Google Forms-style table response viewer, and delete all Cocobase code.

---

## Phase 1: Delete All Cocobase Code

1. Remove 18 Cocobase routes from `config/routes.rb`
2. Delete 6 model files:
   - `app/models/cocobase.rb`
   - `app/models/cocobase_template.rb`
   - `app/models/cocobase_submission.rb`
   - `app/models/cocobase_answer.rb`
   - `app/models/cocobase_field.rb`
   - `app/models/cocobase_template_field.rb`
3. Delete 6 controller files:
   - `app/controllers/manage/cocobases_controller.rb`
   - `app/controllers/manage/cocobase_templates_controller.rb`
   - `app/controllers/manage/cocobase_fields_controller.rb`
   - `app/controllers/manage/cocobase_template_fields_controller.rb`
   - `app/controllers/manage/cocobase_submissions_controller.rb`
   - `app/controllers/my/cocobase_submissions_controller.rb`
4. Delete 4 view directories:
   - `app/views/manage/cocobases/`
   - `app/views/manage/cocobase_templates/`
   - `app/views/manage/cocobase_submissions/`
   - `app/views/my/cocobase_submissions/`
5. Delete service + job:
   - `app/services/cocobase_service.rb`
   - `app/jobs/cocobase_deadline_job.rb`
6. Remove Cocobase references from other files:
   - `app/models/show.rb` — Remove `has_one :cocobase`, `after_commit :generate_cocobase`, `after_commit :update_cocobase_deadline`, and the `generate_cocobase` / `update_cocobase_deadline` methods
   - `app/models/production.rb` — Remove `has_one :cocobase_template`
   - `app/controllers/my/open_requests_controller.rb` — Remove `load_cocobases_data` method and call
   - `app/views/my/open_requests/index.html.erb` — Remove Cocobases section
   - `app/views/shared/navigation/_manage.html.erb` — Remove cocobase_templates reference
   - `config/recurring.yml` — Remove cocobase_deadline job entry
7. Migration to drop 6 Cocobase tables:
   - `cocobase_templates`
   - `cocobase_template_fields`
   - `cocobases`
   - `cocobase_fields`
   - `cocobase_submissions`
   - `cocobase_answers`

---

## Phase 2: Remove Availability from Questionnaires

1. Migration to remove columns from `questionnaires` table:
   - `include_availability_section`
   - `require_all_availability`
   - `availability_show_ids`
2. Update `app/models/questionnaire.rb` — Remove `serialize :availability_show_ids` and availability-related code
3. Update `app/controllers/manage/questionnaires_controller.rb`:
   - Remove availability settings from `form` action
   - Remove availability data loading from `show_response` action
   - Remove availability params from `update` action
4. Update `app/controllers/my/questionnaires_controller.rb`:
   - Remove availability section rendering in `form`
   - Remove availability saving in `submitform`
   - Remove availability validation
5. Update views:
   - `app/views/manage/questionnaires/form.html.erb` — Remove availability configuration UI
   - `app/views/manage/questionnaires/response.html.erb` — Remove availability display
   - `app/views/my/questionnaires/form.html.erb` — Remove availability section from form

---

## Phase 3: Add New Question Types (file_upload, url)

1. Create two new question type classes:
   - `app/models/question_types/file_upload_type.rb` — "File Upload" label, `needs_options? false`
   - `app/models/question_types/url_type.rb` — "URL / Link" label, `needs_options? false`
2. Register new types in `config/initializers/question_types.rb`
3. Update `QuestionnaireAnswer` model (`app/models/questionnaire_answer.rb`):
   - Add `has_one_attached :file` (ActiveStorage)
   - Add file validation (audio: MP3/WAV/AAC/OGG/MP4, image: JPEG/PNG/GIF/WebP, max 25MB)
   - Port media helper methods from `CocobaseAnswer`: `image?`, `audio?`, `youtube_url?`, `spotify_url?`, `youtube_embed_id`, `spotify_embed_uri`
4. Update manage form builder (`app/views/manage/questionnaires/form.html.erb`):
   - Add file_upload + url to the question type dropdown
5. Update manage response viewer (`app/views/manage/questionnaires/response.html.erb`):
   - Render file uploads as images/audio players/download links
   - Render URLs with YouTube/Spotify embed detection
6. Update user-facing form (`app/views/my/questionnaires/form.html.erb`):
   - Add file upload input for file_upload questions
   - Add URL input with preview for url questions
7. Update `app/controllers/my/questionnaires_controller.rb#submitform`:
   - Handle file attachment params for file_upload questions
8. Update `app/controllers/manage/questionnaires_controller.rb#show_response`:
   - Eager-load file attachments

---

## Phase 4: Course-Questionnaire Integration

1. Migration: Add columns to `course_offerings`:
   - `questionnaire_id` (FK, nullable)
   - `delivery_mode` (string — values: "immediate", "delayed", "scheduled", "manual")
   - `delivery_delay_minutes` (integer, for delayed mode)
   - `delivery_scheduled_at` (datetime, for scheduled mode)
2. Update `app/models/course_offering.rb` — Add `belongs_to :questionnaire, optional: true`
3. Update `app/models/questionnaire.rb` — Add `has_many :course_offerings`
4. Course questionnaire auto-creation:
   - When producer enables questionnaire for a course, auto-create a Questionnaire linked to the course's production
   - Set `course_offering.questionnaire_id` to the new questionnaire
5. Update course offering edit view:
   - Toggle questionnaire on/off
   - Configure delivery mode (immediate on registration / delayed / scheduled date / manual)
   - Link to questionnaire form builder for managing questions
6. Delivery logic:
   - **Immediate**: In course registration flow (after successful payment), auto-create `QuestionnaireInvitation` for the registrant and send notification
   - **Delayed**: Enqueue `CourseQuestionnaireDeliveryJob` with configurable delay
   - **Scheduled**: Enqueue job at `delivery_scheduled_at` time
   - **Manual**: Producer triggers bulk send from course page
7. Create `app/jobs/course_questionnaire_delivery_job.rb` — Sends questionnaire invitation to a registrant after delay (idempotent: checks if invitation already exists)
8. Add link from course management page to questionnaire management (form builder, responses)

---

## Phase 5: Google Forms-Style Response Table

1. New `responses_table` action in `app/controllers/manage/questionnaires_controller.rb`:
   - Load all responses with answers, eager-loaded
   - Build matrix: rows = respondents, columns = questions
2. Create view `app/views/manage/questionnaires/responses_table.html.erb`:
   - Horizontal scrollable table
   - Column headers = question text (truncated)
   - Row per respondent with name + headshot
   - Cells show answer values (text), thumbnail (image), play button (audio), embed link (URL)
   - Sortable by respondent name or submission date
3. Add route for the table view
4. Link from existing responses page to the table view (or replace it)

---

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Course ↔ Questionnaire link | Direct FK (`questionnaire_id`) on `course_offerings` | Simpler than join table; 1:1 is sufficient for now |
| Assignment model | Reuse existing `QuestionnaireInvitation` | No new model needed; works for all delivery modes |
| New question types | file_upload + url only | yesno already exists in questionnaires |
| Cocobase data | Drop tables immediately | No data migration needed |
| Response summary | Table view only | No charts or CSV export yet |
| Delivery modes | immediate, delayed, scheduled, manual | All four options supported |

---

## Verification Checklist

- [ ] `bundle exec rspec` — all existing specs pass
- [ ] `grep -ri cocobase app/ config/ spec/` — zero remaining references
- [ ] Manual: Create questionnaire with file_upload + url questions, submit responses, view in table
- [ ] Manual: Create course, enable questionnaire, register student, verify all delivery modes
- [ ] Manual: Verify `/my/open_requests` no longer shows cocobase section
- [ ] Manual: Verify cocobase routes return 404 (removed)

---

## Future Considerations

- **File storage costs**: Audio uploads up to 25MB could grow storage fast. Consider per-questionnaire or per-org storage quota later.
- **Delivery job reliability**: Delayed/scheduled delivery jobs should be idempotent — check if invitation already exists before creating duplicates on retry.
- **Future extensibility**: The `questionnaire_id` FK pattern on `course_offerings` can be replicated on `shows`, `sign_up_forms`, or `audition_cycles` to link questionnaires to other entities.
