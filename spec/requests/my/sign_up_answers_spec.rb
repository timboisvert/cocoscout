# frozen_string_literal: true

require "rails_helper"

# A sign-up form's questions, answered on the sign-up page and kept with the
# registration (after-V1 #1; SignUpAnswers), then shown to producers on the
# roster, the assign queue and the printed list.
RSpec.describe "Sign-up question answers", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: manager) }
  let(:production) { create(:production, organization: org) }
  let(:show) { create(:show, production: production, date_and_time: 3.days.from_now.change(hour: 19, min: 30)) }
  let(:form) { create(:sign_up_form, :with_short_code, production: production, show: show) }
  let(:instance) { create(:sign_up_form_instance, sign_up_form: form, show: show) }
  let!(:slot) { create(:sign_up_slot, sign_up_form: form, sign_up_form_instance: instance, position: 1) }

  let!(:act) { create(:question, questionable: form, text: "What will you perform?", question_type: "text", required: true, position: 1) }
  let!(:needs) do
    build(:question, questionable: form, text: "What do you need?", question_type: "multiple-multiple", position: 2).tap do |question|
      %w[Mic Piano Stool].each { |text| question.question_options.build(text: text) }
      question.save!
    end
  end
  let!(:first_time) { create(:question, questionable: form, text: "First time here?", question_type: "yesno", position: 3) }
  let!(:track) { create(:question, questionable: form, text: "Backing track", question_type: "file_upload", position: 4) }

  def sign_in(user)
    post handle_signin_path, params: { email_address: user.email_address, password: user.password }
  end

  def track_file
    Rack::Test::UploadedFile.new(StringIO.new("ID3 fake mp3"), "audio/mpeg", original_filename: "track.mp3")
  end

  it "asks the form's questions on the sign-up page, ahead of the slots" do
    get my_sign_up_form_path(form.short_code)
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("What will you perform?", "What do you need?", "First time here?", "Backing track",
                            'id="sign-up-details"', "data-required-answer")
    expect(body.index("What will you perform?")).to be < body.index("data-sign-up-confirmation-target=\"slotList\"")
  end

  it "saves a guest's name and answers, file too, with their registration" do
    expect {
      post my_submit_sign_up_form_path(form.short_code, instance_id: instance.id), params: {
        slot_id: slot.id, guest_name: "Kim Possible", guest_email: "kim@example.com",
        question: { act.id.to_s => "Juggling", needs.id.to_s => { "Mic" => "Mic", "Piano" => "" }, first_time.id.to_s => "yes" },
        file_upload: { track.id.to_s => track_file }
      }
    }.to change(SignUpRegistration, :count).by(1)
    expect(response).to redirect_to(my_sign_up_success_path(form.short_code))

    registration = SignUpRegistration.last
    expect(registration.guest_name).to eq("Kim Possible")
    answers = registration.answers.includes(:question).index_by(&:question)
    expect(answers[act].value).to eq("Juggling")
    expect(answers[needs].value_as_array).to eq([ "Mic" ])
    expect(answers[first_time].value).to eq("yes")
    expect(answers[track].file).to be_attached
    expect(answers[track].audition_request).to be_nil
    expect(StorageKeyGeneratorService.generate_key_for_attachment(answers[track].file.attachment))
      .to start_with("organizations/#{org.id}/sign_up_forms/#{form.id}/registrations/#{registration.id}/answers/")
  end

  it "registers nobody while a required question is blank, and says which" do
    expect {
      post my_submit_sign_up_form_path(form.short_code, instance_id: instance.id), params: {
        slot_id: slot.id, guest_name: "Kim Possible", question: { act.id.to_s => " " }
      }
    }.not_to change(SignUpRegistration, :count)
    expect(response).to redirect_to(my_sign_up_form_path(form.short_code, instance_id: instance.id))
    expect(flash[:alert]).to eq("Please answer: What will you perform?")
  end

  it "registers nobody when a file isn't one we take" do
    bad = Rack::Test::UploadedFile.new(StringIO.new("MZ"), "application/x-msdownload", original_filename: "track.exe")
    expect {
      post my_submit_sign_up_form_path(form.short_code, instance_id: instance.id), params: {
        slot_id: slot.id, guest_name: "Kim Possible", question: { act.id.to_s => "Juggling" }, file_upload: { track.id.to_s => bad }
      }
    }.not_to change(SignUpRegistration, :count)
    expect(flash[:alert]).to start_with("Backing track: File must be")
  end

  it "signs a signed-in person up as themselves on a form that doesn't require signing in" do
    person_user = create(:user, password: password)
    sign_in(person_user)

    get my_sign_up_form_path(form.short_code)
    expect(response.body).to include("Signing up as:")
    expect(response.body).not_to include('id="guest_name"')

    post my_submit_sign_up_form_path(form.short_code, instance_id: instance.id), params: { slot_id: slot.id, question: { act.id.to_s => "Poetry" } }
    expect(response).to redirect_to(my_sign_up_success_path(form.short_code))
    expect(SignUpRegistration.last).to have_attributes(person: person_user.person, guest_name: nil)
  end

  it "saves answers for someone joining the queue" do
    form.update!(slot_selection_mode: "admin_assigns")
    person_user = create(:user, password: password)
    sign_in(person_user)

    post my_submit_sign_up_form_path(form.short_code, instance_id: instance.id), params: { question: { act.id.to_s => "Stand-up" } }
    registration = SignUpRegistration.find_by!(person: person_user.person)
    expect(registration).to be_queued
    expect(registration.answers.map(&:value)).to eq([ "Stand-up" ])
  end

  describe "for producers" do
    let!(:registration) { slot.register!(guest_name: "Kim Possible") }

    before do
      registration.answers.create!(question: act, value: "Juggling")
      registration.answers.create!(question: needs, value: { "Mic" => "Mic", "Stool" => "Stool" }.to_json)
      create(:organization_role, :manager, user: manager, organization: org)
      sign_in(manager)
      get manage_path
    end

    it "brings back the Questions tab" do
      get manage_edit_signups_form_path(production, form)
      expect(response.body).to include(">Questions</button>", "What will you perform?")
    end

    it "folds each person's answers under their name on the roster" do
      get manage_signups_form_path(production, form)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Kim Possible", "2 answers", "What will you perform?", "Juggling", "What do you need?")
    end

    it "prints them a line each under the name" do
      get manage_print_list_signups_form_path(production, form)
      expect(response).to have_http_status(:ok)
      html = response.body.gsub(/\s+/, " ")
      expect(html).to include("What will you perform?</span> Juggling", "What do you need?</span> Mic, Stool")
    end

    it "shows a queued person's answers where they get assigned" do
      form.update!(slot_selection_mode: "admin_assigns")
      queued = instance.register_to_queue!(guest_name: "Ron Stoppable")
      queued.answers.create!(question: act, value: "Magic")

      get manage_assign_signups_form_path(production, form, instance_id: instance.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ron Stoppable", "1 answer", "Magic")
    end
  end
end
