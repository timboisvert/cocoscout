# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Manage::People::EmailLogs', type: :request do
  let!(:organization) { create(:organization) }
  let!(:user) { create(:user) }
  let!(:person) { create(:person) }

  before do
    # Associate person with organization
    person.organizations << organization unless person.organizations.include?(organization)
    
    # Sign in user and set current organization
    sign_in user
    allow_any_instance_of(ApplicationController).to receive(:Current).and_return(
      OpenStruct.new(user: user, organization: organization)
    )
  end

  describe 'GET /manage/people/:person_id/email_logs' do
    let!(:email_log1) do
      create(:email_log,
             user: user,
             recipient: person.email,
             recipient_type: 'Person',
             recipient_id: person.id,
             subject: 'Test Email 1',
             sent_at: 2.days.ago)
    end

    let!(:email_log2) do
      create(:email_log,
             user: user,
             recipient: person.email,
             recipient_type: 'Person',
             recipient_id: person.id,
             subject: 'Test Email 2',
             sent_at: 1.day.ago)
    end

    it 'displays email logs for the person' do
      get "/manage/people/#{person.id}/email_logs"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Test Email 1')
      expect(response.body).to include('Test Email 2')
    end

    it 'filters email logs by search term' do
      get "/manage/people/#{person.id}/email_logs", params: { search: 'Test Email 1' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Test Email 1')
      expect(response.body).not_to include('Test Email 2')
    end
  end

  describe 'GET /manage/people/:person_id/email_logs/:id' do
    let!(:email_log) do
      create(:email_log,
             user: user,
             recipient: person.email,
             recipient_type: 'Person',
             recipient_id: person.id,
             subject: 'Test Email',
             body: '<p>This is the email body</p>',
             sent_at: 1.day.ago)
    end

    it 'displays the email log details' do
      get "/manage/people/#{person.id}/email_logs/#{email_log.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Test Email')
      expect(response.body).to include('This is the email body')
    end
  end
end
