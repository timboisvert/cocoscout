# frozen_string_literal: true

require "rails_helper"

# V1.1 plan Phase 2, sign-up assign on a phone: tap someone in the queue,
# then pick their slot from a sheet (drag stays for a mouse); the queue
# comes first; Auto-assign All pins to the bottom; Add to Queue is the shared People Picker.
RSpec.describe "Sign-up assign on a phone", type: :request do
  let(:password) { "Password123!" }
  let(:manager) { create(:user, password: password) }
  let(:org) { create(:organization, :pro, owner: manager) }
  let(:production) { create(:production, organization: org) }
  let(:show) { create(:show, production: production, date_and_time: 3.days.from_now.change(hour: 19, min: 30)) }
  let(:form) { create(:sign_up_form, production: production, show: show, slot_selection_mode: "admin_assigns", slot_generation_mode: "numbered") }
  let(:instance) { create(:sign_up_form_instance, sign_up_form: form, show: show) }
  let!(:slot_one) { create(:sign_up_slot, sign_up_form: form, sign_up_form_instance: instance, position: 1) }
  let!(:slot_two) { create(:sign_up_slot, sign_up_form: form, sign_up_form_instance: instance, position: 2, capacity: 2) }
  let!(:held) { create(:sign_up_slot, :held, sign_up_form: form, sign_up_form_instance: instance, position: 3) }
  let(:placed) { create(:person, name: "Placed Pat") }
  let(:waiting) { create(:person, name: "Waiting Wren") }
  let!(:on_one) { create(:sign_up_registration, person: placed, sign_up_slot: slot_one, sign_up_form_instance: instance) }
  let!(:queued) { create(:sign_up_registration, :queued, person: waiting, sign_up_form_instance: instance) }

  before do
    create(:organization_role, :manager, user: manager, organization: org)
    post handle_signin_path, params: { email_address: manager.email_address, password: password }
    get manage_assign_signups_form_path(production, form, instance_id: instance.id)
    expect(response).to have_http_status(:ok)
  end

  let(:doc) { Nokogiri::HTML(response.body) }

  it "puts the queue first and gives each queued person a Pick a slot button" do
    queue = doc.at_css("[data-assign-queue-panel]")
    expect(queue["class"]).to include("order-first lg:order-none")
    pick = queue.css("button").find { |b| b.text.include?("Pick a slot") }
    expect(pick["data-action"]).to eq("click->assign-drag#openPicker")
    expect(pick["data-registration-id"]).to eq(queued.id.to_s)
    expect(pick["data-name"]).to eq("Waiting Wren")
  end

  it "lets a placed person move, naming the slot they're in" do
    move = doc.css("button").find { |b| b.text.include?("Move") && b["data-registration-id"] == on_one.id.to_s }
    expect(move["data-current-slot-id"]).to eq(slot_one.id.to_s)
  end

  it "has a slot picker sheet listing only slots with room, by id and free count" do
    sheet = doc.at_css("#slot-picker")
    expect(sheet.has_attribute?("data-sheet")).to be(true)
    buttons = sheet.css("button[data-assign-drag-target='pickSlot']")
    by_id = buttons.to_h { |b| [ b["data-slot-id"], b ] }
    expect(by_id[slot_one.id.to_s]["data-free"]).to eq("0")
    expect(by_id[slot_one.id.to_s]["class"]).to include("hidden")
    expect(by_id[slot_two.id.to_s]["data-free"]).to eq("2")
    expect(by_id[slot_two.id.to_s].text).to include("Slot 2", "2 of 2 free")
    expect(by_id[held.id.to_s]["data-free"]).to eq("0")
  end

  it "pins Auto-assign All to the bottom while someone's waiting, and opens Add to Queue as a sheet" do
    bar = doc.at_css("[data-assign-phone-bar]")
    expect(bar.text).to include("1 person waiting", "Auto-assign All")
    expect(bar.at_css("a, button")["href"] || bar.at_css("form")["action"]).to include("auto_assign_queue")
    expect(doc.at_css("[data-people-picker='sign-up-picker'] [data-sheet]")).to be_present # the shared People Picker
  end
end
