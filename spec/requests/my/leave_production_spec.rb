# frozen_string_literal: true

require "rails_helper"

# Leaving a production's talent pool from My. It named a route that no longer
# exists for the link in the managers' notice, so a person who left got an
# error page and no manager was told (Sentry COCOSCOUT-78, 2026-11-14).
RSpec.describe "Leaving a production's talent pool", type: :request do
  let(:password) { "Password123!" }
  let(:user) { create(:user, password: password) }
  let!(:person) { create(:person, user: user).tap { |p| user.update!(default_person: p) } }
  let(:production) { create(:production) }
  let(:manager) { create(:user) }
  let!(:manager_person) { create(:person, user: manager).tap { |p| manager.update!(default_person: p) } }

  before do
    TalentPoolMembership.create!(talent_pool: production.effective_talent_pool, member: person)
    post handle_signin_path, params: { email_address: user.email_address, password: password }
  end

  it "takes them out of the pool and notifies managers with a link to the talent pool" do
    allow(ProductionNotificationSetting).to receive(:users_to_notify).with(production).and_return([ manager ])
    allow(ContentTemplateService).to receive(:render).and_call_original
    allow(MessageService).to receive(:send_direct)

    delete my_leave_production_path(production)

    expect(response).to redirect_to(my_productions_path)
    expect(TalentPoolMembership.where(talent_pool: production.effective_talent_pool, member: person)).not_to exist
    expect(ContentTemplateService).to have_received(:render).with(
      "talent_left_production",
      hash_including(talent_pool_url: a_string_ending_with("/manage/casting/#{production.id}/talent-pools"))
    )
    expect(MessageService).to have_received(:send_direct).with(hash_including(recipient_person: manager.person))
  end
end
