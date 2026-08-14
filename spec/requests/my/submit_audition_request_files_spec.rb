# frozen_string_literal: true

require "rails_helper"

RSpec.describe "My::SubmitAuditionRequest file uploads", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user, email: user.email_address) }
  let(:production) { create(:production) }
  let(:cycle) { create(:audition_cycle, production: production, form_reviewed: true, token: "FILETOKEN123") }
  let!(:file_question) do
    create(:question, questionable: cycle, question_type: "file_upload", text: "Upload your resume", required: true)
  end

  before { post handle_signin_path, params: { email_address: user.email_address, password: password } }

  it "stores an uploaded document on the answer, filed under the hierarchical key" do
    pdf = fixture_file_upload("test_document.pdf", "application/pdf")

    post my_submit_submit_audition_request_form_path(token: cycle.token),
         params: { file_upload: { file_question.id.to_s => pdf } }

    expect(response).to redirect_to(my_submit_audition_request_success_path(token: cycle.token))

    answer = AuditionRequest.last.answers.find_by(question: file_question)
    expect(answer.file).to be_attached
    expect(answer.file.content_type).to eq("application/pdf")
    expect(answer.value).to eq("test_document.pdf")
    expect(answer.file.blob.key).to start_with(
      "organizations/#{production.organization_id}/productions/#{production.id}/audition_cycles/#{cycle.id}/"
    )
  end

  it "keeps the earlier file when resubmitting without a new upload" do
    post my_submit_submit_audition_request_form_path(token: cycle.token),
         params: { file_upload: { file_question.id.to_s => fixture_file_upload("test_document.pdf", "application/pdf") } }

    expect {
      post my_submit_submit_audition_request_form_path(token: cycle.token), params: { question: {} }
    }.not_to change(AuditionRequest, :count)

    expect(response).to redirect_to(my_submit_audition_request_success_path(token: cycle.token))
    answer = AuditionRequest.last.answers.find_by(question: file_question)
    expect(answer.file).to be_attached
  end

  it "blocks submission when a required file question has no upload" do
    expect {
      post my_submit_submit_audition_request_form_path(token: cycle.token), params: {}
    }.not_to change(AuditionRequest, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end
end
